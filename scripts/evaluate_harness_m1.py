#!/usr/bin/env python3
"""Evaluate the deterministic M1 loop on prepared Yosys JSON designs.

The script intentionally keeps the source graph and anonymized graph separate.
It reports annotation-only discovery/proof/ownership, not emitted RTL or
whole-design correctness. Use run_harness_m1.py for actual M1 evaluation.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Allow direct execution from any working directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from harness.detect import propose_full_adders
from harness.ir import SourceGraph, save_json
from harness.proof import prove_exhaustive
from harness.recovery import RecoveryRevision


def evaluate(path: Path, top: str | None, seed: int) -> dict:
    source = SourceGraph.from_yosys_json(json.loads(path.read_text()), top=top)
    public, private = source.anonymize(seed=seed, hide_ports=True)
    anon = SourceGraph.from_yosys_json(public, top="top_0")
    rows = []
    revision = RecoveryRevision(anon)
    for candidate in propose_full_adders(anon):
        proof = prove_exhaustive(anon, candidate, timeout_s=10)
        accepted = False
        if proof.status.value == "proven":
            revision = revision.accept(candidate, proof)
            accepted = True
        rows.append({"candidate": candidate.candidate_id, "status": proof.status.value,
                     "checked_cases": proof.checked_cases, "accepted": accepted,
                     "candidate_hash": candidate.candidate_hash})
    manifest = revision.residual_manifest()
    return {
        "track": "annotation_only", "whole_design_proven": False,
        "input": str(path), "source": source.manifest(), "anonymous": anon.manifest(),
        "anonymization": {"seed": seed, "public_hash": private["public_hash"]},
        "candidate_count": len(rows), "proven_count": sum(x["status"] == "proven" for x in rows),
        "accepted_count": sum(x["accepted"] for x in rows), "candidates": rows,
        "recovery": manifest,
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("design", nargs="+", help="Yosys JSON files")
    ap.add_argument("--top", action="append", help="top per design, in the same order")
    ap.add_argument("--seed", type=int, default=17)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args(argv)
    tops = args.top or []
    report = {"schema": "harness-m1-eval/1", "seed": args.seed,
              "designs": [evaluate(Path(path), tops[i] if i < len(tops) else None, args.seed)
                          for i, path in enumerate(args.design)]}
    save_json(args.out, report)
    print(json.dumps({"schema": report["schema"], "designs": [
        {"input": d["input"], "cells": d["source"]["counts"]["cells"],
         "states": d["source"]["counts"]["state_cells"],
         "candidates": d["candidate_count"], "proven": d["proven_count"],
         "replaced": d["recovery"]["replaced_cells"], "residual": d["recovery"]["residual_cells"]}
        for d in report["designs"]]}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
