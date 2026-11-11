# camera_fusion_r1 资源与约束审计

## 整机原件

TD 6.2.3.210850，器件 PH1A90SEG324-2。两组综合均读回 `area_prior`、`partition`、
`add_map_lut_struct on` 和 `min_control_set 2`，综合线程分别为 4、16。
RAW R2 只有 HD，作为相近架构的旁证。路由报告来自各自复用的综合检查点。

| 固定源及阶段 | Slice / 64,320 | LUT 统计口径 | FF / 128,640 | ERAM / 272 | DSP / 240 |
| --- | ---: | --- | ---: | ---: | ---: |
| Rate R2 d1e5dce4 原始 gate | 64,009 | 80,912 #lut | 70,897 | 259 | 146 |
| 同源原生综合重开 | 63,462 | 79,437 #lut | 70,871 | 259 | 146 |
| 同源 8 路由种子 | 61,970–62,109 | 57,807–58,022 #lut6 / 64,320 | 71,707–71,813 | 259 | 146 |
| RAW R2 41cb5991 原始 gate | 63,022 | 79,389 #lut | 70,774 | 230 | 146 |
| 同源原生综合重开 | 62,484 | 77,942 #lut | 70,748 | 230 | 146 |
| 同源 48 路由种子 | 61,436–61,684 | 56,662–56,924 #lut6 / 64,320 | 71,538–71,696 | 230 | 146 |
| RAW R2 1a5603c1 原始 gate | 63,334 | 79,564 #lut | 71,111 | 236 | 151 |
| 同源原生综合重开 | 62,791 | 78,112 #lut | 71,085 | 236 | 151 |
| 同源 seed25 路由 | 61,733 | 57,200 #lut6 / 64,320 | 71,942 | 236 | 151 |

Gate `#lut` 包含按逻辑输入数计量的 LUT，物理百分比以 routed `#lut6` 为准。Rate 原始 gate
另列 49,360 logic LUT、7,373 ripple、2,160 distributed RAM LUT、16 shift LUT。两基线
不同源、不同线程，面积差只作级别对照。RAW R2 seed56 的物理 Slice/FF/LUT6 为
61,450/71,616/56,718。其旧版双目 HDR 540 秒窗为 30.306/20.204 实际 job/s。
RAW R2 1a5603c1 seed25 在固定结果提交 6a500bce 的本地原件中复用共享 SYN16，原始 gate、
重开和物理面积 SHA256 均与下载索引一致。1a5603c1 相对同设置的 41cb5991 多 312 原始 gate Slice、
307 重开 Slice、337 FF、6 ERAM、5 DSP。该对比包含该轮 HDR 吞吐和 SOURCE/JPEG 修复，
量测范围为 HD 版。seed25 结果清单报告路由完成和全局 +0.001/+0.002 ns 摘要。
本地详细四类时序、例外和 bit 交付仍待上传。 [Rate R2 原件与时序](../../../camera_rate_r3/docs/timing_d1e5/README.md)
· [RAW R2 原始资源文件](../../../../server/td/local/download/camera-raw-r2-41cb-selection-20261110/seed56/checkout/refactor/camera_raw_r2/fpga_prj/rfcamera_raw_r2_Runs/syn_1/rfcamera_raw_r2_gate.area)
· [RAW R2 1a5603c1 下载索引](../../../../server/td/local/download/camera-r2-1a5603c1-seed25/ARTIFACT_INDEX.json)
· [RAW R2 seed25 交付状态](../../../../deliverables/CAMERA_RAW_R2_1a5603c1_seed25_Linux_Debug_20261110/DELIVERY_STATUS.json)
· [RAW R2 帧率与资格边界](../../../camera_raw_r2/docs/hdr_rate_seed56_20261110/README.md)

Rate R2 原始 gate 只余 311 Slice，重开余 858，路由余 2,211–2,350。四像素共享 ISP、
JPEG、滤波与 HE 保留一套。Rate R2 UHD 本身已占用 +24 片 MCU ERAM、+5 片滤波 ERAM，
均已计入 259。新增四片 HDR 预取和两片 Tone ROM 后，按显式实例预算为 265 ERAM，余 7。
画质使用原有四片 Tone ROM，仍需对融合版映射核对。DSP 实例预算以 146 为起点，
保留 MAC4 可释放 4，双像素 Tone 增 5，渐进高光增 2，目标约 149，余 91。
FF 还有约 56,800 个物理资源余量，FF 控制集和布线仍会消耗紧张的 Slice。

R3 双像素 Tone 载体原始 gate +297 Slice，R3 改法比 RAW R2 双像素同载体少 82 Slice。
HDR 画质局部重开分别测得融合 +23 Slice、色彩 +225 Slice 和严格 CFG +143 Slice。
完整 CFG 载体父版 180 秒停于 Map Gate，未得到增量。各载体的映射、口径与覆盖不同，
风险判定为 Slice 裕量紧张。融合版整机 Slice、LUT、FF 与物理可放置性仍待实测。
[UHD 资源](../../../camera_rate_r2/docs/UHD_RESOURCE_COST.md)
· [R3 局部收益](../../../camera_rate_r3/docs/THROUGHPUT_INCREMENT_20261110.md)
· [HDR 画质增量](../../../camera_hdr_quality_r1/docs/QUALIFICATION.md)

## 融合边界

- 两套输入的生产封印均逐项重新核对。R3 与 RAW R2 的 `hdr_pair_read_cursor`、`private_rgb_source_borrow4`、
  `ordered_frame_ingress` 和 `ordered_frame_cdc` 文件相同，已含 B2 和 ASR/同步数据资格分离。
  R3 的四处本地复位相位、四 DSP 的恒等 MAC、Tone 共享舍入及算术资格分离、JPEG DC 门与 MCU 行预取
  均属于合并保留范围。平衡融合增加运动判决，采用同一六推进边的 MAC 路径。HDR Tone 合并四页表、
  Q14 和高光算术，同时保留两像素/拍及 R3 资格控制。RAW R2 的 DJ/v3 诊断页较 R3 更新。
- CFG 保留 R3 的 HD/UHD 合法档位，画质编码保留 374-bit 紧凑 tuple 和 32 字线格式。
  画质标记复用合法代数的高位，WB 借用质量 v1 合同中为零的 HDR delta 高字；
  旧无标记 schema2 继续完整保留该高字。逐字匹配、全包 ACK 和首合法帧 APPLIED 都是资源优化边界。
- ADC、observer SDC、主时钟 SDC 三份原字节一致。R3 的 stereo/stream SDC 对
  `held_profile[11..13]`、几何 bit14、SYS25 request/ack、`u_cfg_release` 以及两路
  `sdr_profile_cfg` 有额外或替换约束。保留与实际 R3 高帧率前端匹配的版本，检查质量参数是否仍走原
  40-bit FIFO、同域状态寄存器与原 CDC 对象。历史 RAW R2 的 `slow_request_cfg`、
  `slow_mode_pixel` 例外只适用于实际存在的首级。后续映射核对 128 条 DFI min guard、
  CSI event FIFO 两条被 IP 预算覆盖的 guard、UART ignored 首级和全部复位副本。
- 历史 d1e5 八种子中七个物理 STA 为负。重复 setup 路径集中在 PIX RAW ingress 宽资格、
  DFI owner 和 F22/F23 join。最差实例的 setup/removal 分别为 −0.440/−0.175 ns。
  RAW FIFO、JPEG MCU 和 quant 的数据 hold 与 ASR removal 分别检查。融合候选的
  setup/hold/recovery/removal、覆盖率、bitgen 与板级资格均待新源结果。

## 优先局部 A/B

### RAW10 整拍窗口

d1e5 四套 ingress 原始 gate 计 1,384/961/540/590 logic LUT。当前候选仅专门化静态整拍配置。
START 加不超过两个 CONTEXT 可保留至多 15 字节。正常发送一次消耗 16 字节，每组加入 5 字节，
因此每个正常 DATA 都携带当前 RAW，且发送前留存字节数为 11–15。整拍几何的合法组数是 16 的
倍数，最后一组前留存 11 字节，送出后 DRAIN 为空。五个固定窗口都等于原 288-bit 移位在相应计数下
的切片，完整 DATA 的 KEEP 为 ffff。通用几何继续原移位及尾字掩码。非法 EOL、故障、取消、保持
和 SOURCE 判定控制保持原路径。只改实验叶，独立功能资格由另一个作者执行。

| 局部载体 | 原始及重开 Slice | #lut | FF | 8 ns SWNS | history→DATA | count→DATA |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| HD/UHD compact | 782→730 | 1,122→840 | 1,062→1,008 | +4.328→+4.706 | +5.426→+6.201 | +4.595→+5.056 |
| 固定 CAM1 LONG | 696→666 | 979→664 | 951→899 | +4.319→+4.478 | +5.427→+6.201 | +4.501→+4.776 |

两对原始 gate 与各自重开的面积文件完全相同。ERAM/DSP 均为 0。叶 logic LUT 分别 637→552、
571→495。RTL 保持历史寄存器声明宽度，映射自动消去 40 个无使用位，未另做缩历史臂。
四臂实际运行 63.171、55.703、49.579、37.922 秒。可从仓库根用登记的 Python 执行
`-B refactor/camera_fusion_r1/experiments/raw_ingress_equiv/run.py --name <fresh_name> --td-root <TOOLS_ROOT>/TD_Release_2026.2.210.850`。
160 秒单臂 watchdog，TD 4 线程。每个 `RESULT.json` 包含命令、输入/输出 SHA 和原件。
这组数据支持方向筛选，收益量级不足以单独消除整机容量疑虑。 [实验与黑盒交接](../../../fpga_prj/verification_archive/experiments/raw_ingress_equiv/PUBLIC_CONTRACT.md)
· [原始运行](../../experiments/raw_ingress_equiv/runs/full_window_r1)

二轮相对已采用的五窗口叶，试测无异步复位的 CONTEXT 和 SOURCE payload。两组载体分别少
15/26 Slice、各少 1 FF，UHD count→DATA 门级余量下降 0.181 ns。节省有限且有映射取舍，候选保留在实验。
[二轮报告](../../../fpga_prj/verification_archive/experiments/raw_ingress_equiv/r2_payload_reset/README.md)

### 控制 FIFO 序列化

d1e5 的 `raw_job_ticket_context_cdc.u_forward` 有 569 logic LUT，固定 IP 子树约 58。
CFG 作业的 request/ack 分别 237/204，双成员 drain 的 request/ack 为 160/155。
共同的 `control_message_fifo_ip` 对 4/7/10 flit 的写出和装配使用乘 40 的动态切片。
同设置先测逐 flit 固定切片、单次解码和各 slice 独立 CE，保留原 40×512、消息寿命、完整消息
握手与停钟清空。如果宽度 375 的单个载体收益有限，再单测 ticket forward，将 128-bit tx_part
选择和 40-bit flit 选择合并为原 flit 顺序的 40-bit 直接选择，保持每条消息与旧接收端一致。
这里有数百 logic LUT 的局部优化空间，具体 Slice 和时序取同载体结果。冻结 DDR IP 树占 JPEG
存储 4,790 logic LUT 中的 3,539，现有 FIFO 行缓冲也已有 LUTRAM 映射，未把这些树计为可直接回收。
