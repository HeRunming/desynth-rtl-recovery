#!/usr/bin/env python3
"""
test_fanin_cluster.py —— 验证扇入聚簇是否真的避免了"总线被批次边界切断"

用 net_meta 的真名做标尺 (只用于评估, 绝不进 prompt)。核心指标:
  **碎片率** = 同一个真实信号族的位被分到多少个不同批次。
  1.0 = 完美 (整条总线在同一批); 越大越糟 —— 试点里 pcpi_rs1 被切成 2 批。

对比三种分批: 固定大小 / 扇入聚簇 / 理论最优(按真名族分, 上界参考)。

用法: python3 test_fanin_cluster.py <mech_cse.json> [--max-ff 40]
"""
import sys, json, re, argparse
from collections import Counter, defaultdict
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from semantic_naming import fanin_clusters, pack_batches, affinity_batches
from eval_naming import family


def fragmentation(batches, fam_of):
    """返回 (平均碎片数, 被切断的族数, 总族数, 最糟的几个)."""
    where = defaultdict(set)
    for bi, b in enumerate(batches):
        for f in b:
            fam = fam_of.get(int(f["q_id"]))
            if fam:
                where[fam].add(bi)
    # 只看多位族 (单位信号无所谓分到哪批)
    sizes = Counter(fam_of.values())
    multi = {f: bs for f, bs in where.items() if sizes[f] >= 2}
    if not multi:
        return 0.0, 0, 0, []
    frags = [len(bs) for bs in multi.values()]
    split = sum(1 for n in frags if n > 1)
    worst = sorted(((len(bs), f, sizes[f]) for f, bs in multi.items()),
                   reverse=True)[:6]
    return sum(frags) / len(frags), split, len(multi), worst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mech"); ap.add_argument("--max-ff", type=int, default=40)
    args = ap.parse_args()

    m = json.loads(Path(args.mech).read_text())
    ffs = m["ff_defs"]
    nm = {int(k): v.get("name", "") for k, v in m["net_meta"].items()}
    fam_of = {int(f["q_id"]): family(nm.get(int(f["q_id"]), "")) for f in ffs}
    print(f"FF 总数 {len(ffs)}, 真实信号族 {len(set(fam_of.values()))} 个\n")

    # 1) 固定大小分批 (现状)
    fixed = [ffs[i:i + args.max_ff] for i in range(0, len(ffs), args.max_ff)]

    # 2) 扇入聚簇
    import time
    t0 = time.time()
    clusters = fanin_clusters(ffs)
    dt = time.time() - t0
    clustered = pack_batches(clusters, args.max_ff)

    # 3) 理论最优: 直接按真名族分批 (上界参考, 实际拿不到真名)
    byfam = defaultdict(list)
    for f in ffs:
        byfam[fam_of[int(f["q_id"])]].append(f)
    ideal = pack_batches(sorted(byfam.values(), key=len, reverse=True),
                         args.max_ff)

    print(f"扇入聚簇耗时 {dt:.1f}s → {len(clusters)} 簇 "
          f"(最大 {max(len(c) for c in clusters) if clusters else 0} 位)\n")

    # 4) 扇入亲和直接装批 (批容量即簇上限, 无事后切割)
    t0 = time.time()
    affin = affinity_batches(ffs, args.max_ff)
    dt2 = time.time() - t0
    print(f"扇入亲和装批耗时 {dt2:.1f}s → {len(affin)} 批\n")

    rows = [("固定大小(现状)", fixed), ("union-find聚簇", clustered),
            ("扇入亲和装批(新)", affin), ("按真名族(理论最优)", ideal)]
    print(f"{'分批方式':22} {'批数':>5} {'平均碎片':>9} {'被切断的族':>12}")
    for label, bs in rows:
        avg, split, tot, worst = fragmentation(bs, fam_of)
        print(f"{label:22} {len(bs):5} {avg:9.2f} {split:6}/{tot:<6}")

    print("\n最碎的几个族 (扇入聚簇):")
    _, _, _, worst = fragmentation(clustered, fam_of)
    for n, fam, size in worst:
        print(f"  {fam[:44]:44} {size:4} 位 → 散落 {n} 批")

    print("\n最碎的几个族 (固定大小, 对照):")
    _, _, _, worst_f = fragmentation(fixed, fam_of)
    for n, fam, size in worst_f:
        print(f"  {fam[:44]:44} {size:4} 位 → 散落 {n} 批")


if __name__ == "__main__":
    main()
