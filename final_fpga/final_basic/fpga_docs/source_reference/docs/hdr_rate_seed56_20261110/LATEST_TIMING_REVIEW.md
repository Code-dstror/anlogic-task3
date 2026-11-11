# seed56 HDR 修复冻结前的增量时序复核

本次回传索引为 `50270e824a8a8be9cc65db873c2a86f9fa97c946`，物理报告源码仍是 `41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213`。项目为 `rfcamera_raw_r2.al`，器件 PH1A90SEG324-2，TD 2026.2.210.850，共享 SYN16、PHY4。已有 48 个原生 `phy_1` 摘要、39 份 detail、40 份 final。缺路径为 seed 2、6、7、9、12、13、18、20。seed20 的摘要 SWNS/HWNS 为 −0.729/−1.082 ns，仍缺足以定位端点的最终路径。以下使用 Routed、Slow/Fast 两角，优先 detail，缺 detail 时用 final。端点数量受原生报告截取和显示精度限制。 [回传库存](../../../../tmp/parameter_timing_41cb_20261110/latest_50270e82/REPORT_INVENTORY.json) · [原 setup 评估](../../../../tmp/parameter_timing_41cb_20261110/SETUP_ASSESSMENT.md) · [原 min/约束评估](../../../../tmp/parameter_timing_41cb_20261110/HOLD_ASSESSMENT.md)

48 个摘要的 SWNS 为 25 负、6 显示零、17 严格正。HWNS 为 35 负、13 严格正。所有严格正的摘要均 ≤50 ps，两项均严格正仅 seed 26、56、92。40 个路径样本的普通检查中，21 个有负 setup、24 个有负数据 hold、17 个有负 removal，未见负 recovery。负 setup 均为 PIX/DFI 同域，负数据 hold 均为 PIX 同域，负 removal 为 PIX 或 USER 同域。40 个样本各自至少有一条正且 ≤50 ps 的 setup、hold、removal 路径。另有显示零的路径，保留三位小数口径。 [统计及代表路径](LATEST_TIMING_PATHS.json)

## 新增报告的四项最小值

补入 detail 的 13 个 seed 与只新增 final 的 seed32，单位 ns。`0*` 表示报告舍入到零。

| Seed | Setup | Hold | Recovery | Removal |
|---:|---:|---:|---:|---:|
| 23 | +0.008 | −0.042 | +2.824 | +0.004 |
| 25 | +0.008 | −0.070 | +2.832 | +0.009 |
| 26 | +0.002 | +0.014 | +3.441 | +0.020 |
| 28 | 0* | +0.020 | +2.443 | +0.013 |
| 29 | −0.218 | −0.018 | +1.988 | +0.020 |
| 31 | −0.079 | −0.039 | +0.051 | +0.020 |
| 32 | +0.007 | +0.007 | +2.912 | −0.021 |
| 34 | −0.017 | +0.020 | +2.949 | +0.020 |
| 37 | −0.180 | −0.022 | +1.315 | −0.022 |
| 39 | −0.060 | −0.014 | +2.403 | −0.032 |
| 40 | −0.327 | −0.024 | +2.589 | +0.002 |
| 42 | −0.138 | +0.010 | +2.346 | +0.020 |
| 46 | +0.004 | +0.011 | +1.687 | −0.049 |
| 47 | 0* | −0.124 | +2.305 | −0.021 |

## 与既有路径的关系

- 既有重复组仍占主导。PIX F→R SOURCE 数据资格匹配 29/40 个采样种子，其中 17 个负。DFI JPEG token FIFO 读头反馈匹配 17/40 个，其中 7 个负。后者增加 seed31/37/39 的 −0.044/−0.091/−0.026 ns 实例，仍是 DFI 整周期反馈。现有 JPEG ingress 复位拆分对应源侧 removal，与该 DFI 反馈是两段。另有 RAW ingress/CFG APPLY、HDR bank owner 重现，例如 seed42 的 CFG→RAW ingress −0.138 ns 与 seed46 的 DFI 时间→owner +0.004 ns。此处取 detail 优先，不能与旧 final 优先的 30 seed 计数直接相减。 [新增样本](LATEST_TIMING_PATHS.json)
- seed40 新见 PIX **R→F**，ticket 的实际数据路径经 `private_processing_selected` 到 `u_original_cleanup.clear_active`。最差 −0.327 ns，4.000 ns 预算，数据 3.995 ns（cell 0.924、net 3.071），`private_processing_selected` 扇出 450、其中一段 2.179 ns。40 份报告在 ≤50 ps 阈值下只采到这个 seed 的同族端点。SOURCE F3→R 改动不能充当此方向的物理验证。 [seed40 D:119](../../../../server/td/local/download/camera-raw-r2-41cb-selection-20261110/seed40/checkout/refactor/camera_raw_r2/fpga_prj/rfcamera_raw_r2_Runs/phy_1/controller-reports/timing_detail.rpt#L119)
- 少量整周期路径补见共享 ISP row-window→清理/准入→`job_restart`，seed37/39/88 分别 −0.180/+0.019/−0.120 ns。DFI HDR response `RLAST` 经过 formatter/产品控制到 `u_ddr_to_pcie`，seed39 −0.060 ns、seed40 +0.018 ns。以数据段的 `m_axi_rlast`、formatter 及 `remaining_beats` 端点归类，packed 邻接单元名不代表新的 CDC。两组列入 B2、Tone2 合入后新路由的定点复查。 [seed37 D:119](../../../../server/td/local/download/camera-raw-r2-41cb-selection-20261110/seed37/checkout/refactor/camera_raw_r2/fpga_prj/rfcamera_raw_r2_Runs/phy_1/controller-reports/timing_detail.rpt#L119) · [seed39 D:17026](../../../../server/td/local/download/camera-raw-r2-41cb-selection-20261110/seed39/checkout/refactor/camera_raw_r2/fpga_prj/rfcamera_raw_r2_Runs/phy_1/controller-reports/timing_detail.rpt#L17026)
- 负 min 保留已见类型。相机 capture FIFO 写侧有 seed25 −0.070、seed31 −0.039，RAW replay 读侧 seed47 −0.124，capture reset removal seed39/46 −0.032/−0.049。补见 seed23 的 PIX preprocess boundary −0.042 以及 seed37/40 的 JPEG MCU RAM 写端 −0.022/−0.024。seed31 还补出 +0.051 ns 的 **recovery**，实际目的为 DCP DSP `rst[0]`，数据段从 F21 terminal context 经 observer/restore 的映射网，8.000 ns 预算。这比原采样的 USER recovery 最小值更薄，严格在 50 ps 阈值之外。 [seed31 D:9221](../../../../server/td/local/download/camera-raw-r2-41cb-selection-20261110/seed31/checkout/refactor/camera_raw_r2/fpga_prj/rfcamera_raw_r2_Runs/phy_1/controller-reports/timing_detail.rpt#L9221) · [min 逐 seed 记录](LATEST_TIMING_PATHS.json)

## 严重告警与本轮判断

- 新核对的 14 份 placement/routing/terminal `phy_1` 告警仍为既有类别。`PHY-5060` 涉及 MCLK 非时钟负载，7 个种子路由另见 `PHY-5031` 区域资源。`USR-6144` 是 PCIe core/user PLL 的 62.500 对 125.000 MHz 诊断，`TMST-7700` 汇总 5 项 SEVERE。`check_timing` 均为 0 无钟、0 invalid、0 combinational loop、0 no-path。12 份有 4 项 shadow/ignored，seed32/42 的第 5 项均为既知 UART `reset_meta` shadow。这里保留严重诊断及其覆盖义务，不把汇总行当成新故障类别。 [seed25 路由告警](../../../../server/td/local/download/camera-raw-r2-41cb-selection-20261110/seed25/stage-logs/routing/phy_1/run.logw) · [seed42 约束检查](../../../../server/td/local/download/camera-raw-r2-41cb-selection-20261110/seed42/checkout/refactor/camera_raw_r2/fpga_prj/rfcamera_raw_r2_Runs/phy_1/rfcamera_raw_r2_chk.timing#L304)
- 14 份补核 exception 报告的 DDR DFI `0.350 ns` 写数据 SMD 每份 128 路，均为正，逐 seed 最小在 +20 至 +24 ps。最薄余量仍需保留逐 bit 检查。已下载路由日志中 `TMST-5089` 仍仅 seed20，涉及 1 条无共同主时钟的路径被跳过。缺端点时不能把摘要 −1.082 ns 归给该告警，也不能据此扩大例外。 [seed31 DDR min](../../../../server/td/local/download/camera-raw-r2-41cb-selection-20261110/seed31/checkout/refactor/camera_raw_r2/fpga_prj/rfcamera_raw_r2_Runs/phy_1/controller-reports/timing_exception.rpt#L40957) · [seed20 路由告警](../../../../server/td/local/download/camera-raw-r2-41cb-selection-20261110/seed20/stage-logs/routing/phy_1/run.log#L864)

增量证据明确新增了需要复查的旧路由端点，尚无足以要求冻结前再改生产 RTL、IP 或约束的同源结论。按已验证的 SOURCE/JPEG 与 reader B2、Tone2 候选进入本轮 SYN16＋48 PHY4 full，回传后按新源分别核对四项检查、≤50 ps 余量、SMD 和覆盖。旧 `41cb5991` 报告对新源物理资格为 STALE。本次只读复核的生产综合、P&R、板级均为 NOT_RUN。
