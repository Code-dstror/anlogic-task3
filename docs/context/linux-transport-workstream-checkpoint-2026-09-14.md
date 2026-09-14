# Linux transport/system 工作流检查点

- 日期：2026-09-14
- 状态：**Current checkpoint**
- 工作流：**Linux transport/system**
- 基线：`main` `c558b49`；Linux HEAD `61d6232`

本文记录 Linux transport 工作流在本检查点已验证的事实、已冻结的软件边界、
FPGA 侧的 Proposed 项与尚待确认的事项。它不记录凭据，也不把硬件假设写成
既成事实。

## 已验证事实

### Git 检查点

- 仓库为 `Code-dstror/anlogic-task3`（Private）。
- `main`、`origin/main`、`backup/main` 与标签 `checkpoint-c558b49` 的已知基线
  均为 `c558b49`。
- 当前 Linux 分支为 `feature/linux-transport`，HEAD 为 `61d6232`；
  `origin/feature/linux-transport` 同样指向该提交。
- 创建本文档前，`git status --short` 无输出，工作区干净。
- `8a55317` 与 `61d6232` 当前只存在于 `feature/linux-transport`；不得声称它们
  已进入 `main`。
- 禁止 force push。

### 自上一检查点完成的提交

| 提交 | 已完成内容 |
|---|---|
| `8a55317` | `test(pipeline): add deterministic corrupt frame source`：新增确定性的 `MockCorruptFrameSource` 及其独立回归测试，用于在 source 边界注入一次 payload 尾部截断。 |
| `61d6232` | `feat(pipeline): add single-frame orchestration`：新增不依赖硬件、每次仅处理一个 source 事件的 `SingleFramePipeline` 及其独立回归测试。 |

两个原子任务均完成了实现、Custom `/review`、针对审查意见的修复、第二次 Custom
`/review`、commit 与 push。完整离线 `unittest` 共 100 项通过。没有进行 RK3576、
PCIe、SGDMA 或 FPGA 硬件测试。

## 已冻结的软件边界

### MockCorruptFrameSource

`MockCorruptFrameSource` 包装既有 `FrameSource`，按零基、仅针对成功产生的
`FRAME` 事件序号选择一次目标。它只实现 payload 尾部截断；不实现随机故障、
bit flip、延迟、超时或硬件错误脚本。

- 非 `FRAME`、EOF 与 source exception 不消耗成功 `FRAME` 计数；非目标事件原样
  透传。
- 成功 delegated `start()` 后，wrapper 从序号零重新计数，并允许新一轮再次注入；
  delegated `start()` 失败时不得提前重置 wrapper 状态。
- 损坏帧是独立的 `EncodedFrame` 副本；metadata 中契约允许的嵌套可变值被隔离，
  不与原帧共享。
- `payload_length` 始终同步为截断后 payload 的实际长度。

### SingleFramePipeline

冻结 API 为：

```python
SingleFramePipeline(
    source,
    validator,
    decoder,
    sequence_tracker,
    metrics,
)

process_next(stop_event) -> DecodedFrame | FrameEvent
```

每次 `process_next()` 的处理顺序为：

```text
source.next_frame
→ 非 FRAME 原样返回
→ FRAME record_received
→ 可选 SequenceTracker.observe
→ JpegPayloadValidator.validate
→ decoder.decode
→ record_delivered
→ 返回 DecodedFrame
```

- 传入的 `stop_event` 原对象交给 source。
- validator 返回的 `EncodedFrame` 是 decoder 的输入；成功时原样返回 decoder 生成的
  `DecodedFrame`。
- 该类不负责 source 的 `start()`、`stop()` 或 `health()`，也不负责循环、线程、
  队列、重试、重连或恢复。

### 错误与 RuntimeMetrics 所有权

`SingleFramePipeline` 是这个单次切片中一个 `FRAME` 从 received 到 delivered/drop
的唯一记账者。每个失败 `FRAME` 最多记录一次 drop；非 `FRAME` 不更新 FRAME
metrics。

| 情形 | 传播与 metrics |
|---|---|
| `SourceError` | 调用一次 `record_source_error()` 后原样传播；不记 received 或 drop。 |
| sequence `ValidationError` | 原样传播；调用一次 `record_drop("sequence_validation:<code>")`。 |
| JPEG `ValidationError` | 调用 `record_jpeg_invalid(code)`，再调用一次 `record_drop("jpeg_validation:<code>")`，并原样传播。 |
| `DecodeError` | 调用一次 `record_drop("jpeg_decode:<code>")` 后原样传播。 |

`DUPLICATE`、`GAP`、`OUT_OF_ORDER` 仅记录对应 sequence anomaly，仍继续处理有效帧。
当前此切片不使用 transport-invalid、source-reconnect 或 queue-depth metrics。

### SequenceTracker

`SequenceTracker` 仍是单一有序 ingest stream 的非回绕、线性诊断器：

- `FIRST`、`IN_ORDER`、`GAP` 推进高水位。
- `DUPLICATE`、`OUT_OF_ORDER` 不推进高水位。
- sequence anomaly 只作诊断，不丢弃有效帧。

序号位宽、回绕、`stream_epoch`、`reset_counter` 与 FPGA reset 到 tracker `reset()`
的映射仍为 TBD。

## 工作流边界

Linux 当前稳定输出为 `bgr24` 的 `DecodedFrame`。AI/application owner 从
`DecodedFrame` 开始负责后续工作；已观察到的官方 Python 示例执行 BGR→RGB、使用
640×640 letterbox 并增加 batch 维度。其 Python 输入边界表现为 RGB、NHWC、`uint8`，
精确 shape 为 `(1, 640, 640, 3)`。这是当前 AI 交接基线，不代表已完成 RK3576
实机验证；`.rknn` 内部 NCHW/`int8` 与 Python 边界之间的转换仍需 RK3576 实机确认。
`PreprocessedFrame` 与 `ModelInput` 仍未实现和冻结，Linux workstream 不应抢先定义。

FPGA、Linux transport 与 AI/application 继续保持独立 workstream。后续由集成负责
人逐个分支合并；每次合并前运行完整测试和 Custom `/review`。`local_refs` 与
`local_refs/official_package` 均只读且不进入 Git。

## FPGA 接口状态

### Proposed，尚未冻结

- 官方 SGDMA 工程可能作为 PCIe EP 基线，但尚无枚举或吞吐实测证据。
- FPGA DDR 计划使用 4 个 slot。
- 每 slot JPEG payload 上限暂定 16 MiB，另加固定帧头。
- 1080p60 时平均 JPEG 尽量不超过约 4 MiB/帧，即约 240 MiB/s。
- 超限帧计划丢弃并上报错误。

### TBD，禁止据此实现

以下都尚未冻结：slot 状态机；“始终发送最新完整帧”的覆盖策略；payload 长度
发现；header 字段、布局与大小端；sequence 位宽与回绕；stream epoch/reset counter；
BAR 与寄存器偏移；IRQ；FPGA reset 映射；以及 PCIe 实测吞吐。

在这些合同经双方确认前，当前不得实现任何写死这些内容的
`TransportRecordValidator`，也不得实现依赖它们的 PCIe/SGDMA source 行为。

## 当前明确未实现的内容

- `TransportRecordValidator`。
- PCIe/SGDMA 实际 `FrameSource` 与设备发现。
- source 生命周期 runner、后台循环与队列。
- 重连、恢复与 FPGA reset 处理。
- RKNN、预处理、推理与输出。

## 下一阶段门禁

继续新增代码前，应优先取得或决定以下两类事项之一：

1. FPGA 精确的 header、slot、sequence 与 reset 契约；或
2. 无硬件 source 生命周期 runner 对 `NO_DATA`、`RECOVERABLE_DISCONNECT`、
   `FATAL_ERROR`、`END_OF_STREAM` 的处置策略。

本检查点不替团队冻结上述尚未决定的策略。
