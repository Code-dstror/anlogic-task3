# camera_fusion_r1 五个放置种子的基线

固定源 `eade457d7477110605f90eb5abc08420d8936642` 的种子 1–5 均完成放置。整机使用 **62,024–62,175 / 64,320 Slice（96.43%–96.67%）**、265 / 272 ERAM 和 149 / 240 DSP。放置阶段的最差 setup 均为负，最差路径来自同一 PIX 下降沿释放信号。布线、最终 STA、比特流与板级资格需要各自的同源结果。[逐种子原始索引](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/AVAILABLE.json) · [机器可读数据](PLACED_BASELINE.json)

## 源与阶段

- 回传快照固定为 `6298a331867fd6bdd818c7ef70c79032b4b768c4`。五个 `spec.json` 均指向同一生产提交、原生工程 `rfcamera_fusion_r1.al` 和 `manual-camera-fusion-r1-20261110-syn4-20s4t-caed505cb11ebaab-syn` 共享 SYN4 检查点。实际放置日志逐种子读到 `set_param place seed N`、`Placer runs in 4 thread(s)`、`finish command "place"`，随后执行 `update_timing -mode manhattan` 和 `report_area`。TD 为 `6.2.3.210850`，器件 `PH1A90SEG324-2`。[固定提交回执](../SERVER_BUILD_20261110.md) · [种子 1 原始放置日志](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s1/stage-logs/placement/phy_1/run.log)
- 五份回执各包含 7 个所选文件。逐件复核完整字节数及 SHA-256 与同一 `ARTIFACT_INDEX.json` 一致。分析使用本种子 `phy_1` 报告。时序标题均为 `Confidence=Placed`，约束文件列出的四份 SDC 路径指向同源 SYN 检查点目录。`*_phy.area` 按放置日志绑定为 **Placed**，剩余 2,145–2,296 Slice 和 7 ERAM 也是此阶段口径。[下载回执 1](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s1/DOWNLOAD.json) · [2](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s2/DOWNLOAD.json) · [3](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s3/DOWNLOAD.json) · [4](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s4/DOWNLOAD.json) · [5](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s5/DOWNLOAD.json)

## 同阶段对照

时序单位为 ns。LUT6、FF 分别取面积报告的 `#lut6`、`#reg`，Slice 取 `#slice`。Recovery 列仅取实际展开的最小路径。每个路径组最多展开 10 个端点，每端点 1 条路径。虽然报告头列出两个角和 `HWNS/HTNS=0.000/0.000`，五份 `Min Paths` 都为空，未报告 hold/removal 的可用最小值。99.85% 是报告给出的 coverage。[原始时序示例](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s1/checkout/refactor/camera_fusion_r1/fpga_prj/rfcamera_fusion_r1_Runs/phy_1/rfcamera_fusion_r1_place.timing)

| 种子 | Slice | LUT6 | FF | ERAM | DSP | Setup WNS / TNS | Setup 违例端点 | Recovery 最小已报 | Hold / Removal | 拥塞 >100% 网格 / 区域 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| 1 | 62,024 | 57,846 | 71,871 | 265 | 149 | −2.024 / −285.210 | 573 | +4.074 | 未报告 / 未报告 | 272 / 21 |
| 2 | 62,124 | 57,876 | 71,885 | 265 | 149 | −1.418 / −131.432 | 231 | +1.154 | 未报告 / 未报告 | 115 / 22 |
| 3 | 62,175 | 57,808 | 71,871 | 265 | 149 | −1.208 / −98.105 | 305 | +3.606 | 未报告 / 未报告 | 293 / 19 |
| 4 | 62,111 | 57,830 | 71,895 | 265 | 149 | −1.808 / −175.447 | 257 | +1.390 | 未报告 / 未报告 | 343 / 19 |
| 5 | 62,099 | 57,874 | 71,851 | 265 | 149 | −1.552 / −175.273 | 270 | +1.374 | 未报告 / 未报告 | 268 / 19 |

`place.qor` 五次均报 `QOR-1201` 裕量不足、`QOR-4001` 高拥塞、`QOR-4004` 拥塞区域。种子 2 和 5 另报 `QOR-2201` 关键高扇出网。五份 `run.logw` 均含 `PHY-7022` 的 95% 阈值告警、`PHY-5054` 的 `sys_clk_dup_1` 混合时钟负载，以及两条 `PHY-5060` 的 CAM MCLK 输出候选告警（各 0 时钟负载、1 个输出 pad 控制端）。`CLKST-5093` 定位到受控 DDR IP 内的 GCLK 级联。`PHY-5010` 是本轮优化后无输入或输出的跳过网。`TMST-7700` 每种子均报 4 项 severe constraint issue，选取的材料缺 `check_timing` 细目及最终例外／ignored 报告，具体四项和物理覆盖待判。[种子 2 QoR](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s2/checkout/refactor/camera_fusion_r1/fpga_prj/rfcamera_fusion_r1_Runs/phy_1/place.qor) · [种子 1 放置告警](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s1/stage-logs/placement/phy_1/run.logw)

## 重复出现的两族 setup 路径

| 种子 | PIX F3 → R4，4.000 ns，最差终点或真实末网 | 裕量 | cell / net 延迟 ns | DFI F3 → R4，3.751 ns，最差终点 | 裕量 | cell / net 延迟 ns |
| --- | --- | ---: | ---: | --- | ---: | ---: |
| 1 | CAM0 RAW ingress `axis_data[127]` | −2.024 | 1.628 / 4.138 | JPEG token FIFO read RAM `.ceb` | −0.327 | 0.503 / 3.326 |
| 2 | CAM0 RAW ingress `axis_data[114]` | −1.418 | 1.506 / 3.654 | HDR owner `clear_slots[0]` | −0.293 | 1.661 / 2.125 |
| 3 | CAM0 RAW ingress `axis_data[10]` | −1.208 | 1.740 / 3.210 | HDR owner `clear_slots[6]` | −0.604 | 1.851 / 2.246 |
| 4 | 实网 `o_raw_source_error[2]`，物理名 `context_q_reg[289]` | −1.808 | 1.422 / 4.128 | SDR replay scheduler `state[0]` | −0.071 | 1.665 / 1.899 |
| 5 | CAM0 RAW ingress `axis_data[19]` | −1.552 | 1.367 / 3.927 | JPEG token FIFO read buffer `.cea` | −0.110 | 0.674 / 2.938 |

**PIX** 每份报告的本域前十条 setup 路径均从 `g_private_processing$u_original_source/u_pixel_reset` 的 `released_n` 副本发射。最差路径有 8–10 级逻辑，net 占数据路径约 65%–74%。种子 1 的真实网从 `u_original_cleanup/rst_n_dup_1552`（`hdr_pair_product_abort_drain4.v:9`）经过 fence 与 capture FIFO 的组合别名，进入 `shared_raw10_frame_ingress.v:349` 选择以及 `:303` 的 `axis_data_next`。同一路径出现 `frame_sequence[7]_syn_10`，无整包 ACK 比较在途的证据。种子 4 末网明确为 `physical_identity_source_fence.v:30` 的 `o_raw_source_error[2]`。其物理端点名由打包产生。精确起止点、行号和各 seed 数据见 JSON。[种子 1 第 119 行](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s1/checkout/refactor/camera_fusion_r1/fpga_prj/rfcamera_fusion_r1_Runs/phy_1/rfcamera_fusion_r1_place.timing) · [种子 4 第 119 行](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s4/checkout/refactor/camera_fusion_r1/fpga_prj/rfcamera_fusion_r1_Runs/phy_1/rfcamera_fusion_r1_place.timing)

```text
s1 PIX slow setup, slack -2.024 ns, budget 4.000 ns
g_private_processing$u_original_source/u_pixel_reset/g_falling_release$released_n_reg_syn_20.clk
  -> g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/ingress/axis_data_reg[127]_syn_2.imb
```

**DFI** 五份报告本域最差均从 JPEG ring owner 的 F3 `released_n` 副本发射。种子 1/5 的数据网由 `jpeg_frame_ring.v:18` 的 `i_rst_n` 经 `ordered_frame_egress.v:20` 的 `o_token_ready`，到实际 token FIFO RAM CE 或读缓冲资格。种子 2/3/4 的数据网含 `full_raw_store.v:98` 的 `i_pair_product_quiet`，TOP 将其接到 `hdr_writer_quiescent`，来自 ring 对真实已承诺写入的静默证明。种子 2 还报告此释放到 JPEG `slot_state` CE 的 +0.019、+0.037 ns。种子 3 最差有 7 级，cell/net 为 1.851/2.246 ns（45%/55%）。[种子 1 第 1879 行](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s1/checkout/refactor/camera_fusion_r1/fpga_prj/rfcamera_fusion_r1_Runs/phy_1/rfcamera_fusion_r1_place.timing) · [种子 2 第 1102、1198 行](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s2/checkout/refactor/camera_fusion_r1/fpga_prj/rfcamera_fusion_r1_Runs/phy_1/rfcamera_fusion_r1_place.timing) · [种子 3 第 1123 行](../../../../server/td/local/download/camera-fusion-eade-placed-20261110/s3/checkout/refactor/camera_fusion_r1/fpga_prj/rfcamera_fusion_r1_Runs/phy_1/rfcamera_fusion_r1_place.timing)

```text
s3 DFI slow setup, slack -0.604 ns, budget 3.751 ns
u_ddr_store/g_ring_store$u_record_owner_reset/g_falling_release$released_n_reg_syn_5.clk
  -> g_s04$u_raw_service/g_cam1_hdr$shared_owner/clear_slots_reg[6]_syn_2.ima
```

这两族是融合骨架给 RAW→ISP 原始源与 JPEG ring owner 增加 F3 ASR 接线后的**数据资格回授**风险。报告的检查类型为 setup，终点为数据／CE。参考 `1a5603c1` 已修复的 `private_rgb_source_borrow4`（`u_source_events`）、JPEG 源侧 `ordered_frame_cdc/ingress` 及 DFI 写仲裁/ARAW 的 R3/F3 分离已通过静态保留审计。融合需要额外处理上述两个 F3 回授锥。PIX 仍有 SOURCE 资格数据热点，DFI 仍有 HDR slot 管理和写静默热点。按已展开路径无法把热点归于迟到 SHORT、水印、匹配 whole ACK、Tone 或 HDR cursor。DDR 128 条 min guard 和原同域 min 检查的有效匹配须由布线结果核实。[静态修复保留](FIX_RETENTION.md) · [时钟和 min guard](../../fpga_src/constraints/real_hdr_clocks.sdc)

## JPEG 熵核对照和后续切口

五份报告有 `u_jpeg/u_entropy` 的 packed LUT 别名和 coefficient bank DRAM period check。可识别的熵层次 setup 条目分布在其他路径组，最小的 +6.487 ns 条目是零逻辑级、CFG 排空 FIFO Gray 指针起点。逐路径数据网未找到可归因于 JPEG READY 或 `reservoir` 的展开路径。top-N 截断限定了这个结论。独立黑盒通过的 `coarse64` 使用 `jpeg_entropy.v` SHA-256 `c6f2e10a8208e500c98154d3e7647f2d4d11a8ed3e7df9fd1f94a09b488a77c7`。真实返回组合关系的 SYN4 载体重开减少 242 Slice，整体 setup 估计 +2.356→+2.384 ns，返回到储备 D 的最差 +4.054→+3.967 ns。按面积收益评估这一改动，完整工程的 READY、面积、放置和时序由新源结果衡量。[熵核面积和定向路径](AREA_RESULTS.md) · [独立黑盒](BLACKBOX.md)

1. **优先隔离 PIX 原始源的数据资格**。以 `private_raw_isp_borrow4.v:51,85,112–113,139–146` 为入口。`o_payload_enable` 经 TOP `anlogic2026.v:1900` 到 `physical_camera_rgb_pipeline.v:216–228` 的 replay 首拍／crop ready 仲裁。另核对 `i_processing_reset_n` 驱动的本地清理。先对照实际 F3 回授锥，看能否复用 R3 数据级以缩短 D/CE 路径，同时保持 F3 ASR、同步 `applied_clear` 与 R4 首个合法握手。比较同载体 Slice 和两个目标锥，按合法首帧、在途反压、停钟复位、取消/排空及下一事务验证。[原始源](../../fpga_src/rtl/private_raw_isp_borrow4.v) · [真实共享 ISP 调用者](../../fpga_src/rtl/physical_camera_rgb_pipeline.v)
2. **单独隔离 DFI ring 数据资格**。从 `ddr3_jpeg_store.v:466–474` 的本地释放和 `jpeg_frame_ring.v:328,478,494–500` 的 quiet、START、DATA、RESULT 资格定位。采用与其他 DFI 数据资格相同的 R3/F3 思路时，验证两个回授终点族及 ring 自己的 slot CE。保留从真实 B 到 READY、FENCE/RESULT、匹配 SAFE/ACK 和准确归还，以及 STOP/CFG/故障全局排空。两个候选分别对照，保留频率、相位和 128 条 DDR min guard。[DDR ring 包装](../../fpga_src/rtl/ddr3_jpeg_store.v) · [JPEG ring](../../fpga_src/rtl/jpeg_frame_ring.v)
