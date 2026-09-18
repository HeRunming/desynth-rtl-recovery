# Harness M0/M1 实现报告

日期：2026-09-18。实现提交基于架构提案 [HARNESS_V2_DESIGN.md](HARNESS_V2_DESIGN.md)。

## 已实现

- `harness/ir.py`：规范化 Yosys JSON、去除 source/debug 属性、不可变 source hash、规模摘要、确定性匿名化和独立私有 mapping。
- `harness/candidate.py`：带 source hash、区域 cell、输入/输出 bit、操作和状态的 typed candidate；验证未知 bit、重复 cell/output 和来源不匹配。
- `harness/detect.py`：不读取源名字的 XOR/AND/OR full-adder 结构候选器。它只提出候选，不签发正确性。
- `harness/proof.py`：分类的 exhaustive proof 与 Yosys AIG + 标准 ABC CEC backend；保存反例、timeout、model/tool error 和日志句柄。
- `harness/recovery.py`：只允许匹配 candidate hash 的 `proven` 候选进入新 revision；拒绝重叠 region；支持 rollback；导出完整 source graph、semantic overlay 和 ownership manifest。
- `harness/state.py`：从 Yosys `$dff/$adff/$dffe/$adffe` 提取 clock edge、异步 reset 和 enable；未知 latch/tri-state/时序 primitive 进入 `unsupported`，不被猜测为单一 posedge 模型。
- `harness/cli.py`：`summary`、`anonymize`、`detect`、`recover` 四个最小命令。

这不是完整 RTL 行为 emitter，也没有声称已经支持任意 cell library、时钟/复位、latch、memory 或顺序等价。当前 recovery export 的正确性保证来自“完整 source graph + overlay”，而非把未恢复区域伪装成高层 RTL。

## 验证证据

`tests/test_harness_m0_m1.py` 和 `tests/test_state_model.py` 覆盖：

- 相同 seed 的匿名化稳定；top/cell/port 原名字不会进入 public graph；
- 结构候选在 8 个输入组合上穷举证明；
- 同一候选经标准 ABC CEC 证明；
- 输出位交换产生 counterexample；零秒预算产生 timeout；
- stale source hash 返回 model error；
- 已接受候选不能重复集成或重叠集成；rollback 恢复完整 residual；
- 导出 manifest 显式记录 source/replaced/residual cell ownership。
- `$dff` 时钟事件、`$adff` 复位极性、`$dffe` enable，以及未知 latch 的 unsupported 门槛。

当前仓库原有 `tests/test_repair_gate.py` 也继续通过。总计 **11 tests passed**。

另外使用 Yosys 将真实 `examples/counter/counter_netlist.v` 归一化后完成导入摘要和匿名化 smoke：38 cells、8 state cells、4 ports；匿名 public JSON 不含 `counter/count/enable/rst` 等原始名字。它还没有进入 full-adder detector，因为该设计没有对应组合 motif；这正是“可报告的未恢复 residual”，不是失败后丢逻辑。

## 当前已知限制

1. `SourceGraph` 目前以 Yosys JSON 为输入；HAL gate-level cell/clock/reset 元数据尚未接入统一 IR。
2. 匿名化仍公开端口方向和 bit 数量；这是可配置的评测条件，不是完全隐藏 bus 形状的最终协议。
3. detector 仅支持 scalar `$xor/$and/$or` full adder，不处理 mapped library cells、multi-output side logic、状态或模块边界搜索。
4. exhaustive backend 是小候选的 sanity/proof backend，ABC backend 只证明隔离组合 region；没有 whole-design sequential proof。
5. recovery overlay 尚未生成带残余实例的可综合行为 RTL；M0 的交付对象是可审计 source-preserving artifact。

因此本次结果证明的是 Harness 安全闭环的最小性质，不是语义恢复率、LLM 增益或真实 benchmark 性能。下一阶段要把 HAL/Yosys 的状态事件模型放入 IR，再实现真实 mapped-cell 的候选适配和分区 sequential proof。
