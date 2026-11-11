# seed12 两轮彩色切 HDR 与第二轮双眼作业缺口

第二轮第 21 笔彩色→HDR 复现了第一轮第 19 笔的首帧等待状态：远端配置已确认，CAM0 已稳定，CAM1 配方写完但停在预热，目标 epoch 没有新曝光准入。第二轮四个**已经成功进入 HDR** 的窗口是另一类问题：四路曝光准入都约 30.3/s，双眼作业合计却一直约 50.4/s；哪只眼少接作业，哪只眼的 BEGIN 拒收就增加。两类现象须分别验证。

## 原件与身份

两轮均为 `camera_raw_r2` 源 `4a08ae35391e7b7ea6767260d7d1b4b182ef4bb9` 的 seed12 双目 JPEG 冷启。交付 bit 实测 4,850,315 字节，SHA256 `ee344e8084e2485c76ba523ccbc224a04c4b2d8fe6f6c14ba734937327f32727`，与交付清单、两轮现场下载回执和第二轮会话一致。下载身份依据操作者冷启与下载回执，独立 SRAM 读回 `NOT_RUN`。第二轮 RK boot `37371c86-93fe-4b52-9f88-3179fcc929ac`，run `4b2779ce77a2905bfdb04549f2118692`，owner PID 2445，BDF `0000:21:00.0`。两轮 runtime 封印一致；现场提供的复用记录注明 control 差异限于独立部署路径的模板及其索引。

外层 `SHA256SUMS.txt` 的 125 项全部匹配，第二轮返回原件 41 份逐项核验长度和 SHA256（40 份整文件，owner.log 为尾部）。嵌套首轮 ZIP 的 SHA256、123 个条目及内部清单身份匹配，复用[首轮已核验结果](../seed12fix_20261109/EVIDENCE.md)。第二轮 65,825 字节 UART 原件按 3,515 条读取偏移复组，独立复算 678 条 OB/v2 与 678 条 DJ/v3 的包头、CRC、字段及读取块关联，均与留存解码一致；仅前缀 59 字节无完整包，尾部无残片。两眼首个 SDR/HDR 的 4 个 AJPG 原件和 sidecar 长度、哈希一致。见[两轮交接包](../../../../deliverables/CAMERA_RAW_R2_seed12_两轮报告与HDR证据_给FPGA_20261109/CAMERA_RAW_R2_seed12_两轮报告与HDR证据/)与[逐项计数](EVIDENCE.json)。

## 已发布 HDR：缺口与 BEGIN 拒收同行

逐条使用 RUN、DFI/PIX 同一 epoch、PIX 已发布且双域有效的 DJ 快照；同序号 OB 三域有效，用各自的首尾快照做差。`capture_admit` 是 PIX 真实准入，HDR 槽序为 CAM0 L/S、CAM1 L/S；`jobs` 是 DFI 接作业握手，`last_source` 是最近被接作业的 SOURCE 序号，并非独立的完整 SOURCE 到达计数。差分为 16 bit（准入、作业、OB）或 8 bit（拒收、过期、坏 FINISH）模计数；连续样本每秒 BEGIN 增量最多 21，epoch 19 的 CAM1 发生回卷。RK 窗另从 `MODE_VIDEO_CONFIRMED` 后至下一次 `MODE_REQUEST` 前选取，两眼预览原件均核对同 epoch；两种时钟不可跨机相减。

| epoch / DJ 序号 | 秒 DJ / RK | 四路各准入 Δ | 作业 Δ CAM0/CAM1（每秒） | 末接 SOURCE 序号 Δ | BEGIN 拒收 Δ | pair 过期 / 坏 FINISH Δ | RK 解码 FPS CAM0/CAM1 |
|---|---:|---:|---|---|---|---|---|
| 1 / 369–377 | 8.000 / 8.028 | 242 | 200/203（25.000/25.375） | 242/242 | 84/76 | 0/0、0/0 | 25.039/25.537 |
| 3 / 380–383 | 3.000 / 2.004 | 91 | 91/60（30.332/19.999） | 91/90 | 0/60 | 0/0、0/0 | 29.941/19.961 |
| 8 / 411–418 | 7.000 / 6.020 | 212 | 141/212（20.144/30.288） | 212/212 | 140/0 | 0/0、0/0 | 20.264/30.231 |
| 19 / 441–448 | 7.001 / 7.017 | 212 | 212/142（30.282/20.283） | 212/213 | 0/142 | 0/0、0/0 | 30.211/20.236 |

每眼以等量 L/S 准入减去作业，四窗缺口依次为 `42/39、0/31、71/0、0/70` 个 pair 当量；`BEGIN 拒收 ÷ 2` 与缺口每眼相差最多 1。四窗两眼作业合计为 `50.375 / 50.332 / 50.432 / 50.565` 每秒；慢眼随重进 HDR 交换，首窗缺口分到两眼。epoch 19 左右同屏，真实可见新 SOURCE 为 `29.926/20.093 FPS`；前三窗只显示 CAM0，CAM1 仍登记与解码。总输出 FPS 不能代替分眼新画面；这些短窗不证明长期容量或延迟。

| epoch（样本数） | 两 bank 都非 FREE CAM0/CAM1 | DJ RAW 读 quiet；OB HDR 写 quiet | OB HDR scheduler busy / credit reserved | OB PIX 准入/JPEG result Δ | OB DFI writer ACK/READY claim Δ | OB USER descriptor/retire Δ；buffer armed |
|---|---|---|---|---|---|---|
| 1（9） | 6/2 | 1/1 | 8/1 | 403/403 | 403/403 | 404/404；7 |
| 3（4） | 1/0 | 2/2 | 2/2 | 151/152 | 152/152 | 152/152；3 |
| 8（8） | 3/3 | 2/2 | 6/2 | 353/353 | 353/353 | 353/353；7 |
| 19（8） | 4/2 | 1/1 | 7/1 | 354/355 | 355/355 | 354/354；5 |

固定板源 `hdr_eye_shared.v` 的 bank 编码为 `0 FREE / 1 BUILD / 2 READY / 3 OWNED`，按 CAM0 两 bank、CAM1 两 bank 排列。29 个 DJ 样本每眼均至少有一个非 FREE，`hdr_owner_empty` 未置位；但慢眼并不总在样本上更满（例如 epoch 3 的 CAM1 没采到两 bank 同占用）。约 1 Hz 的异域快照无法反推 BEGIN 决策沿的可用 bank、等待时长或饱和比例。

固定板源的 `diag_begin_reject` 是 owner 对 BEGIN 握手的聚合拒收；包括描述符或时序资格不合法、失败同组、目录配对检查不通过、无 FREE bank 等。无空 bank 时拒收首成员并记录该组，后续同组另一成员即使遇到空 bank 也不得另起半组。**拒收增量及零 pair 过期、零坏 FINISH 增量，与完整组被拒相符；现有包没有分离拒因，不能据此判定只需增 bank，或断言共享调度的具体瓶颈。** 已确认的缺口在 DFI 作业成立前；稳定的总作业率与随 cohort 交换的慢眼，支持优先验证双眼 bank 释放和共享调度的相位/服务时长。

OB 的 PIX、DFI、USER 各级增量与总作业数相差最多 1，USER 描述符和退休在每窗同增。29 个 USER 样本的 link、BME、supervisor、memory owner 均有效且无 USER 粘滞故障或恢复；22 个 `WAIT_RECORD` 样本均 buffer armed，余 1 个 `RUN`、6 个 `RESULT` 均未 armed。DFI 无当前 bridge/store recovery；粘滞 `0xC` 为窗口前已存在的事件，不能视作窗内新增。快照未采到 writer ACK valid 或 READY valid，握手计数却持续增长。DJ RAW 读 quiet 只是 RAW store 的瞬时状态，没有每笔 HDR 读回及等待原因。现有证据未见持续 DMA 停顿，且 RK 解码无法单独解释已在 FPGA 上游出现的缺口。更短的 USER 补槽、下游 credit 或 reader/writer/ticket 释放等待仍可能通过反压增加 bank 占用。验证容量或公平性时应逐组关联实际 BEGIN/拒因、两成员 FINISH、pair/作业、bank 释放、产品及 USER buffer/退休，并用首事务和同窗双眼对账区分启动、稳态与排空。

## 第 21 笔：与首轮第 19 笔相同的预热停滞

第二轮 owner 原件与 CSV 的 21 笔请求逐一相符：前 20 笔有 APPLIED 和新画面确认，四个 HDR epoch 为 1、3、8、19；第 21 笔无两类成功事件，10.038666427 秒后原保护 STOP（首轮 10.005938391 秒）。两份 STOP 后 CSR 快照间隔 20.465939 ms、90 项值一致；未额外开接收 fd、发 ioctl 或写 MMIO。请求/响应编号为 21/21（首轮 19/19）、`CFG_STATUS=0x11/CFG_ERROR=0`、ACTIVE 扩展首字 `0x2` 仍是彩色，SHADOW `0x202` 为 HDR。用户态可见 epoch 留在 20（首轮 18）；序号相同不代表已发布。SDK 的通用超时文字不区分具体等待分支。

| 字段 | 首轮 | 第二轮 |
|---|---|---|
| RUN 有效等待样本 | seq629–638，其中 629 仍写表 | seq456–465，已写表 |
| DFI / PIX target / PIX applied | 19 / 19 / 18 | 21 / 21 / 20 |
| 写表结束后的 PIX/CFG、SYS CAM0/CAM1 | `0373/C7EA`、`078A78E4/008A6844` | 完全相同 |
| 两眼 PHY_READY / config_done | seq630 起 1/1 | seq456 起 1/1 |
| capture_admit / DFI jobs（等待期常量） | `9868/9868/0/0`、`9850/9846` | `3424/3420/889/889`、`3275/3227` |
| DFI banks、OB USER 等待期 | 全 FREE、`WAIT_RECORD` 且 buffer armed | 相同 |
| 首次采到 RUN=0、CFG flags | seq639、`F7EA` | seq466、`F7EA` |

两轮写表后均为 `WAIT_FRAME`，remote pending/sent/applied、source ready、frame eligible、response space 为 1，remote fault、response active、采样时 frame accept 为 0。CAM0 index138/phase7/warmup7/written/stable/pair_ok，CAM1 index138/phase6/warmup0/written、stable=0、pair_ok=0；两眼 clock lock 正常且未采到 source/I²C fault。RUN 时 cfg pipeline/physical source 不 quiet，maintenance/native pipeline quiet；STOP 后四项 quiet 变为 1，applied 没有推进。第二轮 456–465 的 DJ 除序号外相同，466–716 的 251 条 STOP 后 DJ 也保持。第二轮 PIX 接收/身份粘滞位在此次故障前就已置位，无法把它归给本次 CAM1；坏 FINISH `20/19→21/20` 只在 455→456 的切换采样间隔增加，随后保持，不能归到新 epoch 的某一帧。

这与 [492c5384 本地已复现并修复的孤立 SHORT 等待缺陷](../seed12fix_20261109/README.md) 相容：同一旧 bit 多次进入 HDR 成功后仍会遇到该类启动状态。现场没有逐成员 CSI/FIFO 队首或短脉冲追踪，无法证明第 21 笔真实阻塞成员一定是 group 0 SHORT。492c5384 的独立短测证据有效范围见原记录；这两轮都未使用该候选，新综合、P&R、STA、bitgen、板级均 `NOT_RUN`。本次只审计现有证据。两轮直接 HDR→去雾和两段独立五分钟 HDR 验收均未完成。
