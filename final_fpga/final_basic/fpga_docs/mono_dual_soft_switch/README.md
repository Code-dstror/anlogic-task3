# 不重烧比特流切换单目／双目：RK 实施与验证说明

适用 FPGA：`camera_raw_r2 · 1a5603c1c8aa58565aa9b5facf40a7478ebcf6ba / seed25`。
bit SHA256：`eee7eff50323a8a5c7ddc850d3873e1dda13473debbfe8a690bcb6bab17ac362`。
直接对照随包 SDK 和 RAW/N2 驱动源码；队友的实际私有运行时、KO 必须另核对身份。

**本文是基于现有电路的实施方案，不是已通过上板的热切换操作手册。当前发布的驱动／SDK不能原样执行完整流程。**
目标是在同一 bit、同一 RK 启动周期、同一 PCIe 设备和 owner 下重建 FPGA 图像会话，再选择目数；视频允许短暂中断。
不是连续帧之间无缝切换，也不是把双目预览隐藏一眼。真正单目需恢复传感器 SDR60 配方，双目需 SDR30 配方。

本说明不修改 RTL、生产驱动、原调试 ZIP 或服务器任务。附带程序只读，不能执行复位或自动切换。

## 1. 已确认的能力和实际缺口

| 项目 | 固定源码中的行为 | 对实现的含义 |
|---|---|---|
| 同一 bit 支持单／双目 | `stereo_cold_control` 包含 MONO=0、DUAL=1 | 不需要为不同目数下载不同 bit |
| 拓扑锁定 | APP 或 C2H 启动置 LOCKED；普通 STOP 没有清锁分支 | 关预览、退出进程、STOP/RESUME不能当作重新冷选 |
| 会话软复位 | `production_soft_reset_fence` 先等待真实静默和 token drain，再请求会话复位 | 有复用基础，但超时不能代替旧事务排空 |
| 清除拓扑锁 | PIX/DFI 会话复位会使拓扑控制器的共同复位有效 | 在软复位真正完成后，有望回到未锁定 MONO |
| CFG 与记录格式 | CFG 重新 BOOT；记录选择器受 DFI 共同复位，回到 v1/64 | 必须确认新的非零 CFG session，并重新 SELECT AJPG v4/2112 |
| 内核和 Python 白名单 | 随包 `C2H_LEGACY` 不允许写 CONTROL=0x018 | 直接 `owner.write32(CONTROL, SOFT_RESET)` 会被拒绝，不能仅靠新增Python脚本实现 |
| 发布 N2 值守卫 | 仅允许 MODE=1、DIVISOR=2、APPLY=1 | 回单目应依赖软复位后的默认 MONO；不要直接写 MODE=0或DIVISOR=1 |
| 通用 SharedDebugSession | 要求累计submitted/completed均为0，且要求BOOT v2/192 | 不适合直接用于同fd软复位后的再初始化；固定bit默认v1/64，生命周期计数允许非零但必须对账相等 |

“必须重启／重烧”是此前交付采用的保守恢复流程，不是由摄像头数量本身决定的硬件要求。但在完成下面的驱动适配和验证前，不能宣称当前bit已经支持可靠的软件切目数。

## 2. RK侧最小适配范围

优先在原独占 C2H owner 内增加一个受控的“图像会话重建”入口；FPGA BAR、CFG1/schema2、AJPGv4报文格式保持。
内核控制入口的具体 ioctl 编号由 Linux 工程统一分配，本文不自创线上 ABI。

该入口应复用原驱动的fd、mutex、DMA队列、槽租约和故障处理，不增加第二套BAR映射。最少需要：

1. 能停止新的图像准入，并继续接收、处理和归还已承诺事务，随后安全停止 DMA。
2. 在原 owner 排空边界，由内核执行一次受控的会话软复位请求。CONTROL偏移0x018、SOFT_RESET位值0x2为现有FPGA定义；这是驱动内部动作，不能开放任意CONTROL写入。
3. 允许用户态等待并读取新的CFG BOOT、REARM_READY、未锁定拓扑和记录格式状态；不以延时若干秒代替回执。
4. 同fd重建SDK配置/收包/分眼对象，允许内核生命周期累计计数非零，保留计数审计和租约身份。不得清零计数来绕过现有prepare检查。

**先解决排空顺序，再加入软复位请求。** `ReceiverSnapshot.transport_drained`只说明主机无在途DMA，不证明FPGA还有没有READY帧、JPEG写入或RAW借用。
若先停止所有DMA，FPGA仍有等待输出的帧，软复位fence可能一直等静默；也可能存在已armed但尚未完成的buffer。不能用重复RESET、强制清槽或延长超时掩盖。
现有 `Receiver.stop()` 同时停止APP和DMA，其返回不能单独充当这个新流程的全系统排空证明。应复用或补齐驱动原有的受控source-off／drain机制，检查实际状态。

首版只覆盖 **JPEG→JPEG 的单／双目切换**。RAW/JPEG产品互换、quarantine故障恢复不在本方案的已验证范围内。

## 3. 完整操作顺序

以下步骤由原应用的一个控制worker串行执行；收包worker在需要排空时继续运行。不得由第二个独立进程打开设备执行这些动作。

### A. 保存旧会话并恢复普通SDR

- 记录bit、应用/SDK/KO/kernel身份、BDF、RK boot_id、原owner身份，以及旧CFG session、epoch、目数。
- 暂停接收新的UI配置请求；等待当前CFG事务到确定终态。
- 首次验证时，先用现有在线CFG切到 `mode sdr`，保持Q75，等待APPLIED与当前所有活动眼的新epoch真实记录。这样先把HDR退出、去雾状态与拓扑重建分开验证。
- 同一owner调用附带的 `collect(owner)` 保存 `before.json`。不要以清除RK画面缓存代替停止FPGA工作。

### B. 停止准入并证明排空

- 通过适配后的原驱动入口禁止新准入，持续处理合法完成、归还准确slot/generation租约；停止显示/解码消费者借用旧buffer。
- 核对主机无未取完成、leased=0、无quarantine、submitted==completed；FPGA已接事务也要到真实终态。
- 结合既有UART观察：RAW/JPEG owner、writer/reader、READY/发送状态、credit与buffer状态。UART各域不是同拍快照，只作定位辅助，不能由一次“看起来idle”授权清除所有权。
- 需要继续DMA才能退休的旧帧应先完成。若既有接口不能构成完整排空，不进入步骤C，记录阻塞并补齐该接口。

### C. 执行一次受控软复位，等待新BOOT

由同一owner的受控驱动入口发出一次现有SOFT_RESET请求。FPGA内部依次经过DRAIN、EXECUTE、WAIT_BOOT；请求不是立即清除DDR/product所有权。
沿用应用显式配置的等待预算，不能超时自动重发。成功必须看到以下事实，而非只看到STATUS某一位：

| 观察项 | 进入重新选择前的要求 |
|---|---|
| PCIe与owner | 同一BDF、同一owner；LINK_UP和USER_RESET_RELEASED有效 |
| APP／DMA | APP关闭、C2H/TX/SOURCE不忙；主机stopped，无lease、未取完成和quarantine |
| 会话 | SESSION_ARMED=0、SESSION_REARM_READY=1；新CFG session非零且不同于旧session，ACTIVE session一致 |
| CFG | SESSION_READY、ERROR=0；epoch0、COLOR、Q75，无未完成事务 |
| 拓扑 | LOCKED=0、BUSY=0、ERROR=0，恢复MONO，profile=MONO1920、camera_present=1 |
| RCD2 | 恢复此bit默认版本1／头长64，尚未为新会话SELECT v4 |

保存 `after_boot.json` 并用附带程序检查。观察匹配仅允许继续验证下一步，不证明整个切换已成功。
新session形成后丢弃旧**应用级**CFG等待、元数据、MPP/显示队列和热恢复票据；旧DMA租约必须已经按真实终态归还，不能在这里直接丢掉。

### D. 选择目标目数，再选择记录格式

目标为单目：保留已实读确认的默认MONO，不写MODE=0，也不写DIVISOR=1。单目60fps由实际相机配方/硬件路径决定，不是通过改N2白名单实现。

目标为双目：调用现有 `select_cold_mode()`，MODE=DUAL_JPEG(1)、frame_divisor=2、jpeg_quality=75，等待DONE并核对ACTIVE_MODE、ACTIVE_DIVISOR和双目能力。内部目标仍是两眼传感器原生SDR30，外部D2协议保持。

两种目标都用新会话对象对AJPG执行一次SELECT v4/2112，核对请求/响应session和序号、返回版本/长度及error，然后才START。
不要直接再次调用旧 `SharedDebugSession.prepare()`；其“累计计数为0”和“BOOT v2/192”假设需要适配。
可复用 `C2HSession.prepare()`、`SharedStereoReceiver`、`SharedRecordReader`，但必须由应用维护同一个原owner并替换旧会话对象。

以下仅是**步骤C已通过后的现有API连接示例**，不是完整切换脚本：

```python
from dual_host import stereo_control_v1 as stereo
from dual_host.stereo_control import select_cold_mode
from linux.task3_runtime.session import C2HSession
from dual_host.camera_shared import SharedStereoReceiver

# owner是原应用仍持有的同一个Receiver；after_boot检查和排空证明已完成。
topology = None
if target_cameras == 2:
    topology = select_cold_mode(
        owner.read32, owner.write32, stereo.STEREO_MODES_DUAL_JPEG,
        frame_divisor=2, jpeg_quality=75,
        timeout_s=config_timeout_s, poll_interval_s=poll_s,
    )
# target_cameras==1时必须已检查默认MONO；不写被N2守卫拒绝的MODE=0。
new_session = C2HSession(owner, jpeg_version=4, timeout_s=config_timeout_s)
selection = new_session.prepare()
new_rx = SharedStereoReceiver(
    topology if topology is not None else new_session.transactions,
    selection, cameras=target_cameras, max_record_bytes=owner.capacity,
)
# 用new_rx重建原SharedRecordReader，接收worker准备就绪后才new_session.start()。
# 旧session不能close同一owner，也不能恢复旧热启动票据。
```

### E. START与功能恢复

由新会话执行一次START，核对相机重新配置/预热，以及目标活动眼的第一条真实1080P AJPG v4记录。
按新CFG session、epoch、camera和source_sequence分发；不把旧眼的最后一帧留在屏幕上冒充新流。
单目必须仅有CAM0有效产品，双目必须两眼都收到。随后再按新会话在线开启灰度、高斯、HE、去雾、HDR或单目车道。
记录切换中断时间、首帧延迟和稳态分眼FPS，三者分别统计。HDR目标为每眼约30fps，不能由总显示刷新率代替。

## 4. 附带检查程序怎么用

`switch_probe.py`不打开设备、不写BAR、不发STOP/RESET/START、不归还lease，只调用传入owner的读接口。不会自动轮询或在异常后重试。
应接入已有应用并在其控制/接收串行化边界调用；不要另开一个拥有设备fd的诊断进程。

```python
import json
from pathlib import Path
from switch_probe import collect

# 由原应用分别在步骤A和步骤C完成后调用；path每次使用新文件名。
Path(path).write_text(json.dumps(collect(owner), indent=2), encoding="utf-8")
```

离线检查示例（从这份补充包目录运行；HANDOFF是原seed25调试包解包根目录）：

```sh
export PYTHONPATH="$HANDOFF/rk_support/rk_sdk:$PYTHONPATH"
python3 -B switch_probe.py /绝对路径/before.json /绝对路径/after_boot.json
```

- 返回0、`BOOT_OBSERVATIONS_MATCH_NOT_SWITCH_QUALIFIED`：可观察的BOOT条件匹配，不代表槽排空、相机成功或切换测试PASS。
- 返回1、`BLOCKED`：按issues查缺失条件，停止推进START。
- 返回2、`INVALID_INPUT`：输入缺字段/格式不符。
- 读BAR失败保留异常，不绕过白名单；瞬间变化造成identity_stable=false时，在原控制流程稳定后重新取一次，不自动循环。

## 5. 最小上板验收与失败留证

先验证纯SDR：单→双→单，至少两轮；每段目标眼完成真实首记录和正常退休，再取60秒稳态窗口。
随后覆盖HE／去雾／HDR运行后退回SDR再切目数，并验证切换后的HDR两眼身份与帧率。
同一RK boot_id、BDF和bit SHA保持；新CFG session推进；每轮分别记录请求、排空、新BOOT、拓扑DONE、v4 SELECT、START和首记录时间。

失败时保存：原始UART、owner/driver snapshot、CFG/record/stereo回执、各眼最后记录身份、lease/队列信息。既有quarantine或不确定DMA归属不能进入此正常切换路径。
不要为了让步骤继续而忽略LOCKED、清零软件计数、复用旧session、直接写BAR、解绑驱动或重枚举PCIe。
若正常软复位不能回到新BOOT，应转交主工程检查相应fence/排空路径，不能把它标为“只差RK适配”。

## 6. 本说明的验证边界

已做：固定源码静态核对；只读检查程序的软件模型短测。没有运行RTL仿真、修改RTL、加载驱动或操作开发板。
当前“单／双目不重启切换”的完整RTL链验证、目标KO编译、板级实际切换和满幅持续性能均为 **NOT_RUN**。
源码绑定和实际软件模型结果分别见 `SOURCE_BINDING.json`、`VALIDATION.json`。
