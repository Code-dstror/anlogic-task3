# 原生 PCIe 硬核和自研发送路径

工程在本机 TD 2026.2 build 6.2.3.210850 创建、配置并生成 PH1A90SEG324-2 的 Generic IP Lib PCI Express 1.3。实例 `camera_pcie_ep` 的生成入口是 `fpga_prj/scripts/generate_camera_pcie.tcl`。生成目录独立，源登记只加载 `src_fpga/ip/camera_pcie_ep/camera_pcie_ep.ipc`。全部 11 个新生成文件的 SHA256、生成器、参数、配置 ROM 和端口模型记录在 `NATIVE_IP_IDENTITY.json`。

PF0 使用 `1EDB:ABCD`、类别 `050000`，BAR0 为非预取、32 位、1 MiB，BAR1 和原配置一致。Gen2×1 使用 Bank83 Lane 1、100 MHz 差分参考和 25 MHz AUX，预留四个 MSI 向量，本应用发 PF0 向量 0。客户口数据宽度 128 位。与此前已验证的主机合同逐项对比，264 个原生端口和旧配置的所有功能参数相符。两次从当前安装新建的 IP 产生了相同的 DAT 和 TXT。相对旧工具的初始化表，当前生成器由 85 条变为 90 条，变化出现于 0x708、0x710、0x80c、0x81c、0x890、0x8a8。板上训练结果仍要取新位流的证据。

发送由 `c2h_native_rx_transport` 与 `c2h_native_packetizer` 在 client0 实现。BYPASS 完成包经 `c2h_native_fence_listener` 核对请求者、标签、地址、4 字节长度和 cookie，真实匹配才能结束 fence。主机单字 BAR 读写由 `camera_pcie_bar_rx`、原有寄存器/AXI-Lite owner 和 `camera_pcie_bar_tx` 完成。响应持有原硬核 lookup 和完整 10 位 tag 至 client1 接纳。BAR 复位在 USER 域由硬核复位与业务所有权复位共同异步断言、本地同步释放。旧 CC 在没有匹配的新 lookup 时只排空，不产生原生完成包。

本地应用 DBI 输入保持无访问，原生 IP 自己的初始化模块从新 ROM 配置硬核。MSI/PBA 取决于实际 RESULT、使能、掩码和 grant，DMA 槽仍按原生 ACK/retire 语义归还。应用侧 SDC 引用当前实例下的 `u_pcie/endpoint/bridge/u_controller/pcie_user_clk`。最终布局布线须重新核对时钟和约束查询覆盖。

## 功能检查

```powershell
& 'python' -B refactor/camera_shared_r1/src_fpga/simulation/camera_pcie_native/run.py --name native_repeat --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
```

`native_01` 的 22 项动态检查覆盖原生端口的 MSI 掩码、grant 和重复事件，client0 停顿、MRd 与 BYPASS 匹配，BAR 响应停顿、10 位 tag/lookup、硬核复位和迟到完成。动态测试的电气边界模型从新 IP 的实际端口清单派生。独立库又以真实生成 RTL 和 TD 的 PH1_PHY_PCIE_V3 模型展开完整 `c2h_pcie_endpoint`，`run 0` 成功，原生 IP 与模型告警 407 条，自研 RTL 告警 0 条。原始命令及日志在 `tmp/camera_pcie_native/native_01`，测试没有运行实板 PCIe 枚举、DMA 或链接训练。
