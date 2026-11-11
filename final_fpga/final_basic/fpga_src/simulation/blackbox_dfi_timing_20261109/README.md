# DFI 独立黑盒短测

测试从独立上下文编写，只使用公开端口、选定的合法参数和线格式。生产 RTL、生成 IP 和 TD 模型只用于不透明编译与 SHA256，断言仅采样公开端口。DFI 复位合同及端口声明逐字节复制自本次交接的 `tmp/nov9_dfi_reset/`。ARAW 比对字段来自版本化 JSON。[DFI_CONFIG_PUBLIC.md](../../../docs/timing_20261109/DFI_CONFIG_PUBLIC.md) · [DFI_RESET_PUBLIC.md](DFI_RESET_PUBLIC.md) · [ports.txt](ports.txt) · [raw_video_v1.json](../../../docs/raw_video_v1.json)

| 短测 | 模拟终态 | 独立运行目录 |
| --- | --- | --- |
| `config` | 首 BOOT 经实际双 FIFO 到 PIX ACK。8 次 DFI 请求接收和 8 次 PIX ACK。逐位比较 374 位 tuple，验证两代 schema、ACTIVE 与 HDR 同拍提交、错误和忙回执、前端拒绝、迟到 DONE、停钟复位及新会话 BOOT。 | `config-20261109T011014056528Z` |
| `arbiter` | R3 数据资格、F3 状态释放、R3 到 F3 之间再断言复位，双层仲裁器在 R6 接收首 AW。两个客户端交错竞争，验证 AW/W/B 保持、完整 burst 的响应归属、停钟撤回悬挂 AW 和复位后恢复。4 AW、6 W、4 B。 | `arbiter-20261109T011408946076Z` |
| `formatter` | 两次冷启动均在 R4 接收 START。分别完成首帧和恢复帧，中间撤回停钟时悬挂的旧帧头。12 次输出握手，每帧校验 64 字节 ARAW 头、20 字节 RAW10 载荷、KEEP/LAST 和 DONE。 | `formatter-20261109T011942756768Z` |
| `product` | 首记录经 formatter、实际 product CDC 和 TD FIFO 到 USER。描述符和 AXIS 均受有限反压，校验 84 字节及成功 DONE/drained，随后观测独立的 USER SAFE 与源端退休握手，比较返回身份和状态。 | `product-20261109T011910494469Z` |

运行目录位于本候选的 `tmp/blackbox_dfi_timing_20261109/`。每次保留 `result.json`、实际进程参数、工作目录、输入 SHA256 和原始日志。最初 `product-20261109T011813172219Z` 的 ModelSim 编译被夹具信号前向声明阻塞。调整声明顺序后重跑通过，原失败仍保留。共享 ARAW 夹具明确了输入端口种类后，`formatter` 也另目录复测通过。`arbiter` 的 `vlog/vopt-13314` 对三个夹具输入各报告一次默认端口种类，测试到达 PASS 且编译和优化均无错误。

使用 ModelSim SE-64 2020.4、Python 3.12 和显式指定的 TD 2026.2.210.850。`config` 和 `product` 使用 100 µs 仿真 watchdog，`arbiter` 和 `formatter` 使用 20 µs。每个进程使用本轮剩余墙钟预算，单例总预算 55 秒。ModelSim 库映射和日志均位于独立运行目录。

```powershell
$python = 'python'
$runner = 'refactor/camera_raw_r2/src_fpga/simulation/blackbox_dfi_timing_20261109/run_blackbox.py'
foreach ($case in 'config', 'arbiter', 'formatter', 'product') {
    & $python $runner --case $case --td-root 'D:/App/TD_Release_2026.2.210.850' --modelsim-bin 'D:/App/modelsim/win64'
    if ($LASTEXITCODE -ne 0) { throw "$case did not pass" }
}
```

证据范围为紧凑 CONFIG profile、两级公开 AXI 端口、8×2 ARAW 图像和单条产品记录。整机综合、P&R、物理时序、板级和满幅持续吞吐均为 NOT_RUN。
