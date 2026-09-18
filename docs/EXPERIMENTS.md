# Experiment inventory

| Family | Included evidence | Interpretation |
| --- | --- | --- |
| Small combinational/control examples | examples/, pipeline/, agent/trace_*.json | Historical samples, not a statistically controlled benchmark |
| Baseline vs HAL-assisted recovery | agent/matrix_results.txt, trace_*_baseline/hybrid.json | Keep versions/retries separate; old failures remain archived |
| FIFO v2, UART, traffic | Versioned traces and docs/HANDOFF.md | UART/UART_TX are not independent designs; traffic was unresolved in the historical review |
| PicoRV32 Config B | Historical STATUS/HANDOFF and reviews | Prior simulation evidence; not rerun or asserted newly proven here |
| PicoRV32 Config A skipped MUL | artifacts/config_a/, CONFIG_A_REPAIR_REPORT.md | 33 repaired D bits proven; complete source-state and port regressions passed |
| Architecture audit | ASTRA_REVIEW.md | Historical findings; Config A MUL closure does not close every finding |
| Benchmark selection | bmks.md, BENCHMARK_REVIEW.md | Proposed real-suite evaluation, not completed results |

The current accepted Config A verdict is artifacts/config_a/verdict.json. Historical notes deliberately retain earlier failures and unknown statuses. Large external work caches and toolchains remain on the research server; this repository includes a self-contained replay bundle for the Config A repair.
