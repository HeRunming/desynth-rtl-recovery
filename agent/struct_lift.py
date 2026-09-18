#!/usr/bin/env python3
"""
struct_lift.py —— 结构升级引擎 (v2)

将 HAL 精确提取的逐位布尔函数提升为高层运算符:
  reset  : if (rst) q <= 0
  data   : if (en)  q <= d       (en 可以是复合表达式)
  counter: q <= q + 1 / q - 1   (含可选 en)
  shift  : q <= {q[N-2:0], din} / {din, q[N-1:1]}

关键方法 — H/D 正则分解:
  对任意单比特 FF next-state f(q, inputs):
    H(inputs) = f(1,inputs) XOR f(0,inputs)   ← "保持条件"(输出随 q 变化)
    D(inputs) = f(0,inputs)                    ← "装载数据"
    f(q,inputs) = (H AND q) OR (NOT H AND D)  (恒等式, z3 可证)
  因此可以无条件地写:  if (!H) q <= D;
  (当 H 是 ~wr_en 时即变为 if (wr_en) q <= d)

等价性: 每次提升都用 z3 SAT 验证, 不允许改变逻辑。
"""

import re, sys, os
from typing import Dict, List, Optional, Tuple, Any

# ── z3 bootstrap ────────────────────────────────────────────────
import builtins
_Z3DIR = os.environ.get(
    "Z3_DIR", "/Users/blackbox/try_hai/tools/z3-4.13.4-arm64-osx-13.7.1")
sys.path.insert(0, os.path.join(_Z3DIR, "bin", "python"))
builtins.Z3_LIB_DIRS = [os.path.join(_Z3DIR, "bin")]
import z3
# ────────────────────────────────────────────────────────────────


# ══════════════════════════════════════════════════════════════
# § 1. HAL 函数字符串 → z3.BoolRef
# ══════════════════════════════════════════════════════════════

"""Verilog/CSE 形式的 token: 与 cse.py 的 TOK 保持一致, 外加 _cN wire 引用。
注意 net_\\d+ 必须排在 n\\d+ 之前, 否则 'net_12' 会被切成别的东西。"""
_VTOK = re.compile(r"""
      \d+'[bdh][0-9a-fA-FxzXZ_]+     # 1'b1
    | 0b[01]                          # HAL 常量 (mech_cse 已换掉, 保险)
    | net_\d+ | _c\d+ | n\d+          # 变量: HAL名 / CSE wire / Verilog名
    | [A-Za-z_][\w$.]*(?:\[\d+\])?    # 其它标识符 (层级名等)
    | ~ | ! | & | \| | \^ | \( | \) | \? | : | ==
""", re.X)

_TRUE = {"1'b1", "0b1"}
_FALSE = {"1'b0", "0b0"}


def parse_v_z3(text: str,
               var_map: Dict[int, z3.BoolRef],
               wire_env: Optional[Dict[str, z3.BoolRef]] = None) -> z3.BoolRef:
    """解析 **Verilog/CSE 形式** 的布尔表达式为 z3。

    与 parse_z3 (HAL 形式: net_123 / ! / 0b1) 分开实现, 因为 mech_cse.py 产出的
    是 Verilog 形式 (n123 / ~ / 1'b1) 且带 _cN wire 引用。这个实现是从
    verify_cse_equiv.py 里那个**已被 yosys miter+SAT 交叉验证过**的解析器搬过来的。

    wire_env: {wire名 → 已建好的 z3 表达式}。必须按拓扑序预先建好 —— CSE 保证
    wN 只引用 wM (M<N), 所以顺序遍历即可。传入共享的子表达式对 z3 是好事
    (结构共享), 不是负担。
    """
    toks = _VTOK.findall(text)
    pos = [0]
    env = wire_env or {}

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else None

    def take():
        t = toks[pos[0]]; pos[0] += 1; return t

    def leaf(t: str) -> z3.BoolRef:
        if t in _TRUE:  return z3.BoolVal(True)
        if t in _FALSE: return z3.BoolVal(False)
        if t in env:    return env[t]
        m = re.fullmatch(r"(?:net_|n)(\d+)", t)
        if m:
            nid = int(m.group(1))
            if nid not in var_map:
                var_map[nid] = z3.Bool(f"n{nid}")
            return var_map[nid]
        # 其它裸标识符 (层级名/端口名): 按名字建自由变量
        v = env.get(t)
        if v is None:
            v = z3.Bool(t); env[t] = v
        return v

    def fold(op: str, kids: list) -> z3.BoolRef:
        if len(kids) == 1:
            return kids[0]
        if op == "&": return z3.And(*kids)
        if op == "|": return z3.Or(*kids)
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

    def expr() -> z3.BoolRef:
        t = peek()
        if t is None:
            raise ValueError(f"意外结束: {text[:60]}")
        if t in ("~", "!"):
            take(); return z3.Not(expr())
        if t == "(":
            take(); first = expr(); nxt = peek()
            if nxt == ")":
                take(); return first
            if nxt == "?":
                take(); th = expr()
                if take() != ":":
                    raise ValueError("ITE 缺 ':'")
                el = expr()
                if take() != ")":
                    raise ValueError("ITE 缺 ')'")
                return z3.If(first, th, el)
            op = nxt; kids = [first]
            while peek() == op:
                take(); kids.append(expr())
            if take() != ")":
                raise ValueError(f"缺 ')' in {text[:60]}")
            return fold(op, kids)
        return leaf(take())

    r = expr()
    if pos[0] != len(toks):
        raise ValueError(f"尾部残留 {toks[pos[0]:pos[0]+4]}")
    return r


def build_wire_env(cse_wires, var_map) -> Dict[str, z3.BoolRef]:
    """按拓扑序把 [(名, 表达式)] 建成 {名 → z3 表达式}。"""
    env: Dict[str, z3.BoolRef] = {}
    for wn, we in (cse_wires or []):
        env[wn] = parse_v_z3(we, var_map, env)
    return env


def parse_z3(func: str, var_map: Dict[int, z3.BoolRef]) -> z3.BoolRef:
    """解析 HAL 布尔函数字符串为 z3.BoolRef。未知 net_id 自动加入 var_map。"""
    tokens: list[str] = []
    for m in re.finditer(r"net_(\d+)|0b[01]|\(|\)|&&|&|\|\||\||!|\^", func):
        tokens.append(m.group(0))

    pos = 0

    def peek():
        return tokens[pos] if pos < len(tokens) else None

    def consume():
        nonlocal pos; t = tokens[pos]; pos += 1; return t

    def parse_or():
        left = parse_xor()
        while peek() in ('|', '||'):
            consume(); left = z3.Or(left, parse_xor())
        return left

    def parse_xor():
        left = parse_and()
        while peek() == '^':
            consume(); left = z3.Xor(left, parse_and())
        return left

    def parse_and():
        left = parse_unary()
        while peek() in ('&', '&&'):
            consume(); left = z3.And(left, parse_unary())
        return left

    def parse_unary():
        if peek() == '!':
            consume(); return z3.Not(parse_unary())
        return parse_primary()

    def parse_primary():
        t = peek()
        if t == '(':
            consume(); e = parse_or(); consume(); return e
        if t == '0b1':
            consume(); return z3.BoolVal(True)
        if t == '0b0':
            consume(); return z3.BoolVal(False)
        m = re.match(r'^net_(\d+)$', t)
        if m:
            consume(); nid = int(m.group(1))
            if nid not in var_map:
                var_map[nid] = z3.Bool(f"n{nid}")
            return var_map[nid]
        raise ValueError(f"unexpected token {t!r} at pos {pos}")

    return parse_or()


# ══════════════════════════════════════════════════════════════
# § 2. z3.BoolRef → Verilog 表达式字符串
# ══════════════════════════════════════════════════════════════

def z3_to_verilog(expr: z3.BoolRef,
                  rename: Optional[Dict[str, str]] = None) -> str:
    """将 z3 表达式递归转为 Verilog 运算符字符串。
    rename: z3 变量名 (如 'n123') → Verilog 名 (如 'cycle_counter[2]')。
    """
    if z3.is_true(expr):  return "1'b1"
    if z3.is_false(expr): return "1'b0"

    # 叶子节点 (变量 or bool constant after simplify)
    if z3.is_const(expr):
        nm = str(expr)
        return rename.get(nm, nm) if rename else nm

    n = expr.num_args()

    if z3.is_not(expr):
        inner = z3_to_verilog(expr.arg(0), rename)
        return f"(~{inner})"

    if z3.is_and(expr):
        parts = [z3_to_verilog(expr.arg(i), rename) for i in range(n)]
        return "(" + " & ".join(parts) + ")"

    if z3.is_or(expr):
        parts = [z3_to_verilog(expr.arg(i), rename) for i in range(n)]
        return "(" + " | ".join(parts) + ")"

    # z3 represents XOR as: (a | b) & (~a | ~b) after simplify, or directly
    if expr.decl().name() == 'xor':
        parts = [z3_to_verilog(expr.arg(i), rename) for i in range(n)]
        return "(" + " ^ ".join(parts) + ")"

    # ITE (if-then-else)
    if expr.decl().name() == 'if':
        c = z3_to_verilog(expr.arg(0), rename)
        t = z3_to_verilog(expr.arg(1), rename)
        e = z3_to_verilog(expr.arg(2), rename)
        return f"({c} ? {t} : {e})"

    # Equality (used by simplify sometimes)
    if expr.decl().name() in ('=', '=='):
        a0 = z3_to_verilog(expr.arg(0), rename)
        a1 = z3_to_verilog(expr.arg(1), rename)
        return f"({a0} == {a1})"

    # 后备: 原始 HAL 函数字符串 (不应出现, 但保险)
    raw = str(expr).replace('\n', ' ')
    return raw


# ══════════════════════════════════════════════════════════════
# § 3. SAT 等价验证
# ══════════════════════════════════════════════════════════════

def z3_equiv(e1: z3.BoolRef, e2: z3.BoolRef,
             timeout_ms: int = 4000) -> bool:
    """True 当且仅当 e1 ≡ e2 (无反例); 超时视为 False。"""
    s = z3.Solver(); s.set("timeout", timeout_ms)
    s.add(z3.Xor(e1, e2))
    return s.check() == z3.unsat


# ══════════════════════════════════════════════════════════════
# § 4. H/D 分解 (正则保持/装载分离)
# ══════════════════════════════════════════════════════════════

def extract_hd(func_z3: z3.BoolRef,
               q_var: z3.BoolRef) -> Tuple[z3.BoolRef, z3.BoolRef]:
    """
    对 next-state f(q, inputs) 做 Shannon 展开:
        f(q) = (q & f1) | (~q & f0)      f1 = f|_{q=1}, f0 = f|_{q=0}
    要写成 "保持/装载" 形式 `if (~H) q <= D`, 需要
        f(q) = (H & q) | (~H & D)
    对照 Shannon 展开可知这要求:
        H = f1 & ~f0        (保持: q=1→1, q=0→0)
        D = f0              (装载值)
    注意 H 不能用 f1 XOR f0: 那会把 "保持" 和 "翻转" 混为一谈
    (翻转时 f1=0,f0=1 也满足 XOR=1, 但恒等式给出 q 而真值是 ~q)。
    调用方必须验证 f ≡ (H & q) | (~H & D); 该恒等式并非无条件成立。
    """
    f1 = z3.simplify(z3.substitute(func_z3, (q_var, z3.BoolVal(True))))
    f0 = z3.simplify(z3.substitute(func_z3, (q_var, z3.BoolVal(False))))
    H = z3.simplify(z3.And(f1, z3.Not(f0)))
    D = f0
    return H, D


# ══════════════════════════════════════════════════════════════
# § 5. 同步复位检测
# ══════════════════════════════════════════════════════════════

def _peel_one_reset(func_z3: z3.BoolRef,
                    rst: z3.BoolRef,
                    active_high: bool = True) -> Optional[z3.BoolRef]:
    """检测 func 在 rst=active_high 时是否恒为 0。
    active_high=True:  rst=1 → func==0 (普通高有效复位)
    active_high=False: rst=0 → func==0 (低有效, 如 resetn)
    成功返回 body = func|_{rst=~active_high}; 失败返回 None。
    """
    rst_on  = z3.BoolVal(active_high)
    rst_off = z3.BoolVal(not active_high)
    s = z3.Solver(); s.set("timeout", 2000)
    s.add(z3.substitute(func_z3, (rst, rst_on)))
    if s.check() != z3.unsat:
        return None
    return z3.simplify(z3.substitute(func_z3, (rst, rst_off)))


def peel_reset(funcs_z3: List[z3.BoolRef],
               var_map: Dict[int, z3.BoolRef],
               bits: List[int],
               rst_net_id: Optional[int] = None
               ) -> Tuple[Optional[z3.BoolRef], List[z3.BoolRef]]:
    """
    尝试从所有位剥离同步复位项。
    成功返回 (rst_var, body_funcs); 失败返回 (None, funcs_z3)。
    优先使用调用方指定的 rst_net_id。
    """
    bit_set = set(bits)

    def try_rst(cand: z3.BoolRef, active_high: bool):
        bodies = []
        for fz in funcs_z3:
            b = _peel_one_reset(fz, cand, active_high=active_high)
            if b is None:
                return None
            bodies.append(b)
        return bodies

    candidates: List[z3.BoolRef] = []
    if rst_net_id is not None and rst_net_id in var_map:
        candidates.append(var_map[rst_net_id])
    for nid, v in var_map.items():
        if nid not in bit_set:
            candidates.append(v)

    seen: set = set()
    for cand in candidates:
        key = str(cand)
        if key in seen:
            continue
        seen.add(key)
        for polarity in (True, False):       # try active-high then active-low
            bodies = try_rst(cand, polarity)
            if bodies is not None:
                return cand, bodies

    return None, funcs_z3


# ══════════════════════════════════════════════════════════════
# § 6. 计数器检测 (bit-vector SAT)
# ══════════════════════════════════════════════════════════════

def try_lift_counter(bits: List[int],
                     body_funcs: List[z3.BoolRef],
                     q_vars: List[z3.BoolRef],
                     var_map: Dict[int, z3.BoolRef]) -> Optional[Dict]:
    """
    用 bit-vector 语义检测 q <= (en ? q+inc : q),  inc in {+1, -1}。
    en 可以是任意单 net 或 None (自由计数)。
    返回 {'type':'counter','inc':±1,'en':str_or_None,'width':N} 或 None。
    """
    N = len(bits)
    if N < 2 or N > 32:
        return None

    # 构造 N-bit bitvector, LSB = q_vars[0]
    def make_q_bv():
        parts = [z3.If(q_vars[N-1-i], z3.BitVecVal(1, 1), z3.BitVecVal(0, 1))
                 for i in range(N)]
        return z3.Concat(*parts)

    def check(inc: int, en_var: Optional[z3.BoolRef]) -> bool:
        q_bv = make_q_bv()
        inc_bv = z3.BitVecVal(inc % (1 << N), N)
        sum_bv = q_bv + inc_bv
        all_eq = True
        for i in range(N):
            bit_i_set = (z3.Extract(i, i, sum_bv) == z3.BitVecVal(1, 1))
            if en_var is not None:
                expected = z3.If(en_var, bit_i_set, q_vars[i])
            else:
                expected = bit_i_set
            if not z3_equiv(expected, body_funcs[i], timeout_ms=3000):
                all_eq = False; break
        return all_eq

    body_str0 = str(body_funcs[0])
    # 候选 en: 在第0位函数中出现的非 Q 变量
    en_candidates = [
        v for nid, v in var_map.items()
        if nid not in set(bits) and str(v) in body_str0
    ]

    for inc in (1, -1):
        # 无 enable (自由计数)
        if check(inc, None):
            return {"type": "counter", "inc": inc, "en": None, "width": N}
        # 有 enable
        for ev in en_candidates:
            if check(inc, ev):
                return {"type": "counter", "inc": inc,
                        "en": str(ev), "width": N}
    return None


# ══════════════════════════════════════════════════════════════
# § 7. 移位寄存器检测
# ══════════════════════════════════════════════════════════════

def try_lift_shift(bits: List[int],
                   body_funcs: List[z3.BoolRef],
                   q_vars: List[z3.BoolRef],
                   var_map: Dict[int, z3.BoolRef]) -> Optional[Dict]:
    """
    检测 q[i] <= q[i-1] (left shift, MSB fill) 或 q[i] <= q[i+1] (right shift)。
    边界 bit 接受任意输入 net 作为串行输入 din。
    """
    N = len(bits)
    if N < 2:
        return None

    for direction in ('left', 'right'):
        boundary = 0 if direction == 'left' else N - 1
        src = (lambda i: q_vars[i - 1]) if direction == 'left' \
              else (lambda i: q_vars[i + 1])
        ok = True
        for i in range(N):
            if i == boundary:
                continue
            if not z3_equiv(src(i), body_funcs[i], timeout_ms=2000):
                ok = False; break
        if not ok:
            continue
        # 边界: 找出 din, 转为 Verilog 避免 z3 prefix 污染 CSE
        din_expr = z3.simplify(body_funcs[boundary])
        din_str = z3_to_verilog(din_expr)
        return {"type": "shift", "dir": direction, "din": din_str, "width": N}
    return None


# ══════════════════════════════════════════════════════════════
# § 8. 向量级数据寄存器检测 (基于 H/D 分解)
# ══════════════════════════════════════════════════════════════

def try_lift_data_reg_hd(
        bits: List[int],
        body_funcs: List[z3.BoolRef],
        q_vars: List[z3.BoolRef],
        var_map: Dict[int, z3.BoolRef]) -> Optional[Dict]:
    """
    使用 H/D 分解: 对每一位计算 H[i] 和 D[i]。
    若所有位共享同一个 H (保持条件), 则可以写:
        if (!H) bus <= {D[N-1], ..., D[0]};
    这比逐位布尔表达式可读得多。
    返回 {'type':'data_reg','H_expr':str,'D_exprs':[str,...]} 或 None。
    """
    N = len(bits)
    Hs, Ds = [], []
    for i in range(N):
        H, D = extract_hd(body_funcs[i], q_vars[i])
        Hs.append(H)
        Ds.append(D)

    # 检查所有 H[i] 是否等价
    H0 = Hs[0]
    uniform_H = all(z3_equiv(Hs[i], H0, timeout_ms=2000) for i in range(1, N))

    if not uniform_H:
        return None

    # 恒等式并非无条件成立 (翻转位就不成立), 必须逐位验证
    #     f_i ≡ (H0 & q_i) | (~H0 & D_i)
    # 任一位不成立就放弃提升, 交给 raw 逐位发射, 避免发出错误 RTL。
    for i in range(N):
        ident = z3.Or(z3.And(H0, q_vars[i]),
                      z3.And(z3.Not(H0), Ds[i]))
        if not z3_equiv(body_funcs[i], ident, timeout_ms=4000):
            return None

    # 构建 var rename map: z3 var name → Verilog 信号名
    rename = {}
    for nid, v in var_map.items():
        rename[str(v)] = f"n{nid}"   # 后面在 assembler 里再替换为语义名

    H_str = z3_to_verilog(H0, rename)
    D_strs = [z3_to_verilog(D, rename) for D in Ds]

    return {
        "type": "data_reg",
        "H_expr": H_str,       # 保持条件 (en = NOT H)
        "D_exprs": D_strs,     # 每位装载数据
        "H_z3": H0,            # 供后续 simplify 使用
        "D_z3": Ds,
    }


def try_lift_data_reg_perbit(
        bits: List[int],
        body_funcs: List[z3.BoolRef],
        q_vars: List[z3.BoolRef],
        var_map: Dict[int, z3.BoolRef],
        timeout_ms: int = 4000) -> Optional[Dict]:
    """
    逐位保持/装载: 每位有自己的使能, 写成
        if (~H0) q[0] <= D0;
        if (~H1) q[1] <= D1;
        ...
    典型来源: 寄存器堆的位切片 —— 同一位在 32 个寄存器里由不同的
    地址译码使能, 所以整条 bus 不共享统一 H (uniform_H 失败),
    但每一位单独看仍是标准的 "使能装载" 结构。
    比逐位布尔表达式可读得多, 且每位都验证恒等式, 不会发出错误 RTL。
    """
    N = len(bits)
    Hs, Ds, ok = [], [], []
    for i in range(N):
        # 允许**部分提升**: 单独一位验证失败(或 z3 超时返回 unknown)不该毁掉
        # 整条 bus。之前是全有或全无, 对"低位快、高位极慢"的结构(如乘法器
        # 累加器进位链)一个慢位就让整条退化成 raw, 白扔掉其余位的结构信息。
        try:
            H, D = extract_hd(body_funcs[i], q_vars[i])
            ident = z3.Or(z3.And(H, q_vars[i]), z3.And(z3.Not(H), D))
            good = z3_equiv(body_funcs[i], ident, timeout_ms=timeout_ms)
        except Exception:
            H = D = None; good = False
        if good:
            Hs.append(H); Ds.append(D); ok.append(True)
        else:
            Hs.append(None); Ds.append(None); ok.append(False)

    n_ok = sum(ok)
    if n_ok == 0:
        return None            # 一位都没成, 交给后续/raw

    rename = {}
    for nid, v in var_map.items():
        rename[str(v)] = f"n{nid}"

    return {
        "type": "data_reg_perbit",
        # 未通过的位置 None, 由 assemble 回退到该位的原始布尔函数
        "H_exprs": [z3_to_verilog(H, rename) if H is not None else None
                    for H in Hs],
        "D_exprs": [z3_to_verilog(D, rename) if D is not None else None
                    for D in Ds],
        "perbit_ok": ok,
        "perbit_n_ok": n_ok,
    }


def try_lift_toggle(
        bits: List[int],
        body_funcs: List[z3.BoolRef],
        q_vars: List[z3.BoolRef],
        var_map: Dict[int, z3.BoolRef]) -> Optional[Dict]:
    """
    翻转寄存器: f(q) = q ^ T, 其中 T 与 q 无关。

    Shannon 展开 f = (q & f1) | (~q & f0), 令 T = f0 则
        f = q ^ T  <=>  f1 = ~f0
    这类位无法用 "保持/装载" 表达 (H/D 分解会把翻转误判成保持),
    单独识别成 `q <= q ^ T` 既正确又可读。
    要求所有位共享同一个 T (整条 bus 统一翻转), 否则返回 None。
    """
    N = len(bits)
    Ts = []
    for i in range(N):
        f1 = z3.simplify(z3.substitute(body_funcs[i], (q_vars[i], z3.BoolVal(True))))
        f0 = z3.simplify(z3.substitute(body_funcs[i], (q_vars[i], z3.BoolVal(False))))
        # 必须 f1 ≡ ~f0 才是纯翻转
        if not z3_equiv(f1, z3.Not(f0), timeout_ms=2000):
            return None
        Ts.append(f0)

    T0 = Ts[0]
    if not all(z3_equiv(Ts[i], T0, timeout_ms=2000) for i in range(1, N)):
        return None

    # 逐位验证 f_i ≡ q_i ^ T0
    for i in range(N):
        if not z3_equiv(body_funcs[i], z3.Xor(q_vars[i], T0), timeout_ms=4000):
            return None

    rename = {}
    for nid, v in var_map.items():
        rename[str(v)] = f"n{nid}"

    return {
        "type": "toggle",
        "T_expr": z3_to_verilog(T0, rename),   # 翻转条件
        "T_z3": T0,
    }


# ══════════════════════════════════════════════════════════════
# § 9. 主入口 lift_bus
# ══════════════════════════════════════════════════════════════

def lift_bus(bus_name: str,
             bits: List[int],
             raw_funcs: List[Optional[str]],
             rst_net_id: Optional[int] = None,
             timeout_budget: int = 40,
             verilog: bool = False,
             cse_wires: Optional[List[Optional[list]]] = None,
             perbit_wire_threshold: int = 2000,
             perbit_max_sec: float = 600.0) -> Dict[str, Any]:
    """
    对一条总线做结构提升。
    返回:
      {
        'lifted': bool,
        'type': 'counter'|'shift'|'data_reg'|'raw',
        'rst_var': str or None,
        'rst_proven': bool,
        'bits': [net_id,...],
        'funcs_raw': [...],   # 保留原始函数供 fallback
        ... 类型专属字段 ...
      }
    data_reg 附加: H_expr (保持条件), D_exprs (每位数据)
    counter  附加: inc (+1/-1), en (str/None), width
    shift    附加: dir ('left'/'right'), din (str), width
    """
    import time
    t0 = time.time()
    N = len(bits)
    base = {
        "lifted": False, "type": "raw",
        "bits": bits, "funcs_raw": raw_funcs,
        "rst_var": None, "rst_proven": False,
    }

    # ── 解析 ────────────────────────────────────────────────────
    var_map: Dict[int, z3.BoolRef] = {}
    for nid in bits:
        var_map[nid] = z3.Bool(f"n{nid}")

    funcs_z3: List[z3.BoolRef] = []
    for i, func in enumerate(raw_funcs):
        if func is None:
            funcs_z3.append(z3.BoolVal(False)); continue
        try:
            if verilog:
                # mech_cse.py 产出的是 Verilog 形式 (n123/~/1'b1) 且带 _cN wire
                # 引用, 必须走 parse_v_z3。不能复用 parse_z3: 它用 finditer 逐个
                # 匹配 token, 遇到 n123/~ 这类不认识的会**静默跳过**而不报错,
                # 结果是算出错误的函数却毫无警告。
                wl = (cse_wires[i] if cse_wires and i < len(cse_wires) else None)
                env = build_wire_env(wl, var_map)
                funcs_z3.append(parse_v_z3(func, var_map, env))
            else:
                funcs_z3.append(parse_z3(func, var_map))
        except Exception as e:
            return {**base, "parse_error": str(e)}

    q_vars = [var_map[nid] for nid in bits]

    # ── 复位剥离 ────────────────────────────────────────────────
    rst_var, body_funcs = peel_reset(funcs_z3, var_map, bits, rst_net_id)
    rst_proven = rst_var is not None
    base["rst_var"] = str(rst_var) if rst_var is not None else None
    base["rst_proven"] = rst_proven

    if time.time() - t0 > timeout_budget:
        return base

    # ── wire 极多的 bus: 直接走逐位路径 ─────────────────────────
    #  实测 (Config A 乘法器累加器): z3 耗时随 CSE wire 数**超线性**增长,
    #  约 wires^1.8 (356→515 wires 时 32.5s→75.9s)。整条 16 位累加器有
    #  13208 wires, 于是预算全烧在注定失败的整条尝试上, 最后退化成 raw ——
    #  可是**单独一位是能提升成 data_reg 的**。
    #  所以这里先按 wire 数分流: 太重就跳过整条尝试 (counter/shift/H-D 都
    #  要求全位统一结构, 对乘法器进位链本来就不可能成立), 直接逐位做。
    n_wires = sum(len(w or []) for w in (cse_wires or []))
    if n_wires > perbit_wire_threshold and len(bits) > 1:
        # 每位的 z3 预算必须按**该位自己的 wire 数**给, 不能全 bus 一个固定值:
        # 累加器的 wire 数沿位号陡增 (net_27090 356 → net_27105 ~1400), 按
        # wires^1.8 换算, 高位单独就要 ~440s。给统一的 60s 会让高位返回
        # unknown → z3_equiv 判 False → 整条退化成 raw (实测就是这样)。
        mx = max((len(w or []) for w in (cse_wires or [])), default=0)
        est = 40.0 * (mx / 400.0) ** 1.8 if mx else 4.0
        ms = int(min(max(est, 4.0), perbit_max_sec) * 1000)
        try:
            r = try_lift_data_reg_perbit(bits, body_funcs, q_vars, var_map,
                                         timeout_ms=ms)
            if r:
                return {**base, **r, "lifted": True,
                        "perbit_fastpath": n_wires, "perbit_timeout_ms": ms}
        except Exception:
            pass
        return {**base, "perbit_attempted": n_wires, "perbit_timeout_ms": ms}

    # ── 计数器 ──────────────────────────────────────────────────
    try:
        r = try_lift_counter(bits, body_funcs, q_vars, var_map)
        if r:
            return {**base, **r, "lifted": True}
    except Exception:
        pass

    if time.time() - t0 > timeout_budget:
        return base

    # ── 移位寄存器 ──────────────────────────────────────────────
    try:
        r = try_lift_shift(bits, body_funcs, q_vars, var_map)
        if r:
            return {**base, **r, "lifted": True}
    except Exception:
        pass

    if time.time() - t0 > timeout_budget:
        return base

    # ── 数据寄存器 (H/D 分解) ───────────────────────────────────
    try:
        r = try_lift_data_reg_hd(bits, body_funcs, q_vars, var_map)
        if r:
            return {**base, **r, "lifted": True}
    except Exception:
        pass

    if time.time() - t0 > timeout_budget:
        return base

    # ── 翻转寄存器 (q <= q ^ T) ─────────────────────────────────
    # 放在 data_reg 之后: 纯翻转不满足 H/D 形式, 只会落到这里
    try:
        r = try_lift_toggle(bits, body_funcs, q_vars, var_map)
        if r:
            return {**base, **r, "lifted": True}
    except Exception:
        pass

    if time.time() - t0 > timeout_budget:
        return base

    # ── 逐位保持/装载 (各位使能不同, 如寄存器堆位切片) ──────────
    # 最后兜底: 统一 H 不成立但每位单独是使能装载结构
    try:
        r = try_lift_data_reg_perbit(bits, body_funcs, q_vars, var_map)
        if r:
            return {**base, **r, "lifted": True}
    except Exception:
        pass

    return base
