# 真实 ISP 到 JPEG 退休短测

2026-11-10，`blackbox_fusion_product_a13_all` 的四项 RTL 短门、五个仿真进程和六份
JPEG 独立解码均通过。
每个成功产品逐字节核对 19,200 B RAW10 写入和 1,200 个实际回读拍，再由 24 个 native
写 TLP 重建 3,024 B AJPG v4。每份记录含 2,112 B 头和 912 B JPEG。真实 fence、RC、SAFE、
同一主机 buffer identity 的 ACK 和 JPEG ring 退休响应均成交。 [运行结论](../../../tmp/blackbox_fusion_product_a13_all/summary.json)

测试依据公开端口、线协议和整数数学编写。生产 RTL、投影实现和厂商模型只作不透明编译和
哈希。载体保留真实配置跨域、RAW 存储和回读、shared ISP、WB、Gamma、Tone 选择、JPEG、
DDR writer、native C2H 及 ring 退休。传感器/CSI、时钟源、DDR PHY 和 PCIe hard port 由
数字边界模型提供。像素栅格为 480×32，UHD 能力页仍报告 3840×2160。
[公开合同](../../../fpga_prj/verification_archive/verification_reference/fusion_product_public/CONTRACT.md)

## 成功产品与所有权

通过真实 BAR 选择 geometry 1/profile 5 或 geometry 2/profile 6，协商
`CFG_HOST_CAPABILITIES=1`，提交 schema2 SDR、Q73、最小 Q1 和手动 WB
`(333,178,226)` Q8。匹配 CFG ACK 为 session 1、epoch 1。APP 冷态时用实际
FS/SOF/FE seq10 发布 APPLIED。随后选择 AJPG v4、ARM native buffer、ARM APP，
首个产品从实际捕获的 seq11 开始。

常规、停 DFI 与完整冷重建的四个正向帧均在含 EOI 的 WLAST 后等待 2,600 个 DFI 上升沿，
再于下降沿驱动最后一个 JPEG B。其余 JPEG B 和 RAW B 分别等待 48 和 5 个上升沿。
每个正向产品在 EOI 写完且成功 JPEG RESULT 已到达时，均在最后一个 B 前读到 READY_MASK=0。
writer ACK、record offer 和 native 写均保持无成交。到达 SAFE 后又保留至少
48 个 USER 周期才发送 ACK，退休请求和 ring 退休响应均晚于该 ACK。

| 场景 | seq | EOI WLAST µs | RESULT 后 READY=0 µs | 最后 B µs | Record offer µs | SAFE µs | Host ACK µs | Ring 响应 0 µs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| UHD15 首帧 | 11 | 228.087 | 243.457 | 247.600 | 253.826 | 280.921 | 281.749 | 281.809 |
| UHD15 恢复 | 13 | 439.936 | 455.305 | 459.449 | 465.675 | 492.825 | 493.669 | 493.725 |
| 停 DFI 启动 UHD20 首帧 | 11 | 245.240 | 260.617 | 264.753 | 270.980 | 298.081 | 298.909 | 298.970 |
| 完整冷重建后首帧 | 21 | 228.072 | 243.457 | 247.585 | 253.811 | 280.921 | 281.749 | 281.809 |

停 DFI 场景在 100.111 µs 观察到 USER 释放而 DFI 和 PIX 保持复位。恢复 DFI 后在
100.368 µs 观察到四个公开 reset_n 端口全部释放，随后通过真实 BOOT、配置、ARM 到首帧退休。
[正常启动原始日志](../../../tmp/blackbox_fusion_product_a13_all/normal/simulate.log) ·
[停 DFI 原始日志](../../../tmp/blackbox_fusion_product_a13_all/stopped/simulate.log)

UHD15 的 seq12 在真实 JPEG START 后 337 ns 对已承诺的 RAW AR 注入一次 SLVERR。
AR 地址为 `0x03000500`，ID 1，第 0 拍。共接受 96 个 RAW R 拍和一个实际 JPEG
写突发的 256 B，承诺的 AXI 事务全部排空。RAW SOURCE、JPEG SOURCE、JPEG RESULT 和
writer ACK 均为负，ticket 为错误，完整 64 位 SOURCE/ticket job 一致，RAW 槽退休。
该帧产生零成功 record offer、零 DMA 字节和零 JPEG 正常退休。原 native buffer
generation 2 保持未绑定 ARM，seq13 在相同 CFG session 和 epoch 上用该 buffer 真实退休。
[负帧及恢复日志](../../../tmp/blackbox_fusion_product_a13_all/normal/simulate.log)

## 独立数值结果

GBRG 色块按公开 BLC 减 50、Q8 半值向上乘法、1023 上限和冻结 Gamma 表生成独立 RGB8
期望。解析器核对 AJPG/CTX2、实际 SOURCE 身份、处理模式 `0x80`、中性资格位清零、
JPEG SOF0/4:2:2、30×4 MCU、完整 EOI 和整帧解码。门限为每通道最大绝对误差 4。
六份记录共比较 92,160 个像素，即 276,480 个 RGB8 通道值。

| 场景 | RAW10 R/G/B | 期望 RGB8 | 逐通道最大绝对误差 | 像素数 |
| --- | --- | --- | --- | --- |
| UHD15 首帧，常规与边界 | 172, 440, 858 | 109, 139, 216 | 1, 0, 1 | 30,720 |
| UHD15 恢复，常规与边界 | 613, 328, 234 | 219, 119, 110 | 1, 0, 1 | 30,720 |
| 停 DFI 启动 UHD20 首帧 | 172, 440, 858 | 109, 139, 216 | 1, 0, 1 | 15,360 |
| 完整冷重建后首帧 | 613, 328, 234 | 219, 119, 110 | 1, 0, 1 | 15,360 |

[正常场景数值与 JPEG/记录哈希](../../../tmp/blackbox_fusion_product_a13_all/normal/records.json) ·
[停 DFI](../../../tmp/blackbox_fusion_product_a13_all/stopped/records.json) ·
[响应边界](../../../tmp/blackbox_fusion_product_a13_all/deadline/records.json) ·
[完整冷重建](../../../tmp/blackbox_fusion_product_a13_all/cold_recovery/records.json)

## AXI 写响应时限

`a08` 把每个正向 JPEG B 的延迟都设为 4,096 个 DFI 周期，两项场景都在首帧出现非正
RAW SOURCE。独立保留的 `a10_all_b` 用同样压力复现正常启动，接口账目在首个失败沿
冻结。首个 JPEG WLAST 在 162.692 µs，匹配 B 在 193.428 µs，RAW SOURCE 在 200.948 µs
明确为 0，`o_fault=1`，`o_capture_enabled=0`。RAW 已写完 75 个突发、1,200 拍和
19,200 B，已读 70 个突发和 1,120 拍。模型未注入 SLVERR，已承诺 RAW 和 JPEG AXI
事务均已完成，尚未出现 JPEG RESULT、writer ACK、ticket、RAW 退休或 record offer。
原交接遗漏了继承的写响应时限。若 WLAST 在上升沿 k 成交，最迟在 k+4096 采到 BVALID。
原测试等 4,096 个完整上升沿再于下降沿驱动 B，实际第一次采样在 k+4097。
原始 FAIL 保留，正式测试入口 `--case stress` 保留同一刺激和原始验收以复现。
[时限公开合同](../../../fpga_prj/verification_archive/verification_reference/fusion_product_public/AXI_DEADLINE.md)

[a08 原始日志](../../../tmp/blackbox_fusion_product_a08/normal/simulate.log) ·
[a10 接口账目和原始日志](../../../tmp/blackbox_fusion_product_a10_all_b/normal/simulate.log) ·
[a10 复现台](../../../tmp/blackbox_fusion_product_a10_inputs/bench/tb_fusion_product.sv)

`a13_all` 的 `deadline` 在 k+4096 采到所有九个 JPEG B，其中首帧和同会话恢复帧
各四个，SLVERR 帧一个。正向两帧的 ring 响应均为 0，时间分别为 320.527 和 588.483 µs。
两份 JPEG 的独立解码与常规场景一致。
[边界内接口日志](../../../tmp/blackbox_fusion_product_a13_all/deadline/simulate.log)

`a13_all/timeout` 在 193.424 µs 观测到硬故障，匹配 B 在 k+4097 的 193.428 µs
仍成交。负 RAW SOURCE 后，75 个 RAW 写突发、70 个 RAW 读突发和一个 JPEG 写突发
全部排空，DMA 字节为 0。普通 PERST/link 拉低时 USER/DDR reset_n 均为 1，硬故障
保持。恢复链路后硬故障仍为 1，AXI 债务和 DMA 字节仍为 0。
[边界外排空与链路隔离日志](../../../tmp/blackbox_fusion_product_a13_all/timeout/simulate.log)

排空后结束故障进程。另一全新 ModelSim 进程同时重建官方 GSR、完整 DUT 和 DDR/主机模型，
模拟重新配置或上电。该进程重新 BOOT、配置、ARM，以新 native buffer nonce
`6b33f81733b2ba42` 和 seq21 到真实 ring 退休。证据范围为完整冷重建后的首事务。
[冷重建首事务日志](../../../tmp/blackbox_fusion_product_a13_all/cold_recovery/simulate.log)

## 源身份与运行

从仓库根执行，重跑时使用新的 `--run-name`。本次使用 CPython 3.12.9、Pillow 12.2.0、
ModelSim SE-64 2020.4 与显式 TD Release 2026.2.210.850 模型。每例墙钟 60 秒和
200,000 个 PIX 上升沿，编译与全部案例合计墙钟 180 秒。a13 实测 35.500 秒。
正常、停 DFI、时限内、时限外和冷重建进程分别为 11.094、3.547、5.407、2.859 和 3.344 秒。

```powershell
& '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe' -B 'refactor/camera_fusion_r1/src_fpga/simulation/blackbox_fusion_product/run_gate.py' --modelsim-bin '<TOOLS_ROOT>/modelsim/win64' --td-root '<TOOLS_ROOT>/TD_Release_2026.2.210.850' --run-name 'a13_all' --case all
& '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe' -B 'refactor/camera_fusion_r1/tmp/blackbox_fusion_product_a10_inputs/bench/run_gate.py' --modelsim-bin '<TOOLS_ROOT>/modelsim/win64' --td-root '<TOOLS_ROOT>/TD_Release_2026.2.210.850' --run-name 'a10_all_b' --case normal
& '<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe' -B 'refactor/camera_fusion_r1/src_fpga/simulation/blackbox_fusion_product/run_gate.py' --modelsim-bin '<TOOLS_ROOT>/modelsim/win64' --td-root '<TOOLS_ROOT>/TD_Release_2026.2.210.850' --run-name 'stress_recheck' --case stress
```

| a13 输入或证据 | SHA256 |
| --- | --- |
| `real_isp_a3/compile.json` | `96c4fdc8decc27365da3a1f423ffa88d0b2c45af2bf0ae65d6c2f22a6573a222` |
| `wide_color_pipeline.v` | `54f2c7e04a376d926c63dc16d7b18e81f3a8a221c4caf49cfb426fdd9fcc1db5` |
| `shared_raw10_frame_ingress.v` | `8569d76989de58b9940cfa9090f8f3fd3ecd6c3eddea75b34fa31e01743381c3` |
| `ddr_axi_two_client_arbiter.v` | `380eeec665aa03ab2c0fffb944747afcbe4399f3182ab917496d0a6dfe73b446` |
| `AXI_DEADLINE.md` | `ca3c274386a585a27ab54a0f02e68f2d8d9f1bc6d03ac3761366a76b6164c700` |
| 编译、合同、TD 模型和测试输入前后清单 | `314ff88c49c785fd6ae7e7e94f13f07d0e6a842dbf408cb1530e2f9d46e0fe24` |
| 时限外原始日志 | `e994c4c8437966339508c99eb238f1f2b75c726dd5ff2585a9e96b9173cef949` |
| 完整冷重建原始日志 | `3a785ddf843ebbc1a34aefa48c460c74bc8572e8a1b747773d4fd11b4328e74a` |
| 时限外 13 个原始 ROM 和 DATH 前后清单 | `85a25ad4bffbdf6a539bee8d42510741cf69fb9a527902bb3159d279050079f4` |
| 完整冷重建 13 个原始 ROM 和 DATH 前后清单 | `d2a29fedebaebece37100333771a9ed0a70e19a4993163a8cbf33496c18c27ac` |
| a10 复现输入前后清单 | `f8ede53744edf21d472a28236a759997bc3d8f2a407527acef48f10fbae6d8ec` |
| a10 复现原始日志 | `e88047d93da37f1081d1f5448d346c48209fcfacfc318370af72c3d63b21a06c` |

[a13 精确命令](../../../tmp/blackbox_fusion_product_a13_all/commands.json) ·
[a13 源与测试哈希](../../../tmp/blackbox_fusion_product_a13_all/inputs_before.json) ·
[a13 RAW 输入哈希](../../../tmp/blackbox_fusion_product_a13_all/scenes.json) ·
[a10 精确命令](../../../tmp/blackbox_fusion_product_a10_all_b/commands.json)

a13 的 ModelSim 编译为零错误、零警告。首次展开有 213 条官方模型和冻结 IP 兼容诊断，
涉及 TD DRAM/ERAM INIT_FILE 静态片选、RAM40 ECC 注入端宽度、FDCT MAC 未用级联端
以及 Gamma 仿真 ROM 未用 ECC 输出。原日志保留全部诊断。五个进程均为零 Error/Fatal。

## 保留的早期 FAIL

| 运行 | 分类 | 观察与后续处理 |
| --- | --- | --- |
| [a01](../../../tmp/blackbox_fusion_product_a01/normal/prepare_rom.log)、[a02](../../../tmp/blackbox_fusion_product_a02/normal/prepare_rom.log) | 工具依赖 | Windows PowerShell 子进程找不到 Get-FileHash，显式加载 Utility 模块后通过 ROM 初始化。 |
| [a03](../../../tmp/blackbox_fusion_product_a03/normal/simulate.log) | 工具参数 | ModelSim 加载绝对 ini 路径失败，改用独立运行目录的映射和 ini。 |
| [a04](../../../tmp/blackbox_fusion_product_a04/normal/simulate.log) | 夹具 | `real_isp_a2` 的只读观测路径导致展开失败，维护者修复后生成 `real_isp_a3`。 |
| [a05 正常](../../../tmp/blackbox_fusion_product_a05/normal/simulate.log) | 测试前置 | CFG PREPARE 返回错误，补上已发布的 FRAME_APPLIED 主机协商再通过。 |
| [a05 停 DFI](../../../tmp/blackbox_fusion_product_a05/stopped/simulate.log) | 合同缺口 | 初始测试要求 PIX 在 DFI 停钟期间释放，公开合同澄清 PIX 允许受共同内存复位互锁。 |
| [a06](../../../tmp/blackbox_fusion_product_a06/normal/simulate.log) | runner | 预期的负帧通过标记被误识别为失败。改用精确标记匹配后两例和数值均通过。 |
| [a08](../../../tmp/blackbox_fusion_product_a08/summary.json)、[a10](../../../tmp/blackbox_fusion_product_a10_all_b/summary.json) | 交接合同缺口 | 原正向压力在 k+4097 才给出 B，超出既有服务窗口。 |
| [a11](../../../tmp/blackbox_fusion_product_a11_all/summary.json) | runner | 新增场景清单引用了未导入的 Python 名称，编译前退出。 |
| [a12 timeout](../../../tmp/blackbox_fusion_product_a12_all/timeout/simulate.log) | 复位边界合同缺口 | 硬故障和迟到 B 排空通过。原测试要求常规公开端口触发完整冷复位，夹具无此配置级复位端口。 |

a13 仿真结论限于短栅格、明确的 B 服务窗口和数字边界。满幅持续帧率、综合、P&R、物理 STA、
bitgen 和板级均为 **NOT_RUN**。
