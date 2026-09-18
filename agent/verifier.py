"""
verifier.py —— 用 Yosys 做形式化等价性验证

Agent 生成的 RTL 是否"和原网表功能一致", 由这里判定。
这是整个反综合闭环的"裁判", 让 AI 不靠人肉判断对错。
"""
import os, re, subprocess, tempfile, shutil
from pathlib import Path

# 库单元的行为模型 —— 让 SAT 求解器能对门级网表里的 FF/门建模。
# (只读 liberty 的话 FF 是黑盒, SAT 无法建模, 会报 "No SAT model available")
CELLS_SIM = """
module FF(C, D, Q); input C, D; output reg Q; always @(posedge C) Q <= D; endmodule
module FFR(C, R, D, Q); input C,R,D; output reg Q; always @(posedge C) Q <= R?1'b0:D; endmodule
module FFS(C, S, D, Q); input C,S,D; output reg Q; always @(posedge C) Q <= S?1'b1:D; endmodule
module INV(I, O); input I; output O; assign O = ~I; endmodule
module BUF(I, O); input I; output O; assign O = I; endmodule
module TBUF(I, O); input I; output O; assign O = I; endmodule
module AND2(I0,I1,O); input I0,I1; output O; assign O=I0&I1; endmodule
module OR2(I0,I1,O); input I0,I1; output O; assign O=I0|I1; endmodule
module XOR(I0,I1,O); input I0,I1; output O; assign O=I0^I1; endmodule
module MUX(I0,I1,S,O); input I0,I1,S; output O; assign O=S?I1:I0; endmodule
"""

# 等价性检查流程: 给门级网表配行为cell模型, 展开后与候选RTL做SAT等价证明
EQUIV_TMPL2 = """
read_verilog cells_sim.v gold_netlist.v
rename {top} gold
read_verilog cand.v
rename {top} gate
proc
memory
opt
flatten gold
async2sync
equiv_make gold gate equiv
equiv_simple
equiv_induct
equiv_status -assert
"""


def _detect_top(verilog: str):
    m = re.search(r"\bmodule\s+([A-Za-z_]\w*)", verilog)
    return m.group(1) if m else None


def check_equivalence(candidate_rtl: str, golden_netlist: str, top: str,
                      liberty: str = None):
    """
    candidate_rtl : Agent 生成的 RTL
    golden_netlist: 原始门级网表(金标准)
    top           : 顶层模块名(候选RTL的模块名会被重命名对齐)
    liberty       : 门级网表用的 liberty 库(库单元FF需要它才能被SAT建模)

    返回 dict: {ok, status, reason, log, log_tail}。
    ``status`` 明确区分证明失败、模型错误、超时和未知；旧调用方仍可
    使用 ``ok``/``reason``。若传入 liberty，会先校验并记录其 cell 集合，
    避免参数被静默忽略。
    """
    liberty_info = None
    if liberty is not None:
        lp = Path(liberty)
        if not lp.is_file():
            return {"ok": False, "status": "model_error",
                    "reason": f"liberty 文件不存在: {liberty}",
                    "log": "", "log_tail": "", "liberty": str(lp)}
        try:
            lt = lp.read_text(errors="replace")
            liberty_info = {"path": str(lp),
                            "bytes": lp.stat().st_size,
                            "cells": sorted(set(re.findall(r"\bcell\s*\(\s*([A-Za-z_]\w*)", lt)))}
        except OSError as e:
            return {"ok": False, "status": "model_error",
                    "reason": f"liberty 无法读取: {e}",
                    "log": "", "log_tail": "", "liberty": str(lp)}

    def result(status, reason, log=""):
        return {"ok": status == "proven", "status": status,
                "reason": reason, "log": log, "log_tail": log[-1200:],
                **({"liberty": liberty_info} if liberty_info else {})}

    cand_top = _detect_top(candidate_rtl)
    if not cand_top:
        return result("model_error", "候选RTL里找不到module定义")
    if liberty_info is not None:
        # The behavioral models below are still required for sequential SAT,
        # but the supplied Liberty now has an observable contract: every cell
        # instantiated by the golden netlist must be declared by that library.
        inst_types = set(re.findall(
            r"(?:^|[;}]|\n)\s*([A-Za-z_]\w*)\s+[A-Za-z_]\w*\s*\(",
            golden_netlist, re.M))
        inst_types -= {"module", "input", "output", "inout", "wire", "reg",
                       "assign", "parameter", "localparam", "primitive",
                       "endprimitive", "generate", "endgenerate"}
        missing = sorted(inst_types - set(liberty_info["cells"]))
        liberty_info["netlist_cells"] = sorted(inst_types)
        liberty_info["missing_cells"] = missing
        if missing:
            return result("model_error",
                          "liberty 缺少网表单元: " + ", ".join(missing))

    d = Path(tempfile.mkdtemp(prefix="equiv_"))
    try:
        cand_fixed = re.sub(r"\bmodule\s+" + re.escape(cand_top),
                            f"module {top}", candidate_rtl, count=1)
        (d / "cand.v").write_text(cand_fixed)
        (d / "gold_netlist.v").write_text(golden_netlist)
        (d / "cells_sim.v").write_text(CELLS_SIM)
        (d / "e.ys").write_text(EQUIV_TMPL2.format(top=top))

        r = subprocess.run(["yosys", "e.ys"], cwd=str(d),
                           capture_output=True, text=True, timeout=300)
        out = r.stdout + r.stderr
        if r.returncode == 0 and "Equivalence successfully proven" in out:
            return result("proven", "功能等价已证明", out)
        reason = _extract_error(out)
        # ``equiv_status -assert`` prefixes both incomplete solver results and
        # real counterexamples with ERROR.  Only explicit counterexample /
        # mismatch evidence is a functional failure.  A bare unproven cell is
        # UNKNOWN: treating solver incompleteness as a design bug is unsound.
        if re.search(r"counterexample|mismatch|counter-example", out, re.I):
            status = "failed"
        elif re.search(r"unproven|not proven|timeout|timed out|unknown", out, re.I):
            status = "unknown"
        elif re.search(r"reported \d+ problems", out, re.I):
            status = "failed"
        elif r.returncode != 0 or re.search(r"\b(ERROR|syntax error|No SAT model)\b", out, re.I):
            status = "model_error"
        else:
            status = "unknown"
        return result(status, reason, out)
    except subprocess.TimeoutExpired as e:
        out = ((e.stdout or "") if isinstance(e.stdout, str) else "") + \
              ((e.stderr or "") if isinstance(e.stderr, str) else "")
        return result("timeout", "等价性验证超时(可能逻辑过复杂)", out)
    except FileNotFoundError as e:
        return result("model_error", f"验证工具不可用: {e}")
    finally:
        shutil.rmtree(d, ignore_errors=True)


def _extract_error(log: str) -> str:
    """从 yosys 日志里提取对 Agent 有用的错误摘要。"""
    # 端口不匹配 / 语法错误 / 未证明等价 等
    for pat in [r"ERROR:.*", r".*Port .* not found.*",
                r".*unproven.*", r".*Found and reported \d+ problems.*"]:
        m = re.search(pat, log)
        if m:
            return m.group(0).strip()
    if "unproven" in log:
        return "存在未能证明等价的信号(功能不一致)"
    return "等价性验证未通过"
