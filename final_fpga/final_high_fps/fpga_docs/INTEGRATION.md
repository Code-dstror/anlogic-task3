# 输入与合入映射

| 固定输入 | 用途 |
| --- | --- |
| `camera_rate_r3` `5914a5b22e09c4f9d4fbf1186ee32d1bf8940c592fce6e5a525f8b4cb5abeeb5` | 原生工程、冻结 IP、物理与速率参数、1080P 双目 40/45/48 及 4K15/20 生产骨架 |
| `camera_hdr_quality_r1@7dde99e738a48ec5b399a9cf965f7fd7a47ca8c2` | 平衡融合、四页 Tone、渐进高光保护、手动 WB、schema2 配置与 SDK |
| `camera_raw_r2@1a5603c1c8aa58565aa9b5facf40a7478ebcf6ba` | 画质分支的共同来源。核对 DDR 预取、双像素、HDR 首事务、排空和 CFG 现场观察语义 |

## 交叉合并

| 接口 | 处理 |
| --- | --- |
| `hdr_merge4`、`hdr_pair_pixel_reader`、`hdr_pair_native_source_service4` | 保留四路 MAC 与两段乘加寄存器。作业 START 锁存融合预设。平衡模式对孤立弱残差与可信短曝判定沿用画质候选。原读取预取与收尾时序保持。 |
| `hdr_tone96_shared4`、`wide_color_pipeline`、`shared_wide_isp` | 四页 ROM 地址、扩展增量、Q14/Q16 和高光权重对齐至两条 Tone 算术 lane。保留先选择窗口后舍入，以及算术推进与有效资格分离。 |
| `anlogic2026`、`real_hdr_camera_observe_axis`、`physical_camera_rgb_pipeline`、`private_raw_isp_borrow4` | 采用速率骨架的 HD/UHD 实际尺寸、RAW 位宽与回放选择。PIX 真正接受 RAW SOF 时冻结 WB 和 Tone，DFI 作业冻结融合预设。 |
| `mono_config_*_v2`、`mono_config_transport_v2.vh` | 仅扩展 schema2 W1 和 W12。沿用 32 字 USER SHADOW/ACTIVE、两条原 FIFO、374 位紧凑元组与完整身份/epoch ACK。UHD 仍为 CAM0 SDR，新增手动 WB。HDR、去雾与车道仍按原几何资格。 |
| `rk_sdk` | 合并 UHD 几何/RAW 校验与质量控制发现、参数目录、打包和旧字段默认。旧 UHD bit 原能力字仍可被融合 SDK 接受。原 R3 SDK 的 UHD 精确能力匹配不识别 bit 6，须随工程升级。 |
| `camera_field_diagnostics`、`uart_status_observer`、`observer_cdc.sdc`、`tools/uart_observer.py` | DJ/v4 保留旧 v3 CFG 页语义并追加 v2 双眼 FS。PIX→SYS 保持原四相快照及约束端点，数据银行各增加 32 位。四个保留字节为常量。 |

4K DDR 地址、槽容量、RAW 紧密打包和 JPEG DC 门/MCU 行预取继续使用速率候选输入。
ADC 和业务 SDC 保留原源。UART SDC 延续已限定的单个 PIX bank 到 SYS bank，覆盖追加的计数位。
两张 Tone MIF 来自画质封印，其余 `src_fpga/ip` 文件与速率封印逐字节一致。

## 资源与验证边界

速率骨架的父候选 raw gate 报告为 64,009/64,320 Slice、259/272 ERAM、146/240 DSP。
不同载体中 Tone 双像素、预取、配置、画质和 UART 数据银行的增量不可直接相加。
融合路径的主要代价为双 lane 高光乘法、宽系数算术、紧凑 CFG 快照的字段选择和 UART 追加银行。
资源余量、物理 setup/hold/recovery/removal、满幅高熵吞吐、持续帧率和真实传感器画质待对应证据。
