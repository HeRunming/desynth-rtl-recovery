#!/usr/bin/env python3
"""
alias_map.py —— 解析网表里的 assign 别名, 建立 HAL名 → 真实端口名 的映射

背景(已实证的HAL限制): HAL的Verilog解析器会把 `assign dbg_mem_valid = mem_valid;`
这类别名net合并, 且**保留别名而丢弃真实端口名**。结果:
  - HAL报告 dbg_mem_valid, 而真实端口是 mem_valid
  - 部分端口(mem_addr/mem_wdata/...)在HAL模型里完全不存在
等价性验证按端口名对齐, 所以必须把HAL名翻译回真实端口名。

做法: 扫描网表的 `assign A = B;` (含位选/拼接), 建立双向别名关系。
"""
import re, json, sys


def _clean_ident(s):
    """规范化标识符, 使其与 HAL 的 net 名对齐。

    Verilog 转义标识符形如 `\\genblk1.genblk1.pcpi_mul.resetn ` (反斜杠开头,
    空白结尾)。yosys flatten 用这种写法表示层级名。HAL 内部**不保留反斜杠**,
    net_meta 里就是 `genblk1.genblk1.pcpi_mul.resetn`, 所以这里也要剥掉,
    否则别名表的 key 永远匹配不上 HAL 名。
    """
    s = s.strip()
    if s.startswith("\\"):
        s = s[1:].strip()
    return s


# 标识符: 转义标识符 (\任意非空白 + 空白) 或普通标识符; 后面可跟位选
_IDENT = r"(?:\\\S+\s+|[\w$]+)"
_LHS = rf"({_IDENT}(?:\s*\[[^\]]*\])?)"


def build_alias_map(verilog_text):
    """返回 {别名: 真实名} 映射(按位)。
    处理形式:
      assign a = b;                 -> a[i]:b[i] 逐位(需宽度)
      assign a = { b[31:2], 2'h0 }; -> 部分位映射
      assign a[1:0] = 2'h0;         -> 常量, 忽略
      assign \\hier.path.sig = b;    -> 层级名(转义标识符) 别名
    """
    aliases = {}          # 简单整体别名: 别名基名 -> 真实基名
    pat = re.compile(rf"^\s*assign\s+{_LHS}\s*=\s*([^;]+);", re.MULTILINE)
    for m in pat.finditer(verilog_text):
        lhs, rhs = m.group(1).strip(), m.group(2).strip()
        # 只处理 lhs 是纯标识符(整体赋值)且 rhs 是纯标识符 或 {ident[..], const}
        lbase = _clean_ident(re.sub(r"\s*\[[^\]]*\]$", "", lhs))
        # rhs 是纯标识符 (含转义标识符)
        rm = re.fullmatch(rf"{_IDENT}", rhs + " " if rhs.startswith("\\") else rhs)
        if rm:
            aliases[lbase] = _clean_ident(rhs)
            continue
        # rhs 形如 { ident[hi:lo], N'hX }  -> 取其中的标识符
        cm = re.findall(rf"({_IDENT})\s*\[", rhs)
        if cm and "'" in rhs:   # 含常量的拼接
            aliases[lbase] = _clean_ident(cm[0])
    return aliases


def resolve(hal_name, aliases, real_ports=None):
    """把 HAL 的net名(可能带 (bit)) 翻译成真实端口名。

    real_ports: 真实端口名集合。只有当"HAL名不是端口、而别名目标是端口"时才替换,
    避免把已经正确的端口名(如 pcpi_rs1)错误改成内部信号(如 reg_op1)。
    """
    m = re.match(r"^(.*?)\((\d+)\)$", hal_name)
    base, bit = (m.group(1), m.group(2)) if m else (hal_name, None)

    target = aliases.get(base)
    if target is None:
        real = base
    elif real_ports is None:
        real = target
    else:
        # HAL名已是端口 -> 保持; 否则若别名目标是端口 -> 替换
        if base in real_ports:
            real = base
        elif target in real_ports:
            real = target
        else:
            real = base
    return f"{real}({bit})" if bit is not None else real


if __name__ == "__main__":
    txt = open(sys.argv[1]).read()
    a = build_alias_map(txt)
    # 只显示与端口相关的
    print(json.dumps(a, ensure_ascii=False, indent=2))
