# `tb_vendor_pcie_probe` 诊断契约

## 目的

本测试台是 `pcie_video_transport`、真实加密 SGDMA 与 TD PH1 PCIe V3
仿真模型的有界冒烟探针。它验证厂商模型可由 ModelSim 编译、解密、展开并
进入仿真，不验证完整 PCIe 功能。

## 输入与时序

- `i_sys_clk`：25 MHz，周期 40 ns。
- `i_refclk_p/n`：100 MHz 差分参考时钟，周期 10 ns。
- `i_pcie_mperst`：仿真开始时为低，在 1 us 时释放。
- `i_pcie_rxp/rxn`：始终为已定义的静态差分空闲输入；它不是 Root Complex
  串行激励。
- 应用输入保持禁止且 AXI-Stream 源保持无效；所有 AXI4-Lite、H2C 响应输入
  均驱动为确定值。
- 顶层必须存在名称精确为 `PH1_PHY_GSR` 的 PH1 全局复位模型实例，因为
  PH1 原语模型通过层次名引用它。

## 运行边界与观察量

探针固定运行到 100 us 后结束。结束时记录：

- `o_user_clk`
- `o_user_rst_n`
- `o_user_link_up`
- `o_c2h_status` 与 `o_h2c_status`
- PCIe 串行发送差分输出

生产 RTL 的外部 PLL 稳定计数为 22 bit，约需 33 ms；因此 100 us 探针中
用户时钟/复位或链路状态尚未释放是允许且预期的诊断结果，不得据此判断硬件
链路失败。

## 判定

测试台到达结束点时只输出 `DIAGNOSTIC_NONPASS`。运行脚本还要求：

- PH1 模型与设计源编译退出码为零；
- 仿真成功展开并打印“model elaborated”；
- ModelSim 日志不存在 `** Error`；
- 仿真到达 100 us 的有界结束点。

`DIAGNOSTIC_NONPASS` 表示模型就绪性探测完成，但不是功能通过。

## 明确不可证明项

该测试台没有 Root Complex、PCIe BFM/VIP 或合法串行训练序列，因此不能证明：

- LTSSM 链路训练和 `user_link_up`；
- 枚举、配置空间或 BAR 访问；
- SGDMA 描述符读取、C2H/H2C 数据传输或完成回写；
- MSI/MSI-X、中断、吞吐率或板级信号完整性。

这些功能需要匹配当前 PH1A90SEG324 Gen2 x1 配置的 Root Complex/VIP，或在
SGDMA 的 RQ/RC/CQ/CC 事务边界建立独立且自检的主机模型后另行验证。
