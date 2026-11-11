# RK3576 冷选单目 4K15 或 4K20

同一候选 bit 在每次冷启动选择单目 3840×2160 SDR15 或 SDR20 的 JPEG 或 RAW10。HD 使用原 SDK 入口，显式双目 HD40 使用 `rate_control.select_cold_dual_rate(owner, fps=40, ...)`。几何和产品锁定到本次冷会话，切换时沿用设备负责人的停止、排空与新 BOOT 流程。

## 同一 C2H owner 接线

向 `geometry_control.select_cold_uhd_jpeg` 或 `geometry_control.select_cold_uhd_raw` 传入已经打开的 `linux.dma_c2h_candidate.receiver.Receiver`。由调用方串行持有这个 fd，并确认设备 BDF、停止态及无在途记录。选择要求 APP 关闭、C2H 未开始、`SESSION_REARM_READY=1`、`SESSION_ARMED=0`，以及 fresh MONO 的 epoch 0 COLOR/Q75 BOOT。

| BAR 相对偏移 | 用途 |
| --- | --- |
| `0x018` / `0x01C` | 原应用 CONTROL 和 STATUS，基地址由现有 owner 处理 |
| `0xFA8` / `0xFAC` | 请求和活动产品，JPEG 为 0，RAW 为 1 |
| `0xFB0` / `0xFB4` / `0xFB8` | 原速率能力、请求和活动回读，UHD 选择要求请求和活动均为 legacy 0 |
| `0xFBC` / `0xFC0` / `0xFC4` | 几何请求、活动几何和只读能力，HD 为 0，UHD15 为 1，UHD20 为 2，当前能力为 `0x107` |

两入口默认 `fps=15`，显式传 `fps=20` 选择码 2。新 SDK 根据 `0xFC4` 的 ABI 1 和支持码位图验收，也可用旧 `0x103` 选择 UHD15。旧 SDK 将能力字与 `0x103` 做全字比较，使用 `0x107` 的候选时部署新版。选择沿用 N2 的冷 MONO 拓扑，依次写产品、几何和 APPLY，读回实际活动几何、产品与原 CFG 会话。CFG 须报告 profile 3、CAM0 presence 1、最大尺寸 3840×2160。DONE 确认该冷档已发布。接收以同一 fd 上的完整成功记录为准。请求回读不符、负回执或超时交给原 owner 的故障处理。

### JPEG 与预处理

`payload_budget` 由调用方提供，范围是 4 至 `min(MAX_PAYLOAD, Receiver.capacity - 2112)` 字节。`MAX_PAYLOAD` 为线协议的 16,777,216 B，native C2H record 上限为 16,779,328 B。函数读实际每槽 `Receiver.capacity`，完成原 AJPG v4 SELECT，再返回按 CAM0、会话、epoch、几何、彩色 SOF 和负载上限校验的接收器。

```python
from geometry_control import select_cold_uhd_jpeg
from linux.task3_pipeline.config_transaction import Configuration, ConfigTransactions
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration

options = dict(timeout_s=command_timeout, poll_interval_s=poll_interval)
jpeg = select_cold_uhd_jpeg(owner, fps=20, payload_budget=jpeg_payload_budget, **options)
owner.start()  # 发布驱动在同一 fd 上执行 RESUME 和 APP ARM

# 在原接收线程中复制成功完成的记录，再按原 lease 流程释放槽。
item = jpeg.accept(owned_record)
jpeg_bytes = item.record.jpeg

# 在同一 owner 的控制线程中更新 SDR，接收线程继续工作。
cfg = ConfigTransactions(owner, **options)
base = Configuration(quality=quality, min_quality=min_quality,
                     frame_budget=configured_frame_budget, restart_mcus=restart_mcus)
applied = jpeg.apply(cfg, base, MonoConfiguration(processing_enables=0x0d,
                                                quality_version=1, isp_wb_enable=1,
                                                isp_wb_r=864, isp_wb_g=410, isp_wb_b=784))
```

融合预处理 CFG `FEATURES=0x7f`，schema2 SDR `ENABLES=0x0d`。灰度 `0x01`、图像 Gaussian `0x04` 和 HE `0x08` 可组合。手动 WB 使用 schema2 的三个 Q8 系数，Tone 与融合预设保持零。基础 `PREPARE` 使用 `jpeg.apply(cfg, base, None)` 按 `base.mode` 选择 COLOR、GRAY、GAUSSIAN 或 HISTOGRAM。schema2 的 `base.mode` 取 COLOR，处理从 `processing_enables` 选择。融合 SDK 可读取旧 UHD `FEATURES=0x0f/0x3f`。原 R3 SDK 会按旧值精确比较，融合 UHD 需要配套本 SDK。UHD JPEG 使用三分量 4:2:2，灰度的色度为中性，处理掩码随实际 APPLIED epoch 检查。

可配置质量、最低质量、adaptive、预算和 restart。配置预算须在接收预算以内。新 epoch 在 APPLIED 回读前到达时，沿用 `AwaitingApplied` 的有界独占副本队列。接收预算是主机验收上限，传入该预算时 FPGA 的初始 Q75 BOOT 继续生效。

### RAW10

4K ARAW v1 为 `64 + (3840 / 4) × 5 × 2160 = 10,368,064 B`。每槽实际 `Receiver.capacity` 至少为该值。选择后使用原 C2H 完成长度和租约，RAW 会话保持 BOOT 配置。解析器借用打包样本视图，消费者用完后再释放视图和租约。

```python
from geometry_control import select_cold_uhd_raw

raw = select_cold_uhd_raw(owner, fps=20, timeout_s=command_timeout, poll_interval_s=poll_interval)
owner.start()

# 在原接收循环中，lease 对应一条 RESULT_COMPLETE。
with lease.view() as view:
    frame = raw.accept(view)
    try:
        consume_packed_raw10(frame)
    finally:
        frame.payload.release()
owner.release([lease])
```

旧板记录的 CMA 为 16 MiB。4 KiB 对齐后，每个 4K RAW 槽占 10,371,072 B，两个槽合计 20,742,144 B，另需 fence 等连续内存。双槽验收需要更大的可分配池，并以实际分配成功和 `Receiver.capacity` 读回为准。单槽可用于首事务，持续接收需独立实测。 [原容量证据](../../camera_rate_r1/docs/UHD_RESOURCE_OPTIONS.md)

## 发布 N2 派生驱动

从固定的发布 N2 C/头文件、Makefile 和 Python 白名单生成源码。派生策略新增 FBC/FC0/FC4 读取与 FBC 冷写 0…2。原 DUAL1/N2/APPLY1 守卫、设备 fd、UAPI、DMA 安全退休和租约流程沿用 N2。C2H_LEGACY 批预检检查 APP、DMA、源、ARM、STEREO 锁定与几何写入所需的空闲条件。 [生成器](../fpga_src/rk_sdk/raw_driver/prepare.py)

```sh
export PYTHONPATH="$R2_SDK:$PUBLISHED_N2_PEER:$REPO"
python -B -m raw_driver.prepare --output "$NEW_SOURCE_DIR"
```

输出包含 `source/`、`raw-product.patch`、`SOURCE.json` 和 `python/linux/dma_c2h_candidate/c2h_legacy_policy.py`。运行时把生成的 Python 策略装入私有 R2 SDK 副本的同一路径，将该副本放在发布 peer 之前，从两个包目录之外启动。目标 KO 需要与实机 Linux 6.1.99 的配置、构建树、符号表和 ARM64 工具链匹配。

## 验证范围

本工程采用独立公开 [UHD CFG 合同](UHD_CFG_PUBLIC.md) 和 [首事务夹具](../fpga_prj/verification_archive/verification_reference/uhd_integration_public/CONTRACT.md)。
目标 KO 构建、加载、实板 DMA、JPEG 硬解和持续 4K15/20 验收为 `NOT_RUN`。
