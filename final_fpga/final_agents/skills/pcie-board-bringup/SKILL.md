---
name: pcie-board-bringup
description: Use for an explicitly requested RK3576–FPGA PCIe board test, DMA completion-length experiment, or recovery check. Do not use for RTL-only simulation.
---

# RK3576–FPGA board bring-up

Use only for an authorized board/DMA experiment, not RTL-only verification. Identify the actual board,
serial hardware, bit SHA/source, kernel/driver/program and protocol before mutation. A known COM name
alone is not board identity. Existing session authorization persists; a read-only serial capture does
not authorize START/STOP, CLEAR, programming, driver reload or reboot.

Use [the protocol authority](../../../docs/pcie_protocol_v1.json) plus the selected isolated project's
explicit extensions. Keep original DUAL_SDR/DUAL_HDR register and record format compatibility. A new
mode/value needs a stated host adaptation; link-up is not a host-buffer-ready proof.

Check enumeration/BAR, a fixed payload, then the actual encoded product. ROM JPEG tests transport/host
decode only. Measure actual completion length and content under partial tails, final KEEP/LAST, short
reads, finite stalls, cancellation and restart; do not assume driver EOP semantics from a simulation.

Trace one identity across true FS, selected capture, SOURCE plus B completion, job/decoder START, AR/R,
PIX DATA/FENCE, JPEG result, DMA SAFE/ACK and final retirement. Distinguish RAW/transport/product counts,
same-eye order and generation/cohort. A frozen UART first-window or separate-domain snapshots are not
a continuous same-cycle trace; sampled reset-high cannot exclude a narrow pulse.

For a hang, locate the first uncompleted obligation instead of attributing every zero-FPS event to
camera startup. For rate, compare same-window unique products per eye and phase/backpressure conditions;
separate FPGA delivery from MPP/render/display limits and single-frame latency from steady intervals.

Before buffer reuse prove DMA has stopped writing and follow the reviewed driver recovery contract.
Keep partial/failed records separate, preserve the first failed cold-start evidence, and avoid silently
retrying/reflashing until it appears healthy. UART remains bounded, observation-only and outside business
backpressure. At finish report the board's retained state and serial/driver ownership; untested stages are NOT_RUN.
