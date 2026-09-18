#!/usr/bin/env python3
"""
probe_cse_scale.py —— 实测 cse.py 在超大布尔函数上的压缩率、耗时与内存

用法:
  # 1) 按大小分档, 把代表性函数各自 dump 成独立小文件 (只读一次大 json)
  python3 probe_cse_scale.py dump <mech.json> <outdir> --bands 5000,20000,100000

  # 2) 逐档实测 (建议外面套 timeout, 一档一个进程: 崩了/爆内存不影响其它档)
  timeout 600 python3 probe_cse_scale.py run <outdir>/band_00100000.txt

背景: Config A 的 postmortem 断言 "CNF 已经是最扁平的表示, CSE 救不了那个
87M 字符的函数, 而且解析 87M 字符本身就是瓶颈" —— 但那是**推断, 没实测**。
反过来看: 那个函数只引用 **60 个不同的 net**, 60 个变量上的重复 AND/XOR
模式, hash-consing 理论上应该塌得很厉害。这个脚本就是去证伪/证实它。

分两段计时 (parse vs CSE), 因为 postmortem 把 "解析是瓶颈" 和 "CSE 没用"
当成了同一个论点, 但它们是两件独立的事, 得分开量。
"""
import sys, json, re, time, argparse, resource, threading
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))


def hal_to_v(func: str) -> str:
    """HAL 函数字符串 → CSE 能吃的 Verilog (与 assemble_lifted.hal_to_v 一致)。"""
    if func is None:
        return ""
    v = func.replace("0b1", "1'b1").replace("0b0", "1'b0")
    v = re.sub(r"net_(\d+)", r"n\1", v)
    return v.replace("!", "~")


def mb(x) -> str:
    return f"{x/1e6:.2f}M"


def peak_mb() -> float:
    ru = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    # linux: KB, darwin: bytes
    return ru / 1024 if sys.platform.startswith("linux") else ru / 1024 / 1024


# ══════════════════════════════════════════════════════════════
def cmd_dump(args):
    m = json.load(open(args.mech))
    ff = m["ff_defs"]
    lens = sorted(((len(f["func"] or ""), i) for i, f in enumerate(ff)))
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    bands = [int(x) for x in args.bands.split(",")]
    picked = {}
    for T in bands:
        # 取长度 >= T 的最短那个; 没有就取全局最长
        hit = next((p for p in lens if p[0] >= T), lens[-1])
        picked[hit[1]] = hit[0]

    for idx, L in sorted(picked.items(), key=lambda kv: kv[1]):
        fn = ff[idx]
        p = outdir / f"band_{L:012d}.txt"
        p.write_text(hal_to_v(fn["func"]))
        print(f"{p.name}  q_id=net_{fn['q_id']}  {L:,} 字符")


# ══════════════════════════════════════════════════════════════
def _work(text, args, out):
    from cse import ExprDAG, cse_expressions
    # 1) 只解析: 量 DAG 塌缩程度 + 解析耗时
    t0 = time.time()
    dag = ExprDAG()
    root = dag.parse(text)
    t_parse = time.time() - t0
    n_nodes = len(dag.nodes)
    n_leaves = sum(1 for n in dag.nodes if n[0] == "leaf")
    tree_leaves = dag.size(root)          # 展开成树的叶子数
    out.update(t_parse=t_parse, n_nodes=n_nodes, n_leaves=n_leaves,
               tree_leaves=tree_leaves)

    # 2) 完整 CSE
    t0 = time.time()
    E, wires = cse_expressions({"@f": text}, min_size=args.min_size,
                               min_uses=args.min_uses,
                               max_wires=args.max_wires,
                               factor=not args.no_factor)
    t_cse = time.time() - t0
    body = len(E["@f"])
    wire_chars = sum(len(w) + len(e) + 12 for w, e in wires)   # "  wire w = ...;"
    out.update(t_cse=t_cse, n_wires=len(wires), body=body,
               wire_chars=wire_chars, total_out=body + wire_chars, ok=True)


def cmd_run(args):
    text = Path(args.func).read_text().strip()
    n_in = len(text)
    print(f"输入: {args.func}  {n_in:,} 字符")

    sys.setrecursionlimit(400_000)
    out = {"ok": False}
    # 大栈线程: 全括号表达式的递归下降在深嵌套上会爆 C 栈 (segfault, 抓不到)
    threading.stack_size(1024 * 1024 * 1024)
    th = threading.Thread(target=_work, args=(text, args, out), daemon=True)
    th.start()
    th.join()

    if not out.get("ok"):
        print("  → 失败/未完成 (见上方异常)")
        return
    print(f"  解析:   {out['t_parse']:8.1f}s   DAG 结点 {out['n_nodes']:,} "
          f"(叶子 {out['n_leaves']:,})")
    print(f"          展开树叶子 {out['tree_leaves']:,} → DAG 塌缩 "
          f"{out['tree_leaves']/max(out['n_nodes'],1):.1f}×")
    print(f"  CSE:    {out['t_cse']:8.1f}s   提出 wire {out['n_wires']:,}")
    print(f"  输出:   主体 {mb(out['body'])} + wire {mb(out['wire_chars'])} "
          f"= {mb(out['total_out'])}")
    print(f"  ★ 压缩: {n_in/max(out['total_out'],1):.1f}×   "
          f"({mb(n_in)} → {mb(out['total_out'])})")
    print(f"  峰值内存: {peak_mb():.0f} MB")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("dump"); d.add_argument("mech"); d.add_argument("outdir")
    d.add_argument("--bands", default="5000,20000,100000,1000000")
    d.set_defaults(fn=cmd_dump)
    r = sub.add_parser("run"); r.add_argument("func")
    r.add_argument("--min-size", type=int, default=3)
    r.add_argument("--min-uses", type=int, default=2)
    r.add_argument("--max-wires", type=int, default=20000)
    r.add_argument("--no-factor", action="store_true")
    r.set_defaults(fn=cmd_run)
    a = ap.parse_args()
    a.fn(a)
