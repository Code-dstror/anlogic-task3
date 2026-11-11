# rx_first_loss_trace interface

The observer reset is independent of the business cohort reset. Its WORD input
must be released locally; SYS receives the corresponding observer reset.
`i_sample`, `i_enable`, `i_trigger` and the cohort state belong to WORD. The
first enabled trigger in each generation records the trigger sample and the
following seven consecutive WORD clocks, including while enable becomes low.
Before triggering, disable clears the contiguous prehistory. Complete captures
remain readable until a cohort reset, including while enable is low.

```text
WORD samples -> 32-entry prehistory ring + trigger/7-post addresses
                                      |
                               64x256 sync RAM
                                      | synchronous read
SYS index + request -> 2FF request -> read FSM -> held 320-bit mailbox
SYS o_data          <- ACK-qualified capture <- 2FF ACK <- ack_word
```

Index 0..31 is chronological prehistory, 32 is the trigger, and 33..39 follows
the trigger. For an early trigger the leading `32-valid_pre_count` positions
are invalid and return zero with sample_valid=0. Index 40..62 is invalid.
Index 63 returns a live WORD sample plus current metadata, always sample_valid=0.
Samples 0..39 are valid only after the full capture is ready. A disabled current
mode does not invalidate an already completed sample.

Data bits: 255:0 sample; 271:256 generation; 303:272 trigger_cycle;
309:304 requested index; 315:310 valid_pre_count; 316 capture_ready;
317 capturing_post; 318 requested_sample_valid; 319 enabled. Metadata and the
live sample for status index 63 are captured together when WORD accepts the
request. RAM requests snapshot their metadata before the synchronous read.

Generation starts at zero after observer reset and increments at each observed
cohort release. An asynchronous cohort marker remembers reset even if WORD is
stopped during the complete reset pulse. At generation 65535 a further release
saturates the generation, clears the capture and inhibits new capture until
observer reset; enabled=0 expresses the unavailable state. The WORD cycle counter
continues across cohort resets and may wrap; trigger is unique per generation.

RAM read sequence: latch held index -> decode registered index/issue read ->
RAM consumes address/enable -> capture RAM output into mailbox. The RAM is never asynchronously read or reset.
A cohort reset before response ownership invalidates a pending RAM read. After
ack_word is set, mailbox_word stays unchanged until the request is released,
including through cohort reset. The next transaction observes current metadata.

SYS holds i_index stable before asserting i_request and through ACK. Normal
four-phase order is request high, ACK high, request low, ACK low. If request is
cancelled early, ACK may already be in flight; keep request low and wait for the
old handshake to drain before retrying. A stopped WORD clock produces no ACK;
the outer UART owns timeout and continues its legacy reports independently.

CDC endpoints: i_request -> request_meta -> request_sync; held i_index ->
request_index after synchronized request; ack_word -> ack_meta -> ack_sync/o_ack;
held mailbox_word[319:0] -> o_data[319:0]. The metadata bank request_metadata is
WORD-local. Only scalar request/ACK use synchronizers; the held multi-bit buses
use the four-phase ownership contract. No RAM port crosses clocks.
