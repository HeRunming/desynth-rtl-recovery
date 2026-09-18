#!/usr/bin/env python3
"""
hal_extract.py —— HAL 结构提取器

从门级网表提取结构化事实(寄存器分组/端口/门统计), 输出 JSON。
这些事实作为"精确线索"喂给 LLM, 补上 LLM 的短板(它会数错寄存器、猜错分组)。

用法(独立进程, 因为需要 HAL 的特殊 python 环境):
  /usr/bin/python3 hal_extract.py <netlist.v> <gate_lib.hgl> > facts.json
"""
import os, sys, json
from pathlib import Path

os.environ.setdefault("HAL_BASE_PATH", "/Users/blackbox/try_hai/hal/build")
os.environ["PATH"] = "/Users/blackbox/try_hai/tools/z3-4.13.4-arm64-osx-13.7.1/bin:" + os.environ.get("PATH", "")
sys.path.insert(0, "/Users/blackbox/try_hai/hal/build/lib")
sys.path.insert(0, str(Path(__file__).resolve().parent))

import hal_py
hal_py.plugin_manager.load_all_plugins()
from hal_plugins import dataflow
from artifact_contract import attach_contract


def extract(netlist_path, gatelib_path):
    nl = hal_py.NetlistFactory.load_netlist(netlist_path, gatelib_path)
    if nl is None:
        return {"error": "HAL 无法解析网表"}

    gates = nl.get_gates()
    ffs = [g for g in gates if g.get_type().has_property(hal_py.GateTypeProperty.ff)]

    facts = {
        "total_gates": len(gates),
        "num_flip_flops": len(ffs),
        "top_ports": {"inputs": [], "outputs": []},
        "gate_type_histogram": {},
        "register_groups": [],
    }

    # 端口
    for net in nl.get_global_input_nets():
        facts["top_ports"]["inputs"].append(net.get_name())
    for net in nl.get_global_output_nets():
        facts["top_ports"]["outputs"].append(net.get_name())

    # 门类型直方图
    hist = {}
    for g in gates:
        t = g.get_type().get_name()
        hist[t] = hist.get(t, 0) + 1
    facts["gate_type_histogram"] = hist

    # DANA: 自动寄存器分组 (核心价值 —— LLM 数不准的东西)
    try:
        cfg = dataflow.Configuration(nl)
        cfg.with_flip_flops()
        res = dataflow.analyze(cfg)
        if res is not None:
            for gid, gate_set in res.get_groups().items():
                grp = sorted(g.get_name() for g in gate_set)
                facts["register_groups"].append({
                    "group_id": int(gid),
                    "width": len(grp),
                    "flip_flops": grp,
                })
            # 按宽度排序, 大的在前(更可能是数据寄存器)
            facts["register_groups"].sort(key=lambda x: -x["width"])
    except Exception as e:
        facts["dana_error"] = str(e)

    attach_contract(
        facts, stage="hal_extract",
        counts={
            "gates": len(gates), "ffs": len(ffs),
            "inputs": len(facts["top_ports"]["inputs"]),
            "outputs": len(facts["top_ports"]["outputs"]),
            "register_groups": len(facts["register_groups"]),
            "dana_errors": int("dana_error" in facts),
        },
        status="partial" if "dana_error" in facts else "ok",
    )
    return facts


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(json.dumps({"error": "usage: hal_extract.py <netlist> <gatelib>"}))
        sys.exit(1)
    result = extract(sys.argv[1], sys.argv[2])
    # 只输出 JSON 到 stdout (HAL 的日志会去 stderr)
    print("###JSON_START###")
    print(json.dumps(result, ensure_ascii=False, indent=2))
