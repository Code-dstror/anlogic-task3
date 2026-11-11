# RK3576 冷启动选择 RAW10

使用当前唯一 C2H owner 已打开的 fd。在 APP 关闭、DMA 未启动、SESSION_REARM_READY 已发布且 SESSION_ARMED 为 0 时，先确认 CFG 的同一会话已完成 epoch 0 plain SDR BOOT。生产 1920×1080 RAW10 的一条记录为 2,592,064 字节，缓冲容量取 `Receiver.capacity` 的实际值。

| BAR 字节偏移 | 访问 | 冷启动语义 |
|---|---|---|
| `0xFA8` REQUEST_PRODUCT | 读写 | 暂存 JPEG 0 或 RAW10 1 |
| `0xFAC` ACTIVE_PRODUCT | 只读 | 当前已发布的产品 |
| `0xF90` STEREO_COMMAND | 写 APPLY 1 | 同时发布拓扑、divisor 和产品，等待原双域 DONE |

`select_cold_raw` 先检查原 STEREO ABI2 和 CFG BOOT，再探测两个产品寄存器。双目依次暂存 REQUEST_MODE=1、REQUEST_DIVISOR=2 和 REQUEST_PRODUCT=1。单目确认 BOOT 的请求及活动拓扑均为 MONO 0，直接暂存产品，沿用发布 N2 驱动的 DUAL1 值守卫。两条路径在 APPLY 前读回 RAW 请求值，返回前核对 DONE、ACTIVE_PRODUCT=1 及同一 CFG 会话。双目 D2 的目标是每眼原生 SDR30、捕获 divisor1，单目为 SDR60 全帧。RAW 活动期间由 FPGA 拒绝 CFG 写，APP 或 C2H 启动后沿用冷拓扑的锁。 [实现](../rk_sdk/raw_control.py) · [协议](pcie_protocol_v1.json)

```python
from raw_control import select_cold_raw
from raw_video import RawVideoReceiver

selected = select_cold_raw(
    owner, cameras=2, max_record_bytes=owner.capacity,
    timeout_s=command_timeout, poll_interval_s=poll_interval,
)
receiver = RawVideoReceiver(
    session=selected.session, mode_epoch=selected.mode_epoch,
    cameras=selected.cameras, width=1920, height=1080,
)

# 选择返回后由同一 owner 按现有顺序执行 ARM/START 和收包。
# 每条 owned_record 来自 RESULT_COMPLETE，沿用原 owner 的缓冲区生命周期。
frame = receiver.accept(owned_record)
packed_raw10 = frame.payload
```

每眼 SOURCE 序号独立递增，允许跳号。直接借用 DMA 缓冲时，使用完 `packed_raw10` 再释放该租约。

ARAW v1 使用自己的 64 字节头。原 RCD2 选择可保持 BOOT v1；C2H 仍按实际完成长度和原租约协议交付完整记录。应用按所选产品将 ARAW 交给 RAW 解码入口，JPEG 继续走原 AJPG 消费者。产品请求回读失败、DONE/ACTIVE 不一致或会话变化都交由原 owner 处理故障及关闭。 [ARAW 解码](../rk_sdk/raw_video.py)

## 匹配的驱动源码

发布 `stereo-n2` KO 为 172,920 字节，SHA-256 `61e2aa53f3c4a574744793c633292fcfd5ac83c1e372761e7372acd7c78766ec`，build-id `db2c5b1de225ec72596863cd70de845e3e6d59c7`。配套内核为 Linux 6.1.99，build-id `3029de626e5b93ec060106f70b361766bd9a7132`。生成器核对目标实际编译的五份 C/头文件和来自 `e0818832` 的 Makefile，共六个 SHA-256。发布 peer 的 Python 预检也按独立 SHA-256 核对。 [发布 KO 构建回执](../../../deliverables/DUAL_SDR_seed51_首轮故障分析与修复规划_20261101/field_originals/matched_driver_sources/compiled-build-result.json) · [源码生成器](../rk_sdk/raw_driver/prepare.py)

`C2H_LEGACY` 原批量预检新增 FA8/FAC 读取和 FA8 冷写。对 FA8 仅放行值 0/1，要求已有 fd 及其 mutex 下 DMA idle、无 active buffer、APP 关闭，且源、发送、ARM 与 STEREO LOCK 均为空闲。非白名单或不对齐的偏移、非法值返回 `-EPERM`，忙态返回 `-EBUSY`。原 DUAL1/N2/APPLY1、PCI 动态绑定、DMA 生命周期和 UAPI 按发布源码保留。

从仓库根目录以 `rk_sdk` 在前、发布 peer 在后设置 Python 导入路径，在新的运行目录生成 `source/`、`raw-product.patch`、`SOURCE.json` 及 Python 策略叠加。目标运行时在私有 SDK 副本里使用 `python/linux/dma_c2h_candidate/c2h_legacy_policy.py`，使原 Receiver 在加载时读到新白名单。

```sh
export PYTHONPATH="$CAMERA_RAW_R1/rk_sdk:$PUBLISHED_N2_PEER:$REPO"
python -B -m raw_driver.prepare --output "$CAMERA_RAW_R1/tmp/rk_raw_control/new-source"
```

## 已验证范围

源绑定生成通过。`test_raw_control` 共 10 项通过，使用发布 Receiver 的 `C2H_LEGACY` 打包路径及无设备 ioctl 模型。覆盖单目 BOOT、双目 D2、热写拒绝、旧地址读失败、HDR 和容量拒绝、错误请求回读、DONE 与 ACTIVE 不一致、原 Python 白名单及 AJPG v1/v4 对合法 ARAW 的 magic 拒绝。宿主 MinGW 还编译并执行了从补丁后 `ph1a_c2h.c` 抽出的实际 C 批量预检，覆盖值、对齐、只读、运行、活动 buffer、APP/ARM/LOCK 和原 N2 值保护。 [测试](../rk_sdk/test_raw_control.py) · [本次源和补丁哈希](../tmp/rk_raw_control/n2_raw01/SOURCE.json)

```sh
# RK_RAW_TEST_CC 取本机可执行的宿主 C 编译器。
RK_RAW_TEST_CC="$HOST_CC" python -B -m unittest -v test_raw_control
```

本次目标内核 KO 构建、加载、实际 DMA 及 RK 图像处理均为 NOT_RUN。目标构建需要当前设备匹配的 Linux 6.1.99 构建树、配置、符号表和 ARM64 工具链。
