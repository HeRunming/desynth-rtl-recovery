#!/usr/bin/env python3
"""
build_dataset.py —— 反综合数据 pipeline (雏形)

作用: 扫描 RTL 语料库 -> 用 Yosys 综合成门级网表 -> 形式化等价性验证
      -> 输出带元数据的 (RTL, netlist) 数据集 (JSONL)。

这是整个项目的地基:
  - Phase 1 (Agent): 用它产出的 (netlist) 作为输入、(RTL) 作为参考答案来评测
  - Phase 2 (训练):  用它产出的 (RTL, netlist) 对作为微调语料

用法:
  export PATH="/Users/blackbox/try_hai/oss-cad-suite/bin:$PATH"
  python3 build_dataset.py --corpus rtl_corpus --out dataset
"""
import argparse, json, os, re, subprocess, sys, tempfile, shutil
from pathlib import Path
from typing import Optional, Tuple, Dict

# ---- 综合脚本模板: RTL -> 门级网表 ----
SYNTH_TMPL = """
read_verilog {rtl}
hierarchy -top {top}
proc
opt
techmap
opt
abc -g AND,OR,XOR,MUX
opt_clean
write_verilog -noattr {netlist}
stat
"""

# ---- 等价性检查脚本模板: 证明 RTL 与网表功能一致 ----
EQUIV_TMPL = """
read_verilog {rtl}
rename {top} gold
read_verilog {netlist}
rename {top} gate
proc
equiv_make gold gate equiv
hierarchy -top equiv
equiv_simple
equiv_status -assert
"""


def run_yosys(script: str, cwd: str) -> Tuple[int, str]:
    """在 cwd 目录下跑一段 yosys 脚本, 返回 (exit_code, 合并输出)."""
    with tempfile.NamedTemporaryFile("w", suffix=".ys", dir=cwd, delete=False) as f:
        f.write(script)
        ys_path = f.name
    try:
        r = subprocess.run(["yosys", os.path.basename(ys_path)], cwd=cwd,
                            capture_output=True, text=True, timeout=300)
        return r.returncode, r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return -1, "TIMEOUT"
    finally:
        os.unlink(ys_path)


def detect_top(rtl_text: str) -> Optional[str]:
    """从 RTL 里抓第一个 module 名作为 top."""
    m = re.search(r"\bmodule\s+([A-Za-z_]\w*)", rtl_text)
    return m.group(1) if m else None


def parse_stat(log: str) -> Dict:
    """从 yosys stat 输出里解析门统计."""
    stats = {}
    in_stat = False
    for line in log.splitlines():
        # "84 cells" 标志着门统计段的开始
        m_total = re.match(r"\s+(\d+)\s+cells\s*$", line)
        if m_total:
            stats["total_cells"] = int(m_total.group(1))
            in_stat = True
            continue
        if in_stat:
            # 形如 "   34   $_AND_"
            m = re.match(r"\s+(\d+)\s+(\$?[\w]+)\s*$", line)
            if m:
                stats[m.group(2)] = int(m.group(1))
            elif line.strip() == "":
                break
    return stats


def process_one(rtl_path: Path, workdir: Path) -> Dict:
    """对单个 RTL 文件: 综合 + 等价性验证, 返回一条数据记录."""
    name = rtl_path.stem
    rtl_text = rtl_path.read_text()
    top = detect_top(rtl_text)
    rec = {"name": name, "source_file": rtl_path.name, "top": top}

    if not top:
        rec.update(status="fail", stage="detect_top", error="no module found")
        return rec

    # 每个设计一个独立工作目录, 避免互相干扰
    d = workdir / name
    d.mkdir(parents=True, exist_ok=True)
    shutil.copy(rtl_path, d / "design.v")
    netlist_name = "netlist.v"

    # --- 综合 ---
    code, log = run_yosys(
        SYNTH_TMPL.format(rtl="design.v", top=top, netlist=netlist_name), str(d))
    if code != 0:
        rec.update(status="fail", stage="synth", error=log[-500:])
        return rec
    rec["gate_stats"] = parse_stat(log)

    # --- 等价性验证 ---
    code, log = run_yosys(
        EQUIV_TMPL.format(rtl="design.v", top=top, netlist=netlist_name), str(d))
    equiv_ok = (code == 0 and "Equivalence successfully proven" in log)
    rec["equiv_verified"] = equiv_ok

    # --- 组装数据 ---
    rec["rtl"] = rtl_text
    rec["netlist"] = (d / netlist_name).read_text()
    rec["status"] = "ok" if equiv_ok else "warn"
    if not equiv_ok:
        rec["equiv_log_tail"] = log[-500:]
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="rtl_corpus", help="RTL 语料目录")
    ap.add_argument("--out", default="dataset", help="输出目录")
    args = ap.parse_args()

    base = Path(__file__).parent
    corpus = base / args.corpus
    outdir = base / args.out
    outdir.mkdir(parents=True, exist_ok=True)
    workdir = outdir / "_work"

    rtl_files = sorted(corpus.glob("*.v"))
    print(f"发现 {len(rtl_files)} 个 RTL 文件\n")

    records = []
    for rtl in rtl_files:
        rec = process_one(rtl, workdir)
        records.append(rec)
        gc = rec.get("gate_stats", {}).get("total_cells", "?")
        ev = "✓" if rec.get("equiv_verified") else "✗"
        print(f"  [{rec['status']:>4}] {rec['name']:<16} 门数={gc:<5} 等价验证={ev}")

    # 写 JSONL 数据集
    ds_path = outdir / "dataset.jsonl"
    with open(ds_path, "w") as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    ok = sum(1 for r in records if r["status"] == "ok")
    print(f"\n完成: {ok}/{len(records)} 条通过综合+等价验证")
    print(f"数据集写入: {ds_path}")


if __name__ == "__main__":
    main()
