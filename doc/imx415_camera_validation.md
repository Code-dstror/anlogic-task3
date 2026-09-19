# IMX415 camera pipeline validation

## Scope

This note records evidence for the IMX415 RAW10 camera path through crop, ISP and RGB byte packing. Sensor hardware capture and board validation have not been performed. TD results are recorded separately below.

## Stream contract

- ISP input: 40-bit RAW10, four horizontally adjacent pixels per beat; lane 0 is `tdata[9:0]`.
- ISP output: 96-bit RGB888, four pixels per beat; lane `k` is `tdata[24*k +: 24]` with `R,G,B` in descending byte order.
- `tuser` marks the first beat of a frame and `tlast` marks the final beat of each line.
- State advances only on `valid && ready`. Output data and markers remain stable while stalled.
- Supported runtime sizes are bounded by the configured maximum of 3840×2160; width must be divisible by four.

## ModelSim evidence

The tests compile the real ISP RTL, the PH1 ERAM simulation model and `PH1_PHY_GSR`. No ISP stubs are used.

| Test | Configuration | Result | Evidence |
|---|---|---|---|
| Gamma path | 16×4, Gamma enabled | PASS | `tmp/modelsim/camera_pipeline_gamma/run.log`, 2026-09-16 12:51 |
| Small end-to-end | 16×4, Gamma enabled | PASS | `tmp/modelsim/camera_pipeline_small/run.log`, 2026-09-16 12:51 |
| 1080p end-to-end | 1920×1080, full frame | PASS | 6,220,800 packed bytes in 1,042,597 cycles; `tmp/modelsim/camera_pipeline_1080p/run.log` |
| 4K end-to-end | 3840×2160, full frame | PASS | 24,883,200 packed bytes in 4,158,757 cycles; `tmp/modelsim/camera_pipeline_4k/run.log` |
| CSI-to-RGB integration | 16×4 crop, real asynchronous FIFO and ERAM, random output stalls | PASS | Exact RGB bytes and two valid frame TLASTs; delayed final-row bad CRC emits `frame_error`, never emits `frame_done`/TLAST, and the next frame recovers; `tmp/modelsim/camera_csi_rgb/run.log` |

The full-frame tests check the output byte count and the testbench's pixel/marker invariants. The small test covers the previously failing right-edge and line-boundary behavior. ModelSim reports vendor-model diagnostic text for PH1 ERAM `NOREG` reset combinations and `INIT_FILE` part-select warnings during some fresh optimizations; the recorded runs still finish with `RESULT: PASS`. These diagnostics must be reconciled with the final TD configuration rather than silently treated as synthesis approval.

The crop stage holds each row's final selected 40-bit group until the real RAW
line EOL arrives. The CSI receiver withholds that EOL until payload CRC passes.
The CRC integration test deliberately excludes a trailing raw group from the
crop and delays the final CRC word by 300 pixel clocks; no packed frame can
complete during that interval. A one-cycle abort also bypasses held-output
backpressure so the fault item cannot be lost.

Additional passing regressions cover pin-level I2C configuration and NACK
handling, receiver header ECC and variable RAW10 word counts, actual asynchronous
FIFO overflow/recovery, RGB packing tail masks and stalled-output stability,
UART packet formatting, and the silent-source watchdog. The watchdog test
isolates control using explicitly identified behavioral child shells; it does
not simulate analog PHY behavior. Runners are in `fpga_rtl/tb/run_*camera*`,
`run_csi2_*`, and `run_rgb_axis_packer_modelsim.ps1`.

## Memory implementation

- Each 40-bit line bank is formed from two 20-bit `PH1_LOGIC_ERAM` instances, 1024 words deep, in simple-dual-port mode.
- Gamma uses a 1024×8 `PH1_LOGIC_ERAM` initialized from `fpga_rtl/camera/isp/color/gamma22_10to8.dath`.
- Gamma bypass and ROM paths both retain the same registered one-cycle lookup latency so downstream valid and marker timing remains aligned.

## TD status

TD 6.2.168116 synthesis passed for PH1A90SEG324-2. Gamma initialization resolves
with a source-relative filename. Placement, routing and bitstream generation
completed, but final timing did not pass: setup WNS -2.923 ns, hold WNS
-1.659 ns. The build script correctly exits with failure on these negative
slacks (`tmp/camera_td/build_final.log`, `timing_status.rpt`,
`timing_summary.rpt`). The remaining reported violations are cross-domain
recovery/removal paths into the official asynchronous FIFO reset logic.
No claim of timing closure or board readiness is made for the generated bitstream.

Per the user's final instruction, this delivery is accepted at the behavioral
simulation milestone; further timing investigation and constraint changes are
deferred. The physical flow and its current reports are retained for follow-up.

The strict repository readability/profile gates were attempted for sensor
control and packing but do not pass all naming/comment/structure rules
(`tmp/camera_sensor_gate.json`, `tmp/rgb_axis_packer_gate.json`). They are not
reported as passing. Functional compile and self-checking simulation results
are separate evidence.

The original vendor PHY clock detector contains direct recovered/reference
clock-domain sampling. This inherited implementation was retained. Application
stream resets release synchronously in each local domain, status/enable uses
synchronizers, and multi-bit image data crosses through the vendor asynchronous
FIFO. Clock groups alone do not establish analog robustness or prove the
vendor PHY CDC; those remain part of board validation.

## Hardware work still required

1. Validate IMX415 configuration, CSI lane alignment, Bayer phase and crop parity on hardware.
2. Measure real sensor frame rate and inspect known color-chart, flat-field and dark-frame images.
3. Exercise downstream backpressure and overflow recovery with the real capture clock.
