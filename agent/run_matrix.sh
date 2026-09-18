#!/bin/bash
# run_matrix.sh —— 对照实验矩阵: 每个设计 × {baseline, hybrid}
# 量化 HAL 在不同复杂度下的增益, 找到能力上限
set -u
cd "$(dirname "$0")"
export PATH="/Users/blackbox/try_hai/oss-cad-suite/bin:/Users/blackbox/try_hai/tools/z3-4.13.4-arm64-osx-13.7.1/bin:$PATH"
export LLM_BASE="${LLM_BASE:?}"
export LLM_KEY="${LLM_KEY:?}"

PL=/Users/blackbox/try_hai/pipeline
RESULTS=matrix_results.txt
: > $RESULTS

# 设计: 名称:网表:top
DESIGNS=(
  "alu8:$PL/alu8_hal_netlist.v:alu8"
  "fifo:$PL/fifo_hal_netlist.v:fifo"
  "uart_tx:$PL/uart_tx_hal_netlist.v:uart_tx"
)

for entry in "${DESIGNS[@]}"; do
  IFS=':' read -r name netlist top <<< "$entry"
  for mode in baseline hybrid; do
    echo ">>> $name / $mode ..."
    out=$(/usr/bin/python3 hybrid_pipeline.py --netlist "$netlist" --top "$top" \
          --mode "$mode" --max-retries 4 --save "trace_${name}_${mode}.json" 2>/dev/null \
          | grep -E "成功|失败")
    echo "$name  $mode  $out" | tee -a $RESULTS
  done
done
echo "=== 完成, 结果见 $RESULTS ==="