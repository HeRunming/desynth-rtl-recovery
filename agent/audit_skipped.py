#!/usr/bin/env python3
"""Summarize HAL-skipped FFs and keep dynamic coverage evidence separate.

This intentionally does not infer equivalence from simulation.  A skipped bit
is ``unknown`` unless a directed test demonstrates a concrete disagreement or
an independent proof supplies its next-state function.
"""
from __future__ import annotations
import argparse, json
from pathlib import Path


def audit(mech_path: str, cone_path: str | None = None) -> dict:
    d = json.loads(Path(mech_path).read_text())
    meta = {int(k): v for k, v in d.get("net_meta", {}).items()}
    cones = {}
    if cone_path and Path(cone_path).exists():
        for x in json.loads(Path(cone_path).read_text()):
            cones[int(x["q_id"])] = x.get("cone_gates")
    rows = []
    for ff in d.get("ff_defs", []):
        if ff.get("func") is not None:
            continue
        q = int(ff["q_id"])
        m = meta.get(q, {})
        rows.append({"q_id": q, "name": m.get("name", f"net_{q}"),
                     "reason": ff.get("skipped", "unknown"),
                     "cone_gates": cones.get(q)})
    rows.sort(key=lambda x: x["q_id"])
    return {"schema_version": 1, "mech": str(mech_path),
            "threshold": d.get("threshold"), "num_ffs": d.get("num_ffs"),
            "extracted_ffs": d.get("extracted_ffs"), "skipped_ffs": len(rows),
            "rows": rows,
            "dynamic_status": {"all": "unknown", "note": "Requires directed vectors or SAT proof; simulation pass is not proof."}}


def markdown(a: dict) -> str:
    lines = ["# Skipped FF audit", "", f"- threshold: `{a['threshold']}`",
             f"- FFs: `{a['num_ffs']}` total, `{a['extracted_ffs']}` extracted, `{a['skipped_ffs']}` skipped",
             "- default dynamic status: **unknown** (no equivalence inferred)", "",
             "| q_id | netlist name | cone gates | reason |", "|---:|---|---:|---|"]
    for r in a["rows"]:
        lines.append(f"| {r['q_id']} | `{r['name']}` | {r.get('cone_gates') or '?'} | {r['reason']} |")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mech")
    ap.add_argument("--cones")
    ap.add_argument("--json", required=True)
    ap.add_argument("--markdown", required=True)
    a = ap.parse_args()
    out = audit(a.mech, a.cones)
    Path(a.json).write_text(json.dumps(out, indent=2) + "\n")
    Path(a.markdown).write_text(markdown(out))
    print(f"skipped={out['skipped_ffs']} wrote {a.json} and {a.markdown}")
