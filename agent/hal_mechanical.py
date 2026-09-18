#!/usr/bin/env python3
"""
hal_mechanical.py —— 机械等价还原提取器

从门级网表提取"寄存器传输级"的精确描述, 输出可直接组装成 flat RTL 的数据:
  - 每个FF: q_net_id <= 下一状态布尔函数(用net_<id>表示各输入)
  - 每个主输出: out_net_id = 组合布尔函数
  - net_id 到 (是否输入端口/FF输出/线网) 及原始名字的映射

因为布尔函数是HAL从门级SMT级精确提取的, 用这些函数机械重建的RTL
在数学上必然等价于原网表 —— 这是整个pipeline的一致性验证基石。
"""
import os, sys, json, re
from pathlib import Path

os.environ.setdefault("HAL_BASE_PATH", "/Users/blackbox/try_hai/hal/build")
os.environ["PATH"] = "/Users/blackbox/try_hai/tools/z3-4.13.4-arm64-osx-13.7.1/bin:" + os.environ.get("PATH", "")
sys.path.insert(0, "/Users/blackbox/try_hai/hal/build/lib")
sys.path.insert(0, str(Path(__file__).resolve().parent))
from artifact_contract import attach_contract

import hal_py
hal_py.plugin_manager.load_all_plugins()


def main():
    netlist, gatelib = sys.argv[1], sys.argv[2]
    nl = hal_py.NetlistFactory.load_netlist(netlist, gatelib)
    if nl is None:
        print(json.dumps({"error": "加载失败"})); return

    dec = hal_py.SubgraphNetlistDecorator(nl)
    ffs = [g for g in nl.get_gates()
           if g.get_type().has_property(hal_py.GateTypeProperty.ff)]
    comb = [g for g in nl.get_gates()
            if not g.get_type().has_property(hal_py.GateTypeProperty.ff)]
    cache = {}

    input_nets = {n.get_id() for n in nl.get_global_input_nets()}
    output_nets = {n.get_id() for n in nl.get_global_output_nets()}
    ff_q_ids = set()

    def qnet_of(ff):
        for ep in ff.get_fan_out_endpoints():
            if ep.get_pin().get_name() in ("Q", "q"):
                return ep.get_net()
        return None

    def dnet_of(ff):
        for ep in ff.get_fan_in_endpoints():
            if ep.get_pin().get_name() in ("D", "d"):
                return ep.get_net()
        return None

    # 每个FF的下一状态函数
    ff_defs = []
    for ff in ffs:
        q = qnet_of(ff); dn = dnet_of(ff)
        if q is None or dn is None:
            continue
        ff_q_ids.add(q.get_id())
        bf = dec.get_subgraph_function(comb, dn, cache)
        ff_defs.append({"q_id": q.get_id(), "func": str(bf) if bf else None})

    # 每个输出的组合函数
    out_defs = []
    for onet in nl.get_global_output_nets():
        oid = onet.get_id()
        if oid in ff_q_ids:
            out_defs.append({"o_id": oid, "func": f"net_{oid}", "direct_ff": True})
        else:
            bf = dec.get_subgraph_function(comb, onet, cache)
            out_defs.append({"o_id": oid, "func": str(bf) if bf else None,
                             "direct_ff": False})

    # net_id -> 元信息 (名字/类别)
    net_meta = {}
    for net in nl.get_nets():
        nid = net.get_id()
        cat = "input" if nid in input_nets else \
              "ff_q" if nid in ff_q_ids else \
              "output" if nid in output_nets else "wire"
        net_meta[nid] = {"name": net.get_name(), "cat": cat}

    result = {
        "num_ffs": len(ffs),
        "input_net_ids": sorted(input_nets),
        "output_net_ids": sorted(output_nets),
        "ff_q_ids": sorted(ff_q_ids),
        "ff_defs": ff_defs,
        "out_defs": out_defs,
        "net_meta": net_meta,
    }
    attach_contract(
        result, stage="hal_mechanical",
        input_paths={"netlist": netlist, "gate_library": gatelib},
        counts={
            "ffs": len(ffs),
            "ff_defs": len(ff_defs),
            "ff_missing_func": sum(1 for x in ff_defs if not x.get("func")),
            "outputs": len(out_defs),
            "output_missing_func": sum(1 for x in out_defs if not x.get("func")),
            "skipped": sum(1 for x in ff_defs if x.get("skipped")),
        },
    )
    print("###JSON_START###")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
