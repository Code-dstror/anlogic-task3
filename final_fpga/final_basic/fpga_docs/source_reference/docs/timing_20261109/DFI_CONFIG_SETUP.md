# DFI 配置模式到回放调度与票据

`5bdca7029b4aa9c6005ca67d89d045a92d4fc4a5` 的 seed93 Routed `phy_1` 详细报告 L17866 为 DFI 同上升沿 slow setup，周期 7.502 ns，裕量 −0.702 ns。真实数据网从 `o_active_config[194]_dup_1` 经 `o_fault_reg_syn_5` 和 `_syn_21` 到 ticket `source_fault`，后两网扇出分别为 365、237。6 级路径延迟 7.765 ns，逻辑和连线分别为 1.317、6.448 ns。L18172 同一起点到普通回放 `state[0]` 为 −0.689 ns。L17910–L17932 的时钟与数据网表明两个 `o_fault_reg_syn_*` 中间网都是组合映射。报告 SHA256 为 `1087caa339e2d0bd83abea961bc1d4cfcaca3114f368758c74d4f1ffea81a24c`，同源其他种子和 min 结果见 [5bd 基线](BASELINE_5BD.md)。

`o_active_config[194]` 是紧凑旧 schema 的 HDR 位。紧凑 schema2 由 tag 和产品模式判定 HDR。原 TOP 在每次 DFI 使用时从已提交的配置解码，之后与本域独立的 stereo/raw 冷选合并，进入普通回放和 HDR 的选择与 owner 活动判断。

R2 在 `frame_job_config_cdc` 上增加一个 DFI 活跃 HDR 位。它只在真实 CONFIG 成功沿与完整 ACTIVE tuple、session、epoch 一起发布。其复位和 ACTIVE tuple 同源。TOP 的 DFI HDR/SDR 选择、writer HDR 资格及观测使用该位，cold stereo/raw 条件仍作为本域独立输入。 [提交沿](../../src_fpga/rtl/frame_job_config_cdc.v) · [TOP 接线](../../src_fpga/rtl/anlogic2026.v)

新的启动点前移到模式判定寄存器。原 365/237 扇出控制及长连线仍需用新物理报告判断。R2 这项目前仅做静态连接和 diff 检查，独立功能结果单独记录。隔离载体综合、整机综合、P&R、物理时序、bitgen、板级均为 NOT_RUN。 [公开功能合同](DFI_CONFIG_PUBLIC.md)

seed90 L18025 的 −0.585 ns 是另一条 DFI 同域 setup。CAM1 writer 的 `o_frame[145]` 属 `stamp[31:0]`，经 `hdr_eye_shared.v` 中 `stamp_in_age` 的低字 `<= now_ns[31:0]` 和分配条件到 bank_state CE，7 级，cell 1.944 ns、net 5.907 ns。L18117 的实际网 `stamp_in_age_n6` 将比较结果送入该链。seed93 同模块的 `now_ns[43]` 还通过高字判定。两者检查的合法区间是 `(now-max_age, now]`。`now_ns` 可在任一 DFI 周期更新。首次 BEGIN 判定和同拍 RELEASE 触发的重判分别使用各自判定沿的时间。这条路径独立跟踪。 [详细种子路径](BASELINE_5BD.md)
