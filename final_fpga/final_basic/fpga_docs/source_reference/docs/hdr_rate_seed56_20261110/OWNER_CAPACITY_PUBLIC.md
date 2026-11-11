# 双目 HDR RAW owner 容量黑盒合同

测试实例为 `owner_service_carrier`，固定 16×4，公开端口见声明。载体接实际 `full_raw_store` 和 `raw_pair_job_service`，包含四成员 RAW 捕获、FIFO、写者、AXI 写仲裁、两眼目录、pair owner、派发及 scheduler。DDR 存储、HDR reader、PIX/JPEG 和票据尾部通过公开端口提供 BFM。相同 RTL 施加两种服务时长，结果用于确定该服务条件下的容量截止。 [端口声明](OWNER_CAPACITY_PUBLIC.ports) · [不透明编译清单](OWNER_CAPACITY_PUBLIC.json)

## 时钟、配置与静态边界

- DFI 周期 7.502 ns，PIX 8.000 ns，时钟相位错开。各自上升沿采样。`rst_n` 低有效，跨两个时钟各至少 16 拍，载体在各域同步释放。`i_now_ns` 为单调递增的 DFI 时间戳，单位 ns，建议从非零值开始。外部输入在接收沿之前稳定。
- 复位期间及复位后无事务时，将 `i_reader_quiet`、`i_product_quiet`、`i_writer_quiet` 和 `i_ticket_released` 置高，RAW、SOURCE、reader RESULT、processing pulse、B VALID 置低。复位释放约 32 DFI 拍后拉高 `i_cfg_valid`，保持到 `o_cfg_ready` 握手。确认 `o_cfg_error=0`、观察 `o_cfg_done`，等 `o_policy_admit` 为高再留至少 16 PIX 拍给 capture 发布。测试期间只用一个配置，session 11、epoch 1、HDR ratio 4、delta 50 ms、wait 100 ms、age 1 s。需要独立场景时 cold reset。
- 载体开启两眼四成员、真实 SOURCE、目标槽本地退休和独立 DFI 数据释放，固定 HDR JPEG 路由。两眼 capture enable、有效时间/色相和 DDR ready 固定为高。RAW tap 已经通过物理来源 accept。正常 SOURCE 的 session、epoch、camera 和成功状态由载体固定，驱动者给出序号。停止、取消、SDR 模式、RAW 导出、BAR、mask 和 host replay 请求固定为空闲。

## PIX 四成员与 DFI 写端

lane `l=2*eye+role`，role 0 为 LONG、1 为 SHORT。数据 `s_raw_data[40*l+:40]`、序号 `s_raw_sequence[32*l+:32]`、元数据 `s_raw_metadata[197*l+:197]` 和相应 `s_raw_valid/sof/eol` 位独立。每个成员恰 16 个 40 位 RAW10 组。`s_raw_valid` 置高的每个 PIX 沿发一组，组首 SOF、每四组 EOL。源可以在任意两组间插入空拍。`o_capture_admit[l]` 是真实接受 SOF 的同沿观测，不是 READY。等待一次合法 SOF 后才送本成员的其余组。

| 元数据位 | 合法值 |
|---|---|
| `[63:0]` | 本成员在 SOF 时的纳秒 timestamp，准入时不晚于 `i_now_ns`，SHORT ≥ LONG |
| `[95:64]` / `[127:96]` | LONG 3200 或 SHORT 200，gain 256 |
| `[159:128]` / `[191:160]` | recipe `32'h56a3d02f`，同眼同组共用的递增非零 group |
| `[192]` / `[194:193]` / `[196:195]` | physical=1，角色 LONG=1/SHORT=2，两个资格位均为 1 |

每眼每角色用各自前进的 sequence。真正最终 EOL 之后，对应 `s_source_valid[l]` 持有匹配该成员的 `s_source_sequence[32*l+:32]` 直到 `s_source_ready[l]`。所有已经从 PIX 发出的成员都给 SOURCE，包含后来获负 BEGIN 的成员。可用 `o_capture_admit`、SOURCE 握手和实际 job 身份检查输入是否齐全。

DFI AW/W/B 使用 AXI 正常规则。AW 采样 `m_axi_awvalid && m_axi_awready`，每笔收 `AWLEN+1` 个 `m_axi_wvalid && m_axi_wready`，末拍 WLAST，成功 B 回显已接 AWID、BRESP=OK，BVALID 保持至 `m_axi_bready`。存储区以 `0x02000000` 为基址，每槽 16 MiB，槽号 `4*eye+2*bank+role`。完整成员连续写 80 B，从第一个组最低字节开始，W beat 按 WSTRB 小端写入。AW 地址 16 B 对齐、AWBURST 为 INCR、AWSIZE=4，实际 burst 拆分由接受的 AW/W 账本核对。常规 B 及时响应，必要时只用有限拍延迟。为延长捕获时间，在 PIX 暂停后续组及 SOURCE，已接受的 AW/W/B 正常完成。

## 真实服务与 BFM 终态

DFI `o_pair_valid && o_pair_ready` 取得 `o_pair_bank` 和 `o_pair_id`，是服务计时的起点。后续 `o_job_valid && o_job_ready` 发布 `o_job_frame` 的 `[4]` camera、`[108:77]` LONG sequence、`[366:335]` group、`o_job_id`、`o_job_pair_id` 和两租约。每个接收组按眼保序，两成员数据、匹配 SOURCE 和 AXI B 已成功，两个租约非零且不同。比较完整身份，`o_job_id` 与 acquire 的 `o_pair_id` 对应；逐次 RELEASE 只归还已接的 bank/ID。

BFM 依次以 `i_member_ready`、`i_context_ready`、`i_start_ready` 接受 `o_member_valid`（`o_member_index=0`）、`o_context_valid`、`o_start_valid`。这三笔握手分开计数。START 后将读、产品、写、票据资格置为未完成。到计划时刻给 `i_result_ok=1`，保持 `i_result_valid` 到 `o_result_ready` 握手；`i_result_ready` 表示 transport 的 READY，`o_result_ready` 是作用于调度器的实际 READY。逐步恢复 `i_reader_quiet`、`i_product_quiet`、`i_writer_quiet`，再给匹配 `i_processing_job_id` 的单拍 `i_processing_done`（`i_processing_error=0`）。用 `i_ticket_released` 表示处理结果已归还票据。资格全部满足且终态已提交之前禁止 RELEASE。`o_release_valid && o_release_ready` 退休 `o_release_bank/o_release_id`，`o_retire_done` 回应该次归还。最后 drain 到 `o_quiescent`，`o_fault` 应保持低。

`o_begin_reject[eye]` 为合法运行期负 BEGIN 事件，`o_pair_expire[eye]` 为超时，`o_bad_finish[lane]` 为负 FINISH。`o_bank_states[2*(2*eye+bank)+:2]` 的公开编码为 FREE 0、BUILD 1、READY 2、OWNED 3。事件 oracle 由预定源输入和服务合同独立生成，诊断输出只用于核对及定位。测量期用输入身份分窗，收尾排空单独记录。

## 最小相位对照

每眼 LONG 起点以 3,300 个 DFI 拍为周期，本眼 SHORT 晚 100 拍。首个 RAW 组在成员起点发送，剩余 15 组靠近该成员的计划 SOURCE。LONG 的 SOURCE 在组首后约 2,900 拍，SHORT 约 3,000 拍。首组后保留足够空拍使合法 BEGIN 能在早期决策，最后给足真实 B 和 FIFO 收尾。相同外部刺激下，CAM1 相对 CAM0 分别采用约 100、400 和 3,200 拍固定相位。

以 acquire→RELEASE 约 1,950 拍为慢服务，约 1,590 拍为快服务。基于真实 acquire 安排 BFM 终态，reader 先回复，处理结果和票据归还在目标前数拍，给真实 RELEASE 留固定控制开销。每次报告实际 acquire→RELEASE，另计 acquire→job、job→START 和 START→RESULT。快服务测量窗要求真实时长稳定在低于 1,650 拍的区间。慢服务须真实超过 1,650 拍并接近 1,950 拍。为每笔记录 DFI 边沿，允许实际捕获、目录和 B 延迟改变离散组边界。理想模型仅给出约 60/40、50/50、40/60 的三个 60 组相位对照形状。

每个 phase 可热身 30 组、每眼测量 60 组、最后停止 RAW 并排空。慢服务要见组缺口和同眼负 BEGIN，已接 job 逐一真实归还，合法输入与终态均完整，且没有到期、坏 FINISH 或故障。快服务三相位均要求每眼 60/60，负 BEGIN 为零，所接 job 和归还身份对账相等。每个场景约 2.24 ms 的模拟输入窗口，DFI 运行 watchdog 2.5 ms，wall-clock 限 60 秒。可将多个相位分进程运行，共用一次不透明编译。覆盖同眼容量首拒后旧 bank 归还且迟到 peer 仍拒、下一个合法组恢复，记录真实握手相对顺序。

编译路径以 `refactor/camera_raw_r2/` 为根，TD 模型路径以已验证 `D:/App/TD_Release_2026.2.210.850` 为根。使用 ModelSim `D:/App/modelsim/win64`，清单的 `td_models` 编到 `ph1`，`td_work_sources`、生产闭包与载体编到 `work`。执行 `vsim -L ph1` 加清单所列两个 global 及测试顶层，生产和载体可编译和取 SHA256。短门只证明给定捕获/服务和时钟模型下的实际 RAW 控制容量，不能外推满幅真实 DDR、JPEG 或板级 FPS。

载体的原生 `vlog` 与 `vopt` 预检用时约 2.25 秒，编译和展开错误数为 0。全部 26 项生产 HDL/IP/include 与固定提交一致。展开告警由闲置输出端口及冻结 RAM 模型的 ECC 输入宽度、空初始化范围构成。此处预检没有施加功能刺激。 [预检日志](../../../../tmp/hdr_rate_seed56_20261110/owner_carrier_compile_r1/elaboration.log)
