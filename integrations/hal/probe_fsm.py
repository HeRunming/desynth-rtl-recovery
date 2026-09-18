#!/usr/bin/env python3
"""probe_fsm.py — 探测 HAL 对 FSM 网表的能力边界"""
import os, sys
os.environ["HAL_BASE_PATH"] = "/Users/blackbox/try_hai/hal/build"
sys.path.insert(0, "/Users/blackbox/try_hai/hal/build/lib")
import hal_py
hal_py.plugin_manager.load_all_plugins()

def log(*a): print(*a, flush=True)

# HAL 自带的 fsm 例子(已解压)里有配套 gate library
FSM_DIR = "/Users/blackbox/try_hai/hal/examples/fsm_extracted/fsm"
NETLIST = FSM_DIR + "/fsm.v"
GATELIB = FSM_DIR + "/example_library.hgl"

log("=== 用 HAL 自带 fsm 例子 (含配套 gate library) ===")
log("netlist:", NETLIST)
log("gatelib:", GATELIB)

gl = hal_py.GateLibraryManager.load(GATELIB) if os.path.exists(GATELIB) else None
log("gate library 加载:", "✓" if gl else "✗")

nl = hal_py.NetlistFactory.load_netlist(NETLIST, GATELIB)
if nl is None:
    log("网表加载失败"); sys.exit(1)

gates = nl.get_gates()
ffs = [g for g in gates if g.get_type().has_property(hal_py.GateTypeProperty.ff)]
log(f"\n网表: {len(gates)} 门, {len(ffs)} 个触发器")

# --- DANA: 自动寄存器分组 ---
log("\n=== DANA (dataflow) 自动寄存器分组 ===")
from hal_plugins import dataflow
funcs = [x for x in dir(dataflow) if not x.startswith("_")]
log("dataflow 接口:", funcs)
