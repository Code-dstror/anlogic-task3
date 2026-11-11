# camera_raw_r2 的 RK 在线参数

本页描述 `camera_raw_r2` 物理相机的 JPEG 会话，本包固定源为 `1a5603c1c8aa58565aa9b5facf40a7478ebcf6ba`，参数硬件合同沿用41cb5991。SDK 通过现有 CFG1/schema2 设置参数，同一 epoch 的配置由活动眼共用。设备 fd、DMA、槽租约和配置继续由原进程独占。 [启动和收包](rk_support/rk_sdk/README.md)

## 查看与设置

通过 `python -m linux.rk_debug shell --shared-camera mono|dual` 进入已匹配的 SDK 会话，在 shell 中输入 `caps`（或 `discover`）查看实际支持的模式、滤波与参数清单。`caps` 的 `parameters.base` 和 `parameters.schemas["2"]` 各是一组条目，以 `path` 为键识别，字段包括 `access`、`minimum`、`maximum`、`unit`、`default`。固定项还给出 `value`，枚举或位掩码的 `symbols` 给出可用取值。`parameters.constraints` 描述 D2 冷态 Q75、RAW 在线 CFG 和 host LUT 上传限制。`caps.active` 是同一设备的已生效快照。

`active` 读取当前 session、epoch 和配置。`configure @文件`、`configure {…}` 或 `run --config 文件` 提交配置。首次由 BOOT 进入 schema2 时必须提供完整 extension，或用 `mode sdr` 等简写生成。已在 schema2 时，省略的字段取自 ACTIVE。每次提交等待 APPLIED，并检查 `active` 的 epoch 和参数。下一次更改前用 `status` 确认 `camera_mode.seen_cameras` 已包含所有活动眼。两眼可先后产出新 epoch，接收线程按记录自己的身份分发。

共享 shell 使用 `SharedControls.discover()` 读取能力，用 `SharedControls.propose()` 根据 ACTIVE 形成并校验完整请求。共享会话再通过 `SharedStereoReceiver.apply()` 执行 PREPARE/COMMIT，并把确认的 epoch 交给接收器。去雾也通过这条 CFG 路径选择内建估参。 [共享会话入口](rk_support/rk_sdk/dual_host/debug_modes.py) · [配置和记录接收](rk_support/rk_sdk/dual_host/camera_shared.py)

### JPEG 基础配置

| JSON 字段 | 合法值 | BOOT 默认 | 生效方式 |
|---|---|---|---|
| `base.mode` | `0`（`COLOR`） | `0` | schema2 的滤波由 extension 独立选择 |
| `base.quality` | `1–100` | `75` | JPEG 请求质量，自适应时作为上限 |
| `base.min_quality` | `1–quality` | `1` | 自适应质量的下限 |
| `base.flags` | `0` 或 `1` | `0` | bit 0 为 `ADAPTIVE_QUALITY`，也可写 `["ADAPTIVE_QUALITY"]` |
| `base.frame_budget` | `0–16,777,216` B | `0` | 自适应打开时必须非零 |
| `base.restart_mcus` | `0–65,535` MCU | `0` | 0 禁用 restart markers |

双目 D2 由既有冷态 N2 入口以 Q75 启动。在线质量在 ARM/START 后设置。自适应读取已完成且成功的 JPEG 长度，首帧从请求质量开始，随后在 `min_quality` 与 `quality` 之间调整。预算是反馈目标，超预算帧仍可正常完成。核对实际编码质量与长度时读 AJPG header 的 `quality` 和 `payload_length`，DMA 容量沿用同一 owner 实际分配的 buffer。 [基础校验和事务](rk_support/rk_sdk/linux/task3_pipeline/config_transaction.py) · 质量控制（固定源RTL说明，未作为RK运行依赖打包）

### HDR 配对和合并

`extension.product_mode=2` 选择物理 DOL2 HDR。以下 HDR 值随当前 epoch 生效，全部由 owner 显式填写。`caps` 对可调 HDR 字段返回 `default: null`，表示进入 HDR 时没有自动注入的调参默认值。进入 SDR 时所有 HDR 字段填 `0`。

| `extension` 字段 | HDR 取值 | 单位与用途 |
|---|---|---|
| `hdr_ratio` | 固定 `4` | log2，物理长短曝光比为 16× |
| `hdr_black_long`、`hdr_black_short` | 固定 `50`、`50` | RAW10 码值，合并的数字减黑 |
| `hdr_qualification` | 固定 `15` | 完整资格位掩码 |
| `hdr_motion_base` | `0–16,383` | RAW14 码值，运动残差的基础阈值 |
| `hdr_motion_shift` | `0–15` | bit，对减黑后的长曝光值右移后加到运动阈值 |
| `hdr_max_delta_ns` | `0–4,294,967,295` | ns，两成员的时间差上界 |
| `hdr_max_wait_ns` | `1–4,294,967,295` | ns，候配窗口 |
| `hdr_max_age_ns` | `1–4,294,967,295` | ns，成员到达时的新鲜度窗口 |

delta 的线字段为 64 位，当前物理配对仅接受低 32 位。`delta=0`、`wait=1` 或 `age=1` 都在数字合法范围内，真实 DOL2 成员可能因此无法配对。CFG 仍要等合格帧才到 APPLIED。HDR 的曝光、增益、黑电平和资格采用既有固定配方。 [物理 profile 校验](rk_support/rk_sdk/dual_host/camera_shared.py) · RAW 配对校验（固定源RTL说明，未作为RK运行依赖打包）

### 模式、滤波和 RAW

- `product_mode` 的活动选择为 `MONO_SDR=0` 或 `MONO_HDR=2`。这两个字段名也用于双目 schema2，目数由冷态拓扑选择。
- `processing_enables` 按位组合。灰度 1、去雾 2、高斯 4、HE 8，具体以 `caps` 为准。单目另有多尺度 16 和车道 32，车道要求同时设置多尺度。`mode sdr lane` 会设置两位。
- 去雾开启时，`dehaze_lut_generation=0` 或 `1` 都选择同一内建算法。关闭去雾时填 `0`。共享 shell 的 `load-lut` 和 `query-lut` 保持禁用。高斯核、HE 和 C1 车道内部参数由当前硬件决定。
- RAW10 产品通过既有 RAW 冷选择入口启动。RAW 活动期间 FPGA 拒绝在线 CFG 写入。 [RAW 冷选与驱动合同](reference/RAW_RK_CONTROL.md)

## 完整 HDR 配置文件

保存为 `hdr.json` 后，可在已启动的共享 shell 中输入 `configure @hdr.json`。同一文件可用于 `run --config hdr.json`。以下数值用于展示现有接口，计时为 50 ms、100 ms、1 s，处理位 `10` 开启去雾与 HE。`--shared-hdr-policy hdr.json` 搭配 `mode hdr dehaze he` 时读取其中的九个 HDR 字段，保留当时 ACTIVE 的 JPEG 基础值。

```json
{
  "schema": 2,
  "base": {
    "mode": 0,
    "quality": 85,
    "flags": 1,
    "min_quality": 60,
    "frame_budget": 500000,
    "restart_mcus": 120
  },
  "extension": {
    "schema": 2,
    "product_mode": 2,
    "processing_enables": 10,
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

### 基于 ACTIVE 的局部更新

以下命令在上面的 HDR 配置已 APPLIED、活动眼已经收到该 epoch 后执行。它把请求 JPEG 质量改为 82、运动移位改为 4，保留 HDR、滤波、预算、restart 及其它字段。

```text
active
configure {"base":{"quality":82},"extension":{"hdr_motion_shift":4}}
active
status
```

降质量时，若现有 `min_quality` 高于目标质量，要在同一条命令里一并降低。关闭自适应并清空预算可用 `configure {"base":{"flags":0,"frame_budget":0}}`。退回 SDR 可用 `mode sdr`，由命令清空 HDR 策略字段。单独把 HDR 的 `product_mode` 改成 0 会保留其它 HDR 字段，因而被拒绝。

### Python SDK

下面的函数在应用已经用原 owner 完成冷选择、确认 v4 并执行 ARM/START 后调用。`rx` 是当前会话的 `SharedStereoReceiver`，`owner` 是同一 fd 的 `ConfigTransactions`。返回的 `AppliedConfiguration` 包含 `session`、`mode_epoch`、`first_actual_frame_sequence` 与完整配置。 [冷选择及 owner 创建示例](rk_support/rk_sdk/README.md#冷启与切换)

```python
from dual_host.camera_shared import SharedStereoReceiver
from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_pipeline.config_transaction import Configuration, ConfigTransactions
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration


def apply_hdr(rx: SharedStereoReceiver, owner: ConfigTransactions, budget_bytes: int):
    base = Configuration(
        quality=85,
        flags=p.PCIE_CFG_FLAG_ADAPTIVE_QUALITY,
        min_quality=60,
        frame_budget=budget_bytes,
        restart_mcus=120,
    )
    extension = MonoConfiguration(
        product_mode=p.PCIE_CFG_V2_MODES_MONO_HDR,
        processing_enables=p.PCIE_CFG_V2_ENABLES_DEHAZE | p.PCIE_CFG_V2_ENABLES_HISTOGRAM,
        hdr_ratio=4,
        hdr_black_long=50,
        hdr_black_short=50,
        hdr_motion_base=64,
        hdr_motion_shift=3,
        hdr_qualification=p.PCIE_CFG_EXT_HDR_QUALIFICATION_REQUIRED,
        hdr_max_delta_ns=50_000_000,
        hdr_max_wait_ns=100_000_000,
        hdr_max_age_ns=1_000_000_000,
        dehaze_lut_generation=0,
    )
    return rx.apply(owner, base, extension)
```

## 边界与匹配

| 请求 | 预期 |
|---|---|
| `quality=1,min_quality=1` 或 `quality=100,min_quality=100` | 基础范围合法 |
| `quality=0/101`、`min_quality>quality`、`flags=2`、`restart_mcus=65536` | 拒绝 |
| `flags=1,frame_budget=0` 或 `frame_budget=16777217` | 拒绝 |
| HDR `motion_base=16383`、`motion_shift=15`、`delta=4294967295` | 数字范围合法 |
| HDR `motion_base=16384`、`motion_shift=16`、`delta=4294967296`、`wait=0` 或 `age=0` | 拒绝 |
| HDR 任一 black 为 49、`ratio=3` 或 `qualification=14` | 拒绝 |
| SDR 任一 HDR 字段非零、双目请求车道、单目只请求车道位 32 | 拒绝 |
| 开启去雾时 generation 0 或 1，关闭时 generation 0 | 合法 |
| 关闭去雾时 generation 1，或开启时 generation 2 | 拒绝 |

共享 SDK 会在校验失败时拒绝提交，保持原 ACTIVE。设备端仍独立校验 PREPARE/COMMIT。若实际事务超时、设备拒绝或身份不匹配，沿用原 owner 的故障处理流程并核对 ACTIVE。

匹配版本时按发布清单核对 `camera_raw_r2` bit、设备内核/KO、peer SDK 和本候选 overlay。`caps` 的 `base`、`schema2` 与 ACTIVE 来源于当前设备，参数清单描述本 SDK 支持的物理合同。它们不能证明 bit 的源码 SHA。离线 `python -m linux.rk_debug catalog` 仍是通用 r3/LAB 清单。旧板测脚本及旧 bit 按其原配套环境运行，切换到匹配的 `camera_raw_r2` 发行包后使用本页命令。候选本轮 SDK 完善沿用原 CFG 和 AJPG 布局。 [SDK 装载顺序](rk_support/rk_sdk/README.md) · [原生工程来源](README.md)
