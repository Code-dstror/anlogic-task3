---
name: rtl-stream-contract
description: Use when changing this FPGA project's RTL streaming interfaces, frame boundaries, backpressure, reset, or CDC. Do not use for unrelated documents or software deployment.
---

# RTL stream contracts and independent short verification

Implementation work follows [RTL rules](../../../src_fpga/AGENTS.md). Read only the target contract,
direct neighbors and relevant historical failure evidence; do not preload all projects or regressions.

For functional verification of new/changed RTL or newly requested functional tests, use a fresh-context
black-box test author. Reusing a historical bench alone does not meet that independence requirement. Provide public
ports, legal parameters, documented behavior and risks, plus an opaque compiler file list. The test
author does not read production RTL, old test implementations, internal signals or vendor model
implementation. See [the black-box contract and handoff](references/blackbox-validation.md).
The implementation maintainer may inspect RTL and diagnose compiler errors; this is a separate role.

Freeze widths, signedness, byte/lane order, true FS/FE versus crop SOF/EOL, KEEP/LAST, clock/reset,
admission and error rules. State whether each status is a pulse or held level and when it is meaningful.
READY, accepted response, completed data, drained transport, SAFE acknowledgment and freed ownership
are different events. A held producer may be borrowed until its downstream consumer's handshake.

Check real valid/ready progression and stable offers under stall. A camera cannot stall indefinitely;
corruption/overflow must prevent success and allow the specified recovery. Preserve camera/session/
epoch/sequence/generation/lease and any committed AXI burst through cancellation. Normal slot retirement
must not wait on unrelated writes; global STOP/configuration boundaries keep their full drain proof.

For CDC/reset, verify the actual stable reset authority, local release and clock-stop behavior. A START
promise must establish the consumer context before dependent work. Newly added mailbox or snapshot
fields need matching scoped constraints. No broad exceptions to conceal a structural defect.

Choose minimal sufficient positive, negative and recovery cases with bounded wall time. A legal first
transaction must reach the real terminal; a bad-input/zero-output test does not qualify startup. Small
frames and a throughput model do not establish full-HD sustained FPS. Bind results to actual source,
parameters, tool/models and input hashes; preserve failed runs and report each verification stage separately.
