# CAMERA_RAW R2 seed20 去雾切换现场证据

历史现场日期为 2026-11-09。两个独立冷启动都将合法的双目 SDR 去雾请求送达 CFG shadow，并在约 10 秒后由 SDK 等待超时触发保护 STOP。HDR 轮在旧 epoch 的停收阶段失去进展。HE 轮已在 DFI/PIX 使用新 epoch，并有一份新 epoch 的 CAM1 JPEG 到达 RK，随后公开 CFG 仍停在旧 epoch。两个观察边界需要分别复现。

## 来源与身份

| 来源 | 校验结果 | 证据用途 |
|---|---:|---|
| [原 HDR 报告包](<../../../../deliverables/camera_raw_r2 · 8258220f的多轮调试记录/CAMERA_RAW_R2_seed20_HDR25FPS与切去雾超时_报告与证据_20261109>) | 72/72 SHA256 | 首轮原报告、HDR 短窗与失败现场 |
| [交 FPGA 定位含 RK 审计包](<../../../../deliverables/camera_raw_r2 · 8258220f的多轮调试记录/CAMERA_RAW_R2_seed20_交FPGA定位_含RK侧审计_20261109>) | 77/77 SHA256 | 复用原包 72 份文件，增加定位补充和 4 份 RK 审计文件。下文以 **H** 指该包的 `evidence/` |
| [两轮汇总包](<../../../../deliverables/camera_raw_r2 · 8258220f的多轮调试记录/CAMERA_RAW_R2_seed20_两轮去雾切换超时_证据汇总_20261109>) | 140/140 SHA256 | `第一轮_HDR切去雾/` 与审计包逐文件相同，包括内层校验清单。下文以 **E** 指独有的 `第二轮_HE切去雾/` |

分别按 `verified-index.json` 重算 H 的 29 项和 E 的 37 项大小与 SHA256。H/E 各有一份 `owner.log.tail`，其余为完整文件。两份 `fpga.bin` 的 SHA256 与采集收据一致，`reads.jsonl` 的字节偏移连续到文件末端。从原始字节重算 OB CRC8 和 DJ CRC16，H/E 分别有 436/416 对完整报文，CRC、包头和解码轮次均一致。两轮均 RX-only、TX0，采集器在确认故障后由 SIGTERM 结束，串口收据记载已恢复属性并关闭。UART 到达时间属于采集主机时钟，RK owner 时间属于各自的板端 monotonic 时钟。DFI、PIX、SYS、OB 状态也分别采样。

两轮的下载确认、部署回执和本地交付件均指向 `8258220fdb54d8db8d9f9fd8b77b8185f0c7546d` / seed20。重新计算本地 bit SHA256 为 `4f4c566cc95e60b44b62a52ea171c9e827baf5c13a7929b4074af2bb0983f280`，ZIP SHA256 为 `d0513cec4a925f3aa7d70eb9b7df32ab9c3504249ece6b9531abb07e4be55891`，与独立交付清单及首轮下载记录匹配。现场下载身份来自用户确认，SRAM 未独立读回。两轮使用同一 control/runtime 索引、N2、双目 JPEG Q75 strict、BDF `0000:21:00.0`，各一次 START。原 HDR 包内 `session.json` 的 `video_START_calls=0` 属于初始会话记录，完整 `owner-events.jsonl` 有唯一的 `START_CALL/RETURN`。见[选定 bit 的交付清单](../../../../deliverables/CAMERA_RAW_R2_8258220f_seed20_20261109/MANIFEST.json)、H/E 的 `programming-original.json` 和 `verified-files/capture/owner-events.jsonl`。

| 轮次 | RK boot | Owner PID | Run ID |
|---|---|---:|---|
| H | `f37964cf-64c1-41ae-a888-dfecae18a218` | 2515 | `0c5b1d322a869fcd9be264152b1f37ba` |
| E | `9c0cfb47-ff70-4ee4-b987-d1d130eab2f7` | 2450 | `02f9ef3088cff0ff0e3e0c36470f52fb` |

## 共用的 CFG 边界

H/E `cfg-csr-readonly/result.json` 各包含两次相同的 90 项顺序 CSR 读数，间隔约 20.53 ms，第一次分别在 STOP 调用后约 360.84 s、272.96 s。同一 BDF 的 resource0 用户页 `0x80000` 由 `O_RDONLY|PROT_READ` 路径采样，工具回执的 MMIO 写和 native IOCTL 都是 0。

| 字段 | H：HDR → 去雾 | E：HE → 去雾 |
|---|---:|---:|
| `cfg_session/request_session/active_session` | `1/1/1` | `1/1/1` |
| `request_sequence/response_sequence` | `3/3` | `17/17` |
| `cfg_status/cfg_error` | `0x11/0` | `0x11/0` |
| `shadow[0..31]` | `0x802` 后跟 31 个 0 | `0x802` 后跟 31 个 0 |
| 公开 `mode_epoch` / ACTIVE_EXT word0 | `2` / `0x202`，HDR | `16` / `0x2002`，HE |
| `applied_first_sequence`，旧 ACTIVE | 10 | 802 |
| `record_version/header_length` | `4/2112` | `4/2112` |

`0x11` 只置 `BUSY` 和 `SESSION_READY`。REQ/RESP 同号说明请求身份已被认领。公开的 `ACTIVE`、`mode_epoch`、`applied_first_sequence` 都保留前一笔成功提交，`APP=0` 对应事后 STOP。去雾 shadow 是 schema2、SDR COLOR、处理掩码 2、LUT generation 0，其余扩展参数为零。两轮的网页去雾命令均无 `MODE_APPLIED` 和 `VIDEO_CONFIRMED`，随后由 owner 记录 `CANCELLED_BY_STOP`。网页日志没有用户 STOP 请求，SDK 的 CFG 命令总线轨迹未采集。见 H/E 的 CSR、owner events、H `host-user-freeze-state.json`、E `host-HE-to-dehaze-state.json` 和[首轮 RK 审计](<../../../../deliverables/camera_raw_r2 · 8258220f的多轮调试记录/CAMERA_RAW_R2_seed20_交FPGA定位_含RK侧审计_20261109/rk-sdk-cfg-audit/findings.txt>)。

RK 审计显示，正常路径为 `PREPARE_EXT` → `READY|BUSY` → 同 epoch 时立即 `COMMIT` → `APPLIED` 且 `BUSY` 清零，再读回 ACTIVE。旧 epoch 异常的支路会 `CANCEL`。离线探针在固定 `0x11` 下得到三种等待相同的 10 秒异常文本，板测也只保留这一文本。仓库和发布包的双目 SDK、配置事务、schema2、协议常量四份文件 SHA256 与审计一致，仓库 `linux/dma_c2h_candidate/receiver.py` 也一致。命令和 READY/APPLIED 转移的确切瞬时状态仍需用逐阶段握手轨迹确认。见[审计的源码索引和离线探针](<../../../../deliverables/camera_raw_r2 · 8258220f的多轮调试记录/CAMERA_RAW_R2_seed20_交FPGA定位_含RK侧审计_20261109/rk-sdk-cfg-audit>)。

## H：HDR → 去雾

- RK 先确认左右同屏、灰度 epoch1、HDR epoch2。`HDR_APPLIED` 为 `600184668580` ns，`VIDEO_CONFIRMED` 为 `600297315056` ns，去雾请求为 `614292192676` ns。两眼最后一个完整产品仍为 HDR epoch2，分别在请求前 12.012 ms、后 4.064 ms 到达。`STOP_CALL` 为 `624302501448` ns，距请求 10.010308772 s，随后 STOP 返回。来源为 H 的 `owner-events.jsonl`、`capture/result.json`。
- DJ seq531 还在 epoch2/HDR/RUN，`cfg_pause=0`。seq532 首次看到 `cfg_pause=1`，边界上的 jobs 增量 `2/3`、四路 admit 各 `3`、负 FINISH `1/1`，随后直到末样本 seq899 都无新 jobs/admit，DFI/PIX 始终 `2/2`。seq532–541 RUN 仍为 true，USER phase 为 `WAIT_RECORD`，seq542 起 RUN 关闭、USER 为 `IDLE`。这给出最早采到的停收边界和其持续性。来源为 H `fpga-r2-hdr-window/decoded.jsonl`。
- seq532–899 的 OB DFI 记录 `writer_quiescent=1`、`owner_empty=1`、`scheduler_busy=0`、`credit_reserved=1`，DJ bank 四个都为 FREE。它指向旧态退场时需要核查的未退义务，具体由哪项 drain/ACK 条件卡住、是否走到 COMMIT 尚未知。双眼 SYS phase7/index138，config_done/PHY_READY 均真，采样中无新 config_error、I²C error 或 source_fault。PIX/DFI/USER sticky `14/12/0` 在早先灰度段已出现，切换边界无新增。来源同上。
- Owner 最终 `FAULTED_RETAINED`，host drain 成功、held records 0、mode I/O 不在途。驱动完成 `2597/2597`，其中 2596 份已检查记录和 1 个 SAFE 负完成。双眼各 1298 份完整产品收到、提交、解码，预览 drop `0/0`。录像 14 段/1390 帧封存，`global_quiet_proven=false`、`safe_reopen=false`。来源为 H `capture/result.json` 和 `capture/preview/recording-final.json`。

## E：HE → 去雾

- 本轮 2 笔布局、17 笔模式，前 18 笔网页请求均有视频确认。同方向的 seq4（HE epoch3）和 seq11（HE epoch10）分别在 46.526 ms、67.529 ms 获得 APPLIED，随后也有视频确认。前者双眼首个去雾产品的记录身份都是 epoch4。HDR epoch6、12 也分别成功返回彩色 epoch7、13。故障发生在 HE epoch16 有效视频之后，去雾请求为 `585584724544` ns。两眼最后经 router 接受的产品是 HE epoch16，分别在请求前 20.558 ms、12.485 ms 到达。`STOP_CALL` 为 `595620311527` ns，距请求 10.035586983 s，随后 STOP 返回。来源为 E 的 `owner-events.jsonl`、`first-dehaze-cam*.ajpg.json`、`host-HE-to-dehaze-state.json` 和 `capture/result.json`。
- UART seq531→535 的 epoch16 稳定窗内，两眼各有约 30 job/s，BEGIN 拒绝增量为 0。seq535 仍 `16/16`，seq536 首次观察到 `17/17`，`HDR=0/RUN=1/cfg_pause=0`，相邻样本之间 jobs 已增加 `9/9`。跨 epoch 样本差无法归属每个 job。seq536→545 连续 9.000065 s 内，FS 和 SDR capture admits 都增加 `270/271`，每个相邻样本按 8 位模展开的 BEGIN 拒绝也增加 `270/271`，DFI jobs 停 `5252/5286`、last_source 停 `945/945`，USER descriptor accept/retire 都停 `10525`，USER phase 为 `IDLE`，此时 SYS app enable 仍真。seq546 才观察到 RUN 关闭，末样本 seq756 仍 `17/17`。这说明进入目标 epoch 后摄像仍送帧，生产与退还链路却在有限进展后停住。见 E `fpga-startup-window/decoded.jsonl`。
- seq536–756 OB 的通用 DFI 位显示 `writer_quiescent=1`、`owner_empty=0`、`scheduler_busy=1`、`credit_reserved=0`，DJ 四个 HDR bank 字段为 0。DJ 的当前模式为 SDR，通用 OB 位标签不足以推导 HDR 遗留所有权。双眼 SYS phase7/index202，config_done/PHY_READY 均真，采样中无新 config_error、I²C error 或 source_fault。PIX/DFI/USER sticky `14/12/0` 与 seq535 相同。来源同上。
- **真实新 epoch 的线记录**保存在 E `verified-files/capture/first-camera-error.bin`。重算 SHA256 为 `1b4889e87ed27a65ff71f797aaf28a14357e065edaf76ba18e853d627b7c1b8b`，和旁车一致。DMA completion generation `10522`、`transport_result=0`，旁车 `host_ns=585668298415`，比请求晚 83.574 ms。按线上布局复核 AJPG v4/2112，`status=error=0`，CTX2 和 neutral context 同为 session1/epoch17/seq941，CAM1 physical RAW10 SINGLE，JPEG slot4/generation1761，SPV4 `frame_error=0`。`processing_mode=0x82` 表明去雾已请求，`record_flags=0` 表明该帧未使用去雾历史。记录为 2112+105166=107278 字节，JPEG marker 检查通过且精确 EOI，SOF0 与头均为 1920×1080。AJPG `payload_crc32` 字段为 0，SDK 未定义该字段的验证算法。来源为 E `first-camera-error.{bin,json}`、[线上协议](../../../../docs/pcie_protocol_v1.json)、[SDK AJPG 解析规则](../../rk_sdk/linux/stream_diag/records.py)。
- 同一旁车的 `ConfigError: resolve the faulted configuration session` 对应 SDK 在解析及物理源检查之后对 faulted session 的处理。旁车时间用于记录接收时序，异常实际抛出时点和两份 held records 的逐条身份仍缺。该原始产品证明至少一份 epoch17 记录越过了 FPGA→PCIe→RK 完成路径，且未获应用级确认。现场无 epoch17 `MODE_APPLIED` 或预览确认。见 [SDK accept()](../../rk_sdk/dual_host/camera_shared.py)、E 的 `first-camera-error.json` 和 `owner-events.jsonl`。
- Owner `FAULTED_RETAINED`，host drain 失败，held records 2，mode I/O 不在途。驱动 submitted/completed `10525/10525`，leased/quarantined `0/0`，reader records/inspected `10523/10523`。驱动 DMA 完成、应用保留记录、FPGA 槽退还属于不同边界。双眼预览 received `5243/5278`、submitted `5242/5276`、decoded `5242/5275`、drop `1/2`。录像 51 段/5374 帧封存，`global_quiet_proven=false`、`safe_reopen=false`。来源为 E 的 `capture/result.json` 和 `capture/preview/recording-final.json`。

## HDR 短窗速率与切换故障的关系

H 的稳定 DJ 窗 seq517→531 跨 13.999778 s，四路 capture admits 各 `424`（30.286/s），两眼 jobs `354/353`（25.286/25.215/s），BEGIN 负答复 `140/142`（10.000/10.143/s），pair expiry 和 bad finish 的窗内增量为 `0/0`。HDR 窗的 PIX FS 字段保持不变，四路 SOF 准入和有效 job 才是该窗活动的直接观测。RK preview 第 34→47 行跨 13.047388 s，双眼提交与解码各 `330`（25.292 FPS），各眼可见新 SOURCE `329`（25.216 FPS），HUD 公共输出 `391`（29.968 FPS）。短窗已经把下降定位在 DFI job 和 RK 完整输入层，尚不能将 BEGIN 聚合拒绝归给逐帧原因、特定 bank/credit 状态或排除跨端反压。实际 HDR 新视频到去雾请求仅 13.995 s，两次计划的 5 分钟窗均未完成。来源为 H `fpga-r2-hdr-window/decoded.jsonl` 和 `capture/preview/camera-preview.jsonl`。

E 的两段 HDR 短窗还出现方向相反的眼间差。epoch6 DJ seq449→457 约 8.000 s，四路准入各 236、jobs `235/157`、BEGIN 负答复 `0/156`。epoch12 DJ seq492→503 约 11.001 s，四路准入各 316、jobs `210/315`、BEGIN 负答复 `210/0`。RK 双眼已解码 HDR 窗也分别增加 `212/142`、`203/304`，两段都成功退出至彩色。最终 HE 在去雾请求前仍有正常 job。现有记录支持将 HDR 持续速率与去雾配置活性分别验收，既往模式和负载历史对触发相位的影响仍未知。来源为 E `fpga-startup-window/decoded.jsonl`、`capture/preview/camera-preview.jsonl`、`owner-events.jsonl`。

## 最小可观察复现

1. **HDR 退场。** 在双目 JPEG 正常入口先完成合法 HDR CFG 并得到双眼有效产品。取一笔旧 HDR 帧、DDR 产品或 C2H 传输仍在途的边界，通过公开接口引入有限反压并自然释放，发合法 SDR 去雾 PREPARE。分别检查旧承诺排空、匹配 READY、COMMIT 后首笔匹配去雾帧及 APPLIED。设置空载对照和有界看门狗，用相同刺激记录旧版是否出现旧 epoch 持续 BUSY、输入停收且无终态。
2. **HE 提交。** 先通过真实路径完成 HE，并验证至少一次 HE→去雾→HE 的合法连续事务。然后让新 epoch 的首个合法物理帧到达时系统存在有限旧工作或首帧边界上的竞争。以公开 CFG BAR 检查 READY/COMMIT/APPLIED 的序号、epoch 和完整 ACTIVE，并对照真实 DMA 完成的首个去雾 AJPG4。如果接收模型覆盖 SDK pending，复制少量记录等待 APPLIED 并独立处理 DMA lease 退还。旧版可观察反例是目标 epoch AJPG 已完成，公开 BUSY 和旧 ACTIVE 仍不退。收到 APPLIED 后两眼各需有匹配新 epoch 的合法产品，随后以一笔合法模式事务或受控 STOP 验证可继续运行或排空。
3. **判定口径。** 依赖公开有效握手及 `{session, request_sequence, epoch, camera, source_sequence, generation}`，覆盖持续旧工作和有限反压释放后的首笔合格事务。保留双时钟或多时钟关系和实际流水上下游。去雾请求位和实际历史生效位分别检查。UART 模式、最后一包、SDK 超时、单次叶级 PASS 各自只覆盖其观察边界。小几何只用于切换活性，速率验收需另用等窗的真实 SOURCE/产品/退休对账。见[流接口独立黑盒规则](../../../../.agents/skills/rtl-stream-contract/references/blackbox-validation.md)。

本文件为封存证据的只读复核。功能仿真、综合、P&R、时序与板级对本次复核均为 `NOT_RUN`。
