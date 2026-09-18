#!/usr/bin/env python3
"""
parse_ports.py —— 从 Verilog 网表直接解析真实顶层端口

为什么需要: HAL 的 get_global_input_nets()/get_global_output_nets() 返回的可能是
net 的内部别名(如 PicoRV32 里 `wire dbg_mem_addr = mem_addr` 导致报告 dbg_mem_addr),
并且会遗漏部分真实端口。等价性验证按端口名对齐, 所以必须用网表声明里的真实端口。

支持:
  - Yosys 网表风格:  module m(a, b, c);  然后 body 里 input/output 声明
  - 带参数的模块:    module m #(parameter X=1) (ports);
  - ANSI 端口风格:   module m (input clk, output reg [31:0] q);
  - 多模块文件:      用 top= 指定, 否则取第一个模块

输出: {"module": 名, "inputs": {名: (hi,lo)|None}, "outputs": {...}, "order": [...]}
"""
import re, json, sys

_KW = ("input", "output", "inout")


def _match_paren(text: str, i: int) -> int:
    """text[i] == '('; 返回配对 ')' 的下标 (跳过注释/字符串)。"""
    depth = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            i = text.find("\n", i)
            if i < 0:
                return -1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            if j < 0:
                return -1
            i = j + 2
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def _find_module(text: str, top=None):
    """定位模块声明。返回 (模块名, 端口列表原文, body 起始下标) 或 None。"""
    for m in re.finditer(r"\bmodule\s+(\w+)", text):
        name = m.group(1)
        if top is not None and name != top:
            continue
        i = m.end()
        # 跳过空白/注释, 找到第一个 '(' 或 ';'
        while i < len(text):
            if text[i] in " \t\r\n":
                i += 1; continue
            if text.startswith("//", i):
                i = text.find("\n", i)
                if i < 0: return None
                continue
            if text.startswith("/*", i):
                j = text.find("*/", i + 2)
                if j < 0: return None
                i = j + 2; continue
            break
        if i >= len(text):
            return None
        # 可选参数列表 #( ... )
        if text[i] == "#":
            i += 1
            while i < len(text) and text[i] in " \t\r\n":
                i += 1
            if i >= len(text) or text[i] != "(":
                continue
            close = _match_paren(text, i)
            if close < 0:
                continue
            i = close + 1
            while i < len(text) and text[i] in " \t\r\n":
                i += 1
        if i >= len(text) or text[i] != "(":
            continue                      # 无端口列表 → 不是我们要的顶层
        close = _match_paren(text, i)
        if close < 0:
            continue
        portlist = text[i + 1:close]
        # 端口列表之后应是 ';'
        j = close + 1
        while j < len(text) and text[j] in " \t\r\n":
            j += 1
        if j < len(text) and text[j] == ";":
            j += 1
        return name, portlist, j
    return None


def _strip_comments(s: str) -> str:
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", " ", s)


def _add(dct: dict, names: str, width):
    for nm in names.split(","):
        nm = nm.strip()
        # 去掉数组维度 / 初值 (ANSI 声明里可能出现)
        nm = re.split(r"[\[=]", nm)[0].strip()
        if nm and re.fullmatch(r"\w+", nm) and nm not in _KW:
            dct[nm] = width


def _parse_width(hi, lo):
    return (int(hi), int(lo)) if hi is not None else None


def parse(verilog_text, top=None):
    hit = _find_module(verilog_text, top)
    if hit is None and top is not None:
        hit = _find_module(verilog_text, None)
    if hit is None:
        return {"error": "找不到module声明", "inputs": {}, "outputs": {}, "order": []}
    modname, portlist_raw, body_start = hit

    portlist = _strip_comments(portlist_raw).replace("\n", " ")
    body = verilog_text[body_start:]
    inputs, outputs = {}, {}

    # ── ANSI 风格: 方向关键字直接写在端口列表里 ─────────────────
    ansi = False
    if re.search(r"\b(input|output|inout)\b", portlist):
        ansi = True
        cur_dir, cur_w = None, None
        for item in portlist.split(","):
            item = item.strip()
            if not item:
                continue
            dm = re.match(r"^(input|output|inout)\b\s*", item)
            if dm:
                cur_dir = dm.group(1)
                item = item[dm.end():]
                cur_w = None                       # 新方向 → 位宽重新解析
            item = re.sub(r"^(wire|reg|logic|signed|unsigned)\b\s*", "", item).strip()
            wm = re.match(r"^\[\s*([\w'\-+ ]+?)\s*:\s*([\w'\-+ ]+?)\s*\]\s*", item)
            if wm:
                hi, lo = wm.group(1).strip(), wm.group(2).strip()
                if hi.isdigit() and lo.isdigit():
                    cur_w = (int(hi), int(lo))
                else:
                    cur_w = None                   # 参数化位宽, 交给 body 声明
                item = item[wm.end():].strip()
            if not item or cur_dir is None:
                continue
            if cur_dir == "input":
                _add(inputs, item, cur_w)
            elif cur_dir == "output":
                _add(outputs, item, cur_w)

    # ── 非 ANSI 风格 (Yosys 网表): body 里的 input/output 声明 ──
    for kind, dct in (("input", inputs), ("output", outputs)):
        for dm in re.finditer(
                rf"^[ \t]*{kind}\s+(?:wire\s+|reg\s+|logic\s+|signed\s+)*"
                rf"(?:\[\s*(\d+)\s*:\s*(\d+)\s*\]\s*)?([\w\s,]+?)\s*;",
                body, re.MULTILINE):
            w = _parse_width(dm.group(1), dm.group(2))
            if ansi:
                # ANSI 已给出端口集合, body 声明只用来补位宽
                for nm in dm.group(3).split(","):
                    nm = nm.strip()
                    if nm in dct and dct[nm] is None and w is not None:
                        dct[nm] = w
            else:
                _add(dct, dm.group(3), w)

    port_order = [p.strip() for p in portlist.split(",") if p.strip()] if not ansi \
        else list(inputs) + list(outputs)
    return {"module": modname, "inputs": inputs, "outputs": outputs,
            "order": port_order}


if __name__ == "__main__":
    txt = open(sys.argv[1]).read()
    top = sys.argv[2] if len(sys.argv) > 2 else None
    print(json.dumps(parse(txt, top), ensure_ascii=False, indent=2))
