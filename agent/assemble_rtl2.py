#!/usr/bin/env python3
"""
assemble_rtl2.py —— 机械等价还原组装器 (v2, 修复端口问题)

相比v1的改进:
 1. 从网表 module 声明解析**真实端口列表**(不依赖HAL的global net查询)
 2. 用 assign 别名映射把 HAL 名翻译回真实端口名
    (HAL会保留 dbg_mem_valid 而丢弃真实端口 mem_valid)
 3. 补齐 HAL 模型里缺失/悬空的端口(如未使用的 irq/trace_*), 保证端口列表与gold一致
"""
import sys, json, re
sys.path.insert(0, ".")
from parse_ports import parse as parse_ports
from alias_map import build_alias_map, resolve


def hal_func_to_verilog(func):
    if func is None:
        return "1'bx"
    v = func.replace("0b1", "1'b1").replace("0b0", "1'b0")
    v = re.sub(r"net_(\d+)", r"n\1", v)
    return v.replace("!", "~")


def split_bit(nm):
    m = re.match(r"^(.*?)\((\d+)\)$", nm)
    return (m.group(1), int(m.group(2))) if m else (nm, None)


def assemble(data, netlist_text, top):
    pinfo = parse_ports(netlist_text)
    aliases = build_alias_map(netlist_text)
    real_in, real_out = pinfo["inputs"], pinfo["outputs"]

    net_meta = {int(k): v for k, v in data["net_meta"].items()}
    input_ids = set(data["input_net_ids"])
    output_ids = set(data["output_net_ids"])
    ff_q_ids = set(data["ff_q_ids"])

    # net_id -> 真实信号引用
    real_port_names = set(real_in) | set(real_out)
    ref = {}
    for nid in (input_ids | output_ids):
        halname = net_meta[nid]["name"]
        realname = resolve(halname, aliases, real_port_names)   # 端口感知的别名翻译
        base, bit = split_bit(realname)
        ref[nid] = f"{base}[{bit}]" if bit is not None else base
    ff_out_set = {nid for nid in ff_q_ids if nid in output_ids}
    for nid in ff_q_ids:
        if nid not in ref:
            ref[nid] = f"n{nid}"

    def R(nid):
        # FF驱动的输出: 表达式里引用内部reg, 避免反馈路径断裂
        if nid in ff_out_set:
            return f"n{nid}_r"
        return ref.get(nid, f"n{nid}")

    clk_id = next((nid for nid in input_ids
                   if "clk" in net_meta[nid]["name"].lower()), None)

    def to_v(func):
        v = hal_func_to_verilog(func)
        return re.sub(r"n(\d+)", lambda m: R(int(m.group(1)))
                      if int(m.group(1)) in ref else f"n{m.group(1)}", v)

    lines = [f"module {top} ("]
    ports = []
    for nm, w in real_in.items():
        ws = f"[{w[0]}:{w[1]}] " if w else ""
        ports.append(f"  input  {ws}{nm}")
    for nm, w in real_out.items():
        ws = f"[{w[0]}:{w[1]}] " if w else ""
        ports.append(f"  output {ws}{nm}")
    lines.append(",\n".join(ports))
    lines.append(");")

    # 内部FF reg
    for nid in sorted(ff_q_ids):
        if nid in ff_out_set:
            lines.append(f"  reg n{nid}_r; // {net_meta[nid]['name']}")
        elif nid not in input_ids and nid not in output_ids:
            lines.append(f"  reg n{nid}; // {net_meta[nid]['name']}")

    # always
    if clk_id is not None:
        lines.append(f"  always @(posedge {R(clk_id)}) begin")
        for ff in data["ff_defs"]:
            qid = ff["q_id"]
            tgt = f"n{qid}_r" if qid in ff_out_set else R(qid)
            lines.append(f"    {tgt} <= {to_v(ff['func'])};")
        lines.append("  end")

    # 输出驱动。记录每个端口基名已被驱动的位, 便于补齐未驱动的位
    driven_bits = {}          # 端口基名 -> set(位号 或 None表示整体)
    for od in data["out_defs"]:
        oid = od["o_id"]
        pr = ref.get(oid, f"n{oid}")
        b, bit = (pr.split("[")[0], pr.split("[")[1].rstrip("]")) if "[" in pr else (pr, None)
        driven_bits.setdefault(b, set()).add(int(bit) if bit is not None else None)
        if od.get("direct_ff") and oid in ff_out_set:
            lines.append(f"  assign {pr} = n{oid}_r;")
        elif not od.get("direct_ff"):
            lines.append(f"  assign {pr} = {to_v(od['func'])};")

    # 补齐: HAL模型里完全缺失或部分位未驱动的输出端口, 绑0保证端口一致且无悬空
    for nm, w in real_out.items():
        got = driven_bits.get(nm, set())
        if w is None:
            if not got:
                lines.append(f"  assign {nm} = 1'b0; // HAL模型未含此端口")
        else:
            hi, lo = w
            allbits = set(range(lo, hi + 1))
            missing = sorted(allbits - {g for g in got if g is not None})
            if None in got:
                continue                      # 整体已驱动
            if len(missing) == len(allbits):
                lines.append(f"  assign {nm} = {hi-lo+1}'b0; // HAL模型未含此端口")
            else:
                for b in missing:
                    lines.append(f"  assign {nm}[{b}] = 1'b0; // 该位在HAL模型中未驱动")

    lines.append("endmodule")
    return "\n".join(lines)


if __name__ == "__main__":
    data = json.load(open(sys.argv[1]))
    netlist_text = open(sys.argv[2]).read()
    top = sys.argv[3]
    print(assemble(data, netlist_text, top))
