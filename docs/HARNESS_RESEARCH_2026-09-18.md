# 语义恢复 Harness：现状与工具调研

日期：2026-09-18。代码审查基线：`21ea019ff0d6fa348ad09af29b1868cb10b34ad4`。

本轮目标是重新对齐研究问题，不是继续扩展 Config A 特定修复。本文记录静态代码审查、官方工具文档/源码、论文阅读；除 HAL Python API 导入探测外，没有运行新恢复实验，也没有重测论文性能。设计提案和验收步骤见 [HARNESS_V2_DESIGN.md](HARNESS_V2_DESIGN.md)。

## 1. 判断：已有成果有价值，但主线确实偏移

用户的目标是：**强 LLM + 结构化 Harness + EDA 工具，在匿名化真实网表上，可验证地恢复更多高级语义。**

最近工作实际闭合的是：已知 PicoRV32 Config A 的乘法器位置、操作数和语义之后，修复 33 个缺失的下一状态位，证明 64 个乘积输出的组合等价，并完成全设计仿真回归。这解决了真实缺陷，也建立了可复用的证据绑定和回放机制；但未证明匿名候选发现、未知模块边界恢复、LLM 增益或整机形式化等价。

| 现有工作 | 应保留的价值 | 不能据此声称 |
|---|---|---|
| 小电路 baseline / HAL hints + LLM | 基线入口、轨迹和失败案例 | 真实规模下的统计优势；当前 hybrid 仍输入完整网表 |
| HAL 机械提取、CSE、寄存器分组 | 连接关系、局部功能、共享表达式的探索 | 完整状态机模型；DANA 分组不是真实模块边界 |
| LLM 命名、分组、架构说明 | 局部摘要经验、语义假设 | 好名字等于恢复功能；带设计名实验等于匿名实验 |
| Z3 模板提升 | 计数、移位、装载等候选库基础 | 任意功能恢复；对表达式证明等于最终 RTL 正确 |
| Config A 乘法器修复 | 原网表导出、ABC CEC、负例控制、hash 门禁、回放 | 匿名自动识别乘法器；其他设计也已修好 |
| 全端口和全状态仿真 | 重要回归与反例诊断 | 全输入序列形式化等价 |

之前“完全修复”的完成边界应理解为 **Config A 指定修复及其回归**，不是通用系统所有缺陷都消失。继续围绕原始 `pcpi_mul.*` 名称手调更多特例，会加深偏移。

## 2. 当前代码的关键缺口

以下行号对应上述基线。新增问题是静态路径发现，尚未做专门的可执行最小复现，实施阶段应先把它们转成故障用例。

| 问题 | 证据 | 对新 Harness 的要求 |
|---|---|---|
| 全文网表 + 静态 hints，重试整份 RTL | `agent/hybrid_pipeline.py:56,59,70,124` | 换成有界、按需结构查询和局部候选事务 |
| D/Q 提取没有完整 clock/reset/enable/initial 语义 | `agent/hal_mechanical.py:43,49,59,63` | 从库和连线取得状态语义；不能根据名字猜 |
| 匿名时可能找不到时钟，所有状态统一 posedge、初值 0 | `agent/assemble_lifted.py:289,473,482,484` | 保留实际事件/初始化模型，域不明则拒绝相应转换 |
| 复位检测尝试两种极性却丢弃命中极性，发射固定低有效 | `agent/struct_lift.py:351,354`; `agent/assemble_lifted.py:497` | 候选包含极性；证明实际发射产物 |
| `func=None` 被当作 False 进入提升 | `agent/struct_lift.py:649` | UNKNOWN 不是常数；原图必须一直保留 |
| 大锥跳过后只剩空函数，发射时变 X | `agent/hal_mechanical_chunked.py:84,142`; `agent/assemble_lifted.py:43,639` | 未恢复区保留原门图，不能用 X/0 补洞 |
| 通用 lift cache 无输入 hash/库/假设绑定 | `agent/assemble_lifted.py:307` | 推广 Config A 的证据绑定，缓存命中必须校验 |
| 反例、unknown、超时被压成布尔失败；批次结束才保存 | `agent/struct_lift.py:263`; `agent/lift_runner.py:106,134` | 持久任务、分类结果、反例回放、硬 deadline、断点续跑 |
| 部分 bit 提升却按整条总线计数 | `agent/struct_lift.py:540,555`; `agent/lift_runner.py:124` | 逐位/逐对象账本；语义覆盖和机械改写覆盖分开 |
| 固定 cell 模型，liberty 只检查名称，无条件 async2sync，删证明目录 | `agent/verifier.py:12,35,61,109,140` | 库语义验收；不默认改模型；持久证明包 |
| 架构 prompt 明示 PicoRV32/RISC-V，并传原网名 | `agent/arch_recovery.py:21,37` | 严格隔离 golden/source/name 信息 |
| 分组依赖 net ID 邻接，并重排位序 | `agent/semantic_naming.py:213`; 端口名提示 `:316` | 匿名 ID 随机置换；位序必须显式假设并验证 |
| regroup 的匿名化是 no-op，结果未进恢复闭环 | `agent/regroup.py:43,89` | 多边界候选应进入搜索/验证，不止 purity 报告 |

Config A 的 `repair_mul_word.py` 和 `scripts/config_a_proof/build.py` 明确依赖固定 qid、顶层和原始寄存器名。它们应成为 **proof service 的参考实现与回归样本**，而不是新系统的发现算法。

## 3. 工具调查：优先用什么，分别能做什么

### 3.1 HAL：比当前用法丰富，但不是正确性裁判

官方仓库提供图表示、Python/C++ API、解析/写出、DANA、时钟树、仿真和 igraph 集成 [S1]。本地源码版本为 `391881cd4cb94fb25a6fd0abffed94fc55378ced`。

**DANA** 使用控制信号、前后继和结构信息恢复寄存器分组 [S2]。适合作为多种 bus 假设的一个来源；不是总线位序、功能或设计原有层次的证明。不可把给定优先宽度当成不计成本的先验。

**module_identification 是本轮最值得接入的发现。** 插件已经采用“base candidates → 结构变体 → 操作数/位序/控制信号功能假设 → SMT 检查 → 选择候选”的流程 [S3]。README 明确支持加减、比较、常数乘等；不应把常数乘宣传为通用双变量乘法器发现。其自动结构候选生成是架构相关的，当前文档支持 XILINX_UNISIM 和 Lattice iCE40。因此 ASIC 标准单元输入需要自己的候选边界适配器。

`execute_on_gates` 允许对已有候选 gate 集做识别，是我们接入 ASIC region proposer 的合适入口。仍需核验支持的 cell/BooleanFunction 和候选输出是否完整，不能由 API 存在推断任意 ASIC 都能运行。

尤其注意 `VerifiedCandidate` 的定义 [S4]：它记录覆盖的 control assignments、逐控制赋值的 word-level operation；`m_total_output_nets` 和 `m_output_nets` 可能不同。**插件的 verified 不是整个 region 在所有控制情况下、所有输出均可替换的许可证。** Harness 必须补齐边界/控制覆盖，并对原图独立证明。

**solve_fsm** 可在给定状态寄存器和转移逻辑后分析 FSM [S5]；不是无需边界的全设计状态机发现。状态爆炸、未知初值、非法状态和控制输出仍需我们管理。第一版保留编码、输出状态转移表，避免直接重编码。

**bitorder_propagation** 本地有源码，但未见对应构建插件；作为后续候选工具，不列入即用能力。

可用性实际检查：设定 `HAL_BASE_PATH`、`PYTHONPATH` 并用 `/usr/bin/python3`，`hal_py`、`dataflow`、`module_identification`、`solve_fsm` 可以导入；`execute`、`execute_on_gates`、`Configuration` 存在。直接 HAL CLI 仍遇到动态库加载路径问题。本轮未执行 module identification 功能 smoke，不能称整合已完成。

### 3.2 Yosys / ABC / SMT：构建可验证功能边界

| 工具 | 核实能力 | 在 Harness 的位置 | 重要局限 |
|---|---|---|---|
| Yosys RTLIL/JSON、`read_liberty` | 解析/归一化；liberty frontend 有 function、FF/latch 建模代码 [S6] | 输入审计、候选编译、实际 RTL 重读、miter | `read_liberty -lib` 只建黑盒；库缺语义不能忽略；不支持项须明确拒绝 |
| ABC | AIG 变换、CEC、算术结构识别 [S7,S8] | 算术候选、组合/下一状态等价 | 算术识别依赖保留下来的 cutpoint；激进优化会破坏；变换后 net ID 不自动对应原图 |
| Z3 / bit-vector SMT | 现有模板验证已使用 Z3 | 有限候选空间、控制谓词、宽度/符号/截断验证、反例 | 宽乘法/大公式可能昂贵；只用 SMT 不解决规模与边界发现 |
| EQY + SBY | 分区、match/collect、依次尝试策略、超时、反例；k-induction、PDR [S9,S10] | 后续时序等价、分区验证与 invariants | 需正确匹配点；匿名输入不应靠原始名字对齐；BMC 无反例不是无限时域证明 |
| Icarus / Verilator | 仿真；本项目已用 Icarus 做回归 | 快速证伪、反例回放、覆盖 | 不是等价裁判；二值/四值行为和初态必须一致 |
| AMulet 2.2 | 对 unsigned/signed multiplier AIG 验证/认证，支持 proof checker 链接 [S11] | 困难乘法候选的可选专用验证后端 | 需要已知操作数/规约与适配的形状；截断/混合控制不能未经适配直接套用 |

Yosys `fsm_detect` 依赖 `$dff/$adff`、mux tree 和特定用途形状 [S12]。不能期待对任意 flattened、technology-mapped 网表执行 `fsm` 就自动恢复状态机；`memory_collect` 类似，不能凭空还原已完全展开的任意存储结构。

Config A 留下的重要教训是：实验性 `&acec` 曾产生不能在原始 AIG 上重现的“反例”，标准 `&cec` 后来证明等价。新系统必须把**发现、变换、证明、原图反例回放**分开；不盲信日志中一个 success/failure 字样。负例测试是验证检查链的补充，不能代替正确 proof model。

### 3.3 研究方法：可以接入，但不应都放进第一版

| 方法/论文 | 本轮核实结论 | 建议 |
|---|---|---|
| ABC Structural Reverse Engineering of Arithmetic Circuits [S8] | cut enumeration 检测 HA/FA、adder tree 和边界；原文明示依赖内部 cutpoint 保留 | 第一批算术 detector；保存极性、位权和源边界，不仅正则解析文本统计 |
| Simulation Graphs for Reverse Engineering / ReveNGe [S13] | 用 simulation graph 匹配库组件，LAD/SAT 找候选，再标准等价验证；边界定位仍需预处理 | 借鉴 simulation signature + library matching；论文给旧源码链接，本轮未验证能构建 |
| Reverse Engineering Word-Level Models from Look-Up Table Netlists [S14] | 分析 FPGA carry-chain、K-cut、顺序模块，产出高层 Verilog | FPGA 专用 adapter；不是 ASIC 通用方案。纠正本地模糊文件名，不应误当 HAL 插件论文 |
| BoolE [S15] | Boolean equality saturation 恢复多输出结构/精确 FA，并改善乘法验证；论文测试含 post-mapping 和 dch 优化 | 困难局部 region 的后续探索，设置 e-node/内存/时间上限；所读论文未找到可确认官方代码链接 |
| ReVEAL [S16] | GNN 推断乘法器结构，用 SAT 确认逆向映射，为代数验证服务 | 作为后期 detector；不是完整 RTL 恢复器；本轮未确认公开可复现 artifact |
| mockturtle [S17] | AIG/MIG/k-LUT 网络和 cut enumeration 等 C++ 算法，README 给完整 API 示例 | ABC 输出不足时补专用 cut/signature adapter；无需一开始再造图引擎 |
| egg [S18] | 可取得的 e-graph / equality saturation 库 | 可实现受限位向量规则；egg 本身不是已完成的硬件逆向工具 |

不能把论文给出的加速比直接写成我们的预期性能，也不能把“论文方法已读”写成“代码已接通”。商业 Conformal/Formality 可以成为有许可证时的额外交叉裁判，但当前不应作为复现链的必需条件。

## 4. Benchmark 选择也需要纠偏

之前 README 把 GenEDA Task 3 排在第一位，但项目的 benchmark review 并没有取得其可核验 artifact。这种优先级没有足够证据，应撤回。新系统不需要等待一个不确定的比赛包才开始。

推荐分三层，所有层都单独报告：

1. **工程验收集**：自动生成和匿名化的小算术/控制/状态例子，加故障注入。用来判断系统是否可靠，不能支撑“真实设计效果好”。
2. **真实主试验**：固定上游 commit、配置、库和综合脚本的开源 RTL，独立综合后去除名称/层次/属性；至少覆盖非 CPU 控制设计、混合数据控制设计、真实 CPU。恢复 worker 不接触 golden RTL。PicoRV32 已高度参与开发，应列 development，不能作为主要 held-out 证据。
3. **外部网表泛化**：HAL benchmarks 的 Open8、PRESENT 等；官方 README 列出 Open8 LSI_10K 1,884 门、PRESENT 1,393 门、BasicRSA 79,787 门 [S19]。Open8/PRESENT 比 BasicRSA 更适合第一轮接入。上游 SOURCE 指针不等于同版本配对；可直接对输入网表证明等价，但没有配对 golden/标注就不能算源语义 recall。

EPFL 官方套件主要是组合电路、多种表示，适合字级恢复压力测试，不能替代时序设计 [S20]。IWLS 2005 官方页面确认 RTL 与 mapped 网表，但库完整性、再分发许可和配对仍需导入时验收 [S21]。GenEDA、ITC99/GNN-RE、所谓 PLDI decompilation suite 在本轮仍没有被提升为已验证可用主 benchmark。

**功能等价不需要原始高层 RTL**：匿名输入门图本身就是行为 oracle。**原语义召回率**才需要独立标注或合成前参考，并且综合消掉的功能不能计作“应恢复却没恢复”。

## 5. 本轮来源与核实层级

访问日期均为 2026-09-18。在线 README/文档是当日版本，未宣称它们已经安装；正式实验需另外锁 commit。HAL 的源码判断使用本地固定 commit `391881cd4cb94fb25a6fd0abffed94fc55378ced`。下列资料已实际读取，不是仅按标题列出。

- **S1** HAL 官方 README：https://github.com/emsec/hal 。图表示、Python/C++、DANA/clock tree/simulator、MIT 许可。
- **S2** DANA 官方实现说明：https://github.com/emsec/hal/blob/391881cd4cb94fb25a6fd0abffed94fc55378ced/plugins/dataflow_analysis/README.md 。论文 *DANA – Universal Dataflow Analysis for Gate-Level Netlist Reverse Engineering*，TCHES 2020：https://eprint.iacr.org/2020/751 （本轮读实现说明，未重新读取这份论文）。
- **S3** HAL module identification：https://github.com/emsec/hal/blob/391881cd4cb94fb25a6fd0abffed94fc55378ced/plugins/module_identification/README.md 。
- **S4** VerifiedCandidate：https://github.com/emsec/hal/blob/391881cd4cb94fb25a6fd0abffed94fc55378ced/plugins/module_identification/include/module_identification/candidates/verified_candidate.h 。
- **S5** HAL FSM API：https://github.com/emsec/hal/blob/391881cd4cb94fb25a6fd0abffed94fc55378ced/plugins/solve_fsm/include/solve_fsm/solve_fsm.h 。
- **S6** Yosys Liberty frontend：https://github.com/YosysHQ/yosys/blob/main/frontends/liberty/liberty.cc 。
- **S7** ABC 官方项目：https://github.com/berkeley-abc/abc 。
- **S8** Mishchenko, Sterin, Brayton, *Structural Reverse Engineering of Arithmetic Circuits*：https://people.eecs.berkeley.edu/~alanmi/publications/2017/tech17_arith.pdf 。已下载并提取正文。
- **S9** EQY quickstart/config/strategies：https://github.com/YosysHQ/eqy/tree/main/docs/source 。已读 NERV 示例、分区和策略文档。
- **S10** SBY reference：https://github.com/YosysHQ/sby/blob/main/docs/source/reference.rst 。
- **S11** AMulet 2：https://github.com/d-kfmnn/amulet2 。已读 README，包括 `-verify`/`-certify`/`-signed`、2.2 修复和 checker 链接；未安装重测。
- **S12** Yosys FSM detection：https://github.com/YosysHQ/yosys/blob/main/passes/fsm/fsm_detect.cc 。
- **S13** Soeken et al., *Simulation Graphs for Reverse Engineering*, FMCAD 2015：https://agra.informatik.uni-bremen.de/doc/konf/fmcad15_revenge.pdf 。已下载并提取正文。
- **S14** Narayanan et al., *Reverse Engineering Word-Level Models from Look-Up Table Netlists*：https://arxiv.org/html/2303.02762v1 。已读原文 HTML。
- **S15** *BoolE: Exact Symbolic Reasoning via Boolean Equality Saturation*：https://arxiv.org/html/2504.05577v1 。已读方法与实验；未取得官方实现。
- **S16** *ReVEAL: GNN-Guided Reverse Engineering for Formal Verification of Optimized Multipliers*：https://arxiv.org/html/2512.22260v1 。已读方法；未取得官方实现。
- **S17** mockturtle：https://github.com/lsils/mockturtle 。已读 README 和 cut enumeration 示例。
- **S18** egg：https://github.com/egraphs-good/egg 。已读 README。
- **S19** HAL benchmarks：https://github.com/emsec/hal-benchmarks 。已重新读取官方 README；许可/源配对仍参照先前 [BENCHMARK_REVIEW.md](BENCHMARK_REVIEW.md) 的未决项。
- **S20** EPFL benchmarks：https://github.com/lsils/benchmarks 。已读官方套件说明。
- **S21** IWLS 2005：https://iwls.org/iwls2005/benchmarks.html 。已重新取得官方页面。

本轮资料已缓存于研究机临时目录；此处仅收录自写分析和引用，不把外部论文或 benchmark 包复制进项目。
