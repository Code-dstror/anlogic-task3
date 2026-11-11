# 5bdca702 布线时序基线

工程 `camera_raw_r1`，源码 `5bdca7029b4aa9c6005ca67d89d045a92d4fc4a5`，请求 `camera-raw-fieldfix-20261108-syn16-48s4t`。用已登记的 `server/td/td.ps1 status` 刷新并固定结果提交 `4351bf0093314e6d3b169c987cb32d05502fbae1`。服务快照为北京时间 2026-11-09 08:30:51，读取时年龄 1210.6 秒。命令回执 ACCEPTED，原生读回为一次共享 SYN 16 线程、独立 PHY 每种子 4 线程。器件 PH1A90SEG324-2，TD 2026.2／6.2.3.210850。所有已分析的 PHY 均核对 `reused-from.json` 指向同一共享综合和源码。

固定快照有 46 个 PHY 到 bitgen 和重开 DONE，s77/s92 仍 RUNNING。37 个 bit 文件条目已完整发布。本次固定集合逐分块和整文件校验 613 份文件、1,051,083,090 字节，含 12 套物理报告和可得的共享综合证据。其余 36 个种子的报告分析保持 PENDING。综合详细时序、时钟树和完整 `run.logw` 等 8 项在该提交仍 PENDING。回传路径、逐文件哈希及各自缺项见 [制品索引](../../../../server/td/local/download/camera-raw-5bd-20261109/UPLOAD_INDEX.json) 和 [下载记录](../../../../server/td/local/download/camera-raw-5bd-20261109/COLLECTION.json)。

## 原生时序结果

12 套 `phy_1` 报告为 Routed，均启用快慢两角的 max/min，STA coverage 99.85%。每组最多 100 个端点、每端点最多 3 条路径。下表的分型裕量取可见路径，DDR min 单独取生效的 128 个 0.350 ns 检查。分型端点、真实数据网、源码行和双角可见最差值见 [BASELINE_5BD.json](BASELINE_5BD.json)。

| 检查 | 可见最小值范围（ns） | 负裕量种子 | 代表最差报告 |
|---|---:|---:|---|
| Setup | −0.702 至 −0.150 | 12/12 | s93 detail L17866，DFI 同沿，slow |
| 普通 hold | −0.080 至 +0.017 | 8/12 | s90 detail L10464，PIX 同沿，fast |
| Recovery | +2.059 至 +4.098 | 0/12 | s96 detail L193608，SYS→USER，slow |
| Removal | −0.046 至 +0.011 | 6/12 | s96 detail L10347，PIX 同沿，fast |
| DDR 写数据守卫 | −0.383 至 +0.023 | 2/12 | s43 exception L46226，DFI 同沿，fast |

| Seed | SWNS | STNS | HWNS | HTNS | 普通 hold | Recovery | Removal | DDR min |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 23 | −0.275 | −29.096 | +0.007 | 0 | +0.007 | +3.488 | +0.009 | +0.023 |
| 43 | −0.591 | −189.723 | −0.383 | −0.658 | −0.037 | +3.568 | −0.037 | −0.383 |
| 73 | −0.324 | −63.772 | −0.013 | −0.019 | −0.013 | +2.614 | +0.008 | +0.021 |
| 83 | −0.381 | −93.454 | −0.033 | −0.084 | −0.033 | +3.835 | −0.005 | +0.020 |
| 85 | −0.561 | −137.242 | −0.060 | −0.597 | −0.060 | +3.550 | −0.042 | +0.023 |
| 87 | −0.150 | −16.136 | +0.010 | 0 | +0.017 | +2.141 | +0.010 | +0.023 |
| 89 | −0.368 | −56.187 | +0.001 | 0 | +0.001 | +3.760 | +0.010 | +0.020 |
| 90 | −0.585 | −205.837 | −0.080 | −0.121 | −0.080 | +4.098 | +0.001 | +0.022 |
| 93 | −0.702 | −157.357 | −0.353 | −1.238 | −0.028 | +2.815 | −0.021 | −0.353 |
| 96 | −0.281 | −39.460 | −0.046 | −0.169 | −0.031 | +2.059 | −0.046 | +0.023 |
| 97 | −0.497 | −79.161 | −0.009 | −0.060 | +0.005 | +2.893 | −0.009 | +0.022 |
| 99 | −0.551 | −107.963 | −0.016 | −0.016 | −0.016 | +3.287 | +0.011 | +0.023 |

单位均为 ns。服务快照的 46 个 DONE 摘要有 46 个 SWNS 为负、39 个 HWNS 为负。摘要最佳的 s76/s80 SWNS 同为 −0.034 ns，HWNS 分别为 −0.013/−0.021 ns，详细路径仍待发布。已核验的 12 个物理结果时序 FAIL，服务器仿真和板级均为 NOT_RUN。此基线对应 R1，R2 当前的物理结果由 R2 新源码运行建立。

## 新报告指向的 RTL 路径

1. **DFI 模式解码到普通回放和 ticket。** s93 detail L17866 的 `o_active_config[194]_dup_1` 到 `u_ticket/source_fault` 为 −0.702 ns。中间真实网 `o_fault_reg_syn_5`／`o_fault_reg_syn_21` 扇出 365／237，分别见 detail L17913/L17916 与 `high_fanout.txt` L59/L90。6 级数据路径 7.765 ns，cell 1.317、net 6.448。相同配置位和扇出 365 的分支到普通回放 `state[0]` 为 −0.689 ns（L18172，cell 2.014、net 5.731），写回实际网来自 `raw_pair_replay_scheduler.v` L128。`[194]` 是紧凑 schema1 HDR 位，`[373]` 是 schema2 tag，经 `analysis_hdr_enabled` 和 `stereo_sdr_dfi` 进入普通回放选择。可见同族还由 `dfi_mode` 及 falling release 启动，终点包含回放状态、ticket 及 DDR 读路。缩短模式 decode 时，保持 CFG 成功同拍更新、失败保留旧 active、reset 初态、首个新模式事务和故障/取消顺序。当前源码的 `pair_mode` 在 pending 配置期间已可变，不能直接当作 active 资格。
2. **PIX 启动资格贯穿两眼 HDR gate。** 10/12 个种子见负路径。s93 detail L119 的 packed 起点 `u_jpeg/add7_syn_88.clk` 对应实际 `physical_pair_config_owner` 的 `owner_rst_n`，扇出 434（detail L157，`high_fanout.txt` L48）。它与 drain reset-done、bootstrap `operational` 相交，经 `cfg_source_ready/cfg_pause` 和 gate 的资格折叠到右眼 `o_source_error[3]`。−0.666 ns，9 级，cell 1.906、net 6.301。s43 −0.590 ns（L119）和 s90 −0.514 ns（L725）由不同的 joint drain release 网启动，汇合到同一资格链。另有 11/12 个种子见 HDR gate 其他事件负路径。s43 detail L9032 的 −0.557 ns 从左眼 event FIFO `read_head`／`s0_data[55]` 到 `source_error[2]`，cell 2.687、net 5.660。拆短新 FS 准入时须覆盖同拍停机/故障、首个合法 FS、迟到 peer 与已准入老组的终态。既有 watermark 切分后的另一路仍有 3/12 个种子可见负裕量，最差 s96 L3929 −0.229 ns。
3. **DFI falling release 到 RAW writer 组合资格。** 10/12 个种子见负路径。s43 detail L18061 的 `hdr_identity_reset_n_dup_109` 经 `dol2_axi_write_arbiter.v` L58 的 protocol fault 相关映射逻辑，到 `shared_raw_capture_writer.v` 的 `bad/state[1]`。3.751 ns 半周期预算，5 级，cell 1.362、net 2.679，裕量 −0.591 ns。s99 L17974 同族 −0.543 ns。该组是到 D/CE 的 setup。分离本域数据资格与 ASR 释放时，保留停钟下异步断言、最早合法采样边界和 ASR 的 recovery/removal。其他 DFI 半周期释放路径也需要独立检查。
4. **HDR bank 的年龄和描述符比较。** 8/12 个种子见 `bank_state` 负路径。s93 detail L20368 的真实 `now_ns[43]` 经 `hdr_eye_shared.v` L110 的高字/epoch 年龄核对，到 CAM1 `bank_state[11].ceb`，−0.651 ns，cell 1.989、net 5.937。s90 L18025 由 writer `o_frame[145]` 经相同 age 判定和 `CHECK_BEGIN` 的 bank 更新到 `bank_state[5].ceb`，−0.585 ns，cell 1.944、net 5.907。`write_data[4]_syn_11` 属打包后节点，真实条件须沿 `stamp_in_age` 至 bank allocation 核对。该族还见独立的目录写路径，s93 L21280 为 −0.648 ns。若在新 PHY 上仍限制时序，单独处理 age/描述符资格，保持真实接纳时刻、bank 并发释放重判和迟到 peer 合同。

## 与 R2 已采纳改动的关系

- `ordered_frame_egress` 的首 flit 解码和缓冲写使能切分覆盖了同模块的若干负路径，例如 s89 detail L18253 `kind[0]` 到 `start_context_match` 的 −0.284 ns。s43 L22288 的 −0.464 ns 从 `o_jpeg_tdata[28]` 到 `jpeg_frame_ring.v` 的 `result_good`，主要延迟在下游写结果链，仍需看 R2 PHY。
- `hdr_raw14_shared_transport4` 的 FENCE 资格和 `private_raw_isp_borrow4` 的未发布 SOURCE 结果写使能改动只切这两个终态边界。s43 detail L19096 的 −0.522 ns 是 DFI `source_local_rst_n` 到 scheduler `state[5]`，与 FENCE 比较的采纳改动是独立路径。PIX 前端 HDR gate 的 FS/source-error 也属于另一层。
- RGB adapter 的 reset-free 无效 payload 直接去掉 s85 detail L11295 的 `output_rgb_reg[55].asr` 对应载荷复位端点（−0.014 ns）。s97 L10428 的 `source_ok_reg.asr`（−0.009 ns）属于仍需复位的控制，保持计入 removal。四个改动的物理影响以新 PHY 为准。 [R2 已验证的改动](../../README.md)

## Min、约束覆盖与路由日志

- s90 普通 hold 从 RAW HDR ingress 的 `axis_data_reg[7]` 到官方 FIFO 的 `dia[6]`，实际直连数据网 `capture_fifo/source_word[7]`（detail L10464/L10502）。fast，cell 0.096、net 0.177、skew 0.158 ns。s96 removal 从 `u_jpeg_to_ddr/u_source_reset/release_pipe[2]` 到 ingress `frozen_result[24].asr`，实网 `u_ingress/i_rst_n_dup_1910`（detail L10347/L10385），cell 0.090、net 0.109、skew 0.054 ns。这两条本域路径各含 0.050 ns SDC hold uncertainty。s96 最小 recovery 从 SYS POR 经 `i_sys_rst_n` 到 USER reset synchronizer 的第一级 ASR，+2.059 ns（L193608/L193637）。保留本域检查与已留的 50 ps guard。 [时钟约束](../../fpga_prj/constraints/real_hdr_clocks.sdc)
- 128 个 DDR 目标在 12 套均有生效守卫。s43 负 bit229，s93 负 bit219/225/226/228。s43 exception L46226 的真实 `u_ddrppc/dfi_wrdata[229]` 为 frozen IP 内直达 PPC 的 0 级路径，报告 0.121 ns 数据延迟（cell −0.213、net 0.334）和 0.104 ns skew。按同一路由换算回旧 0.100 ns 守卫，最差仍为 −0.133 ns。DDR 冻结 IP 和当前 0.350 ns guard 均保持。
- `observer_cdc.sdc` 的 endpoint-only 32 ns max 将同域路径也纳入例外。s93 exception L18610 的 `ready_slot`→`dfi_flags_meta` 是 DFI→DFI，budget 32 ns，data 6.399 ns，打包后的 `dfi_flags_reg[7]` 是物理别名。L12770 同样证明 SYS→SYS 到 `sys_flags_meta` 的覆盖。同组的 `set_false_path -hold -to` 也没有来源域限定，需逐源限定真正异步输入，核对同域 setup/min 和复位负向控制。现有报告另见两个 flags 规则各 1 条被时钟组忽略，s93/s96 多一条 `reset_meta` 重叠。 [Observer 约束](../../fpga_prj/constraints/observer_cdc.sdc)
- CAM1 event FIFO 的两个 7.500 ns Gray pointer max 在 12 套均为每方向 9 条全 shadowed。s93 exception L632–647 指明实际生效的是原生通用 soft FIFO 7.700 ns 规则。按对象和原生优先级核对该 200 ps 差异及对应 path-skew，保持真实 CDC 边界。`held_profile[10]` 的 7.000 ns USER→PIX/DFI 仍有效。`check_timing` 对 SYS→USER observer `request_level[2]`→首级 `request_sync[0]` 的警告指向局部 32 ns 约束（s93 check L275–279）。保持其余同组路径独立核验。 [立体 CDC 约束](../../fpga_prj/constraints/stereo_cdc.sdc)
- 12 套无 no-clock、invalid/no-path constraint 或组合环，均有 38 input 和 57 output delay 缺项。`clock_tree.txt` 含 pin 拓扑及双角 latency，原生 PCIe CORE/USER 均为 125 MHz，原始 `USR-6144` 仍记录 62.5/125 MHz 请求值与实际值差异。该项和两眼 MCLK 的 `PHY-5060/5031`、DDR GCLK 级联 `CLKST-5093` 分开保留。`PHY-5010` 多为 0 输入或输出的映射网跳过，不能凭其别名把实际存活的 bank 路径归为缺线。 [原生日志索引](BASELINE_5BD.json)
- 物理参数读回 `fix_hold high`、`hold_fix_iteration 10`、`post_route_opt ultra`。s93 路由迭代初始 overflow 362804（routing `run.log` L438），随后到 0（L487）。`fix_hold` 遇到 ASR 路由 DRC 回退（L922 起），最后一轮仍 −353 ps（L1009）。s43 最后 −383 ps（L1036）。因此已有 min repair 仍留下守卫/本域负路径。Routed Slice 61,980～62,120／64,320，仅用于说明连线余量与变更成本。
