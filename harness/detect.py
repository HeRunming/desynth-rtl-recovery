"""Deterministic, name-independent structural candidate detectors."""
from __future__ import annotations

from .candidate import Candidate


def _one_bit(cell: dict, pin: str) -> int | None:
    bits = cell.get("connections", {}).get(pin, [])
    return bits[0] if len(bits) == 1 and isinstance(bits[0], int) else None


def propose_full_adders(graph) -> list[Candidate]:
    """Find XOR/XOR and AND/AND/OR full-adder motifs in a Yosys JSON graph.

    Cell instance names and net IDs are used only as opaque identifiers.  The
    detector does not inspect source attributes or port names.
    """
    cells = graph.module().get("cells", {})
    by_type: dict[str, list[tuple[str, dict]]] = {}
    for name, cell in cells.items():
        by_type.setdefault(cell.get("type", ""), []).append((name, cell))
    xors = by_type.get("$xor", [])
    ands = by_type.get("$and", [])
    ors = by_type.get("$or", [])
    out: list[Candidate] = []
    for x1_name, x1 in xors:
        x1_out = _one_bit(x1, "Y")
        x1_in = tuple(sorted((_one_bit(x1, "A"), _one_bit(x1, "B"))))
        if x1_out is None or None in x1_in:
            continue
        for x2_name, x2 in xors:
            if x2_name == x1_name:
                continue
            x2_out = _one_bit(x2, "Y")
            x2_a, x2_b = _one_bit(x2, "A"), _one_bit(x2, "B")
            if x2_out is None or x1_out not in (x2_a, x2_b):
                continue
            cin = x2_b if x2_a == x1_out else x2_a
            a, b = x1_in
            if cin in (a, b, None):
                continue
            for a1_name, a1 in ands:
                if set((_one_bit(a1, "A"), _one_bit(a1, "B"))) != {a, b}:
                    continue
                a1_out = _one_bit(a1, "Y")
                if a1_out is None:
                    continue
                for a2_name, a2 in ands:
                    if a2_name == a1_name or set((_one_bit(a2, "A"), _one_bit(a2, "B"))) != {cin, x1_out}:
                        continue
                    a2_out = _one_bit(a2, "Y")
                    if a2_out is None:
                        continue
                    for or_name, org in ors:
                        if set((_one_bit(org, "A"), _one_bit(org, "B"))) != {a1_out, a2_out}:
                            continue
                        carry = _one_bit(org, "Y")
                        if carry is None:
                            continue
                        cells_used = tuple(sorted((x1_name, x2_name, a1_name, a2_name, or_name)))
                        out.append(Candidate(
                            candidate_id=f"fa_{x2_name}_{or_name}", source_hash=graph.source_hash,
                            region_cells=cells_used, input_bits=(a, b, cin), output_bits=(x2_out, carry),
                            operation="full_adder", evidence={"detector": "xor_and_or_motif", "shared": x1_out},
                        ))
    # Stable deduplication when the two inputs of a commutative cell were visited in reverse.
    seen: set[tuple] = set(); unique = []
    for c in out:
        key = (c.region_cells, c.input_bits, c.output_bits)
        if key not in seen:
            seen.add(key); unique.append(c)
    return unique
