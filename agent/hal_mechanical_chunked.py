#!/usr/bin/env python3
"""
hal_mechanical_chunked.py —— 内存安全的提取器

cone_stats 告诉我们哪些 FF 的扇入锥会炸内存。这版跳过那些怪兽,
只提取"安全"的 FF (cone_gates <= threshold)。

调用: hal_mechanical_chunked.py <netlist> <gatelib> <cone_stats.json> \
                                 [--threshold T] [--out mech.json]

未提取的 FF 记录为 {"q_id": ..., "func": null, "skipped": "cone too large"}。
这样 assemble 时能看到覆盖率, 而不是以为"全提取完了"。
"""
import os, sys, json
from pathlib import Path

os.environ.setdefault("HAL_BASE_PATH", "/Users/blackbox/try_hai/hal/build")
os.environ["PATH"] = "/Users/blackbox/try_hai/tools/z3-4.13.4-arm64-osx-13.7.1/bin:" + os.environ.get("PATH", "")
sys.path.insert(0, "/Users/blackbox/try_hai/hal/build/lib")
sys.path.insert(0, str(Path(__file__).resolve().parent))
from artifact_contract import attach_contract

import hal_py
hal_py.plugin_manager.load_all_plugins()


def main():
    if len(sys.argv) < 4:
        print("用法: hal_mechanical_chunked.py <netlist> <gatelib> <cone_stats.json> "
              "[--threshold T] [--out mech.json]", file=sys.stderr)
        return 1

    netlist, gatelib, cone_json = sys.argv[1], sys.argv[2], sys.argv[3]
    threshold = 3000
    out_path = None
    if "--threshold" in sys.argv:
        threshold = int(sys.argv[sys.argv.index("--threshold") + 1])
    if "--out" in sys.argv:
        out_path = sys.argv[sys.argv.index("--out") + 1]

    with open(cone_json) as f:
        cone_stats = {r["q_id"]: r for r in json.load(f)}

    nl = hal_py.NetlistFactory.load_netlist(netlist, gatelib)
    if nl is None:
        print(json.dumps({"error": "加载失败"})); return 1

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

    for ff in ffs:
        q = qnet_of(ff)
        if q:
            ff_q_ids.add(q.get_id())

    # 每个FF的下一状态函数, 跳过超过阈值的
    ff_defs = []
    skipped, extracted = 0, 0
    for i, ff in enumerate(ffs, 1):
        q, dn = qnet_of(ff), dnet_of(ff)
        if q is None or dn is None:
            continue
        qid = q.get_id()
        cone_sz = cone_stats.get(qid, {}).get("cone_gates", 0)
        if cone_sz > threshold:
            ff_defs.append({"q_id": qid, "func": None,
                            "skipped": f"cone {cone_sz} gates > {threshold}"})
            skipped += 1
            if skipped <= 5:
                print(f"  skip {q.get_name()}: cone={cone_sz}", file=sys.stderr,
                      flush=True)
            continue
        try:
            bf = dec.get_subgraph_function(comb, dn, cache)
            ff_defs.append({"q_id": qid, "func": str(bf) if bf else None})
            extracted += 1
        except Exception as e:
            ff_defs.append({"q_id": qid, "func": None,
                            "skipped": f"提取异常: {type(e).__name__}"})
            skipped += 1
            print(f"  ERR {q.get_name()}: {e}", file=sys.stderr, flush=True)
        if i % 200 == 0:
            print(f"  {i}/{len(ffs)}  提取={extracted} 跳过={skipped}",
                  file=sys.stderr, flush=True)

    # 每个输出的组合函数
    out_defs = []
    for onet in nl.get_global_output_nets():
        oid = onet.get_id()
        if oid in ff_q_ids:
            out_defs.append({"o_id": oid, "func": f"net_{oid}", "direct_ff": True})
        else:
            try:
                bf = dec.get_subgraph_function(comb, onet, cache)
                out_defs.append({"o_id": oid, "func": str(bf) if bf else None,
                                 "direct_ff": False})
            except Exception as e:
                out_defs.append({"o_id": oid, "func": None, "direct_ff": False,
                                 "error": str(e)})

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
        "extracted_ffs": extracted,
        "skipped_ffs": skipped,
        "threshold": threshold,
        "input_net_ids": sorted(input_nets),
        "output_net_ids": sorted(output_nets),
        "ff_q_ids": sorted(ff_q_ids),
        "ff_defs": ff_defs,
        "out_defs": out_defs,
        "net_meta": net_meta,
    }
    attach_contract(
        result, stage="hal_mechanical_chunked",
        input_paths={"netlist": netlist, "gate_library": gatelib, "cone_stats": cone_json},
        counts={
            "ffs": len(ffs),
            "ff_defs": len(ff_defs),
            "extracted": extracted,
            "skipped": skipped,
            "outputs": len(out_defs),
            "output_missing_func": sum(1 for x in out_defs if not x.get("func")),
        },
        status="partial" if skipped else "ok",
    )

    print(f"\n完成: {extracted}/{len(ffs)} 提取, {skipped} 跳过",
          file=sys.stderr, flush=True)

    if out_path:
        with open(out_path, "w") as f:
            json.dump(result, f, ensure_ascii=False)
        print(f"→ {out_path}", file=sys.stderr, flush=True)
    else:
        print("###JSON_START###", flush=True)
        print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
