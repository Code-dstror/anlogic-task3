# 赛题 3 Linux 用户态处理流水线架构

- 状态：**Proposed（设计草案，未冻结）**
- 日期：2026-09-13
- 范围：为 Ubuntu x86_64 离线开发和未来 RK3576 aarch64 联调定义用户态模块边界；本轮不实现代码。
- 依据：[赛题需求](../requirements/task3-requirements.md)、[平台基线](../hardware/platform-baseline.md)、[PCIe Linux 基线](../analysis/pcie-linux-baseline.md)、[决策 0001](../decisions/0001-pcie-primary-mipi-fallback.md)、[决策 0002](../decisions/0002-sgdma-char-device-first.md)、[JPEG 协议草案](../../interface/pcie-jpeg-protocol-v0.1.md)和 [FPGA 确认清单](../coordination/fpga-confirmation-checklist.md)。

## 1. 目标与约束

目标是建立一条可由 mock 输入离线验证、以后可替换为 SGDMA 接收和 RKNN 推理的连续处理链。赛题最终需要 FPGA JPEG/LZ77 压缩流经 PCIe 或 MIPI 到 RK3576 并完成本地目标检测；本架构针对当前候选的 **JPEG + PCIe + SGDMA 字符设备** 路线设计，但不将该候选、链路代际或任何硬件参数写死。

以下均保持 TBD，且不得在软件中硬编码：PCIe 代际/BDF、Vendor/Device ID、BAR 编号或偏移、SGDMA `/dev` 节点和 C2H 通道、slot 数/容量/stride、DMA 完成与一帧 EOP 的关系、CRC 算法、时间戳单位、JPEG 最大尺寸/分辨率/帧率。实际设备应在 target 运行时发现或经显式配置取得；不得假设 `/dev/video73`、`/dev/video22` 或课程示例的任何参数存在。

传输记录来源先在 source 边界完成 `ProtocolParser → TransportRecordValidator → SequenceTracker → EncodedFrame` 转换；裸 JPEG 来源直接合成 `EncodedFrame`，不伪造 wire header。无论来源如何，公共流水线只接受完整逻辑编码帧；它并不承诺 SGDMA 的底层 `read()` 天然等于一帧。未来 SGDMA 适配层必须在冻结的 slot/descriptor/完成长度合同之上完成帧组装、传输层校验和所有权回收，才可发布 `EncodedFrame`。

## 2. 完整流水线与模块职责

```text
bare JPEG FrameSource ─────────────────────────────┐
Protocol-record source / SgdmaFrameSource            │
  → ProtocolParser → TransportRecordValidator        │
  → SequenceTracker                                 │
  → EncodedFrame ────────────────────────────────────┘
  → JpegPayloadValidator
  → JPEG Decoder
  → Preprocessor
  → Inference Backend
  → Postprocessor
  → Display / Recorder
                 └────────────→ Metrics（贯穿所有阶段）
```

| 阶段 | 输入 → 输出 | 职责与失败处理 |
|---|---|---|
| 裸 JPEG `FrameSource` | 本地 JPEG → `EncodedFrame` | 读取普通 JPEG，合成本地 metadata 后直接交给公共流水线；它不创建也不校验 PCIe wire header。可报告暂时无数据、可恢复断连或致命错误；不得交付半帧。 |
| `ProtocolParser` + `TransportRecordValidator` | wire record → 已验证 record | 仅用于 header + payload 的传输记录来源。parser 分离记录，validator 仅校验 magic、`protocol_version`、`header_size`、`payload_length`、flags 合法性和启用时的 CRC；这些错误均按传输错误丢弃。它不判断 sequence 是否连续。 |
| `SequenceTracker` | 已验证 record → `EncodedFrame` | 保存最近观察到的 `wire_sequence`，检测 duplicate、gap、out-of-order/向后跳变，并更新独立 metrics/log；v0.1 默认仅诊断，不因这些异常丢弃 payload 有效的帧。每个成功 `EncodedFrame` 都分配本地单调递增 `ingest_id`，并保留可选的 `wire_sequence`。未来可配置为丢弃的策略保持 TBD，不属于当前 MVP。 |
| `JpegPayloadValidator` | `EncodedFrame` → 经 payload 验证的 `EncodedFrame` | 所有来源共同经过。校验 payload 非空、配置的最大长度和 JPEG SOI/EOI；必要时可尝试解码作完整性验证，但不要求 wire protocol header。失败按 JPEG payload 错误丢弃，绝不送入后续阶段。 |
| `JPEG Decoder` | 编码 JPEG → `DecodedFrame` | 解码为明确声明的像素布局；从实际 JPEG 解码结果复核宽高，不盲信传输头中的声明。解码失败记为非法帧/解码错误并丢弃。 |
| `Preprocessor` | `DecodedFrame` → 模型输入张量/`PreprocessedFrame` | 颜色转换、resize、letterbox/crop、归一化、数据布局与量化。模型特定规则在此隔离，保留变换信息供结果映射。 |
| `Inference Backend` | `PreprocessedFrame` → 原始推理输出 | 只承担模型生命周期和执行，不读取设备、不解 JPEG、不渲染。失败经统一错误通道上报。 |
| `Postprocessor` | 原始输出 → `DetectionResult` | 置信度阈值、NMS、类别映射、坐标反变换，并与来源 `frame_id`/时间戳关联。类别、阈值和模型输入规格为可配置项。 |
| `Display/Recorder` | `DetectionResult`（可选原图/标注图）→ 外部可观察结果 | 可先实现结构化控制台/JSONL 输出；屏幕显示和录像是可插拔 sink，非赛题已明确的强制显示接口。sink 慢时不得反压阻塞推理主路径。 |
| `Metrics` | 各阶段事件 → `RuntimeMetrics` | 单调计数、阶段耗时直方/样本、队列水位和窗口 FPS；定期快照并在退出时汇总。 |

建议每个阶段只依赖相邻的数据模型和小接口。解码器、预处理器和推理后端不得知道 PCIe/BAR/slot；SGDMA 源不得依赖 RKNN 或显示库。

## 3. 输入源抽象

建议的概念接口（语言无关）为：`start(config)`、`next(stop_token) -> FrameEvent`、`stop()`、`health()`。`FrameEvent` 应可表达 `frame`、短暂 `no_data`、`recoverable_disconnect`、`fatal_error` 和 `end_of_stream`，从而避免把正常 mock 结束或设备重连误作非法图像。

| 实现 | 运行位置 | 作用与边界 |
|---|---|---|
| `MockFileFrameSource` | x86_64 / RK3576 | 输入为普通裸 JPEG 文件，按配置循环、排序或节流。它为每帧合成 `source_name=mock_file`、接收时间和等于文件大小的 `payload_length`；公共 ingest 层为成功帧分配本地连续 `ingest_id`。可选测试序号只作为 mock source metadata，不伪造正式 PCIe 协议 header。 |
| `MockProtocolRecordSource` / `ProtocolRecordFileSource` | x86_64 / RK3576 | 输入测试用的 `header + JPEG payload` record，专门经 `ProtocolParser`、`TransportRecordValidator` 和 `SequenceTracker` 覆盖 magic、version、length、CRC 及 sequence 诊断；成功后转换为统一 `EncodedFrame`。测试 record 格式可参考草案，但不得宣称已是冻结 FPGA ABI。 |
| `MockCorruptFrameSource` | x86_64 / RK3576 | 生成两类可复现错误：损坏的协议 record（magic/version/header/flags/length/CRC），以及合法协议 record 或裸 JPEG 中的损坏 JPEG payload（截断、超长、非法/缺失 SOI/EOI）。它还可生成 sequence duplicate/gap/out-of-order 诊断场景；这些有效 payload 帧不按传输错误丢弃。各类必须使用不同错误码、指标和预期结果。 |
| `SgdmaFrameSource` | 仅 RK3576 实机验证 | 第一版优先以 Python 从 BAR/slot/DMA 获得传输信息，完成 `ProtocolParser`/`TransportRecordValidator`/`SequenceTracker`、转换为含 `ingest_id` 和 `wire_sequence` 的 `EncodedFrame`、slot 认领/回收、超时和断连重发现。按最终驱动接口选择 `os.open`/`os.read`、`fcntl.ioctl` 或 `mmap`，不预设其中任一方式可用。BAR ABI、DMA 长度发现和 slot 状态机未冻结前，仅保留接口与 fake transport，不可声称可连接真实 FPGA。 |
| `V4L2FrameSource`（可选） | 主要为 RK3576 | 未来只在 FPGA 输出已被验证为标准 JPEG/MJPEG 且 V4L2 compressed capture 正确提供帧边界与 `bytesused` 后实现。节点通过枚举和能力匹配选择，不固定 `/dev/videoN`。它不是 SGDMA 版的前置条件。 |

`MockFileFrameSource` 的裸 JPEG 直接进入 `JpegPayloadValidator`，所以正常 JPEG fixture 有确定的成功路径。协议解析只由 `MockProtocolRecordSource` / `ProtocolRecordFileSource` 和未来 `SgdmaFrameSource` 覆盖；成功 record 经 `SequenceTracker` 获得连续 `ingest_id` 并保留 `wire_sequence`。测试 record 应通过共享 builder 生成，不能把 v0.1 草案的 `JPV0`、64 字节头、CRC 算法或 slot 参数当成已冻结生产 ABI。`SgdmaFrameSource` 的任何测试替身必须让上层只能看到 `EncodedFrame`，以防 hardware TBD 泄漏至解码/推理层。

## 4. 推理后端抽象

概念接口为：`load(model_config)`、`infer(preprocessed_frame) -> RawInferenceOutput`、`close()`，并由 backend 声明输入规格、版本和健康状态。预处理规则可以由模型描述或 backend 能力提供，但转换工作仍由 `Preprocessor` 完成并可离线单测。

| 后端 | 用途 | 约束 |
|---|---|---|
| `MockInferenceBackend` | x86_64 的稳定流水线测试。可按帧号产生确定性候选框/类别/延迟/故障，不要求模型文件或 NPU。 | 应可配置模拟延时以制造队列过载；输出必须可验证 frame 关联和后处理。 |
| `RKNNLiteBackend` | RK3576 上的首选 Python 后端；使用官方 RKNNLite Python 接口封装模型加载、`rknn_lite` 初始化、输入提交和输出释放。 | **不能**在 x86_64 虚拟机安装或运行 aarch64 RKNNLite wheel；仅在 target 的匹配运行时、模型和驱动条件满足后验证。官方 Python 示例只能作只读行为参考，不能复制进工程。 |
| `RKNN C API/C++ Backend` | RK3576 上的 C/C++ 候选；以 RKNN runtime C API 管理模型、tensor 和 NPU 执行。 | 头文件、库、ABI、模型格式和 target BSP 均需在板上核验；不可由 host 编译成功推断其可运行。 |

推理后端不得决定结果输出方式，也不得拥有采集线程；模型文件路径、类别标签和阈值应来自 target 配置。模型、aarch64 wheel、运行日志、录制视频和大规模 test 输出均不提交 Git，应通过忽略规则和部署清单管理。

## 5. 语言路线比较（Proposed）

| 路线 | 开发速度 | 性能 | 调试 | 部署 | 维护 | 结论 |
|---|---|---|---|---|---|---|
| 全 Python | mock、JPEG、可视化、协议迭代和 RKNNLite 原型最快；第一版可复用同一套模块边界。 | GIL、对象复制和高频 DMA/队列可能限制上限；须以 target 实测判断。 | 离线阶段和设备 bring-up 迭代友好；可以直接记录 `os`/`fcntl`/`mmap` 调用与协议事件。 | host 只使用原生依赖；target 另部署匹配的 Python/RKNNLite runtime，存在 ABI 差异。 | 单语言、无跨进程/跨语言协议，当前复杂度最低。 | **推荐（Proposed）**：MVP、首版 `SgdmaFrameSource` 和 `RKNNLiteBackend` 都优先采用 Python。 |
| C++ 共享库 + Python binding | 需额外设计 binding、内存所有权和异常边界，开发速度较慢。 | 可把已证实热点的 DMA/协议解析移出 Python，同时保留 Python 模型流程。 | 原生段可针对性 profile；binding 增加调试和 ABI 风险。 | 需维护 native 库与 Python 包的 target 构建、版本匹配。 | 适合局部热点，接口纪律要求较高。 | 后续优化候选；只在 Python 瓶颈有实测证据后评估。 |
| C++ 独立采集进程 + 共享内存 | 需要进程生命周期、共享内存布局、同步和错误恢复设计。 | 有机会降低跨语言复制并隔离采集故障，但收益必须测量。 | 采集与推理可分别观测，跨进程问题更复杂。 | 增加两个制品、权限和部署协调。 | 模块隔离更强，维护面也更大。 | 后续优化候选；当前不引入 C++ 与 Python IPC。 |
| 全 C++ + RKNN C API | 业务与模型迭代最慢。 | 可能减少跨语言/对象开销，适合极限优化。 | DMA 与推理可原生调试，但 RKNN tensor/后处理更复杂。 | 单个原生程序便于最终部署，仍依赖 target runtime ABI。 | 统一语言、接口少；模型和 RKNN API 变更直接影响主程序。 | 后续优化候选，不作为当前默认方案。 |

Python-first 的目的，是在没有板卡和 FPGA 联调条件时减少实现、部署和跨语言接口的复杂度，**不代表最终一定使用 Python**。第一版不引入 C++/Python IPC；`SgdmaFrameSource` 的 Python 实现仍只在协议、驱动与板端条件确认后进行。

迁移或局部下沉到 C++ 必须由性能测量触发，而不是预期触发。候选触发条件为：持续丢帧、队列长期积压、Python 协议解析占用明显、拷贝开销影响端到端延迟，或经完整实测仍无法达到最终目标。当前不虚构帧率、CPU 使用率或延迟阈值；每次迁移前应保存同一工作负载下的基线和瓶颈证据。

## 6. 并发、背压、退出与错误传播

### 6.1 线程/任务划分

初版采用四个长期工作者和一个受控 shutdown 协调器：

```text
采集线程 ─[encoded_queue]→ 解码线程 ─[decoded_queue]→ 推理线程 ─[result_queue]→ 输出线程
   │                               │                         │                    │
   └────────────────────────────── Metrics / structured logs ─────────────────────┘
```

- 采集线程负责 `FrameSource`，并在 source 可恢复断连时进入受限重试；它不执行 JPEG 解码。
- 解码线程执行验证、JPEG 解码和预处理。验证失败在此终止，不占用推理队列。
- 推理线程调用 backend、后处理并产生关联的 `DetectionResult`。
- 输出线程完成终端/JSONL/显示/录制等可选 sink。它不能持有会阻塞 slot 回收的 DMA 资源。
- `Metrics` 使用线程安全累积器或事件汇聚器；不得通过一个无界日志队列造成隐性内存增长。

队列必须有上限，容量是运行时配置而非 slot 数的别名。建议按帧个数和可选的字节预算双重限制，并记录当前深度、高水位和每个 drop 原因。每项队列容量、线程数、重试退避和超时均是可调配置，不是协议字段。

### 6.2 队列满时的策略

实时检测的默认策略为 **保留较新工作、在软件队列满时丢弃最旧且尚未被消费者取得的帧**（drop-oldest），以限制端到端陈旧度；每次丢弃要增加 `dropped_queue_overload`、保留被丢帧序号并让序号监测可解释 gap。若队列实现无法原子安全地撤销最旧项，则可先使用 drop-newest，但必须在配置和指标中明确，不能静默改变。

这只适用于 Linux 自己拥有的队列。FPGA slot 的策略仍受未冻结的所有权合同约束：当前协议草案建议无 `EMPTY` slot 时 FPGA 丢弃当前新帧、绝不覆盖 `READY/READING`。Linux 不得为了追求低延迟擅自覆盖 FPGA slot。输出队列可单独采用 drop-oldest，录像若要求完整性则应采用独立落盘策略并明确它可能降低实时性。

### 6.3 干净退出与错误传播

所有线程共享 `stop_token`、有界队列关闭语义和一个带阶段/错误码/可恢复性/原因链的 `PipelineError` 通道：

1. 正常结束或外部停止：停止 source 产生新帧，关闭 `encoded_queue`；下游排空已接收项目后依次关闭后继队列。
2. 致命错误：原子请求停止，唤醒所有阻塞队列/设备等待，取消或等待在途工作；`SgdmaFrameSource` 必须先停止 DMA、使本地 slot 失效并按已确认合同回收，再关闭 FD。
3. 可恢复 source 错误：记录错误与重试次数，丢弃不完整帧，重新进行设备发现和能力读取；恢复成功前不复用旧 BDF/BAR/FD/slot 视图。
4. backend 或 decoder 失败：单帧数据错误仅记数丢帧；模型加载失败、连续不可恢复 runtime 失败则升级为致命错误。
5. 协调器 join 全部线程、flush 最后 metrics、输出结构化失败摘要；不得以守护线程或直接进程退出跳过 DMA/文件资源释放。

## 7. 数据模型

以下为概念字段，不绑定 Python dataclass、C++ struct 或协议内存布局。可选字段应显式表示 unknown，而不是以 0、固定 BAR 或固定 slot 代替；`extensions` 保存版本化、来源限定的额外 metadata，避免每次协议演进击穿全部模块。

| 模型 | 建议字段 | 说明 |
|---|---|---|
| `FrameMetadata` | `ingest_id`（本地单调递增）、`frame_id`（可选本地 UUID）、`source_name`、`wire_sequence`（可选）、`received_monotonic_ns`、`source_timestamp` + `timestamp_domain`（可选）、`transport`、`encoding`、`declared_width/height`（可选）、`payload_length`、`integrity`（CRC 状态/算法标识）、`protocol_version`（可选）、`extensions` | 表达来源与可追溯性；不含 BAR 地址、固定 slot 编号或硬件常量。若 future source 有 slot token，它只在 source 私有生命周期内存在，帧离开 source 后不可依赖。 |
| `EncodedFrame` | `metadata`、只读 `payload`、`payload_capacity`、`acquired_monotonic_ns` | payload 是完整逻辑编码码流；如保留原始封装字节，只作为诊断附件并受大小上限保护。 |
| `DecodedFrame` | `metadata`、`pixels`、`width`、`height`、`pixel_format`、`row_stride`、`decoded_monotonic_ns` | 宽高/像素格式以解码器实际输出为准；可保留原声明用于 mismatch 诊断。 |
| `DetectionResult` | `ingest_id`、`frame_id`（可选）、`wire_sequence`（可选）、`source_timestamp`（可选）、`model_id/version`、`preprocess_transform`、`detections[{class_id,label,score,bbox}]`、`inference_started/finished_monotonic_ns`、`status/error` | 日志和输出同时记录 `ingest_id` 与 `wire_sequence`；坐标系必须标注（模型输入、解码图或两者）；输出无检测也应是成功结果，而非错误。 |
| `RuntimeMetrics` | `frames_received`、`frames_dropped`（按原因细分）、`transport_records_invalid`（magic/version/header/flags/length/CRC 分组）、`sequence_duplicate`、`sequence_gap`、`sequence_out_of_order`、`jpeg_payloads_invalid`（空/超长/SOI-EOI/解码分组）、`jpeg_decode_time`、`inference_time`、`end_to_end_time`、`fps`、各队列 `depth/high_watermark`，以及 source 重连/错误计数 | sequence 指标是独立诊断项而非 invalid/drop 计数；耗时采用单调时钟；对端 timestamp 未完成时钟同步前不得伪称跨端端到端延迟。提供总数、窗口值和分位数/直方统计的能力。 |

`wire_sequence` 与本地 `ingest_id` 分离：duplicate、gap、out-of-order 或回绕仍可被记录，而每个成功接收帧的本地 `ingest_id` 连续且关联不冲突。检测结果不能只用“当前帧”全局变量关联，必须携带 `ingest_id`，并在可用时携带 `wire_sequence`。

## 8. Host/target 边界与仓库卫生

| 范围 | 可做/应做内容 | 不可作为验证结论的内容 |
|---|---|---|
| Ubuntu 22.04 x86_64 虚拟机 | 数据模型、队列/退出、mock source、协议/JPEG 快速验证、JPEG 解码、预处理、mock 推理、后处理、结构化输出、离线测试与故障注入。可用 host 原生工具/依赖构建测试环境。 | 不安装 aarch64 RKNNLite wheel；不能验证 RKNN NPU、SGDMA 驱动/字符设备、PCIe 枚举/BAR、DMA、真实相机或性能数据。 |
| RK3576 aarch64 板端 | 运行时发现 PCIe/SGDMA/V4L2 节点、设备与协议兼容性、真实 JPEG、RKNNLite/C API、NPU性能、实际延迟/CPU/内存、断连/复位恢复。 | 不应由课程固定节点/分辨率替代实机能力查询；不应把 host 结果作为板端性能结论。 |
| 共同代码 | 与硬件无关的模型、validator、JPEG decoder adapter、preprocess/postprocess、队列协议、metrics、fixtures、mock backend 和配置 schema。 | 共同代码不应包含 target 私有 wheel、驱动二进制或 BAR/slot 具体值。 |

Git 不提交大型模型、RKNNLite wheel/SDK、驱动构建产物、录像/截图、原始大量 JPEG、日志、性能 trace、core dump 或下载缓存。应提交小型可再分发测试 fixture、fixture 生成说明、依赖版本清单/哈希以及部署步骤；大文件通过团队约定的制品存储或板端部署渠道提供。

## 9. 日志与性能指标

日志采用结构化、带 `frame_id`/`source_name`/阶段/错误码的记录，避免记录完整 payload 或敏感/巨大的图像内容。正常路径应按采样率记录，错误和状态转换完整记录；日志写入失败不得阻断实时主链。

最低运行时指标如下，均需在报告中注明统计窗口、工作负载、设备/模型版本和时间口径：

| 指标 | 定义/口径 |
|---|---|
| 接收帧数 | source 成功发布完整 `EncodedFrame` 的总数；不等于 FPGA 采集总数。 |
| 丢帧数 | 必须按 source、传输校验（magic/version/header/flags/长度/CRC）、JPEG payload、队列过载、解码、推理、输出和恢复阶段分类；sequence anomaly 不计为 v0.1 丢帧。 |
| 非法帧数 | 分为传输 record 错误（magic/version/header/flags/长度/CRC）与 JPEG payload 错误（空/超长/SOI-EOI/解码），不得混合统计。 |
| 序号异常 | 独立记录 `sequence_duplicate`、`sequence_gap`、`sequence_out_of_order`；v0.1 仅诊断，payload 有效帧继续处理，输出中以 `ingest_id` + `wire_sequence` 关联。 |
| JPEG 解码时间 | `JpegPayloadValidator` 通过后到得到 `DecodedFrame` 的单调时钟耗时，分别统计成功/失败。 |
| 推理时间 | backend 执行区间；模型前处理和后处理另计，不能混为 NPU 时间。 |
| 端到端时间 | 当前 host 阶段定义为 `result_finished_monotonic_ns - received_monotonic_ns`。只有 timestamp 域和跨端同步冻结并实测后，才能报告传感器/FPGA 到结果的跨端延迟。 |
| FPS | 以成功结果和接收帧各自按滑动窗口计算；不得只用理论 source 节流值。 |
| 队列深度 | 每个有界队列的瞬时深度、高水位、满次数和停留时间；用来解释延迟和丢帧。 |

## 10. 离线测试矩阵

| 场景 | 输入/注入 | 期望可观测结果 |
|---|---|---|
| 裸 JPEG 正常路径 | `MockFileFrameSource` 读取已知可解码文件 | 合成 `source=mock_file` 和文件大小 `payload_length`；成功帧获本地连续 `ingest_id`，跳过传输 record 校验，经 `JpegPayloadValidator` 后得到 1 个成功 `DetectionResult`。 |
| 合法协议 record | `MockProtocolRecordSource` / `ProtocolRecordFileSource` 输入合法 header + JPEG payload | 经 parser 和 `TransportRecordValidator` 成功转换为 `EncodedFrame`，再走同一 JPEG/推理路径。 |
| 连续多帧 | 循环或目录序列 | 序号和结果关联正确，干净 EOF/停止，无泄漏或线程残留。 |
| 不同 JPEG 长度 | 小/中/接近配置上限的合法 fixture | 均按真实长度处理；不以固定分辨率或固定帧长推断容量。 |
| 裸 JPEG 损坏 | `MockFileFrameSource` fixture 截断，或破坏 SOI/EOI | `JpegPayloadValidator` 或 decoder 拒绝，计入 JPEG payload 错误，不调用推理。 |
| 合法协议中的损坏 JPEG | 通过传输校验的 record，其 payload 截断或 SOI/EOI 无效 | 传输校验成功后由 `JpegPayloadValidator`/decoder 拒绝；计入 JPEG payload 错误而非 record 错误。 |
| 错误 magic/version/flags/length/CRC | `MockCorruptFrameSource` 生成损坏 protocol record | `TransportRecordValidator` 在转换 `EncodedFrame` 前拒绝；按字段分别计入传输 record 错误。CRC 未启用时明确为 not-verified，不伪校验。 |
| 重复和跳变帧序号 | payload 有效的 protocol record 重放、倒退、缺号、模拟回绕 | `SequenceTracker` 记录 duplicate/gap/out-of-order 且对应计数器增加；帧继续进入公共流水线并成功输出。测试验证本地 `ingest_id` 仍连续，输出同时记录 `ingest_id` 和 `wire_sequence`；回绕规则由 future 合同验证。 |
| 队列过载 | 快 source + 慢 mock inference/output | 有界内存，执行已配置的丢帧策略，drop 原因/队列高水位/延迟可解释。 |
| 模拟设备断开和重新连接 | source 产生可恢复断连后替换/恢复流 | 在途不完整帧丢弃；source 状态、重试和重连计数正确；不复用失效句柄/状态。 |

上述测试只证明用户态合同。真实 SGDMA、slot 所有权、EOP、BAR、CRC 算法、NPU性能及物理断连必须在板端和 FPGA 合同冻结后重新验证。
