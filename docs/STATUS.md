> Historical research note. For the accepted Config A MUL repair, see [CONFIG_A_REPAIR_REPORT.md](CONFIG_A_REPAIR_REPORT.md). Other findings retain their original status.

# 反综合 Pipeline 阶段性总结

> 2026-08-22 · 门级网表 → 可读 RTL · 全部数字为实测，外推处已标注

## TL;DR

两个 PicoRV32 配置全链路打通，都通过两级等价验证（端口级 0 失配 + 内部寄存器 0 分歧）。
包括曾被 postmortem 判为"不可行"的 Config A（并行乘法器，单比特函数 87.6MB）。

**当前最大短板不是精度，是字级抽象的缺失**：13~30 条总线因跨位进位链依赖无法结构提升，
33 位因 cone 超阈值根本没被提取。两者是同一个根因，也有同一个解法（见"改进建议 #1"）。

---

## 一、架构

六个阶段，每阶段产物可独立检查、可缓存：

| # | 阶段 | 脚本 | 输入 → 输出 |
|---|------|------|-------------|
| 0 | 综合 | `synth_big.ys` | RTL → liberty 映射的 flat 门级网表 |
| 1 | 精确提取 | `hal_mechanical.py` | 网表 → 每个 FF 的下一状态布尔函数 + DANA 分组 |
| 2 | CSE 预处理 | `mech_cse.py` | 逐函数公共子表达式压缩（命名前） |
| 3 | 语义命名 | `semantic_naming.py` | 匿名布尔函数 → 总线分组 + 语义名 + role（LLM 并发） |
| 4 | 结构提升 | `struct_lift.py` / `lift_runner.py` | 布尔函数 → `if(~H) q<=D` 等结构（z3 逐位验证） |
| 5 | 组装 | `assemble_lifted.py` + `cse.py` | 结构 + 命名 → 可读 RTL（全局 CSE） |
| 6 | 验证 | `gen_tb.py` / `gen_tb_internal.py` | 端口级 + 内部寄存器交叉验证 |

**设计上的两个要点**：

1. **HAL 做的不只是分块**。它把门级连线 SMT 级精确归约成布尔函数 —— 这一步精确（LLM 会算错）
   且正好是 LLM 易读的形式。即 **HAL = 精确降噪 + 分块，LLM = 语义辨别 + 可读重建**。
2. **命名阶段不看原始信号名**。只喂布尔结构（`net_123` 级别），名字仅用于事后评估纯度。
   这是诚实性约束：真实场景里名字已被抹掉。

---

## 二、能做到的事（实测）

### 两个配置的完整结果

| | Config A | Config B |
|---|---|---|
| 配置 | `ENABLE_FAST_MUL=1`（并行乘法器） | `ENABLE_MUL=1`（时序乘法器） |
| FF 总数 | 2313 | 2435 |
| 总线数 | 171 | 502 |
| 结构提升 | 158/171 = **92.4%** | 472/502 = **94.0%** |
| FF 位覆盖（可提取基数） | 2021/2280 = **88.6%** | 2091/2435 = **85.9%** |
| 提取阶段缺口 | **33 位**（cone > 3000） | 0 |
| 产出 RTL | 2.5MB / 22641 行 | 1.1MB |
| **端口等价（50000 周期）** | **0 / 899,820 失配** | **0 / 899,820 失配** |
| **内部寄存器交叉验证** | **0 / 171 分歧** | **0 / 502 分歧** |
| iverilog -Wall | exit 0 | exit 0 |

提升类型分布：
- Config A：`data_reg` 133 / `data_reg_perbit` 24 / `shift` 1
- Config B：`data_reg` 416 / `toggle` 40 / `data_reg_perbit` 14 / `shift` 2

### 语义识别质量

纯从布尔函数结构（无原始名字）还原出 PicoRV32 真实架构组件：寄存器堆、指令译码寄存器、
程序计数器 PC、内存地址寄存器、立即数解码寄存器、流水线状态机、移位器、ALU 结果寄存器。

- Config A：171 总线，0 失败批次，仅 **4.7%** 归为 `other`
- 评估口径要注意：按"主导信号占比"算纯度会误判寄存器堆（DANA 把 32 个寄存器的同一位号聚成一组，
  按信号名算纯度只有 1/31，但 LLM 识别为 "register_file_bit_slice" 是**完全正确**的）。
  改按"信号族"评估后：**81% 多位总线同族纯度 ≥ 0.8**。

### 规模处理能力

- HAL 提取 2313 个 FF 函数：**1.4~1.8 秒**
- CSE 预处理全量 mech：445.5M → 5.8M 字符（**77.2×**），74s/16workers
- 结构提升 Config A：**51.8 秒**（服务器 48 核）
- 最极端单函数压缩：`net_27105` 68.81M → 55.7K（**1235.7×**），yosys miter+SAT 证明等价

### 验证体系

三层，互相独立：

1. **形式化**：yosys miter+SAT 抽样验证 CSE 等价（12/12 equivalent，反例控制 12/12 有效）
2. **端口级仿真**：50000 周期随机激励，全输出端口逐周期比对
3. **内部寄存器交叉验证**：raw 版 vs lift 版逐周期比对每个寄存器，能定位首次分歧周期

---

## 三、问题与局限

### 3.1 最大短板：缺字级抽象（两个症状，同一根因）

| 症状 | Config A | Config B |
|---|---|---|
| 未提升总线 | 13 条 / 292 位 | 30 条 / 344 位 |
| 提取阶段就跳过 | 33 位 | 0 |

**这两个症状是同一个根因**：逐位 Shannon 展开看不见跨位依赖。

- 未提升的总线**全部**是跨位进位链（加法器/递增器/累加器）：每位下一状态依赖同总线其它位。
  `counter`/`shift`/统一 `H-D` 三种模式都要求全位统一结构，对进位链本就不可能成立 → 退化成 raw。
- 那 33 位是同一现象的极端形态：`genblk1.pcpi_mul.rd(31..63)`，并行乘法器 64 位乘积的 MULH 半边。
  cone 从 3064 门单调涨到 9066，超过 HAL 阈值 3000 直接跳过。

**为什么不能靠提高阈值解决**（关键数据）：已提取的最大函数 `rd(30)` = **87,580,051 字符（单比特）**，
cone 刚压在 3000 以下。沿位号增长率约 **1.17×/bit**（30.0→35.1→40.7→47.3→55.1→63.7→72.9→87.6 MB）。
同比率外推 `rd(31)`≈100MB、`rd(63)`≈14GB、33 位合计约 **100GB** 函数文本。

> ⚠ 这是**外推不是实测**。但差距有三个数量级，所以结论是"不是调参问题"而非"精确到 14GB"。

### 3.2 那 33 位的准确表述（勿夸大）

它们在 RTL 里发射为 `1'bx` 并逐行标注。验证结论必须这样说：

> 这 33 位**在随机激励下未传播到输出端口**，不等于它们与原设计等价。

MULH 半边要激活需要真的取到 MULH 指令，随机 `mem_rdata` 极少形成合法 MULH 编码。
判定本身是可信的（gold 网表 FF 全部 `initial Q=0` 所以 gold 侧不含 X，mask 由 gold 侧算 ——
dut 侧的 X 若传到端口必然计为 mismatch，实际没发生），但**覆盖率不足是真的**。

### 3.3 验证体系的缺口

- **整体等价只有仿真，没有形式化**。yosys miter+SAT 只用在 CSE 抽样（12 个函数），
  整设计级别靠 50000 周期随机仿真。仿真通过 ≠ 等价证明。
- **随机激励对乘法器路径覆盖极弱**（见 3.2）。这不只影响那 33 位，
  整条 `pcpi_mul` 数据路径都缺少定向激励。
- yosys 形式化 equiv 对本类设计会报 unproven，但那是 `equiv_induct` 的能力局限
  （下一状态函数相同的 FF 配对混乱），不是真不等价 —— 之前 UART 上已确认过。

### 3.4 其它已知问题

| 问题 | 现状 | 影响 |
|---|---|---|
| z3 耗时随 CSE wire 数超线性（约 `wires^1.8`） | 已加逐位快速路径 + 按位给预算 | 累加器类总线仍烧预算 |
| LLM 总线命名重名 | `control_state` 一个名字出现 11 次，靠 assemble 阶段加后缀去重 | 可读性打折；派生工具易踩键碰撞 |
| DANA 过聚合 | 已有 `regroup.py` 做 LLM 语义重聚类（10 混合组 → 37 子组，26 个纯度≥0.8） | 未接进主 pipeline |
| Config A 有 4.7% 总线归为 `other` | — | 语义完整性小缺口 |
| 覆盖率口径易误报 | 已改为"可提取基数"分母（2280 而非 2313） | 旧报告的 87.4% 把"从未有输入数据的位"算作提升失败 |

---

## 四、改进建议（按优先级）

### P0 — 字级抽象旁路（一举解决 3.1 的两个症状）

领域里有成熟解法，**工具已经装在我们服务器上**（oss-cad-suite 自带 `yosys-abc` 1.01）。

我跑过的决定性实验：合成 32×32 乘法器，用**与 Config A 完全相同**的映射流程
（`abc -liberty hal_cells.lib`）出门级网表，喂给 ABC 的 `&atree`：

| | AIG 结点 | 检出 FA/HA | 耗时 |
|---|---|---|---|
| 未映射 | 8516 | 1159 | **0.01 秒** |
| 走我们的 liberty 流程 | 8365 | **1114** | **0.01 秒** |

两个结论：(a) **我们的综合流程没有破坏加法器结构** —— 实测，不是假设；
(b) 0.01 秒 vs 我们逐位提取 `rd(30)` 产出 87.6MB，差距是**算法范式**而非优化。

`&atree -v` 打出的锥体尺寸表（`Supp=2 Cone=1` … `Supp=28 Cone=737`）说明它**看得见**
同一个二次增长却不受影响：它在 3-feasible cut 上做局部模式匹配，从不构造整锥函数。
范式差异 = 我们在算"这一位是什么布尔函数"，它在问"这三根线构成全加器吗"。

**建议做法：不替换 HAL 提取，加一条旁路。**
HAL 照常提取 2280 位；对 `cone > 3000` 被跳过的位走 `&atree` 识别加法器树 →
提升成字级 `rd <= a * b`。那 33 位从"发射 `1'bx` 的空洞"变成"一行字级算子"，
而且比现在 2021 位的逐位形式**更可读**。同一条路顺带补上 3.1 的未提升总线
（需要字级模式匹配 `q+1` / `q+D` / `q<<1`）。

相关工具在我们这套 ABC 里都有：`&atree`（抽加法器树）、`&anorm -b`（Booth 归一化）、
`%blast -M num`（按尺寸 blast 乘法器），说明字级往返被支持。

**待办的第一个未知**：FF 切割没跑通（试了 6 次 —— `expose -cut -dff` 不认 liberty 映射出的
`FF` 单元；`$_DFF_P_` 不能在 Verilog 里直接实例化；自己写正则改写 Verilog 产生语法错）。
所以**尚未在真实 PicoRV32 乘法器锥上验证**。mul32 实验已证明范式与流程兼容，
但这一步必须先做，它决定这条路的可行性。

### P1 — 补验证体系的缺口

1. **定向激励**。随机 `mem_rdata` 几乎不形成合法 MULH 编码，整条 `pcpi_mul` 路径缺覆盖。
   做一个指令级激励生成器（合法 RISC-V 编码流，含 MUL/MULH/MULHSU/MULHU），
   这样那 33 位的 X 到底会不会传到端口就变成**实测**而不是"随机激励下没看到"。
2. **整设计形式化等价**。现在只有 CSE 抽样是形式化的（12 个函数），设计级别靠仿真。
   仿真通过 ≠ 等价证明。可以按总线切分做分块 miter+SAT，绕开 `equiv_induct` 的配对局限。
3. **X 传播审计**。加一条检查：统计有多少输出端口的锥体包含那 33 位。
   这是静态可算的，比仿真更强 —— 能直接回答"这些位在结构上是否可达输出"。

### P2 — 可读性与语义质量

1. **总线命名去重前移**。`control_state` 一个名字出现 11 次，靠 assemble 阶段加后缀区分。
   应在命名阶段就让 LLM 看到已用名字并给出区分性命名（`control_state_decode` 而非 `control_state_5`）。
   顺带消除派生工具的键碰撞坑（`make_nolift_cache.py` 已踩过：按原名建 dict 丢了 53 条）。
2. **`regroup.py` 接进主 pipeline**。已验证有效（10 个混合组 → 37 子组，26 个纯度 ≥ 0.8，
   71% 的位归入纯净子组），但目前是离线实验脚本，没进主流程。
   Config A 那 4.7% 的 `other` 应该能靠它再压一截。
3. **`unnamed_<nid>` 兜底命名**。含那 33 位的总线叫 `unnamed_27075`，
   可读性上是明显的洞。

### P3 — 工程化

| 项 | 说明 |
|---|---|
| CLI 不统一 | `assemble_lifted.py` 用位置参数 + `--cache/-o`，其它脚本用 `--mech/--out` 风格，容易记错 |
| 服务器环境依赖 source | 不 `source env.sh` 时 z3 是坏的（`undefined symbol: Z3_solver_register_on_clause`），iverilog/yosys 也不在 PATH |
| 长任务必须 nohup | 长连接会被 `Connection closed by ... port 49322` 掐断（Config A 组装 30+ 分钟）；且要 `python3 -u`，否则日志缓冲看起来像卡死 |
| SSH 端口坑 | 漏 `-p 49322` 会连到另一个 sshd，报 `Permission denied (publickey,password)` —— 完全伪装成密钥失效，实际密钥是好的 |

---

## 五、参考文献（P0 方案的依据）

| 方向 | 文献 | 对我们的作用 |
|---|---|---|
| 算术结构识别 | [Berkeley/ABC 2017 arith RE](https://people.eecs.berkeley.edu/~alanmi/publications/2017/tech17_arith.pdf) | ✅ 直接对症，`&atree` 已可用 |
| 库匹配逆向 | [ReveNGe, FMCAD'15](https://agra.informatik.uni-bremen.de/doc/konf/fmcad15_revenge.pdf) | ✅ 形状最贴合：模拟图 + 子图同构（LAD/SAT）把子电路匹配到算子库；论文称能在 300+ PI 的 block 里找 32 位算术组件，且提供开源框架 |
| 等式饱和（SOTA） | [BoolE, arXiv 2504.05577](https://arxiv.org/html/2504.05577v1) | 精确 FA 检出 93.48%(CSA)/84.81%(Booth)，是 ABC 的 3.53×/3.01× |
| 符号计算机代数 | [AMulet 2.0](https://fmv.jku.at/papers/KaufmannBiere-TACAS21.pdf) | ❌ 验证**已知**规约，不直接解决（我们没有规约）；但是结构恢复后的天然下游 |
| GNN 引导逆向 | [arXiv 2512.22260](https://arxiv.org/html/2512.22260v1) | 把优化过的乘法器反映射回字级表示 |
| LUT 级字级重建 | [arXiv 2303.02762](https://arxiv.org/abs/2303.02762) | 靠分析进位链检测字级结构 |

**这一族方法的公共死角（必须知道）**：优化过的乘法器。BoolE 论文里那组 `dch` 优化过的
乘法器，ABC 检出的精确全加器是 **0 个**。我们的 `abc -liberty` 流程温和所以结构还在
（1114 个 FA 实测），但如果目标网表经过激进优化，检出率会崩。

BoolE 本身的局限：没有确认的开源实现（论文无仓库链接）；规则集是从 ABC 在 CSA/Booth
模板上的输出挖出来的，泛化性绑定这些模板；需要人工剪枝规则集（作者自称 "empirical,
manual pruning"）；迭代次数是固定常数不是跑到不动点；**Wallace 树全文未提**。

---

## 六、复现命令

```bash
# 服务器: ssh -p 49322 hrm@140.143.244.199   ← 端口不能漏
source /home/hrm/desynth/env.sh              # z3 + oss-cad-suite 都靠它
cd /home/hrm/desynth/pipeline

# 组装 (--cache 走已有 lift 结果, 不需要 z3)
python3 -u assemble_lifted.py \
  ../work/big/big_mech_cse.json ../work/big/big_names.json \
  ../work/big/pico_big_netlist.v picorv32 \
  --cache ../work/big/big_lift.json --mod picorv32_lift \
  -o ../work/big/pico_big_lift.v -v

# 端口级等价 (50000 周期)
python3 gen_tb.py ../work/big/pico_big_netlist.v picorv32 picorv32_lift \
  --cycles 50000 --tb tb_eq_big -o ../work/big/tb_eq_big.v
cd ../work/big && iverilog -o sim_eq_big \
  tb_eq_big.v pico_big_netlist.v pico_big_lift.v cells_init.v && ./sim_eq_big

# 内部寄存器交叉验证 (需要 raw 基线)
python3 make_nolift_cache.py ../work/big/big_lift.json ../work/big/big_nolift.json
# ...用 --cache big_nolift.json --mod picorv32_raw 再组装一次, 然后 gen_tb_internal.py
```

---

## 七、一句话判断

**精确性和规模已经不是瓶颈**（两个配置都 0 失配，2313 FF 提取 1.8 秒，最极端函数压缩 1235×）。
**瓶颈是抽象层级** —— 我们停在"逐位精确布尔函数"这一层，而进位链/乘法器本质上是字级对象。
P0 那条旁路是从"更努力地做逐位"转向"换个层级看"，这也是领域里成熟做法的方向。
