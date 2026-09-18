#!/usr/bin/env python3
"""
dana_groups.py —— 导出 DANA 寄存器分组(用 net_id 表示), 供语义命名按组切批

为什么需要: 固定大小切批会把本应同组的信号(如32位寄存器)切散,
导致 LLM 看不到完整总线, 只能输出一堆1位信号。
用 DANA 的结构分组切批, 让同一组 FF 在同一次 LLM 调用里。
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

    cfg = dataflow.Configuration(nl)
    cfg.with_flip_flops()
    res = dataflow.analyze(cfg)
    groups = []
    if res:
        for gid, gset in sorted(res.get_groups().items(), key=lambda kv: -len(kv[1])):
            # 取每个FF的Q net id (语义命名用 net_id 索引)
            ids = []
            for g in gset:
                for ep in g.get_fan_out_endpoints():
                    if ep.get_pin().get_name() in ("Q", "q"):
                        ids.append(ep.get_net().get_id())
            groups.append({"gid": int(gid), "width": len(ids), "bits": sorted(ids)})

    print("###JSON_START###")
    print(json.dumps({"groups": groups}, ensure_ascii=False))


if __name__ == "__main__":
    main()
