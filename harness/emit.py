"""Complete RTL export and state-preserving whole-design equivalence.

M1 proves every output and every state D/control function with all source Q
bits unconstrained. State correspondence and initial values are checked
separately. No internal-name matching, induction assumption, async2sync, or
X-as-don't-care is used. The current admission contract is single-clock,
2-state combinational logic with dff/adff/dffe/adffe state.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import re
import signal
import subprocess
import tempfile
import time
from pathlib import Path

from .ir import SourceGraph, save_json
from .recovery import RecoveryRevision
from .state import require_supported_state


def _yosys_path(yosys: str | None) -> str:
    return yosys or os.environ.get("YOSYS") or shutil.which("yosys") or "yosys"


def _q(value: str | Path) -> str:
    text = str(value)
    if any(c in text for c in "\n\r\x00"):
        raise ValueError("newline/NUL in tool path or identifier")
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def _file_hash(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _tool_identity(command: str) -> dict:
    resolved = shutil.which(command)
    if resolved is None:
        raise FileNotFoundError(f"executable unavailable: {command}")
    path = Path(resolved).resolve()
    identity = {"path": str(path), "sha256": _file_hash(path), "invoked_as": command}
    # OSS CAD distributes executable shell entrypoints. Bind the known target
    # binary as well; this is not a claim to hash all dynamic dependencies.
    with path.open("rb") as stream:
        header = stream.read(4096)
    marker = ('/libexec/' + path.name + ' "$@"').encode()
    binary = path.parent.parent / "libexec" / path.name
    if header.startswith(b"#!") and marker in header:
        if not binary.is_file():
            raise FileNotFoundError(f"missing tool wrapper target: {binary}")
        identity["delegated_executable"] = {"path": str(binary.resolve()), "sha256": _file_hash(binary)}
    return identity


def _run(args: list[str], root: Path, label: str, deadline: float, records: list | None = None) -> str:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("whole-design verification time budget exhausted")
    record = {"label": label, "argv": args, "cwd": str(root), "timeout_s": remaining,
              "returncode": None, "status": "starting", "log": f"{label}.log"}
    if records is not None:
        records.append(record)
    start = time.monotonic()
    try:
        proc = subprocess.Popen(args, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, start_new_session=True)
        try:
            stdout, stderr = proc.communicate(timeout=remaining)
            log = stdout + stderr
        except subprocess.TimeoutExpired as exc:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = proc.communicate()
            (root / f"{label}.log").write_text(stdout + stderr)
            record.update({"returncode": proc.returncode, "status": "timeout"})
            raise TimeoutError(f"{label} timed out") from exc
        (root / f"{label}.log").write_text(log)
        record.update({"returncode": proc.returncode, "status": "finished"})
        if proc.returncode:
            raise RuntimeError(f"{label} exited {proc.returncode}: {log[-2000:]}")
        return log
    except OSError as exc:
        record.update({"status": "launch_error", "reason": str(exc)})
        raise
    finally:
        record["elapsed_s"] = time.monotonic() - start


def _admit(graph: SourceGraph):
    if hasattr(graph, "assert_integrity"):
        graph.assert_integrity()
    if hasattr(graph, "validate"):
        errors = graph.validate()
        if errors:
            raise ValueError("invalid source graph: " + "; ".join(errors[:10]))
    mod = graph.module()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", graph.top):
        raise ValueError("unsupported top identifier")
    if len(graph.data["modules"]) != 1 or mod.get("memories"):
        raise ValueError("requires a flattened single module without memories")
    if mod.get("attributes", {}).get("blackbox"):
        raise ValueError("blackbox module is not an implementation")
    ports = mod.get("ports", {})
    if not ports or not any(p["direction"] == "output" and p["bits"] for p in ports.values()):
        raise ValueError("requires nonempty output interface")
    for p in ports.values():
        if p["direction"] not in {"input", "output"} or not p["bits"]:
            raise ValueError("empty/inout interface unsupported")
    # X initial state is supported; X/Z in logic itself is not a Boolean model.
    for obj in list(ports.values()) + list(mod.get("netnames", {}).values()):
        if any(b in ("x", "z") for b in obj.get("bits", [])):
            raise ValueError("X/Z logic unsupported")
    for c in mod.get("cells", {}).values():
        if any(b in ("x", "z") for bits in c["connections"].values() for b in bits):
            raise ValueError("X/Z logic unsupported")
        if not c["type"].startswith("$"):
            raise ValueError("unmodeled technology cell/blackbox")
    model = require_supported_state(graph)
    pi = {b for p in ports.values() if p["direction"] == "input" for b in p["bits"]}
    clocks = {(e.clock_bits, e.clock_polarity) for e in model.elements}
    if len(clocks) > 1:
        raise ValueError("M1 requires one clock domain and edge")
    for e in model.elements:
        if len(e.clock_bits) != 1 or e.clock_bits[0] not in pi:
            raise ValueError("M1 clock must be a direct primary input")
        if e.reset_bits and (len(e.reset_bits) != 1 or e.reset_bits[0] not in pi):
            raise ValueError("M1 asynchronous reset must be a direct primary input")
    return model


def _alias(source: SourceGraph, bit: int) -> str:
    return f"__harness_q_{source.source_hash[:16]}_{bit}"


def _marked_data(source: SourceGraph, implementation: SourceGraph) -> dict:
    data = implementation.data
    nets = data["modules"][implementation.top].setdefault("netnames", {})
    for e in _admit(source).elements:
        for bit in e.q_bits:
            name = _alias(source, bit)
            if name in nets:
                raise ValueError("reserved state provenance alias collision")
            nets[name] = {"hide_name": 0, "bits": [bit], "attributes": {"keep": "1"}}
    return data


def _emit(revision: RecoveryRevision, implementation: SourceGraph, directory: str | Path,
          yosys: str | None, timeout_s: float, recovered: bool) -> Path:
    _admit(implementation)
    out = Path(directory).resolve(); out.mkdir(parents=True, exist_ok=True)
    save_json(out / "source_graph.json", _marked_data(revision.graph, implementation))
    rtl = out / "residual.v"
    script = (f"read_json source_graph.json; hierarchy -check -top {implementation.top}; "
              "check -assert; write_verilog -noattr residual.v")
    (out / "emit.ys").write_text(script + "\n")
    _run([_yosys_path(yosys), "-s", "emit.ys"], out, "emit", time.monotonic() + timeout_s)
    if not rtl.is_file() or not rtl.stat().st_size:
        raise RuntimeError("Yosys emitted no residual RTL")
    manifest = revision.residual_manifest()
    manifest.update({"emitted_rtl": True, "verification_scope": "source_graph_export_pending_check",
                     "rtl": str(rtl), "rtl_sha256": hashlib.sha256(rtl.read_bytes()).hexdigest(),
                     "semantic_replacements_emitted": recovered,
                     "implementation_hash": implementation.source_hash})
    if recovered:
        owned = {cell for c in revision.accepted for cell in set(c.region_cells) - set(c.retained_cells)}
        manifest.update({"replaced_cells": len(owned),
                         "residual_cells": len(revision.graph.module().get("cells", {})) - len(owned)})
    manifest["implementation_cells"] = len(implementation.module().get("cells", {}))
    save_json(out / "manifest.json", manifest)
    return rtl


def emit_residual(revision: RecoveryRevision, directory: str | Path, *, yosys: str | None = None,
                  timeout_s: float = 60.0) -> Path:
    """Export the complete original residual, preserving widths/events/init."""
    return _emit(revision, revision.graph, directory, yosys, timeout_s, False)


def emit_recovered(revision: RecoveryRevision, directory: str | Path, *, yosys: str | None = None,
                   timeout_s: float = 60.0) -> Path:
    """Export the proof-gated implementation, keeping original state identities."""
    return _emit(revision, revision.implementation_graph(), directory, yosys, timeout_s, True)


def _cut_state(graph: SourceGraph, source: SourceGraph) -> tuple[dict, dict]:
    """Build complete combinational F/G interface using explicit Q provenance."""
    model = _admit(graph)
    mod = graph.module()
    expected = [b for e in _admit(source).elements for b in e.q_bits]
    q_to_id = {}
    for bit in expected:
        alias = mod.get("netnames", {}).get(_alias(source, bit), {}).get("bits", [])
        if len(alias) != 1 or not isinstance(alias[0], int) or alias[0] in q_to_id:
            raise ValueError("missing/ambiguous state provenance alias")
        q_to_id[alias[0]] = bit
    actual_q = [q for e in model.elements for q in e.q_bits]
    if len(actual_q) != len(set(actual_q)) or set(actual_q) != set(q_to_id):
        raise ValueError("state correspondence is not a complete bijection")
    original_ports = mod["ports"]
    # Stable generated port names avoid collisions with arbitrary source names.
    ports = {}
    io_contract = []
    for i, (name, p) in enumerate(sorted(original_ports.items())):
        io_contract.append((name, p["direction"], len(p["bits"]), p.get("offset", 0), p.get("upto", 0), p.get("signed", 0)))
        ports[f"p{i}"] = {"direction": p["direction"], "bits": p["bits"]}
    states = {}
    for e in model.elements:
        if e.kind not in {"$dff", "$adff"}:
            raise ValueError("normalization did not lower enables to D muxes")
        if len(e.initial_value) != len(e.q_bits):
            raise ValueError("state initial-value vector is incomplete")
        for i, q in enumerate(e.q_bits):
            sid = q_to_id[q]
            states[str(sid)] = {"kind": e.kind, "clock_polarity": e.clock_polarity,
                                "reset_polarity": e.reset_polarity,
                                "reset_value": e.reset_value[i] if e.reset_value else None,
                                "initial_value": e.initial_value[i]}
            ports[f"q{sid}"] = {"direction": "input", "bits": [q]}
            ports[f"d{sid}"] = {"direction": "output", "bits": [e.d_bits[i]]}
            ports[f"clk{sid}"] = {"direction": "output", "bits": list(e.clock_bits)}
            if e.reset_bits:
                ports[f"rst{sid}"] = {"direction": "output", "bits": list(e.reset_bits)}
        del mod["cells"][e.cell]
    mod["ports"] = dict(sorted(ports.items()))
    # Init has been checked explicitly and must not constrain free Q inputs.
    for net in mod.get("netnames", {}).values():
        net.get("attributes", {}).pop("init", None)
    return {"modules": {"top": mod}}, {"ports": io_contract, "states": states}


def verify_residual_export(revision: RecoveryRevision, rtl: str | Path, *, yosys: str | None = None,
                           timeout_s: float = 60.0, artifact_dir: str | Path | None = None) -> tuple[bool, str]:
    """Fail-closed F/G proof of the actual exported RTL against the source.

    Artifacts, scripts, hashes, and a classified verdict persist on every path.
    This is a state-preserving two-state proof, not arbitrary state recoding SEC.
    """
    root = Path(artifact_dir).resolve() if artifact_dir else Path(tempfile.mkdtemp(prefix="residual_cec_"))
    root.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + timeout_s
    result = {"schema": "whole-design-proof/1", "status": "model_error", "proven": False,
              "source_hash": revision.graph.source_hash, "scope": "all_outputs_and_all_state_functions",
              "semantics": "single_clock_state_preserving_two_state", "artifact_dir": str(root),
              "evidence_kind": "trusted_tool_execution_not_certificate", "tools": {}, "processes": [],
              "tool_identity_scope": "entrypoint_and_known_wrapper_binary_not_dynamic_dependencies"}
    logs = []
    try:
        _admit(revision.graph)
        rtl = Path(rtl).resolve()
        # Bind the proof to an immutable snapshot; caller edits cannot race import.
        snapshot = rtl.read_bytes(); (root / "candidate.v").write_bytes(snapshot)
        result["rtl_sha256"] = hashlib.sha256(snapshot).hexdigest()
        save_json(root / "source_graph.json", _marked_data(revision.graph, revision.graph))
        if time.monotonic() >= deadline:
            raise TimeoutError("whole-design verification time budget exhausted")
        yidentity = _tool_identity(_yosys_path(yosys))
        result["tools"]["yosys"] = yidentity
        abc_command = os.environ.get("ABC") or str(Path(yidentity["path"]).with_name("yosys-abc"))
        if not os.environ.get("ABC") and not shutil.which(abc_command):
            abc_command = shutil.which("yosys-abc") or shutil.which("abc") or abc_command
        result["tools"]["abc"] = _tool_identity(abc_command)
        for name, version_args in (("yosys", ["-V"]), ("abc", ["-c", "version"])):
            identity = result["tools"][name]
            identity["version"] = _run([identity["path"], *version_args], root,
                                      f"{name}_version", deadline, result["processes"]).strip()
            if not identity["version"]:
                raise RuntimeError(f"{name} produced an empty version record")
        ypath = result["tools"]["yosys"]["path"]
        for name, reader in (("gold", "read_json source_graph.json"), ("gate", "read_verilog candidate.v")):
            script = (f"{reader}; hierarchy -check -top {revision.graph.top}; proc; dffunmap; "
                      f"check -assert; write_json {name}_normalized.json")
            (root / f"{name}_normalize.ys").write_text(script + "\n")
            logs.append(_run([ypath, "-s", f"{name}_normalize.ys"], root, f"{name}_normalize", deadline, result["processes"]))
        contracts = []
        for name in ("gold", "gate"):
            graph = SourceGraph.from_yosys_json(json.loads((root / f"{name}_normalized.json").read_text()), revision.graph.top)
            cut, contract = _cut_state(graph, revision.graph)
            contracts.append(contract); save_json(root / f"{name}_cut.json", cut)
        save_json(root / "state_contracts.json", {"gold": contracts[0], "gate": contracts[1]})
        if contracts[0] != contracts[1]:
            raise ValueError("interface/state/initial-value/event contract mismatch")
        result["state_bits"] = len(contracts[0]["states"])
        result["output_bits"] = sum(w for _, direction, w, _, _, _ in contracts[0]["ports"] if direction == "output")
        # Full miter: there are no corresponding-internal-net assumptions.
        script = ("read_json gold_cut.json; rename top gold; read_json gate_cut.json; rename top gate; "
                  "miter -equiv -flatten gold gate miter; hierarchy -top miter; check -assert; "
                  "sat -verify -prove trigger 0 -show-inputs -show-outputs")
        (root / "whole_design_sat.ys").write_text(script + "\n")
        result["status"] = "unproven"
        logs.append(_run([ypath, "-s", "whole_design_sat.ys"], root, "whole_design_sat", deadline, result["processes"]))
        # Independent ABC CEC on combinational AIGs (same complete F/G ports).
        for name in ("gold", "gate"):
            script = (f"read_json {name}_cut.json; hierarchy -top top; techmap; opt; "
                      f"aigmap; check -assert; write_aiger -symbols {name}.aig")
            (root / f"{name}_aig.ys").write_text(script + "\n")
            logs.append(_run([ypath, "-s", f"{name}_aig.ys"], root, f"{name}_aig", deadline, result["processes"]))
        abc = result["tools"]["abc"]["path"]
        abc_log = _run([abc, "-c", "cec gold.aig gate.aig"], root, "whole_design_abc", deadline, result["processes"])
        logs.append(abc_log)
        from .proof import _abc_status, ProofStatus
        if _abc_status(abc_log, 0) != ProofStatus.PROVEN:
            raise RuntimeError("ABC did not report equivalence")
        # A tool replaced during the job invalidates its provenance.
        for identity in result["tools"].values():
            for component in [identity] + ([identity["delegated_executable"]] if "delegated_executable" in identity else []):
                if _file_hash(component["path"]) != component["sha256"]:
                    raise RuntimeError("tool executable changed during verification")
        result.update({"status": "proven", "proven": True, "backends": ["yosys_sat", "abc_cec"]})
    except TimeoutError as exc:
        result.update({"status": "timeout", "reason": str(exc)})
        logs.append(str(exc))
    except (ValueError, RuntimeError, OSError, KeyError, TypeError) as exc:
        result["reason"] = str(exc); logs.append(str(exc))
    log = "\n".join(logs)
    (root / "residual_cec.log").write_text(log)
    result["artifacts_sha256"] = {p.name: _file_hash(p) for p in sorted(root.iterdir())
                                  if p.is_file() and p.name != "verification.json"}
    save_json(root / "verification.json", result)
    return result["proven"], log
