> Historical research note. For the accepted Config A MUL repair, see [CONFIG_A_REPAIR_REPORT.md](CONFIG_A_REPAIR_REPORT.md). Other findings retain their original status.

# Benchmark 来源与可用性核查

核查日期：2026-09-11。范围是 `bmks.md` 中的候选，以及一个与当前 HAL 流程直接相关的公开仓库 `emsec/hal-benchmarks`。这里区分“已从官方页面/仓库核实”和“仅在论文或 `bmks.md` 中提及”；后者不作为已获得数据集的依据。没有使用或保存任何 API 鉴权信息。

## 可用性矩阵

| 候选 | 来源核查 | 许可证 | RTL 与 netlist | cell library / 综合脚本 | 适用性与结论 |
|---|---|---|---|---|---|
| GenEDA Task 3, ICCAD 2025 | `bmks.md` 称有 9 个 arithmetic designs，但工作区没有 DOI、官方 URL 或 artifact；本次公开仓库检索未定位到可确认的官方包 | 未核实 | 未核实 | 未核实 | 暂不能作为可复现实验输入。先取得 artifact 链接、版本和 license 文件 |
| IWLS 2005 | **官方页面已核实**：`https://iwls.org/iwls2005/benchmarks.html` 明确写有 84 个设计、最大 185,000 registers/900,000 gates；RTL 与 mapped Verilog/OpenAccess 都提供 | 页面没有明确再发布许可证；不要假定为开源 | **是**，页面明确写 RTL-source 与 mapped netlists | 页面写明 Cadence RTL Compiler、180nm library；下载页没有清楚说明 library 文件和完整脚本是否随包提供，library 区链接为 CRETE | 主 benchmark 候选，规模和配对最符合目标；但需先下载并做许可证审查 |
| ITC'99 / I99T | `bmks.md` 有旧链接；IWLS 页面列出 ITC99。当前 `itc99.dii.unisi.it` DNS 不可解析 | 未核实，不能按 OSS 使用 | 常见公开包有 HDL/测试资料，但本次未取得可验证的同版本 RTL+综合 netlist 配对 | 未核实，且不同镜像/版本差异大 | 适合顺序/FSM，但必须先固定来源、版本、cell 库和综合流程 |
| GNN-RE (TCAD 2022) | 在本地论文参考文献中确认论文：Alrahis et al., IEEE TCAD 41(8), 2435-2448；未定位到官方 benchmark 下载仓库 | 未核实 | `bmks.md` 的“37 designs”未能由可下载 artifact 复核 | 未核实 | 可作为领域对照论文，当前不适合作为复现实验输入 |
| PLDI'23 Hardware Decompilation suite | `bmks.md` 提到公开 artifact，但工作区没有 URL/commit；本次未获得可验证包 | 未核实 | 未核实 | 未核实 | 需要 artifact DOI/repository 和 license 后再纳入；声称“主要 loop recovery”不能替代 netlist→RTL 适配性验证 |
| ISCAS'85/'89 | 经典 benchmark 来源明确，但主要是门级/组合电路集合；不同镜像提供的格式不统一 | 通常没有清晰 OSS license，需按原始发布条款处理 | **通常不是成对的 RTL+综合 netlist**，不能直接用于完整恢复准确率 | 无统一 library/script | 只适合 parser、组合逻辑和结构识别 sanity check，不应作为主 sequential benchmark |
| EPFL combinational suite | 公开套件可获得 AIG/BLIF/Verilog 组合电路；本次未在工作区固定具体 commit | 具体文件/镜像许可证需逐项核实 | 主要是组合表示，不提供与原 RTL 成对的 mapped sequential netlist | 通常没有与当前 liberty 配套的官方综合脚本 | 适合 arithmetic/combinational 预实验；不适合验证 FF、reset、FSM 恢复 |
| `emsec/hal-benchmarks`（补充候选） | **仓库已实际克隆核实**：`https://github.com/emsec/hal-benchmarks`；README 列出 edge、ibex、Open8、tiny_aes、des、BasicRSA、sha-3、present、opentitan | 根目录及浅层文件中未发现 LICENSE；README 只给出各设计的上游 `SOURCE` URL，不能把整个仓库当作已获统一许可 | **映射 netlist 在仓库内**（LSI_10K Synopsys、XILINX_UNISIM Vivado）；原始 HDL 通常通过 `SOURCE` 指针获取，不保证同 commit/同参数 | LSI_10K 和 XILINX_UNISIM 的 cell 类型可由仓库外 HAL gate-library 定义支持；仓库本身没有统一综合脚本 | 当前最容易接入 HAL 的外部候选，但必须保留上游来源、netlist hash、library hash 和 license 记录 |

## 已核实的证据

### IWLS

官方页面的原文事实是：84 个设计；最大约 185,000 个寄存器和 900,000 个门；所有设计由 Cadence RTL Compiler quick synthesis 映射到 180nm library；以 Verilog 和 OpenAccess 两种格式提供；下载为 `IWLS_2005_benchmarks_V_1.0.tgz`。页面没有明确写许可证，也没有承诺提供可复现的综合脚本。因此报告指标应标为“官方配对数据可得、流程可部分追溯”，而不是“完全可重综合”。

建议下载后执行：

```bash
curl -fL http://iwls.org/iwls2005/IWLS_2005_benchmarks_V_1.0.tgz \
  -o /data/hrm/benchmarks/IWLS_2005_benchmarks_V_1.0.tgz
sha256sum /data/hrm/benchmarks/IWLS_2005_benchmarks_V_1.0.tgz
tar tzf /data/hrm/benchmarks/IWLS_2005_benchmarks_V_1.0.tgz | sed -n '1,80p'
```

下载包、网页快照和 hash 应一起保存；在确认许可前不要将其提交到项目仓库或公开镜像。

### HAL benchmarks

实际克隆的仓库在临时目录中包含：

```text
crypto/rsa/rsa_lsi_10k_synopsys.v
crypto/present/present_lsi_10k_synopsys.v
cpu/open8/open8_lsi_10k_synopsys.v
cpu/ibex_risc-v/ibex_lsi_10k_synopsys.v
```

README 还列出 LSI_10K/XILINX_UNISIM 的门数，并为每个设计提供上游源链接。例如 BasicRSA、Open8、IBEX 都有 `SOURCE` 文件；但 `SOURCE` 只是上游指针，不是锁定的 commit 或综合 manifest。LSI 网表头部包含 Synopsys DC 版本和日期，说明网表可追溯到综合工具，但仓库没有对应脚本。仓库没有根 LICENSE 文件，本项目应把“代码、网表、上游源”按不同许可证分别记录。

可复核命令：

```bash
git clone --depth 1 https://github.com/emsec/hal-benchmarks /data/hrm/benchmarks/hal-benchmarks
git -C /data/hrm/benchmarks/hal-benchmarks rev-parse HEAD
find /data/hrm/benchmarks/hal-benchmarks -type f -name SOURCE -print
find /data/hrm/benchmarks/hal-benchmarks -maxdepth 2 -iname '*license*' -o -iname '*copying*'
sha256sum /data/hrm/benchmarks/hal-benchmarks/crypto/rsa/rsa_lsi_10k_synopsys.v
```

## 推荐 pilot

### Arithmetic pilot：HAL BasicRSA（外部 stress）+ 本地 32-bit adder（可证明 smoke）

首选外部设计是 `crypto/rsa/rsa_lsi_10k_synopsys.v`，原因是 README 给出 BasicRSA 的 LSI_10K/XILINX_UNISIM 规模，网表头部记录 Synopsys DC，且 RSA 是真正的宽字算术而不是只有组合小门。先从 `SOURCE` 指向的 OpenCores BasicRSA 固定一个上游 commit，确认顶层、参数、reset 和源网表是否匹配；如果不能证明配对，就把结果标为“结构压力测试”，不计入 RTL 恢复准确率。

在外部 stress 前，用仓库已有的 `simple_circuits/adder_32_bit.vhd` 作为可控 smoke：用固定 Yosys/ABC liberty 流程自行综合出 netlist，保存 RTL、netlist、`.ys`、library 和 hash。这不是公开 benchmark 的原始 mapped pair，但能为 arithmetic 旁路提供无许可证歧义的端到端基线。

最小执行步骤：

1. 对 adder smoke 运行现有 HAL 提取、CSE、结构提升和组合 miter；要求每个输出位有来源，不能有 `func=null`。
2. 对 RSA 网表只先做 cone_stats、cell-library coverage、FF/clock/reset 清单，不立即投入 LLM。
3. 选一个 8/16-bit 可裁剪 RSA/乘法锥做 ABC `&atree` 候选；候选通过逐位 SAT miter 后才组装 word-level RTL。

### Sequential/control pilot：HAL Open8

选择 `cpu/open8/open8_lsi_10k_synopsys.v`。它有明确的 CPU/控制器性质，LSI 网表中可观察到 `FD2`、`AO2`、`NR2`、`FA1A` 等时序和算术 cell；README 提供 Open8 上游源指针。它比直接上 IBEX/OpenTitan 小，能先暴露 clock-gating、状态寄存器分组、同步/异步 reset 和内部寄存器对齐问题。

最小执行步骤：

1. 锁定 Open8 上游源 commit，记录顶层和所有参数；先用 HAL `lsi_10k.hgl` 检查网表 cell coverage。
2. 运行 `cone_stats.py`，按 clock/reset domain 分组；若存在 clock-gating，不能直接使用当前单 `always @(posedge clk)` 组装器。
3. 先只恢复 4 类控制块：PC/状态寄存器、计数器、总线握手和一个 ALU 数据寄存器；每块做内部 net-id 对齐和分块 sequential miter。
4. 加固定 seed 的指令/总线激励，覆盖 reset、wait、interrupt/异常（若该版本包含）和 back-pressure；报告 proven/covered/unknown 三种状态。

## 最小指标表

每个 benchmark/pilot 至少记录以下字段：

| 类别 | 指标 |
|---|---|
| Provenance | 上游 URL、commit/tag、下载时间、RTL/netlist/library/脚本 SHA-256、许可证文件路径 |
| Parsing | 顶层名、输入/输出、cell 类型覆盖率、FF 数、clock/reset domain 数、memory/black-box 数 |
| Extraction | FF 总数、提取数、`func=null` 数、最大/分位 cone、总函数字符或 DAG 节点数 |
| Recovery | bus 数、位覆盖率、结构提升数/类型、LLM 批次失败和自动修补数、token/耗时 |
| Correctness | 组合 miter proven 数、sequential miter proven/unknown 数、端口 mismatch、内部 net-id divergence、定向 opcode/state coverage |
| Reproducibility | 固定 seed、测试向量 hash、工具版本、命令行、完整日志和失败分类 |

推荐的硬门槛是：`func=null=0` 才能宣称“全状态覆盖”；所有输出有来源且 cell coverage=100% 才能进入等价 verdict；任何形式化超时记为 `unknown`，不能记为失败或通过。

## 执行顺序与阻塞项

1. 先做本地 `adder_32_bit` smoke，验证 manifest、hash、cell coverage 和 miter 流程。
2. 再导入 HAL BasicRSA，完成许可证/源 commit/顶层配对核查和 cone 预检。
3. 以 HAL Open8 做 sequential/control pilot，先验证多时钟/clock-gating 识别，再做控制块分块 miter。
4. 通过上述门槛后再申请/下载 IWLS；IWLS 是主 benchmark 候选，但其许可证、library 文件和综合脚本必须先由官方包核实。
5. GenEDA、ITC99、GNN-RE、PLDI suite 当前均缺少可锁定的 artifact/许可证/配对证据，暂不纳入定量主表。

## Pilot selection review

基于已核实证据，第一批应选择本地 `adder_32_bit` smoke + `hal-benchmarks` 的 Open8 LSI_10K 网表：前者有完全可控 RTL/综合脚本/库，后者有可实际取得的映射网表和明确上游 SOURCE，且顺序/控制风险比 IBEX/OpenTitan 小。BasicRSA 作为第二个 arithmetic stress，只在上游 RTL commit 与网表顶层、端口、FF/reset 对齐后计入准确率；对齐失败只能计为结构压力测试。IWLS 适合主 benchmark 扩展，但官方页面虽确认 RTL+mapped Verilog/OpenAccess 和 180nm 流程，未确认 license、cell library 文件或综合脚本，下载包验收前不能作为可再分发/完全可复现数据集。GenEDA、ITC99、GNN-RE、PLDI suite 当前缺少可锁定 artifact/license/library 配对，只能作为待补证据候选；ISCAS/EPFL 主要组合或无 RTL-netlist 成对关系，只能做 parser/arithmetic smoke。

验收条件：

1. 每个输入保存 URL、commit、license、SHA-256。
2. RTL/netlist 顶层、端口和寄存器/复位结构自动匹配。
3. HAL cell coverage 100%，无未知 cell、black-box 或未解释 clock/reset。
4. `func=null=0` 且所有输出有来源。
5. 候选 RTL 通过组合或分块 sequential miter，随机测试仅作为补充。
6. 固定 seed/vector hash/tool versions 可重放。
7. license 不明的数据不提交仓库、不公开发布。
