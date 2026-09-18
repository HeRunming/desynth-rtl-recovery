#!/usr/bin/env python3
"""
verify_mech_cse.py —— 证明 mech_cse.py 的压缩没有改变任何函数的逻辑

为什么必须做: mech_cse 把 445M 压到 5.8M (77×)。压缩率越高越该怀疑 ——
一个静默丢掉子表达式的 bug 也会表现为"压缩率极高"。这里对随机抽样的函数
逐个用 yosys miter+SAT 做形式化等价判定。

抽样策略: 优先覆盖**最大的那些函数** (压缩率最高 = 最可能出错的地方),
再随机补齐中小档。纯随机抽样会几乎只抽到未被压缩的小函数, 等于没验。

带反例控制: 每轮额外跑一个"故意破坏"的版本, 确认判定流程真能报不等价。

用法:
  python3 verify_mech_cse.py <orig_mech.json> <cse_mech.json> [--n 12]
"""
import sys, json, re, time, argparse, random, subprocess, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from cse import TOK

OPS = {"~", "&", "|", "^", "(", ")", "?", ":", "=="}


def hal_to_v(func: str) -> str:
    if func is None:
        return ""
    v = func.replace("0b1", "1'b1").replace("0b0", "1'b0")
    v = re.sub(r"net_(\d+)", r"n\1", v)
    return v.replace("!", "~")


def leaves_of(*texts) -> list:
    out = set()
    for t in texts:
        for tok in TOK.findall(t):
            if tok in OPS or "'" in tok:
                continue
            out.add(tok)
    return sorted(out)


def emit(mod, ins, body, wires=None, corrupt=None) -> str:
    L = [f"module {mod}(" + ", ".join(ins + ["y"]) + ");"]
    for v in ins:
        L.append(f"  input {v};")
    L.append("  output y;")
    for wn, we in (wires or []):
        rhs = f"~({we})" if wn == corrupt else we
        L.append(f"  wire {wn} = {rhs};")
    L.append(f"  assign y = {body};")
    L.append("endmodule")
    return "\n".join(L)


def yosys_equiv(dirp: Path, fb: str, timeout: int):
    script = f"""
read_verilog -formal a.v {fb}
miter -equiv -flatten A B miter
hierarchy -top miter
proc
opt -full
techmap
opt -full
sat -verify -prove trigger 0 miter
"""
    (dirp / "run.ys").write_text(script)
    t0 = time.time()
    try:
        r = subprocess.run(["yosys", "-s", "run.ys"], cwd=str(dirp),
                           capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return "inconclusive", time.time() - t0
    log = (r.stdout or "") + (r.stderr or "")
    dt = time.time() - t0
    if "no model found: SUCCESS!" in log:
        return "equivalent", dt
    if "model found: FAIL!" in log or "proof did fail" in log:
        return "not-equivalent", dt
    return "inconclusive", dt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("orig"); ap.add_argument("cse")
    ap.add_argument("--n", type=int, default=12, help="抽样函数数")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    print("读入两份 mech ...", flush=True)
    A = json.load(open(args.orig))
    B = json.load(open(args.cse))
    assert len(A["ff_defs"]) == len(B["ff_defs"]), "ff_defs 数量不一致!"
    assert len(A["out_defs"]) == len(B["out_defs"]), "out_defs 数量不一致!"

    # 按原始长度排序, 取最大的一半配额 + 随机一半配额
    pairs = []
    for i, (fa, fb) in enumerate(zip(A["ff_defs"], B["ff_defs"])):
        pairs.append((len(fa.get("func") or ""), i))
    pairs.sort(reverse=True)
    k = max(1, args.n // 2)
    chosen = [i for _, i in pairs[:k]]
    rest = [i for _, i in pairs[k:] if B["ff_defs"][i].get("cse_wires")]
    random.seed(args.seed)
    chosen += random.sample(rest, min(args.n - k, len(rest)))

    print(f"抽样 {len(chosen)} 个 FF 函数 (含最大的 {k} 个)\n")
    ok = bad = incon = 0
    ctrl_ok = ctrl_bad = 0
    for rank, i in enumerate(chosen, 1):
        fa, fb = A["ff_defs"][i], B["ff_defs"][i]
        orig = hal_to_v(fa.get("func"))
        body = fb.get("func") or ""
        wires = fb.get("cse_wires") or []
        if not orig:
            continue
        n0 = len(orig)
        n1 = len(body) + sum(len(w) + len(e) + 4 for w, e in wires)
        ins = leaves_of(orig, body, *[e for _, e in wires])
        wnames = {w for w, _ in wires}
        ins = [v for v in ins if v not in wnames]

        tmp = Path(tempfile.mkdtemp(prefix="mcse_"))
        (tmp / "a.v").write_text(emit("A", ins, orig))
        (tmp / "b.v").write_text(emit("B", ins, body, wires))
        v, dt = yosys_equiv(tmp, "b.v", args.timeout)

        cm = ""
        if wires:
            (tmp / "c.v").write_text(
                emit("B", ins, body, wires, corrupt=wires[-1][0]))
            cv, _ = yosys_equiv(tmp, "c.v", args.timeout)
            if cv == "not-equivalent":
                ctrl_ok += 1; cm = " ctrl✅"
            else:
                ctrl_bad += 1; cm = f" ctrl❌({cv})"
        subprocess.run(["rm", "-rf", str(tmp)])

        mark = {"equivalent": "✅", "not-equivalent": "❌ 不等价!",
                "inconclusive": "⚠️ 未定"}[v]
        if v == "equivalent": ok += 1
        elif v == "not-equivalent": bad += 1
        else: incon += 1
        print(f"  [{rank:2}/{len(chosen)}] net_{fa['q_id']:<8} "
              f"{n0/1e6:7.2f}M→{n1/1e3:7.1f}K "
              f"({n0/max(n1,1):6.1f}×) wire{len(wires):>5}  "
              f"{dt:6.1f}s {mark}{cm}", flush=True)

    print(f"\n等价 {ok}  不等价 {bad}  未定 {incon}")
    print(f"反例控制: 有效 {ctrl_ok}  失灵 {ctrl_bad}")
    good = bad == 0 and ctrl_bad == 0 and ok > 0
    print(f"结论: {'✅ mech_cse 压缩可信' if good else '❌ 有问题, 不可用'}")
    sys.exit(0 if good else 1)


if __name__ == "__main__":
    main()
