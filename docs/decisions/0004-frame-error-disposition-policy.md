# 0004：单帧错误处置策略

- 状态：**Accepted for hardware-independent Linux runner v1**
- 日期：2026-09-14
- 决策方：Linux transport workstream
- 关联：[0003](0003-linux-lifecycle-runner-event-policy.md)

## Context

ADR 0003 将 `ValidationError` 与 `DecodeError` 后是否继续处理下一帧留为
**Deferred**。当前所有生产 `PipelineError` 均使用默认 `recoverable=False`，因此该字段
不是可用的 runner 控制流契约。需要让确定的单帧坏 JPEG 不终止流，同时不能吞掉未知、
运行时或程序契约错误。

## Decision

v1 采用异常**精确类**、`stage` 与 `code` 的 allowlist 分类；三者必须同时匹配。
分类器 fail-closed：不在 allowlist 中的任何 `PipelineError` 都为 `PROPAGATE`，并且
不依据 `recoverable`。

唯一的 `CONTINUE_NEXT_FRAME` 路径为：

- `ValidationError`，`stage == "jpeg_payload_validation"`，且 code 为
  `jpeg_payload_empty`、`jpeg_payload_too_short`、`jpeg_payload_too_long`、
  `jpeg_payload_invalid_soi` 或 `jpeg_payload_invalid_eoi`。
- `DecodeError`，`stage == "jpeg_decode"`，且 code 为 `jpeg_decode_failed`。

已知的 `sequence_tracking / invalid_wire_sequence`、`jpeg_decode_cv2_error`、
`jpeg_decode_invalid_image`、所有 `SourceError`、所有 `ConfigurationError`、其他
`PipelineError`、未知 code、错误 stage 或错误异常类均为 `PROPAGATE`。新增可继续的
code 必须经过单独评审，并同步更新本 ADR、分类器和测试。

## Metrics 与传播

分类器是纯函数：不捕获异常、不修改 error、不记 metrics，也不执行循环。
`SingleFramePipeline` 已负责 received、drop、JPEG-invalid、source-error 与原异常传播；
未来 runner 不得重复记账。

未来 lifecycle runner 可以在捕获 `ValidationError` 或 `DecodeError` 后调用分类器：
`CONTINUE_NEXT_FRAME` 时继续处理后续帧，`PROPAGATE` 时把原异常交给外部 supervisor。
本 ADR 不处理 `FrameEventKind.RECOVERABLE_DISCONNECT`，它仍由 ADR 0003 处置；
也不负责 `SourceError` 重试、设备发现、恢复或 reset。

## Consequences

- 已知损坏 JPEG 可以继续后续帧。
- OpenCV runtime/契约异常、sequence 输入错误和未知错误会上交，而不会无限吞掉。
- `recoverable=False` 的 allowlist 错误仍可继续；非 allowlist 错误即使
  `recoverable=True` 也传播。
- 本 ADR 只解决 ADR 0003 中 `ValidationError`/`DecodeError` 后是否继续的 Deferred
  项，不修改其非 `FRAME` 事件策略。

## Out of scope

- runner API、循环、线程、队列、source 生命周期与 polling/backoff。
- 自动恢复、PCIe/SGDMA、设备发现。
- FPGA header、slot、BAR、IRQ、reset；stream epoch、sequence 位宽与回绕。
- application callback、预处理、RKNN 与输出。
