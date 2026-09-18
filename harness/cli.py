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
    args = ap.parse_args(argv)
    graph = load_yosys_json(args.json, args.top)
    if args.command == "summary":
        print(json.dumps(graph.manifest(), sort_keys=True, indent=2)); return 0
    if args.command == "anonymize":
        public, private = graph.anonymize(seed=args.seed, hide_ports=args.hide_ports)
        save_json(args.out, public)
        Path(str(args.out) + ".manifest.json").write_text(json.dumps({"public": private["public_hash"], "source": graph.source_hash}, indent=2) + "\n")
        return 0
    candidates = propose_full_adders(graph)
    if args.command == "detect":
        Path(args.out).write_text(json.dumps([c.canonical() for c in candidates], sort_keys=True, indent=2) + "\n"); return 0
    revision = RecoveryRevision(graph)
    results = []
    for candidate in candidates:
        result = prove_exhaustive(graph, candidate)
        results.append(result.as_dict())
        if result.status.value == "proven":
            revision = revision.accept(candidate, result)
    revision.export(args.out)
    Path(args.out, "proofs.json").write_text(json.dumps(results, sort_keys=True, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
