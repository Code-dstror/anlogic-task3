# PCIe 视频传输封装接入合同

## 范围与结构

本次封装采用用户确认的方式 B：`pcie_video_transport` 对 FPGA 业务逻辑提供
AXI-Stream record 输入和完整 AXI4-Lite master。业务寄存器组位于封装外。
板级 `pcie_c2h_test_top` 是可综合接线示例，保留测试源及外部应用寄存器。
这两个层级不得混淆：片内总线不需要分配封装管脚。

```text
JPEG record source -> pcie_video_transport -> PCIe -> RK3576
                             |
                       AXI4-Lite master
                             |
                    外部译码/互连/寄存器组
```

不增加 DDR、图像处理、JPEG 编码器或 Linux 驱动；不改变厂商 IP 配置。
输入已经是一张完整 JPEG 的传输记录，长度在前置帧头中提供。

## AXI-Stream record 输入

五个业务端口为 `i_src_tdata[127:0]`、`i_src_tkeep[15:0]`、
`i_src_tvalid`、`o_src_tready`、`i_src_tlast`；不暴露 metadata 输入。
上游与应用总线使用封装输出的 PCIe 用户时钟和复位。异步来源必须先做 CDC。

- 每条记录为 `[64-byte header][JPEG payload]`，无尾部 padding。
- 帧头为 4 拍，全部 `TKEEP=0xFFFF`，全部 `TLAST=0`。
- 只有 JPEG 最后一拍 `TLAST=1`；不是图像行尾，也不是单独的帧头包。
- `payload_length` 不含 64 字节传输头，包含 JPEG 自身的 SOI/EOI；范围 1..16 MiB。
- 非尾拍全部 16 字节有效；尾拍从低字节通道连续有效。
- 每拍最先传输字节位于 `TDATA[7:0]`；多字节头字段采用 little-endian。
- 仅 `TVALID && TREADY` 前进；反压期间保持 DATA/KEEP/LAST 和 VALID。
- 允许输入空拍和任意有限反压，不交织多个 record。
- 复位后的首个握手必须是新 record 的首拍；不能接着发送旧 payload。

外部 `i_app_enable` 和 `i_app_reset_n` 由业务寄存器或应用控制逻辑驱动。
提交 metadata 前撤销 enable 只暂停输入，保留已收头部；重新使能时源继续原记录，
不能把 enable 的翻转当作重新对齐。应用复位才丢弃半个帧头。
允许预取一个头部等待链路及 C2H running，但这不表示主机 DMA 已提交。
metadata 已提交后撤销 enable 或丢失链路/通道运行状态属于中止。

非法头部不会发到 SGDMA，入口丢弃到输入 TLAST 后恢复；若源永不提供 TLAST，
须应用复位，当前没有私自设定的超时常数。开始发往 SGDMA 后发生错误则置
`o_recovery_required`，停止接收新记录直到复位；Linux 需先取消/清理失败的
DMA 并丢弃部分 record，再按双方恢复顺序重启，上游从新头开始。

帧头布局见下表（对应 `c2h_frame_tx.v` 的四拍封装）；公共常量以
`doc/pcie_protocol_v1.json` / 共享 Verilog 定义为准，不依赖未提交的协作答复。当前支持 flags=1、
保留字段为零；CRC 字段仅传递，未计算或校验，CRC 算法尚未冻结。
不应把 JPEG SOI 自身当作这里的 64 字节协议头。

| 字节偏移 | 类型/长度 | 字段 |
|---|---|---|
| 0x00 | u32 | magic = 0x47504A41 |
| 0x04 | u16 | version = 1 |
| 0x06 | u16 | header_length = 64 |
| 0x08 | u32 | frame_sequence（入口提供，封装透传） |
| 0x0C | u32 | payload_length，1..16777216 |
| 0x10 / 0x12 | 各 u16 | width / height |
| 0x14 / 0x15 / 0x16 / 0x17 | 各 u8 | pixel_format / compression / quality / flags |
| 0x18 | u64 | timestamp_ns |
| 0x20 / 0x24 | 各 u32 | status / error_code |
| 0x28 / 0x2A | 各 u16 | slot_id / reserved0=0 |
| 0x2C | u32 | payload_crc32（当前不计算、不校验） |
| 0x30..0x3F | 16 bytes | reserved1=0 |

测试源中的尺寸、compression、quality 等常量仅为传输测试值，不能证明
payload 已经是 JPEG；真实编码参数的语义仍需冻结。

错误码由共享 JSON 生成：原有 0..5 保持，新增 `HEADER_FORMAT=6` 和
`RECOVERY_REQUIRED=7`。新增错误码不修改 record 字节布局。接收端应将未知非零
错误值作为失败处理，不能按成功帧解释。`o_last_error` 是诊断输出，外部寄存器
模块可映射它；通用封装本身不为它私自占用 AXI4-Lite 地址。

## AXI4-Lite 外部总线

封装提供 master：输出 AWADDR/AWPROT/AWVALID、WDATA/WSTRB/WVALID、
BREADY、ARADDR/ARPROT/ARVALID、RREADY；输入 AWREADY/WREADY、
BRESP/BVALID、ARREADY、RDATA/RRESP/RVALID。地址、数据均为 32 位，WSTRB 为 4 位。

封装不消耗业务地址，不截断地址，不内置业务寄存器组。
多个 slave 通过外部互连或统一译码器接入，不能简单并联响应线。
互连必须保留读写目标到响应完成，并支持写地址、写数据独立到达。
未命中地址应产生错误响应，不能永久不响应。

现有示例寄存器组仅实现桥接地址窗口 0x00080000..0x00080FFF。
把总线暴露出来并不扩大 PCIe BAR aperture；新增业务地址必须处在实际配置的
BAR 可达范围内，并由 FPGA/Linux 共同分配。
Linux 动态取得 BAR 映射，不能硬编码主机物理地址。

总线在 user_clk 域；异步寄存器模块需要 AXI4-Lite CDC 或本地命令握手。
BAR 写响应代表寄存器访问完成，不代表业务命令执行完成；执行状态由外部
业务寄存器定义。软复位数据通路不应复位正在返回写响应的寄存器总线。

## Linux 接收边界

流内帧头只改变 FPGA 片内接入方式，线上仍只有一份 64 字节头。
Linux 仍需检查完整 record、实际长度、版本、状态及 JPEG 内容。
候选接收方式为先提交 64+16 MiB 容量的 C2H read，再使能数据源，
由 EOP/实际完成长度结束。该驱动行为尚未在 RK3576 验证。
若不支持，需另设长度发现/提交握手；不能把 `user_link_up` 当作 DMA 已就绪。

源末拍被接收、SGDMA 末拍握手、主机 DMA completion 和 Linux 解码完成
是不同事件；FPGA 发送完成不能作为 Linux 消费完成证明。

## 验证与状态

用户已将本次验收范围明确为仿真，不要求 TD 综合或布局布线。

2026-09-15 本轮结果：

| 检查 | 结果与范围 |
|---|---|
| `fpga_rtl/tb/run_modelsim.ps1 -MaxCases` | PASS；原 C2H/AXI4-Lite/H2C 回归，以及带内帧头链路 1/15/16/17/16MiB-1/16MiB、随机 VALID 空拍/反压、非零 metadata 字节比对、坏头排空后恢复、半头复位 |
| `fpga_rtl/tb/run_video_transport_modelsim.ps1` | PASS；0 errors/0 warnings；AXI4-Lite 全通道透传、H2C、连续帧、使能暂停、payload/link/C2H 故障、尾拍竞争、复位及零空拍错误恢复 |
| 板级示例及新测试源组合编译 | ModelSim vlog PASS，0 errors/0 warnings；这项是编译，未单独宣称板级全链行为仿真通过 |
| 厂商 PCIe/SGDMA 与 RK3576 | wrapper 测试用独立 endpoint double，仅证明封装接口行为；另行完成真实加密 SGDMA 的 16-byte 描述符/C2H/回写事务仿真，见下方报告；仍无枚举或 RK3576 板级证据 |
| TD | 用户调整验收前同步成功；启动的构建已中止，之后 RTL 又有修改，不作为本次综合、时序或 bitstream 证据 |

行为证据位于 `tmp/modelsim/rtl/pcie_inband_transport.log` 和
`tmp/modelsim/video_transport/{compile.log,pcie_video_transport.log}`。
测试替身位于 `fpga_rtl/tb/stubs/pcie_sgdma_endpoint.v`，只由专用 runner 编译；
不得注册到真实 TD 源集中。

后续真实厂商模型与 SGDMA 事务级测试的范围、复现入口和限制见
[PCIe 功能仿真报告](pcie_functional_simulation_attempt.md)。本表的自研封装仿真
不能与独立 SGDMA 仿真合并宣称完整硬核端到端已经验证。

严格 Verilog 技能检查的八项结果（`tmp/quality/adapter.json`，仅适配器范围）：
compile=passed；ast/readability/comment/naming/profile=failed；
testbench/toolchain=not_requested（该静态命令自身未调用外部仿真）。
实际 ModelSim 证据独立如上；不能把仿真 PASS 说成严格风格/组合锥检查 PASS。
本次提供三份同名模块说明，未完成 governed WaveDrom 产物生成。

测试源 `c2h_inband_test_source` 是旧源与旧帧封装器的组合，正常调用要求长度
在 1..16MiB 范围。非法测试长度可能令测试源等待 payload ready，需应用复位；
这不影响生产入口对非法带内头部的拒绝/排空行为。
