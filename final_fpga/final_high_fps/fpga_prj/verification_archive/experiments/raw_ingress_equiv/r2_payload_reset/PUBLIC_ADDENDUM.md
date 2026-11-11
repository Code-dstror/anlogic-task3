# RAW10 ingress reset equivalence

The [public contract](../PUBLIC_CONTRACT.md), [ports](../PORTS.vh), parameters and accepted token edges
are identical for both arms. The [opaque compile list](OPAQUE_SOURCES.json) identifies the only two
DUT sources. Compile each in its own library. Use the independent byte and metadata oracle to check
valid payloads, sidebands, actual handshakes, stale/drop/error counts, and retirement. Ignore payload
while output VALID is low.

- Send the first legal SOF on the first rising edge after reset release. Check the complete START and
  CONTEXT fields from that edge, distinct from the inputs driven during reset and later cycles. Complete
  the actual RAW frame and exact SOURCE through END. Repeat after aborting a frame with reset while a
  CONTEXT or DATA token is held and the clock can be stopped.
- On the edge retiring the previous END or ABORT, admit the next SOF with a different valid identity,
  timestamp, gains, metadata and geometry. Subsequent CONTEXT and SOURCE matching use the new frame.
  A stale SOURCE issued before the new SOF or while the old terminal is being retired cannot certify the
  new frame. Issue the matching SOURCE after the new frame has begun and verify its true terminal.
- A malformed first frame follows the original START/ABORT contract, then a legal new frame completes
  with a clean snapshot. Keep partial-tail and fixed-role profile checks from the first round.
