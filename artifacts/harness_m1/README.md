# M1 development evidence — 2026-09-18

The summary records 58 passing regression tests and 15 design/seed runs: 12 full-design SAT + ABC CEC passes, 3 FIFO source-admission rejections. This is development evidence, not an external benchmark or LLM comparison.

`campaign_20260918.tar.gz` contains the complete campaign: imported inputs, evaluator-only source mappings, anonymous worker inputs, local proofs and SQLite attempts, emitted RTL, proven snapshots, state contracts, scripts, tool identities, process logs and verdicts. `summary_20260918.json` binds the archive, runtime code and proven RTL to SHA256 hashes and provides paths relative to the archive.

Extract into a new directory for inspection. Embedded absolute paths record the original machine/run; for fresh execution use `scripts/run_harness_m1.py`, rather than treating relocated cached records as portable authority. Evaluator mappings must not be made accessible to a future LLM recovery worker. Source graph/RTL/verification hashes in every successful run were cross-checked before archival.

See [the report](../../docs/HARNESS_M0_M1_REPORT.md) for the exact state-preserving proof contract, unsupported FIFO semantics and reproduction commands.
