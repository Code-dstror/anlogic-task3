# Public interface declarations

Production implementations must remain opaque to the black-box test author.

```verilog
module stereo_capture_source4 #(
    parameter integer CAMERA_ID=0,
    parameter integer WIDTH=1920,
    parameter integer HEIGHT=1080,
    parameter integer TAG_WIDTH=32,
    parameter integer SEPARATE_DATA_RESET=0,
    parameter integer FS_CADENCE_ENABLE=0
)(
    input wire clk, rst_n, i_enable,
    input wire [31:0] i_session, i_epoch,
    input wire [63:0] i_time_ns,
    input wire i_time_valid,
    input wire [39:0] i_data,
    input wire i_valid, i_accept, i_sof, i_eol, i_abort,
    input wire [31:0] i_sequence,
    input wire i_identity_valid,
    input wire i_event_valid,
    output wire o_event_ready,
    input wire [1:0] i_event_kind,
    input wire i_event_ok,
    input wire [3:0] i_event_error,
    input wire [31:0] i_event_sequence,
    input wire i_event_identity_valid,
    input wire i_receive_fault, i_identity_quarantine,
    output wire [39:0] o_capture_data,
    output wire o_capture_valid, o_capture_accept, o_capture_sof, o_capture_eol,
    output wire o_capture_abort, o_capture_geometry_done,
    output wire [31:0] o_capture_session, o_capture_epoch, o_capture_sequence,
    output wire [196:0] o_capture_metadata,
    output wire o_raw_source_valid,
    input wire i_raw_source_ready,
    output wire [31:0] o_raw_source_session, o_raw_source_epoch, o_raw_source_sequence,
    output wire o_raw_source_camera, o_raw_source_ok,
    output wire [7:0] o_raw_source_error,
    output wire o_idle, o_fault,
    // Same logical PIX reset as rst_n; local copy only for data masks.
    input wire i_data_reset_n,
    // Cold PIX configuration; applies to the next true trusted FS only.
    // Legacy/default callers retain capture-all behavior.
    input wire [7:0] i_frame_divisor
);

```



Only an actual accepted CSI FS can open an owner. Admission requires
`i_enable`, valid common time, trusted event identity, available tag capacity
and no live receive/quarantine/router fault. `i_enable` already represents the
caller's cold mode, initialized CFG and application admission decision. A
change to enable, session, epoch or common time after FS does not alter an
admitted frame.

At FS the module snapshots session, epoch, parser-issued sequence and common
timestamp. A later cropped SOF attaches the capture context to that exact FS;
it never renumbers the camera or takes a second timestamp. RAW traffic is
eligible only while that fence owns the same trusted sequence. Wrong/unknown
identity during an active capture causes negative continuity termination.

The per-eye internal tag is a monotonically increasing finite token. Default
TAG_WIDTH=32; zero is not issued. It saturates without reuse. On the last legal
tag, `o_fault` reports exhaustion while the already admitted frame can still
finish. Further FS events are discarded until a coordinated reset. The tiny
two-bit test instance validates saturation behavior only; production retains
32 bits rather than reducing the lifetime for resource savings.

## Passive capture contract

`i_data[39:0]` carries four unsigned RAW10 samples, lane0 in bits 9:0. Inputs
are accepted only on `i_valid && i_accept`; i_accept is the camera stream's
actual acceptance, not this capture FIFO's ability to backpressure the sensor.
The module has no pixel READY output. `o_capture_valid && o_capture_accept`
identifies an admitted passive tap transfer. Its data, SOF/EOL, frozen
session/epoch/sequence and metadata belong to that same transfer.

Accepted EOL placement is checked at every group. `o_capture_geometry_done`
is a pulse only for the exact WIDTH×HEIGHT group count with every expected EOL
and no accumulated fault. It is not a CSI FE. A malformed line, crop abort,
identity failure or continuity failure prevents good SOURCE and retires the
capture negatively. Downstream FIFO/DDR overflow and write acknowledgements
remain the existing capture writer's separate responsibility; a good SOURCE
does not bypass its write-success contract.

The output metadata is 197 bits:

| Bits | Meaning in this profile |
|---|---|
| 196 | metadata measurement validity = 0 |
| 195 | SOURCE_QUALIFIED = 0 |
| 194:193 | exposure role = UNKNOWN/0 |
| 192 | physical-source provenance = 1 |
| 191:160 | exposure group = UNKNOWN/0 |
| 159:128 | calibration ID = UNKNOWN/0 |
| 127:96 | actual gain = UNKNOWN/0 |
| 95:64 | actual exposure = UNKNOWN/0 |
| 63:0 | common timestamp frozen at admitted FS |

Time validity is required at admission and must be conveyed separately by the
caller's existing capture metadata contract. A timestamp alone does not make
the measurement bundle valid or prove exposure synchronization. No HDR pair,
exposure group or calibration qualification is invented.

## Complete input and failure semantics

The real identity fence receives actual FS/FE/ABORT and the exact capture
context. A good RAW SOURCE requires successful matching FE, complete crop
geometry and actual crop quiet. The native branch uses the same RAW geometry
and quiet proofs, with its result consumed locally using ready=1; it does not
represent an ISP output. Its capsule contains only actual sequence, session,
epoch, frozen timestamp, camera ID and admitted-time-valid, with other fields
zero. The native result never leaves this leaf.

`o_raw_source_*` is a held valid/ready result, including exact owner identity,
camera ID, ok and error. Its fields do not change under sink stall. The old
owner remains alive through both independent fence result handshakes.

Physical event input never waits for an unbounded downstream SOURCE stall:
`o_event_ready` follows the logical local reset (`rst_n`, or its qualified
same-cycle data copy in the optional mode). Events transfer to the fence when
it can accept them.
If a new FS arrives while the preceding owner is awaiting result retirement,
that whole new frame is discarded by sequence filtering. If the preceding
frame never received its terminal, the new FS instead also authenticates a
continuity failure of that old owner; it cannot leave the old owner hanging.
When the old terminal was already seen, the dropped future frame cannot
retroactively corrupt the held old SOURCE result.

`i_receive_fault` handles PHY failures that cancel the receiver's pending
event, and `i_identity_quarantine` blocks new ownership. These negatively
terminate an active owner even if no FE/ABORT can arrive. A late CRC beyond
the selected crop remains a negative matching terminal. Ordinary bad-frame
failure is local to one instance and does not poison the other camera or
permanently inhibit a later healthy frame. Untrusted/quarantined input is
never marked good. `o_fault` reports router protocol fault, exhausted tags or
active identity quarantine, rather than treating every ordinary CRC failure
as a permanent structural failure.

`o_idle` requires the actual fence and router to be idle. Free-running input
crop/abort without an admitted owner does not make this output busy. Internal
`crop_quiet` still requires router idle and no input valid/abort, so an admitted
frame cannot retire before its real crop tail is quiet. Disabling admission
does not bypass an existing owner or held SOURCE result. A source-cohort reset cancels all
owners/results and restarts tags. The caller coordinates it with the receiver
identity reset and downstream capture drain; a session counter write alone is
not a reset proof.
