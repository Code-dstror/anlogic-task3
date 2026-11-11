# RK3576 相机模式控制与接收

## 从现有接收程序切换模式

camera_raw_r2 使用原来的 `python -m linux.rk_debug shell` 和 `run`。启动时加 `--shared-camera mono` 或 `--shared-camera dual`，接收线程、配置线程、DMA 租约和设备 fd 都由这个进程持有。冷启动选择目数，运行中可切换 SDR/HDR 和各滤波组合。换目数需要结束原会话并按原板级流程取得新的冷启动 BOOT。每眼有独立的帧身份与状态，双目使用同一个处理掩码。

在 RK 上使用已登记的设备路径、PCI BDF 和现有 owner 预算。为这版安装本仓库的 `linux/rk_debug` 程序，将本目录放在已安装的 peer SDK **前面**的 `PYTHONPATH` 中。从这两个包目录以外的工作目录启动，避免当前工作目录优先导入旧模块。SDK 复用 peer 的 Receiver、ioctl、C2HSession 和记录收包代码。可先在纯软件环境检查 `python -m linux.rk_debug shell --help` 和 `python -c 'import dual_host.debug_modes, linux.rk_debug.cli; print(dual_host.debug_modes.__file__, linux.rk_debug.cli.__file__)'`。

```sh
export PYTHONPATH="$R2_RK_SDK:$RK_PEER_ROOT"
python -m linux.rk_debug shell --shared-camera dual \
  --device "$C2H_DEVICE" --expected-bdf "$PCI_BDF" \
  --config-timeout "$CFG_TIMEOUT_S" --command-timeout "$COMMAND_TIMEOUT_S" \
  --drain-timeout "$DRAIN_TIMEOUT_S" --report-output "$NEW_REPORT_FILE" \
  --shared-hdr-policy "$OWNER_HDR_CONFIGURATION"
```

在上述 shell 中可依次输入以下命令。每次切换后使用 `status`，等 `camera_mode.seen_cameras` 包含当前拓扑所有相机后，再提交下一次切换。

| 输入 | FPGA 输出与回读 |
| --- | --- |
| `caps` | 当前拓扑的实际模式/处理能力及 `parameters`，含在线 JPEG、HDR 运动/配对字段和固定值 |
| `active` | 当前 session、epoch 和完整 ACTIVE 快照 |
| `mode sdr gray gaussian he` | SDR，开启灰度、高斯、HE |
| `mode hdr dehaze he` | 原传感器 HDR，开启 FPGA 去雾及 HE |
| `mode sdr lane` | 单目原 F22/C1 车道，读出 v4 稀疏车道终态及点数 |
| `mode sdr` | 关闭 HDR 和全部可选处理，恢复彩色 |
| `status` | `camera_mode` 含 pending/active epoch 和各眼最近的 SOURCE、处理掩码、是否真正去雾、HDR 合并与车道点数 |
| `quit` | 当前 owner 执行原有正常停止和 drain |

`--shared-hdr-policy` 是调用方准备的完整 schema2 HDR 配置 JSON（`schema=2`、`extension.product_mode=2`，含全部九个 `hdr_*` 字段）。`mode hdr` 采用文件里的 HDR 字段和命令中的滤波组合，保留当前 JPEG 基础参数。用户也可直接使用原有的 `configure @完整配置.json` 或 `run --config`。HDR 使用固定 ratio 4、black 50/50、qualification 15，以及调用方提供的 motion 和 timer。SDR 的 HDR 字段均为零。去雾简写 generation 取 0，完整配置也可选择同一内建算法的 generation 1。车道仅单目可用。

进入 schema2 后，`configure {"base":{"quality":82}}` 会基于当前 ACTIVE 修改质量并保留其余字段。已经在 HDR 时，可用 `configure {"extension":{"hdr_motion_shift":4}}` 更新运动阈值的移位。每次以 `active` 核对新 epoch，并用 `status` 确认各活动眼已有该 epoch 的有效记录。完整 JSON、边界和匹配的 bit/SDK 说明见 [RK 参数合同](../docs/parameter_timing_20261110/RK_PARAMETERS.md)。

单目可用原 MONO KO。程序读原 CFG 的 CAM0 单目 profile/presence、COLOR/Q75、session 和 epoch0；不访问 STEREO 窗口。双目使用原已通过冷启资格的 N2 KO，遵守其硬编码取值守卫，唯一的拓扑写入是 REQUEST_MODE=1、REQUEST_DIVISOR=2、COMMAND/APPLY=1。两路均要求冷 BOOT 选择 v2，原 owner 取得 v4 选择回执后 START，再在相同 fd 上配置。内核须与原发行包的 kernel/build-id 和 KO 匹配。原发布 N2 内核的源码守卫位于 `work/anlogic2026/RK3576/linux/video/r5_video/dual_r3_stereo_driver.py`；本目录的 Python 预检表逐字节复用了已发布双目快照的 `peer/linux/dma_c2h_candidate/c2h_legacy_policy.py`，SHA-256 为 `c561609a270bd57e4be341b1e7425544002e5e4ef162f600f5743ddcb8b83779`。

新 epoch 的 JPEG 可先于 RK 读到 APPLIED。此时同一收包线程先释放 DMA 租约，按原到达顺序暂存独占帧副本，上限取 native 环的槽数。副本占满时暂缓取下一个完成槽，控制线程继续读回 APPLIED；已确认的帧才交给原消费者。超时或硬件身份不匹配时沿用 owner 的故障保留流程。原有不带 `--shared-camera` 的命令继续使用原 profile 和版本策略。

本目录沿用 STEREO ABI2、CFG1/schema2、v4 的 2112 B 帧头和原有槽、DMA、ACK 语义。原来的彩色双目入口 `dual_host.stereo_control.select_cold_mode` 与 `dual_host.dual_records.DualRecordDemux` 继续可用。R1 新增的 `dual_host.camera_shared.SharedStereoReceiver` 给双目滤波与 HDR 提供严格的产品校验。模块只使用调用方已有的 BAR 接口和收到的完整记录。

实际运行的旧 seed1 试验脚本锁定旧 bit 和旧 profile，`dual_r3_stereo.validate_color_record` 仅接受原彩色产品。上述显式 R1 入口使用每个 epoch 实际应用的配置进行记录检查。

## 冷启与切换

1. 在既有唯一 BAR owner 下完成新会话 BOOT。确认 APP 未启用且 C2H 未开始，然后调用 `SharedStereoReceiver.select_cold(bar, timeout_s=..., poll_interval_s=..., max_record_bytes=...)`。超时取设备负责人策略，最大记录长度取实际已分配的缓冲大小。此调用完成 DUAL/N2/Q75 和 v4 的确认。
2. 沿用既有 DMA/SELECT 后的 ARM、START、收包与安全释放顺序。每次交给 `accept` 的数据必须是一条完整且成功的记录。MMIO 事务与驱动所有权由原 owner 管理。
3. 冷选择后构造 `ConfigTransactions(bar, timeout_s=..., poll_interval_s=...)`。这里读取实际 DUAL profile 和两个摄像头的 presence。视频已运行时通过 `rx.apply(owner, base, profile)` 提交完整配置。调用返回前已核对真实 APPLIED 及活动 32 个字。灰度、高斯、HE 的掩码分别是 1、4、8，支持组合。SDR/HDR 的 `product_mode` 分别是 0、2，两眼在该 epoch 共用处理配置。基础 mode 取 COLOR。N2 的 D2 请求选择每眼 SDR30 传感器配方，内部采集 divisor 为 1。DOL2 按每眼完整长短组交付。去雾由实际能力位 0x02 开放。

```python
from dual_host.camera_shared import SharedStereoReceiver
from linux.task3_pipeline.config_transaction import Configuration, ConfigTransactions
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration

# 唯一 BAR owner 的冷启动阶段，在 ARM 前调用。
rx = SharedStereoReceiver.select_cold(
    bar, timeout_s=cfg_timeout, poll_interval_s=poll_interval,
    max_record_bytes=dma_record_capacity)

# 原应用完成 ARM/START 后创建当前拓扑的 CFG owner。
owner = ConfigTransactions(bar, timeout_s=cfg_timeout, poll_interval_s=poll_interval)
base = Configuration(quality=75)
rx.apply(owner, base, MonoConfiguration(processing_enables=1 | 4 | 8))

# 等两个眼均进入上述 epoch 后再执行下一个事务。
# approved_hdr_fields 为当前传感器配方和原 owner 的 motion/timeout 策略：
# hdr_ratio=4、hdr_black_long=50、hdr_black_short=50、hdr_qualification=15，
# 以及 hdr_motion_base、hdr_motion_shift、hdr_max_delta_ns、hdr_max_wait_ns、
# hdr_max_age_ns。生产参数由调用方显式提供。
hdr_with_dehaze_he = MonoConfiguration(product_mode=2, processing_enables=2 | 8,
                                       dehaze_lut_generation=0, **approved_hdr_fields)
receipt = rx.apply(owner, base, hdr_with_dehaze_he)
```

## 双目去雾

在实际 CFG schema2 能力包含 0x02 时，用 `MonoConfiguration(processing_enables=2, dehaze_lut_generation=0)` 请求 FPGA 逐像素恢复，也可以在同一配置中加入 HE 等已公布的位。内生估参默认为 0，1 显式选择同一内建算法，禁用时字段必须为 0。CFG ACTIVE 保留本次选择值，画面使用的上一合格帧系数由硬件按眼维护。旧版缺少能力位时请求会在 PREPARE 前被拒绝。

v4 同一记录的 `item.record.metadata.dehaze_requested` 取自该帧的 schema2 处理掩码。`dehaze_applied` 取自该帧的 DEHAZE_FILTERED 产品位。调试界面分别显示“已请求”和“本帧已恢复”。初次进入或本眼历史失效时可收到 requested=True、applied=False 的恒等输出。收到该眼真正用过合格历史的完整帧时才观察到 applied=True。单帧接收策略不会因为另一眼已使用恢复核就要求此眼同样置位。HDR_MERGED 与 DEHAZE_FILTERED 独立校验。v4 保留既有布局，未传输逐帧系数或新的系数代号。

双目 HDR＋去雾＋HE 的 schema2 第 0 个字为 `0x00002A02`，自动系数选择位于第 11 个字，值为 0。CFG SHADOW 是用户写入的计划。COMMIT 后两个传感器切配方，只有在实际视频边界完成 APPLIED，旧 ACTIVE 和 epoch 才被新状态替代。Linux 在途接收继续按各帧自己的 SOURCE/epoch 分发。首次 VC FS、PHY 就绪和完整 I²C 写入分别提供接收进度，恢复核的应用状态仍取该眼实际 JPEG 的产品位。

## 接收器接线

把 DMA 成功记录复制为独占 bytes，按原规则释放 lease，在接收回调执行 `item = rx.accept(owned_bytes)`。将 `item.record.jpeg` 送入 `item.camera` 对应的 MPP 队列，随帧保留 `item.session`、`item.epoch` 和 `item.sequence`。同眼要求 epoch、序号和槽代次前进，左右顺序各自判断。

CFG COMMIT 和 DMA 读回可并发。新 epoch 的首包可能先于 RK 读到 APPLIED，`AwaitingApplied` 表示调用方应把该份独占 bytes 保存在**有界的分眼 FIFO**，继续释放底层 DMA 租约，待事务成功后按到达顺序重新提交该眼的积压。此异常不会推进解码和源序号。超过缓存/时间上限或提交失败，结束该次接收并走原有恢复流程。上一 epoch 的在途记录仍按旧配置解释。两个眼均报告新 epoch 后才允许提交下一次切换。由单一有序路由线程调用 `accept`，与 CFG 线程独立。接收器把相机、RAW10、LONG/SINGLE、真实 HDR_MERGED、qualified、pair/job 和本 epoch 的滤波掩码放在一起校验。

## 已验证范围

从本目录运行 `PYTHONPATH="$PWD:$REPO" python -B -m unittest -v test_mode_shell test_shared_stereo`。测试使用真实 shell 命令解析、单 fd 的 Receiver、PREPARE_EXT/COMMIT 32 字影子/活动快照、原收包线程和完整 v4 parser；只替换设备 ioctl 和内存映射。覆盖单目/双目冷启、N2 取值限制、迟到 APPLIED、每眼不同 epoch 的在途记录、去雾应用位和单目原车道的零候选正常终态。设备 BAR、DMA、MPP、显示及持续帧率须用新 bit 和实际 RK 单独验收。

`test_published_shell.py --peer 原发布包/runtime/peer` 在独立的临时目录复制原 Python 包，再更新 `linux/rk_debug/{cli,controls,consumers,products}.py` 四个 RK 源文件，用上述私有 SDK 运行同一套测试。原 seed1 回传的 phase-A 单目包和 phase-B 双目包分别通过，二者都调用各自发布包原有的 Receiver。部署本版也应使用单独的 peer 副本，保留锁定旧 bit 的资格包。
