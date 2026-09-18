"""Typed semantic candidates and strict source-bound validation."""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Iterable


class CandidateStatus(str, Enum):
    PROPOSED = "proposed"
    PROVEN = "proven"
    REJECTED = "rejected"
    UNKNOWN = "unknown"


@dataclass
class Candidate:
    candidate_id: str
    source_hash: str
    region_cells: tuple[str, ...]
    input_bits: tuple[int, ...]
    output_bits: tuple[int, ...]
    operation: str
    parameters: dict[str, Any] = field(default_factory=dict)
    evidence: dict[str, Any] = field(default_factory=dict)
    status: CandidateStatus = CandidateStatus.PROPOSED
    proof_id: str | None = None
    retained_cells: tuple[str, ...] = ()

    def canonical(self) -> dict[str, Any]:
        return {
            "candidate_id": self.candidate_id,
            "source_hash": self.source_hash,
            "region_cells": list(self.region_cells),
            "input_bits": list(self.input_bits),
            "output_bits": list(self.output_bits),
            "operation": self.operation,
            "parameters": self.parameters,
            "evidence": self.evidence,
            "status": self.status.value,
            "proof_id": self.proof_id,
            "retained_cells": list(self.retained_cells),
        }

    @property
    def candidate_hash(self) -> str:
        # Status and proof_id are lifecycle metadata.  They must not change the
        # identity bound by a proof artifact after transactional acceptance.
        identity = {k: v for k, v in self.canonical().items() if k not in {"status", "proof_id"}}
        raw = json.dumps(identity, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(raw.encode()).hexdigest()

    def validate(self, graph: Any) -> list[str]:
        errors: list[str] = list(graph.validate())
        if self.source_hash != graph.source_hash:
            errors.append("source_hash mismatch")
        mod = graph.module()
        cells = mod.get("cells", {})
        if not self.region_cells:
            errors.append("candidate has no region cells")
        missing = [c for c in self.region_cells if c not in cells]
        if missing:
            errors.append(f"region cells missing: {missing[:4]}")
        if len(set(self.region_cells)) != len(self.region_cells):
            errors.append("duplicate region cell")
        if len(set(self.input_bits)) != len(self.input_bits):
            errors.append("duplicate input bit")
        if self.operation != "full_adder" or len(self.input_bits) != 3 or len(self.output_bits) != 2:
            errors.append("unsupported candidate operation/interface")
        if self.parameters:
            errors.append("full_adder parameters unsupported")
        if len(set(self.output_bits)) != len(self.output_bits):
            errors.append("duplicate output bit")
        if not self.output_bits:
            errors.append("candidate has no outputs")
        valid_bits = set()
        for cell in cells.values():
            for bits in cell.get("connections", {}).values():
                valid_bits.update(b for b in bits if isinstance(b, int))
        valid_bits.update(b for p in mod.get("ports", {}).values() for b in p.get("bits", []) if isinstance(b, int))
        for b in (*self.input_bits, *self.output_bits):
            if b not in valid_bits:
                errors.append(f"unknown bit {b}")
        region_outputs: set[int] = set()
        region_inputs: set[int] = set()
        region = set(self.region_cells)
        produced: set[int] = set(); consumed: set[int] = set()
        users: dict[int, set[str]] = {}
        for other_name, other in cells.items():
            for other_pin, other_bits in other.get("connections", {}).items():
                if other.get("port_directions", {}).get(other_pin) == "input":
                    for bit in other_bits:
                        if isinstance(bit, int): users.setdefault(bit, set()).add(other_name)
        for name in self.region_cells:
            cell = cells.get(name, {})
            if cell.get("type") not in {"$xor", "$and", "$or", "$not"}:
                errors.append("candidate region is not supported scalar combinational logic")
            if any(len(bits) != 1 for bits in cell.get("connections", {}).values()):
                errors.append("candidate region contains nonscalar cell")
            for pin, bits in cell.get("connections", {}).items():
                direction = cell.get("port_directions", {}).get(pin)
                for bit in bits:
                    if not isinstance(bit, int):
                        continue
                    if direction == "output":
                        produced.add(bit)
                    elif direction == "input":
                        consumed.add(bit)
        port_bits = {b for p in mod.get("ports", {}).values() for b in p.get("bits", []) if isinstance(b, int)}
        for bit in produced:
            inside_users = users.get(bit, set()) & region
            outside_users = (users.get(bit, set()) - region) or ({"__port__"} if bit in port_bits else set())
            if outside_users or not inside_users:
                region_outputs.add(bit)
        region_inputs = consumed - produced
        retained = set(self.retained_cells)
        if not retained <= region or len(retained) != len(self.retained_cells):
            errors.append("invalid retained cell set")
        retained_produced = {b for name in retained for pin, bits in cells.get(name, {}).get("connections",{}).items()
                             if cells[name].get("port_directions",{}).get(pin)=="output" for b in bits if isinstance(b,int)}
        if set(self.output_bits) & retained_produced:
            errors.append("semantic outputs cannot also be residual driven")
        if not set(self.output_bits) <= region_outputs or region_outputs - set(self.output_bits) - retained_produced:
            errors.append(f"candidate omits or adds region side outputs: expected {sorted(region_outputs)}")
        for name in retained:
            for pin, bits in cells.get(name, {}).get("connections",{}).items():
                if cells[name].get("port_directions",{}).get(pin)=="input":
                    if any(b in produced and b not in retained_produced for b in bits):
                        errors.append("retained logic depends on deleted region cell")
        if set(self.input_bits) != region_inputs:
            errors.append(f"candidate boundary inputs mismatch: expected {sorted(region_inputs)}")
        return errors


def candidate_from_dict(data: dict[str, Any]) -> Candidate:
    return Candidate(
        candidate_id=data["candidate_id"], source_hash=data["source_hash"],
        region_cells=tuple(data.get("region_cells", [])), input_bits=tuple(data.get("input_bits", [])),
        output_bits=tuple(data.get("output_bits", [])), operation=data["operation"],
        parameters=dict(data.get("parameters", {})), evidence=dict(data.get("evidence", {})),
        status=CandidateStatus(data.get("status", CandidateStatus.PROPOSED.value)), proof_id=data.get("proof_id"),
        retained_cells=tuple(data.get("retained_cells", [])),
    )
