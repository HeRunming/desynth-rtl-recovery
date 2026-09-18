"""Source-preserving recovery revisions and complete residual export."""
from __future__ import annotations

import copy
import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .candidate import Candidate, CandidateStatus
from .ir import SourceGraph, canonical_json
from .proof import ProofResult, ProofStatus


@dataclass
class RecoveryRevision:
    graph: SourceGraph
    accepted: list[Candidate] = field(default_factory=list)
    revision: int = 0

    @property
    def residual_hash(self) -> str:
        payload = {"source": self.graph.source_hash, "accepted": [c.canonical() for c in self.accepted], "revision": self.revision}
        return hashlib.sha256(canonical_json(payload).encode()).hexdigest()

    def residual_manifest(self) -> dict[str, Any]:
        mod = self.graph.module(); cells = set(mod.get("cells", {}))
        owned = set(x for c in self.accepted for x in c.region_cells)
        return {
            "schema": "recovery-revision/1", "source_hash": self.graph.source_hash,
            "residual_hash": self.residual_hash, "revision": self.revision,
            "source_cells": len(cells), "accepted_candidates": len(self.accepted),
            "replaced_cells": len(owned), "residual_cells": len(cells - owned),
            "cell_ownership_closed": owned | (cells - owned) == cells,
            "accepted": [c.canonical() for c in self.accepted],
        }

    def accept(self, candidate: Candidate, proof: ProofResult) -> "RecoveryRevision":
        errors = candidate.validate(self.graph)
        if errors:
            raise ValueError("candidate invalid: " + "; ".join(errors))
        if proof.status is not ProofStatus.PROVEN or proof.candidate_hash != candidate.candidate_hash:
            raise ValueError("candidate requires matching proven proof")
        occupied = {x for c in self.accepted for x in c.region_cells}
        overlap = occupied.intersection(candidate.region_cells)
        if overlap:
            raise ValueError(f"candidate overlaps accepted cells: {sorted(overlap)}")
        accepted = copy.deepcopy(candidate); accepted.status = CandidateStatus.PROVEN; accepted.proof_id = candidate.candidate_hash
        return RecoveryRevision(self.graph, self.accepted + [accepted], self.revision + 1)

    def rollback(self) -> "RecoveryRevision":
        """Return the previous accepted revision without mutating this object."""
        if not self.accepted:
            return self
        return RecoveryRevision(self.graph, self.accepted[:-1], max(0, self.revision - 1))

    def export(self, directory: str | Path) -> Path:
        """Export complete source graph plus semantic overlay and manifest."""
        out = Path(directory); out.mkdir(parents=True, exist_ok=True)
        (out / "source_graph.json").write_text(json.dumps(self.graph.data, sort_keys=True, indent=2) + "\n")
        (out / "semantic_overlay.json").write_text(json.dumps([c.canonical() for c in self.accepted], sort_keys=True, indent=2) + "\n")
        path = out / "manifest.json"; path.write_text(json.dumps(self.residual_manifest(), sort_keys=True, indent=2) + "\n")
        return path
