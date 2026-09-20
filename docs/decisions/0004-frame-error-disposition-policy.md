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

`CONTINUE_NEXT_FRAME` 路径为：

- `ValidationError`，`stage == "jpeg_payload_validation"`，且 code 为
  `jpeg_payload_empty`、`jpeg_payload_too_short`、`jpeg_payload_too_long`、
  `jpeg_payload_invalid_soi` 或 `jpeg_payload_invalid_eoi`。
- `DecodeError`，`stage == "jpeg_decode"`，且 code 为 `jpeg_decode_failed`。
- `ValidationError`，仅当调用方已经完成 record 边界组装并提供**恰好一条** PCIe v1
  record 候选时，以下 `(stage, code)` 组合可以按单 record 丢弃：
  - `transport_record_validation`：`record_header_truncated`、`record_too_large`、
    `record_invalid_frame_magic`、`record_invalid_protocol_version`、
    `record_invalid_header_length`、`record_invalid_flags`、
    `record_invalid_reserved0`、`record_invalid_reserved1`、
    `record_payload_length_zero`、`record_payload_length_exceeds_max`、
    `record_payload_truncated`、`record_trailing_bytes`。
  - `transport_record_mapping`：`record_error_code_nonzero`。

已知的 `sequence_tracking / invalid_wire_sequence`、`jpeg_decode_cv2_error`、
`jpeg_decode_invalid_image`、`transport_record_buffer_access`、`record_not_bytes_like`、
`invalid_record`、`invalid_ingest_id`、`invalid_received_monotonic_ns`、
`invalid_source_name`、所有 `SourceError`、所有 `ConfigurationError`、其他
`PipelineError`、未知 code、错误 stage 或错误异常类（包括子类）均为 `PROPAGATE`。
新增可继续的 code 必须经过单独评审，并同步更新本 ADR、分类器和测试。

## Metrics 与传播

分类器是纯函数：不捕获异常、不修改 error、不记 metrics，也不执行循环。
`SingleFramePipeline` 已负责 received、drop、JPEG-invalid、source-error 与原异常传播；
当 source 在上述完整单 record 边界前提下抛出 allowlisted transport `ValidationError`
时，它调用一次 `record_transport_invalid(code)` 与一次
`record_drop("transport_validation:<code>")`，随后原样重抛。此类 record 在得到
`FRAME` event 前已被拒绝，因此不会增加 `frames_received`；相应地
`transport_records_invalid` 和 `frames_dropped` 不要求满足 `dropped <= received`。
runner 只分类和返回 `DROPPED_FRAME`，不得重复记账。

生命周期 runner 在捕获 `ValidationError` 或 `DecodeError` 后调用分类器：
`CONTINUE_NEXT_FRAME` 时继续处理后续帧，`PROPAGATE` 时把原异常交给外部 supervisor。
本 ADR 不处理 `FrameEventKind.RECOVERABLE_DISCONNECT`，它仍由 ADR 0003 处置；
也不负责 `SourceError` 重试、设备发现、恢复或 reset。

## Consequences

- 已知损坏 JPEG 可以继续后续帧。
- OpenCV runtime/契约异常、sequence 输入错误和未知错误会上交，而不会无限吞掉。
- buffer access、mapper 调用契约错误、未知 transport 错误，以及尚未具备完整 record
  边界的真实 framing 丢失均会上交；它们不能被当作一条可安全丢弃的 record。
- `recoverable=False` 的 allowlist 错误仍可继续；非 allowlist 错误即使
  `recoverable=True` 也传播。
- 本 ADR 只解决 ADR 0003 中 `ValidationError`/`DecodeError` 后是否继续的 Deferred
  项，不修改其非 `FRAME` 事件策略。

## Out of scope

- runner API、循环、线程、队列、source 生命周期与 polling/backoff。
- 自动恢复、PCIe/SGDMA、设备发现，以及真实 SGDMA record 边界发现和恢复。一次
  read 或 completion 不被假定等于一帧；本决策不声称自动恢复或真实 DMA 已完成。
- FPGA header、slot、BAR、IRQ、reset；stream epoch、sequence 位宽与回绕。
- application callback、预处理、RKNN 与输出。
