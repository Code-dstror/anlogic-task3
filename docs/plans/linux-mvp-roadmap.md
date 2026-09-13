# 赛题 3 Linux 用户态 MVP 路线图

- 状态：**Proposed（计划草案，未冻结）**
- 日期：2026-09-13
- 范围：仅规划 Linux 用户态；不替代 FPGA 实现、协议冻结或板端 bring-up。
- 关联：[用户态流水线架构](../architecture/linux-userspace-pipeline.md)、[PCIe JPEG 协议 v0.1](../../interface/pcie-jpeg-protocol-v0.1.md)、[FPGA 确认清单](../coordination/fpga-confirmation-checklist.md)。

## 总体原则

阶段 A--E 必须可在 Ubuntu 22.04 x86_64 虚拟机离线完成，使用 host 原生依赖和 mock，不安装 aarch64 RKNNLite wheel。第一版 MVP 采用全 Python；F 的首版 `SgdmaFrameSource` 也优先尝试 Python，G 优先采用官方 RKNNLite Python 接口。F--H 仍需要待确认的硬件合同或 RK3576 板端。Python-first 用于减少无硬件阶段的复杂度，不代表最终一定使用 Python。PCIe、SGDMA 字符设备优先和任何 C++ 优化边界均为 Proposed；本路线图不冻结 BAR、slot、CRC、实际节点、PCIe speed/width、JPEG 上限或模型参数。

建议的最小 MVP 是：`MockFileFrameSource（裸 JPEG）→ EncodedFrame → JpegPayloadValidator → JPEG Decoder → Preprocessor → MockInferenceBackend → Postprocessor → JSONL/console sink + Metrics`，并用 `MockCorruptFrameSource` 覆盖损坏 JPEG 和断连事件。协议 record 测试走独立的 `MockProtocolRecordSource/ProtocolRecordFileSource → ProtocolParser → TransportRecordValidator → SequenceTracker → EncodedFrame` 路径；sequence anomaly 在 v0.1 只计数、不丢弃有效 payload。它证明软件处理合同和可观测性，而不是 PCIe、FPGA 或 NPU 已验证。

## A. 工程骨架和数据类型

| 项目 | 内容 |
|---|---|
| 输入条件 | 已有本架构文档和小型、可再分发 JPEG fixture；无板卡、无 FPGA、无 RKNNLite。 |
| 交付文件 | `linux/` 下的用户态工程骨架、共享数据模型（`FrameMetadata`、`EncodedFrame`、`DecodedFrame`、`DetectionResult`、`RuntimeMetrics`）、配置 schema、错误码/日志接口、测试目录及 `.gitignore` 补充（仅在实现轮）。 |
| 验收标准 | 可在 x86_64 编译/解释并运行最小空 pipeline；数据模型不会包含 BAR、固定 slot、固定 `/dev/videoN`；停止令牌、队列关闭和 metrics 快照有单元测试。 |
| 依赖的 TBD | 无硬件合同依赖；仅需在实现前选择 Python 或 C++ 的第一批代码组织，不等同于最终语言决策。 |
| 需要板卡或 FPGA 队友 | 否。 |

## B. MockFileFrameSource

| 项目 | 内容 |
|---|---|
| 输入条件 | 阶段 A 数据模型/配置/日志接口完成；拥有合法 JPEG fixture 和其授权/来源记录。 |
| 交付文件 | `MockFileFrameSource`、裸 JPEG fixture manifest、顺序/循环/节流配置、`MockProtocolRecordSource` 或 `ProtocolRecordFileSource`、`MockCorruptFrameSource` 和可复现错误注入测试。 |
| 验收标准 | `MockFileFrameSource` 从裸 JPEG 合成 `source=mock_file` 和文件大小 `payload_length`，不创建 PCIe header；每个成功帧获得本地连续 `ingest_id`。独立 protocol source 能覆盖 record 的 magic/version/flags/length/CRC，以及由 `SequenceTracker` 诊断的 duplicate/gap/out-of-order；这些 sequence anomaly 的有效 payload 帧继续处理且 `ingest_id` 连续。`MockCorruptFrameSource` 明确区分损坏 record 与合法 record/裸 JPEG 中的损坏 payload。EOF、停止和模拟断连/重连均有预期事件。 |
| 依赖的 TBD | 协议草案的 magic/CRC/头字段尚未冻结；它们只约束 protocol-source 测试格式，不能影响裸 JPEG MVP，也不能宣称与 FPGA ABI 兼容。 |
| 需要板卡或 FPGA 队友 | 否。 |

## C. JPEG 验证与解码

| 项目 | 内容 |
|---|---|
| 输入条件 | B 可提供合法和损坏 JPEG；选择 host 可用的 JPEG 解码库/运行时，但不在本轮设计阶段安装。 |
| 交付文件 | `JpegPayloadValidator`、`TransportRecordValidator`、`ProtocolParser`、JPEG decoder adapter、解码像素格式约定、长度/边界检查、分层错误测试和耗时指标。 |
| 验收标准 | 裸 JPEG 和通过传输校验的 record 都能解码为 `DecodedFrame`；`JpegPayloadValidator` 拒绝空/超长/截断/非法 SOI/EOI payload 且不要求 wire header；`TransportRecordValidator` 仅拒绝 record 的错误 magic/version/header_size/flags/payload_length/启用时 CRC，且失败时不产生 `EncodedFrame`；独立 `SequenceTracker` 对 duplicate/gap/out-of-order 只记数，payload 有效帧仍产生连续 `ingest_id`。解码得到的宽高能与 metadata 声明比较并记录不一致。 |
| 依赖的 TBD | JPEG 是否标准兼容、编码模式/采样、实际最大长度、CRC 算法与覆盖范围、协议版本/头尺寸仍 TBD（P0-04、P2-01）。实现必须以可配置限制和 feature flag 隔离。 |
| 需要板卡或 FPGA 队友 | 否；但真实 FPGA JPEG 兼容性只能待队友/板端样本确认。 |

## D. MockInferenceBackend

| 项目 | 内容 |
|---|---|
| 输入条件 | C 能产出稳定 `DecodedFrame`；定义一个小型 mock 模型输入规格和预处理/后处理契约。 |
| 交付文件 | Preprocessor、`MockInferenceBackend`、Postprocessor、确定性 detection fixture、模型/类别/阈值配置接口。 |
| 验收标准 | mock 对同一输入产生可预测结果，且结果保留 `ingest_id` 与可选 `wire_sequence` 关联；可模拟推理延迟和单帧/初始化故障；坐标变换可逆或可检查；无 RKNNLite wheel、无真实模型也能完成测试。 |
| 依赖的 TBD | 最终模型、类别集、输入尺寸、量化、NPU core 策略和准确率门槛 TBD（需求 Q6）。 |
| 需要板卡或 FPGA 队友 | 否。 |

## E. 连续流水线和指标

| 项目 | 内容 |
|---|---|
| 输入条件 | A--D 的 source、验证、解码、预处理、mock backend 和 sink 都可单独测试。 |
| 交付文件 | 四工作线程/任务编排、有界 `encoded/decoded/result` 队列、drop 策略、干净退出/错误传播、JSONL 或控制台 sink、metrics 汇总和离线集成测试。 |
| 验收标准 | 连续运行时内存受队列/字节预算约束；在快 source/慢 mock inference 下执行配置的 drop-oldest（或明确的安全替代）并报告原因；输出接收/丢弃/非法帧、JPEG/推理/端到端耗时、FPS、队列深度；断连重连与致命错误能停止、join、输出摘要。 |
| 依赖的 TBD | FPGA slot 过载策略与 source timestamp 域仍 TBD；本阶段只定义 Linux 内部队列行为，不能外推为 FPGA backpressure 合同或跨端延迟。 |
| 需要板卡或 FPGA 队友 | 否。此阶段完成即为第一个虚拟机 MVP。 |

## F. SGDMA 适配

| 项目 | 内容 |
|---|---|
| 输入条件 | E 的 pipeline 契约稳定；RK3576 板卡可用；取得经授权的 SGDMA 驱动/BSP；P0 和 P1 中的关键 FPGA 回答已冻结，至少包括 EP/RC角色、实际身份、BAR/能力发现、C2H、长度发现、帧边界、slot metadata/所有权，以及 **P1-08 最小复位与重新同步合同**：PCIe 链路复位后的状态、FPGA 复位后的 slot 初始化、Linux 进程重启重新同步、stale `READY/READING` 清理、producer/consumer 索引重置、驱动/设备重新打开和协议版本重新读取流程。未确认前只允许接口/占位实现，不得宣称 SGDMA 真实接入完成，也不得进入依赖恢复流程的验收测试。 |
| 交付文件 | Python `SgdmaFrameSource`、动态 PCI/字符设备发现、能力/配置记录、DMA buffer 生命周期、BAR/slot/DMA 传输信息获取、`ProtocolParser`/`TransportRecordValidator` 集成、统一 `EncodedFrame` 转换、slot 认领/回收、超时/重发现状态机、板端诊断记录和受控测试程序。根据最终驱动接口在 `os.open`/`os.read`、`fcntl.ioctl`、`mmap` 中选择实际可用方式；不预设任一方式、节点或 ioctl ABI。 |
| 验收标准 | 以真实枚举结果记录 BDF、BAR resource、实际 C2H 节点和能力；完成固定小数据 C2H、单个完整 JPEG 的长度/完整性/解码、多 slot 连续接收、无 EMPTY/消费慢时的计数，以及按 P1-08 执行一次最小复位/重新同步验证。绝不硬编码课程示例 BAR、BDF 或节点；不把 read 返回长度擅自当帧边界，除非实测/合同已确认。自动重连、多级超时和不中断推理热恢复不属于本阶段验收。 |
| 依赖的 TBD | P0-04--07、P1-01--08：JPEG 兼容性/上限、SGDMA 实际节点与对齐、BAR ABI、slot/状态/可见性、EOP、轮询/IRQ，以及最小复位/重新同步合同。P2 的高级恢复优化（自动重连、多级超时、详细错误计数、故障注入、不间断推理热恢复）不阻塞此阶段入口。 |
| 需要板卡或 FPGA 队友 | 是，两者都需要。加载模块、设备树修改、重启等需另行获得明确批准。 |

## G. RKNNLite 适配

| 项目 | 内容 |
|---|---|
| 输入条件 | RK3576 aarch64 板卡、与 BSP 匹配的 RKNNLite runtime/wheel、模型及类别文件均可合法取得；E 的 backend 契约已稳定。F 不是严格前置条件：可先以 MockFileFrameSource 在 target 验证 NPU。 |
| 交付文件 | 基于官方 RKNNLite Python 接口的 `RKNNLiteBackend`、target 部署/版本核验说明、模型配置、输入/输出 tensor adapter、与 mock 结果的接口一致性测试、NPU耗时与错误日志。 |
| 验收标准 | 只在 target 安装并导入匹配 aarch64 wheel；能以本地 JPEG fixture 完成模型加载、预处理、推理、后处理和结果关联；记录模型/runtime/板端版本及推理耗时；失败时能释放 runtime 并输出诊断。 |
| 依赖的 TBD | 模型/类别/量化/输入规格/性能门槛/NPU core 策略 TBD；target runtime 与 BSP ABI 需实测确认。 |
| 需要板卡或 FPGA 队友 | 需要板卡；不需要 FPGA 队友即可用 mock 输入完成本阶段。 |

## H. 实机性能优化

| 项目 | 内容 |
|---|---|
| 输入条件 | F 与 G 已在真实 JPEG + NPU 上形成稳定端到端链路；双方冻结协议和度量口径；有可重复的输入工作点和测试持续时间。 |
| 交付文件 | 性能基线/对比报告、调优配置、CPU/内存/队列/吞吐 trace、必要时的轮询与 IRQ 对比、候选 V4L2 MJPEG 或 RKNN C API/C++ 评估记录。 |
| 验收标准 | 对指定工作点量化接收帧数、分类丢帧、非法帧、JPEG解码时间、推理时间、端到端时间、FPS、队列深度，并与 FPGA 侧压缩率/资源/采集计数统一口径；优化不能破坏错误恢复、帧关联或协议校验。 |
| 依赖的 TBD | P2-01--06：时间戳/CRC/序号、错误计数、**高级恢复优化**、测试向量、FPGA 性能计数和版本标识；PCIe 实际链路能力和 IRQ 可用性也须实测。最小复位/重新同步合同已是 P1-08 的 Stage F 入口条件。 |
| 需要板卡或 FPGA 队友 | 是，两者都需要。 |

## 阶段门与决策点

1. A--E 后，评审 mock MVP 的接口是否足以隔离硬件 TBD；若否，只调整用户态抽象，不以猜测补齐硬件参数。
2. F 前，FPGA 队友应填写确认清单并共同更新接口文档；协议未冻结时不开始真实 DMA 接收实现。
3. G 可与 F 并行但只在板端进行；x86_64 继续使用 `MockInferenceBackend`。
4. H 仅在测量显示持续丢帧、队列长期积压、Python 协议解析占用明显、拷贝开销影响端到端延迟，或无法达到最终实测目标时，才评估 C++ 共享库加 Python binding、C++ 独立采集进程加共享内存，或全 C++/RKNN C API。不得虚构具体性能阈值，也不以预期性能提前引入 IPC 或重写。

## 非交付项（本轮）

本路线图不创建代码、不安装依赖、不加载模块、不改设备树、不烧录/重启、不实现 FPGA 内容、不修改 `local_refs/official_package`，也不提交 Git。大型模型、wheel、运行产物不应提交 Git。
