#!/usr/bin/env python3
"""
assemble_lifted.py —— 结构升级 RTL 组装器

输入:
  - hal_mechanical.py 提取结果 (精确布尔函数)
  - semantic_naming.py 命名方案
  - struct_lift.py 结构提升结果
输出:
  带结构的可读 RTL:
    - 同步复位: if (rst) q <= 0; else ...
    - 数据寄存器: if (!H) bus <= {D};
    - 计数器: if (en) bus <= bus + 1;
    - 移位寄存器: bus <= {bus[N-2:0], din};
    - 其余: 带语义名的逐位布尔表达式 (fallback)

保证: 只做等价变换 (每次提升都由 struct_lift 用 z3 验证)。
"""
import sys, json, re
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_ports import parse as parse_ports
from alias_map import build_alias_map, resolve
try:
    from struct_lift import lift_bus, z3_to_verilog
except (ImportError, AttributeError):
    from struct_lift_minimal import lift_bus, z3_to_verilog


# ══════════════════════════════════════════════════════════════
# 1. 工具函数
# ══════════════════════════════════════════════════════════════

def hal_to_v(func: str) -> str:
    """HAL 函数字符串 → Verilog (保留 net_id, 供后续 rename 替换)。

    None 或空串 → 1'bx: HAL 对 cone 超阈值的 FF 会写 func=None (mech_cse 存成 "")。
    这种位没有任何 next-state 逻辑可发射, 必须显式给 1'bx —— 早先漏了空串判断,
    结果发射出 `bus[i] <= ;` (33 处), iverilog 直接 Malformed statement。
    用 X 而不是"不发射": 不发射等于声称这一位保持原值, 那是个没有依据的断言;
    X 会在仿真里传播, 让未提取的位无法伪装成验证通过。
    """
    if func is None or not str(func).strip(): return "1'bx"
    v = func.replace("0b1", "1'b1").replace("0b0", "1'b0")
    v = re.sub(r"net_(\d+)", r"n\1", v)
    return v.replace("!", "~")


def scope_cse_wires(func: str, cse_wires: list, scope: str):
    """把 per-function 的 _cN 重命名为全局唯一名, **不做就地展开**。

    mech_cse.py 产出的 _cN 是每个函数独立编号的 (A 的 _c0 与 B 的 _c0 无关),
    直接发射会撞名/未声明。曾经试过就地内联展开 —— 那是错的: cse_wires 里
    _c1 可以引用 _c0 两次, 嵌套链一内联就指数膨胀 (Config A 实测输出 937MB /
    3532 行)。CSE 的意义正是避免这种重复, 内联把它彻底抵消掉了。

    所以这里只加前缀: _cN → {scope}_cN, 引用与定义一起改写, 输出规模与 CSE
    形式同阶 (线性)。

    返回 (改写后的 func, [(改写后的wire名, 改写后的wire定义), ...])。
    wire 列表保持原顺序 —— CSE 保证 _cN 只引用 _cM (M<N), 顺序发射即满足
    Verilog 的先声明后使用。
    """
    if not cse_wires:
        return func, []

    ren = {wn: f"{scope}{wn}" for wn, _ in cse_wires}
    pat = re.compile(r"\b_c\d+\b")
    sub = lambda s: pat.sub(lambda m: ren.get(m.group(0), m.group(0)), s)

    return sub(func), [(ren[wn], sub(we)) for wn, we in cse_wires]


def expand_cse_wires(func: str, cse_wires: list) -> str:
    """就地展开 _cN 引用 (**已弃用**: 会指数膨胀, 见 scope_cse_wires)。

    保留仅供单元测试与小规模调试; 发射路径一律走 scope_cse_wires。
    """
    if not cse_wires:
        return func

    # 按顺序展开所有 wire 定义
    expanded = {}
    for wn, we in cse_wires:
        e = we
        # 替换这个定义中引用的已展开 wire (用正则避免部分匹配 _c0 匹配到 _c01)
        for prev_w, prev_e in expanded.items():
            e = re.sub(rf'\b{re.escape(prev_w)}\b', f"({prev_e})", e)
        expanded[wn] = e

    # 展开原始函数
    result = func
    for wn, e in expanded.items():
        result = re.sub(rf'\b{re.escape(wn)}\b', f"({e})", result)
    return result


def split_bit(nm: str):
    m = re.match(r"^(.*?)\((\d+)\)$", nm)
    return (m.group(1), int(m.group(2))) if m else (nm, None)


# ══════════════════════════════════════════════════════════════
# 2. 构建语义重命名表: net_id → Verilog 名
# ══════════════════════════════════════════════════════════════

def build_rename(mech: dict, buses: list,
                 net_meta: dict, real_ports: set,
                 aliases: dict) -> dict:
    """返回 {'n123': 'signal_name[bit]', ...} 供表达式替换。"""
    rename: dict[str, str] = {}
    ff_q_ids = set(mech["ff_q_ids"])
    input_ids = set(mech["input_net_ids"])
    output_ids = set(mech["output_net_ids"])

    # FF Q 节点 → 语义名[位]
    sem: dict[int, str] = {}
    for b in buses:
        bits = [x for x in b.get("bits", []) if x in ff_q_ids]
        if not bits: continue
        bname = re.sub(r"\W", "_", b.get("name") or "unnamed")
        for i, nid in enumerate(bits):
            sem[nid] = f"{bname}[{i}]" if len(bits) > 1 else bname
    for nid, v in sem.items():
        rename[f"n{nid}"] = v

    # 主输入/输出端口 → 端口名
    for nid in (input_ids | output_ids):
        if nid not in net_meta: continue
        real = resolve(net_meta[nid]["name"], aliases, real_ports)
        base, bit = split_bit(real)
        vname = f"{base}[{bit}]" if bit is not None else base
        rename[f"n{nid}"] = vname

    return rename


def apply_rename(expr_str: str, rename: dict) -> str:
    """把表达式字符串里的 n<id> 替换为语义名。"""
    return re.sub(r"\bn(\d+)\b",
                  lambda m: rename.get(f"n{m.group(1)}", f"n{m.group(1)}"),
                  expr_str)


def negate(expr: str) -> str:
    """求 ~expr, 并在安全时消去双重否定。

    只有当 expr 形如 "(~X)" 且那对外层括号确实包住整个表达式时,
    才能剥成 X。像 "(~a | b)" 也以 "(~" 开头, 但剥出来是 "a | b",
    语义完全不同且仍是合法 Verilog —— 会静默产生错误 RTL。
    """
    if expr.startswith("(~") and expr.endswith(")"):
        # 外层括号必须正好包住整个表达式
        depth = 0
        wraps_all = False
        for i, ch in enumerate(expr):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    wraps_all = (i == len(expr) - 1)
                    break
        if wraps_all:
            inner = expr[2:-1].strip()      # "~" 之后的部分
            # inner 还必须是单个原子: 裸标识符 / 位选 / 完整括号组 /
            # 或再一层 "~..."。若其后还跟着 & | ^ 等运算符, 说明
            # "~" 只作用于第一个操作数, 不能剥。
            if _is_atom(inner):
                return inner
    # 必须给操作数补一层括号: "~" 比 & | ^ 结合更紧,
    # 直接写 "(~a & b)" 会被解析成 "((~a) & b)"。
    return f"(~({expr}))" if not _is_atom(expr) else f"(~{expr})"


def _is_atom(s: str) -> bool:
    """s 是否为单个原子表达式 (其上没有顶层二元运算符)。"""
    s = s.strip()
    if not s:
        return False
    if s.startswith("~") or s.startswith("!"):
        return _is_atom(s[1:])
    if s.startswith("("):
        depth = 0
        for i, ch in enumerate(s):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return i == len(s) - 1    # 括号组占满整串
        return False
    # 裸标识符 / 位选 / 常量, 且不含顶层运算符
    return re.fullmatch(r"[A-Za-z_][\w$]*(?:\[\d+\])?|\d+'[bdh][0-9a-fA-FxzXZ_]+",
                        s) is not None


# ══════════════════════════════════════════════════════════════
# 3. 主组装函数
# ══════════════════════════════════════════════════════════════

def assemble(mech: dict, names: dict, netlist_text: str, top: str,
             rst_net_id=None, verbose=False, lift_cache: dict = None,
             mod_rename: str = None, use_cse: bool = True,
             cse_min_size: int = 3) -> str:
    pinfo = parse_ports(netlist_text)
    aliases = build_alias_map(netlist_text)
    real_in, real_out = pinfo["inputs"], pinfo["outputs"]
    real_ports = set(real_in) | set(real_out)

    net_meta = {int(k): v for k, v in mech["net_meta"].items()}
    input_ids = set(mech["input_net_ids"])
    output_ids = set(mech["output_net_ids"])
    ff_q_ids = set(mech["ff_q_ids"])
    ff_out_set = {n for n in ff_q_ids if n in output_ids}

    buses_raw = names.get("buses", [])

    # ── 去重 bus 名 ──────────────────────────────────────────
    # 注意: 必须检查生成名是否真的未被占用。若 LLM 同时给出 foo 和 foo_1,
    # 单纯的计数器会让第二个 foo 也变成 foo_1 → 重复声明。
    # 与 lift_runner.build_buses 保持一致。
    buses = []
    used_names: set[str] = set()
    for b in buses_raw:
        nm = re.sub(r"\W", "_", b.get("name") or "unnamed")
        final = nm
        suffix = 1
        while final in used_names:
            final = f"{nm}_{suffix}"
            suffix += 1
        used_names.add(final)
        bits = [x for x in b.get("bits", []) if x in ff_q_ids]
        if not bits: continue
        buses.append({**b, "name": final, "bits": bits})

    # 未命名 FF 补丁
    named_ids = {nid for b in buses for nid in b["bits"]}
    for nid in sorted(ff_q_ids):
        if nid not in named_ids:
            buses.append({"name": f"unnamed_{nid}", "bits": [nid],
                          "role": "other", "evidence": ""})

    # ── 端口引用表 ───────────────────────────────────────────
    port_ref: dict[int, str] = {}
    for nid in (input_ids | output_ids):
        if nid not in net_meta: continue
        real = resolve(net_meta[nid]["name"], aliases, real_ports)
        base, bit = split_bit(real)
        port_ref[nid] = f"{base}[{bit}]" if bit is not None else base

    # ── 语义映射 FF → bus位 ───────────────────────────────────
    sem: dict[int, tuple] = {}
    for b in buses:
        for i, nid in enumerate(b["bits"]):
            sem[nid] = (b["name"], i, len(b["bits"]))

    # ── rename 表: n<id> → signal_name ─────────────────────
    rename = build_rename(mech, buses, net_meta, real_ports, aliases)

    # R(nid): 表达式里对某 net 的引用
    def R(nid: int) -> str:
        if nid in input_ids:
            return port_ref.get(nid, f"n{nid}")
        if nid in ff_q_ids:
            nm, i, w = sem[nid]
            return f"{nm}[{i}]" if w > 1 else nm
        return f"n{nid}"

    # per-FF CSE wire 声明池: {wire名: wire定义}, 插入序即拓扑序。
    # 用 dict 而非 list: 发射阶段的 fallback 会用同样的 scope 再调一次 to_v,
    # 同名同定义直接覆盖, 不会产生重复声明。
    ff_cse_decls: dict[str, str] = {}

    def to_v(func: str, cse_wires=None, scope: str = None) -> str:
        """转换 HAL 函数 → Verilog。

        带 cse_wires 时不做内联展开 (会指数膨胀), 而是给 _cN 加 scope 前缀,
        并把 wire 定义登记到 ff_cse_decls 供后续发射。
        """
        if cse_wires and scope:
            f2, decls = scope_cse_wires(func, cse_wires, scope)
            for wn, we in decls:
                ff_cse_decls[wn] = apply_rename(hal_to_v(we), rename)
            return apply_rename(hal_to_v(f2), rename)
        return apply_rename(hal_to_v(func), rename)

    ff_map = {ff["q_id"]: ff for ff in mech["ff_defs"]}
    clk_id = next((n for n in input_ids
                   if "clk" in net_meta.get(n, {}).get("name", "").lower()), None)

    # ── HAL 未提取的位 (cone 超阈值) ──────────────────────────
    #  这些位的 func 是 None/""; hal_to_v 会给 1'bx。必须在 RTL 里显式标注,
    #  否则读者无法区分 "这一位真是 X" 和 "我们没提取出来"。
    skipped_ffs = {ff["q_id"]: ff.get("skipped")
                   for ff in mech["ff_defs"] if ff.get("skipped")}

    def skip_note(nid: int) -> str:
        s = skipped_ffs.get(nid)
        if not s:
            return ""
        hier = (net_meta.get(nid, {}) or {}).get("name", f"net_{nid}")
        return f"   // ⚠ HAL 未提取 ({s}) — {hier}"

    # ── 对每条总线做结构提升 (或用缓存) ────────────────────────
    lift_results: dict[str, dict]
    if lift_cache is not None:
        lift_results = lift_cache
        if verbose:
            lifted = sum(1 for r in lift_results.values() if r.get('lifted'))
            print(f"Using cached lift results: {lifted}/{len(lift_results)} lifted")
    else:
        import time
        lift_results = {}
        for b in buses:
            raw_funcs = [ff_map[nid]["func"] if nid in ff_map else None
                         for nid in b["bits"]]
            t0 = time.time()
            r = lift_bus(b["name"], b["bits"], raw_funcs,
                         rst_net_id=rst_net_id, timeout_budget=15)
            dt = time.time() - t0
            lift_results[b["name"]] = r
            if verbose:
                tag = f"OK {r['type']}" if r['lifted'] else "raw"
                print(f"  lift {b['name']:25s} {tag}  ({dt:.1f}s)", flush=True)

    # ══════════════════════════════════════════════════════
    # CSE: 先把所有要发射的表达式收集起来做全局公共子表达式提取
    # ══════════════════════════════════════════════════════
    #  H = f1 & ~f0 与 D = f0 引用的信号集合几乎完全重合, 内联展开会把
    #  同一份组合逻辑重述多遍。先收集 → CSE → 再发射, always 块里就只剩
    #  结构骨架, 共享的译码项变成 always 块外的 wire。
    #  纯文本重写, 不改变布尔函数; 仍由仿真交叉验证。
    E: dict[str, str] = {}          # 标签 → 已 rename 的表达式

    def collect(tag: str, expr: str):
        if expr:
            E[tag] = apply_rename(expr, rename)

    for b in buses:
        nm = b["name"]
        lr = lift_results.get(nm, {})
        ltype = lr.get("type") if lr.get("lifted") else "raw"
        if ltype == "data_reg":
            collect(f"{nm}#H", lr.get("H_expr"))
            for i, d in enumerate(lr.get("D_exprs") or []):
                collect(f"{nm}#D{i}", d)
        elif ltype == "data_reg_perbit":
            # H_exprs/D_exprs 里可能有 None: 那一位没通过 z3 验证 (部分提升),
            # 回退到该位的原始布尔函数。
            hs = lr.get("H_exprs") or []
            for i, h in enumerate(hs):
                collect(f"{nm}#Hp{i}", h)
            for i, d in enumerate(lr.get("D_exprs") or []):
                collect(f"{nm}#D{i}", d)
            for i, nid in enumerate(b["bits"]):
                if i < len(hs) and hs[i] is None:
                    ff = ff_map.get(nid)
                    if ff is not None:
                        E[f"{nm}#R{nid}"] = to_v(ff["func"],
                                                 ff.get("cse_wires"),
                                                 f"_q{nid}")
        elif ltype == "toggle":
            collect(f"{nm}#T", lr.get("T_expr"))
        elif ltype == "counter":
            collect(f"{nm}#EN", lr.get("en"))
        elif ltype == "shift":
            collect(f"{nm}#DIN", lr.get("din"))
        else:                        # raw: 逐位原始函数
            for nid in b["bits"]:
                ff = ff_map.get(nid)
                if ff is not None:
                    E[f"{nm}#R{nid}"] = to_v(ff["func"],
                                             ff.get("cse_wires"),
                                             f"_q{nid}")

    # 组合输出也一起进池子 —— 它们与 H/D 共享大量译码逻辑
    for od in mech["out_defs"]:
        if not od.get("direct_ff"):
            E[f"@out{od['o_id']}"] = to_v(od["func"],
                                          od.get("cse_wires"),
                                          f"_o{od['o_id']}")

    cse_wires: list[tuple[str, str]] = []
    if use_cse and E:
        try:
            from cse import cse_expressions
            reserved = {b["name"] for b in buses} | real_ports
            pfx = "w"
            while any(n.startswith(pfx) and n[len(pfx):].isdigit()
                      for n in reserved):
                pfx = "_" + pfx
            E2, cse_wires = cse_expressions(E, min_size=cse_min_size,
                                            min_uses=2)
            if pfx != "w":
                ren = {f"w{i}": f"{pfx}{i}" for i in range(len(cse_wires))}
                pat = re.compile(r"\bw(\d+)\b")
                sub = lambda s: pat.sub(
                    lambda m: ren.get(f"w{m.group(1)}", m.group(0)), s)
                cse_wires = [(sub(n), sub(e)) for n, e in cse_wires]
                E2 = {k: sub(v) for k, v in E2.items()}
            E = E2
            if verbose:
                before = sum(len(v) for v in E.values())
                print(f"CSE: {len(cse_wires)} wires 提出")
        except Exception as e:
            if verbose:
                print(f"CSE 跳过 ({type(e).__name__}: {e})")
            cse_wires = []

    def X(tag: str, fallback: str = None) -> str:
        """取 CSE 之后的表达式; 没进池子的回退到原样。"""
        v = E.get(tag)
        return v if v is not None else fallback

    # ══════════════════════════════════════════════════════
    # 生成 RTL
    # ══════════════════════════════════════════════════════
    L = []
    L.append("// " + "=" * 58)
    L.append(f"// {mod_rename or top}  —— 结构升级后的反综合 RTL")
    L.append("// 结构由 HAL 精确提取(SMT级); 每次提升经 z3 等价验证")
    if skipped_ffs:
        L.append("// " + "-" * 58)
        L.append(f"// ⚠ 能力边界: {len(skipped_ffs)}/{len(ff_map)} 位未被 HAL 提取")
        L.append(f"//   (cone 门数超过阈值 {mech.get('threshold', '?')}), 这些位发射为 1'bx")
        L.append("//   并在对应行标注。它们与原设计【不等价】, 仿真验证必须排除或")
        L.append("//   单列为已知差异 —— X 会传播, 不会伪装成通过。")
        _hs = sorted({(net_meta.get(q, {}) or {}).get("name", f"net_{q}").split("(")[0]
                      for q in skipped_ffs})
        for _h in _hs[:6]:
            _n = sum(1 for q in skipped_ffs
                     if (net_meta.get(q, {}) or {}).get("name", "").startswith(_h))
            L.append(f"//   - {_h}: {_n} 位")
    L.append("// " + "=" * 58)
    L.append(f"module {mod_rename or top} (")
    ports = []
    for nm, w in real_in.items():
        ports.append(f"  input  {f'[{w[0]}:{w[1]}] ' if w else ''}{nm}")
    for nm, w in real_out.items():
        ports.append(f"  output {f'[{w[0]}:{w[1]}] ' if w else ''}{nm}")
    L.append(",\n".join(ports))
    L.append(");\n")

    # ── 寄存器声明 ────────────────────────────────────────
    L.append("  // ---- 寄存器声明 ----")
    for b in buses:
        w = len(b["bits"])
        nm = b["name"]
        lr = lift_results.get(nm, {})
        type_tag = lr.get("type", "raw") if lr.get("lifted") else "raw"
        role = b.get("role", "")
        decl = f"  reg [{w-1}:0] {nm};" if w > 1 else f"  reg {nm};"
        L.append(f"{decl:<44}// {type_tag}: {role}")
    L.append("")

    # ── per-FF CSE wire (HAL 提取时就带的, 加了 scope 前缀) ────
    #  这些 wire 必须先于 always 块声明。发射阶段的 fallback 还会往
    #  ff_cse_decls 里补条目, 所以这里只占位, 最后再回填。
    ff_cse_slot = len(L)
    L.append("")   # 占位, 末尾 splice

    # ── 公共子表达式 wire ─────────────────────────────────
    if cse_wires:
        L.append(f"  // ---- 公共子表达式 ({len(cse_wires)} 项, "
                 f"由 CSE 自动提取) ----")
        for wn, we in cse_wires:
            L.append(f"  wire {wn} = {we};")
        L.append("")

    # ── 上电初值 (对齐 gold FF 的 initial Q = 0) ──────────────
    L.append("  // ---- 上电初值 ----")
    L.append("  initial begin")
    for b in buses:
        w = len(b["bits"])
        nm = b["name"]
        L.append(f"    {nm} = {w}'b0;" if w > 1 else f"    {nm} = 1'b0;")
    L.append("  end")
    L.append("")

    # ── always 块 ─────────────────────────────────────────
    if clk_id is not None:
        clk_nm = R(clk_id)
        L.append(f"  always @(posedge {clk_nm}) begin")

        for b in buses:
            nm = b["name"]
            bits = b["bits"]
            N = len(bits)
            lr = lift_results.get(nm, {})
            rst_var_s = lr.get("rst_var")  # e.g. 'n18'
            rst_verilog = apply_rename(rst_var_s, rename) if rst_var_s else None

            L.append(f"    // -- {nm} ({b.get('role','?')}) --")

            # 开头复位 block
            has_rst = lr.get("rst_proven") and rst_verilog
            if has_rst:
                L.append(f"    if (~{rst_verilog}) begin")
                L.append(f"      {nm} <= {N}'b0;")
                L.append( "    end else begin")
                indent = "      "
            else:
                indent = "    "

            ltype = lr.get("type") if lr.get("lifted") else "raw"

            # ── 计数器 ─────────────────────────────────────
            if ltype == "counter":
                inc = lr["inc"]
                en_s = X(f"{nm}#EN") if lr.get("en") else None
                op = f"{nm} + {N}'b1" if inc == 1 else f"{nm} - {N}'b1"
                if en_s:
                    L.append(f"{indent}if ({en_s})")
                    L.append(f"{indent}  {nm} <= {op};")
                else:
                    L.append(f"{indent}{nm} <= {op};")

            # ── 逐位保持/装载 (各位使能不同) ─────────────────
            elif ltype == "data_reg_perbit":
                H_list = lr.get("H_exprs", [])
                D_list = lr.get("D_exprs", [])
                for i, (H_e, D_e) in enumerate(zip(H_list, D_list)):
                    tgt = f"{nm}[{i}]" if N > 1 else nm
                    # H_e is None → 该位未通过 z3 验证 (部分提升), 回退到原始
                    # 布尔函数。不能对 None 调 apply_rename (re.sub 会抛)。
                    if H_e is None or D_e is None:
                        nid = bits[i]
                        ff = ff_map.get(nid)
                        if ff is None:
                            continue
                        rhs = X(f"{nm}#R{nid}",
                                to_v(ff["func"], ff.get("cse_wires"),
                                     f"_q{nid}"))
                        note = skip_note(nid) or "   // 该位未提升 (z3 未证)"
                        L.append(f"{indent}{tgt} <= {rhs};{note}")
                        continue
                    H_v = X(f"{nm}#Hp{i}", apply_rename(H_e, rename))
                    D_v = X(f"{nm}#D{i}", apply_rename(D_e, rename))
                    if H_v == "1'b0":
                        L.append(f"{indent}{tgt} <= {D_v};")
                    elif H_v == "1'b1":
                        L.append(f"{indent}{tgt} <= {tgt};   // 恒定保持")
                    else:
                        L.append(f"{indent}if ({negate(H_v)}) {tgt} <= {D_v};")

            # ── 翻转寄存器 ──────────────────────────────────
            elif ltype == "toggle":
                T_v = X(f"{nm}#T", apply_rename(lr["T_expr"], rename))
                if T_v == "1'b1":
                    L.append(f"{indent}{nm} <= ~{nm};   // 每拍翻转")
                elif T_v == "1'b0":
                    L.append(f"{indent}{nm} <= {nm};   // 恒定保持")
                else:
                    L.append(f"{indent}if ({T_v}) begin")
                    L.append(f"{indent}  {nm} <= ~{nm};")
                    L.append(f"{indent}end")

            # ── 移位寄存器 ──────────────────────────────────
            elif ltype == "shift":
                dir_ = lr["dir"]
                din_s = X(f"{nm}#DIN", apply_rename(lr["din"], rename))
                if dir_ == "left":
                    if N > 1:
                        L.append(f"{indent}{nm} <= {{{nm}[{N-2}:0], {din_s}}};")
                    else:
                        L.append(f"{indent}{nm} <= {din_s};")
                else:
                    if N > 1:
                        L.append(f"{indent}{nm} <= {{{din_s}, {nm}[{N-1}:1]}};")
                    else:
                        L.append(f"{indent}{nm} <= {din_s};")

            # ── 数据寄存器 (H/D) ────────────────────────────
            elif ltype == "data_reg":
                H_expr = lr.get("H_expr", "")
                D_exprs = lr.get("D_exprs", [])
                H_v = X(f"{nm}#H", apply_rename(H_expr, rename))
                DV = [X(f"{nm}#D{i}", apply_rename(d, rename))
                      for i, d in enumerate(D_exprs)]
                # en = ~H; emit: if (en) bus <= {D}
                if H_v == "1'b0":
                    # 无保持条件 → 直接赋值 (H=0 意味着永远装载)
                    if len(D_exprs) == 1:
                        L.append(f"{indent}{nm} <= {DV[0]};")
                    else:
                        rhs = "{" + ", ".join(DV[N-1-i] for i in range(N)) + "}"
                        L.append(f"{indent}{nm} <= {rhs};")
                elif H_v == "1'b1":
                    # 永远保持: H≡1 且恒等式已验证 → next state 恒为现态
                    L.append(f"{indent}{nm} <= {nm};   // 恒定保持")
                else:
                    # if (~H) bus <= {D}
                    en_expr = negate(H_v)
                    if len(D_exprs) == 1:
                        L.append(f"{indent}if ({en_expr}) begin")
                        L.append(f"{indent}  {nm} <= {DV[0]};")
                        L.append(f"{indent}end")
                    else:
                        L.append(f"{indent}if ({en_expr}) begin")
                        for i in range(len(D_exprs)):
                            tgt = f"{nm}[{i}]"
                            L.append(f"{indent}  {tgt} <= {DV[i]};")
                        L.append(f"{indent}end")

            # ── 原始 (逐位布尔, 带语义名) ────────────────────
            else:
                for nid in bits:
                    ff = ff_map.get(nid)
                    if ff is None: continue
                    _, i, w = sem[nid]
                    tgt = f"{nm}[{i}]" if w > 1 else nm
                    rhs = X(f"{nm}#R{nid}",
                            to_v(ff["func"], ff.get("cse_wires"), f"_q{nid}"))
                    note = skip_note(nid)
                    L.append(f"{indent}{tgt} <= {rhs};{note}")

            if has_rst:
                L.append("    end")  # close else

        L.append("  end  // always")
        L.append("")

    # ── 组合输出 ──────────────────────────────────────────
    L.append("  // ---- 输出驱动 ----")
    driven: dict[str, set] = {}
    for od in mech["out_defs"]:
        oid = od["o_id"]
        pr = port_ref.get(oid, f"n{oid}")
        base = pr.split("[")[0]
        bit_ = pr.split("[")[1].rstrip("]") if "[" in pr else None
        driven.setdefault(base, set()).add(int(bit_) if bit_ is not None else None)
        if od.get("direct_ff") and oid in ff_out_set:
            L.append(f"  assign {pr} = {R(oid)};")
        elif not od.get("direct_ff"):
            L.append(f"  assign {pr} = "
                     f"{X(f'@out{oid}', to_v(od['func'], od.get('cse_wires'), f'_o{oid}'))};")

    # 补齐缺失端口。缺失是证据不足，不能用确定的 0 掩盖；显式 X 会
    # 在仿真中传播，并让调用方可以审计 UNKNOWN 来源。
    for nm, w in real_out.items():
        got = driven.get(nm, set())
        if w is None:
            if not got:
                L.append(f"  assign {nm} = 1'bx;   // UNKNOWN: HAL未含此端口")
        else:
            hi, lo = w
            if None in got: continue
            missing = sorted(set(range(lo, hi+1)) - {g for g in got if g is not None})
            if len(missing) == hi - lo + 1:
                L.append(f"  assign {nm} = {hi-lo+1}'bx;   // UNKNOWN: HAL未含此端口")
            else:
                for bb in missing:
                    L.append(f"  assign {nm}[{bb}] = 1'bx;   // UNKNOWN: 该位未驱动")

    L.append("endmodule")

    # ── 回填 per-FF CSE wire 声明 ──────────────────────────────
    #  发射阶段的 fallback 也会往 ff_cse_decls 里补, 所以必须等全部发射完
    #  才知道完整集合。dict 的插入序保持了 CSE 的拓扑序 (_cN 只引用 _cM,
    #  M<N), 顺序发射即满足先声明后使用。
    if ff_cse_decls:
        blk = [f"  // ---- HAL 提取时的共享子表达式 "
               f"({len(ff_cse_decls)} 项, per-FF 作用域) ----"]
        blk += [f"  wire {wn} = {we};" for wn, we in ff_cse_decls.items()]
        blk.append("")
        L[ff_cse_slot:ff_cse_slot + 1] = blk

    return "\n".join(L)


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("mech"); ap.add_argument("names")
    ap.add_argument("netlist"); ap.add_argument("top")
    ap.add_argument("--rst", type=int, default=None)
    ap.add_argument("--cache", default=None,
                    help="pico_lift_results.json (跳过重新 lift)")
    ap.add_argument("--mod", default=None, help="输出模块改名(供 testbench 对比)")
    ap.add_argument("--no-cse", action="store_true", help="关闭公共子表达式提取")
    ap.add_argument("--cse-min-size", type=int, default=3)
    ap.add_argument("-o", default=None, help="输出文件 (默认 stdout)")
    ap.add_argument("-v", action="store_true")
    args = ap.parse_args()
    mech  = json.loads(Path(args.mech).read_text())
    names = json.loads(Path(args.names).read_text())
    nl    = Path(args.netlist).read_text()
    cache = json.loads(Path(args.cache).read_text()) if args.cache else None
    rtl = assemble(mech, names, nl, args.top, rst_net_id=args.rst,
                   verbose=args.v, lift_cache=cache, mod_rename=args.mod,
                   use_cse=not args.no_cse, cse_min_size=args.cse_min_size)
    if args.o:
        Path(args.o).write_text(rtl)
        print(f"wrote {args.o}  ({len(rtl.splitlines())} lines)")
    else:
        print(rtl)
