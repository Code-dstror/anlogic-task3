# PIX 配对与 JPEG CDC 独立黑盒短测

ModelSim SE-64 2020.4 和 TD 2026.2.210.850 模型。台架根据公开接口合同编写，RTL 和模型作为不透明编译输入。PIX 使用外部 64 相位和少量 RAW4，JPEG 使用实际 FIFO、fence、扩展 ERAM 和生产配置。每例单独启动 ModelSim，墙钟上限 60 秒。仿真 watchdog 为 PIX 10 µs、JPEG 50 µs。

## PIX 仿真 9/9 PASS

| 场景 | 公开终态 |
|---|---|
| `first_overlap` | 首组分别锁存两路 FS 时间戳，连续 RAW4、错相 FE、双 SOURCE 及正配对。旧 SHORT FE 与新 LONG FS 同沿，旧 SHORT SOURCE 在新 LONG RAW 期间保持。 |
| `stop_wrap` | STOP 在 FE/FS 采样沿生效。跳过组晚到 SHORT 排空。无合格时间的完整物理组为负，随后组号从 `ffffffff` 回卷到 `1`、`2` 并完成正终态。 |
| `peer_faults` | 两个方向的首 RAW 与对端 BAD、LONG 重入 offer 与 SHORT BAD。重入旧组双 error 5。低 stable 的热身组完成物理 FE，随后恢复组完成正 SOURCE 和配对。 |
| `cohort` | cohort 切换时旧 SHORT 保留旧身份并报 error 9，新 LONG 同沿起始，新组完成双 SOURCE。 |
| `stopped_reset` | 停钟复位撤销已发布的旧 LONG SOURCE 和活动 SHORT。复位释放后的首个 FS 采样沿进入，回卷组完成。 |
| `deadline`、`terminal_priority` | 64 相位超时，FE 与 BAD 同沿为 error 8，截止沿双 FE 或 FE 与 BAD 均为 error 11。健康后继组完成。 |
| `old_short_fault` | 旧 SHORT BAD 时已发布 LONG 成功终态保持，随后复验老组错误与新组 LONG RAW 同沿，新组双 SOURCE 和配对为正。 |
| `dual_cancel` | fault、旧 SHORT 重入 offer 和新 LONG FE 同沿。两旧上下文各报 error 9，负事件一次、坏组计数加二，健康后继组完成。 |

受测 `real_hdr_pair_cycle_gate.v` SHA256 为 `68e0b67235a1d0b765e31f4adc48a3765980a627ce84f69f529d523b460c2b59`。计分终点为两路 SOURCE 真正握手、物理配对事件与 quiet。RAW 入口使用立即可接收的消费模型。

## JPEG CDC 仿真 14/14 PASS

- 两个连续合法帧跨 sequence `ffffffff → 0`，不同眼、session、epoch、tag。每帧核对 37 个有效字节、短尾 KEEP/LAST、128 个 EXT 流握手、完整 410 个 RAM 字、扩展租约复读及 RESULT。第二帧核对 drain fence。START、LAST、EXT、RESULT 均施加反压。
- 停源切点为 CONTEXT 准备完成而 START 尚未握手、目的 START 持有、部分 DATA、源 EXT flit 0/64/127 已呈现但未握手、FENCE 对应目的 RESULT 持有。START 和 FENCE 例同时停目的钟。每例复位后用不同身份和内容完成新合法帧。
- 负 RESULT 无 LAST，核对 32 个有效字节及透传错误码。错误 ID、LENGTH、epoch/quality 分别验证 E1、E2、E4，随后合法帧继续通过。
- 坏 prefix flit1 在源端报 fault。允许 stream_start 准备请求，实际呈现并保持 flit0，八个源边沿内流和源 RESULT 握手数为零。合法 prefix 加坏 stream flit7 在送完 128 拍后由目的端锁存 shape fault。本帧目的 EXT/RESULT 握手数为零，两例均协调复位并完成新帧。

受测 `ordered_frame_ingress.v` SHA256 为 `8d8b0336b84c3c98118585c4e7f3e43b6fe77e0c99fcfb4f118fbe683df305b1`。扩展按公开 v2/v4 字节布局生成，独立计算 RAM 的小端 40 位字及末字补零。JPEG 数据为短字节流。

## 复现与日志

```powershell
$pythonExe = 'python'
$testRunner = 'refactor/camera_raw_r2/src_fpga/simulation/blackbox_pix_jpeg_20261109/run_blackbox.py'
& $pythonExe $testRunner pix --modelsim-bin 'D:/App/modelsim/win64' --td-root 'D:/App/TD_Release_2026.2.210.850'
& $pythonExe $testRunner jpeg --modelsim-bin 'D:/App/modelsim/win64' --td-root 'D:/App/TD_Release_2026.2.210.850'
```

可用重复的 `--case` 选项选定短例。日志位于 `work/exp/blackbox_pix_jpeg_20261109/`。每次运行分别保留输入 SHA、工具版本、各进程命令与墙钟、原始输出和结果索引。

| 运行目录 | 保留结果 |
|---|---|
| `20261109T013012Z_pix_44501e` | 首轮 3 项通过。原 FAIL 对应 invalid-time 后 READY 假设、重入 offer 等同握手、cohort 失败后的等待拍遗漏。 |
| `20261109T014319Z_pix_5e4587` | 8 项通过。重入取消本身通过，恢复前漏排空热身物理组，原 FAIL 保留。 |
| `20261109T014550Z_pix_f783d5` | 补齐热身组两路 FE，公开 quiet 清账后 `peer_faults` 通过。 |
| `20261109T013955Z_jpeg_75eb22` | 11 项主场景通过。另两项原 FAIL 将坏 prefix 的源早拒误当作目的 shape 校验。 |
| `20261109T014321Z_jpeg_769fb0` | 合法 prefix + 坏 stream flit7 通过。坏 prefix 复合断言的原 FAIL 保留。 |
| `20261109T014552Z_jpeg_d5ed31` | 原 FAIL 将 stream_start 准备请求当作实际 flit 接收，已记录源 fault 和零握手。 |
| `20261109T014707Z_jpeg_817525`、`20261109T014745Z_jpeg_c6618a` | 坏 prefix 拒绝首 flit 并在协调复位后完成合法新帧；最后一轮核对八个源边沿上的 fault 保持。 |

综合、P&R、物理时序、板级及满幅持续吞吐均为 NOT_RUN。
