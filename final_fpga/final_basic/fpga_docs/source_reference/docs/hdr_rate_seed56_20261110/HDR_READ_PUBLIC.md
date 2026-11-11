# HDR reader / DDR response black-box short-test contract

Use only this document, the public [reader interface and numerical contract](../seed12_round2_20261109/HDR_READER_PUBLIC.md),
the declaration-only port files supplied by the maintainer, and the author's own new tests.
RTL, vendor model implementations, old benches and old runners are opaque: compile/hash only.
The existing `seed12_hdr_reader_carrier` is permitted as opaque wiring of the real external decoder, reader, member ERAMs and merge.
Baseline is fixed `41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213`; candidate cursor is an isolated alternative, not a different numerical algorithm.

## Purpose and boundaries

The reported board case is two cameras admitting LONG and SHORT at about30.306/s each but jobs at30.306/20.204/s.
Both eyes exchange the slow role on re-entry; same-session SDR achieves about30/30.
This short test measures and validates the actual HDR read path under identical explicit memory-response and consumer conditions.
It cannot establish a full-HD board frame rate or uniquely identify a real board latency from seconds-scale UART snapshots.

Use WIDTH68, HEIGHT63 (1071 four-pixel groups,5355B per member,335 AXI words per member), ratio4, black50/50,
motion64/3 initially. Choose deterministic independent RAW10 values covering dark clipping, knee boundaries, static and moving cases.
No long multi-frame full-raster run. A few short jobs with distinct camera/bank are sufficient.
The public reader/carrier interfaces are unchanged. Reuse the earlier contract for exact arithmetic, lane order,
SOF/EOL/EOF/index, AXI page/byte addressing, 16-beat/4KiB limits, and valid/ready semantics.

For the main integration run, put the real `ddr_axi_two_client_arbiter` between the reader's AXI ports (client1) and a memory BFM.
Client0 can be tied inactive initially, then inject a bounded valid competing read burst in a separate case.
Unused AW/W/B source channels remain inactive; tie public READY/response signals consistently and monitor their absence.
All share the same DFI clock; use a period of7.502ns or documented integer test equivalent.
The memory BFM accepts each real master AR, waits an explicit latency (e.g.32 DFI edges), then offers exactly ARLEN+1 responses
with matching ID, response0 and LAST only on the final beat. Hold all response fields while stalled.
Do not read internal arbiter, cursor, decoder, queue, RAM or merge state.

## Required checks

- Legal first START reaches genuine RESULT OK, exactly1071 accepted outputs, independent RAW14/motion oracle and exact markers/index.
  All requested memory byte addresses are consumed once; no extra frame/bank bytes. This geometry crosses a 4KiB boundary,
  more than two512-group reservations, and ends with11 valid bytes in the final AXI word. Result cannot precede required output acceptance.
- Measure actual START→RESULT cycles and AR/R handshakes under the same32-cycle memory latency and no output stalls for both variants.
  Record master-side burst idle intervals and observed R backpressure as well as client-side traces if exposed by the test harness.
  The expected address/byte/numerical oracle is independent; the baseline's values are only a performance comparison, not a correctness oracle.
- Finite output backpressure: hold an offered output, allow incoming bursts to fill available queues, verify the offered data and sidebands
  remain stable and occupancy outputs stay within0..512 per member. Release and complete. Include read/queue wrap and simultaneous input/output
  transfers through more than one chunk; no513th group or duplicated tail. Exercise ARREADY and inter-R-beat gaps separately.
- Cancel with an AR already presented but not yet accepted. That promised AR must remain stable, be accepted when ready returns, and its entire
  response burst must be consumed/drained. No later unpromised AR is issued. Result is negative only after genuine read/output drain.
- Cancel after real responses have been accepted while output is stalled. Already presented output is not silently withdrawn; release the consumer,
  drain promised bus responses and all accepted pending data before quiet/result. Then, without a fake per-job reset, submit a different camera/bank
  and independent content, and require a new positive result with no stale data.
- A legitimate RRESP error must not yield success. Wrong RID or malformed RLAST are protocol faults and may quarantine until a coordinated identity
  and bus-cohort reset; do not weaken that requirement just to continue. After reset, complete a fresh legal first job.
- At least one bounded client0 read overlap verifies arbitration and response routing; neither client's bytes/ID/LAST may be assigned to the other.

The observed `o_read_quiet` is a whole-reader proof, including decoder, member queues, merge and presented output, not merely no ARVALID.
Use true valid/ready handshakes. Acceptance into any buffer does not authorize early bank reuse or early source completion.
SOURCE identity/bank ownership outside the reader and physical DDR timing remain out of scope for this short harness.

## Opaque compile additions

Use the prior reader contract's actual decoder/ERAM/merge closure and explicit TD2026.2 models.
Add production `rtl/ddr_axi_two_client_arbiter.v` and `rtl/ddr_response_bank16.v` to the actual-arbiter integration closure.
Candidate also requires `ddr_response_bank16.v` even for the direct-memory reader case; compile it in both variants.
All other production/IP/model files are identical between A/B. Public port declarations may be read; their implementations may not.
Maintainer will supply opaque absolute baseline/candidate cursor paths and declaration-only arbiter/carrier headers.
ModelSim `D:/App/modelsim/win64`, TD root `D:/App/TD_Release_2026.2.210.850`, Python3.12 from ENVIRONMENT.local.
New output library/run per attempt, wall watchdog60s per process and a finite simulated watchdog (e.g.1ms per scenario).
Preserve initial failures and classify DUT, contract, fixture and tool problems before re-running. No board/driver/server actions.
