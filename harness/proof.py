"""Local two-state proofs with replayable, source-bound execution evidence.

ABC logs are trusted-tool execution evidence, never a SAT proof certificate.
Only scalar AND/OR/XOR/NOT cells (and their Yosys gate primitives) are modeled.
"""
from __future__ import annotations

import hashlib
import itertools
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any


class ProofStatus(str, Enum):
    PROVEN = "proven"
    COUNTEREXAMPLE = "counterexample"
    UNKNOWN = "unknown"
    TIMEOUT = "timeout"
    MODEL_ERROR = "model_error"
    TOOL_ERROR = "tool_error"


@dataclass
class ProofResult:
    status: ProofStatus
    candidate_hash: str
    backend: str
    checked_cases: int = 0
    counterexample: dict[str, int] | None = None
    reason: str = ""
    elapsed_ms: int = 0
    artifact: dict[str, Any] = field(default_factory=dict)
    source_hash: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return {**self.__dict__, "status": self.status.value}


def _json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def _hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _identity(candidate):
    return {k: v for k, v in candidate.canonical().items() if k not in {"status", "proof_id"}}


_OPS = {"$and": "&", "$or": "|", "$xor": "^", "$not": "~",
        "$_AND_": "&", "$_OR_": "|", "$_XOR_": "^", "$_NOT_": "~"}


def _scalar_cell(cell):
    typ = cell.get("type")
    if typ not in _OPS:
        raise ValueError(f"unsupported proof cell {typ}")
    ports = {"A", "Y"} if _OPS[typ] == "~" else {"A", "B", "Y"}
    conns = cell.get("connections", {})
    if set(conns) != ports or any(len(bits) != 1 for bits in conns.values()):
        raise ValueError(f"non-scalar or unsupported ports on {typ}")
    if cell.get("port_directions") != {p: "output" if p == "Y" else "input" for p in ports}:
        raise ValueError(f"invalid port directions on {typ}")
    for key, value in cell.get("parameters", {}).items():
        if key not in {"A_WIDTH", "B_WIDTH", "Y_WIDTH", "A_SIGNED", "B_SIGNED"}:
            raise ValueError(f"unsupported parameter {typ}.{key}")
        parsed = int(value, 2) if isinstance(value, str) else value
        if parsed not in ((1,) if key.endswith("WIDTH") else (0, 1)):
            raise ValueError(f"non-scalar parameter {typ}.{key}")
    return _OPS[typ]


def _drivers(graph, candidate):
    drivers = {}
    cells = graph.module()["cells"]
    for name in candidate.region_cells:
        cell = cells[name]
        _scalar_cell(cell)
        bit = cell["connections"]["Y"][0]
        if type(bit) is not int or bit in drivers:
            raise ValueError("region output is constant or multiply driven")
        drivers[bit] = cell
    return drivers


def _eval_bit(bit, env, memo, visiting, drivers):
    # Yosys JSON constants are strings. Integer zero/one are ordinary wire IDs.
    if isinstance(bit, str):
        if bit not in {"0", "1"}:
            raise ValueError(f"unsupported four-state constant {bit}")
        return int(bit)
    if bit in env:
        return env[bit]
    if bit in memo:
        return memo[bit]
    if bit in visiting:
        raise ValueError(f"combinational loop at bit {bit}")
    if bit not in drivers:
        raise ValueError(f"unbound boundary bit {bit}")
    visiting.add(bit)
    cell = drivers[bit]; op = _scalar_cell(cell)
    def inp(pin):
        return _eval_bit(cell["connections"][pin][0], env, memo, visiting, drivers)
    a = inp("A")
    if op == "~":
        result = 1 - a
    else:
        b = inp("B")
        result = {"&": a & b, "|": a | b, "^": a ^ b}[op]
    visiting.remove(bit); memo[bit] = result
    return result


def _candidate_outputs(candidate, vals):
    if candidate.operation != "full_adder" or len(candidate.input_bits) != 3 or len(candidate.output_bits) != 2 or candidate.parameters:
        raise ValueError("only parameter-free scalar full_adder candidates are supported")
    a, b, cin = (vals[x] for x in candidate.input_bits)
    return (a ^ b ^ cin, (a & b) | (cin & (a ^ b)))


def _new_directory(artifact_dir, prefix):
    if artifact_dir is None:
        return Path(tempfile.mkdtemp(prefix=prefix))
    root = Path(artifact_dir).resolve()
    root.mkdir(parents=True, exist_ok=True)
    if any(root.iterdir()):
        return Path(tempfile.mkdtemp(prefix="attempt_", dir=root))
    return root


def _finish(result, started, directory=None):
    result.elapsed_ms = int((time.monotonic() - started) * 1000)
    if directory:
        result.artifact["dir"] = str(directory)
        result.artifact["files"] = {p.name: _hash(p) for p in sorted(directory.iterdir()) if p.is_file() and p.name != "result.json"}
        (directory / "result.json").write_text(json.dumps(result.as_dict(), sort_keys=True, indent=2) + "\n")
        result.artifact["result_sha256"] = _hash(directory / "result.json")
    return result


def prove_exhaustive(graph, candidate, *, timeout_s=30.0, artifact_dir=None):
    started = time.monotonic()
    result = ProofResult(ProofStatus.MODEL_ERROR, candidate.candidate_hash, "exhaustive", source_hash=graph.source_hash,
                         artifact={"schema": "local-proof/2", "evidence_kind": "exhaustive_truth_table", "truth_table": []})
    directory = _new_directory(artifact_dir, "harness_exhaustive_") if artifact_dir else None
    try:
        errors = candidate.validate(graph)
        if errors: raise ValueError("; ".join(errors))
        drivers = _drivers(graph, candidate)
        _candidate_outputs(candidate, dict.fromkeys(candidate.input_bits, 0))
        for values in itertools.product((0, 1), repeat=len(candidate.input_bits)):
            if time.monotonic() >= started + timeout_s:
                result.status = ProofStatus.TIMEOUT; result.reason = "deadline"; break
            env = dict(zip(candidate.input_bits, values))
            actual = tuple(_eval_bit(bit, env, {}, set(), drivers) for bit in candidate.output_bits)
            expected = _candidate_outputs(candidate, env)
            result.checked_cases += 1
            result.artifact["truth_table"].append({"inputs": list(values), "actual": list(actual), "expected": list(expected)})
            if actual != expected:
                result.status = ProofStatus.COUNTEREXAMPLE
                result.counterexample = {str(bit): value for bit, value in env.items()}
                result.reason = "output mismatch"; break
        else:
            result.status = ProofStatus.PROVEN
    except (ValueError, KeyError, TypeError, RecursionError) as exc:
        result.reason = str(exc)
    if directory:
        (directory / "source.json").write_text(_json(graph.data))
        (directory / "candidate.json").write_text(_json(_identity(candidate)))
        (directory / "truth_table.json").write_text(_json(result.artifact["truth_table"]))
    return _finish(result, started, directory)


def _region_verilog(graph, candidate, *, semantic):
    drivers = _drivers(graph, candidate)
    _candidate_outputs(candidate, dict.fromkeys(candidate.input_bits, 0))
    names = {bit: f"i{i}" for i, bit in enumerate(candidate.input_bits)}
    names.update({bit: f"n{i}" for i, bit in enumerate(drivers)})
    def expr(bit):
        if isinstance(bit, str):
            if bit not in {"0", "1"}: raise ValueError(f"unsupported constant {bit}")
            return "1'b" + bit
        if bit not in names: raise ValueError(f"unbound region bit {bit}")
        return names[bit]
    header = "module top(input i0, input i1, input i2, output sum, output carry);\n"
    if semantic:
        body = "assign sum = i0 ^ i1 ^ i2;\nassign carry = (i0 & i1) | (i2 & (i0 ^ i1));\n"
    else:
        # Validate acyclicity and all dependencies before writing any model.
        for bit in drivers:
            _eval_bit(bit, dict.fromkeys(candidate.input_bits, 0), {}, set(), drivers)
        body = "wire " + ", ".join(names[bit] for bit in drivers) + ";\n"
        for bit, cell in drivers.items():
            op = _scalar_cell(cell); a = expr(cell["connections"]["A"][0])
            rhs = f"~{a}" if op == "~" else f"{a} {op} {expr(cell['connections']['B'][0])}"
            body += f"assign {names[bit]} = {rhs};\n"
        body += f"assign sum = {expr(candidate.output_bits[0])};\nassign carry = {expr(candidate.output_bits[1])};\n"
    return header + body + "endmodule\n"


def _tool(value, env, fallbacks):
    name = value or os.environ.get(env)
    if name:
        resolved = shutil.which(name)
    else:
        resolved = next((p for x in fallbacks if (p := shutil.which(x))), None)
    if not resolved: raise FileNotFoundError(f"{env} executable unavailable; set {env} or PATH")
    return str(Path(resolved).resolve())


def _run(command, directory, stem, deadline, records):
    remaining = deadline - time.monotonic()
    if remaining <= 0: raise subprocess.TimeoutExpired(command, 0)
    record = {"command": command, "stdout": stem + ".stdout", "stderr": stem + ".stderr", "returncode": None, "timeout": False}
    records.append(record)
    with (directory / record["stdout"]).open("wb") as out, (directory / record["stderr"]).open("wb") as err:
        proc = subprocess.Popen(command, cwd=directory, stdout=out, stderr=err, start_new_session=True)
        try:
            proc.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            record["timeout"] = True
            try: os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            proc.wait(); record["returncode"] = proc.returncode
            raise
        record["returncode"] = proc.returncode
    return proc.returncode, (directory / record["stdout"]).read_text(errors="replace") + (directory / record["stderr"]).read_text(errors="replace")


def _abc_status(log, rc):
    if rc != 0: return ProofStatus.TOOL_ERROR
    equivalent = re.search(r"^Networks are equivalent(?: after structural hashing)?\.\s*(?:Time\s*=\s*\d+(?:\.\d+)?\s*sec\.?\s*)?$", log, re.M)
    inequivalent = re.search(r"^Networks are NOT EQUIVALENT\b[^\n]*$", log, re.M)
    if inequivalent: return ProofStatus.COUNTEREXAMPLE
    if equivalent and not re.search(r"\b(?:unknown|undecided|error|failed)\b", log, re.I): return ProofStatus.PROVEN
    return ProofStatus.UNKNOWN


def prove_abc(graph, candidate, *, abc=None, yosys=None, timeout_s=30.0, artifact_dir=None):
    started = time.monotonic(); deadline = started + timeout_s
    directory = _new_directory(artifact_dir, "harness_abc_")
    result = ProofResult(ProofStatus.MODEL_ERROR, candidate.candidate_hash, "abc", source_hash=graph.source_hash,
                         artifact={"schema": "local-proof/2", "evidence_kind": "trusted_tool_execution_not_certificate", "processes": [], "tools": {}})
    try:
        (directory / "source.json").write_text(_json(graph.data))
        (directory / "candidate.json").write_text(_json(_identity(candidate)))
        errors = candidate.validate(graph)
        if errors: raise ValueError("; ".join(errors))
        (directory / "gate.v").write_text(_region_verilog(graph, candidate, semantic=False))
        (directory / "gold.v").write_text(_region_verilog(graph, candidate, semantic=True))
        tools = {"yosys": _tool(yosys, "YOSYS", ["yosys"]), "abc": _tool(abc, "ABC", ["yosys-abc", "abc"])}
        for name, path in tools.items():
            result.artifact["tools"][name] = {"path": path, "sha256": _hash(path)}
            cmd = [path, "-V"] if name == "yosys" else [path, "-c", "version"]
            rc, version = _run(cmd, directory, name + "_version", deadline, result.artifact["processes"])
            result.artifact["tools"][name]["version"] = version.strip()
            if rc: raise OSError(f"{name} version probe exited {rc}")
        for stem in ("gate", "gold"):
            script = f"read_verilog {stem}.v; prep -top top; aigmap; write_aiger {stem}.aig"
            (directory / (stem + ".ys")).write_text(script + "\n")
            rc, log = _run([tools["yosys"], "-s", stem + ".ys"], directory, "yosys_" + stem, deadline, result.artifact["processes"])
            if rc: raise OSError(f"Yosys {stem} exited {rc}: {log[-500:]}")
        command = [tools["abc"], "-c", "cec gate.aig gold.aig"]
        rc, log = _run(command, directory, "abc", deadline, result.artifact["processes"])
        (directory / "abc.log").write_text(log)
        result.status = _abc_status(log, rc)
        result.reason = "standard ABC CEC execution evidence" if result.status == ProofStatus.PROVEN else log[-1000:]
    except subprocess.TimeoutExpired:
        result.status = ProofStatus.TIMEOUT; result.reason = "total proof deadline exceeded"
    except (ValueError, KeyError, TypeError, RecursionError) as exc:
        result.status = ProofStatus.MODEL_ERROR; result.reason = str(exc)
    except OSError as exc:
        result.status = ProofStatus.TOOL_ERROR; result.reason = str(exc)
    return _finish(result, started, directory)


def _check_artifact_files(proof):
    artifact = proof.artifact
    if "dir" not in artifact: return True
    root = Path(artifact["dir"])
    if not artifact.get("files") or not artifact.get("result_sha256"): return False
    if _hash(root / "result.json") != artifact["result_sha256"]: return False
    saved = json.loads((root / "result.json").read_text())
    actual = proof.as_dict(); actual = {**actual, "artifact": {k: v for k, v in artifact.items() if k != "result_sha256"}}
    if saved != actual: return False
    for name, digest in artifact["files"].items():
        if Path(name).name != name or _hash(root / name) != digest: return False
    return True


def verify_proof_evidence(graph, candidate, proof):
    """Validate bound evidence, replaying exhaustive semantics independently.

    ABC evidence checks integrity and the recorded trusted-tool invocation. It
    does not certify an untrusted prover or prevent malicious manifest forgery.
    """
    try:
        if proof.status != ProofStatus.PROVEN or proof.source_hash != graph.source_hash or proof.candidate_hash != candidate.candidate_hash or candidate.validate(graph):
            return False
        if not _check_artifact_files(proof): return False
        if proof.artifact.get("schema") != "local-proof/2": return False
        if proof.backend == "exhaustive":
            replay = prove_exhaustive(graph, candidate)
            return replay.status == ProofStatus.PROVEN and replay.checked_cases == proof.checked_cases and replay.artifact["truth_table"] == proof.artifact.get("truth_table")
        if proof.backend != "abc": return False
        root = Path(proof.artifact["dir"])
        if (root / "source.json").read_text() != _json(graph.data) or (root / "candidate.json").read_text() != _json(_identity(candidate)): return False
        for stem, semantic in (("gate", False), ("gold", True)):
            if (root / (stem + ".v")).read_text() != _region_verilog(graph, candidate, semantic=semantic): return False
            expected = f"read_verilog {stem}.v; prep -top top; aigmap; write_aiger {stem}.aig\n"
            if (root / (stem + ".ys")).read_text() != expected: return False
            if not (root / (stem + ".aig")).is_file(): return False
        tools = proof.artifact["tools"]; records = proof.artifact["processes"]
        if len(records) != 5: return False
        for name in ("yosys", "abc"):
            tool = tools[name]
            if not re.fullmatch(r"[0-9a-f]{64}", tool["sha256"]): return False
            version_log = (root / (name + "_version.stdout")).read_text(errors="replace") + (root / (name + "_version.stderr")).read_text(errors="replace")
            if tool["version"] != version_log.strip(): return False
        y, a = tools["yosys"]["path"], tools["abc"]["path"]
        expected_commands = [[y, "-V"], [a, "-c", "version"], [y, "-s", "gate.ys"], [y, "-s", "gold.ys"], [a, "-c", "cec gate.aig gold.aig"]]
        for record, command in zip(records, expected_commands):
            if record["command"] != command or record["returncode"] != 0 or record["timeout"]: return False
        log = (root / "abc.stdout").read_text(errors="replace") + (root / "abc.stderr").read_text(errors="replace")
        if (root / "abc.log").read_text() != log or _abc_status(log, 0) != ProofStatus.PROVEN: return False
        # Local scalar domains are tiny: also independently validate the modeled
        # function, so a fabricated success banner cannot cause acceptance.
        return prove_exhaustive(graph, candidate).status == ProofStatus.PROVEN
    except (OSError, ValueError, KeyError, TypeError):
        return False


class ProofStore:
    """Append-only attempt records; loaded records must retain evidence files."""
    def __init__(self, root):
        self.root = Path(root); self.root.mkdir(parents=True, exist_ok=True)

    def save(self, result):
        path = self.root / f"{result.candidate_hash}-{uuid.uuid4().hex}.json"
        with path.open("x") as stream:
            json.dump(result.as_dict(), stream, sort_keys=True, indent=2); stream.write("\n")
        return path

    def load(self, path):
        data = json.loads(Path(path).read_text())
        data["status"] = ProofStatus(data["status"])
        result = ProofResult(**data)
        if not _check_artifact_files(result): raise ValueError("proof artifact integrity failure")
        return result
