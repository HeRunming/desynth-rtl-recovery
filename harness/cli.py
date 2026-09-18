#!/usr/bin/env python3
"""Small deterministic CLI for M0/M1 smoke experiments."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from .detect import propose_full_adders
from .ir import load_yosys_json, save_json
from .proof import ProofStore, prove_exhaustive
from .recovery import RecoveryRevision
from .runner import run_recovery


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="source-preserving semantic recovery harness")
    sub = ap.add_subparsers(dest="command", required=True)
    for command in ("summary", "anonymize", "detect", "recover"):
        p = sub.add_parser(command); p.add_argument("json"); p.add_argument("--top")
    sub.choices["anonymize"].add_argument("--out", required=True)
    sub.choices["anonymize"].add_argument("--seed", type=int, default=0)
    sub.choices["anonymize"].add_argument("--hide-ports", action="store_true")
    sub.choices["detect"].add_argument("--out", required=True)
    sub.choices["recover"].add_argument("--out", required=True)
    sub.choices["recover"].add_argument("--backend", choices=["abc", "exhaustive"], default="abc")
    sub.choices["recover"].add_argument("--budget", type=float, default=30)
    sub.choices["recover"].add_argument("--final-budget", type=float, default=60)
    args = ap.parse_args(argv)
    graph = load_yosys_json(args.json, args.top)
    if args.command == "summary":
        print(json.dumps(graph.manifest(), sort_keys=True, indent=2)); return 0
    if args.command == "anonymize":
        public, private = graph.anonymize(seed=args.seed, hide_ports=args.hide_ports)
        save_json(args.out, public)
        # Do not publish source_hash or the evaluator mapping alongside the
        # public graph: source hashes enable corpus/linkage attacks.
        Path(str(args.out) + ".manifest.json").write_text(json.dumps({"schema": "anonymous-graph/1", "public": private["public_hash"]}, indent=2) + "\n")
        return 0
    candidates = propose_full_adders(graph)
    if args.command == "detect":
        Path(args.out).write_text(json.dumps([c.canonical() for c in candidates], sort_keys=True, indent=2) + "\n"); return 0
    result = run_recovery(graph, args.out, backend=args.backend, budget_s=args.budget, final_budget_s=args.final_budget)
    print(json.dumps(result, sort_keys=True, indent=2))
    return 0 if result['whole_design_proven'] else 1



if __name__ == "__main__":
    raise SystemExit(main())
