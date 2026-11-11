# camera_fusion_r1 整机容量预算

当前生产采用 RAW10 五窗口叶 `8569d769` 和等价色彩叶 `54f2c7e0`。两项均有源绑定独立黑盒，
色彩还经真实共享 ISP 和 3840×4 SDR 短帧验证。原生 `read_design` 和同 AL 重开通过。
下表是 TD 6.2.3.210850、PH1A90SEG324-2、原有面积优先流程下的工程预算。
范围来自后文列出的情景输入及历史装箱幅度，未经过整机测量或统计抽样，实际映射可超出。
[独立功能记录](../../blackbox/datapath/README.md) · [原生读取日志](../../tmp/native_read_a1/td.log)

| 阶段 | Slice / 64,320 | LUT 统计 | FF / 128,640 | ERAM / 272 | DSP / 240 |
| --- | ---: | --- | ---: | ---: | ---: |
| 原始 `opt_gate` | 约 64,100–65,000 | 约 80,200–82,700，`#lut` | 约 70,800–71,500 | 265，实例预算 | 149，实例预算 |
| 原生 `syn_1` 重开 | 约 63,500–64,400 | 约 78,500–81,000，`#lut` | 约 70,800–71,500 | 265，实例预算 | 149，实例预算 |
| 路由完成后的条件估算 | 约 62,000–63,600 | 约 57,000–59,400，`#lut6` / 64,320 | 约 71,500–72,400 | 265，实例预算 | 149，实例预算 |

综合估计跨过 Slice 容量线。原始 `#slice*` 由 TD 标为预估，历史工程在物理装箱后有机会落入
器件容量。按路由情景仅约 720–2,320 个 Slice 余量，ERAM 预计只余 7 片，DSP 余 91 个。
FF 和 DSP 总数有余量，Slice 装箱、ERAM 分布与拥塞仍是风险。现有证据支持继续将同器件作为
验证目标，实际是否装入、能否完成路由以及四类时序是否有余量均待新整机阶段确认。
父版 d1e5dce4 八种子中七个物理 STA 有负裕量，另一个 setup 仅显示 0.000 ns。
[整机原始基线与时序](README.md)

## 基线与已测部件

以支持相同 HD/UHD 几何的 `camera_rate_r2@d1e5dce4` 为主锚点。原始 gate 为
64,009 Slice、80,912 `#lut`、70,897 FF。重开为 63,462、79,437、70,871。
两阶段均为 259 ERAM、146 DSP，已包含 UHD 大行缓存。HD 的 RAW R2 从 `41cb5991`
升至 `1a5603c1` 的同设置整机对照增加 312/307 个原始/重开 Slice、337 FF、6 ERAM 和 5 DSP，
用于核对 HDR 扩吞吐的成本量级。融合另有质量、UART 和不同等价优化，仍以 UHD 父版为面积锚点。
[三份源绑定原件](README.md#整机原件)

| 同载体测量 | 原始 gate | 同 AL 原生重开 |
| --- | --- | --- |
| Rate R2 色彩 → 最终融合色彩 | 1,083→1,450 Slice，1,220→1,882 `#lut` | 1,081→1,394 Slice，1,218→1,730 `#lut` |
| 初始融合色彩 → 最终等价优化 | 1,519→1,450 Slice | 1,463→1,394 Slice |
| RAW 五窗口，HD/UHD compact | 782→730 Slice，1,122→840 `#lut`，1,062→1,008 FF | 同原始 gate |
| RAW 五窗口，CAM1 fixed LONG | 696→666 Slice，979→664 `#lut`，951→899 FF | 同原始 gate |

父到最终色彩两阶段均为 2,180→2,560 FF、14→16 ERAM、17→24 DSP，包含双像素 Tone、
共享舍入、动态 WB、四页 ROM 与渐进高光的完整算术载体。初始到优化融合色彩两阶段
均少 398 FF，`#lut`、ERAM 和 DSP 相同，8 ns 载体重开的最差 setup 保持 +4.059 ns。
预算用父到最终色彩的净差，双像素 Tone、两个高光 DSP 和局部优化收益已经计入。
[父版载体及 SHA](../../tmp/color_parent_compare/parent_a1/rate_r2/manifest.json)
· [最终载体及 SHA](../../tmp/color_parent_compare/parent_a1/fused_optimized/manifest.json)
· [融合色彩前后对照](../../tmp/color_pipe_equiv/identity_a1)
· [RAW 两个载体原件](../../experiments/raw_ingress_equiv/runs/full_window_r1)

ERAM 实例预算按 259 加 HDR 读取预取的四片 RAM 和双像素色彩的两片 ROM 得 265。
质量四页复用已计入的 ROM，配置保留原 32 字存储与 40-bit FIFO。DSP 实例预算按 146
加色彩载体净增的 7 并扣除融合由八乘法器到四 MAC 的 4 个得 149。
当前合并的平衡融合仍用这四条 MAC。实际有效实例和隐式映射以新源 gate 报告为准。
[HDR 读取对照](../../../camera_rate_r3/experiments/hdr_prefetch_cost/README.md)
· [四 MAC 对照](../../../camera_rate_r3/experiments/dsp_area/README.md)

## 范围的计算口径

以下增量用于预算情景，只有第一行是直接代入的同载体测量。其余行是依据所列局部证据
取整的预留或折算，保留层级共享、扇出复制和选择逻辑影响。各行的端点并非可同时实现的最优/最坏组合。

| 变化项 | Slice 情景 | `#lut` 情景 | FF 情景 |
| --- | ---: | ---: | ---: |
| 完整色彩，原始 / 重开 | +367 / +313 | +662 / +512 | +380 |
| 预取、融合 MAC/平衡判定、JPEG、SOURCE 与复位 | −60 至 +40 | −150 至 +150 | −240 至 −140 |
| 采用的五窗口 RAW | −165 至 0 | −1,200 至 0 | −210 至 0 |
| CFG、UART 和尚未量得的整机映射交互预留 | 0 至 +500 | 0 至 +900 | 0 至 +300 |

第二行的参考是预取载体 −3/−1 Slice、−235 FF，JPEG DC 与 MCU 两独立载体在两阶段净计
−43 Slice，SOURCE 同源局部 −16 Slice。早期四 MAC 的 −30 Slice 与画质平衡融合单独的
+23 Slice 来自同一算术边界的不同变体，归入共同预留。复位相位、启停和其他小控制逻辑也
由该预算吸收。RAW 优化的收益端点按两类载体各最多复用两次取整，保守端点计零收益。
这些数只描述预算中可考虑的抵扣规模。不同宽度和参数的四条生产入口由整机映射定值。
[JPEG 两项 A/B](../../../camera_rate_r3/experiments/jpeg_throughput/README.md)
· [SOURCE 资格](../../../camera_rate_r3/docs/RESET_TIMING_CHANGES.md)

CFG 严格模式的局部参考为 +143 Slice、+204 `#lut`、+70 FF，生产是可信 BAR 加完整 USER/PIX/DFI
链，完整载体曾在父版 Map Gate 达到 180 秒限额。严格小载体既省略完整 CDC/消费者，也包含生产
可裁剪的二次验证，因而只作规模参考。DJ/v4 恢复 CFG 状态并保留两眼 FS，PIX→SYS 两级既有银行
各扩 32 位，PIX 页原保留的 16 位也承载 CFG flags。若这些位均保留，两个银行本身约多 96 个
有效位寄存容量，另有输出字节选择和状态连线的未测成本。32 位已发布 epoch 接入既有字位，
四个新增保留字节是常量。最后一行的 +500 Slice 预算也参考早期 UHD 小载体预算对实际 d1e5
整机映射低估约 514/521 Slice 的量级，覆盖未知面积交互，实际值仍可高于预留。
[CFG 资源测量](../../../camera_hdr_quality_r1/analysis/quality_cfg_probe/README.md)
· [UHD 先前预算](../../../camera_rate_r2/docs/UHD_RESOURCE_COST.md)
· [DJ/v4 字段与 CDC](../../UART_FIELD_V4.md)

综合两列分别从同阶段父实测出发，按情景计算，再向外取整到百位。重开到路由的估算采用三套
源绑定基线观察到的约 0.8–1.5k Slice 装箱差和 0.79–0.95k FF 增量，前提是该设计完成路由。
历史路由 `#lut6` 与对应重开 `#lut` 的实测比例约 0.727–0.732，用于路由 LUT6 的数量级校验。
`#lut` 按逻辑 LUT 输入数报告，`#lut6` 是物理统计，比例仅是这一批同器件工程的经验外推。

## 保留的试验和资格

- RAW 上下文 payload 去异步复位在两个载体分别少 15 和 26 Slice，UHD 的 count→DATA 估计余量下降
  0.181 ns。以本轮容量目标衡量，保留在实验。 [二轮 RAW 结果](../../../fpga_prj/verification_archive/experiments/raw_ingress_equiv/r2_payload_reset/README.md)
- 控制 FIFO 固定 flit 片选在 375 位载体两臂原生通过，重开仍为 498 Slice、少 18 `#lut`。
  147 位候选出现 TD `PRJ-8806`，缺可比有效结果，生产保留原序列化。
  [375 位原件](../../tmp/control_flit_equiv/w375_a2/RESULTS.json)
  · [147 位失败原件](../../tmp/control_flit_equiv/w147_a1/candidate/td.log)

复核现有高成本锥后，尚未找到有证据支撑约 500 Slice 收益的低风险局部等价候选。

- 元数据存储生产参数启用 `STAGING_EXTENSION_ENABLE` 和 `STREAM_READ`，16,384 位通用全量读写
  支路已裁剪。实际数据由 40-bit RAM 字串行回放，旧整机该树为 607 logic LUT、541 FF、6 ERAM。
  大位宽声明不能作为可回收资源依据。
- 四个 RAW writer 树为 201/201/245/231 logic LUT，所含描述符校验、AW/W/B 生命周期、错误填充
  和槽终态均在生产生效。即使把 WDATA 掩码移到现有选通边界，每条路径仍需保持承诺和 stalled WDATA
  稳定，实际可省量取决于 TD 当前合并方式。
- 两个 HDR 配对门各有约 800 logic LUT。高成本的 32 位序号比较实现同拍有序选择，包括任意异常
  序号的非传递关系。将比较跨拍复用会改变故障反压与超时边界，需要新的共享状态和独立验证。
- JPEG 熵核的 72 位追加可在已排字节计数下改为直接 64 位对齐，涉及一层宽选择和八个中间位。
  这属于小规模映射优化，预算中未抵扣该项。现有熵字节、RST、FF00 和反压门的已验证源码保持。

上述面积来自 d1e5dce4 原始 gate 层次，logic LUT 不能折为对应数量的 Slice。
是否还需回收数百 Slice，首先取决于新整机映射和装箱结果。若实测不足，能显著回收的候选将涉及
共享跨域描述符或数据选择、减少重复存储等结构级调整，需要连同并发所有权、原守护和时序重新验证。
[旧 gate 层次报告](../../../../server/td/local/download/camera-rate-r2-d1e5-20261110/syn/checkout/refactor/camera_rate_r2/fpga_prj/rfcamera_rate_r2_Runs/syn_1/rfcamera_rate_r2_gate.area)

资源合理性为 **NOT_PROVEN**。预算高档提示风险，是否超限仍需实际测量。
融合源的整机综合、P&R、物理 STA、bitgen 和板级均为 **NOT_RUN**。
局部逻辑和数值验证与整机阶段分别记账。物理容量及最终资格以同一融合封印的综合和路由报告为准，
同时核对 setup、hold、recovery、removal、例外和覆盖率。
