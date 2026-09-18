"""Proof services, classified outcomes, and source-bound proof artifacts."""
from __future__ import annotations

import json
import itertools
import os
import shutil
import subprocess
import tempfile
import time
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

    def as_dict(self) -> dict[str, Any]:
        return {
            "status": self.status.value, "candidate_hash": self.candidate_hash,
            "backend": self.backend, "checked_cases": self.checked_cases,
            "counterexample": self.counterexample, "reason": self.reason,
            "elapsed_ms": self.elapsed_ms, "artifact": self.artifact,
        }


def _eval_bit(graph, bit: int, env: dict[int, int], memo: dict[int, int], visiting: set[int]) -> int:
    if bit in (0, 1):
        return bit
    if bit in env:
        return env[bit]
    if bit in memo:
        return memo[bit]
    if bit in visiting:
        raise ValueError(f"combinational loop at bit {bit}")
    visiting.add(bit)
    drivers = []
    for name, cell in graph.module().get("cells", {}).items():
        for pin, bits in cell.get("connections", {}).items():
            if cell.get("port_directions", {}).get(pin) == "output" and bit in bits:
                drivers.append((name, cell, pin, bits.index(bit)))
    if len(drivers) != 1:
        raise ValueError(f"bit {bit} has {len(drivers)} drivers")
    _, cell, pin, idx = drivers[0]
    typ = cell.get("type")
    def inp(p: str) -> int:
        bits = cell.get("connections", {}).get(p, [])
        return _eval_bit(graph, bits[idx] if len(bits) > 1 else bits[0], env, memo, visiting)
    if typ in {"$xor", "$and", "$or", "$xnor", "$nand", "$nor"}:
        a, b = inp("A"), inp("B")
        value = {"$xor": a ^ b, "$and": a & b, "$or": a | b, "$xnor": int(a == b), "$nand": int(not (a & b)), "$nor": int(not (a | b))}[typ]
    elif typ in {"$not", "$logic_not"}:
        value = 1 - inp("A")
    elif typ in {"$mux", "$pmux"}:
        sel = _eval_bit(graph, cell["connections"]["S"][0], env, memo, visiting)
        p = "B" if sel else "A"
        value = inp(p)
    else:
        raise ValueError(f"unsupported proof cell {typ}")
    visiting.remove(bit); memo[bit] = int(value); return int(value)


def _candidate_outputs(candidate, vals: dict[int, int]) -> tuple[int, ...]:
    if candidate.operation != "full_adder":
        raise ValueError(f"unsupported candidate operation {candidate.operation}")
    a, b, cin = (vals[x] for x in candidate.input_bits)
    return (a ^ b ^ cin, (a & b) | (cin & (a ^ b)))


def prove_exhaustive(graph, candidate, *, timeout_s: float = 30.0) -> ProofResult:
    started = time.monotonic(); cases = 0
    errors = candidate.validate(graph)
    if errors:
        return ProofResult(ProofStatus.MODEL_ERROR, candidate.candidate_hash, "exhaustive", reason="; ".join(errors))
    try:
        for values in itertools.product((0, 1), repeat=len(candidate.input_bits)):
            if time.monotonic() - started > timeout_s:
                return ProofResult(ProofStatus.TIMEOUT, candidate.candidate_hash, "exhaustive", cases, reason="deadline")
            env = dict(zip(candidate.input_bits, values)); memo: dict[int, int] = {}
            actual = tuple(_eval_bit(graph, bit, env, memo, set()) for bit in candidate.output_bits)
            expected = _candidate_outputs(candidate, env)
            cases += 1
            if actual != expected:
                ce = {str(bit): value for bit, value in env.items()}
                return ProofResult(ProofStatus.COUNTEREXAMPLE, candidate.candidate_hash, "exhaustive", cases, ce, "output mismatch", int((time.monotonic() - started) * 1000))
        return ProofResult(ProofStatus.PROVEN, candidate.candidate_hash, "exhaustive", cases, elapsed_ms=int((time.monotonic() - started) * 1000))
    except Exception as exc:
        return ProofResult(ProofStatus.MODEL_ERROR, candidate.candidate_hash, "exhaustive", cases, reason=str(exc), elapsed_ms=int((time.monotonic() - started) * 1000))


def _region_verilog(graph, candidate, *, semantic: bool) -> str:
    """Emit a tiny isolated miter input for the candidate's source region."""
    if candidate.operation != "full_adder":
        raise ValueError(f"unsupported ABC candidate operation {candidate.operation}")
    mod = graph.module(); cells = mod.get("cells", {})
    region = set(candidate.region_cells)
    drivers: dict[int, tuple[str, dict]] = {}
    for name in candidate.region_cells:
        cell = cells[name]
        for pin, bits in cell.get("connections", {}).items():
            if cell.get("port_directions", {}).get(pin) == "output":
                for bit in bits:
                    if isinstance(bit, int): drivers[bit] = (name, cell)
    names = {bit: f"i{i}" for i, bit in enumerate(candidate.input_bits)}
    visiting: set[int] = set(); expr_cache: dict[int, str] = {}
    def expr(bit: int) -> str:
        if bit in names: return names[bit]
        if bit in (0, 1): return "1'b1" if bit else "1'b0"
        if bit in expr_cache: return expr_cache[bit]
        if bit in visiting: raise ValueError("region combinational loop")
        if bit not in drivers: raise ValueError(f"region output depends on external bit {bit}")
        visiting.add(bit); _, cell = drivers[bit]; typ = cell.get("type")
        def inp(pin: str) -> str:
            bits = cell.get("connections", {}).get(pin, [])
            if len(bits) != 1: raise ValueError(f"non-scalar pin {typ}.{pin}")
            return expr(bits[0])
        if typ in {"$xor", "$and", "$or"}: op = {"$xor": "^", "$and": "&", "$or": "|"}[typ]; value = f"({inp('A')} {op} {inp('B')})"
        elif typ in {"$not", "$logic_not"}: value = f"~{inp('A')}"
        else: raise ValueError(f"unsupported region cell {typ}")
        visiting.remove(bit); expr_cache[bit] = value; return value
    port_decl = ", ".join(f"input {x}" for x in names.values()) + ", output sum, output carry"
    if semantic:
        a, b, cin = (names[x] for x in candidate.input_bits)
        body = [f"assign sum = {a} ^ {b} ^ {cin};", f"assign carry = ({a} & {b}) | ({cin} & ({a} ^ {b}));"]
    else:
        body = [f"assign sum = {expr(candidate.output_bits[0])};", f"assign carry = {expr(candidate.output_bits[1])};"]
    return "module top(" + ", ".join(names.values()) + ",sum,carry);\n  " + "; ".join(port_decl.split(", ")) + ";\n  " + "\n  ".join(body) + "\nendmodule\n"


def prove_abc(graph, candidate, *, abc: str | None = None, yosys: str | None = None,
              timeout_s: float = 30.0, artifact_dir: str | Path | None = None) -> ProofResult:
    """Prove a local candidate with Yosys AIG export and standard ABC CEC.

    The original region and semantic candidate are emitted independently. ABC
    sees only two AIGs with the same named interface order; source and candidate
    hashes are recorded alongside the logs by the caller.
    """
    started = time.monotonic()
    errors = candidate.validate(graph)
    if errors:
        return ProofResult(ProofStatus.MODEL_ERROR, candidate.candidate_hash, "abc", reason="; ".join(errors))
    yosys = yosys or os.environ.get("YOSYS") or shutil.which("yosys") or "/Users/blackbox/try_hai/oss-cad-suite/bin/yosys"
    abc = abc or os.environ.get("ABC") or shutil.which("yosys-abc") or "/Users/blackbox/try_hai/oss-cad-suite/bin/yosys-abc"
    if not Path(yosys).is_file() or not Path(abc).is_file():
        return ProofResult(ProofStatus.TOOL_ERROR, candidate.candidate_hash, "abc", reason="Yosys/ABC executable unavailable")
    temp = Path(artifact_dir) if artifact_dir else Path(tempfile.mkdtemp(prefix="harness_abc_"))
    temp.mkdir(parents=True, exist_ok=True)
    gate_v, gold_v = temp / "gate.v", temp / "gold.v"
    gate_aig, gold_aig = temp / "gate.aig", temp / "gold.aig"
    gate_v.write_text(_region_verilog(graph, candidate, semantic=False))
    gold_v.write_text(_region_verilog(graph, candidate, semantic=True))
    try:
        for source, top, aig in ((gate_v, "top", gate_aig), (gold_v, "top", gold_aig)):
            proc = subprocess.run([yosys, "-p", f"read_verilog {source}; prep -top {top}; aigmap; write_aiger {aig}"], capture_output=True, text=True, timeout=timeout_s)
            if proc.returncode:
                return ProofResult(ProofStatus.TOOL_ERROR, candidate.candidate_hash, "abc", reason=proc.stderr[-1000:], artifact={"dir": str(temp)})
        proc = subprocess.run([abc, "-c", f"cec {gate_aig} {gold_aig}"], capture_output=True, text=True, timeout=timeout_s)
        log = proc.stdout + proc.stderr
        if "equivalent" in log.lower() and "not equivalent" not in log.lower():
            status = ProofStatus.PROVEN; reason = "standard ABC CEC"
        elif "not equivalent" in log.lower() or "counterexample" in log.lower():
            status = ProofStatus.COUNTEREXAMPLE; reason = log[-1000:]
        else:
            status = ProofStatus.UNKNOWN; reason = log[-1000:] or f"ABC rc={proc.returncode}"
        (temp / "abc.log").write_text(log)
        return ProofResult(status, candidate.candidate_hash, "abc", 0, reason=reason, elapsed_ms=int((time.monotonic() - started) * 1000), artifact={"dir": str(temp), "source_hash": graph.source_hash})
    except subprocess.TimeoutExpired:
        return ProofResult(ProofStatus.TIMEOUT, candidate.candidate_hash, "abc", reason="deadline", elapsed_ms=int((time.monotonic() - started) * 1000), artifact={"dir": str(temp)})


class ProofStore:
    """Content-addressed proof records; no record is accepted without hashes."""
    def __init__(self, root: str | Path):
        self.root = Path(root); self.root.mkdir(parents=True, exist_ok=True)

    def save(self, result: ProofResult) -> Path:
        path = self.root / f"{result.candidate_hash}.json"
        path.write_text(json.dumps(result.as_dict(), sort_keys=True, indent=2) + "\n")
        return path
