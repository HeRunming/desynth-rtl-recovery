#!/usr/bin/env python3
"""
verify_cse_equiv.py —— 形式化证明 CSE 输出与原始表达式逻辑等价

为什么需要: probe_cse_scale.py 量到 552× 压缩, 但压缩率本身毫无意义 ——
必须先证明压缩后逻辑没变。

关键设计: 这里走**独立于 ExprDAG 的解析路径** (文本直接→z3, 不排序操作数、
不做 hash-consing), 所以 ExprDAG 里的 bug 会在这里暴露, 而不是被自己确认。

另外带**反例控制**: 故意破坏一根 wire, 确认判定器真能报出不等价。
(踩过的坑: 验证器自身的 bug 会伪装成"能力失败"或"全部通过"。)

用法:
  python3 verify_cse_equiv.py <func.txt> [--timeout-ms 120000]
"""
import sys, time, argparse, threading
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import z3
from cse import TOK, cse_expressions

CONST = {"1'b1": True, "1'b0": False}


def text_to_z3(s: str, env: dict):
    """全括号 Verilog 布尔表达式 → z3。env: 名字 → z3 表达式 (就地补充叶子)。"""
    toks = TOK.findall(s)
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else None

    def take():
        t = toks[pos[0]]; pos[0] += 1; return t

    def leaf(nm):
        if nm in CONST:
            return z3.BoolVal(CONST[nm])
        v = env.get(nm)
        if v is None:
            v = z3.Bool(nm); env[nm] = v
        return v

    def fold(op, kids):
        if len(kids) == 1:
            return kids[0]
        if op == "&":
            return z3.And(*kids)
        if op == "|":
            return z3.Or(*kids)
        if op == "^":
            r = kids[0]
            for k in kids[1:]:
                r = z3.Xor(r, k)
            return r
        if op == "==":
            r = kids[0]
            for k in kids[1:]:
                r = (r == k)
            return r
        raise ValueError(f"未知运算符 {op}")

    def expr():
        t = peek()
        if t is None:
            raise ValueError(f"意外结束: {s[:60]}")
        if t == "~":
            take(); return z3.Not(expr())
        if t == "(":
            take(); first = expr(); nxt = peek()
            if nxt == ")":
                take(); return first
            if nxt == "?":
                take(); th = expr()
                assert take() == ":", "缺 ':'"
                el = expr(); assert take() == ")", "缺 ')'"
                return z3.If(first, th, el)
            op = nxt; kids = [first]
            while peek() == op:
                take(); kids.append(expr())
            assert take() == ")", f"缺 ')' in {s[:60]}"
            return fold(op, kids)
        return leaf(take())

    r = expr()
    if pos[0] != len(toks):
        raise ValueError(f"尾部残留 {toks[pos[0]:pos[0]+4]}")
    return r


def build_cse_side(body, wires, env, corrupt=None):
    """按拓扑序把 wire 定义灌进 env, 再建主体。corrupt: 指定要取反的 wire。"""
    for wn, we in wires:
        v = text_to_z3(we, env)
        env[wn] = z3.Not(v) if wn == corrupt else v
    return text_to_z3(body, env)


def check(a, b, timeout_ms):
    s = z3.Solver(); s.set("timeout", timeout_ms)
    s.add(z3.Xor(a, b))
    return s.check()


def run(text, args, out):
    t0 = time.time(); envA = {}; A = text_to_z3(text, envA)
    out["t_a"] = time.time() - t0
    out["n_vars"] = len(envA)

    t0 = time.time()
    E, wires = cse_expressions({"@f": text}, min_size=args.min_size,
                               min_uses=args.min_uses,
                               max_wires=args.max_wires)
    out["t_cse"] = time.time() - t0
    body = E["@f"]
    clash = [w for w, _ in wires if w in envA]
    assert not clash, f"wire 名与叶子名撞车: {clash[:3]}"

    t0 = time.time()
    B = build_cse_side(body, wires, dict(envA))
    out["t_b"] = time.time() - t0

    t0 = time.time()
    out["verdict"] = str(check(A, B, args.timeout_ms))
    out["t_chk"] = time.time() - t0

    out.update(n_wires=len(wires), body=len(body),
               wire_chars=sum(len(w) + len(e) + 12 for w, e in wires))

    # ── 反例控制: 破坏一根 wire, 判定器必须报 sat (不等价) ──
    if wires and not args.skip_control:
        C = build_cse_side(body, wires, dict(envA), corrupt=wires[-1][0])
        out["control"] = str(check(A, C, args.timeout_ms))
    out["ok"] = True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("func")
    ap.add_argument("--timeout-ms", type=int, default=120000)
    ap.add_argument("--min-size", type=int, default=3)
    ap.add_argument("--min-uses", type=int, default=2)
    ap.add_argument("--max-wires", type=int, default=20000)
    ap.add_argument("--skip-control", action="store_true")
    args = ap.parse_args()

    text = Path(args.func).read_text().strip()
    n_in = len(text)
    print(f"输入: {Path(args.func).name}  {n_in:,} 字符")

    sys.setrecursionlimit(400_000)
    threading.stack_size(1024 * 1024 * 1024)
    out = {"ok": False}
    th = threading.Thread(target=run, args=(text, args, out), daemon=True)
    th.start(); th.join()

    if not out.get("ok"):
        print("  → 失败 (见上方异常)"); sys.exit(2)

    tot = out["body"] + out["wire_chars"]
    print(f"  变量 {out['n_vars']}   wire {out['n_wires']:,}   "
          f"输出 {tot/1e6:.3f}M   压缩 {n_in/max(tot,1):.1f}×")
    print(f"  耗时: 原式→z3 {out['t_a']:.1f}s  CSE {out['t_cse']:.1f}s  "
          f"CSE式→z3 {out['t_b']:.1f}s  判定 {out['t_chk']:.1f}s")
    v = out["verdict"]
    print(f"  等价判定 (Xor 应为 unsat): {v}"
          f"  → {'✅ 等价' if v == 'unsat' else '❌ 未证明'}")
    if "control" in out:
        c = out["control"]
        print(f"  反例控制 (破坏 wire, 应为 sat): {c}"
              f"  → {'✅ 判定器有效' if c == 'sat' else '❌ 判定器失灵'}")
    ok = v == "unsat" and out.get("control", "sat") == "sat"
    print(f"  结论: {'✅ 压缩可信' if ok else '❌ 不可信'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
