> Historical research note. For the accepted Config A MUL repair, see [CONFIG_A_REPAIR_REPORT.md](CONFIG_A_REPAIR_REPORT.md). Other findings retain their original status.

# MUL 定向覆盖与 skipped-bit 审计

日期：2026-09-11。实验使用远端 `/data/hrm/desynth/work/big` 中已有的 Config A 网表和 lift 产物；没有修改组装器。

## 可复现实验

新增脚本：[`agent/gen_mul_tb.py`](../agent/gen_mul_tb.py)。它生成固定指令 ROM，依次执行 `MUL`、`MULH`、`MULHSU`、`MULHU`，使用负数、零和有符号边界值，并将结果写入不同地址。程序 manifest 保存在远端 `work/big/mul_directed_manifest.json`，`seed=0`，33 个指令字，1500 个观测周期。

远端命令：

```sh
cd /data/hrm/desynth
python3 work/gen_mul_tb.py picorv32 picorv32_lift \
  -o work/big/tb_mul_directed.v \
  --manifest work/big/mul_directed_manifest.json --cycles 1500
source env.sh
iverilog -g2012 -o work/big/sim_mul_directed \
  work/big/tb_mul_directed.v work/big/pico_big_netlist.v \
  work/big/pico_big_lift.v work/big/cells_init.v
./work/big/sim_mul_directed > work/big/mul_directed.log 2>&1
```

## 结果

日志：`/data/hrm/desynth/work/big/mul_directed.log`。

* gold/lift 两侧均执行 8 次 store，均观察到四类 opcode：每个 `funct3=0..3` 各 6 个 `pcpi_valid` 周期（这是请求覆盖计数，不冒充内部 ready 握手）。
* 第一处实质差异在 `cyc=19` 的第一个 `MUL(-1,2)` 写回：gold `fffffffe`，lift `7ffffffe`。之后同一错误保持到下一取指周期，因此总接口比较为 `126` 个错误。
* 8 个 gold store 数据为 `fffffffe, ffffffff, ffffffff, 00000001, 00000000, fffff800, 00000000, 00000000`；lift 侧为 `7ffffffe`（前 7 次保持该值），第 8 次为 `00000000`。
* 日志汇总：`MUL_DIRECTED errors=126 stores_gold=8 stores_dut=8 cycles=1499`，四类 opcode 的 gold/dut 计数均为 `6/6`。

这证明随机测试漏掉的路径确实会触发 skipped 位，而且影响低 32 位可见输出。它同时证明当前 lift RTL 不能称为完整设计等价；`errors=126` 是明确的 **failed**，不是 unknown。

## skipped 位静态审计

新增脚本：[`agent/audit_skipped.py`](../agent/audit_skipped.py)。远端产物：

* `work/big/skipped_audit.json`
* `work/big/skipped_audit.md`

共 2313 个 FF，2280 个已提取，33 个 skipped；全部是 `genblk1.pcpi_mul.rd(31..63)`，cone 为 3064 到 9066，原因是超过阈值 3000。默认状态记录为 `unknown`，不会由仿真通过推导等价。

## 结论和接入建议

阶段 1 的最小实验已完成。覆盖证据应纳入后续 manifest/verdict：四种 MUL opcode 均被定向触发，但当前 33 位导致可观察差异，因此 Config A verdict 应为 `failed`（完整 lift），其余未覆盖状态仍只能标为 `unknown`。

暂不建议把该 testbench 接入主 pipeline 的“通过”门槛，直到 skipped 位由 ABC/字级候选或形式化 miter 证明并替换。建议保留它作为回归门槛：任何候选 lift 至少要通过四类 opcode 的握手覆盖、8 次写回和 gold/lift 逐周期比较。
