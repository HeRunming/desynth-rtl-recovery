# DeSynth RTL Recovery

HAL + structured naming + SMT/ABC verification for recovering readable RTL from gate-level netlists. This repository collects the existing research scripts, small-design experiments, architecture/benchmark reviews, and a reproducible PicoRV32 Config A fast-MUL repair.

## Current verified result

Config A previously emitted `X` for 33 multiplier state bits (`rd[31:63]`). A signed 33×33-bit product now replaces those assignments **only after all 33 real FF D-cone obligations are proven**. Standard ABC `&cec` checks all 64 product outputs with all 66 operand bits unconstrained. Negative controls flip outputs 31 and 63 and must fail.

| Acceptance evidence | Result |
| --- | --- |
| ABC CEC of the 64 real FF D functions | Equivalent; covers all 33 repaired bits |
| MUL/MULH/MULHSU/MULHU directed program | 8 matching stores, zero errors |
| Directed internal-state comparison | 2,313 FF Q bits; 3,469,500 checks; zero errors |
| Original 50,000-cycle port regression | 899,820 checks; zero mismatches, zero skipped all-X checks |
| 3,000-cycle source internal-state regression | 2,313 FF Q bits; 6,939,000 checks; zero errors |

This proves the repaired multiplier next-state functions and records whole-design simulation coverage. **It is not a whole-CPU sequential equivalence proof or a claim of general benchmark performance.**

See [the repair report](docs/CONFIG_A_REPAIR_REPORT.md), [machine-readable verdict](artifacts/config_a/verdict.json), and [experiment inventory](docs/EXPERIMENTS.md).

## Layout

- `agent/`: extraction, CSE, naming, lifting, verification, proof-gated repair.
- `pipeline/`, `examples/`: existing small RTL/netlist samples and research traces.
- `scripts/`: current reproducible Config A proof and regression entry points.
- `artifacts/config_a/`: original/repaired RTL, real netlist, mappings, testbenches, and evidence.
- `docs/`: reviews and historical notes. Older verdicts are superseded only for the Config A repair described above.
- `integrations/hal/`: original HAL probes and local build patch; HAL itself is an external dependency.

## Reproduce Config A

Use Python 3.10+ and Yosys/ABC/Icarus on PATH. The validated remote tool versions are recorded in the report. LLM credentials are unnecessary for the repair proof and regressions.

```sh
# Optional: point to the tested OSS CAD Suite tools.
export YOSYS=/path/to/oss-cad-suite/bin/yosys
export ABC=/path/to/oss-cad-suite/bin/yosys-abc
export IVERILOG=/path/to/oss-cad-suite/bin/iverilog
export VVP=/path/to/oss-cad-suite/bin/vvp

python3 scripts/prove_config_a.py --root artifacts/config_a --output proof_replay
python3 agent/repair_mul_word.py --root artifacts/config_a --proof-dir artifacts/config_a/proof_replay
python3 scripts/regress_config_a.py --root artifacts/config_a --out regression_replay
python3 -B -m unittest discover -s tests -v
```

Each proof process has an external hard timeout; unproven, failed, timed out, incomplete or changed inputs prevent emission. Replay directories must be new to preserve prior evidence. Replaying the proof changes report hashes/timestamps; archived evidence should be retained when comparing results.

Legacy HAL/LLM experiments still contain machine-specific paths and separate dependency requirements. `.env.example` documents the two LLM environment variables; no credentials are included. See [dependencies](docs/DEPENDENCIES.md) and the historical [handoff](docs/HANDOFF.md).

## Next research steps

The research goal is verified recovery of higher-level semantics from anonymized real netlists using a strong LLM, a structured harness, and EDA tools. The Config A repair is a reusable verification case, not evidence of autonomous anonymous recovery.

The [September 18 research review](docs/HARNESS_RESEARCH_2026-09-18.md) audits the current gaps and available tools. The [Harness v2 proposal](docs/HARNESS_V2_DESIGN.md) starts with a complete residual implementation, adds bounded structural queries and competing semantic candidates, and accepts replacements only with proof and final emitted-RTL checks. The bounded M0/M1 implementation now emits complete residual RTL, replaces proven full adders with actual arithmetic, and checks the emitted design with Yosys SAT plus ABC CEC under an explicit state-preserving contract. See the [implementation and limitations report](docs/HARNESS_M0_M1_REPORT.md).

The current development campaign passes whole-design checks on four designs across three anonymization seeds; FIFO is explicitly unsupported due to memory and undefined-value semantics. It is not an external benchmark or evidence of LLM gain. Next, add bounded HAL queries and the LLM to the same proof-gated loop, then evaluate incremental gain on anonymized real designs with matched budgets. External suites require source/library/license qualification; GenEDA Task 3 is not yet a verified available input. See the earlier [benchmark review](docs/BENCHMARK_REVIEW.md) for unresolved dataset provenance.

## Reproduce the anonymous M1 loop

```sh
# Set YOSYS and ABC as above; no LLM credentials needed.
python3 -B -m unittest discover -s tests -v
python3 -B scripts/run_harness_m1.py --out /tmp/harness-m1-run --seeds 17 42 99
```

The default campaign records 12 proven runs and 3 FIFO admission rejections, so its aggregate exit status is nonzero. See each report rather than treating unsupported cases as success. `scripts/evaluate_harness_m1.py` is the older annotation-only experiment.
