#!/bin/bash
# hal_env.sh —— 加载编译好的 HAL(无GUI) python 环境
# 用法: source hal/hal_env.sh; /usr/bin/python3 你的脚本.py
export HAL_BASE_PATH="/Users/blackbox/try_hai/hal/build"
export PYTHONPATH="/Users/blackbox/try_hai/hal/build/lib:$PYTHONPATH"
# 必须用系统 python3.9 (有distutils; 且SIP会剥离DYLD路径, 依赖已用install_name_tool改成@loader_path)
alias halpy='/usr/bin/python3'
echo "HAL python 环境就绪 (HAL_BASE_PATH=$HAL_BASE_PATH)"
echo "用 /usr/bin/python3 运行脚本; import hal_py 可用"
