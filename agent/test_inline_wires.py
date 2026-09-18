#!/usr/bin/env python3
"""
test_inline_wires.py —— _inline_small_wires / build_prompt 自检

重点验证三件事:
 1. 短定义真的被内联了 (之前 reversed 的写法是空转, 看似工作实则没内联)
 2. where 块里列出的长定义是**闭包**: 长定义引用的长定义也要在, 否则出现无定义 _cN
 3. 内联后语义不变 —— 用 z3 证明"内联展开后的表达式 ≡ 原始 wire 形式"
"""
import sys, re
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import z3
from semantic_naming import _inline_small_wires, build_prompt, _CREF
from struct_lift import parse_v_z3, build_wire_env

fails = []


def ck(label, cond, extra=""):
    print(f"  {'✅' if cond else '❌'} {label}{('  ' + extra) if extra else ''}")
    if not cond:
        fails.append(label)


print("=== 1. 短定义被内联 (回归: reversed 写法会一个都不内联) ===")
wires = [("_c0", "(n1 & n2)"), ("_c1", "(_c0 | n3)")]
body, rest = _inline_small_wires("(_c1 ^ n4)", wires, max_len=60)
ck("body 里不再有 _cN", not _CREF.search(body), body)
ck("没有残留 where 项", rest == [], str(rest))
ck("展开正确", body == "(((n1 & n2) | n3) ^ n4)", body)

print("\n=== 2. 长定义保留引用, 且闭包完整 ===")
long_a = "(" + " & ".join(f"n{i}" for i in range(100, 130)) + ")"   # >60 字符
wires2 = [("_c0", "(n1 & n2)"), ("_c1", long_a), ("_c2", "(_c1 | _c0)")]
body2, rest2 = _inline_small_wires("(_c2 & n9)", wires2, max_len=60)
names2 = {w for w, _ in rest2}
refs2 = set(_CREF.findall(body2)) | {r for _, e in rest2 for r in _CREF.findall(e)}
ck("body 仍引用长定义", bool(_CREF.search(body2)), body2[:60])
ck("where 块非空", len(rest2) > 0, f"{len(rest2)} 项")
ck("闭包完整 (无未定义 _cN)", refs2 <= names2,
   f"引用={sorted(refs2)} 定义={sorted(names2)}")

print("\n=== 3. 内联不改变语义 (z3 证明) ===")
for label, b, ws in [
    ("嵌套短定义", "(_c1 ^ n4)", wires),
    ("混合长短", "(_c2 & n9)", wires2),
    ("多次引用同一 wire", "((_c0 & n5) | (_c0 ^ n6))", wires),
]:
    vm_a = {}
    env_a = build_wire_env(ws, vm_a)
    orig = parse_v_z3(b, vm_a, env_a)

    nb, nr = _inline_small_wires(b, ws, max_len=60)
    vm_b = {}
    env_b = build_wire_env(nr, vm_b)
    new = parse_v_z3(nb, vm_b, env_b)

    s = z3.Solver(); s.add(z3.Xor(orig, new))
    r = s.check()
    ck(f"{label} ≡ 原式", r == z3.unsat, str(r))

print("\n=== 4. 反例控制: 破坏内联结果必须被检出 ===")
vm_c = {}
env_c = build_wire_env(wires, vm_c)
orig = parse_v_z3("(_c1 ^ n4)", vm_c, env_c)
bad = parse_v_z3("(((n1 | n2) | n3) ^ n4)", vm_c)   # & 改成 |
s = z3.Solver(); s.add(z3.Xor(orig, bad))
ck("破坏后应 sat", s.check() == z3.sat)

print("\n=== 5. build_prompt: 截断发生在内联之后 ===")
items = [{"q_id": 42, "func": "(_c1 ^ n4)", "cse_wires": wires}]
p = build_prompt(items, "", func_cap=0)
ck("prompt 含展开后的结构", "(n1 & n2)" in p, "")
ck("prompt 不含裸 _cN", "_c0" not in p and "_c1" not in p)
# 长定义时应出现 where 块与提示
items2 = [{"q_id": 43, "func": "(_c2 & n9)", "cse_wires": wires2}]
p2 = build_prompt(items2, "", func_cap=0)
ck("含 where 块", "其中 (共享子表达式)" in p2)
ck("含 _cN 说明", "共享子表达式" in p2)

print("\n=== 6. 无 cse_wires 的函数不受影响 ===")
items3 = [{"q_id": 44, "func": "((n1 & n2) | n3)"}]
p3 = build_prompt(items3, "", func_cap=0)
ck("原样输出", "((n1 & n2) | n3)" in p3)
ck("无 where 块", "其中" not in p3)

print(f"\n{'='*46}")
print(f"结论: {'✅ 全部通过' if not fails else '❌ 失败: ' + ', '.join(fails)}")
sys.exit(0 if not fails else 1)
