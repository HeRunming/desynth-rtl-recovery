#!/usr/bin/env python3
"""z3setup.py —— 让独立安装的 z3 能被 python 直接 import (无 brew / 无 pip)。

SIP 会剥离 DYLD_LIBRARY_PATH, 所以用 z3 官方支持的 builtins.Z3_LIB_DIRS 机制。
"""
import builtins, os, sys

Z3DIR = os.environ.get(
    "Z3_DIR", "/Users/blackbox/try_hai/tools/z3-4.13.4-arm64-osx-13.7.1")
_py = os.path.join(Z3DIR, "bin", "python")
if _py not in sys.path:
    sys.path.insert(0, _py)
builtins.Z3_LIB_DIRS = [os.path.join(Z3DIR, "bin")]

import z3  # noqa: E402,F401
