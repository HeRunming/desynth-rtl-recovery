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
        }

    @property
    def candidate_hash(self) -> str:
        raw = json.dumps(self.canonical(), sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(raw.encode()).hexdigest()

    def validate(self, graph: Any) -> list[str]:
        errors: list[str] = []
        if self.source_hash != graph.source_hash:
            errors.append("source_hash mismatch")
        mod = graph.module()
        cells = mod.get("cells", {})
        missing = [c for c in self.region_cells if c not in cells]
        if missing:
            errors.append(f"region cells missing: {missing[:4]}")
        if len(set(self.region_cells)) != len(self.region_cells):
            errors.append("duplicate region cell")
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
        return errors


def candidate_from_dict(data: dict[str, Any]) -> Candidate:
    return Candidate(
        candidate_id=data["candidate_id"], source_hash=data["source_hash"],
        region_cells=tuple(data.get("region_cells", [])), input_bits=tuple(data.get("input_bits", [])),
        output_bits=tuple(data.get("output_bits", [])), operation=data["operation"],
        parameters=dict(data.get("parameters", {})), evidence=dict(data.get("evidence", {})),
        status=CandidateStatus(data.get("status", CandidateStatus.PROPOSED.value)), proof_id=data.get("proof_id"),
    )
