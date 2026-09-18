#!/usr/bin/env python3
"""
hal_extract_functions.py —— 提取网表的完整"寄存器传输"描述

对每个触发器提取其下一状态布尔函数, 对每个输出提取其布尔函数。
这把门级网表转成一组 (信号 <= 布尔函数) 的赋值, 本质上是
"未命名、未分组的 RTL" —— 正好是 LLM 擅长翻译成可读代码的形式。

输出 JSON: {ff_next_state: {ff名: 布尔函数}, outputs: {...}, register_groups: [...]}
"""
import os, sys, json

os.environ.setdefault("HAL_BASE_PATH", "/Users/blackbox/try_hai/hal/build")
os.environ["PATH"] = "/Users/blackbox/try_hai/tools/z3-4.13.4-arm64-osx-13.7.1/bin:" + os.environ.get("PATH", "")
sys.path.insert(0, "/Users/blackbox/try_hai/hal/build/lib")

import hal_py
hal_py.plugin_manager.load_all_plugins()
from hal_plugins import dataflow


def main():
    netlist, gatelib = sys.argv[1], sys.argv[2]
    nl = hal_py.NetlistFactory.load_netlist(netlist, gatelib)
    if nl is None:
        print(json.dumps({"error": "加载失败"})); return

    dec = hal_py.SubgraphNetlistDecorator(nl)
    comb = [g for g in nl.get_gates()
            if not g.get_type().has_property(hal_py.GateTypeProperty.ff)]
    ffs = [g for g in nl.get_gates()
           if g.get_type().has_property(hal_py.GateTypeProperty.ff)]
    cache = {}

    def net_name(net):
        return net.get_name() if net else "?"

    # 每个 FF 的下一状态函数
    ff_next = {}
    for ff in ffs:
        dnet = None
        for ep in ff.get_fan_in_endpoints():
            if ep.get_pin().get_name() in ("D", "d"):
                dnet = ep.get_net()
        qnet = None
        for ep in ff.get_fan_out_endpoints():
            if ep.get_pin().get_name() in ("Q", "q"):
                qnet = ep.get_net()
        if dnet is not None:
            bf = dec.get_subgraph_function(comb, dnet, cache)
            ff_next[ff.get_name()] = {
                "q_net": net_name(qnet),
                "next_state": str(bf) if bf is not None else None,
            }

    # 每个主输出的布尔函数
    outputs = {}
    for onet in nl.get_global_output_nets():
        # 若输出直接来自FF的Q, 记录; 否则提取组合函数
        try:
            bf = dec.get_subgraph_function(comb, onet, cache)
            outputs[onet.get_name()] = str(bf) if bf is not None else "(直连/寄存器输出)"
        except Exception:
            outputs[onet.get_name()] = "(无法提取)"

    # DANA 分组
    cfg = dataflow.Configuration(nl); cfg.with_flip_flops()
    res = dataflow.analyze(cfg)
    groups = []
    if res:
        for gid, gset in sorted(res.get_groups().items(), key=lambda kv: -len(kv[1])):
            groups.append({"id": int(gid), "width": len(gset),
                           "ffs": sorted(g.get_name() for g in gset)})

    result = {
        "num_ffs": len(ffs),
        "num_comb_gates": len(comb),
        "inputs": [n.get_name() for n in nl.get_global_input_nets()],
        "outputs_list": [n.get_name() for n in nl.get_global_output_nets()],
        "register_groups": groups,
        "ff_next_state": ff_next,
        "output_functions": outputs,
    }
    print("###JSON_START###")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
