# Black-box IO contract: HDR pair cycle gate

The following is only the public parameter/port declaration, not implementation.

```verilog
module real_hdr_pair_cycle_gate #(
    parameter integer TIMEOUT_CYCLES=12500000,
    parameter [31:0] RECIPE_CALIBRATION_ID=32'h56a3d02f,
    parameter [31:0] LONG_LINE_TICKS=3200, SHORT_LINE_TICKS=200,
    parameter [31:0] GAIN_Q8_8=256,
    parameter integer EXTERNAL_PHASE_ENABLE=0
) (
    input wire i_clk,i_reset_n,i_fault,i_stable,i_admit_enable,
    input wire [31:0] i_session,i_epoch,
    input wire [63:0] i_time,
    input wire i_time_valid,
    input wire i_capture0_idle,i_capture1_idle,
    input wire [146:0] s0_data,s1_data,
    input wire s0_valid,s1_valid,
    output wire s0_ready,s1_ready,
    output reg [39:0] m0_data,m1_data,
    output reg m0_valid,m1_valid,m0_sof,m1_sof,m0_eol,m1_eol,m0_abort,m1_abort,
    output reg [31:0] o_sequence0,o_sequence1,o_session,o_epoch,
    output reg [196:0] o_metadata0,o_metadata1,
    output reg o_source0_valid,o_source1_valid,
    input wire i_source0_ready,i_source1_ready,
    // Legacy shared names now name LONG only. SHORT has its own held bundle.
    output reg [31:0] o_source_session,o_source_epoch,o_source0_sequence,o_source1_sequence,
    output reg o_source_ok,
    output reg [7:0] o_source_error,
    output reg [31:0] o_source1_session,o_source1_epoch,
    output reg o_source1_ok,
    output reg [7:0] o_source1_error,
    output reg o_pair_event,o_pair_ok,
    output wire [31:0] o_diag_pair,
    output wire [47:0] o_diag_counts,
    output reg [31:0] o_good_pairs,o_bad_pairs,o_not_admitted_pairs,
    output wire o_quiet,
    input wire [31:0] i_timeout_phase
);

```

# HDR pair cycle gate

This candidate retains two PIX-domain group contexts. The physical member
rasters, RAW10 packing, DDR bank authority, RAW14 merge, T96, ISP and JPEG
algorithms are unchanged.

`s0` is physical LONG and `s1` is physical SHORT. Their 147-bit FIFO tokens use
RAW10 four-pixel data `[39:0]` (pixel 0 at `[9:0]`), cropped SOF `[40]`, cropped
EOL `[41]`, abort `[42]`, event/error code `[46:43]`, word-domain exposure group
`[78:47]`, independent VC capture sequence `[110:79]`, trusted identity `[111]`,
and trusted common-cycle identity `[112]`. The retained upper token fields are
not used here. Code 7 is true FS, 6 is true FE after upstream CRC/full-sensor
geometry validation, 0 is cropped RAW, and 8/abort/untrusted identity is negative.
Crop EOL is neither physical FE nor the eventual JPEG record TLAST. This gate
has no TKEEP; each RAW beat has all four samples present. Cropped frame size
and margins are checked by the unchanged crop/ingress modules.

Tokens transfer only on `s_valid && s_ready`. RAW payload is consumed without
gate backpressure. A new FS may wait for its own previous ingress/held SOURCE,
or for one of the two contexts; the other member remains able to consume FE.
The upstream real camera FIFOs remain finite at 512 tokens: no claim is made
that arbitrary DDR or SOURCE stalls can be absorbed. The gate adds no pixels
of storage. The existing source/ingress ownership and physical packet timeout
contracts continue to bound service. A third unresolved group is held, never
silently declared good or allowed to overwrite a context.

At trusted LONG FS a free context records group and per-member lifecycle.
Both active contexts share the registered capture cohort. Only one unfinished
member can exist on each ordered lane, so its registered output sequence is
also the sequence used to create that lane's terminal. This removes 256 bits
of duplicated context cohort/sequence registers. SOURCE bundles independently
copy the old registered identity on their enqueue edge and do not borrow it
afterwards, including same-edge old-cohort cancellation and new LONG FS.
SHORT joins only the exact group. Each lane emits registered 40-bit RAW,
SOF and EOL into its existing passive ingress; there is no downstream RAW
ready at this boundary. Admission uses local ingress readiness, so the old
SHORT can remain active while the next LONG enters the other DDR bank.
Upstream context and payload remain ordered independently on each lane.

Each started member produces exactly one held SOURCE bundle at its own true
FE, or a negative bundle on CRC/geometry/identity/reentry/timeout/cohort fault.
The former shared `o_source_session/epoch/ok/error` now belong to LONG;
`o_source1_session/epoch/ok/error` are independent SHORT fields. All SOURCE
fields and valid hold until the corresponding ready handshake. Capture data
still uses the common `o_session/o_epoch`: a cohort mismatch cancels old
contexts and suppresses their same-edge RAW before a new cohort can emit RAW.
Each held terminal retains its context's original cohort and VC sequence.

A positive LONG SOURCE is member success, not pair success. If its SHORT
later fails, LONG is never retracted, and the next LONG owning that lane is
never aborted for the old group. SHORT's real negative writer finish marks
the matching DDR bank bad. If SHORT never emitted SOF, it never acquired a
writer; the incomplete bank expires only after its existing real writers are
idle. Both members' real successful writers remain necessary for bank READY.
Writer B errors independently veto READY even when both physical FEs were good.

`o_good_pairs` and `o_pair_event/o_pair_ok` describe trusted physical pair
completion for sensor warmup, not JPEG publication. A fault can cancel both
contexts on one edge; the diagnostic counters count both, while the sensor
owner receives one negative event, sufficient to leave STABLE. STOP disables
new group admission and drains their tails; admitted members still terminate
according to their original ownership. Timeouts issue only negative outcomes.
Skipped/failed-group drain ordering uses modulo-32 serial comparisons within
the open half-range; zero is invalid. Coordinated cohort reset clears both
contexts and the drain watermark.

With ordered physical lanes two contexts cannot complete GOOD on one edge.
The older group must have finished LONG before the newer LONG FS can create
the second context; its outstanding SHORT must finish before the newer SHORT
FS can start. There is only one SHORT token per edge. The short fixture asserts
`good_events <= 1` throughout and separately checks two-context cancellation.

Focused evidence is generated by `tools/run_hdr_overlap_unified.py`. It uses
the actual shared ingress, shared writer, DDR authority/directory and official
TD 2026.2 RAM model at 16x2. The single-clock FIFO and AXI sink are test-only
boundaries. It checks RAW bytes, real B-before-positive-finish, matching pair
publication, finite endpoint/terminal stalls, negative outcomes and recovery.
The old gate is a negative control on the same fixture. It does not validate
CDC, electrical capture, sustained full-HD fps, physical timing or board output.

## Directed black-box clarifications

The external timeout phase is a free-running count from zero through
`TIMEOUT_CYCLES-1`. An unresolved context times out after a full period from
acceptance of its LONG FS. Wrapping through zero does not shorten the period.

When a true FE and a negative event for the same group arrive on the same
edge, the negative outcome takes precedence. A success presented before a
later failure remains valid. After a negative pair outcome, capture
qualification requires `i_stable` to go low and then high again. Already
admitted members retain their original ownership through that transition.

With `i_admit_enable` low, new groups drain while admitted groups can still
complete. With admission enabled and `i_stable` low, a complete physical group
can produce a positive warmup event without publishing RAW or SOURCE.

Modulo ordering covers forward and backward offsets strictly inside the open
half-range. An exact `0x80000000` separation has no prescribed order. The
directed suite checks offsets on either side and the independently invalid
group zero.
