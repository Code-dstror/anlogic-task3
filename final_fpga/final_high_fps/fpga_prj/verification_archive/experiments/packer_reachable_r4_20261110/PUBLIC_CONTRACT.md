# JPEG byte packer sampled contract

Use [the public declaration](PORTS.vh) and exactly one arm from the
[opaque source list](OPAQUE_SOURCES.json). Write fresh stimulus and a byte/transfer
scoreboard. The DUT accepts bytes and presents 128-bit AXIS beats.

Use an 8 ns clock, with synchronous active-low reset held across at least two
rising edges. Change stimulus away from the sampling edge. Compare values sampled
at rising edges. An input transfer is `i_valid && o_ready`, and an output transfer
is `o_axis_tvalid && i_axis_tready`. Hold every offered input byte and LAST
under backpressure. Coordinated reset may discard prior unfinished work.

The first byte of a beat is bits [7:0], and KEEP bit 0 qualifies that byte.
Nonterminal beats have full KEEP. A successful final beat has a contiguous
nonempty low-byte KEEP and LAST. The source marks the frame's final byte with
`i_last`. Exercise a tail within a word, an exactly full last word, multiple
words and input gaps. The complete DATA, KEEP and LAST tuple must stay stable
while VALID is stalled. A full nonterminal beat can transfer on the same edge
that accepts the first byte of its successor. The pending terminal beat must
transfer before accepting another frame.

`i_abort` is sampled as a level and masks input READY. An output already offered
under stall stays committed through its actual handshake. The abort discards
other bytes and the previous frame, then a new frame can start when idle.
An already offered tail retains its LAST until accepted, including when abort
is asserted. A coordinated reset is the separate condition that may discard
an unfinished offer. Test abort with a partial unoffered word and with a
visible stalled output, then test legal recovery.

Use small legal `MAX_PAYLOAD_BYTES` values of 17 and 31. Exactly MAX bytes ending
on an accepted LAST can succeed. Acceptance of the next byte of an overlong
frame produces a one-cycle `o_overflow` and `o_frame_error` pulse. It discards
the excess frame through the accepted input LAST, unless aborted first.
Earlier committed AXIS prefix bytes remain observable and their existing
offers hold until accepted. Score failure independently of prefix delivery.
Verify both a rejected byte with LAST and continued discard through a later
LAST. Each failure is followed by a legal fresh frame.

Check byte content, KEEP, LAST, accepted cycles, stalls, error pulses and idle.
Use the same independently scored stimuli for each arm and bounded wall/cycle
watchdogs. This leaf consumes bytes and has no vendor model dependencies.
