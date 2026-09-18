# Dependencies and third-party sources

The proof/repaired RTL regression uses Python standard library, Yosys, its ABC binary, and Icarus. The exact validated versions are in CONFIG_A_REPAIR_REPORT.md. Tools are not vendored.

The HAL pipeline uses https://github.com/emsec/hal at commit `391881cd4cb94fb25a6fd0abffed94fc55378ced`, including its `hal_py` and plugins. Local probes and a CMake adjustment are in integrations/hal. The generated gate vocabulary is defined by pipeline/hal_cells.lib. Historical build instructions contain original host paths and may require adaptation.

Z3 is used by the structural lifting stages (`z3-solver`, with native library paths handled by agent/z3setup.py). API-backed naming uses the Python standard library and externally supplied LLM_BASE/LLM_KEY environment variables. No provider account configuration is bundled.

examples/complex/picorv32.v retains its upstream copyright and ISC notice. The derived Config A netlist and lift artifacts refer to this source. HAL has its own upstream licensing; binaries, build trees, paper PDFs, credentials and local application settings are excluded. This snapshot does not assign a new blanket license to research code or third-party material.
