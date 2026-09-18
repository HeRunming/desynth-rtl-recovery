# Changelog - Config A CSE Assembly Fix

## 2026-08-20: Fix assemble_lifted.py for CSE format compatibility

**问题**: `assemble_lifted.py` 不认识 `cse_wires` 字段，导致未提升的 bus 发射时会产生未声明的 `_cN` wire 引用。

**影响范围**:
- Config A: 74/232 位 (31.9%) 在 9 条未提升的 bus 里
- Config B: 未评估，但同样使用 CSE 预处理

**根因**:
`mech_cse.py` 把共享子表达式从 `func` 移到了 `cse_wires`，而 `assemble_lifted.py` 的两条 raw 发射路径只看 `func`:
1. 未提升的 bus → `E[f"{nm}#R{nid}"] = to_v(ff["func"])`
2. 部分提升的位 (data_reg_perbit 里 z3 验证失败的位)
3. 组合输出 → `E[f"@out{oid}"] = to_v(od["func"])`

**修复**:

1. **新增 `expand_cse_wires(func, cse_wires)` 函数** (assemble_lifted.py:39-62)
   - 就地展开 `_cN` 引用 (按正向拓扑序)
   - 用正则 `\b_cN\b` 避免 `_c1` 误匹配 `_c10`
   - 返回完全展开形式 (不含任何 `_cN` 残留)

2. **修改 `to_v()` 函数签名** (assemble_lifted.py:237-240)
   ```python
   def to_v(func: str, cse_wires=None) -> str:
       expanded = expand_cse_wires(func, cse_wires) if cse_wires else func
       raw = hal_to_v(expanded)
       return apply_rename(raw, rename)
   ```

3. **修改 3 处调用点**:
   - Line 300: `E[f"{nm}#R{nid}"] = to_v(ff["func"], ff.get("cse_wires"))` (部分提升的位)
   - Line 311: `E[f"{nm}#R{nid}"] = to_v(ff["func"], ff.get("cse_wires"))` (未提升的 bus)
   - Line 316: `E[f"@out{od['o_id']}"] = to_v(od["func"], od.get("cse_wires"))` (组合输出)

**验证**:
- ✅ 单元测试 6 项全部通过 (边界匹配/拓扑序/空输入)
- ⏳ 端到端验证: 等待服务器 SSH 权限恢复后执行

**代价**:
- 展开后约 0.5M 字符 (仅影响 74 位 / 2313)
- 相比 Config A 原始 568MB mech, 完全可接受

**下一步**:
1. 传输修复后的 `assemble_lifted.py` 到服务器
2. 执行 Config A 完整组装 → iverilog 语法检查
3. 如果通过，进入仿真验证阶段
