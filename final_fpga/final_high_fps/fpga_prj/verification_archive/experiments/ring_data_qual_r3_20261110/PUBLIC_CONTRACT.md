# DFI JPEG ring independent short verification

Compile one arm from [the opaque manifest](OPAQUE_SOURCES.json). The public top is
`jpeg_ring_reset_boundary` in [the port declaration](PORTS.vh). It contains the local
release boundary and the real six-slot ring. Author new stimulus, DDR model and
scoreboard using public transfers. The test observes this boundary, with the host and
DDR supplied by the driver.

## Profile and sampling

Use `CAMERA_COUNT=2`, `SLOT_BYTES=16777216`, `WRITE_RESULT_ENABLE=1`,
`WRITE_TAG_ENABLE=1`, `MASK_ENABLE=0` and default slot bases. There are three
slots per camera, IDs 0–2 for camera 0 and 3–5 for camera 1. Use the fixed slot bases
in the public declaration with a sparse
DDR store. Tie mask input VALID, REQUEST, readiness and metadata low. Unless testing
a request, keep `i_req_valid=0` and all request fields at zero.

Use one 7.502 ns DFI clock. Drive away from the sampling edge. Every transfer is on a
rising edge with its VALID and READY both high. Observe stable pre-edge values for
handshake cycle comparisons. Assert coordinated active-low `i_cold_rst_n` across
startup and allow assertion while DFI is stopped. A coordinated reset may discard
the old ring state. Use this reset when the simulated DDR has no outstanding burst.
Deassert away from any edge. R1 is the first rising edge after deassertion and R4
is the first eligible sampling edge. With DDR ready, a free slot and no conflicts,
a held START can first transfer at R4. START READY and write quiet are DFI
sampled signals. Their levels between R3 and the following falling edge may differ
between arms. Neither an early combinational level nor a stopped clock transfers
anything.

## Write, DATA and RESULT

- Keep START and the capture ID, camera, nonzero session and writer tag, epoch, width,
  height, quality and timestamp stable until `i_start_valid && o_start_ready`. Before
  START there is no active DATA or RESULT transaction. START owns a slot until a
  complete write terminal. A free-slot indication is an admission credit.
- Present DATA after START. The first byte of a 128-bit beat is bits [7:0]. Nonterminal
  KEEP is `16'hffff`. Final KEEP is a contiguous nonempty low-byte prefix. Advance
  only on `i_jpeg_tvalid && o_jpeg_tready` and hold DATA/KEEP/LAST under stall.
  The accepted LAST marks the final payload beat.
- Offer RESULT after the accepted tail. The matching positive RESULT supplies the
  capture ID, quality, epoch, accepted byte length and `ok=1`. RESULT
  acceptance and external AXI B acceptance are separate. Hold RESULT until
  `i_result_valid && o_result_ready`.
- The AXI model counts AW, each W beat, and B separately. AWLEN is beats minus one
  and each beat has 16 byte lanes. Use AWID/BID zero in the legal cases. Check that
  `WLAST` occurs on the last promised W and preserve held AW and W including
  addresses, data, WSTRB and LAST. Supply each B only after its actual final W.
  Memory bytes follow the accepted WSTRB. Take AR/R similarly, with correct ID,
  response and RLAST, and stable R under stall.
- A positive writer ACK is `o_write_result_valid && i_write_result_ready` with
  `ok=1`, error zero, matching identity and exact payload length. The held ACK must
  remain stable under stall. A matching positive RESULT plus all real successful
  write responses and the accepted DATA tail is required for commit. Withhold
  the final B after RESULT and assert that neither success ACK nor this frame's
  READY appears during that wait. A new START is blocked while its old writer ACK
  is offered and unaccepted.
- For a nonzero B response on the accepted final burst, still deliver the matching
  RESULT and drain the owed AXI handshakes. Expect a failed write ACK with the
  original identity, error 3 and zero successful length. The failed capture has no
  READY. After the failed ACK is accepted and the writer is quiet, complete a new
  legal capture without reset.

## Read, retirement and quiet

READY is a held descriptor. Verify its capture ID, length, dimensions, timestamp,
camera/session/epoch/quality, slot and generation. `o_ready_valid && i_ready_claim`
claims the oldest pending record. ACK and READY can be independently backpressured.
After claim, compare each accepted read payload beat with the stored write data and
KEEP. Stall the last payload offer. Its DATA/KEEP/LAST stay stable. Read-complete is
available only after the actual read tail; it remains until matching retirement.

SAFE and host completion belong to the downstream transport. Drive `i_retire_valid`
for normal retirement only after that external precondition and the accepted read
tail. The tuple is slot/session/generation and the response is held until accepted.
With one live claimed record, an early matching RETIRE can be used as a directed
negative check and returns BUSY (3). A wrong generation before a good retirement
returns STALE (2) and leaves the live record owned. The matching error-free RETIRE
returns OK (0). When a slot is reused its generation advances, skipping zero. The
first allocation of a cold slot uses generation one. Allocation starts at the
first slot of the requested camera and rotates within that camera, skipping
unavailable slots. A later frame may therefore use a different slot before reuse.

`o_write_quiescent` describes the writer. It is false with a pending START, accepted
write payload/AXI work, a held writer ACK or recovery required. It can become true
when that writer is empty even while a committed record is pending READY or the
reader is active. `o_record_quiescent` covers the record transport and is false
while the reader, pending record, queries or held retirement response still own
work. Use both predicates in the DFI samples and verify the positive empty case.

## Minimum directed gate

Run the same independently scored input schedule on both opaque arms and compare
accepted START, DATA, RESULT, AW/W/B, ACK, READY, AR/R, payload and retirement events
and sampled ready/quiet levels. Use a legal first transaction with a tail shorter
than 16 bytes, a second burst, finite W and B stalls, held write ACK, read tail stall
and retirement. Follow a negative B with a legal recovery. Include a coordinated
reset with DFI stopped after debt is drained and complete a fresh first transaction.
Use finite wall and cycle watchdogs. The ring test covers writer/reader ownership
and terminal ordering. Actual host SAFE, FPGA routing and board operation have
separate evidence.

## Opaque compile

The manifest lists project-relative RTL paths and TD-root-relative official model
paths with SHA-256. Check all hashes without opening the bodies. In a fresh run
directory create `work` and `ph1` libraries. Compile `model_sources` into `ph1`
and `td_work_sources` plus exactly one arm's sources into `work` in Verilog mode,
with `-L ph1`. Compile the independent bench separately. Simulate its top plus
`work.PH1_PHY_GSR` and `ph1.glbl`. This ring uses official DRAM models with no
external ROM initialization files. Report compile errors to the maintainer using
the log path.
