# JPEG 打包器独立黑盒验证

ModelSim SE-64 2020.4 实际通过 baseline 和 reachable-r4 候选的四个组合。测试使用 8 ns 时钟和公开端口，从真实输入握手建立字节队列，从真实输出握手退休字节。每次呈现输出都逐字节检查低 lane 起始顺序、KEEP 和 LAST，反压期间比较完整 DATA、KEEP 和 LAST。输入和输出握手在上升沿采样。超长字节的接受沿更新寄存脉冲，因此在紧邻的下一采样沿检查 overflow 与 frame_error 同时为 1。两臂各自按同一预期评分。[公开合同](../../fpga_prj/verification_archive/experiments/packer_reachable_r4_20261110/PUBLIC_CONTRACT.md) · [测试台](../../fpga_prj/verification_archive/src_fpga/simulation/blackbox_packer_r4/tb_packer.sv)

| MAX | baseline | 候选 | 两臂各自的采样周期 | 成功帧 | 输入字节握手 | 输出拍握手 | 同沿收发 |
| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |
| 17 | PASS | PASS | 518 | 26 | 324 | 35 | 7 |
| 31 | PASS | PASS | 1065 | 40 | 737 | 63 | 21 |

- 每组测试遍历长度 1 至 MAX，覆盖全部 1–16 字节有效尾拍、恰好整拍及合法 MAX 的双拍帧。合法首帧到达 LAST 握手。
- 每组有 19 个输出 stall 采样沿，其中 11 个是尾拍。提前呈现下一帧首字节产生 4 个输入 stall 采样沿，首字节在旧尾拍握手之后被接受。
- 每组恰好观测两次 overflow 和 frame_error 脉冲。首例超长字节携带 LAST，次例继续接收并丢弃 20 字节直到 LAST。两个已传输的前缀分别按内容计分，两次故障各自恢复到合法 MAX 帧。
- 每组覆盖部分未呈现字的 abort、已呈现整拍的 abort 排空和已呈现尾拍的 abort 排空。排空尾拍保持 LAST。同步复位丢弃旧尾拍，紧接着发送的合法 MAX 帧成功完成。

## 可复现证据

从仓库根执行下列命令。runner 每个 ModelSim 子进程限 35 秒，总窗口 110 秒。测试台 watchdog 为 24 µs。本次退出码为 0，实测墙钟约 9.5 秒，编译和仿真均报告 0 error、0 warning。

~~~powershell
& '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe' -I -B 'refactor/camera_fusion_r1/src_fpga/simulation/blackbox_packer_r4/run_packer.py' --modelsim-bin '<TOOLS_ROOT>/modelsim/win64'
~~~

| 输入 | SHA256 |
| --- | --- |
| baseline（提交 eade457d7477110605f90eb5abc08420d8936642） | 2a39a241c6ed1c722a4ccfaa96287789898ae6da54736614b7064e697a95446f |
| reachable-r4 候选 | 8b27772b4455d2107a2fbdfeb0cac9a17ce853f003ca469e64f638094cb59354 |
| tb_packer.sv | 65d105d876b346fec53c5ff3604ef2ac31993fae808b70be5ee6a755a9fd5661 |

result.json 记录完整命令、工作目录、工具退出码、公开输入及源码的运行前后 SHA256，前后值全部一致。原始日志按 arm 和 MAX 保存。[本机运行结果](../../tmp/packer_r4_blackbox_20261110_223146_747874/result.json) · [baseline MAX17](../../tmp/packer_r4_blackbox_20261110_223146_747874/baseline/MAX17.log) · [baseline MAX31](../../tmp/packer_r4_blackbox_20261110_223146_747874/baseline/MAX31.log) · [候选 MAX17](../../tmp/packer_r4_blackbox_20261110_223146_747874/candidate/MAX17.log) · [候选 MAX31](../../tmp/packer_r4_blackbox_20261110_223146_747874/candidate/MAX31.log)

本门槛的功能仿真为 PASS，覆盖 MAX=17/31 的单 packer，无厂商模型。综合、P&R、时序及板级验证在本门槛内均为 NOT_RUN。
