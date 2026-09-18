#!/usr/bin/env python3
"""
test_merge_buses.py —— merge_split_buses 自检 + 真实数据回归

真实回归用试点输出: pcpi_rs1 的 32 位被批次边界切成
  data_register(24 位) + control_data_byte(8 位)
**两半名字完全不同**, 所以只靠名字归一化合不上 —— 必须靠批次切口证据。

用法:
  python3 test_merge_buses.py                       # 只跑单元测试
  python3 test_merge_buses.py <mech.json> <names.json> --cut A,B   # 加真实回归
"""
import sys, json, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from semantic_naming import merge_split_buses, _norm_name

fails = []


def ck(label, cond, extra=""):
    print(f"  {'✅' if cond else '❌'} {label}{('  ' + extra) if extra else ''}")
    if not cond:
        fails.append(label)


def bus(name, role, bits, ev=""):
    return {"name": name, "role": role, "bits": bits, "evidence": ev}


print("=== 1. 同名相邻 → 合并 ===")
bs, n = merge_split_buses([bus("data_reg", "data_reg", [10, 11, 12]),
                           bus("data_reg_2", "data_reg", [13, 14])])
ck("合并成 1 条", len(bs) == 1 and n == 1, f"{len(bs)} 条")
ck("位全在且有序", bs and bs[0]["bits"] == [10, 11, 12, 13, 14],
   str(bs[0]["bits"]) if bs else "")

print("\n=== 2. 异名但落在批次切口 → 也要合并 (试点的真实情形) ===")
bs, n = merge_split_buses(
    [bus("data_register", "data_reg", list(range(629, 653))),
     bus("control_data_byte", "data_reg", list(range(621, 629)))],
    cut_pairs={(628, 629)})
ck("合并成 1 条", len(bs) == 1 and n == 1, f"{len(bs)} 条")
ck("32 位齐全", bs and len(bs[0]["bits"]) == 32,
   f"{len(bs[0]['bits'])} 位" if bs else "")
ck("依据里标注了切口", bs and "批次切口" in (bs[0].get("evidence") or ""))

print("\n=== 3. role 不同 → 绝不合并 ===")
bs, n = merge_split_buses([bus("x", "counter", [1, 2]),
                           bus("x", "data_reg", [3, 4])],
                          cut_pairs={(2, 3)})
ck("保持 2 条", len(bs) == 2 and n == 0, f"{len(bs)} 条")

print("\n=== 4. 同名但相隔很远 → 不合并 (防误并无关总线) ===")
bs, n = merge_split_buses([bus("flag", "flag", [10]),
                           bus("flag", "flag", [9000])])
ck("保持 2 条", len(bs) == 2 and n == 0, f"{len(bs)} 条")

print("\n=== 5. 不丢位、不重复 (任何情况下) ===")
inp = [bus("a", "data_reg", [1, 2, 3]), bus("b", "data_reg", [4, 5]),
       bus("c", "counter", [6]), bus("a", "data_reg", [100, 101])]
bs, n = merge_split_buses(inp, cut_pairs={(3, 4)})
before = sorted(x for b in inp for x in b["bits"])
after = sorted(x for b in bs for x in b["bits"])
ck("位集合完全一致", before == after, f"{len(before)} → {len(after)}")
ck("无重复位", len(after) == len(set(after)))

print("\n=== 6. 空输入 / 空 bits 不崩 ===")
bs, n = merge_split_buses([])
ck("空列表", bs == [] and n == 0)
bs, n = merge_split_buses([bus("x", "r", []), bus("y", "r", [1])])
ck("跳过空 bits", len(bs) == 1)

print("\n=== 7. _norm_name ===")
for a, b in [("data_register_2", "data_register"), ("Data_Reg_hi", "data_reg"),
             ("x_lsb", "x"), ("mul_accumulator", "mul_accumulator")]:
    ck(f"{a} → {b}", _norm_name(a) == b, _norm_name(a))

# ── 真实数据回归 ──────────────────────────────────────────────
ap = argparse.ArgumentParser()
ap.add_argument("mech", nargs="?"); ap.add_argument("names", nargs="?")
ap.add_argument("--cut", default="628,629")
args, _ = ap.parse_known_args()

if args.mech and args.names:
    print("\n=== 8. 真实数据回归 (试点输出) ===")
    sys.path.insert(0, str(Path(__file__).parent))
    from eval_naming import family
    m = json.loads(Path(args.mech).read_text())
    nm = {int(k): v.get("name", "") for k, v in m["net_meta"].items()}
    plan = json.loads(Path(args.names).read_text())
    raw = plan["buses"]
    a, b = (int(x) for x in args.cut.split(","))
    out, n = merge_split_buses(raw, cut_pairs={(a, b)})
    print(f"  {len(raw)} → {len(out)} 条 bus ({n} 次合并)")
    for x in out:
        fams = {family(nm.get(int(i), "")) for i in x["bits"]}
        print(f"    {x['name'][:26]:26} {len(x['bits']):3} 位  真名族={sorted(fams)}")
    # pcpi_rs1 应该合成一条 32 位
    rs1 = [x for x in out
           if {family(nm.get(int(i), "")) for i in x["bits"]} == {"pcpi_rs1"}]
    ck("pcpi_rs1 合成单条", len(rs1) == 1, f"{len(rs1)} 条")
    ck("且为 32 位", bool(rs1) and len(rs1[0]["bits"]) == 32,
       f"{len(rs1[0]['bits'])} 位" if rs1 else "")
    ids_before = sorted(int(i) for x in raw for i in x["bits"])
    ids_after = sorted(int(i) for x in out for i in x["bits"])
    ck("位无增减", ids_before == ids_after)

print(f"\n{'='*46}")
print(f"结论: {'✅ 全部通过' if not fails else '❌ 失败: ' + ', '.join(fails)}")
sys.exit(0 if not fails else 1)
