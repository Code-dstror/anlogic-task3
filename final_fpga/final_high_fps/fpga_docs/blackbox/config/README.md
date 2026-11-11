# 配置、冷选与 SDK 独立短测

测试作者仅使用 [CFG 载体公开合同](../../../fpga_prj/verification_archive/verification_reference/QUALITY_CONFIG_PUBLIC.md)、
[UHD 配置合同](../../UHD_CFG_PUBLIC.md)、[几何冷选合同](../../GEOMETRY_CONTROL_PUBLIC.md)、
[速率合同](../../../../camera_rate_r1/docs/RATE_CONTROL_CONTRACT.md)及线协议 JSON。
测试通过公开 IO 注入时钟停顿、采集欠账、写排空延迟和旧 ACK。测试作者未打开生产 RTL、厂商模型或旧测试实现。

## 覆盖边界

| 门 | 终态与判据 |
| --- | --- |
| HD 双目 CFG | 真实 USER/PIX/DFI owner 与原生 TD FIFO。BOOT 无图发布 neutral。真实首帧通知后比对 session、epoch、sequence、base 与全部 32 字。PREPARE 等旧流水空闲，COMMIT 等眼 1 结束、采集欠账及迟到写响应。旧整包 ACK 不推进 admission，匹配 ACK 后新流水 busy 仍可 APPLIED。 |
| HD 单目 CFG | HDR 画质和旧编码、HDR→HE→HDR、版本/保留位/非法白平衡和 SDR Tone 拒绝及同会话恢复。手动 WB 使用不同 RGB 值，Tone、融合与去雾 generation 共存。 |
| UHD CFG | 单目能力、旧 scalar Gaussian、新 schema2 灰度＋Gaussian＋HE 和 WB。HDR、dehaze、lane 不能生效，拒绝保留旧 ACTIVE。 |
| 关画质能力 CFG | 旧 HDR 和 HE 正常，CFG_FEATURES bit 6 清零，直接写入新增 W1/W12 拒绝。 |
| 冷选 | 真实 AXI-Lite 应用 BAR 与冷选控制器完成 HD mono60、dual30/40/45/48、UHD15 JPEG、UHD20 RAW。错开 PIX/DFI quiet 并暂停 SYS25，保留旧 USER ACTIVE。APP busy 门、APP/C2H 上线锁定、cohort reset 和复位后首应用。 |
| SDK | 新旧真实 SDK 各自通过独立 BAR 模型，核对新旧 profile/能力值及全部 32 字的 PREPARE_EXT、COMMIT、APPLIED。核对旧文档默认值、部分更新、非法请求发送前拒绝，以及 W1/W12 被篡改的 ACTIVE 返回 STALE。 |

冷选控制器的 `o_user_frame_divisor`、`o_pixel_frame_divisor`、`o_dfi_frame_divisor` 均报告协商值。
双目 D2 的 sensor profile 4 对应名义 30 fps，下游使用该 profile 解析物理采集分频。
冷选只覆盖 BAR 与各域选档，传感器写入和物理帧率由各自验证证明。CFG 载体的 late-B 和首帧由公开输入建模，
DFI CONFIG 和 CDC 用真实模块。SDK 只使用内存 BAR。综合、P&R、时序和板级在本门均为 **NOT_RUN**。

旧 `camera_rate_r3` SDK 在融合 HD 的新能力位上接受 W1/W12 全零的旧文档。
旧 SDK 对融合 UHD 能力字 `0x7f` 返回 UNSUPPORTED，融合 UHD 需使用新版 SDK。
新版接受旧 UHD COLOR-only `0x0f`、旧带预处理的 `0x3f` 和融合 `0x7f`，仅为实际能力开放在线选项。

## 运行

从仓库根使用 `ENVIRONMENT.local.md` 登记的 CPython 3.12.9、ModelSim SE-64 2020.4 和 TD Release 2026.2 模型。
为每轮指定一个新目录。单个进程限时 55 秒，整轮 175 秒。两个 SV 测试台另有仿真 watchdog。

```powershell
$fusion = (Resolve-Path 'refactor/camera_fusion_r1').Path
$fusionPython = '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe'
& $fusionPython -B "$fusion/src_fpga/simulation/blackbox_fusion_config/run_blackbox.py" `
    --modelsim-bin '<TOOLS_ROOT>/modelsim/win64' `
    --td-root '<TOOLS_ROOT>/TD_Release_2026.2.210.850' `
    --run-dir "$fusion/tmp/blackbox_fusion_config_review"
```

支持 `--only cfg|cold|sdk`。结果目录的 `evidence.json` 记录实际命令、前后 SHA-256、终态及日志。
最终 [配置复验](../../../tmp/blackbox_fusion_config_all_01/evidence.json) 的 197 项输入前后 SHA-256 一致。
四组 CFG、八次冷选应用和新旧 SDK 均通过，子进程合计约 18 秒。
旧目录保留。冷选首轮 `blackbox_fusion_config_cold_01` 把协商端口当作物理分频，依据公开合同澄清后在 `cold_02` 通过。
SDK 的 `sdk_01` 至 `sdk_04` 记录模拟 BAR 与调用修正，包含父 APP 发现寄存器及 v4 格式能力。
`sdk_05`、`sdk_06` 保留真实 SDK 接受数字字符串的失败。修复后相同负例与完整文档、直接 API 负例均通过。
UART 的独立运行与范围见 [DJ/v4 测试](../../../fpga_prj/verification_archive/src_fpga/simulation/blackbox_fusion_uart/README.md)。
