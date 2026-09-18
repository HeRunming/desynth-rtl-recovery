#!/usr/bin/env python3
"""test_parse_v_z3.py —— parse_v_z3 / build_wire_env 的自检

重点不是"能跑通", 而是**用 z3 证明 CSE 形式与手工展开形式等价**, 并带反例控制
(故意破坏一根 wire, 判定必须变 sat)。否则一个静默丢子表达式的解析器也会"跑通"。
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import z3
from struct_lift import parse_v_z3, build_wire_env, parse_z3

fails = []


def check(label, cond, extra=""):
    print(f"  {'✅' if cond else '❌'} {label}{('  ' + extra) if extra else ''}")
    if not cond:
        fails.append(label)


print("=== 1. 老解析器 (HAL 形式) 未被破坏 ===")
vm = {}
e = parse_z3("(net_1 & !net_2)", vm)
check("parse_z3 HAL 形式", str(e) != "", str(e))

print("\n=== 2. parse_v_z3 解析 CSE 形式 (_cN wire) ===")
vm2 = {}
wires = [("_c0", "(n1 & n2)"), ("_c1", "(_c0 | n3)")]
env = build_wire_env(wires, vm2)
cse_form = parse_v_z3("(_c1 ^ n4)", vm2, env)
check("解析成功", cse_form is not None, str(cse_form))

print("\n=== 3. 核心: CSE 形式 ≡ 手工展开形式 ===")
vm3 = {}
expanded = parse_v_z3("(((n1 & n2) | n3) ^ n4)", vm3)
s = z3.Solver(); s.add(z3.Xor(cse_form, expanded))
r = s.check()
check("等价判定应为 unsat", r == z3.unsat, str(r))

print("\n=== 4. 反例控制: 破坏 wire 后必须报不等价 ===")
vm4 = {}
env_bad = build_wire_env([("_c0", "(n1 & n2)"), ("_c1", "(_c0 | ~n3)")], vm4)
bad = parse_v_z3("(_c1 ^ n4)", vm4, env_bad)
s2 = z3.Solver(); s2.add(z3.Xor(bad, expanded))
r2 = s2.check()
check("破坏后应为 sat (判定器有效)", r2 == z3.sat, str(r2))

print("\n=== 5. 各种字面量与语法 ===")
vm5 = {}
cases = [
    ("Verilog 常量 1'b1", "(n1 & 1'b1)"),
    ("Verilog 常量 1'b0", "(n1 | 1'b0)"),
    ("HAL 常量 0b1", "(net_5 | 0b1)"),
    ("ITE", "(n1 ? n2 : n3)"),
    ("层级名(带点)", "(genblk1.genblk1.pcpi_mul.resetn & n9)"),
    ("位选", "(data_reg[3] ^ n7)"),
    ("HAL 取反 !", "(!net_8 & n9)"),
    ("Verilog 取反 ~", "(~n8 & n9)"),
    ("n元 AND", "(n1 & n2 & n3 & n4 & n5)"),
    ("嵌套", "((n1 | (n2 & (n3 ^ n4))) & ~n5)"),
]
for label, txt in cases:
    try:
        v = parse_v_z3(txt, vm5)
        check(label, v is not None)
    except Exception as ex:
        check(label, False, f"{type(ex).__name__}: {ex}")

print("\n=== 6. 常量语义正确 (不只是能解析) ===")
vm6 = {}
a1 = parse_v_z3("(n1 & 1'b1)", vm6)
n1 = parse_v_z3("n1", vm6)
s3 = z3.Solver(); s3.add(z3.Xor(a1, n1))
check("(n1 & 1'b1) ≡ n1", s3.check() == z3.unsat)

a2 = parse_v_z3("(n1 | 1'b0)", vm6)
s4 = z3.Solver(); s4.add(z3.Xor(a2, n1))
check("(n1 | 1'b0) ≡ n1", s4.check() == z3.unsat)

a3 = parse_v_z3("(~n8 & n9)", vm6)
a4 = parse_v_z3("(!net_8 & net_9)", vm6)
s5 = z3.Solver(); s5.add(z3.Xor(a3, a4))
check("~n8 与 !net_8 指向同一变量", s5.check() == z3.unsat)

print("\n=== 7. 坏输入必须报错, 不能静默吞掉 ===")
for label, txt in [("尾部残留", "(n1 & n2) n3"), ("未闭合", "(n1 & n2")]:
    try:
        parse_v_z3(txt, {})
        check(label, False, "没报错 (危险: 会静默算错)")
    except Exception:
        check(label, True, "正确抛异常")

print(f"\n{'='*44}")
print(f"结论: {'✅ 全部通过' if not fails else '❌ 失败: ' + ', '.join(fails)}")
sys.exit(0 if not fails else 1)
