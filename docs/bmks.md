| Benchmark                                | 与 Gate-level → RTL 的匹配度 |   认可度 | 规模/特点                                                                         | 我的建议                              |
| ---------------------------------------- | ----------------------: | ----: | ----------------------------------------------------------------------------- | --------------------------------- |
| **GenEDA Task 3, ICCAD 2025**            |                   ★★★★★ | ★★★★☆ | 9 个 arithmetic designs；直接提供 gate-level netlist、golden RTL、testbench           | **最贴你的任务，首选直接 benchmark**         |
| **IWLS 2005**                            |                   ★★★★☆ | ★★★★★ | 84 个设计；RTL + synthesized Verilog netlist + cell library；CPU/AES/DES/DMA/USB 等 | **最适合作为主 benchmark 扩充版**          |
| **ITC'99 / I99T**                        |                   ★★★★☆ | ★★★★★ | b01–b22；RTL + synthesized gate-level；FSM、CPU、控制器等                             | **非常经典、非常适合顺序逻辑**                 |
| **GNN-RE, IEEE TCAD 2022**               |                   ★★★★☆ | ★★★★☆ | 37 个设计；原 RTL + DC 综合 netlist；adder/multiplier/control/subtractor/comparator   | **反向工程领域本身认可度高**                  |
| **PLDI'23 Hardware Decompilation suite** |                   ★★★★☆ | ★★★★★ | 53 个 netlist；SystemVerilog/PyRTL；公开 artifact                                  | **概念上与你最接近，但主要评 loop recovery**   |
| ISCAS'85/'89                             |                   ★★☆☆☆ | ★★★★★ | 最经典门级 benchmark                                                               | 适合补充，不适合当主要 netlist→RTL benchmark |
| EPFL combinational                       |                   ★★☆☆☆ | ★★★★★ | combinational AIG/Verilog/BLIF                                                | 更适合逻辑优化，而不是 RTL 恢复                |
