# camera_raw_r2 seed25 · RK3576 全功能调试手册

适用位流为 PH1A90SEG324-2 的 `camera_raw_r2` seed25，固定源 `1a5603c1c8aa58565aa9b5facf40a7478ebcf6ba`。用交付清单核对实际下载文件 SHA-256，留存现场下载回执。RK 每轮记录 boot ID、PCI BDF、设备节点、已加载 KO 与 kernel build-id、应用和 SDK 身份。MAGIC 与 ABI 用于确认接口。位流身份以实际下载文件和回执为准。编译与时序见[交付首页](README.md)，改动见[版本对照](CHANGES_FROM_41cb5991.md)。seed25 的板级、实际 C2H/MPP/HDMI、RAW ISP 和满幅持续帧率均为 **NOT_RUN**。

## 模式和验收对象

| 目标 | 入口 | 每眼首个合格产品与标称帧率 |
| --- | --- | --- |
| 单目 SDR 彩色 JPEG | CAM0 冷选 JPEG，BOOT 或 `mode sdr` | CAM0 物理 RAW10/SINGLE 源，1920×1080 AJPG v4，60 fps |
| 双目 SDR 彩色 JPEG | 双目冷选 JPEG，BOOT 或 `mode sdr` | 两眼各有合法 SOURCE，1920×1080，各 30 fps |
| 单、双目灰度／高斯／HE | 对应 JPEG 会话中分别开 `mode sdr gray`、`mode sdr gaussian`、`mode sdr he`，再开组合 | 每眼新 epoch 掩码分别为 `0x01`、`0x04`、`0x08`，组合 `0x0D`。速率同 SDR |
| 单目原车道 | `mode sdr lane` | CAM0 60 fps，掩码 `0x30` 含 F22 多尺度和 F23 原车道。v4 S07/F23 合法终态允许零候选 |
| 单、双目真 HDR | 对应 JPEG 会话中 `mode hdr` | 每眼独立 DOL2 合并，物理 LONG、qualified、HDR_MERGED、非零 `job_id == pair_id`，各 30 fps |
| 单、双目去雾 | 对应 JPEG 会话中 `mode sdr dehaze`，另复测 `mode hdr dehaze` 或 `mode hdr dehaze he` | `requested` 与该眼该帧 `applied` 分记。SDR 单 60／双各 30，HDR 各 30 |
| 单目 RAW10 | 冷态 `select_cold_raw(..., cameras=1)` | CAM0 1920×1080、ARAW v1、epoch 0，每条 2,592,064 B，60 fps |
| 双目 RAW10 | 冷态 `select_cold_raw(..., cameras=2)` | CAM0/CAM1 分眼 ARAW v1、epoch 0，各 30 fps |

外部双目请求沿用 `MODE=1, DIVISOR=2`（D2），内部 SDR 采用传感器原生 30 fps、有效捕获 DIV1。单目 SDR 以 60 fps 全帧捕获，HDR 走独立 DOL2 配方。JPEG 会话支持在线 CFG 切换 SDR/HDR、处理掩码和 JPEG 参数。目数、D2 以及 JPEG/ARAW 属于冷选择，APP/ARM 后锁定，RAW 活动期间 FPGA 拒绝在线 CFG 写。单、双目使用各自独立冷轮，双目两眼共用一个处理掩码，车道能力只在单目开放。

## 1. 准备 RK 私有环境

部署从与实际 KO、kernel 和用户态库匹配的已发布 `runtime/peer` 开始。JPEG 单目可沿用匹配 MONO KO，双目使用支持 DUAL1/N2/APPLY1 的发布 stereo-N2 KO。RAW 单、双目均使用第 4 节新增产品窗口白名单的驱动及 Python 策略。保留原发布包，以下变量均取现场绝对路径。`RK_PEER`、`RK_RUN` 是新目录，`HANDOFF` 是解包根目录，`PUBLISHED_PEER` 指向匹配发布环境中的 `runtime/peer`。

```sh
mkdir "$RK_PEER" "$RK_RUN"
cp -a "$PUBLISHED_PEER/." "$RK_PEER/"
cp "$HANDOFF/rk_support/cli_overlay/linux/rk_debug/"*.py "$RK_PEER/linux/rk_debug/"
export PYTHONPATH="$HANDOFF/rk_support/rk_sdk:$RK_PEER"
cd "$RK_RUN"
python3 -B -m linux.rk_debug shell --help
python3 -B -m linux.rk_debug run --help
python3 -B -c 'from linux.rk_debug import cli; from linux.dma_c2h_candidate import receiver; from dual_host import debug_modes; print(cli.__file__, receiver.__file__, debug_modes.__file__, sep="\n")'
```

`cli` 和 `receiver` 应来自该私有 peer，`debug_modes` 应来自本包 SDK 或已登记的匹配私有适配。运行目录应在两套源码之外。显示和录像应用另核对实际 ARM64 MPP、HUD、车道/采样器、编码库及其绝对路径和 SHA。旧 seed92 的 R5 文件名和模板目录曾导致已 SELECT、尚未 START 时失败。冷轮开始前确认上一 owner 状态、实际 BDF 和设备节点对应，确保单一 fd 负责 BAR、CFG、DMA、取结果与 RELEASE。PCIe LINK_UP 后仍要核对 USER reset、BME、DMA 容量、DDR calibration、memory owner 及 APP/ARM。

## 2. JPEG 冷启动与同一 owner 接收

**先核对 BOOT 兼容。** 固定源的 RCD2 硬件复位值是 `v1/64`。固定 SDK 的 `SharedDebugSession.prepare()` 仍硬编码 `v2/192` 前置检查，原样 `shell/run --shared-camera` 会在该检查处拦住合法 `v1/64` 冷轮。使用已核对兼容的 RK 私有 owner，或用下面的同 fd API。旧 seed92 私有应用的修正记录只证明该环境曾完成兼容，交付里的固定 SDK 与 `cli_overlay` 是源文件，现场私有 `ColdSession` 需单独匹配。

冷态应实读合法初始版本/头长 `1/64` 或 `2/192`，CFG `SESSION_READY`，同一非零 session 与 active session、epoch 0、COLOR/Q75、APP 关闭、`SESSION_REARM_READY=1` 且 `SESSION_ARMED=0`。双目在同一 fd 冷写 DUAL1/N2/APPLY1 等待 PIX/DFI DONE。单目直接采用 BOOT MONO 拓扑。随后 JPEG 对同一 CFG 会话执行**一次 SELECT v4/2112**，核对 `RESPONSE_SEQUENCE`、`RESPONSE_SESSION`、version/length、error 和 selection epoch，再 START。RCD2 `0x2B0/0x2B4` 为已选版本和长度，`0x2A0..0x2AC` 为状态及响应。任何错配、初始 v4、非冷态或缺少正回执按启动失败保留。

以下代码嵌入现场应用的现有 owner。首次打开使用 `Receiver(C2H_DEVICE, nonblocking=True)`，全程传同一个实例。`expected_bdf`、`cfg_timeout_s`、`poll_s` 采用现场预算。准备阶段由同一线程独占读写，`cold.prepare()` 内调用 SDK `select_record` 并核对正回执。成功后 `SharedRecordReader` 复用已验证的 v4 解析、先还租约与有界待确认队列。

```python
from dataclasses import asdict

from dual_host import stereo_control_v1 as stereo
from dual_host.camera_shared import SharedStereoReceiver
from dual_host.debug_modes import SharedRecordReader
from dual_host.stereo_control import select_cold_mode
from linux.rk_debug.products import ProductInspector
from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_runtime.session import C2HSession


def prepare_jpeg(owner, *, cameras, expected_bdf, cfg_timeout_s, poll_s):
    if cameras not in (1, 2) or owner.owner_identity().bdf != expected_bdf:
        raise RuntimeError("Unexpected topology or PCI owner")
    info = owner.snapshot()
    if (not info.transport_drained or info.submitted or info.completed
            or owner.leased_count or owner.poll(0)):
        raise RuntimeError("Fresh stopped C2H owner required")
    read = owner.read32
    status = read(p.PCIE_REG_STATUS)
    busy = (p.PCIE_STATUS_C2H_RUNNING | p.PCIE_STATUS_TX_BUSY |
            p.PCIE_STATUS_SOURCE_BUSY | p.PCIE_STATUS_SESSION_ARMED)
    if (read(p.PCIE_REG_CONTROL) & p.PCIE_CONTROL_APP_ENABLE or status & busy
            or not status & p.PCIE_STATUS_SESSION_REARM_READY):
        raise RuntimeError("Source-off pre-ARM boundary required")
    record_boot = (read(p.PCIE_REG_RECORD_SELECTED_VERSION),
                   read(p.PCIE_REG_RECORD_SELECTED_HEADER_LENGTH))
    session = read(p.PCIE_REG_CFG_SESSION)
    cfg_boot = (read(p.PCIE_REG_CFG_ACTIVE_SESSION), read(p.PCIE_REG_CFG_STATUS),
                read(p.PCIE_REG_CFG_ERROR), read(p.PCIE_REG_CFG_MODE_EPOCH),
                read(p.PCIE_REG_CFG_ACTIVE_MODE), read(p.PCIE_REG_CFG_ACTIVE_QUALITY))
    print({"record_boot": record_boot, "cfg_session": session, "cfg_boot": cfg_boot})
    if (record_boot not in ((1, 64), (2, 192)) or not session
            or cfg_boot != (session, p.PCIE_CFG_STATUS_SESSION_READY, 0, 0,
                            p.PCIE_CFG_MODE_COLOR, 75)):
        raise RuntimeError("Unexpected RCD2 or CFG cold BOOT tuple")
    expected_mono = (p.PCIE_CFG_PROFILE_MONO1920, 1, 1920, 1080)
    initial_profile = (read(p.PCIE_REG_CFG_COMPILED_PROFILE),
                       read(p.PCIE_REG_CFG_CAMERA_PRESENT),
                       read(p.PCIE_REG_CFG_MAX_WIDTH), read(p.PCIE_REG_CFG_MAX_HEIGHT))
    if initial_profile != expected_mono:
        raise RuntimeError("Expected fresh MONO CAM0 1920x1080")

    topology = None
    if cameras == 2:
        topology = select_cold_mode(
            owner.read32, owner.write32, stereo.STEREO_MODES_DUAL_JPEG,
            frame_divisor=2, jpeg_quality=75, timeout_s=cfg_timeout_s,
            poll_interval_s=poll_s,
        )
        print({"stereo_apply": asdict(topology)})
    cold = C2HSession(owner, jpeg_version=4, timeout_s=cfg_timeout_s)
    selection = cold.prepare()
    if (selection.session, selection.version, selection.header_length) != (session, 4, 2112):
        raise RuntimeError("v4 SELECT receipt differs from the current CFG BOOT")
    tx = cold.transactions
    caps = tx.capabilities
    expected = (p.PCIE_CFG_PROFILE_DUAL1920, 3, 1920, 1080) if cameras == 2 else expected_mono
    if (caps.compiled_profile, caps.camera_present, caps.max_width, caps.max_height) != expected:
        raise RuntimeError("CFG profile or presence differs from selected topology")
    rx = SharedStereoReceiver(
        topology if topology is not None else tx, selection,
        cameras=cameras, max_record_bytes=owner.capacity,
    )
    reader = SharedRecordReader(owner, ProductInspector(
        expected_jpeg_version=4, max_record_bytes=owner.capacity), rx)
    print({"record_select": asdict(selection)})
    return cold, rx, reader
```

成功后调用 `cold.start()` 一次。在原接收线程循环 `reader.poll_once(poll_s)`，保存返回的 JPEG 完成／负完成事件与 `reader.last`。`rx.status()['seen_cameras']` 应达到 `[0]` 或 `[0, 1]`，各眼 `reader.last` 应对应当前 session、epoch。首有效记录到达前使用现场首帧期限，同时保留 UART。BOOT epoch0 可有 legacy COLOR 首包，`schema2_processing_enables` 为 `None` 时应交 SDK 按该包的 epoch0/plain COLOR 合同验证，应用显示层按关闭可选处理归类并保留原 metadata。后续 schema2 epoch 按实际 mask 校验。

对于正常收尾，由 owner 调用 `cold.request_stop()`，接收线程继续 `reader.poll_once(poll_s)`，直至 `reader.drained()` 且 `cold.finish_stop()` 返回真，最后按 owner 全局安全关闭流程执行 `cold.close()`。限制排空时间，分别保留主机排空及 FPGA 退休证据。任一事务超时、传输归属不确定或 reader fault，记录终态，停止提交新配置，保留原 owner，由负责人按已登记的故障 STOP/排空流程处理。冷态 SELECT 失败应保留回执且停在 START 前。正常 host drain 与 FPGA 全局 quiet 分别确认，quarantine 或安全关闭未证明时按现场冷恢复流程交接。

### 已匹配的交互入口

以下命令适用于 **已核对合法 BOOT 元组兼容** 的 RK 环境。`TOPOLOGY` 为 `mono` 或 `dual`，设备路径、BDF、三个超时、每轮新报告文件均取现场值。只验 SDR 时省略 `--shared-hdr-policy` 及其值。先省略显示和录像参数做纯接收。

```sh
python3 -B -m linux.rk_debug shell --shared-camera "$TOPOLOGY" \
  --device "$C2H_DEVICE" --expected-bdf "$PCI_BDF" \
  --config-timeout "$CFG_TIMEOUT_S" --command-timeout "$COMMAND_TIMEOUT_S" \
  --drain-timeout "$DRAIN_TIMEOUT_S" --report-output "$NEW_REPORT_FILE" \
  --shared-hdr-policy "$OWNER_HDR_CONFIGURATION"
```

固定时长纯接收可以使用 `run`。记录预算需覆盖整个观测窗及尾部，报告路径的父目录应已存在。`--config "$FULL_CONFIGURATION"` 可在 START 后应用初始配置。

```sh
python3 -B -m linux.rk_debug run --shared-camera "$TOPOLOGY" \
  --device "$C2H_DEVICE" --expected-bdf "$PCI_BDF" \
  --config-timeout "$CFG_TIMEOUT_S" --command-timeout "$COMMAND_TIMEOUT_S" \
  --drain-timeout "$DRAIN_TIMEOUT_S" --report-output "$NEW_REPORT_FILE" \
  --max-seconds "$RUN_SECONDS" --max-records "$RECORD_BUDGET"
```

| `rk-debug>` 输入 | 回执与检查 |
| --- | --- |
| `caps`、`active` | 当前 CFG 拓扑、能力、session、epoch 及 ACTIVE。`camera_shared_r1` 是复用的 SDK profile 名 |
| `status` | `camera_mode.active_epoch`、`pending_epoch`、`seen_cameras`、`last_by_camera`。分眼记录序号、处理掩码、去雾 applied、HDR merged、车道点数 |
| `mode sdr` | 恢复彩色 SDR，清可选处理和 HDR 字段 |
| `mode sdr gray` / `mode sdr gaussian` / `mode sdr he` | 独立功能，组合使用 `mode sdr gray gaussian he` |
| `mode sdr dehaze` / `mode hdr dehaze he` | 去雾为 `0x02`，与 HE 组合为 `0x0A`。简写用内建 generation 0 |
| `mode sdr lane` | 单目原车道，掩码 `0x30`，退回 `mode sdr` 后检查清线与新记录 |
| `mode hdr` | 从 `--shared-hdr-policy` 取九个 HDR 字段，继承当前基础质量，由本命令决定处理掩码 |
| `configure @/绝对路径/完整配置.json` | 切入 schema2 时提交完整 extension。已有 schema2 epoch 时 `configure {"base":{"quality":85}}` 可单改质量 |
| `quit` | 由原 owner 正常 STOP、drain 并写入报告 |

`pause` / `resume` 继续同一个 owner 生命周期。目数或产品变化应正常停流排空，然后由设备负责人执行获授权的 RK/FPGA 共同冷启动及同一位流下载，再用新 boot/run ID 检查 BOOT 与未锁定态。推荐在测试计划里单独列四个冷轮（单目 JPEG、双目 JPEG、单目 RAW、双目 RAW），另以一次 RAW→JPEG 冷轮验证产品回切和首事务。

## 3. 在线 CFG、画面和功能检查

保持接收线程运行，同时由一个 CFG worker 提交完整配置。使用上面的 API 入口时，worker 可调用以下函数。`mode_words` 取表中的参数部分，例如 `sdr gray gaussian he`。`hdr_policy` 为审定 JSON 的 `Path`。

```python
from dual_host.debug_modes import mode_document
from linux.task3_pipeline.config_transaction import Configuration
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration


def apply_jpeg_mode(cold, rx, mode_words, hdr_policy=None, quality=75):
    topology = "mono" if rx.cameras == 1 else "dual"
    doc = mode_document(mode_words, topology, hdr_policy)
    return rx.apply(cold.transactions, Configuration(quality=quality),
                    MonoConfiguration(**doc["extension"]))
```

保留 PREPARE_EXT → READY → COMMIT → APPLIED 请求/响应身份及 ACTIVE 32 字回读。APPLIED 后检查新 epoch 首个有效 SOURCE，等所有参与眼都交付本 epoch 合格记录再切下一项。新 epoch 产品早于 RK 读到 APPLIED 时，SDK 先归还 DMA lease，再有界保存独占副本。确认后按到达顺序提交，旧 epoch 在途包按各自 epoch 处理。失败时冻结证据并走第 2 节收尾，保持原 owner 串行化。

真 HDR 使用物理 DOL2，JSON 顶层 `schema=2`、`base.mode=0`（COLOR）、`extension.product_mode=2`。以下为 seed92 历史对照配方，只有经当前设备负责人选定后才用于复测。`hdr_ratio=4` 为协议编码值，`hdr_max_delta_ns` 按 32 位，wait/age 采用非零值。SDR 使用 `product_mode=0` 和全零 HDR 字段。

```json
{
  "schema": 2,
  "base": {"mode": 0, "quality": 75},
  "extension": {
    "product_mode": 2,
    "processing_enables": 0,
    "hdr_ratio": 4,
    "hdr_black_long": 50,
    "hdr_black_short": 50,
    "hdr_motion_base": 64,
    "hdr_motion_shift": 3,
    "hdr_qualification": 15,
    "hdr_max_delta_ns": 50000000,
    "hdr_max_wait_ns": 100000000,
    "hdr_max_age_ns": 1000000000,
    "dehaze_lut_generation": 0
  }
}
```

- 彩色先做 CAM0、CAM1 单独遮挡和对应画面检查。固定曝光条件与场景，保存彩色、灰度、高斯、HE 和组合的每眼样本，分别核对色度、边缘噪声与对比分布是否按请求变化。处理掩码和图像观察分别记录。
- 去雾查能力 `0x02`，`dehaze_lut_generation` 可用 0（自动）或 1（显式内建）。初次进入或本眼历史失效允许 `requested=1/applied=0` 恒等帧。两眼分别观察后续真正 `DEHAZE_FILTERED`，报告首个 applied 序号、稳态 applied 数／请求产品数及样本。HDR＋去雾同时核对 HDR_MERGED 和去雾 applied 两个位。
- 原车道使用含清晰车道标线与无候选场景，分别核对 F22、F23 终态和点数，保留有候选画面叠加。切出后下一有效 SDR epoch 应清除叠加。记录链路、叠加显示和识别准确率分开验收。
- 首轮纯接收后接入现有 RK 分眼 MPP 队列，按 SOURCE.camera 分发，保留身份。双目依次验 CAM0 全屏、CAM1 全屏、左右同屏，隐藏眼仍持续接收。通用 shell 的 `--decode` 要同时给 `--mpp-library` 和 `--mpp-timeout-ms`。若用其 HDMI 消费者，再给 `--pixel-library`、`--connector-id`、`--plane-id`、`--gst-colorimetry`。通用消费者适于单路核对，分眼与同屏使用现场匹配应用。库、Connector/Plane、色彩参数取现场实际值。MPP、合成、显示入口和物理 HDMI 分项记证据。

需要离线分眼时，可用 SDK 从已保存的完整 AJPG v4 记录流导出 JPEG 和身份 sidecar。指定本次 CFG session 与新输出目录。

```sh
python3 -B -m dual_host.dual_records --record-version 4 \
  --source-session "$CFG_SESSION" --input "$AJPG_RECORD_STREAM" --output "$NEW_EXPORT_DIR"
```

## 4. RAW10 驱动、冷选与收包

ARAW 是**未经压缩的 Bayer RAW10 定长打包直传**。FPGA 数据通路绕过 ISP、算法和 JPEG，使用 DDR RAW 槽、读出和 C2H。RK 如需 ISP，按实际 Bayer phase、bit depth、packing、stride、内存输入和校准方案单独接入验证，本位流的 RK ISP 结果为 **NOT_RUN**。

原发布 stereo-N2 以 Linux 6.1.99、内核 build-id `3029de626e5b93ec060106f70b361766bd9a7132` 为适配来源。其 KO 为 172,920 B，SHA-256 `61e2aa53f3c4a574744793c633292fcfd5ac83c1e372761e7372acd7c78766ec`，build-id `db2c5b1de225ec72596863cd70de845e3e6d59c7`。RAW 候选保留原 UAPI、N2 值守卫和租约规则，给 C2H_LEGACY 增加 FA8/FAC 读、FA8 冷写。FA8 只允许 0 或 1，写入须同 fd 在驱动 mutex 下满足 APP、DMA、源、发送、ARM、LOCK 空闲。越白名单、未对齐和非法值返回 `-EPERM`，忙态返回 `-EBUSY`。核对随包 `rk_support/raw_driver_candidate/SOURCE.json`，使用实际目标 kernel 构建树、配置、`Module.symvers` 和 ARM64 工具链。单独留存目标构建和加载身份。历史 seed92 实际板测 KO 的回执只用于对照。

```sh
mkdir "$RAW_BUILD_SOURCE" "$RK_RAW_SDK"
cp "$HANDOFF/rk_support/raw_driver_candidate/source/"* "$RAW_BUILD_SOURCE/"
make -C "$RK_KERNEL_BUILD" M="$RAW_BUILD_SOURCE" ARCH=arm64 \
  CROSS_COMPILE="$RK_CROSS_COMPILE" W=1 modules
cp -a "$HANDOFF/rk_support/rk_sdk/." "$RK_RAW_SDK/"
cp "$HANDOFF/rk_support/raw_driver_candidate/python/linux/dma_c2h_candidate/c2h_legacy_policy.py" \
  "$RK_RAW_SDK/linux/dma_c2h_candidate/c2h_legacy_policy.py"
export PYTHONPATH="$RK_RAW_SDK:$RK_PEER"
cd "$RK_RUN"
python3 -B -c 'from linux.dma_c2h_candidate import c2h_legacy_policy as p; print(p.__file__); assert 0xfa8 in p.WRITABLE and {0xfa8,0xfac} <= p.READABLE and 0xfac not in p.WRITABLE'
```

生成器需要完整 `1a5603c1` checkout 的匹配编译输入与 `e0818832` Git 对象；其生成器与上一版8258220f逐字节相同。从仓库根重生可用 `PYTHONPATH="$REPO/refactor/camera_raw_r2/rk_sdk:$REPO" python3 -B -m raw_driver.prepare --output "$NEW_RAW_DRIVER_OUTPUT"`。驱动加载、绑定与冷轮由设备负责人执行。Python 叠加应更新导入优先的私有 SDK 副本。

冷态核对同一 owner 的空闲/无租约/无 unread/未 ARM、APP=0、`REARM_READY`、CFG 初始 plain SDR 与 `owner.capacity >= 2592064`。`select_cold_raw` 先读回 JPEG 初态，双目写入 DUAL1/N2，单目采用已有 MONO，随后暂存 RAW 产品并发 APPLY。SDK 核对真实 APPLY DONE、当前活动拓扑/产品和同会话。RCD2 保持 BOOT 选择即可，ARAW 使用独立头和解析器。旧 JPEG shell 的 `--raw-record-dir` / `--raw-preview-dir` 属于旧 LZ 消费者。ARAW 走以下专用入口。

| STEREO BAR 偏移（字节） | 含义 |
| --- | --- |
| `0xF8C` / `0xF9C` | REQUEST_MODE / ACTIVE_MODE，MONO=0、双目=1 |
| `0xFA0` / `0xFA4` | REQUEST_DIVISOR / ACTIVE_DIVISOR，双目请求为 2 |
| `0xFA8` / `0xFAC` | REQUEST_PRODUCT / ACTIVE_PRODUCT，JPEG=0、RAW10=1，FAC 只读 |
| `0xF90` / `0xF94` / `0xF98` | COMMAND / STATUS / ERROR。APPLY=1，STATUS bit0 BUSY、bit1 DONE、bit2 LOCKED |

```python
from linux.dma_c2h_candidate.c2h_abi import RESULT_COMPLETE
from raw_control import select_cold_raw
from raw_video import RawVideoReceiver

selected = select_cold_raw(
    owner, cameras=cameras, max_record_bytes=owner.capacity,
    timeout_s=command_timeout_s, poll_interval_s=poll_s,
)
araw = RawVideoReceiver(
    session=selected.session, mode_epoch=selected.mode_epoch,
    cameras=selected.cameras, width=1920, height=1080,
)
owner.start()  # One START by the original owner after successful APPLY.

# In the existing receive loop, for each safe result from receive_available().
if lease.result == RESULT_COMPLETE:
    with lease.view() as view:
        owned_record = bytes(view)
    lease.release()
    frame = araw.accept(owned_record)
    packed_raw10 = frame.payload
```

上例首轮用独占副本。直接借用 DMA view 时，消费完毕再释放准确 lease。保留负完成与释放故障的原处理分支。STOP 后继续取安全结果，核对 `running=0, stopped=1, quarantined=0, submitted==completed, poll(0)=false, leased_count=0`，再查源／发送／FPGA 槽退休和 owner 安全关闭条件。SAFE、主机 lease release 和 FPGA 槽实际退休需分别关联。

ARAW 头为 64 B 小端，payload 每行 2,400 B、1,080 行共 2,592,000 B。四个样本依次在一个小端 40 位字的 bit 0–9、10–19、20–29、30–39。接入方按 LE5 解包后转换为目标 ISP packing，记录实际 Bayer phase（0 RGGB、1 GRBG、2 GBRG、3 BGGR）。解析校验 exact completion length、头、geometry、session/epoch、眼别、job 非零和眼内序号向前。真实跳号单独对账。实际满速两个拓扑合计记录吞吐目标均约 155.52 MB/s。协议未提供 ARAW payload 线校验，记录 SHA 用于样本溯源，像素正确性另用已知图样/解包核对。

```sh
python3 -B - "$ARAW_FILE" <<'PY'
from pathlib import Path
import sys
from raw_video import parse_raw_video

frame = parse_raw_video(Path(sys.argv[1]).read_bytes())
print(frame.width, frame.height, frame.camera, frame.source_session,
      frame.mode_epoch, frame.source_sequence, frame.bayer_phase,
      frame.job_id, len(frame.payload))
print(frame.unpack_samples()[:16])
PY
```

## 5. 本版UART与重点复测

本版必须使用随包 DJ/v3 解码器。详细采集命令、字节/位定义、配置等待状态及两种卡死的复测步骤见 [Linux交接重点](LINUX_HANDOFF.md) 和 [DJ/v3说明](UART_FIELD_V3.md)。
不要使用上一版的两个 PIX FS 计数位置解释本版数据：该32位现在为配置引擎已发布epoch；四路capture_admit和DFI各眼作业/拒收/负终态统计仍保留。

本轮把HDR T96映射由每拍一个像素扩为两个，并加入16字响应预取，同时保留既有配置/启动修复。本bit尚未上板；按第6节同窗对账验证HDR30/30，不从短测或时序通过推导实际帧率已达标。已有可调参数与完整示例见 [RK_PARAMETERS.md](RK_PARAMETERS.md)。

## 6. 同窗统计和判定

每次运行保留 `boot_id/run_id、bit/KO/应用 SHA、BDF、session、epoch、camera、source_sequence`。逐条再记 `host_monotonic_ns、capture_time_ns`（有效时）、`job/pair、slot/generation、wire_bytes、completion_status、release_ns、drop_reason`。帧去重按 `(run_id, session, epoch, camera, source_sequence)`，两眼序号各自比较。按共同单调时钟区间 `[t0,t1)` 取两个眼、FPGA 各级和 RK 各级的匹配证据。UART/RK 时钟未对齐时保留采集对齐误差和窗边在途数。逐眼 `FPS = 窗内唯一合格产品数 / 窗秒数`，分别记 SOURCE/准入、作业、有效记录、真实退休和 RK 解码/新画面，重复合成的旧眼图像只记公共输出。稳态区间、START 到首个有效帧、切换到首个新 epoch 帧、STOP 到最后结果/释放与槽退休分别计时。

| 判定项 | PASS 条件 |
| --- | --- |
| 冷启动／产品或目数切换 | 新冷轮和匹配环境中，冷回执与会话一致，JPEG 有 v4/2112 正 SELECT，RAW 有 `ACTIVE_PRODUCT=1`。各参与眼至少一条合法 1080p 首记录通过实际 DMA/解析到产品终态，STOP 排空和关闭证据完整 |
| 单、双目稳态 | 使用同一有效窗，分别达到单目 SDR/RAW 60、双目 SDR/RAW 各 30、HDR 各 30 的名义速率。建议每模式至少 60 秒有效窗，测试前登记现场帧率容差和重复次数。每眼无未知丢失、重复、倒退和错误完成，合格产品与实际退休对账，窗边在途及任何合法拒收均有解释 |
| 模式、画面及叠加 | APPLIED、ACTIVE、每眼新 epoch、实际产品标签及相应样本均符合请求。去雾有各眼实际 applied 证据，单目车道有正确终态和切出清线，双目各布局分别核对身份与新画面 |
| 故障与恢复 | 每项实际触发的失败有明确负终态或冻结证据，失败身份无伪造成功记录。按记录的安全路径冷建后，各相关眼重新完成合法首事务。未触发的负分支标 NOT_RUN |
| 未完成项 | 本次 seed25 交付的板级条目起始均为 **NOT_RUN**。实际观察违背判据记 FAIL，因设备或驱动阻塞记 BLOCKED，已采集但缺关键观测记 UNKNOWN。局部功能、持续帧率、像素质量、RK ISP 和 HDMI 分别判定 |

核对来源为固定源的 `refactor/camera_raw_r2/rk_sdk`、`docs/RAW_RK_CONTROL.md`、`docs/fieldfix_20261109/UART_FIELD_V3.md` 及协议 JSON。本轮直接对照是41cb5991 / seed56的双目HDR30/20板调记录，见版本差异文档；更早seed92的RK启动/驱动资料只是兼容背景。现场应保留本轮原始 UART、实际记录与报告，供后续按同一口径复测。
