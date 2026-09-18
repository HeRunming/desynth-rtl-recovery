# Harness M0/M1：实际 RTL 发射与整体验证

日期：2026-09-18。以 [Harness v2 设计](HARNESS_V2_DESIGN.md) 为目标，本文记录其首个有明确支持范围的可执行闭环；不表示整个研究系统或 M1 的全部语义类别已经完成。

## 交付内容与验收边界

现在可以运行：原始 Yosys 图准入 → 匿名化 → 结构候选 → 局部 ABC 证明 → 真实加法 RTL 替换与完整 residual 发射 → 重读实际 RTL → Yosys SAT 与标准 ABC CEC 复核。失败候选不删除源逻辑；最终产物失败时尝试发射并证明原始完整 residual，失败尝试仍单独留档。

- **源图与匿名化**：规范化内容以不可变字符串及 SHA256 绑定；调用者只能取得副本。匿名化先检查原图，拒绝未建模 memory/process/库单元；打乱 cell/port/wire ID，删除源名、内部 bus 分组与调试属性，保存初态。源映射独立保存在 evaluator 目录。端口方向和位宽仍公开。
- **候选与边界**：当前仅自动发现 scalar XOR/AND/OR full-adder。验证所有外部扇出；若内部 XOR/AND 仍被外部使用，保留对应门及其依赖闭包。接受后用两次显式零扩展的 2-bit `$add` 实现 sum/carry。
- **局部证明**：小域穷举或独立源/候选 AIG 的 ABC CEC；只有正确退出和明确等价判词才能通过。保存反例、timeout、工具错误及文件哈希；接受和缓存复用重新检查证据。小候选另做独立穷举重放，不信任调用者写入的 `proven` 标志。
- **完整发射**：原始图保持不变；仅移除被接受且无需保留的源门，所有其他逻辑和状态进入真实 Verilog。overlay 报告与实际 RTL 替换计数分开，局部成功不直接产生全局成功。
- **持久续跑**：SQLite 按 source/candidate 建义务，每次重试独立记录 engine、budget、终态。独占 runner 才能回收中断任务；只复用证据仍有效的证明。每次运行独立 release，根报告原子更新；运行开始先清除旧成功状态，异常不会遗留本次 `proven`。

代码入口：`harness/ir.py`、`state.py`、`candidate.py`、`detect.py`、`proof.py`、`recovery.py`、`emit.py`、`jobs.py`、`runner.py`。

## Whole-design 证明的具体含义

当前支持单个已展平模块、无组合环的二态逻辑，以及状态保持的 `$dff/$adff/$dffe/$adffe`。顺序设计要求同一直接输入时钟域，异步 reset 为直接输入；不支持状态重编码。

验证器分别导入不可变源图与**实际发射文件的快照**，显式核对全部原始输出、状态 Q 双射、每一位初值、时钟边沿和复位值/极性。所有 Q 作为共同且自由的切点，证明全部输出函数和全部 D/clock/reset 函数一致，包括不可从输出观察到的状态。启用控制按真实逻辑展开。

在这些前提下，初态一致且完整转移函数一致，支持状态保持的整机等价结论。验证先运行 Yosys SAT，再运行独立 AIG 上的标准 ABC CEC；不使用源内部信号同名作为等价假设，不通过 async2sync 更改事件模型。任何初值、边沿、状态缺失或输出差异均拒绝。

这不是任意多时钟/四态/memory/黑盒/重编码设计的顺序等价，也不是独立形式证明证书。导入器、语义模型、miter builder、Yosys 和 ABC 仍在可信计算基内；版本、命令、哈希和日志支持审计及重放。

## 开发集结果

入口为 `scripts/run_harness_m1.py`，5 个仓库已有网表，每个使用匿名种子 17、42、99。worker 只收到匿名 JSON 路径；当前目录隔离尚不是操作系统权限隔离，接入不可信模型前需要进一步落实 evaluator/worker 隔离。

| 开发设计 | 源 cell 数 | 每 seed 发现/接受 full-adder | 实际替换源 cell | 保留源 cell | 全设计结果 |
|---|---:|---:|---:|---:|---|
| counter | 38 | 0 / 0 | 0 | 38 | 三次均通过 |
| traffic | 67 | 0 / 0 | 0 | 67 | 三次均通过 |
| alu8 | 235 | 3 / 3 | 9 | 226 | 三次均通过 |
| fifo | — | 未运行 | — | — | 源图准入拒绝，三次均报告 unsupported |
| uart_tx | 162 | 0 / 0 | 0 | 162 | 三次均通过 |

共 15 个设计/seed 组合，12 个完成实际 RTL 全设计验证，3 个未获准入；种子重复不算独立设计。FIFO 含未展开 `$memrd/$memwr_v2`、memory 声明和组合 `X`，不能擅自把 don't-care 置零后宣称等价。必须先补齐并独立验证 memory/未定义值契约。

**更正旧报告**：ALU 的 3 个候选覆盖 15 个源门，但其中 6 个共享门必须保留，故实际替换为 9 个、保留 226 个；之前“替换 15 个、保留 220 个”的 overlay 结论不成立。本轮实际 RTL 的全设计证明覆盖修正后的实现。

这些是小型开发设计，尚无外部 held-out benchmark 的语义恢复率、PPA、LLM 增益或性能主表。无候选设计的成功说明 residual 保真，不算新增高级语义。

## 回归与故障注入

测试覆盖真实 full-adder → `$add`、共享 side output 保留/错误删除、宽位/有符号 residual、初值和多位匿名顺序、异步 reset/enable、输出及不可观察状态 D 的篡改、时钟边沿变化、状态映射缺失、多时钟/未知单元拒绝、缺失证明/伪造判词/证据篡改、timeout、进程中断与历史保留、端口独占 wire ID、失败 RTL 回退和旧成功报告失效。

本次完整回归 **58 项全部通过**，15 组 campaign 已用最终代码重新执行。见 [可机读汇总及完整证据归档](../artifacts/harness_m1/README.md)。归档前逐一核对了 12 个成功 RTL 的快照、报告和证明哈希，以及证明目录内的全部文件哈希。

原 `tests/test_repair_gate.py` 一并运行，legacy Config A 路径未修改。本轮不把历史 CPU 仿真当成新 Harness 的整机证明。

## 重现

需要 Python 3.10+，Yosys 和 ABC；不需要 LLM 凭据。建议使用新输出目录，保留原始证据。

```sh
export YOSYS=/path/to/oss-cad-suite/bin/yosys
export ABC=/path/to/oss-cad-suite/bin/yosys-abc
python3 -B -m unittest discover -s tests -v
python3 -B scripts/run_harness_m1.py --out /tmp/harness-m1-run --seeds 17 42 99
```

campaign 因 FIFO 明确 unsupported 返回非零，这是预期汇总状态，不能解读为 15/15 成功。`campaign.json` 汇总所有失败；各成功 worker 保留 `report.json`、SQLite 尝试记录、候选证据、真实 RTL、命令日志和整体验证结果。重新用同一 worker 输出目录运行 `harness.cli recover` 可检验证据后续跑。

旧 `scripts/evaluate_harness_m1.py` 仅做 annotation-only 评估，明确标记 `whole_design_proven=false`；最终 RTL 结论以新入口为准。

## 下一阶段

M1 尚需扩展 bus/region 假设与更多语义类别。优先接入有界 HAL/结构查询和统一候选 API，以已有最终证明门禁约束 LLM；随后增加可复综合、许可及库模型可确认的真实非 CPU pilot。比较固定规则、LLM 静态摘要、LLM 查询和完整恢复闭环的同预算增益。memory、多域和状态重编码另立模型验收门槛。
