# seed12 首次彩色切 HDR 现场证据

## 固定身份与原件

2026-11-09 共同冷启的双目 JPEG 会话使用 `camera_raw_r2` 源码 `4a08ae35391e7b7ea6767260d7d1b4b182ef4bb9`、物理 seed12。交付 bit 实测 4,850,315 字节，SHA256 `ee344e8084e2485c76ba523ccbc224a04c4b2d8fe6f6c14ba734937327f32727`，与交付清单、现场请求、会话和下载回执一致。板上身份依据操作者冷启及下载回执，独立 SRAM 读回为 `NOT_RUN`。RK boot `01ba5cef-7a61-4ff2-80a6-04ca62ce77f1`，run `6dc44ae8d56935b54b89adf15107e53a`，owner PID 2470，BDF `0000:21:00.0`。 [交付清单](../../../../deliverables/CAMERA_RAW_R2_4a08ae35_seed12_Linux_Debug_20261109/MANIFEST.json) · [现场下载回执](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/programming-original.json)

原包 `SHA256SUMS.txt` 的 122 条哈希全部匹配。故障索引的 32 份原件和进展索引的 9 份原件另外核对了字节数，owner.log 的保全范围是 TAIL。按 3,991 条读取偏移复组 75,847 字节 UART 原件，独立核算每包 CRC、线上原始字段与读块归属，全部与保留解码行一致。有效包为 781 条 OB/v2 和 782 条 DJ/v3，CRC 错误、无效头和尾残片均为 0，前缀等丢弃字节共 22。CG、RX、RT 均为 0，SYS 只有 DJ 中的两眼各 32 bit 配置快照。 [故障报告及原件](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/) · [机器可读证据](EVIDENCE.json)

## RK 请求与 CSR

较早的“两条路径均正常”已被用户明确更正为“尚未实际切换，现在开始”。实际 owner 事件和 CSV 逐笔相符。请求 1–18 是 HE→去雾→彩色六轮，均取得 `MODE_APPLIED` 与 `MODE_VIDEO_CONFIRMED`，APPLIED 耗时 36.084–80.895 ms。请求 19 是此会话的第一次彩色→HDR，用户最终确认“彩色切HDR失败”。HDR→去雾→HDR、两段独立五分钟 HDR 窗口、HDR 帧率与画质均为 `NOT_RUN`。 [逐笔结果](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/MODE_REQUEST_RESULTS.csv) · [更正](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/user-feedback-correction.json) · [失败反馈](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/user-color-to-HDR-failure.json)

| RK owner 事件 | 同一单调时钟 ns |
|---|---:|
| 请求 18 彩色 | 638793463705 |
| 彩色 APPLIED，epoch 18、CAM0 首实际序号 6964 | 638852478177 |
| 彩色新画面确认 | 638961472659 |
| 请求 19 HDR | 738441189832 |
| 原保护流程 STOP_CALL | 748447128223 |
| STOP_RETURN | 748447365086 |
| 停止后两次 CSR 快照 | 849648608681、849669140387 |

请求 19 至 STOP_CALL 为 10.005938391 s，STOP 耗时 0.236863 ms。请求 19 的 APPLIED 和新画面确认字段均为空，owner 留下 `RuntimeError: TimeoutError: CFG transaction timeout; pending hardware state retained`。网页的 `CANCELLED_BY_STOP` 是停止后的请求状态，FPGA CANCEL 是否送达未知。最终 owner 为 `FAULTED_RETAINED`，host transport 已排空，held、leased、quarantined 均为 0，`global_quiet_proven/native_closed/safe_reopen` 均为 false。95 段录像共 9,889 帧均封存，视频保留在原 SD。 [RK owner 事件](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/fault-verified-files/capture/owner-events.jsonl) · [owner 收尾原件](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/fault-verified-files/capture/result.json) · [网页末状态](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/host-color-to-HDR-fault-state.json)

停止后同 boot、同 BDF，通过 `O_RDONLY/PROT_READ` 对齐 u32 读取得两次间隔 20.531706 ms 的快照，90 项逐值相同。CSR 给出 `CFG_STATUS=0x11`（BUSY、SESSION_READY）、`CFG_ERROR=0`、`REQ/RESP=19/19`、`session=1`、公开 `mode_epoch=18`、`ACTIVE_EXT_0=0x00000002`（彩色 SDR）、`SHADOW_0=0x00000202`（目标 HDR）。REQ/RESP 编号匹配时 APPLIED 仍保留在 epoch 18。CSR 助手的 MMIO 写入、native ioctl、START 调用数均为 0，第二个接收 fd 未打开。 [CSR 原件](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/fault-verified-files/diagnostic-cfg-readonly/result.json)

## UART 逐样本

到达时间为采集机北京时间，表中取 DJ 末字节读块时间并截到毫秒。OB 同序号也各有独立的读块时间。DFI、PIX、USER 独立快照，SYS 在 UART FREEZE 沿覆盖，序号仅用于匹配观察轮次。RK 单调时间用于计算 RK 事件间隔。以下 DJ 的 fresh/reset_n mask 均为 3，OB 均为 7。 [UART 原件](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/fpga-startup-window/) · [DJ/v3 字段](../fieldfix_20261109/UART_FIELD_V3.md) · [继承的 DJ/v2 字段](../fieldfix_20261108/UART_FIELD_V2.md)

| DJ/OB seq | DJ 到达时间 | 状态 | PIX capture_admit | DFI jobs CAM0/CAM1 | OB USER descriptor/retire |
|---:|---|---|---|---|---|
| 625 | 21:43:43.994 | A | 9750/9750/0/0 | 9731/9728 | 19453/19452 |
| 626 | 21:43:44.995 | A | 9780/9780/0/0 | 9761/9758 | 19513/19512 |
| 627 | 21:43:45.994 | A | 9810/9810/0/0 | 9791/9788 | 19573/19572 |
| 628 | 21:43:46.994 | A | 9840/9840/0/0 | 9821/9818 | 19633/19632 |
| 629 | 21:43:47.995 | B | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 630 | 21:43:48.994 | C | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 631 | 21:43:49.994 | C | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 632 | 21:43:50.995 | C | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 633 | 21:43:51.994 | C | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 634 | 21:43:52.995 | C | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 635 | 21:43:53.995 | C | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 636 | 21:43:54.994 | C | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 637 | 21:43:55.995 | C | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 638 | 21:43:56.994 | C | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 639 | 21:43:57.995 | D | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 640 | 21:43:58.995 | D | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 641 | 21:43:59.994 | D | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 642 | 21:44:00.995 | D | 9868/9868/0/0 | 9850/9846 | 19689/19688 |
| 836（末样本） | 21:47:14.994 | D | 9868/9868/0/0 | 9850/9846 | 19689/19688 |

| 状态 | RUN / DFI epoch / PIX target / PIX applied / CFG state | PIX flags / CFG flags | 两眼 SYS raw（CAM0/CAM1） | OB PIX levels / sticky / PHY_READY（CAM0/CAM1） |
|---|---|---|---|---|
| A | 1 / 18 / 18 / 18 / IDLE(0) | `0332 / 406A` | `00CA7864 / 00CA7864` | `016F / C / 1,1` |
| B | 1 / 19 / 19 / 18 / WAIT_FRAME(3) | `0033 / F7EA` | `00394800 / 00394800` | `0703 / E / 0,0` |
| C | 1 / 19 / 19 / 18 / WAIT_FRAME(3) | `0373 / C7EA` | `078A78E4 / 008A6844` | `076F / E / 1,1` |
| D | 0 / 19 / 19 / 18 / WAIT_FRAME(3) | `0373 / F7EA` | `078A78E4 / 008A6844` | `076F / E / 1,1` |

| SYS raw | warmup | index | phase | written | stable | pair_event | pair_ok |
|---|---:|---:|---:|---:|---:|---:|---:|
| `0x00CA7864` | 0 | 202 | 7 | 1 | 1 | 0 | 0 |
| `0x00394800` | 0 | 57 | 4 | 0 | 0 | 0 | 0 |
| `0x078A78E4` | 7 | 138 | 7 | 1 | 1 | 0 | 1 |
| `0x008A6844` | 0 | 138 | 6 | 1 | 0 | 0 | 0 |

这些 SYS 快照的两眼 `clock_locked=1`，`abort/source_fault/error/i2c_error=0`。seq629 两眼 `config_done` 与 `PHY_READY` 同时采到 0，seq630 起两者均恢复 1。DJ 的两眼当前 `identity_fault/receive_fault` 四位在整个窗口均为 0。OB PIX 的聚合粘滞 `camera_receive_or_identity` 从首个有效 PIX 样本 seq160 到 seq628 都为 0，在 seq629 首次置 1，并保持到串口采集结束。OB 粘滞 `0xC→0xE` 新增的 bit1 只记录接收或身份类事件，归属哪一眼、具体类别和发生周期未知。seq630 起 CAM1 已写完配方并采到 PHY_READY，但 `warmup=0/phase=6/pair_ok=0`，CAM0 已到 `warmup=7/phase=7/pair_ok=1/stable=1`。 [OB/DJ 解码原件](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/fpga-startup-window/decoded.jsonl)

seq629–638 的 `remote_pending/sent/applied/source_ready/frame_apply_eligible/response_space=1`，`remote_fault/response_active/frame_accept=0`。seq629 的四类 quiet 均为 1。seq630–638 的 `cfg_pipeline/physical_source=0`，`maintenance/native_pipeline=1`。seq639 首次采到 RUN=0，四类 quiet 都回到 1，CFG state、PIX applied、两眼 SYS 和计数仍保留。seq639–836 的 198 条 DJ 除序号外逐项相同。 [OB/DJ 解码原件](../../../../deliverables/CAMERA_RAW_R2_seed12_本轮切换试验与故障证据_20261109/CAMERA_RAW_R2_seed12_试验与故障证据/fpga-startup-window/decoded.jsonl)

进入目标 epoch 后四路 `capture_admit` 无可见增量。该计数随 RUN 上升清零，切模式保留旧 SDR 余数，SDR 的 CAM0/CAM1 占前两槽，HDR 的顺序是 CAM0 L/S、CAM1 L/S。DFI 的最近 SOURCE `9953/9952`、BEGIN reject `0/0`、pair expire `0/0`、bad FINISH `18/18` 和四个 FREE bank 从 seq629 起均保持，`18/18` 在切换前就存在。OB `frame_admission/jpeg_result_handshake` 从 `19639/19639` 到 `19696/19696` 后也保持，USER transport phase 在 RUN 期间为 WAIT_RECORD，STOP 后为 IDLE，PCIe link 与 supervisor ready 采样始终为 1。 [逐样本字段与计数](EVIDENCE.json)

## 已证实的边界

- HDR 目标到达 PIX 和 DFI，采到了完整远端 ACK。故障在等待新配置的实际采集边界期间表现为 WAIT_FRAME、PIX applied 保持 18、公开 ACTIVE 保持彩色。两眼采集不对称与接收或身份聚合事件是同一故障窗口的实测线索。
- 约 1 Hz 的取样及无逐 pair 页的原件，无法区分短暂坏 pair、瞬时资格变化和完全无 pair，也无法证明 `frame_accept` 从未有过短脉冲。短计数是模计数。具体是哪个 RTL 或物理条件阻止了合法首帧，需独立验证。
- SDK 缺逐笔 READY/COMMIT 调用轨迹。CSR 是停止后现场，RUN 时的 gate 只用 seq629–638 说明。本审计属于历史原件校验，当前候选的功能仿真、综合、P&R、时序和板级结果均由各自独立证据记录。
