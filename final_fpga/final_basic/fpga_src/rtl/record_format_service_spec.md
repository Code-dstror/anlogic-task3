# Record selection decision pipeline

The public USER BAR owner, canonical 147-bit command/ACK, source session,
unsupported-version checks, and official FIFO reset/CDC contract are unchanged.
This candidate supports v1/v2/v4; the historical RECORD_V3_ENABLE parameter
enables sparse v4 and does not enable the retired four-strip v3 layout.

At the actual complete DFI command handshake, the service captures raw
shape/version/session error and the **current** quiescence bit independently.
The unpublished ACK register retains the requested version and exact identity.
On the following DFI edge, it applies the frozen positive selection or preserves
the previous selection on failure. The next edge publishes the complete ACK.
No later quiet/session value can turn the captured negative result positive.

The additional private decision edge breaks the routed global quiet cone before
the 32-bit epoch and version enables. It adds only decision_quiet/reply_pending;
the existing ACK storage carries the plan, with no new wide context bank.
Only one command is owned through this interval. USER remains BUSY until the
actual return ACK; production uses that ownership to inhibit new frame admission.
USER cannot observe DONE or a new version from mere FIFO enqueue.

Either domain reset cancels all private pipeline stages and FIFO cohort.
Focused tests cover reset between command and commit, stopped clocks, held ACK,
positive-to-negative and negative-to-positive quiet changes after command take,
session changes after take, unsupported formats, and successful recovery.

Source-bound physical cause: e700 seed1 timing_detail.rpt line19217, DFI
product-reset/quiet cone to record epoch CE, -0.663ns, fanout2409, 84% net delay.
RTL tests cannot establish new physical setup/hold/removal closure.
