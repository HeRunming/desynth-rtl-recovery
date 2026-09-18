# Config A fast-MUL repair — 2026-09-18

**Verdict: repaired multiplier accepted; all requested regression classes passed.**

## Original defect

HAL skipped 33 `genblk1.pcpi_mul.rd(31..63)` next-state functions because their cones exceeded 3,000 gates. The emitted lift assigned `1'bx`. A directed `MUL(-1, 2)` exposed a real mismatch (`7ffffffe` vs `fffffffe`); the old random port test had missed it.

## Proven repair

The proof exporter resolves every real FF Q and its D connection from the original mapped netlist JSON, traverses combinational dependencies to FF Q cutpoints, rejects unsupported cells, unresolved inputs, duplicate drivers and unknown constants, and emits all 64 rd D functions. The reference is a signed 33×33 product truncated to 64 bits. Both interfaces explicitly contain all 66 operand bits. The regeneration check rereads the original Verilog and verifies the complete cell semantics and net-bit mapping against the archived JSON; source attributes containing a different input path are excluded.

Yosys builds both networks without warnings and with `check -assert`; ABC `&cec` compares them. The new CEC phase reports `UNDECIDED` while reducing the miter, then the automatic old-CEC fallback concludes **Networks are equivalent** in approximately 16 seconds. The final fallback verdict is the accepted evidence. Two independent modified references (output 31 and output 63 inverted) both produce `NOT EQUIVALENT`. All 33 proof obligations link to the complete 64-output proof, rather than claiming 33 independent solver runs.

The acceptance manifest binds the source Verilog, cell model, JSON, candidate, AIGs and log hashes. Emission verifies all 33 statuses, qid spans, actual register declarations and unique target assignments; it refuses unknown or changed evidence. The candidate is emitted after operand declarations to avoid implicit forward-declared wires. No LLM call is used in this repair.

## Bit mapping

| Semantic state | HAL qid | Actual emitted lift |
| --- | --- | --- |
| rd[31:38] | 27106–27113 | unnamed_27075[31:38] |
| rd[39:63] | 27114–27138 | control_state_5[0:24] |
| rs1[32:0] | 27140–27172 | data_word_a[32:0] |
| rs2[31:0] | 27173–27204 | input_capture_reg[31:0] |
| rs2[32] | 27205 | data_word_b_msb_flag |

The name manifest contains duplicate bus labels. The emitter follows the assembler's actual suffix allocation and checks concrete declarations. HAL qids and Yosys net numbers are distinct namespaces; the source net names and bit indices bind them. `source_internal_mapping.json` records all 2,313 Q-state comparisons.

## Acceptance results

- Directed four-opcode MUL test: eight matching stores, zero errors. Each opcode has six `pcpi_valid` observation cycles on each side. The legacy log calls these “handshakes”; they are request observation counts, not independent ready events.
- Directed internal-state test: every one of 2,313 FF Q bits checked, 3,469,500 checks, zero errors.
- Original 50k-cycle port test: zero mismatches / 899,820 checks, zero skipped all-X checks.
- Source internal-state test: 3,000 cycles, all 2,313 FF Q bits, 6,939,000 checks, zero errors. Uses the original port-regression stimulus, with explicit FF-instance Q references derived from qid provenance, including all repaired bits. No X masking or warmup exclusion was added to make it pass.
- Gate unit tests: altered AIG, incomplete proof, timeout status, wrong qid provenance, and duplicate patch are rejected; emission exactly reproduces the archived repaired RTL.
- The packaged proof replay was executed again in a fresh remote directory and accepted. The packaged regression runner also records commands, timeouts and hashes.

## Failed attempts and corrections

Old direct Minisat approaches timed out and remain unproven. An earlier harness misdeclared the MUX output, omitted explicit sign input declarations and relied on ABC's ineffective approximate partition timeout. Its results are discarded. The current flow has external process-group timeouts.

Experimental `&acec` arithmetic-tree matching returned an all-zero counterexample with output bit 5 set. Independent evaluation of the *original* AIGs yields zero on both sides; 260 deterministic AIG test vectors also agree. Therefore that transformed arithmetic-checker result is not accepted as a counterexample or proof. Its log is retained for tool investigation; only standard CEC plus negative controls gates the repair.

The old raw-named lift also contains the same 33 `X` assignments. Comparing a repaired lift to it reports two different packed buses; this is an invalid oracle for the repaired bits, not an initialization defect. The old failed log is retained. The replacement internal test compares all state against the actual original gate netlist without altering that reference. An earlier test probe incorrectly compared D to Q and reused a loop variable; it was stopped and is excluded from acceptance evidence.

## Tools and scope

Validated on Linux 6.8.0-136-generic with Yosys 0.68+80 (`621d943ac`), ABC 1.01 (2026-08-18 build), and Icarus Verilog 14.0 devel (`s20260301-381-gb5fdf0647`). `cells_init.v` initializes mapped FF Q to zero; the lift uses the corresponding zero initial state. Formal CEC is two-state combinational equivalence with unconstrained operand register values. Regressions exercise the complete source and lift under this simulation model.

This closes the Config A fast-MUL skipped-bit repair. Other architecture findings and broad benchmark generality are separate follow-up work. No PPA or universal whole-CPU equivalence claim is made.
