#!/usr/bin/env python3
"""
hal_chunk.py —— HAL 分块提取器 (大规模网表的关键)

思路: 大网表整体喂 LLM 会超时。改为以"寄存器组"为单元,
提取每个寄存器位的"下一状态布尔函数"(next-state logic),
把 11654 门的网表分解成 N 个小的、可读的布尔函数块,
每块小到 LLM 能轻松处理。

这利用了 HAL 的两个核心能力:
  1. DANA 自动寄存器分组
  2. get_subgraph_function 提取任意信号的布尔函数
"""
import os, sys, json

os.environ.setdefault("HAL_BASE_PATH", "/Users/blackbox/try_hai/hal/build")
os.environ["PATH"] = "/Users/blackbox/try_hai/tools/z3-4.13.4-arm64-osx-13.7.1/bin:" + os.environ.get("PATH", "")
sys.path.insert(0, "/Users/blackbox/try_hai/hal/build/lib")

import hal_py
hal_py.plugin_manager.load_all_plugins()
from hal_plugins import dataflow


def get_ff_next_state_function(nl, ff_gate):
    """提取一个触发器 D 端的布尔函数(即它的下一状态逻辑)。"""
    # 找 D 输入 pin 的网络
    d_net = None
    for ep in ff_gate.get_fan_in_endpoints():
        pin = ep.get_pin()
        if pin.get_name() in ("D", "d"):
            d_net = ep.get_net()
            break
    if d_net is None:
        return None
    try:
        # 提取从该网络反向到寄存器/输入边界的子图布尔函数
        bf = hal_py.SubgraphNetlistDecorator(nl).get_subgraph_function(
            [g for g in nl.get_gates()], d_net)
        return str(bf)
    except Exception as e:
        return f"<提取失败: {e}>"


def main():
    netlist = sys.argv[1]
    gatelib = sys.argv[2]
    nl = hal_py.NetlistFactory.load_netlist(netlist, gatelib)
    if nl is None:
        print(json.dumps({"error": "加载失败"})); return

    # DANA 分组
    cfg = dataflow.Configuration(nl)
    cfg.with_flip_flops()
    res = dataflow.analyze(cfg)
    groups = res.get_groups() if res else {}

    # 统计每组规模, 以便分块
    summary = {"total_gates": len(nl.get_gates()),
               "num_groups": len(groups), "groups": []}
    for gid, gate_set in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        summary["groups"].append({"id": int(gid), "width": len(gate_set)})

    print("###JSON_START###")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
