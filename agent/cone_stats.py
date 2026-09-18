#!/usr/bin/env python3
"""
cone_stats.py —— 廉价的可扩展性诊断

不做 get_subgraph_function (那一步才是内存炸点), 只算每个 FF 的
"组合扇入锥" 大小: 从 D 端反向 BFS, 遇到 FF 输出/输入端口就停。

锥大小是提取代价的先验指标 —— 布尔函数的规模由锥内门数决定。
用它可以在付出提取代价之前就知道: 哪些寄存器会炸, 炸得多厉害。

用法: cone_stats.py <netlist> <gatelib> [--json out.json]
"""
import os, sys, json
from collections import deque

os.environ.setdefault("HAL_BASE_PATH", "/Users/blackbox/try_hai/hal/build")
os.environ["PATH"] = "/Users/blackbox/try_hai/tools/z3-4.13.4-arm64-osx-13.7.1/bin:" + os.environ.get("PATH", "")
sys.path.insert(0, "/Users/blackbox/try_hai/hal/build/lib")

import hal_py
hal_py.plugin_manager.load_all_plugins()


def main():
    netlist, gatelib = sys.argv[1], sys.argv[2]
    out_json = None
    if "--json" in sys.argv:
        out_json = sys.argv[sys.argv.index("--json") + 1]

    nl = hal_py.NetlistFactory.load_netlist(netlist, gatelib)
    if nl is None:
        print("加载失败", file=sys.stderr); return 1

    is_ff = {}
    for g in nl.get_gates():
        is_ff[g.get_id()] = g.get_type().has_property(hal_py.GateTypeProperty.ff)

    # net_id -> 驱动它的 gate (源)
    driver = {}
    for g in nl.get_gates():
        for ep in g.get_fan_out_endpoints():
            driver[ep.get_net().get_id()] = g

    ff_q_ids = set()
    for g in nl.get_gates():
        if not is_ff[g.get_id()]:
            continue
        for ep in g.get_fan_out_endpoints():
            if ep.get_pin().get_name() in ("Q", "q"):
                ff_q_ids.add(ep.get_net().get_id())

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

    ffs = [g for g in nl.get_gates() if is_ff[g.get_id()]]
    rows = []
    for ff in ffs:
        q, dn = qnet_of(ff), dnet_of(ff)
        if q is None or dn is None:
            continue
        # 反向 BFS: 统计锥内组合门数 + 按类型分布
        seen_g, seen_n = set(), set()
        kinds = {}
        dq = deque([dn.get_id()])
        seen_n.add(dn.get_id())
        while dq:
            nid = dq.popleft()
            if nid in ff_q_ids:      # 到达状态边界, 停
                continue
            g = driver.get(nid)
            if g is None:            # 输入端口 / 常量
                continue
            gid = g.get_id()
            if is_ff[gid]:
                continue
            if gid in seen_g:
                continue
            seen_g.add(gid)
            tn = g.get_type().get_name()
            kinds[tn] = kinds.get(tn, 0) + 1
            for ep in g.get_fan_in_endpoints():
                n2 = ep.get_net().get_id()
                if n2 not in seen_n:
                    seen_n.add(n2)
                    dq.append(n2)
        rows.append({"q_id": q.get_id(), "q_name": q.get_name(),
                     "cone_gates": len(seen_g), "kinds": kinds})

    rows.sort(key=lambda r: -r["cone_gates"])
    tot = sum(r["cone_gates"] for r in rows)
    print(f"FF 数: {len(rows)}   锥门数总和: {tot}   平均: {tot/max(1,len(rows)):.0f}")
    print(f"{'锥门数':>8}  {'XOR':>5}  {'MUX':>5}  q_name")
    for r in rows[:25]:
        k = r["kinds"]
        nx = sum(v for t, v in k.items() if "XOR" in t.upper())
        nm = sum(v for t, v in k.items() if "MUX" in t.upper())
        print(f"{r['cone_gates']:>8}  {nx:>5}  {nm:>5}  {r['q_name'][:60]}")

    import statistics
    cg = [r["cone_gates"] for r in rows]
    print("\n分位: " + "  ".join(
        f"p{p}={statistics.quantiles(cg, n=100)[p-1]:.0f}" for p in (50, 75, 90, 99)))
    print(f"max={max(cg)}  >5000门的FF数={sum(1 for c in cg if c > 5000)}"
          f"  >10000门的FF数={sum(1 for c in cg if c > 10000)}")

    if out_json:
        with open(out_json, "w") as f:
            json.dump(rows, f)
        print(f"\n→ {out_json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
