# DJ/v4 独立 UART 短测

测试仅使用 [公开线格式](../../../../../fpga_docs/UART_FIELD_V4.md)和[端口声明](../../../verification_reference/UART_FIELD_V4_PORTS.vh)。
四个生产 UART 模块不透明编译。`tb_fusion_uart.sv` 从 TX 采样实际 8N1，
`check_uart.py` 独立计算 OB CRC8 和 DJ CRC16，再核对轮次、两域整页、FS 与保留字。
五轮包含首个 RUN 同拍事件、PIX 停钟及恢复、DFI 拒收计数回卷、运行中 epoch 更新、RUN 停后保持与再次启动。
SDK 使用独立构造的 DJ/v2、v3、v4 和实串 OB/v2，逐字节分片，坏 CRC 后仍解出两个合法包。

从仓库根运行，目录每轮独立。

```powershell
$fusion = (Resolve-Path 'refactor/camera_fusion_r1').Path
$fusionPython = '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe'
& $fusionPython -B "$fusion/src_fpga/simulation/blackbox_fusion_config/run_blackbox.py" `
    --only uart `
    --modelsim-bin '<TOOLS_ROOT>/modelsim/win64' `
    --td-root '<TOOLS_ROOT>/TD_Release_2026.2.210.850' `
    --run-dir "$fusion/tmp/blackbox_fusion_uart_review"
```

[结果与输入 SHA-256](../../../tmp/blackbox_fusion_uart_01/evidence.json)为 **PASS**。
五轮 525 字节，PIX 停钟轮 DJ `fresh=0x01`，其余轮 `fresh=0x03`。
保留了原始 [TX 字节](../../../tmp/blackbox_fusion_uart_01/uart_model/uart_capture.bin)和[解码日志](../../../tmp/blackbox_fusion_uart_01/uart.log)。
仿真使用 25 MHz SYS 与 `UART_DIV=4` 加速。板级串口、综合与物理时序 **NOT_RUN**。
