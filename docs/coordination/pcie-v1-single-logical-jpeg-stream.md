# FPGA → RK3576：PCIe v1 单逻辑 JPEG 帧流答复

- 日期：2026-09-15
- 对应问题：P0-03、P0-04、P0-04a/P0-04c、P1-03a/P1-03b。
- 结论：**接受：PCIe v1 固定为单逻辑 JPEG 帧流。**
- 状态：接受架构方向；生产图像链路仍为 `Proposed`，未完成项保持 `TBD`。
  本文没有新增任何 `Tested` 项，也不把仿真 PASS 等同于 RK3576 实机验证。
- 权威状态入口：[FPGA 确认清单](fpga-confirmation-checklist.md)。

## 1. 对六个问题的逐项回答

| 问题 | v1 设计答复 | 当前实现与证据边界 |
|---|---|---|
| 1. 一条 record 是否是一张预处理并编码完成的完整 JPEG？ | **是，针对生产 JPEG 模式。** 一条有效 record = 一份 64-byte 传输头 + 一张完整 JPEG 的字节数据；不能是一行像素、一个 JPEG 分片或若干独立 JPEG 的拼接。 | `Proposed`。当前可复用 PCIe 封装接收外部准备好的 record，自己不做图像预处理或编码。预处理项目、顺序、像素格式和 encoder 尚未完成/冻结。 |
| 2. 多颗摄像头是否在 FPGA 侧归并为一个逻辑输出？ | **是。** FPGA 前端必须在提交 PCIe record 前完成所需的选择、融合、拼接或整帧调度；Linux 只消费最终输出。上述方法是候选，不要求全部实现，也不承诺已经具备融合/拼接。 | `Proposed`。实际摄像头数量、接线、跨时钟域、同步和调度策略均 `TBD`。融合/拼接的结果若启用，应是一张最终图像再编码为一个 JPEG，而非把多个 JPEG 塞进一个 payload。 |
| 3. Linux v1 是否不识别物理摄像头、不加 camera_id/stream_id？ | **是。** v1 不提供物理摄像头身份或独立子流语义，保持当前 64-byte header，不增加这两个字段。 | 当前 header 确实没有这些字段。不得把 `slot_id`、sequence 高位或 reserved 字段暗中用作 camera_id；`slot_id` 是存储/诊断概念，不是图像来源。 |
| 4. record 是否禁止交错？ | **是。** 输出顺序只能是 `header(A) → payload(A) → header(B) → payload(B)`。A 最后一拍完成输出握手前，不得输出 B 的 header/payload。 | 已有帧发送器及带内头部封装的行为仿真覆盖串行记录和反压；这不是板级 `Tested`。上游可在缓冲空间允许时预取下一条头部，但不能在 C2H 输出线上交错。 |
| 5. 是否全局 frame_sequence，只随最终输出 record 递增？ | **是，作为逻辑流序号的设计方向。** 多摄像头不能各自把独立计数器混入同一输出；正常连续输出的下一条 record 使用逻辑流的下一序号。 | `Proposed`。字段现为 header offset `0x08` 的 little-endian u32。通用封装透传上游提供的 sequence，不生成、纠正或校验单调性。真实前端的分配时点、丢弃/失败是否消耗号码、复位/会话规则仍 `TBD`，见第 3 节。 |
| 6. payload 是否保证是标准 JPEG，而非原始像素/中间数据/测试字节？ | **生产合同要求是。** Linux 发布为 JPEG 图像的数据必须是一张完整、标准可解码的 JPEG，包含其 SOI/EOI；64-byte 传输头在 JPEG 文件之外。 | 当前板级测试源默认可产生固定的 331-byte、1×1 grayscale、OpenCV 可解码 JPEG fixture。这只关闭“测试 payload 不是 JPEG”的缺口，不表示 camera、三项预处理或生产 JPEG encoder 已实现。PCIe 封装仍只负责传输格式/长度/握手，不验证 JPEG 语法或可解码性。该 fixture 的验证范围仅为 Python 静态/OpenCV；ModelSim、TD、板卡 PCIe/DMA 和 RK3576 仍未验证。生产合同保持 `Proposed/TBD`，绝不是 `Tested`。 |

## 2. 该结论对 Linux 的含义

Linux v1 的应用模型可以围绕单个逻辑 `EncodedFrame` 序列设计，不需要
按物理摄像头建立多套队列、独立 sequence 或 camera_id 分流规则。
摄像头切换造成的图像内容变化，不自动构成第二个独立输出流。

但该架构接受不解除尚未确认的真实 transport 门禁：

- 必须按 P0-04a 的版本化布局解释 header；本次不改 magic、version、字段偏移或 reserved。
- 一个 record 的总有效字节数仍为 `64 + payload_length`；payload_length 不含传输头。
- 非交错并不意味着一次 Linux `read()`、一个 DMA descriptor 或一次 completion
  必然对应一条 record。长度发现、EOP 实际长度及读取策略仍按 P0-07a/P0-07b 待联调冻结。
- 正常 record 完成后才可发布图像；错误、中断、超时产生的半条 record 必须丢弃。
  不得将后续字节直接拼接成“修复后的 JPEG”；具体恢复顺序仍需双方确认。
- 测试模式必须由双方明确的联调配置与生产图像路径隔离。当前没有新增或冻结
  自动识别测试模式的 header 标志，不能靠 `compression=1`、`quality=75` 或
  “长度正确”认定是真 JPEG，更不能把测试字节交给生产 JPEG/AI 路径。
- JPEG 解码成功、预处理语义正确和 DMA 完成是三项独立验收。

## 3. sequence 与多摄像头的明确边界

v1 的 sequence 归属于**最终逻辑输出**，不是物理摄像头帧号，不是 slot index，
也不是 Linux 已消费计数。前端若丢弃某摄像头输入、选择另一摄像头或生成融合图像，
其内部计数不能直接替代这个逻辑序号。

候选正常路径：最终输出调度器为选定、已编码且准备发布的 record 填写 sequence，
在该 record 的 header/payload 全部传输期间保持不变；下一条正常 record 加一。
当前字段为 u32，取值范围为 0..0xffffffff；此处不规定达到上限后的线上序号。
回绕/epoch 规则仍待双方确认；当前 Linux SequenceTracker 使用非回绕语义。

以下细节仍属于 P1-03a/P1-03b 的 `TBD`，不因本文而冻结：

- 发送前取消、编码失败、超长拒绝、缓存覆盖及发送中止是否消耗号码。
- 首个有效 sequence、应用复位/摄像头复位/PCIe 复位的对应关系。
- 重连后的会话区分、是否需要未来新增 epoch，以及如何丢弃旧 completion。
- Linux 如何解释序号间隙、重复与恢复后的回零；不能仅靠 sequence 判定数据有效。

如果未来产品要求 Linux 按相机分别做推理、标定、时间同步或独立丢帧统计，
那是与本次 v1 假设不同的需求，应启动新的协议版本/能力协商，明确 stream_id、
各流 sequence、时间戳及调度语义。不能不改版本就重解释 v1 保留字段。
目前没有必须让 Linux 消费多路独立流的已确认需求，因此不选择“不接受”。

## 4. 当前可以证明什么

| 范围 | 当前证据 | 本文状态处理 |
|---|---|---|
| 64-byte 头部、长度、TKEEP/TLAST、反压与连续 record | 自研 RTL/ModelSim 回归通过，含边界长度、发送器错误路径及 RTL 复位回归 | 只沿用既有静态/行为证据，不提升为实机 Tested |
| 真实加密 SGDMA 的描述符读取、16-byte C2H 写入及完成回写 | 2026-09-15 事务级自检与独立工作库复跑通过 | 数据是测试字节；不证明真实 JPEG、完整硬核链路或 Linux 驱动 |
| PCIe 硬核 | ModelSim 编译、展开、有界运行；无匹配 Root Port/BFM | 没有链路训练/枚举成功证据 |
| camera、三项预处理、JPEG encoder、多摄像头归并 | 当前生产 RTL 尚未完成 | Proposed/TBD |
| 标准 JPEG 解码、色度抽样、quality 含义、真实帧长度预算 | 无当前 FPGA → RK3576 实机图像证据 | TBD |

详细仿真条件、267 条警告及未通过的静态门禁见
[PCIe 功能仿真报告](../../doc/pcie_functional_simulation_attempt.md)。
本轮提交前复跑传输仿真通过，但不提升真实 JPEG/板级验收状态。

## 5. FPGA 分支与版本关联

- FPGA 分支：`feature/fpga-pipeline`。
- 本次 PCIe RTL/仿真/接入说明交付 commit：
  `5b751eb9e6ba081b2e4b9f381d90491b19098cbf`。
  其中包含通用封装、带内头部、真实 SGDMA 最小事务测试与验证范围说明。
- 已推送至 `origin/feature/fpga-pipeline`，并用远端分支查询核对到相同 hash：
  [GitHub PCIe 交付提交](https://github.com/Code-dstror/anlogic-task3/commit/5b751eb9e6ba081b2e4b9f381d90491b19098cbf)。
- 清理生成物 commit：`ce6d58c`；先前测试流水基线为
  `53ffd3add64e0685e7fa2c196b2248ac4cac517d`。
- 本答复及确认清单随本次独立文档提交纳入版本控制；文档版本可由下方 `git log` 查询。
  上述交付 commit 关联被说明的实现，不包含本文，也不代表本文已成为 Tested 合同。
  Linux 不能从源码提交中推断尚未实现的 camera/JPEG 保证。
- 本次答复不关联旧 bitstream 为新功能证据；没有对应的新生产 JPEG bitstream。
- 后续实现或证据变化时，应另行提交并关联当时的 RTL/bitstream；
  本文不将新工作区仿真结果归给旧 bitstream。

可复查入口（仓库根目录）：

```powershell
git branch --show-current
git rev-parse HEAD
git status --short
git log -1 -- docs/coordination/pcie-v1-single-logical-jpeg-stream.md
rg -n "frame_sequence|STATE_WAIT_LAST|o_meta_ready" fpga_rtl/pcie/c2h_frame_tx.v
rg -n "o_meta_frame_sequence|final_header_valid" fpga_rtl/pcie/pcie_inband_header_adapter.v
```

## 6. 达到生产确认/实测所需的后续证据

1. 冻结摄像头连接、预处理次序、encoder 类型、色度抽样、quality 与尺寸合同。
2. 用真实或受控 golden 图像生成完整 JPEG，确认 SOI/EOI、实际长度并在 RK3576 解码。
3. 完成最终输出调度器及逻辑 sequence 规则，覆盖相机切换、失败、丢帧与复位。
4. 完成真实板级枚举、BAR、DMA 实际长度和连续 JPEG 传输；保存 driver/kernel、
   RTL commit、bitstream hash、命令和日志后，再按清单逐项提升到 `Tested`。
