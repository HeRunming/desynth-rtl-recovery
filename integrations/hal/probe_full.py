#!/usr/bin/env python3
"""probe_full.py — 端到端跑 HAL: DANA分组 → solve_fsm解状态图, 看它到底产出什么"""
import os, sys
os.environ["HAL_BASE_PATH"] = "/Users/blackbox/try_hai/hal/build"
sys.path.insert(0, "/Users/blackbox/try_hai/hal/build/lib")
import hal_py
hal_py.plugin_manager.load_all_plugins()
from hal_plugins import dataflow, solve_fsm

def log(*a): print("###", *a, flush=True)

FSM = "/Users/blackbox/try_hai/hal/examples/fsm_extracted/fsm"
nl = hal_py.NetlistFactory.load_netlist(FSM + "/fsm.v", FSM + "/example_library.hgl")

gates = nl.get_gates()
ffs = [g for g in gates if g.get_type().has_property(hal_py.GateTypeProperty.ff)]
log(f"网表: {len(gates)} 门, {len(ffs)} 触发器")
log("触发器名:", [g.get_name() for g in ffs])

# === 1) DANA 自动寄存器分组 ===
log("\n===== 1) DANA 自动寄存器分组 (无需人工指定) =====")
cfg = dataflow.Configuration(nl)
cfg.with_flip_flops()
res = dataflow.analyze(cfg)
if res is None:
    log("DANA 返回 None"); sys.exit(1)
groups = res.get_groups()
log(f"DANA 自动识别出 {len(groups)} 个寄存器组:")
for gid, gate_ids in groups.items():
    log(f"  组{gid}: {len(gate_ids)} 个触发器")

# === 2) solve_fsm: 用 DANA 找到的状态寄存器解状态图 ===
log("\n===== 2) solve_fsm 解状态转移图 =====")
# 拿最大的组当 state_reg (启发式)
if groups:
    biggest = max(groups.values(), key=len)
    state_reg = list(biggest)  # 已经是 Gate 对象
    log(f"用 {len(state_reg)} 个触发器作为 state_reg")
    # transition_logic: 全部组合门
    comb = [g for g in gates if not g.get_type().has_property(hal_py.GateTypeProperty.ff)]
    log(f"transition_logic: {len(comb)} 个组合门")
    dot = FSM + "/state_graph.dot"
    result = solve_fsm.solve_fsm(nl, state_reg, comb, {}, dot, 60000)
    if result is None:
        log("solve_fsm 返回 None (可能 state_reg 选择不对)")
    else:
        log(f"✓ 解出状态转移图: {len(result)} 个状态")
        for state, trans in list(result.items())[:8]:
            log(f"  状态 {state}: {len(trans)} 条转移 -> {list(trans.keys())}")
        log(f"DOT 图写入: {dot}")
