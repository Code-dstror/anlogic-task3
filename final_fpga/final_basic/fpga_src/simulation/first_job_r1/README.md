# 首作业控制与物理 SOF 门控短测

2026-11-04。范围是新候选 `dual_unified_r1`；原 `dual_hdr_merge_r1`、vendor/IP、服务器和板卡均未修改。本目录不是双目首卡的板级关闭证据。

## 已复现的控制缺口和修复

`physical_camera_rgb_pipeline.v` 原 `discard_sof` 要求 `isp_job_idle`。
旧作业的 RGB SOF 被下游保持时，ISP 虽忙，外层 RAW 弹性输入仍可能有空间。
此时到来的**禁用新物理 SOF** 通过门控，被输入寄存器接纳；旧作业排空后，它产生额外的完整 RGB 帧。
`live_gate_baseline_r5/run.log` 的真实事件为 `t=1025000 ps`、`isp_job_idle=0`、`input_valid=0`、
`selected_valid=1`、`raw_ready=1`、`enable=0`，未 force 任何内部状态或握手。

最小业务变更只从 `discard_sof` 移除 `isp_job_idle` 条件；新 SOF 按真实 enable/pause 决策，
沿用既有 `discard_live` 排空整帧。既有 RAW/RGB 缓冲、reset、abort 和退休逻辑未改。
旧作业仍可继续输出；已经接纳的合法新 SOF 及其全帧尾部也继续传递。

| 最终同夹具 A/B | ISP starts | 禁用 starts | 实际 RGB 帧 | RGB 组 | RAW stall 保持检查 |
|---|---:|---:|---:|---:|---:|
| 固定旧版负控 `live_gate_baseline_r5` | 11 | 1 | 10 | 60 | 76 |
| 候选 `live_gate_candidate_r4` | 10 | 0 | 9 | 54 | 38 |

两例均 PASS。各有一次真实 cohort reset 取消已保持而尚未交付的 RGB，因此 starts 比帧数多 1。
两例均覆盖：空闲禁用帧不启动；旧 RGB SOF 有限 stall 保持；已接纳半帧中 enable 下降或 pause 上升仍交付完整 6 组；
已经接纳到 RAW 弹性寄存器的 SOF 在 ISP stall 和后续禁用时保持；late 真实 RAW ABORT 报告一次且不清已呈现 RGB；
cohort reset 立即隔离 VALID、释放后无旧 SOF；后续合法帧恢复。

源接口为同 PIX 时钟的 4×RAW10 输入、4×RGB888 输出，lane0 在最低位；真实 RAW SOF/EOL 经裁剪与 ISP 传递。
本例是合法 8×3 RAW，SOF 在首组、EOL 每两组一次；数据和 sideband 只在 valid/ready 时前进，stall 时逐拍检查保持。
使用实际 crop、RAW 弹性输入、wide ISP、官方 RAM/DSP 和冻结 ROM；没有 JPEG/DDR/PCIe 产品资格或数值画质结论。

## 首 ticket、信用与 DROP 矩阵

`control_matrix_native_r3` PASS **49 例、19,707 checks、49 次 admission、49 次写入 ACK**，运行 3.718 s，零警告。
48 个合法冷态组合覆盖 CAM0/CAM1、3 种 PIX/DFI reset 释放顺序、4 种相位、提前或晚到的 ARM/信用、
有限 PIX 停钟、私读响应等待和 START/写入 ACK 等待，全部经过真实 normal scheduler、ticket CDC/官方控制 FIFO、
credit CDC 和 JPEG admission，最终精确完成与释放。没有用超时或强制释放推进业务。

边界 BFM 是上游 RAW owner tuple、DDR 响应、ISP 的已处理像素、JPEG 算术和最终写入 ACK；
该夹具没有完整生产 TOP、实际私读 AXI 或真实图像处理。多字段身份按 frame384/lease64/job64/pair64/member/ticket64 验证，
PIX context 只在真实 `pool_idle && admission_ready && context_match` 后接纳。

第 49 例是明确的合同违规负控：先有真实 `credit_request`，在 grant 未返回时呈现一个未许可的 SOF，
实际 admission 进入 DROP。随后同一 ticket 已发布，信用真的 reserved/grant=1，context 仍不接纳。
47 个 PIX 周期内保持这个停点，只有对应的真实 done 输入后恢复 IDLE，再用当前精确 tuple 正常完成。
这证明检测器可区分“信用已预留”和“admission 能接纳”，不证明板上真的发生了这个违规 SOF。

```
case=48 event=NEGATIVE_DROP_WITH_GRANT
scheduler=4 ticket_state=3 context_v/r/owned=100 pool=1
credit_req/ack/grant/reserved=1111 admission=3 error=0/00
```

## 板上 B 的归因边界与只读 tap

重新核对原件 `deliverables/DUAL_HDR补充/DUAL_HDR_seed1_顺序全功能三会话结果_20261101/phase-B/fpga-rx/redecoded.jsonl`：
OB342–344 都是 fresh=7、APP/ARM=1、PIX=`0x16f`、DFI=`0xb0f`、USER=`0x47f`，PIX admission 和 DFI writer ACK 均为 0。
DFI sticky=4 在 OB340–341、APP=0 时已经存在；PIX sticky=8 到 OB345、APP=0 后才出现。
旧 OB 不含以下 FSM/许可子状态，不能从旧 sticky 或 reserved 推出根因。

空闲且禁用的 live SOF 在真实小 ISP 测试中被正确丢弃；生产 TOP 又禁止双目模式的 live job，cold APPLY 等待 pipeline quiet。
目前没有证明上述“旧作业尾忙时的新 SOF”可达于故障 B 的独立冷启。
因此 **board_root_cause=NOT_ESTABLISHED，首作业板级关闭=NOT_RUN**。
保持既有 `pairbank_stop` 的 ticket recovery 保护，不新增固定等待、伪终态或超时释放。

| 新出口 | 所属域 | 位定义 |
|---|---|---|
| `raw_pair_processing_service.o_diag_scheduler_state[3:0]` | DFI | normal scheduler 的真实 state；0 IDLE、1 MEMBER、2/3 REPLAY req/rsp、4 ACTIVE、5/6 RETIRE req/rsp、7 WAIT_PROCESS、8/9 CANCEL、10/11 owner req/rsp、12 FAULT。无 normal 编译分支时为 0。 |
| `raw_pair_processing_service.o_diag_ticket_state[2:0]` | DFI | 0 RECOVER、1 WAIT_SYNC、2 IDLE、3 RUN、4 WAIT_RELEASE、5 RESULT、6 FAULT。 |
| `raw_pair_processing_service.o_diag_ticket_pixel[3:0]` | PIX | `{pixel_active,context_match,context_owned,terminal_sent}`，复用原比较结果。 |
| `jpeg_frame_admission.o_diag_state[2:0]` | PIX | 0 IDLE、1 START、2 RUN、3 DROP、4 WAIT_RESULT、5 WAIT_CREDIT_CLEAR。 |
| service 既有 `o_first_fault_code[7:0]` | DFI | source always 锁存；1 owner 消失、2 cancel tuple 错、3 writer 身份/形状/重复、4 terminal 形状/重复/写入关系错、5 同步返回的 PIX fault。 |

tap 逐层只读传播，没有复制宽 tuple 比较器，不驱动 ready/reset 或业务状态。
TOP/UART 接线和跨域冻结归父代理集成；这些端口本身不代表跨域 bundle 可以直接采样。

## 复现命令与原件

```powershell
& 'python' -B -u refactor/dual_unified_r1/src_fpga/simulation/first_job_r1/run.py --name unique_control --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
& 'python' -B -u refactor/dual_unified_r1/src_fpga/simulation/first_job_r1/run_live_gate.py --name unique_baseline --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64 --pipeline-source refactor/dual_hdr_merge_r1/src_fpga/rtl/physical_camera_rgb_pipeline.v --expect-leak 1
& 'python' -B -u refactor/dual_unified_r1/src_fpga/simulation/first_job_r1/run_live_gate.py --name unique_candidate --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
```

输出为候选下 `tmp/first_job_r1/<name>/`：实际 argv、SOURCE_START/END SHA256、编译与运行日志、RESULTS；
控制矩阵另有逐阶段 `first_job_trace.txt`。每次新名字，不覆盖旧证据。
已知沙箱 WinError623 的首尝试和夹具开发中的失败日志均保留，不计为通过。

最终有效运行：

- [控制矩阵 RESULTS](../../../tmp/first_job_r1/control_matrix_native_r3/RESULTS.json)
- [固定旧版负控 RESULTS](../../../tmp/first_job_r1/live_gate_baseline_r5/RESULTS.json)
- [候选门控修复 RESULTS](../../../tmp/first_job_r1/live_gate_candidate_r4/RESULTS.json)

两例 ISP 运行各约 4.5 s。19 项官方诊断精确分类为 tone ECC 输入宽度 4、gamma 未使用 ECC 端口 1+2、
TD ERAM INIT_FILE part-select 8、tone ECC runtime 宽度 4；RTL 自有警告为 0。
没有全局 suppress，新诊断或数量变化会失败。实际工具 TD Release2026.2.210.850 / ModelSim2020.4，
两端输入 SHA 复核一致。综合、P&R、时序、bitgen和板级均 **NOT_RUN**。
