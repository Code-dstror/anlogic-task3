# SOURCE 借用接口与复位边界

本文件和 opaque 清单是独立测试输入。生产源、历史测试和内部层次只用于编译与取哈希。仅通过公开端口驱动和观察。基线为 `41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213`。工具使用本机登记的 ModelSim 和显式 TD 2026.2 根 `D:/App/TD_Release_2026.2.210.850`，各版用独立工作库、日志和墙钟/仿真 watchdog。[Opaque 编译清单](C:/fpga_workspace/anlogic-task3/refactor/camera_raw_r2/experiments/timing_source_20261110/OPAQUE_SOURCES.json)

## 合法 profile

被测 `private_rgb_source_borrow4` 使用 `MAX_WIDTH=1920, MAX_HEIGHT=1080, NR_ENABLE=0, NEUTRAL_STATS_ENABLE=0, DEHAZE_ENABLE=0`。本接口为已持有原始 RAW owner 后的 RGB 直通及 SOURCE 终态服务。合法描述符宽度为不超过 1920 的正四倍数，高度为 1–1080。可选 `8×2` 四组短帧，每组四个 24 位像素。F21、NR、neutral、writer 及 AXI 后端不参与本 profile。将其输入置零，包括配置和写响应 VALID，所有未使用输出可留空。`i_matrix_hard_fault` 可独立驱动，正常用例置零。

除 DFI 时钟/复位、DFI 故障外，下列握手按 PIX 上升沿计。1 位信号省略位宽。

| 通道 | 输入 | 输出 |
|---|---|---|
| 时钟与复位 | `i_pixel_clk, i_pixel_rst_n, i_dfi_clk, i_dfi_rst_n` | `o_pixel_fault, o_dfi_fault` |
| 原 owner | `i_owner_valid, i_borrow_live, i_owner_frame[383:0], i_owner_lease[63:0], i_owner_job[63:0], i_owner_pair[63:0], i_owner_native_tag[63:0], i_owner_writer_tag[31:0], i_owner_member` | `o_context_available, o_pool_idle` |
| 原 context | `s_context_valid, s_context[575:0], m_context_ready` | `s_context_ready, m_context_valid, m_context[575:0]` |
| RGB | `s_rgb[95:0], s_keep[3:0], s_sof, s_eol, s_last, s_valid, s_tag[63:0], s_index[31:0], m_ready` | `s_ready, m_rgb[95:0], m_keep[3:0], m_sof, m_eol, m_last, m_valid, m_tag[63:0], m_index[31:0]` |
| 原 SOURCE | `s_status_valid, s_status_context[575:0], s_status_tag[63:0], s_status_ok, s_status_error[7:0], s_status_groups[31:0], i_original_read_quiescent` | `s_status_ready, o_stale_original_status_count[31:0]` |
| SOURCE notice | `m_source_notice_ready` | `m_source_notice_valid, m_source_notice_context[575:0], m_source_notice_ok, m_source_notice_error[7:0]` |
| 已处理 SOURCE | `i_processed_sof_fire, i_writer_source_start_fire, i_pipeline_quiescent, i_pipeline_ok, i_pipeline_error[7:0], m_processed_source_ready` | `m_processed_source_valid, m_processed_source_frame[383:0], m_processed_source_lease[63:0], m_processed_source_job[63:0], m_processed_source_pair[63:0], m_processed_source_write_tag[63:0], m_processed_source_member, m_processed_source_error` |

- 借用描述符 `frame` 在 `[76:45]` 填非零 session，`[4]` 填 camera，`[220:205]` 填宽，`[236:221]` 填高。`s_context = {job[63:0], session[31:0], 31'b0, camera, native_tag[63:0], frame[383:0]}`。lease、job、native_tag、writer_tag 均须非零。建立 `i_owner_valid=1, i_borrow_live=1` 后提供相符的 context，owner 的 frame、lease、job、pair、native_tag、writer_tag、member 保持到已处理 SOURCE 真实传输并恢复 pool idle。
- Context 先由 `s_context_valid && s_context_ready` 接收，再以相同 576 位交给 `m_context_valid && m_context_ready`。下一步才开始 RGB。输入 valid/data 保持至 ready，输出在受压期间保持 valid、data 及 sideband。RGB 全 96 位、keep、SOF/EOL/LAST、tag、index 原样传输。首组 index 0，之后每个真实 RGB 握手加一。完整短帧四组，keep=4'hf，第一组 SOF，每行第二组 EOL，末组 LAST。
- 原 SOURCE 的 context、tag 匹配借用身份，`s_status_groups` 是本帧实际接受的 RGB 组数，包含同沿握手的最后一组，以 32 位计数。源证明提供后保持输入有效并持有内容直到 `s_status_ready`，允许源在 ready 仍低时先行给出稳定的完整证明。`i_original_read_quiescent` 为真后，notice 传输相同身份与 OK/error。Notice 有独立 ready，稳定等待接收。原 SOURCE 和 notice 各计一次握手。
- 完成 notice 且 `i_pipeline_quiescent=1` 后可以消费相符的原 SOURCE。已处理 SOURCE 单独持有，字段取冻结 owner，write_tag 为 32 位零扩展。`m_processed_source_error` 是布尔值，源或下游为负则为 1。已有真实 RGB 提交的坏源可用 `s_status_ok=0` 和非零 error 检查负终态。处理流水为空且已处理 SOURCE 真正被消费后，才允许下一 owner。`i_processed_sof_fire` 是每帧最多一次的真实下游 SOF 脉冲，writer start 若驱动则只能同沿或随后一次。
- 可用错 tag/context 的原 SOURCE 验证丢弃计数。该握手不生成 notice 或已处理 SOURCE，之后仍可提交同一 owner 的合法 SOURCE。计数为饱和 32 位。未证明 owner 的上下文、计数不合规和外部复位撤销的旧事务不作为合法成功案例。

## 采样、复位和短测

- 任一低有效复位可在停钟时撤回有效 context、RGB、notice 及已处理 SOURCE，旧事务随复位中止。两复位都高后，以随后第一次合法 PIX 正沿为 R1，依次 R2、R3，随后下降沿 F3，下一正沿 R4。符合条件的 context 最早在 R4 握手。只以正沿上的 valid/ready 计事务，F3 上采样 presented 输入时，首个 R4 尚未发生，故无新 context/RGB/notice/终态有效。测试覆盖复位由两域先后释放、PIX 停在高/低、R3 到 F3 之间重新断言以及持有输出时停钟断言。
- 用例先做早呈现 context 的合法第一帧，确认 R4 恰好接收一次。阻塞下游 context、RGB、notice 和 processed SOURCE 各至少一拍，实际接收全部预期字段。停钟恢复后换身份完成一帧，旧身份不泄漏。负源案例先有真实 RGB 握手，再注入准确的负 SOURCE 与有限下游忙，终态出错且无重复。可以用公开信号驱动下列 cleanup 检查尾部恢复。
- 与实际 cleanup 联用时，`hdr_pair_product_abort_drain4` 参数为 `SYNC_CLEAR_ENABLE=1, SEPARATE_DATA_RESET=1, FALLING_INPUT_RESET=1`。输入 `clk,rst_n,i_data_reset_n` 取同域时钟与外部合法复位；`i_context_fire,i_context_tag[63:0]` 为输出 context 的真握手和 tag；`i_source_fire,i_source_tag[63:0],i_source_ok,i_source_read_quiescent` 取该帧第一个 notice 及原读静默；`i_native_job_start` 为实际 RGB SOF 握手；`i_native_valid,i_isp_valid,i_preprocess_valid,i_admission_valid` 为各公开出口的有效呈现。源 notice 每帧只发一次 cleanup 事件。驱动 `i_failed_status_ready`，观察 `o_drain_pending,o_local_rst_n,o_local_data_rst_n,o_failed_status_valid,o_protocol_fault,o_stale_source_count[31:0],o_cleanup_pulse`。在失败后保持任一呈现或暂缓消费，clear 需等已承诺呈现排空，负 STATUS 随后才可消费。覆盖最接近 F3 和正常运行时下降沿的呈现，停钟时复位撤回及新健康帧。初始共同复位期内，`rst_n` 与 `i_data_reset_n` 可使用同一外部复位用于此受控接口短测。生产相位门槛以 SOURCE 的两域端口为准。
- 每次从公开端口建立独立计分。Baseline 与候选使用同刺激、独立日志、同工具/参数，记录哈希和首个终态。错误分类为 DUT、合同、夹具或工具。短样本覆盖事务边界和数据逐位一致性。
