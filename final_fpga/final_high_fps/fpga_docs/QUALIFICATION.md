# 融合工程本机验证与资源边界

本页保存初次融合eade457d/ef8a2c66的验证范围。后续已验证优化及实际基线综合/Placed资源见
[优化进度](optimization_r2_20261110/PROGRESS.md)，原封印保存在[EADE_SOURCE_SEAL.json](optimization_r2_20261110/EADE_SOURCE_SEAL.json)。

日期：2026-11-10。独立入口为 `fpga_prj/rfcamera_fusion_r1.al`。原生 Runs、RTL、IP、
约束和配套 SDK 均位于本候选目录，三份来源工程及旧比特流保持原样。

功能融合和本机验证已完成。**“资源占用已经合理”仍为 NOT_PROVEN**：当前预算上沿
跨过器件 Slice 容量，不能把局部综合、read_design 或历史物理结果当作新整机可装入证明。

## 融合结果

以 `camera_rate_r3` 封印 `5914a5b2` 为骨架，合入 `camera_hdr_quality_r1@7dde99e7`，
用共同来源 `camera_raw_r2@1a5603c1` 核对近期修复。最终生产封印为
`ef8a2c66d1f14d6a39b4cc2fde76a5ce4d3a97e5c2ca8d85f63eb9187ab70628`，408项生产输入、253项注册、156项冻结IP。
保留单目 HD60、双目 HD30/40/45/48、
HDR 两像素 Tone/DDR 预取、4K15/20 JPEG/RAW、原合法图像算法、帧身份、槽归还和配置排空。
新增画质控制包括两档融合、四档 Tone、渐进高光保护、共享 RGB 白平衡；4K JPEG 也能调白平衡。
UART DJ/v4 同时保存配置诊断和两眼物理 FS。

复用同一套 ISP、预处理、JPEG 和传输通路。4K 不开放 HDR/去雾/车道，RAW 不开放在线图像 CFG。
旧 rate_r3 SDK 的 UHD 能力精确匹配会拒绝新增能力位，融合4K需配套本 SDK；HD旧线编码仍兼容。
[完整功能与参数](MODE_MATRIX.md) · [三方合入映射](INTEGRATION.md) · [RK调参](RK_QUALITY_CONTROLS.md)

## 本机功能验证

三个独立测试作者均由无实现上下文的 `gpt-6.1-sol max` 子代理启动，依据公开端口、
合法参数、线协议和数学合同新写测试；生产 RTL、厂商模型和旧 TB 实现不作为期望来源。
实现维护者单独处理依赖、夹具绑定和白盒故障定位。每个仿真有60秒以内墙钟和仿真 watchdog，
没有进行多帧满幅长仿真。

| 验证范围 | 结果和实际终态 |
| --- | --- |
| CFG/冷控/SDK | 四组真实USER/PIX/DFI配置、八次HD/UHD冷选通过；完整32字与epoch回读、旧ACK、欠账/晚B、APPLIED与新流水busy、非法值拒绝及恢复通过。发现并修复新增画质字段接受数字字符串的问题，同一反例复验通过。 |
| RAW打包 | 两臂各15 END、7 ABORT，四种配置的公开轨迹逐沿相同；覆盖HD/UHD、两HDR角色、非整拍尾、坏SOURCE、相邻事务、复位与恢复。 |
| HDR/Tone/ISP | 融合2284组、四页65536灰码及彩色边界通过；两臂色彩/真实共享ISP逐码与统计通过，包含3840×4和末拍保持。Tone保持两拍接受四像素组。 |
| 真实HDR读取链 | 六个68×63作业、6426组RAW14逐码至quiet RESULT_OK；两眼/两bank、START锁参、跨4KiB、尾KEEP、SLVERR、取消承诺排空和复位后恢复通过。 |
| UART DJ/v4 | 从真实8N1 TX解出525B，OB/DJ两CRC、CFG与FS同快照、停钟/恢复、回卷、旧版混流和坏CRC后恢复通过。 |
| 真实ISP到产品退休 | 真正CFG/ARM、RAW写读、ISP/WB/Gamma、JPEG、最终B、native fence/ACK及ring退休；同会话读错负终态与后续合法恢复、停DFI启动、完整JPEG独立解码通过。deadline边界及完整冷重建的最终记录见产品报告。 |

[配置门](blackbox/config/README.md) · [数据与读取门](blackbox/datapath/README.md)
· [产品门](blackbox/product/RESULTS.md) · [UART门](../fpga_prj/verification_archive/src_fpga/simulation/blackbox_fusion_uart/README.md)

产品载体用480×32验证真实处理及运输链，传感器/CSI、PLL、DDR PHY和PCIe硬端口仍是数字模型。
3840×4只证明生产行宽和数值边界。不能用这些结果承诺双目40/45/48、4K20或HDR双眼30/30的
满幅持续产品帧率，也不能把合成图像/短图模型当作IMX415实际画质。

## 资源优化与预估

采用两项新等价优化：RAW10整拍配置采用五个固定字节窗口，保留通用尾拍与故障行为；
单位色彩矩阵去掉两级冗余数据延迟，保持原整数运算、帧参数和流水吞吐。

| 同设置局部载体 | Slice变化 | 其他与路径 |
| --- | --- | --- |
| RAW HD/UHD compact | 782→730 | FF1062→1008，history→DATA估计+5.426→+6.201ns |
| RAW固定HDR LONG | 696→666 | FF951→899，history→DATA估计+5.427→+6.201ns |
| 初始融合色彩→优化 | raw1519→1450；重开1463→1394 | 少398FF，LUT/ERAM/DSP不增；8ns setup估计保持+4.059ns |

没有采纳只省少量资源且UHD目标路径变差的上下文复位改法。控制FIFO片选实验未得到有意义的
Slice收益，另有一个 TD PRJ-8806 失败，均保留原件。后续审计未找到可有依据地回收约500 Slice
的低风险局部改动；没有删除功能、降精度、扩展false path或修改业务超时值来制造达标。

| 预计口径 | Slice / 64320 | FF / 128640 | ERAM / 272 | DSP / 240 |
| --- | --- | --- | --- | --- |
| 原始 opt_gate 工程预算 | 约64100–65000，99.7%–101.1% | 约70800–71500 | 约265，97.4% | 约149，62.1% |
| 同AL综合重开工程预算 | 约63500–64400，98.7%–100.1% | 约70800–71500 | 同上 | 同上 |

这是以源绑定整机父版和同载体对照为依据的情景预算，不是新整机测量，也不是统计置信区间。
完整色彩载体净增已经包括双像素Tone、动态WB及高光算术，未重复计算它们的单叶增量。
父版物理装箱后曾缩小，但新源是否能装入和形成时序余量仍待确认。
[详细预算、LUT口径、未测代价及排除依据](analysis/resource_audit/ESTIMATE.md)

## 原生工程与阶段状态

最终源码的TD read_design、同AL重开和层次核对已完成。层次核对包含新质量/UHD validator、
两个Tone lane及高光乘法、四MAC融合、四个预取RAM、DJ/v4的256位PIX快照和128条DDR guard端点。
这不是物理时序检查；旧时序结果对本融合源为STALE。

| 阶段 | 状态 |
| --- | --- |
| 独立黑盒短仿真 | PASS，按各门公开合同与模型范围；AXI边界与完整冷重建已完成 |
| TD整体read_design/原生重开/层次 | PASS |
| 同载体有界小模块综合 | 采用项PASS；未采纳失败独立保留 |
| 融合源整机综合 | NOT_RUN |
| P&R、物理setup/hold/recovery/removal、bitgen、板级 | NOT_RUN |
| 整机资源合理性与持续帧率 | NOT_PROVEN |

AXI压力门最初把超过继承服务期限一拍的响应当作正向输入，发现硬恢复保护并定位。
原规范规定4096周期进展期限，代码在各来源中同字节。补齐[服务期限合同](../fpga_prj/verification_archive/verification_reference/fusion_product_public/AXI_DEADLINE.md)
后验证边界与故障排空，原FAIL不覆盖。PERST/link不清DDR/native所有权；完整重新配置/上电重建
与同会话在线恢复分别记录。没有实际烧录、重启设备、发布服务器任务或改变旧编译队列。

最终生产输入和辅助输入见 [SOURCE_SEAL.json](SOURCE_SEAL.json)；保存的小文件原始证据见
[INDEX.json](validation_20261110/INDEX.json)。未生成融合版比特流。
