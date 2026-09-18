#!/usr/bin/env python3
"""
verify_cse_yosys.py —— 用 yosys 的 miter+SAT 证明 CSE 输出与原式等价

为什么不用 z3 直接判: 实测 947K 字符的函数, z3 建完公式后 Xor 判定 600s
超时返回 unknown (见 verify_cse_equiv.py)。原因是把整条巨型公式塞给一个
SMT 调用, 没有结构共享。yosys 走的是组合等价检查的标准路子 (miter + SAT,
底层有结构哈希/ABC), 正是为这种规模设计的。

顺带一个好处: yosys 是**完全独立的第三方工具**, 不共享我这边任何解析/DAG
代码, 所以它给出的 unsat 比我自己写的判定器更有说服力。

必带反例控制: 故意破坏一根 wire, 确认整条流程真能报不等价。
(教训: 验证器自身的 bug 会伪装成"全部通过"。)

用法:
  python3 verify_cse_yosys.py <func.txt> [--keep] [--min-uses 2]
"""
import sys, re, time, argparse, subprocess, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from cse import TOK, cse_expressions

OPS = {"~", "&", "|", "^", "(", ")", "?", ":", "=="}


def leaves_of(text: str) -> list:
    """扫出所有变量名 (排除运算符与常量字面量)。独立于 ExprDAG。"""
    out = set()
    for t in TOK.findall(text):
        if t in OPS or "'" in t:
            continue
        out.add(t)
    return sorted(out)


def emit(mod: str, ins: list, body: str, wires=None, corrupt=None) -> str:
    L = [f"module {mod}(" + ", ".join(ins) + ", y);"]
    for v in ins:
        L.append(f"  input {v};")
    L.append("  output y;")
    for wn, we in (wires or []):
        rhs = f"~({we})" if wn == corrupt else we
        L.append(f"  wire {wn} = {rhs};")
    L.append(f"  assign y = {body};")
    L.append("endmodule")
    return "\n".join(L)


def run_yosys(dirp: Path, fa: str, fb: str, timeout: int) -> tuple:
    """返回 (verdict, 日志尾部)。verdict: equivalent / not-equivalent / inconclusive"""
    script = f"""
read_verilog -formal {fa} {fb}
miter -equiv -flatten A B miter
hierarchy -top miter
proc
opt -full
techmap
opt -full
sat -verify -prove trigger 0 miter
"""
    sp = dirp / "run.ys"
    sp.write_text(script)
    t0 = time.time()
    try:
        # cwd=dirp: 脚本里用的是相对文件名 a.v/b.v, 必须在临时目录里执行
        # 不能加 -q: 那会把 "SAT proof finished ... SUCCESS!/FAIL!" 这行也吞掉,
        # 而判定结果就是从这行读的 (加了 -q 会让所有用例都返回 inconclusive)。
        r = subprocess.run(["yosys", "-s", str(sp)], cwd=str(dirp),
                           capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return "inconclusive", f"yosys 超时 (>{timeout}s)", time.time() - t0
    log = (r.stdout or "") + (r.stderr or "")
    dt = time.time() - t0
    # yosys sat -verify: 成功证明会打印 "SUCCESS!"; 找到反例则 "FAIL"/assert
    if "SUCCESS!" in log or "Assert honored" in log:
        return "equivalent", log[-400:], dt
    if re.search(r"SAT proof finished.*model found|FAIL|Assert failed", log):
        return "not-equivalent", log[-400:], dt
    if r.returncode != 0:
        return "inconclusive", log[-700:], dt
    return "inconclusive", log[-700:], dt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("func")
    ap.add_argument("--min-size", type=int, default=3)
    ap.add_argument("--min-uses", type=int, default=2)
    ap.add_argument("--max-wires", type=int, default=20000)
    ap.add_argument("--timeout", type=int, default=2400)
    ap.add_argument("--skip-control", action="store_true")
    ap.add_argument("--keep", action="store_true", help="保留临时目录以便复查")
    args = ap.parse_args()

    text = Path(args.func).read_text().strip()
    n_in = len(text)
    ins = leaves_of(text)
    print(f"输入: {Path(args.func).name}  {n_in:,} 字符   变量 {len(ins)}")

    t0 = time.time()
    E, wires = cse_expressions({"@f": text}, min_size=args.min_size,
                               min_uses=args.min_uses,
                               max_wires=args.max_wires)
    t_cse = time.time() - t0
    body = E["@f"]
    clash = [w for w, _ in wires if w in set(ins)]
    assert not clash, f"wire 名与变量名撞车: {clash[:3]}"
    tot = len(body) + sum(len(w) + len(e) + 12 for w, e in wires)
    print(f"  CSE {t_cse:.1f}s   wire {len(wires):,}   输出 {tot/1e6:.3f}M   "
          f"压缩 {n_in/max(tot,1):.1f}×")

    tmp = Path(tempfile.mkdtemp(prefix="cse_equiv_"))
    (tmp / "a.v").write_text(emit("A", ins, text))
    (tmp / "b.v").write_text(emit("B", ins, body, wires))

    v, log, dt = run_yosys(tmp, "a.v", "b.v", args.timeout)
    mark = {"equivalent": "✅ 等价", "not-equivalent": "❌ 不等价",
            "inconclusive": "⚠️  未定"}[v]
    print(f"  yosys 等价判定 ({dt:.1f}s): {v}  → {mark}")
    if v != "equivalent":
        print("  --- yosys 日志尾部 ---")
        for ln in log.strip().splitlines()[-12:]:
            print("   ", ln)

    ctrl = None
    if wires and not args.skip_control:
        (tmp / "c.v").write_text(
            emit("B", ins, body, wires, corrupt=wires[-1][0]))
        ctrl, clog, cdt = run_yosys(tmp, "a.v", "c.v", args.timeout)
        cm = {"not-equivalent": "✅ 判定器有效",
              "equivalent": "❌ 判定器失灵(破坏后仍说等价)",
              "inconclusive": "⚠️  控制组未定"}[ctrl]
        print(f"  反例控制 ({cdt:.1f}s): {ctrl}  → {cm}")

    if args.keep:
        print(f"  临时文件保留在 {tmp}")
    else:
        subprocess.run(["rm", "-rf", str(tmp)])

    ok = v == "equivalent" and (ctrl is None or ctrl == "not-equivalent")
    print(f"  结论: {'✅ 压缩可信' if ok else '❌ 尚不可信'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
