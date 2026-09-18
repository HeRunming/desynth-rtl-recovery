> Historical research note. For the accepted Config A MUL repair, see [CONFIG_A_REPAIR_REPORT.md](CONFIG_A_REPAIR_REPORT.md). Other findings retain their original status.

# ASTRA 架构与研究审查

审查范围：本地 `agent/`、`pipeline/`、`STATUS.md`、`HANDOFF.md`，以及服务器 `/data/hrm/desynth/work/big` 的只读产物。审查日期：2026-09-11。没有修改核心代码，也没有把用户提供的 API key 写入文件。

## 结论先行

当前系统已经证明“HAL 精确提取 + 结构化命名 + 局部 Z3 提升 + 仿真回归”能够在 PicoRV32 上产出可工作的 RTL；它还没有证明“完整门级设计等价”，也没有证明 HAL 在统计意义上稳定优于纯 LLM。主要风险集中在三个边界：未提取状态被发射为 `X`、验证主要是随机仿真、以及各阶段 schema/环境契约不统一。下一阶段应先让验证结果可判定、可复现，再做字级算术恢复。

## Findings（按严重性）

### P0-1：Config A 存在 33 个未提取状态位，当前结果不能称为完整等价

证据：服务器 `work/big/big_mech.json` 有 2313 个 `ff_defs`，其中 33 个 `func=null`；`diag_thresh.log` 给出 cone 3064 到 9066，范围是 `pcpi_mul.rd`。`assemble_lifted.py:292-303` 将这类位发射为 `1'bx`。远端 `verify_big.log` 的“0 mismatches / 899820 checks”只是 50000 周期端口仿真，且没有激活 MULH 路径的覆盖证明。

影响：一个未定义的 next-state 可以在未触达时不影响端口，但这不能推出对所有输入序列等价。尤其乘法器高位是本项目要研究的最难路径，随机测试恰好最容易漏掉它。

建议：把状态完整性作为硬性 verdict 字段（`proved`、`covered`、`unknown` 分开）；对所有 `func=null` 做静态输出 cone 可达性分析；在 X 存在时禁止报告“design equivalent”。最终用分块 miter/SAT 或 word-level 算术模型证明。

### P0-2：验证器的通用性声明高于实现能力

`agent/verifier.py:48-55` 接受 `liberty` 参数但完全没有使用；`CELLS_SIM`（`verifier.py:12-22`）只定义固定的 `FF/FFR/FFS/INV/BUF/TBUF/AND2/OR2/XOR/MUX`。遇到另一套 liberty cell、异步复位、时钟沿或多电源控制时，Yosys 可能把 cell 当黑盒或改变时序语义。`verifier.py:35-39` 直接运行 `equiv_induct`，失败时也只返回摘要，不区分“反例不等价”“模型缺失”“超时”。

影响：该函数不是可靠的设计级裁判；失败可能是模型问题，成功也只代表当前行为模型下的成功。小样本网表刚好使用了固定原语，掩盖了契约缺口。

建议：从 liberty 自动生成/加载 cell 行为模型并校验 cell 覆盖率；把同步/异步 reset、初值、clock domain 明确建模；验证结果至少分为 `proven/failed/unknown/model_error/timeout`，并保存完整 Yosys script 和日志。

### P0-3：输出缺失时默认驱动常量 0，存在静默掩盖错误的路径

`agent/assemble_lifted.py:639-653` 在 HAL 没有输出定义或输出位未被记录时，向端口补 `1'b0`。相比未提取 FF 的 `1'bx`，这个 fallback 是确定值，可能让未覆盖端口在特定激励下“看起来正常”。注释说明了“HAL 未含此端口”，但没有让验证器把它标成失败。

建议：缺失输出统一发射 `X` 或直接中止组装；端口覆盖率为 100% 才允许进入等价测试。对每个输出保存来源（direct FF、HAL function、fallback）并纳入 verdict。

### P1-1：命名阶段的 schema 契约断裂，端口提示通常为空

`semantic_naming.py:305-309` 读取 `data.get("ports", {})`；但 `hal_mechanical.py:82-90` 输出的是 `input_net_ids`、`output_net_ids`、`net_meta`，没有 `ports` 字段，`mech_cse.py` 只是原样传递该 schema。因此命名 prompt 的 `port_hint` 通常为空。类似地，`hybrid_pipeline.py` 使用的是独立 `hal_extract.py` 的 `top_ports` schema，两条链路没有统一格式。

影响：语义命名少了最便宜且最可靠的端口线索；实验之间的 prompt 信息量不一致，不能直接横向比较。

建议：定义版本化 schema（例如 `schema_version=1`, `ports.inputs/outputs`, `ff_defs`, `net_meta`），在每个阶段入口做 JSON schema 校验；兼容旧文件时显式转换并记录转换日志。

### P1-2：DANA 失败会静默降级，hybrid 结果可能其实是弱线索 baseline

`hal_extract.py:51-67` 捕获 DANA 异常后只写 `dana_error`；`hybrid_pipeline.py:108-115` 仅检查顶层 `error`，有 `dana_error` 仍会把事实当作成功线索喂给 LLM。这样“HAL+LLM”可能只包含端口和门统计，实验标签却仍是 hybrid。

建议：DANA 失败时写入 `hal_status=partial/error`，实验报告按实际线索分层；对比矩阵同时记录“完整 HAL、部分 HAL、无 HAL”。

### P1-3：随机 testbench 覆盖不足且不可复现

`gen_tb.py:82-86` 和 `gen_tb_internal.py:66-70` 对输入逐拍使用 `$random`，没有固定 seed、测试向量归档或指令级约束；`gen_tb.py:80-88` 固定跳过复位传播期，默认只做端口比较。服务器 `verify_int_big.log` 只有 3000 周期、171 个同名同宽寄存器，`verify_partial.log` 也是 3000 周期内部比较。

影响：50000 周期和约 900k checks 是数量指标，不是状态/指令覆盖指标；MUL/MULH、异常、边界地址等路径可能从未触达。内部比较只比较 raw/lift 两侧同名寄存器，未覆盖 33 个 X 位，也无法发现命名导致的错位。

建议：保存 seed 和每次输入；加入合法 RISC-V 指令流生成器，定向覆盖 MUL/MULH/MULHSU/MULHU、零/最大操作数、异常和 back-pressure；统计状态、opcode、PCPI handshake 和每个 skipped cone 的可达性。内部比较应以 net id 映射为主，覆盖所有状态，包括 unnamed/skipped。

### P1-4：多时钟/多复位设计被压成单一同步时钟模型

`assemble_lifted.py:481-504` 对所有 bus 生成一个 `always @(posedge clk)`，复位由 `if (~rst)`包裹；`lift_runner.py:86-92` 和 `pico_lift_runner.py:39-43` 通过“第一个名字包含 rst/reset/clr 的 input”选择 reset。HAL 提取器 `hal_mechanical.py:40-60` 只按 D/Q pin 找 FF，没有把 clock/reset 类型纳入 FF 语义记录。

影响：对含多个 clock domain、异步 reset、置位 FF 或不同极性的真实网表，可能把时序行为错误地重建为同步单时钟 RTL。当前 PicoRV32 单域样本不能排除该风险。

建议：在 netlist schema 中记录每个 FF 的 clock、edge、reset/set pin 和 polarity；按 domain 分组生成 always 块；无唯一 reset 时停止自动猜测，要求显式参数。

### P1-5：LLM 输出的结构错误被自动修补，质量退化没有进入实验指标

`semantic_naming.py:263-289` 的 `validate_plan` 会删除重复 ID、自动补 `unnamed_<nid>`，但 `main()` 在 `semantic_naming.py:351-355` 忽略返回的 `ok` 和 `prob`，只按 `plan.get("error")` 计数。批次即使覆盖错误或重复，也可能被记为无错误。

建议：记录每批原始 plan、missing/dup/extra 数量和修补数量；把自动修补率作为主要质量指标；超过阈值时重试或判该批失败，不要只看最终 JSON 能否组装。

### P2-1：路径和入口硬编码，服务器迁移后易产生“旧产物成功”

`hal_extract.py:13-15`、`hal_mechanical.py:15-17`、`hybrid_pipeline.py:25-33`、`run_matrix.sh:6-10` 写死 `/Users/blackbox/try_hai` 和 macOS 工具路径；`pico_lift_runner.py:9-13` 还固定读写 `/tmp/pico_*.json`。远端 canonical 路径已经是 `/data/hrm/desynth`，通用 `lift_runner.py`虽较好，但旧入口仍可被误调用。

建议：统一 CLI 配置（项目根、HAL、Yosys、Z3、输出目录），启动时打印并校验绝对路径、文件 hash 和 git revision；禁止从固定 `/tmp` 读取未带 manifest 的输入。

### P2-2：实验矩阵的比较口径不平衡，结论存在过度外推

`agent/run_matrix.sh:14-29` 只跑 `alu8/fifo/uart_tx` 三个设计；仓库的 `matrix_results.txt` 是旧结果，FIFO baseline/hybrid 均 4 轮失败，而 `HANDOFF.md` 已说明 v2 FIFO trace 后来成功、UART 与 UART_TX 实为同一顶层，`traffic` 仍未通过。重试次数、提示长度、模型/温度和 API 响应没有成本或 token 归一化。

因此不能从当前材料推出“HAL 稳定提升成功率”。应报告每个设计、版本、轮数、token、延迟、HAL 是否完整、失败原因，并把同一设计的 v1/v2 视为修订实验而非独立样本。

### P2-3：表示层仍是逐位函数，跨函数共享没有进入命名输入

`mech_cse.py:13-19` 明确采用逐函数 CSE，不做跨函数共享；全局 CSE 在 `assemble_lifted.py:327-409` 已经太晚，LLM 命名阶段仍看不到跨位/跨 FF 的算术结构。远端实测 Config A 49 个 FF 占 98% 文本，最大单函数约 87.6M 字符，33 位因 cone 阈值跳过。

这不是简单提高阈值即可解决的性能问题，而是抽象层级问题：需要共享 DAG、AIG/ABC 局部模式或 word-level 中间表示。

## 架构与验证体系评估

优点是阶段边界清楚，HAL 提取和结构提升可缓存，CSE 有独立 Z3 反例控制，且内部寄存器比较比单看端口更有诊断价值。主要缺口是“数据完整性”和“验证证据”没有成为流水线的一等对象：产物缺少统一 manifest，`func=null`、DANA error、fallback output、自动修补和 timeout 没有汇总成单一状态；验证脚本也没有把 unknown 与 failed 分离。

建议每个阶段输出：输入 hash、工具版本、schema 版本、计数（输入 FF/输出 FF/缺失/修补/超时）、状态枚举和日志路径。最终报告只从 manifest 生成，避免手工把不同版本日志拼成一条结论。

## 调研与技术路线

### P0 字级算术旁路

现有 `STATUS.md` 记录了一个有价值的先导实验：相同 liberty 映射下，32x32 乘法器经 ABC `&atree` 实测检出 1114 个 FA，0.01 秒完成；这说明综合流程尚未破坏全部算术结构，且局部模式识别远比构造整锥布尔函数合适。建议旁路仅接管 `cone > threshold` 或超大函数：先在 AIG 上识别 FA/HA/CSA/Booth 局部结构，再根据位拓扑组装候选 word operator，最后对候选算子做 miter/SAT 证明。不要把 ABC 检出直接当成语义真值，优化后的乘法器可能失去模板；`STATUS.md` 已记录 BoolE 在激进 `dch` 乘法器上精确 FA 检出为 0 的反例。

最小可行实验：对 Config A 的 `pcpi_mul.rd` 32 个已提取位和 33 个 skipped 位，固定同一 netlist/hash，比较 (a) 当前 X、(b) ABC 局部识别、(c) 手工 word-level candidate；对每个 candidate 做逐位 miter，并跑 MUL/MULH 定向仿真。成功标准是所有 64 位都有来源且 candidate 被 SAT 证明，失败时保留原始位函数/X。

### MUL 定向激励

生成合法 RISC-V R-type 指令，而不是随机 `mem_rdata`。覆盖 `MUL/MULH/MULHSU/MULHU`、rs1/rs2 为 0、1、全 1、符号边界和随机值；控制 `pcpi_valid/ready/wr` 的握手与等待周期。每个测试保存 seed、指令序列、命中状态和首次 X 传播周期。这样可以把“未传播到输出”从偶然观察升级为可复核覆盖结果。

### 形式化验证

先做组合/下一状态函数级证明，再做按总线或 clock domain 的分块 sequential miter。对 skipped 位使用三值/未知标记，禁止被普通 `equiv_induct` 的寄存器配对问题掩盖。若完整 design miter 超时，报告 `unknown`，同时给出已证明块的集合和未证明块的集合。

### HAL/ABC 集成

保留 HAL 作为精确边界与 net metadata 来源，把 ABC 用作结构识别器，而不是替代 HAL。中间表示建议是带 source net/bit provenance 的 AIG/DAG：HAL 提供语义无关的精确节点，ABC 提供局部算术候选，LLM 只负责候选命名和解释。候选必须携带证明状态，组装器只消费 `proven` 候选。

参考方向（项目已有文献记录）：ABC 算术结构识别（2017）；ReveNGe 的库匹配/子图同构；BoolE 的等式饱和；AMulet 的等式重写；基于进位链的 LUT/网表字级重建。使用这些工作时要保留适用条件：模板依赖、对激进优化乘法器的退化、规则人工剪枝，以及 Wallace/非标准树覆盖不足。

## 分阶段改进路线

### 阶段 0：证据和契约（1-2 天）

统一 schema、manifest、路径配置和 verdict 枚举；修复 `ports/top_ports` 转换；记录 DANA/LLM 修补/skip/fallback；输出缺失改为 hard failure。最小实验是对现有 Config B 重新生成 manifest，并确认输入 hash、2435 FF、502 bus、skip=0、验证日志可由脚本自动汇总。

### 阶段 1：验证补强（2-4 天）

加入固定 seed 和向量归档、MUL 指令生成器、状态/opcode/握手覆盖、按 net id 的内部比较；做 3 个分块 miter（控制状态、数据寄存器、PCPI MUL）。预期收益是把当前“仿真通过”拆成可解释的 proven/covered/unknown，风险是 SAT 在大锥超时；最小可行范围先选 8-bit 小型乘法器和 Config B 的 PCPI 控制块。

### 阶段 2：ABC 字级旁路（3-7 天）

建立 AIG 导出、`&atree`/算术候选解析、bit provenance 和候选 miter。先处理 Config A 的 33 skipped 位，再处理 13 条未提升进位总线。预期是消除 `1'bx` 洞并显著改善可读性；风险是优化结构的识别率低，必须保留 raw/X fallback。最小成功指标：32x32 先在合成样例和 PicoRV32 乘法器上证明一个完整 word candidate。

### 阶段 3：跨函数 DAG 和可重复矩阵（1-2 周）

把 `mech_cse` 的文本解析升级为共享 DAG/结构 hash-consing，LLM 输入使用有界的局部 DAG 摘要；重新跑经过版本锁定的设计矩阵，至少包含 traffic、FIFO v2、两个 Pico 配置和一个激进优化对照。预期是降低长尾 token/内存并测量 HAL 的真实增益；风险是 DAG 规范化可能改变 LLM 线索，需要独立语义/等价回归。

## 最小下一步清单

1. 先修复 schema、manifest、缺失输出 hard failure 和 verdict 枚举。
2. 对 Config A 生成 MUL/MULH 定向向量和 skipped-bit 输出 cone 报告。
3. 用 ABC 旁路只处理一个 `pcpi_mul.rd` word，逐位 SAT 证明后再接入组装器。
4. 重新生成一份可自动汇总的 A/B 对照矩阵，区分成功、修补、unknown 和失败。
