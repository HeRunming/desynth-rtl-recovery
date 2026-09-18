#!/usr/bin/env python3
"""
assemble_rtl.py —— 把 HAL 机械提取的布尔函数组装成 flat Verilog RTL

关键: HAL 布尔函数里的 net_<id> 是叶子变量(主输入 或 FF的Q输出)。
把每个 FF 的 Q 声明为 reg, 主输入声明为 input, 组装出:
  - 时钟沿更新: q <= <下一状态函数>
  - 输出: assign out = <函数>
生成的 RTL 数学上等价于原网表(因函数是SMT级精确提取)。
"""
import sys, json, re


def hal_func_to_verilog(func, all_clk_input=None):
    """把 HAL 布尔函数语法转成 Verilog 表达式。
    HAL:  &  |  ^  !  ()  net_<id>  0b1/0b0
    Verilog: &  |  ^  ~  ()  n<id>   1'b1/1'b0"""
    if func is None:
        return "1'bx"
    v = func
    v = v.replace("0b1", "1'b1").replace("0b0", "1'b0")
    # net_123 -> n123
    v = re.sub(r"net_(\d+)", r"n\1", v)
    # 逻辑非 ! -> ~ (HAL的!是按位非, 单bit等价)
    v = v.replace("!", "~")
    return v


def port_name(raw):
    """把 HAL 端口名转成 Verilog 端口引用。
    tx_data(6) -> tx_data[6]; tx_start -> tx_start
    等价检查按端口名对齐, 所以必须用原始名字。"""
    m = re.match(r"^(.*)\((\d+)\)$", raw)
    if m:
        return m.group(1), int(m.group(2))   # (基名, 位下标)
    return raw, None


def assemble(data, top="top"):
    net_meta = {int(k): v for k, v in data["net_meta"].items()}
    input_ids = set(data["input_net_ids"])
    output_ids = set(data["output_net_ids"])
    ff_q_ids = set(data["ff_q_ids"])

    # net_id -> Verilog 引用名。端口net用原始名(等价检查按名对齐), 内部net用 n<id>
    ref = {}          # net_id -> Verilog表达式(如 tx_data[6] 或 n178)
    buses = {}        # 基名 -> {max位, is_input}
    for nid in (input_ids | output_ids):
        base, bit = port_name(net_meta[nid]["name"])
        if bit is None:
            ref[nid] = base
            buses.setdefault(base, {"max": None, "ids": []})
        else:
            ref[nid] = f"{base}[{bit}]"
            b = buses.setdefault(base, {"max": -1, "ids": []})
            b["max"] = max(b["max"], bit)
        buses[base]["ids"].append(nid)
    # 内部FF net(非端口)
    for nid in ff_q_ids:
        if nid not in input_ids and nid not in output_ids:
            ref[nid] = f"n{nid}"

    # FF直接驱动的输出: 表达式里必须引用其内部reg(n<id>_r), 而非端口wire,
    # 否则FF反馈路径断裂(always写reg, 下游却读组合wire)
    ff_out_set = {nid for nid in ff_q_ids if nid in output_ids}

    def R(nid):
        if nid in ff_out_set:
            return f"n{nid}_r"
        return ref.get(nid, f"n{nid}")

    # 时钟net
    clk_id = None
    for nid in input_ids:
        if "clk" in net_meta[nid]["name"].lower() or "clock" in net_meta[nid]["name"].lower():
            clk_id = nid; break

    def to_verilog(func):
        v = hal_func_to_verilog(func)
        # 把 n<id> 里属于端口的替换成端口引用
        def repl(m):
            nid = int(m.group(1))
            return R(nid) if nid in ref else f"n{nid}"
        return re.sub(r"n(\d+)", repl, v)

    # 端口声明(按bus聚合)
    in_bases, out_bases = {}, {}
    for nid in input_ids:
        base, bit = port_name(net_meta[nid]["name"])
        in_bases.setdefault(base, -1)
        if bit is not None: in_bases[base] = max(in_bases[base], bit)
        else: in_bases[base] = None
    for nid in output_ids:
        base, bit = port_name(net_meta[nid]["name"])
        out_bases.setdefault(base, -1)
        if bit is not None: out_bases[base] = max(out_bases[base], bit)
        else: out_bases[base] = None

    lines = [f"module {top} ("]
    ports = []
    for base, mx in sorted(in_bases.items()):
        w = f"[{mx}:0] " if mx not in (None, -1) else ""
        ports.append(f"  input  {w}{base}")
    for base, mx in sorted(out_bases.items()):
        w = f"[{mx}:0] " if mx not in (None, -1) else ""
        ports.append(f"  output {w}{base}")
    lines.append(",\n".join(ports))
    lines.append(");")

    # 内部FF reg (非端口)
    ff_internal = [nid for nid in ff_q_ids if nid not in output_ids and nid not in input_ids]
    for nid in ff_internal:
        lines.append(f"  reg n{nid}; // {net_meta[nid]['name']}")
    # FF直接驱动输出: 用 reg + assign
    ff_out = [nid for nid in ff_q_ids if nid in output_ids]
    for nid in ff_out:
        lines.append(f"  reg n{nid}_r; // FF输出 {net_meta[nid]['name']}")

    # always
    if clk_id is not None:
        lines.append(f"  always @(posedge {R(clk_id)}) begin")
        for ff in data["ff_defs"]:
            qid = ff["q_id"]
            expr = to_verilog(ff["func"])
            tgt = f"n{qid}_r" if qid in ff_out else R(qid)
            lines.append(f"    {tgt} <= {expr};")
        lines.append("  end")

    # 输出: 端口名用原始名(ref), FF输出从内部reg引出
    for od in data["out_defs"]:
        oid = od["o_id"]
        portref = ref.get(oid, f"n{oid}")
        if od.get("direct_ff"):
            if oid in ff_out:
                lines.append(f"  assign {portref} = n{oid}_r;")
        else:
            lines.append(f"  assign {portref} = {to_verilog(od['func'])};")

    lines.append("endmodule")
    return "\n".join(lines)


if __name__ == "__main__":
    data = json.load(open(sys.argv[1]))
    top = sys.argv[2] if len(sys.argv) > 2 else "top"
    print(assemble(data, top))
