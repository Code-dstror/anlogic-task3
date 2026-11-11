# Reset and product-boundary public verification contract

This is an independent black-box handoff. Read only this file, CONTRACT.md,
the generated fixture ports/compile.json, and the linked public protocol/math.
Production Verilog, opaque projections and vendor models may be compiled and
hashed, but not read. Do not read old benches or access DUT internal hierarchy.

## Local release boundary

Public module declaration:

```verilog
module reset_release_sync #(parameter integer FALLING_RELEASE=0)(
    input wire i_clk,input wire i_async_rst_n,output wire o_rst_n);
```

Use the production file `src_fpga/rtl/reset_release_sync.v` as an opaque input.
No vendor model is needed for this unit. Mode 0 releases its output after the
third rising clock following asynchronous input release. Mode 1 waits until the
following falling edge. An asynchronous assertion drives either output low
without needing a clock. With no clock edges the output must not become active.
At the receiving rising edges, a synchronously sampled consumer sees the same
first active edge in both profiles. Keep reset deassertion away from sampling
edges; vary its phase, pause the clock before and during release, and assert it
again while the clock is stopped. Check no stale high reappears after restart.
The mixed-edge local cleanup in the actual product chain is checked through its
public failed-frame/recovery behavior, not its internal registers.

## Actual integration

Use the already generated opaque fixture
`tmp/uhd_integration_projection/rate3_reset_integration_a1/` and its public ports.
It retains actual capture, private RAW/ISP borrowing, JPEG-to-DDR CDC and JPEG
ring consumers. External ISP math/physical interfaces and 480x32 raster are the
same explicit model boundaries described by CONTRACT.md. This is not a full-HD
or physical camera throughput proof.

Cold application BAR offsets are F8C topology (0 MONO/1 DUAL), FA0 divisor
(use 2), FA8 product (0 JPEG/1 RAW), FB4 rate (0 legacy), FBC geometry
(1 UHD15/2 UHD20), F90 command (APPLY=1). F94 status has busy/done/locked at
bits 0/1/2 and active topology at [4:3]. F9C/FA4/FAC/FB8/FC0 read active
topology/divisor/product/rate/geometry; FC4 capabilities are 0x107. Stage
topology before the other settings. BOOT and rearm-ready do not require a
fabricated HD sensor frame; a later CFG COMMIT/APPLIED still requires the actual
qualified cold observation frame. The actual application CONTROL is 0x018.
The real production POR consumes about 2047 SYS25 rising edges (81.9 us)
before application cold release. Allow a bounded 24000 PIX edges for initial
domain/FIFO release; an 8000 PIX/64 us wait is earlier than this defined POR.
Do not shorten the real boot or change a DUT timeout to satisfy a fixture.
SDR RAW10 reaches the external ISP as zero-extended 14-bit lanes:
`{4'b0000, sample[9:0]}`, never shifted left. Low lane is the earliest pixel.

Execute the complete positive / in-flight RAW SLVERR / positive recovery
sequence in CONTRACT.md, including real CONFIG ACK/APPLIED, buffer ARM, APP ARM,
last JPEG B hold and matching native fence/ACK/retirement. No forged SOURCE,
JPEG result, writer ACK or internal state forcing is allowed.

Also check a separate cold-start run in which DFI is stopped from time zero
through the real POR assertion and release. Keep other external interfaces idle
and model their reset behavior consistently. Resume DFI, complete actual BOOT and the first
legal configuration/product transaction. Two short runs with distinct reset and
clock phases are sufficient; do not add multi-frame full-resolution simulation.
PERST is not a replacement for independent cold product ownership reset, so do
not first complete BOOT and then manufacture a new cold cohort by toggling PERST.

For the nonempty pipeline cancellation retain public held offers until their
actual take or explicit reset/cancellation boundary. Error SOURCE must not turn
into a successful record, and the next complete transaction must retire. No
result before final B, checked fence and matching ACK counts as retirement.

Use ModelSim SE-64 2020.4 at <TOOLS_ROOT>/modelsim/win64 and explicit TD models from
<TOOLS_ROOT>/TD_Release_2026.2.210.850. Python is
<USER_HOME>/AppData/Local/Programs/Python/Python312/python.exe. New run folders
only; 180 seconds wall limit and 200000 PIX edges per integration run. Preserve
all original failures and classify test/contract/dependency/DUT causes. Retain
source and TB hashes, tools, commands, parsed records and exact observed stages.
