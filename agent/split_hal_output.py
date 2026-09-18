#!/usr/bin/env python3
"""split_hal_output.py —— 把 hal_mechanical.py 的输出切成纯 JSON

hal_mechanical.py 输出格式:
  <HAL 日志行>
  ###JSON_START###
  {实际 JSON}

本脚本读取后切分, 写出纯 JSON 文件。
"""
import sys, re
from pathlib import Path

if len(sys.argv) < 3:
    print("用法: split_hal_output.py <raw.txt> <out.json>", file=sys.stderr)
    sys.exit(1)

raw = Path(sys.argv[1]).read_text()
marker = "###JSON_START###"
if marker not in raw:
    print(f"未找到 {marker}, 提取可能未完成", file=sys.stderr)
    sys.exit(1)

json_part = raw.split(marker, 1)[1].strip()
Path(sys.argv[2]).write_text(json_part)
print(f"写入 {sys.argv[2]}  ({len(json_part)} 字节)")
