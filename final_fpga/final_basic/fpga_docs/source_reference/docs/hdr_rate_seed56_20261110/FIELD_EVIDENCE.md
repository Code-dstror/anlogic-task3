# seed56 双目 HDR 现场证据复算

同一 RUN 的 540 秒稳定 HDR 窗中，两眼 LONG 和 SHORT 的实际准入各为 30.306 次/秒，DFI 接作业已分成 30.306 和 20.204 次/秒。像素处理准入、JPEG result、writer ACK、READY claim、USER 描述符和退休的总量都为 27,275。RK 完整产品接收、解码和选中新 SOURCE 沿用约 30/20 的分布。此前版本的慢眼交换在本版复现，换慢眼和约 25/25 时总 job 率仍约 50.5/s。

## 原件及运行身份

- 现场包清单所列 50 个文件逐一重算 SHA256，目录无额外文件（清单自身除外）。启动子索引的 31 个原件逐一匹配字节数和 SHA256。现场包 `PACKAGE_INFO.json` 所指的来源 ZIP 只有归档摘要回执，交付根目录无对应 ZIP 可供复核。
- 实际交付 bit 为 `camera_raw_r2_41cb5991_seed56.bit`，4,850,315 字节，SHA256 `4030fabe8fb3c323932d501c086363d89feb20b4277ec37aae90f17e56e7be74`。目录文件、交付 ZIP 内字节、版本 manifest、下载回执、枚举引用和公开状态一致。实际交付 ZIP 的 SHA256 为 `6a5e4850933c67edb0b5fdb257a307dcae7fc435d62fae2cc891cfdead3538f3`，与该 ZIP 的旁车及下载回执一致。源码 Git 身份为 `41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213`。板内身份采用操作者冷启及下载文件确认，SRAM 独立读回为未采集。
- 启动与 RK 采样回执一致。Boot `5e95ef3c-aa39-4686-82d8-bd90c9e15052`，PID 2697，run `95e742a8d92f6531784c96d9ba827c4a`，BDF `0000:21:00.0`，节点 `/dev/ph1a_c2h_0000:21:00.0`。使用双目 JPEG/Q75/strict SOURCE，单 owner 同 fd，原 HDR ratio4、black 50/50、motion 64/3、qualification 15、delta 50 ms、wait 100 ms、age 1 s。runtime 索引 `fb5e6e8a3d44d86ccac6c87fb4bec8512534f45ea3668a84c3fd84d04f4a7038` 和四个运行库的回执哈希与 seed12 相同。control 索引为本轮 `7aef5bd05961561c8cecf59fe6012c0a429b92d5ae5a8dc4074397f1e88f6b20`。运行驱动的 build ID 与经核验的 stereo-n2 文件回执相符。这些是现场运行身份记录，交付包没有运行库、已加载内存和独立 lease 时延 trace。
- 以交付的官方 decoder（SHA256 `926a896f94f1bbd55077e23cb37aedd1f2a86634b570efba8c748b4cb9257b22`）按 6,841 个原读取块边界重播 128,712 字节。读取覆盖连续，逐行解码与现场 JSONL 匹配。共 2,653 帧，DJ/v3 1,327、OB/v2 1,326，CRC/非法头/尾残片各 0，丢弃 22 字节。CG、RX、RT 均为 0。原件为在线采集快照。
- owner 原始事件逐笔匹配 37 笔 MODE_REQUEST/APPLIED/VIDEO_CONFIRMED，请求先于 APPLIED，APPLIED 先于新画面确认。另有 2 笔布局请求、1 次 START、0 次 STOP。HDR 已确认 epoch 为 5/13/15/17/27/29/31/33/35/37，用户反馈此轮动态且无卡住。首对 HDR AJPG 原件来自 epoch5。结论覆盖这次已观察的切换序列。FDT 现场比对回执记载差异在未使用尾部 padding，原始 FDT 文件未收入现场包。

## epoch37 同轮对账

使用 DJ seq837–1377，首尾采集主机单调时间差 540.000454644 秒（主机记录约北京时间 12:13:01–12:22:01）。541 个连续 DJ 全部 fresh/reset=3、DFI RUN、双目 JPEG HDR、DFI epoch=PIX target=PIX cfg_applied=37、CFG IDLE、两眼 SYS stable。OB 取相同报告号，541 个连续 OB 的 PIX/DFI/USER 页全部 fresh 且出复位，OB 首尾差 540.000372221 秒。DFI/PIX/SYS/USER 各自冻结，OB/DJ UART 读到的先后与时差仅为采集主机时刻。

| DJ 事件或身份 | CAM0 首→尾 / 增量 | CAM1 首→尾 / 增量 | CAM0 / CAM1 每秒 |
|---|---|---|---:|
| LONG `capture_admit`，16 位 | 5607→21972 / 16365 | 2453→18818 / 16365 | 30.306 / 30.306 |
| SHORT `capture_admit`，16 位 | 5598→21963 / 16365 | 2453→18818 / 16365 | 30.306 / 30.306 |
| 真实 DFI job TAKE，16 位 | 5054→21419 / 16365 | 5251→16161 / 10910 | 30.306 / 20.204 |
| 最后一次真实 TAKE 的 SOURCE，32 位 | 18→16383 / 跨度 16365 | 17→16382 / 跨度 16365 | 序号范围 |
| `begin_reject`，8 位 | 242→242 / 0 | 108→10 / 10910 | 0 / 20.204 |
| `pair_expire`，8 位 | 0→0 / 0 | 0→0 / 0 | 0 / 0 |
| `bad_finish`，8 位 | 38→38 / 0 | 35→35 / 0 | 0 / 0 |

累计逐相邻样本差分 `(b−a) mod 2^width`，仅对连续有效页解模。慢眼 `begin_reject` 有 43 次实读数值回落，540 段的增量为 20（477 段）、21（16 段）、22（47 段）。每段间隔约一秒，以这条计数的实际输入事件量可排除整圈藏在相邻样本内。慢眼 SOURCE 序号跨度多于真实 TAKE 5,455，准入与 TAKE 的差也是 5,455。10,910 个聚合 BEGIN 负答复与每个缺口两次负答复相容，逐眼 L/S 拒收身份及原因在本页不可见。epoch17 的首条已发布快照仍显示旧的 `last_source=79/79`，下一条为 `38/40`，故该短窗保留原始身份跳变，省略整窗 SOURCE 跨度。

| OB 聚合事件，均 16 位 | 首→尾 | 增量 | 每秒 |
|---|---:|---:|---:|
| PIX `frame_admission`（处理端 `admission_take`） | 10305→37580 | 27275 | 50.509 |
| PIX JPEG result 握手 | 10304→37579 | 27275 | 50.509 |
| DFI writer ACK 握手 | 10304→37579 | 27275 | 50.509 |
| DFI store READY claim | 10286→37561 | 27275 | 50.509 |
| USER native descriptor accept | 10287→37562 | 27275 | 50.509 |
| USER JPEG retire 握手 | 10286→37561 | 27275 | 50.509 |

OB 六项没有逐眼拆分。540 个相邻区间的 job 总量及六项 OB 各为 50 或 51，209 个区间七项增量完全一致，其余每项相差至多 1。长窗对账支持已接作业能持续走完下游。JPEG result 和 writer ACK 包括相应负结果的握手，USER 退休及 RK 合法产品是独立的末端观测。PIX/DFI/USER sticky 值分别始终为 14/12/0，前两者保留先前故障位。相同 sticky 值无法计数重复的同类错误。

| RK epoch37，两眼同屏 | CAM0 增量 / FPS | CAM1 增量 / FPS |
|---|---:|---:|
| 160.000089476 秒，完整合法产品接收 | 4844 / 30.275 | 3228 / 20.175 |
| 同窗登记、解码各项 | 4842 / 30.262 | 3229 / 20.181 |
| 同窗合成器选中新 SOURCE | 4793 / 29.956 | 3229 / 20.181 |
| 429.276553948 秒，429 条原始预览样本，登记、解码各项 | 13009 / 30.304 | 8673 / 20.204 |
| 同预览长窗合成器选中新 SOURCE | 12877 / 29.997 | 8674 / 20.206 |

RK 160 秒以同 session、epoch 的完整产品 SOURCE 为参照，首尾 `8199/8198 → 13043/13040`。最近的 DJ seq1107–1267 为 `8201/8198 → 13050/13048`，160.001717849 秒内 job +4849/+3233（30.306/20.206）。这组 SOURCE 邻近窗口支持同一业务阶段速率对应，首尾身份差及独立单调时钟限制了逐帧守恒判断。合成器数据测量实际选图的新 SOURCE，HDMI 物理扫描未测。

RK 九次采样的解码 backlog 八次 [0,0]、一次 [1,0]，预览丢弃计数仅 +1/+0。进程平均 328.42%（一核=100%），最高单线程 31.55%，owner 线程 14.16%，调度等待约 0.93%，8 核整体忙碌 42.50%。录像均 RECORDING，native error 和 queued 为 0，封段 143→193，保留独立 retention.last_error。完整接收已经只有 20.175 FPS 的眼进入解码后仍约 20.181 FPS，持续解码或缩放丢 10 FPS 的解释与本窗不符。短时 PCIe/lease/DDR 反馈仍缺逐次证据。

## 共享服务和 bank 采样

| OB DFI 同域 levels | 样本 | 同报告号的 DJ bank | 同轮 OB USER phase |
|---|---:|---|---|
| scheduler busy=0，credit reserved=1，owner empty=0，writer quiescent=1 | 83 | 两眼均 FREE+BUILD。四 bank 组合 0101 ×40、1001 ×43 | WAIT_RECORD/armed 53，RESULT/unarmed 30 |
| scheduler busy=1，credit reserved=0，owner empty=0，writer quiescent=0 | 458 | 详见 JSON 的 18 种组合 | WAIT_RECORD/armed 355，RESULT 96，RUN 6，IDLE 1 |

DJ bank 编码按 CAM0 bank0/1、CAM1 bank0/1，0 FREE、1 BUILD、2 READY、3 OWNED。快眼含 READY 8/541，慢眼 186/541。快眼为 FREE+BUILD 或 BUILD+OWNED 共 531/541，慢眼的状态分布更广。慢眼换成 CAM0 的 epoch27/29/31 共 36 个样本里，快眼 CAM1 也全部为这两种组合。DJ 读到比同号 OB 晚 3.482–7.640 ms，实际冻结时差未知。1 Hz 采样存在和传感器周期的相位混叠。这些是同轮关联，可证明反复观测到空档和已保留 credit，无法换算每帧服务时长、真实忙碌占空比或 BEGIN 拒绝当拍的 bank 原因。OB 的 `store_ready_valid` 是输出存储层信号，HDR bank READY 见 DJ。

本版 DJ/v3 的 DFI 只有四个 bank 状态、事件计数、`read_quiet`/owner empty 等标志（`read_quiet=1` 采到 88/541）。旧 DJ/v1 的 scheduler/ticket state 和 wait gates 已被替换，当前记录无 HDR 调度器、ticket 或 reader 的细分状态。USER 的 WAIT_RECORD/RESULT 等状态仅属于传输层。

## 重入、SDR 对照及 seed12 增量

- epoch37 九个相邻 60 秒块的 job 总率 50.499–50.517/s，每块慢眼 1,212 或 1,213 个作业。相邻约 1 秒区间分眼增量只出现 30/20、30/21 和 31/20。长窗的分配为每三次输入节奏约 3+2 个 job，帧级丢弃周期仍需事件 trace。
- 其他稳定 HDR 窗复算得到 epoch5/13/33/35 的 CAM1 慢，epoch15/27/29/31 的 CAM0 慢。epoch17 约 22 秒为 25.228/25.273/s，BEGIN 分别 +222/+222，总率仍 50.501/s。持续约 6 秒及以上的 HDR 窗总率约 50.44–50.68/s，极短窗受边界计数影响更大。
- 同一 owner/BDF/双目 JPEG 的 SDR color epoch22，DJ seq747–761 的 14.000397 秒内 jobs +420/+421（29.999/30.071/s），同号 OB 退休 +840（59.998/s），USER 15/15 为 WAIT_RECORD。RK 同 epoch 两眼同屏子窗 6.018 秒，登记和解码均 30.075/30.075 FPS，新 SOURCE 为 30.075/29.909 FPS。由此可知该会话的通用下游曾处理约 60 个产品/秒。HDR 专属工作量和短时反馈需要单独验证。
- seed12 的两轮中，成功 HDR 的 UART 窗仅 3–8 秒、RK 约 2–8 秒。旧原始解码也有约 25/25、30/20 和反转的 20/30，慢眼 BEGIN 增长、两眼 expire/bad_finish 零增量、USER retire 与总 job 差不超过 1。新增长时间对账、同报告号 credit/bank 关联、RK CPU/解码/合成对照及本次 37 笔成功切换。seed56 包含孤立 SHORT 启动修复和读 chunk 155→160 优化，当前现场仍未达双眼各 30 FPS。

## 可反驳的定位假设

稳定的约 50.5/s 总率随 HDR 共享作业保持，分配随重入相位改变。工作假设是可发 job 的形成与共享服务周期、有限 bank 生命周期发生耦合，使部分 BEGIN 得到负答复。由 READY 状态可见性和 credit 样本可进一步区分两类情况。若真有 READY job 且 credit 可用但持续未 TAKE，验证派发或 owner 释放条件。若该空档期间缺 READY，则验证 bank 归还、两曝光写入、配对和 BEGIN 负答复先后。满幅双眼输入持续约 60.61 对/秒时，按同一个 DFI 时间基准记录 BEGIN 资格与结果、bank 状态变更、READY、job TAKE、读/合成终态和 slot/credit，核对造成缺口的逐次因果。用 USER 退休及 RK 完整产品对账可区分真实服务不足和下游反馈。当前记录不具备这些逐拍状态。

## 复现

离线运行本目录的 `analyze_field.py`，使用 Python 3.12 的标准库和交付只读 decoder。输入为 `deliverables` 的 seed56 现场包、seed56 Linux 调试包和 seed12 两轮对照原件。输出 `FIELD_EVIDENCE.json` 含计数端点、相邻增量分布、bank 关联、近邻 SOURCE 对照和短窗结果。读取和离线复算通过，仿真、综合、P&R、时序和新板级操作均为本次 NOT_RUN。
