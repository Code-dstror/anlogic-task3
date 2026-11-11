# seed56 HDR 30/20 的共享处理诊断

基线 `camera_raw_r2` / `41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213` / seed56。现场 epoch37 的 DJ/v3 同窗 540.000455 秒内，每眼 LONG 和 SHORT 分别增加 16,365，双眼合计约 60.611 组/s。CAM0/CAM1 DFI jobs 分别增加 16,365/10,910，合计 50.509/s。OB/v2 对应同段 descriptors accept 和 retire 各增 27,275。慢眼从 FPGA job 已是约 20.2/s，独立 RK 窗口未显示长期软件积压。`begin_reject` 是聚合计数，现有 1 Hz 记录没有逐组拒绝原因或独占阶段时间。 [现场核查](../../../../deliverables/CAMERA_RAW_R2_seed56_双目HDR帧率问题_给FPGA队友_20261110/CAMERA_RAW_R2_seed56_HDR帧率不对称_RK侧核查_20261110.md)

## 已找到固定 HDR 上限

生产 HDR 经 `private_raw_isp_borrow4` 外借到 `u_camera` 的真实共享 ISP。`shared_wide_isp` 到 `wide_color_pipeline`，其中 `hdr_tone96_shared4` 把 168 位四像素组拆成四拍，每拍只送一个 RGB14 像素到 T96。`s_ready` 要等 `group_lane==3` 才接下一组。末 lane 才提交一组 120 位 RGB10。SDR 走组级旁路。seed56 原生报告只展开这一处 tone，并确认 PIX 时钟为 125.000 MHz。 [顶层](../../src_fpga/rtl/anlogic2026.v) · [物理 ISP](../../src_fpga/rtl/physical_camera_rgb_pipeline.v) · [颜色链](../../src_fpga/rtl/wide_color_pipeline.v) · [T96](../../src_fpga/rtl/hdr_tone96_shared4.v) · [seed56 时钟](../../../../server/td/local/download/camera-raw-r2-41cb-selection-20261110/seed56/checkout/refactor/camera_raw_r2/fpga_prj/rfcamera_raw_r2_Runs/phy_1/simple.timing)

| 量 | 1080p 合计服务模型 |
|---|---:|
| T96 无停顿像素数 / 帧 | 2,073,600 PIX cycles |
| T96 无停顿服务时间 / 帧 | 16.5888 ms |
| T96 无停顿服务上限 | 60.2816 帧/s |
| 现场 60.6111/s 的每帧平均时间预算 | 16.4986 ms / 2,062,330 PIX cycles |
| 若目标按合计 60.000/s 计算，T96 后余量 | 9,733 PIX cycles / 77.9 µs / 帧 |

即便 DDR/merge/下游完全无停顿，原 T96 也不能持续接收现场双眼提供的 60.6111 组/s。reader 预取可以减少额外空拍。`60.2816` 是数学上限，实际 50.509 及跨 epoch 慢眼变化还受共享作业周转、两 bank 的捕获相位和其他反压影响，现有资料无法确定各段份额。

## RAW bank 与 JPEG/host 的所有权

1. `raw_hdr_phase_scheduler4` 一次持有一个 HDR 作业。reader 的 RESULT 只让 `RUN` 转为 `WAIT_PRODUCT`。后者要求匹配 processing 终态、HDR reader quiet、私有/公开 RAW read quiet 和处理池 quiet，才发 owner RETIRE。等待 `RELEASE_JOB` 完成期间仍不接新作业。 [共享调度](../../src_fpga/rtl/raw_hdr_phase_scheduler4.v)
2. 处理票据使用匹配的全帧 SOURCE 和 JPEG DDR write-result。顶层把真实 writer ACK 分送处理票据和 metadata gate，`i_write_quiescent` 还要求 JPEG START/DATA/RESULT 不再有效。RAW pair bank 实际 release 要求 HDR read quiet、写 quiet、票据释放以及目录读不在途。故 RAW bank 从 capture 占用到 reader 完成后仍保留，至少覆盖本帧 JPEG 写入及其终态。 [处理票据连接](../../src_fpga/rtl/raw_pair_processing_service.v) · [票据源端](../../src_fpga/rtl/raw_job_ticket_context_cdc.v) · [双 bank 归还](../../src_fpga/rtl/hdr_pair_bank_owner_dual.v)
3. 正常 HDR 归还用 JPEG ring 的 `o_write_quiescent`，要求 staged 写数据、最终 B 和写结果排空。读取端的 READY/SENDING、host lease 和 `o_record_quiescent` 是独立的。若 host 长时间占满 JPEG 槽，后续 `record_product_available`/credit 会拖住新的处理准入，JPEG 读也可争用 DDR。这是间接反压，现有 1 Hz 证据不能把它从所有帧的等待时间中扣除。 [JPEG ring 写/全局静默](../../src_fpga/rtl/jpeg_frame_ring.v) · [顶层接线](../../src_fpga/rtl/anlogic2026.v)

提早复用 RAW bank 需要把 reader 已完成的原始存储生命周期与尚在处理的身份/租约拆开，还需允许第二作业进入实际空闲级，独立验证两作业的取消和真终态。它也无法跨越单 T96 的算术服务上限。该方向适合在量到 RAW bank/票据空等后再评估。

## JPEG 与其它级的静态服务量

- 1080p 4:2:2 每帧 120×135=16,200 MCU，MCU 内 2Y+Cb+Cr。色彩和预处理入口为四像素组。MCU 读每块 8 行，最后一行握手后调下一块。实际 DCT 是共享的 1D 核，行/列各 8 向量/块，共 64 向量/MCU，以一向量/拍为无停顿下界。量化流对每块交 1 HEADER+8 DATA，为 36 token/MCU。两数是不同级的服务量，不应相加当作每 MCU 固定占用。
- 真实 entropy 每拍最多规划两个 AC 符号并按非零位置跳过零，单字节/PIX cycle 送 formatter/packer。服务时间取决于系数、字节 stuffing 和反压。目标 60.611/s 的预算约 127.3 PIX cycles/MCU、2,062,330 bytes/frame 的单字节理想带宽。现场首个 HDR epoch5 两个原件分别约 78,635/69,040 JPEG 字节，对应单字节出口下界 0.629/0.552 ms。它们是启动原件，不能代表 epoch37 的系数稠密度或 JPEG 时延。JPEG 仍需实际 stage 占用测量。 [MCU 行流](../../src_fpga/rtl/jpeg_mcu_422.v) · [共享 FDCT](../../src_fpga/rtl/jpeg_dct8x8_pipeline.v) · [量化流](../../src_fpga/rtl/jpeg_quant_stream.v) · [熵编码](../../src_fpga/rtl/jpeg_entropy.v) · [首条 HDR 原件目录](../../../../deliverables/CAMERA_RAW_R2_seed56_双目HDR帧率问题_给FPGA队友_20261110/startup-originals/capture)
- epoch37 的 RK 实际产品显示 `processing_enables=0`。不能用高斯/HE/DCP 打开后的资源或等待解释这段现场。双目 SDR 在该会话达到合计 60/s，说明共用 JPEG/写回链能处理这段 SDR 的数据，HDR 图像内容、RAW 双读和 T96 与此不同。

## 可复现验证与实施取舍

1. **预取的独立收益。** 真实 DDR arbiter＋reader 的独立 16/16 短测，在首 R 延迟 32 拍的模型中由 3,515 降到 2,421 cycles/1,071 groups，均为 42 AR/670 R 且 RAW14 一致。client R stall 1,280→0，master idle 1,451→356，master R stall 均为 0。仲裁器本来就有 client 16-beat response bank，预取的作用是尽快排完该 bank，令下一 AR 首响应与旧数据解码重叠。结果针对短模型，实际 DDR 带宽和稳定 FPS 尚待新 bit。
2. **解除 T96 固定上限。** 最小吞吐候选为原 `hdr_tone96_shared4` 内双独立像素通道。每组分两拍，保留单组所有权、共同 `advance`、SDR 组级旁路、四 lane 顺序及 SOF/EOL/clipped。每 lane 逐位复用原 96 段系数、max、半向上取整、限幅与 DSP 算术。新 lane 大致需另 2 个 ROM ERAM、5 DSP，外围 LUT/Slice 和扇出用 A/B 核实。旧 leaf 每个系数 ROM 的 A 口为写数据、B 口读，现有端口无法直接用作第二读地址。双 lane 的理论下界为 8.2944 ms/1080p，实际节省取决于读链及后段反压。
3. **最小独立验证。** 保持 Q75、HDR 比率/黑电平和生产尺寸不变。T96 公共接口做连续不同四 lane、各段边界与饱和、同组序号、SDR/HDR/SDR、任意输出反压及复位。比较独立数值 oracle 的每像素输出与 sideband，并证明无反压 HDR 稳态每 2 拍一组。预取与 tone 合入后，真实链至少通过首个合法 pair→SOURCE→JPEG 写终态→票据→RAW 归还，以及后继相反眼的事务。对照保持相同 RAW 样本和相机 FS 相位。
4. **新 bit 验证。** 在同一稳定 HDR epoch 记录每眼 LONG/SHORT admit、bank BEGIN 拒收/失效、reader/ISP 输入输出握手、JPEG 写结果、RAW bank 归还和 USER 产品/退休。按 DFI job start→reader RESULT→写终态→release 分别计时，另记 `credit` 等待和 JPEG 完成字节。先用实际双眼相位再覆盖慢眼交换。相同窗口用 RAW 来源/产品/退休对账，不用 host 显示数字代替 FPGA 的吞吐。

## reader 原生局部 A/B

固定源完整 1080p reader 两臂用同一 TD 2026.2、4 线程、`area_prior`、`partition`、`min_control_set=2`、`add_map_lut_struct=on`、DFI 7.502 ns 和 F3 释放。`reader_native02` 的 baseline 和第一版 A8 预取 opt_gate 与同 AL 重开均 PASS。A8 在重开报告中 LUT 1731→1759，FF 1704→1470，Slice 1423→1404，ERAM 2→6，DSP 8 保持。F3→cursor 的估计余量 +3.002→+1.039 ns，候选最慢落在响应队列容量/握手→cursor 状态。

容量判定收尾 B2 单独综合 PASS，复用原 baseline 并核共同输入 SHA-256。重开为 1749 LUT、1470 FF、1401 Slice、6 ERAM、8 DSP。F3 Q→cursor 状态 D 的旧组合弧已在精确 pin 查询中消失，队列计数→状态 D 的全周期估计余量为 +4.981 ns。剩余全载体最差为 F3→新增 RAM 读使能 +1.687 ns，仍需核新源真实布线。整机 Slice、P&R/STA、bitgen、板级为 NOT_RUN。 [A/B 入口与证据](../../experiments/hdr_read_prefetch_20261110/README.md)
