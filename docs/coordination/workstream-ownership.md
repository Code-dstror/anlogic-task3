# Parallel workstream ownership

This document separates implementation ownership while preserving the shared
pipeline contracts. It does not freeze FPGA ABI details or model properties.

## FPGA workstream

Owns MIPI CSI sensor capture, FPGA JPEG encoding, PCIe Endpoint, SGDMA,
slot/BAR/IRQ, and FPGA-side protocol and reset implementation. This workstream
jointly maintains [the PCIe JPEG protocol](../../interface/pcie-jpeg-protocol-v0.1.md)
with Linux.

## Linux transport and system workstream

Owner: Linux owner.

Owns `MockProtocolRecordSource`, `TransportRecordValidator`,
`SequenceTracker`, PCIe record-to-`EncodedFrame` conversion, and
`SgdmaFrameSource`. It also owns driver build/load, device discovery, BAR/slot
consumption, reconnection, reset, deployment, and target system integration.
The completed `MockFileFrameSource`, `JpegPayloadValidator`, and
`OpenCvJpegDecoder` are maintained here. Its stable external handoff is a
`DecodedFrame`.

## AI and application workstream

Owner: AI/application owner.

Starts from the current `DecodedFrame` handoff. It proposes and implements the
planned `PreprocessedFrame` and `ModelInput` shared contracts, BGR-to-RGB
conversion, letterbox and model-input construction,
`MockInferenceBackend`, `RKNNLiteBackend`, YOLOv5 output parsing, NMS,
coordinate restoration, `DetectionResult`, JSONL/console output, annotated
display, and FPS, latency, and accuracy tests. It does not directly modify
SGDMA, PCIe record, or FPGA protocol implementations.

## Shared contracts

The following current types and files are not private to one workstream.
Adjacent workstreams must review changes before they are made:

- `linux/task3_pipeline/models.py`
- `linux/task3_pipeline/interfaces.py`
- cross-module error semantics in `linux/task3_pipeline/errors.py`
- `linux/task3_pipeline/__init__.py`
- `interface/pcie-jpeg-protocol-v0.1.md`
- current types: `FrameMetadata`, `EncodedFrame`, `DecodedFrame`, and
  `DetectionResult`. `DetectionResult` exists as a data type, but this does not
  mean the complete inference pipeline is implemented.
- reset/re-synchronization and performance-metric definitions

The planned, not-yet-implemented `PreprocessedFrame` and `ModelInput` are
shared contracts proposed and implemented by the AI/application workstream.
They require Linux and AI adjacent-workstream review before becoming stable;
they are not AI-private types. The current stable implementation handoff still
ends at `DecodedFrame`.

## Current handoff boundary

```text
FPGA wire/slot
→ Linux TransportRecord
→ EncodedFrame
→ JpegPayloadValidator
→ OpenCvJpegDecoder
→ DecodedFrame
→ AI Preprocessor
→ ModelInput
→ InferenceBackend
→ DetectionResult
→ OutputSink
```

## Git collaboration rules

- Merge this decoupling change into `main` before creating parallel branches.
- Suggested branches are `feature/linux-transport` and
  `feature/rknn-pipeline`.
- Each contributor uses an independent clone or worktree; contributors do not
  share one working tree.
- One commit handles one module or one shared contract.
- Submit and review a shared-contract change separately before implementations
  that depend on it.
- Every new module has its own `test_<module>.py`; do not recreate a single
  giant test file.
- Before merging, run `compileall`, the complete `unittest` suite, and
  `git diff --check`.
- `official_package` and `local_refs` remain read-only and are not added to
  Git.
