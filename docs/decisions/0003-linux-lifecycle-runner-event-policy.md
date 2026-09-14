# 0003：Linux source lifecycle runner 事件处置策略

- 状态：**Accepted for hardware-independent Linux runner v1**
- 日期：2026-09-14
- 决策方：Linux transport workstream
- 关联：[Linux transport 检查点（2026-09-14）](../context/linux-transport-workstream-checkpoint-2026-09-14.md)

## 决策

本决策只冻结未来无硬件 Linux lifecycle runner 的控制流边界；它不实现 runner，
也不冻结 FPGA header、slot、sequence 位宽、stream epoch、reset 或真实重连实现。

`SingleFramePipeline` 继续只处理一次 `process_next()`，不管理 lifecycle。未来的
lifecycle runner 只负责分类其返回的 `FrameEvent` 和传播的异常；硬件恢复动作由未来
外部 supervisor 或 transport 实现负责。

- runner 不得在内部无限忙轮询。
- 非 `FRAME` 事件必须保留原始 `FrameEvent` 与 `detail`，不得改写为伪造异常。
- v1 不自动重连、不自动 reset FPGA，且不重置 `SequenceTracker`。
- 同一事件的不同指标可按既有契约分别更新，但同一处理层不得对同一指标重复记账。
  lifecycle runner 也不得重复记录已经由 `SingleFramePipeline` 负责的指标：FRAME 的
  received、成功 FRAME 的 delivered、sequence anomaly、sequence/JPEG/decode 失败的
  drop、JPEG validation invalid，以及 `source.next_frame()` 抛出的 `SourceError`。
  lifecycle 层只记录由其负责的非 FRAME 生命周期事件，例如
  `RECOVERABLE_DISCONNECT` 与 `FATAL_ERROR` 各自的一次 source error。

## 事件处置

### NO_DATA

`NO_DATA` 表示当前暂时没有帧，不是错误，也不是 EOF。runner 应立即将同一个
`NO_DATA` `FrameEvent` 返回给调用者，并保持可继续处理状态。

- 不调用 sleep，不在内部自旋，也不自行选择轮询间隔。
- 不更新 `source_error`、`source_reconnect`、drop、received 或 delivered metrics。
- 调度、等待和退避由调用者或未来 supervisor 决定。

### RECOVERABLE_DISCONNECT

`RECOVERABLE_DISCONNECT` 表示当前 source 通路断开，但事件声明未来可能恢复。
runner 返回同一个事件及其 `detail`，并结束当前连续处理阶段，不立即再次调用 source。

- lifecycle 层对此事件调用一次 `RuntimeMetrics.record_source_error()`。
- 不记录 frame drop，因为该事件没有交付 `EncodedFrame`。
- runner 内不自动重连、重新 `start()`、重新枚举设备或 reset FPGA。
- 只有未来外部恢复流程实际成功后，才允许该恢复流程调用
  `RuntimeMetrics.record_source_reconnect()`；v1 runner 不调用它。
- “recoverable”不代表本轮调用自动成功恢复。

### FATAL_ERROR

`FATAL_ERROR` 表示当前 source 会话不可继续。runner 返回同一个事件及其 `detail`，
并进入当前运行阶段的终止状态。

- lifecycle 层调用一次 `RuntimeMetrics.record_source_error()`。
- 不记录 frame drop，因为没有收到 `EncodedFrame`。
- 不自动重启、重连或 reset。
- 是否重建整个 source/runner 由外部 supervisor 或操作人员决定。

### END_OF_STREAM

对 `MockFileFrameSource` 等有限 source，`END_OF_STREAM` 表示正常结束。runner 返回
同一个 `END_OF_STREAM` `FrameEvent`，正常终止当前运行阶段。

- 不记录 source error 或 frame drop。
- 不自动 restart source。
- 未来硬件 source 是否会产生 `END_OF_STREAM` 由其 transport 契约决定；本决策
  不作假设。

### SourceError exception

`SingleFramePipeline` 已在 `source.next_frame()` 抛出 `SourceError` 时调用
`RuntimeMetrics.record_source_error()` 一次，并原样传播该异常。lifecycle runner
捕获或观察该异常时不得再次调用 `record_source_error()`。

- v1 不依据 `SourceError.recoverable` 自动重试。
- runner 终止当前连续处理阶段，并把原异常交给调用者或外部 supervisor。
- 未来恢复策略可以读取 `recoverable`，但必须另行决策。

## FRAME 阶段错误与 sequence

本决策不改变 `SingleFramePipeline` 已有契约：

- sequence `ValidationError`、JPEG `ValidationError`、`DecodeError` 都发生在已收到
  `FRAME` 后，因此 received 已记录；三条失败路径均由 `SingleFramePipeline` 以各自
  准确 reason 记录一次 drop，并原样传播。lifecycle runner 不得重复记录 received 或
  drop。
- sequence `ValidationError` 的 drop reason 为 `sequence_validation:<code>`；它不调用
  `record_jpeg_invalid()`，也不记录 delivered。
- JPEG `ValidationError` 调用一次 `record_jpeg_invalid(code)`，其 drop reason 为
  `jpeg_validation:<code>`，且不记录 delivered。
- `DecodeError` 的 drop reason 为 `jpeg_decode:<code>`；它不调用
  `record_jpeg_invalid()`，也不记录 delivered。
- JPEG-invalid 是 JPEG payload validation 阶段的专属指标，不适用于 sequence
  validation 或 JPEG decode failure。以上指标均由 `SingleFramePipeline` 负责，
  lifecycle runner 不得重复记账。
- 捕获单帧 `ValidationError` 或 `DecodeError` 后是否自动继续下一帧为 **Deferred**；
  在实现循环前必须单独决定。
- `DUPLICATE`、`GAP`、`OUT_OF_ORDER` 是 `SequenceTracker` 的正常诊断结果，
  不是 runner 终止条件。

## SequenceTracker 与 reset

`RECOVERABLE_DISCONNECT`、`FATAL_ERROR`、`END_OF_STREAM` 都不得隐式调用
`SequenceTracker.reset()`。source 再次 `start()` 成功也不得仅据此推断 sequence epoch
已改变。

何时 reset tracker 保持 **TBD**，必须等待 stream epoch、reset counter、sequence
位宽及 FPGA reset 映射冻结。当前继续使用非回绕线性语义。

## 状态与动作表

| 输入 | 返回原事件/异常 | 当前运行阶段终止 | source_error 增加 | frame drop 增加 | 自动恢复 | SequenceTracker reset |
|---|---|---|---|---|---|---|
| `NO_DATA` | 是，原 `FrameEvent` | 否 | 否 | 否 | 否 | 否 |
| `RECOVERABLE_DISCONNECT` | 是，原 `FrameEvent` 与 detail | 是 | 是，一次 | 否 | 否 | 否 |
| `FATAL_ERROR` | 是，原 `FrameEvent` 与 detail | 是 | 是，一次 | 否 | 否 | 否 |
| `END_OF_STREAM` | 是，原 `FrameEvent` | 是，正常结束 | 否 | 否 | 否 | 否 |
| `SourceError` exception | 是，原异常 | 是 | 否，已由 `SingleFramePipeline` 记一次 | 否 | 否 | 否 |

## 不在本决策范围

以下事项为 **Deferred** 或 **TBD**，不由本 ADR 决定：

- runner 的最终类名和公开 API；后台线程和队列；polling/backoff 时间。
- 自动设备发现；PCIe/SGDMA 重连；FPGA reset。
- stream epoch/reset counter；sequence 位宽和回绕。
- slot、header、BAR、IRQ。
- `ValidationError`/`DecodeError` 后是否自动继续。
- application callback、预处理、RKNN 和输出。

## 实现门禁与后续

实现最小 lifecycle runner 前，必须先决定单帧 `ValidationError`/`DecodeError` 后，
究竟继续还是终止当前运行阶段。

实现自动恢复前，必须获得 FPGA transport、device discovery、reset 与 stream epoch
的精确契约。不得因为本 ADR 使用“recoverable”一词，就假定硬件重连已经实现。
