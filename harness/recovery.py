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
            "semantic_covered_cells": len(owned),
            "planned_replaced_cells": len({x for c in self.accepted for x in set(c.region_cells)-set(c.retained_cells)}), "unexplained_cells": len(cells - owned),
            "replaced_cells": 0, "residual_cells": len(cells),
            "cell_ownership_closed": owned | (cells - owned) == cells,
            "emitted_rtl": False,
            "verification_scope": "source_graph_with_semantic_overlay",
            "accepted": [c.canonical() for c in self.accepted],
        }

    def accept(self, candidate: Candidate, proof: ProofResult) -> "RecoveryRevision":
        errors = candidate.validate(self.graph)
        if errors:
            raise ValueError("candidate invalid: " + "; ".join(errors))
        if (proof.status is not ProofStatus.PROVEN or proof.candidate_hash != candidate.candidate_hash
                or proof.source_hash != self.graph.source_hash):
            raise ValueError("candidate requires matching proven proof")
        from .proof import verify_proof_evidence
        if not verify_proof_evidence(self.graph, candidate, proof):
            raise ValueError("proof evidence failed validation")
        occupied = {x for c in self.accepted for x in c.region_cells}
        overlap = occupied.intersection(candidate.region_cells)
        if overlap:
            raise ValueError(f"candidate overlaps accepted cells: {sorted(overlap)}")
        accepted = copy.deepcopy(candidate); accepted.status = CandidateStatus.PROVEN; accepted.proof_id = candidate.candidate_hash
        return RecoveryRevision(self.graph, self.accepted + [accepted], self.revision + 1)

    def implementation_graph(self) -> SourceGraph:
        """Replace proven scalar full adders with explicit 2-bit additions.

        Whole-design verification of the emitted RTL is a separate requirement.
        Original source graph remains immutable and is always the oracle.
        """
        data = self.graph.data
        mod = data["modules"][self.graph.top]; cells = mod["cells"]
        all_bits = {b for c in cells.values() for bs in c.get("connections", {}).values() for b in bs if isinstance(b,int)}
        all_bits.update(b for n in mod.get("netnames", {}).values() for b in n.get("bits",[]) if isinstance(b,int))
        # Unused inputs may exist only in ports, without a cell connection or
        # diagnostic netname. They still occupy wire IDs in the source graph.
        all_bits.update(b for p in mod.get("ports", {}).values() for b in p.get("bits",[]) if isinstance(b,int))
        next_bit = max(all_bits | {1}) + 1
        removed = set(); outputs = set()
        for index, cand in enumerate(self.accepted):
            if cand.status != CandidateStatus.PROVEN or cand.proof_id != cand.candidate_hash:
                raise ValueError("changed accepted candidate")
            errors = cand.validate(self.graph)
            if errors: raise ValueError("; ".join(errors))
            if removed.intersection(cand.region_cells): raise ValueError("overlapping accepted regions")
            removed.update(cand.region_cells); outputs.update(cand.output_bits)
            for cell in set(cand.region_cells) - set(cand.retained_cells): cells.pop(cell)
            tmp = [next_bit, next_bit+1]; next_bit += 2
            for part, a, b, y in [(0,[cand.input_bits[0],"0"],[cand.input_bits[1],"0"],tmp),
                                  (1,tmp,[cand.input_bits[2],"0"],list(cand.output_bits))]:
                name = f"semantic_fa_{index}_{part}"
                if name in cells: raise ValueError("replacement cell name collision")
                cells[name] = {"type":"$add", "parameters":{"A_WIDTH":"10","B_WIDTH":"10","Y_WIDTH":"10","A_SIGNED":"0","B_SIGNED":"0"},
                               "port_directions":{"A":"input","B":"input","Y":"output"},
                               "connections":{"A":a,"B":b,"Y":y}}
        # Keep aliases only for retained nets. Eliminated internal diagnostic
        # aliases have no driver after replacement and must not be re-emitted.
        live = {b for c in cells.values() for bs in c.get("connections",{}).values() for b in bs if isinstance(b,int)}
        live.update(b for p in mod.get("ports",{}).values() for b in p.get("bits",[]) if isinstance(b,int))
        for name, net in list(mod.get("netnames", {}).items()):
            if any(isinstance(b,int) and b not in live for b in net.get("bits",[])):
                if net.get("attributes",{}).get("init") is not None:
                    raise ValueError("replacement would remove initialized net")
                del mod["netnames"][name]
        result = SourceGraph.from_yosys_json(data, self.graph.top)
        errors = result.validate()
        if errors: raise ValueError("invalid replacement graph: " + "; ".join(errors))
        return result

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
