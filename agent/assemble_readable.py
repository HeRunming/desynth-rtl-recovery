#!/usr/bin/env python3
"""
assemble_readable.py —— 可读 RTL 组装器

输入:
  - hal_mechanical.py 的提取结果 (精确布尔函数)
  - semantic_naming.py 的命名方案 (LLM 从布尔函数推断的总线/位序/语义名)
输出:
  可读 RTL: 用语义名的向量寄存器 + 按位赋值的 always 块

保证: 只做"重命名 + 位宽聚合", 不改变任何逻辑 -> 必然与机械还原等价,
      再用 verifier 对原网表做形式化/仿真验证兜底。
"""
import sys, json, re
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_ports import parse as parse_ports
from alias_map import build_alias_map, resolve


def hal_to_verilog(func):
    if func is None:
        return "1'bx"
    v = func.replace("0b1", "1'b1").replace("0b0", "1'b0")
    v = re.sub(r"net_(\d+)", r"n\1", v)
    return v.replace("!", "~")


def split_bit(nm):
    m = re.match(r"^(.*?)\((\d+)\)$", nm)
    return (m.group(1), int(m.group(2))) if m else (nm, None)


def assemble(mech, names, netlist_text, top):
    pinfo = parse_ports(netlist_text)
    aliases = build_alias_map(netlist_text)
    real_in, real_out = pinfo["inputs"], pinfo["outputs"]
    real_ports = set(real_in) | set(real_out)

    net_meta = {int(k): v for k, v in mech["net_meta"].items()}
    input_ids = set(mech["input_net_ids"])
    output_ids = set(mech["output_net_ids"])
    ff_q_ids = set(mech["ff_q_ids"])
    ff_out_set = {n for n in ff_q_ids if n in output_ids}

    # --- 端口引用 ---
    port_ref = {}
    for nid in (input_ids | output_ids):
        real = resolve(net_meta[nid]["name"], aliases, real_ports)
        b, bit = split_bit(real)
        port_ref[nid] = f"{b}[{bit}]" if bit is not None else b

    # --- 语义名: net_id -> (bus名, 位号) ---
    sem = {}
    buses = []
    used_names = {}
    for b in names.get("buses", []):
        nm = re.sub(r"\W", "_", b.get("name") or "unnamed")
        if nm in used_names:              # 名字去重
            used_names[nm] += 1
            nm = f"{nm}_{used_names[nm]}"
        else:
            used_names[nm] = 0
        bits = [x for x in b.get("bits", []) if x in ff_q_ids]
        if not bits:
            continue
        buses.append({"name": nm, "bits": bits, "role": b.get("role", "other"),
                      "evidence": b.get("evidence", "")})
        for i, nid in enumerate(bits):
            sem[nid] = (nm, i, len(bits))

    # 未被命名的 FF 兜底
    for nid in sorted(ff_q_ids):
        if nid not in sem:
            nm = f"unnamed_{nid}"
            buses.append({"name": nm, "bits": [nid], "role": "other", "evidence": "未命名"})
            sem[nid] = (nm, 0, 1)

    def R(nid):
        """表达式里对某个 net 的引用。"""
        if nid in input_ids:                       # 主输入 -> 端口名
            return port_ref[nid]
        if nid in ff_q_ids:                        # FF输出 -> 语义名[位]
            nm, i, w = sem[nid]
            return f"{nm}[{i}]" if w > 1 else nm
        return f"n{nid}"                           # 理论上不该出现

    def to_v(func):
        return re.sub(r"n(\d+)", lambda m: R(int(m.group(1))), hal_to_verilog(func))

    clk_id = next((n for n in input_ids if "clk" in net_meta[n]["name"].lower()), None)

    L = []
    L.append("// ============================================================")
    L.append(f"// {top} —— 反综合还原的 RTL")
    L.append("// 结构由 HAL 精确提取(SMT级), 语义命名由 LLM 从布尔函数推断")
    L.append("// ============================================================")
    L.append(f"module {top} (")
    ports = []
    for nm, w in real_in.items():
        ports.append(f"  input  {f'[{w[0]}:{w[1]}] ' if w else ''}{nm}")
    for nm, w in real_out.items():
        ports.append(f"  output {f'[{w[0]}:{w[1]}] ' if w else ''}{nm}")
    L.append(",\n".join(ports))
    L.append(");")
    L.append("")

    # --- 寄存器声明(按语义总线聚合) ---
    L.append("  // ---- 恢复出的寄存器 (按功能分组) ----")
    for b in buses:
        w = len(b["bits"])
        decl = f"  reg [{w-1}:0] {b['name']};" if w > 1 else f"  reg {b['name']};"
        L.append(f"{decl:<44}// {b['role']}: {b['evidence'][:70]}")
    L.append("")

    # --- always 块 ---
    if clk_id is not None:
        L.append(f"  always @(posedge {R(clk_id)}) begin")
        by_bus = {}
        for ff in mech["ff_defs"]:
            nm, i, w = sem[ff["q_id"]]
            by_bus.setdefault(nm, []).append((i, ff))
        for b in buses:
            items = sorted(by_bus.get(b["name"], []))
            if not items:
                continue
            L.append(f"    // {b['name']} ({b['role']})")
            for i, ff in items:
                tgt = f"{b['name']}[{i}]" if len(b["bits"]) > 1 else b["name"]
                L.append(f"    {tgt} <= {to_v(ff['func'])};")
        L.append("  end")
    L.append("")

    # --- 输出驱动 ---
    L.append("  // ---- 输出 ----")
    driven = {}
    for od in mech["out_defs"]:
        oid = od["o_id"]
        pr = port_ref.get(oid, f"n{oid}")
        base = pr.split("[")[0]
        bit = pr.split("[")[1].rstrip("]") if "[" in pr else None
        driven.setdefault(base, set()).add(int(bit) if bit is not None else None)
        if od.get("direct_ff") and oid in ff_out_set:
            L.append(f"  assign {pr} = {R(oid)};")
        elif not od.get("direct_ff"):
            L.append(f"  assign {pr} = {to_v(od['func'])};")
    # 补齐 HAL 模型缺失的输出
    for nm, w in real_out.items():
        got = driven.get(nm, set())
        if w is None:
            if not got:
                L.append(f"  assign {nm} = 1'b0;   // HAL模型未含此端口")
        else:
            hi, lo = w
            if None in got:
                continue
            missing = sorted(set(range(lo, hi + 1)) - {g for g in got if g is not None})
            if len(missing) == hi - lo + 1:
                L.append(f"  assign {nm} = {hi-lo+1}'b0;   // HAL模型未含此端口")
            else:
                for bb in missing:
                    L.append(f"  assign {nm}[{bb}] = 1'b0;   // 该位未驱动")
    L.append("endmodule")
    return "\n".join(L)


if __name__ == "__main__":
    mech = json.loads(Path(sys.argv[1]).read_text())
    names = json.loads(Path(sys.argv[2]).read_text())
    netlist = Path(sys.argv[3]).read_text()
    print(assemble(mech, names, netlist, sys.argv[4]))
