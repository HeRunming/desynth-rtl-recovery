> Historical research note. For the accepted Config A MUL repair, see [CONFIG_A_REPAIR_REPORT.md](CONFIG_A_REPAIR_REPORT.md). Other findings retain their original status.

# try_hai 工作交接

更新时间：2026-09-10

## 0. 服务器状态

SSH 免密连接已确认可用：`ssh -p 49322 hrm@140.143.244.199`。

远端工作区已迁移到 `/data/hrm/desynth`。旧路径 `/home/hrm/desynth` 和 `/data/hrm_desynth` 均保留为指向新路径的兼容符号链接；迁移前目录保存在 `/data/hrm/desynth-migration-backup-20260910`。关键文件副本已做 SHA-256 校验。远端 `env.sh` 的 `DESYNTH_ROOT` 已更新为 `/data/hrm/desynth`，工具链和 PicoRV32 产物可从新路径正常加载。

远端现状：`/data` 尚有约 1.1TB 可用空间，根分区仅约 1.8GB 可用；后续大文件必须写入 `/data`。检查时没有实际运行中的 Yosys、Icarus、HAL 或 lift 计算进程，只有几个等待历史任务结束的监视 shell。

## 1. 项目目标

本项目研究门级网表到可读 RTL 的反综合（de-synthesis）。核心判断是：HAL 负责精确地从门级连线提取布尔函数和寄存器分组，LLM 负责语义识别和可读结构重建，Yosys/SAT 或仿真负责裁判。所有候选 RTL 都必须以等价验证为准，不能只凭代码可读性判断成功。

## 2. 当前代码结构

| 目录 | 作用 |
|---|---|
| `agent/` | 反综合闭环、HAL 提取、CSE、语义命名、结构提升、RTL 组装、验证和测试脚本 |
| `pipeline/` | 小型 RTL 语料、综合网表和四条样本数据集 |
| `examples/` | counter、traffic FSM、ALU、FIFO、UART、CPU datapath、PicoRV32 样例 |
| `hal/` | HAL 源码及已编译 Python binding |
| `oss-cad-suite/` | Yosys、ABC、Icarus、Verilator 等工具链 |
| `tools/` | 独立 Z3、CMake、Boost 等依赖 |
| `STATUS.md` | 目前最完整的 PicoRV32 阶段总结，优先于较早记录 |

## 3. 已完成且有证据的实验

### A. 小型数据集基线

`pipeline/dataset/dataset.jsonl` 有 4 条完整样本，均已完成 RTL→门级网表综合，并通过形式化等价：

| 设计 | 门级 cell 数 | 结果 |
|---|---:|---|
| `alu4` | 84 | 通过 |
| `counter8` | 22 | 通过 |
| `fsm_traffic` | 47 | 通过 |
| `shift_reg` | 8 | 通过 |

构建入口是 `pipeline/build_dataset.py`。我在本机重新执行到 `/private/tmp/try_hai_dataset_check`，4/4 通过。

### B. LLM 纯反综合与 HAL+LLM 对照

`agent/trace_*.json` 保存了每轮提示、RTL 和验证结果。已成功的设计包括：

- `alu8`：baseline/hybrid 均第 1 轮通过。
- `crc8`：baseline/hybrid 均第 1 轮通过。
- `cpu_datapath`：baseline/hybrid 均第 1 轮通过。
- `uart`、`uart_tx` 两组轨迹实际都使用 `uart_tx` 顶层：baseline/hybrid 均第 1 轮通过，不应算成两个不同设计。
- `fifo`：早期 baseline/hybrid 失败；`trace_fifo_baseline_v2.json` 已第 1 轮通过，`trace_fifo_hybrid_v2.json` 第 3 轮通过。应以 v2 为当前结果。
- `traffic`：`trace_traffic.json` 3 轮未通过，仍是小型基线中的未解决样本。

早期 FIFO 失败部分来自 Yosys memory/process 未预处理和未证明 `$equiv`，不应直接解释成 LLM 永久无法恢复 FIFO。

### C. PicoRV32 大规模 pipeline

`STATUS.md`（2026-08-22）记录了两个配置的端到端结果：

- Config A：`ENABLE_FAST_MUL=1`，2313 个 FF、171 条总线。
- Config B：`ENABLE_MUL=1`，2435 个 FF、502 条总线。
- HAL 逐位精确提取；CSE 将 Config A 的 445.5M 字符压到 5.8M，约 77.2×。
- 结构提升：Config A 158/171 条总线，Config B 472/502 条总线。
- 端口级随机仿真 50000 周期：两个配置均 0/899820 失配。
- 内部寄存器交叉验证：Config A 0/171 分歧，Config B 0/502 分歧。
- Icarus `-Wall` 语法检查通过。

语义命名从匿名布尔结构识别出寄存器堆、PC、指令译码、内存地址、流水线状态机、移位器和 ALU 结果等组件。评估应使用“信号族纯度”，不能把寄存器堆的不同寄存器误算成混杂信号。

## 4. 已验证的方法链

1. `hal_mechanical.py` / `hal_mechanical_chunked.py`：提取每个 FF 的下一状态布尔函数。
2. `mech_cse.py`：逐函数公共子表达式消除，缓解乘法器表达式爆炸。
3. `semantic_naming.py`：匿名结构分批交给 LLM，输出 bus、位序和角色；含跨批合并与缺失位补齐。
4. `struct_lift.py` / `lift_runner.py`：用 Z3 逐位证明 reset、data、counter、shift 等结构提升。
5. `assemble_lifted.py`：组装可读 RTL；CSE wire 使用作用域前缀避免碰撞。`CHANGELOG.md` 中的旧版“就地展开”修复已被当前作用域方案替代。
6. `gen_tb.py`：端口级逐周期比较；`gen_tb_internal.py`：逐寄存器比较。
7. `verify_cse_equiv.py` / `verify_cse_yosys.py`：CSE 等价和反例控制。

## 5. 当前真正的技术瓶颈

### P0：字级抽象缺失

逐位 Shannon 函数对跨位进位链和乘法器不友好。Config A 有 13 条未提升总线，另有 33 个乘法器高位因 cone 超过 3000 被跳过；这些位当前 RTL 发射为 `1'bx`。这 33 位在随机激励下没有传播到输出，但这不等于设计级等价已经被证明。

阶段报告记载的先导实验：同一 liberty 映射流程生成的 32×32 乘法器，ABC `&atree` 在 0.01 秒内检出 1114 个加法器结构。它支持继续探索算术识别旁路，但检出局部加法器并不等于已经恢复乘法操作数、位序、符号和控制条件。真实 PicoRV32 的 FF 边界切割和乘法器锥识别仍待验证。

### P1：验证覆盖

- 为 MUL/MULH/MULHSU/MULHU 生成合法 RISC-V 指令级激励。
- 对跳过的 33 位做静态输出 cone 可达性审计。
- 研究按总线切分的设计级 miter，减少对 `equiv_induct` 配对的依赖。

### P2：语义与工程化

- 将 `regroup.py` 接入主 pipeline；离线结果显示混合组可拆成更多高纯度子组。
- 命名阶段提前消除 `control_state` 等重名。
- 统一 CLI 参数和环境启动方式。

## 6. 本机与远端边界

PicoRV32 大体积中间产物已在远端 `/data/hrm/desynth/work/big` 确认存在，包括 `big_mech.json`、`big_mech_cse.json`、`big_names.json`、`big_lift.json`、`pico_big_lift.v` 和验证日志。历史报告所指的旧路径 `/home/hrm/desynth/work/big` 现在通过兼容链接继续可用。本次没有重新生成大规模产物，但直接读取远端验证日志确认了历史结果。

远端验证日志实测内容：Config A `verify_big.log` 为 `COMPILE_OK`，50000 周期端口比较 `0 mismatches / 899820 checks`；`verify_int_big.log` 为 `0/171 regs diverged`。Config B 的 `verify_partial.log` 为 `0 mismatches / 899820 checks` 和 `0/502 regs diverged`。

`TRANSFER_READY.md` 是 2026-08-20 的旧传输说明，目标是把 `assemble_lifted.py` 修复版传到服务器；它不能代替远端当前状态。SSH 端口和免密权限已确认，迁移后的 canonical root 是 `/data/hrm/desynth`。

## 7. 当前本机环境问题

- `tools/env.sh` 只把 Z3 可执行文件加入 PATH，没有把独立 Z3 Python 包加入 `PYTHONPATH`；直接运行 `test_parse_v_z3.py` / `test_inline_wires.py` 会得到 `ModuleNotFoundError: z3`。脚本自身已在 `struct_lift.py` 中使用 `Z3_DIR` 引导，但测试脚本没有复用该引导。
- HAL binding 加载时尝试写 `~/.local/share/hal/log/hal.log`，当前环境出现 `Operation timed out`。需要把 HAL 日志目录配置为可写的临时目录或补一个统一启动 wrapper。
- `test_merge_buses.py` 已通过；数据集构建已通过。`test_lift_cse.py` 需要真实 `mech_cse.json` 参数，不能空跑。

## 8. 推荐接手顺序

1. 已确认远端 PicoRV32 产物、配置相关日志和脚本版本；8 月 22 日报告已经记录组装及仿真通过，8 月 20 日待传输说明不再是当前待办。
2. 在本机补统一 `env` wrapper，使 Z3 Python 和 HAL 日志路径可重复初始化。
3. 先解决 liberty 映射 FF 的边界切割，再在真实 PicoRV32 乘法器锥上验证 ABC 算术识别；保留节点到原网表的映射。
4. 增加 MUL 系列指令级激励和 X/输出 cone 审计，重新评估 33 位。
5. 将字级算术结果接入组装器，目标是消除 `1'bx` 洞，并对原有 0 失配基线做回归。

首个可执行入口建议从 `agent/synth_big.ys`、`agent/cone_stats.py`、`agent/hal_mechanical_chunked.py` 和 `agent/assemble_lifted.py` 四个文件开始；不要重新跑已经完成的 LLM 矩阵。
