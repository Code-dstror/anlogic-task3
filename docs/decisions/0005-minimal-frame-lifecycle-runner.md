# 0005：最小显式单步 Frame lifecycle runner

- 状态：**Accepted for hardware-independent Linux runner v1**
- 日期：2026-09-14
- 决策方：Linux transport workstream
- 关联：[0003](0003-linux-lifecycle-runner-event-policy.md)、[0004](0004-frame-error-disposition-policy.md)

## Context

ADR 0003 与 ADR 0004 已冻结非 `FRAME` lifecycle event 和单帧错误策略，但 runner 的
公开 API 与状态机仍未决定。需要一个不依赖硬件、同步且由调用者显式驱动的一步边界，
以交付成功帧、生命周期事件或已允许丢弃的单帧错误。

## Decision

`FrameLifecycleRunner` 接收一个 `FrameSource` 与 pipeline 阶段依赖，并在内部仅构造
一次 `SingleFramePipeline`。它提供 `start(config)`、`step(stop_event)`、`stop()` 与
`health()`；每次 `step()` 最多返回一个 `FrameStepOutcome`。

- runner 只使用 `IDLE`、`RUNNING`、`TERMINATED` 三态；状态不是 shared contract。
- 非 `RUNNING` 的 `step()` 抛出 `ConfigurationError`，code 为 `runner_not_running`；
  `RUNNING` 时重复 `start()` 抛出 `runner_already_running`。
- `DELIVERED`、`EVENT`、`DROPPED_FRAME` outcome 恰好携带一个原对象；不复制对象。
- `NO_DATA` 保持运行；`RECOVERABLE_DISCONNECT`、`FATAL_ERROR`、`END_OF_STREAM` 终止
  本轮运行。终止事件或异常只在首次 step 交付，不缓存或重放。
- `ValidationError`/`DecodeError` 依 ADR 0004 分类：allowlist 返回 dropped outcome，
  否则终止并原样传播。其他异常同样原样传播并终止。
- 只有显式且成功的 `start()` 才进入 `RUNNING`；它不是恢复流程。`stop()` 只委托给
  source，不承诺比 source 更强的幂等性。
- runner 从不调用 `SequenceTracker.reset()`；成功 start 不代表 stream epoch 改变。

## Metrics ownership

遵循 ADR 0003/0004：`SingleFramePipeline` 是 FRAME 的 received、delivered、drop、
JPEG-invalid、sequence anomaly 及 `SourceError` exception 的唯一记账者。runner 仅对
`RECOVERABLE_DISCONNECT` 与 `FATAL_ERROR` 各记录一次 source error。它不记录 drop、
reconnect、transport-invalid 或 queue-depth；`NO_DATA` 与 `END_OF_STREAM` 不记指标。

## Consequences

- 没有内部循环或 busy polling。
- 调用者可明确观察 delivered、event 与 dropped error。
- allowlist 错误不会被静默吞掉；PROPAGATE 错误 fail-closed。
- 外部 supervisor 仍负责调度、等待及恢复。

## Out of scope

- 自动循环、线程、队列、sleep/backoff。
- application callback。
- 自动恢复、设备发现、PCIe/SGDMA。
- FPGA reset、stream epoch、sequence reset。
- header、slot、BAR、IRQ。
- RKNN 和输出。
