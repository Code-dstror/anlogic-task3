# RK HDR 画质控制

`camera_fusion_r1` 通过现有 CFG1/schema2 的 PREPARE_EXT、COMMIT 和 APPLIED 应用画质配置。RK SDK 在 `caps` 的 `schema2.quality_version` 报告现场能力，在 `parameters.schemas["2"]` 列出可用字段。`active` 回读当前 session、epoch 和完整快照。HD 使用既有 `python -m linux.rk_debug shell --shared-camera mono|dual` 入口，4K JPEG 使用 [UHD 冷选与 CFG](UHD_RK_CONTROL.md)。

| `extension` 字段 | 允许值 | 生效条件 |
| --- | --- | --- |
| `quality_version` | 0 或 1 | 0 要求本表其余字段全零。1 启用画质字段合同 |
| `hdr_tone_preset` | 0 平衡、1 旧曲线、2 明亮、3 高光 | HDR，且 `quality_version=1` 时可提交显式预设 |
| `hdr_fusion_preset` | 0 平衡、1 旧融合 | HDR，且 `quality_version=1` 时可提交显式预设 |
| `isp_wb_enable` | 0 默认、1 手动 | SDR 或 HDR。手动要求 `quality_version=1` |
| `isp_wb_r`、`isp_wb_g`、`isp_wb_b` | 手动时各 1–1023；默认时各 0 | 共享 Q8 乘数，256 表示 1 倍 |

本候选对旧 schema1、旧 schema2 HDR 快照采用改良后的平衡 Tone 与融合。需要重现旧算法时，在 HDR 下明确选择 Tone 1 和 Fusion 1。关闭手动白平衡时回到原工厂值与 UART 调节路径，出厂 R/G/B 分别为 909/410/832。手动模式在同一 epoch 对两眼使用相同系数。传感器的 HDR ratio 4、black 50/50 和资格掩码 15 沿用固定配方。

在现有 HDR schema2 会话中选择高光优先并更新白平衡。`configure` 对同 schema 的补丁保留省略字段。

```text
configure {"extension":{"quality_version":1,"hdr_tone_preset":3,"hdr_fusion_preset":0,"isp_wb_enable":1,"isp_wb_r":864,"isp_wb_g":410,"isp_wb_b":784}}
active
status
```

`active` 应显示新 epoch 和精确请求值。等 `status` 的 `camera_mode.seen_cameras` 包含当前拓扑的所有眼后再提交下一次切换。`mode hdr` 使用 `--shared-hdr-policy` 文件，可在原 HDR 策略中提供本表字段。未提供时用默认值。`mode sdr` 使用默认白平衡，手动调整可以随后通过 `configure` 提交。原完整 JSON 在首次切入 schema2 时省略本表字段即可保持旧编码。

恢复旧编码可以清零所有画质字段。

```text
configure {"extension":{"quality_version":0,"hdr_tone_preset":0,"hdr_fusion_preset":0,"isp_wb_enable":0,"isp_wb_r":0,"isp_wb_g":0,"isp_wb_b":0}}
```

HD 的旧 SDK 在新 bit 的 BOOT 或画质字段全零的 ACTIVE 上仍可使用。启用画质设置后换回旧 HD SDK 前，先由新 SDK 应用全零画质字段或重新 BOOT。原 R3 SDK 对 UHD 能力字做精确比较，使用融合 4K 时需换成本文配套 SDK。融合 SDK 可识别旧 4K 能力字，显式画质配置会在 PREPARE 之前按实际能力判定。

## 线协议与生效边界

原 CFG_FEATURES 寄存器新增 bit 6。原 CFG_EXT SHADOW 与 ACTIVE 仍各 32 字。schema2 W1 的低 30 位按 R/G/B 各 10 位排列，bit 30 为 WB 使能，bit 31 保留。W12 bits 1:0 为 Tone，3:2 为融合，7:4 为版本，31:8 保留。其他字段和 schema1 使用原定义。编译能力关闭的对照载体沿用父配置发现与拒绝行为；新工程支持能力时，全零画质字段选择新默认。

配置走现有 USER 到 PIX 和 PIX 到 DFI 的 FIFO，按旧事务合同排空并完整回 ACK。PIX 共享 ISP 在实际接受 RAW 帧首时冻结 WB 和 Tone 页，DFI 融合读取器在接受 HDR 作业 START 时冻结融合预设。完整 32 字快照与对应 epoch 一起发布。业务记录以原 epoch 标识应用的配置。

[增量字段定义](quality_control_v1.json) · [继承线协议](pcie_protocol_v1.json) · [SDK 装载](../fpga_src/rk_sdk/README.md)
