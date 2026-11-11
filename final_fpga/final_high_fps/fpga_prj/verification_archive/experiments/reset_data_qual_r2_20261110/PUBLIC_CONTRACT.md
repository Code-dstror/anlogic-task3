# Private RAW replay sampled interface

Use [public port declarations](PORTS.vh) and the hash-bound [opaque source list](OPAQUE_SOURCES.json).
Compile either arm into a fresh library. The test author observes only public ports and writes an
independent driver and scoreboard. The test boundary contains the real private RAW source, cleanup
and RGB adapter. An external ISP model supplies RGB and controls its own RAW ready and idle.

## Legal profile and clock

Use `EXTERNAL_ISP_ENABLE=1`, `ORIGINAL_SYNC_CLEAR_ENABLE=1`, `RAW_SAMPLE_BITS=14`,
`BASE_WIDTH=16`, `BASE_HEIGHT=4`, `MAX_WIDTH=32`, and `MAX_HEIGHT=8`. These two exact
geometries give 16 and 64 four-sample groups respectively. Keep a single 8 ns PIX clock.
Transfers occur at a rising edge with VALID and READY both high. Drive synchronous fields
away from the sampling edge. A valid producer holds its payload and sideband while stalled.

`i_pixel_rst_n` is an asynchronously asserted, active-low coordinated reset. It can be
asserted with PIX stopped and may discard unfinished work. Deassert away from a clock edge.
Call the first rising edge after deassertion R1, the third rising edge R3, the following
falling edge F3 and the next rising edge R4. The external ISP reset releases at F3
after cold startup. The first active rising sample is R4. With all external quiet/idle
inputs asserted, context availability may appear after that sample. A producer presents
a command only once the availability is visible, then waits for the later payload
qualification before starting RAW. There is no DATA or RAW SOURCE acceptance during startup
or before a legitimate owner. Use the same ordering after a stopped-clock reset.

## Context and borrowed owner

`i_context_fire` is a one-cycle accepted-command notification. Pulse it at a rising edge
only while `o_context_available=1`. The command is private, with `i_context_private=1`,
and publication is present at that edge. `i_owner_published` stays high until the entire
borrowed operation is idle. `i_owner_valid` may be asserted later to establish the owner.
For the directed tests assert it no earlier than the command, then retain it and all
owner identity fields until final `o_pool_idle`. The qualifier `o_locked_owner_valid`
describes the active payload owner. Final idle is the lifetime boundary.

The frame capsule is 384 bits. Width is `frame[220:205]`, height `frame[236:221]`,
session `frame[76:45]` and camera `frame[4]`. The remainder can be a fixed, distinct
pattern. Copy the entire capsule to `i_context_frame` and `i_owner_frame`. Match job,
pair and member between command and owner. Set `i_context_key={session,31'd0,camera}` and
`i_context_aux=i_context_job`. Use a nonzero job, lease, native tag and writer tag.
`i_owner_frame`, lease, job, pair, native tag, writer tag and member are borrowed until idle.
Check the corresponding `o_locked_*` fields when `o_locked_owner_valid=1`.

The accepted output context is `{job,key,native_tag,frame}` in four fields of
64, 64, 64 and 384 bits, most significant first. `m_context_valid` and the full context
hold through backpressure. Accept that context before counting output RGB groups.

## RAW, ISP, and distinct terminals

One accepted RAW group holds four 14-bit samples, first sample in bits [13:0].
Use SOF on the first group and EOL on each row's last group. In a legal transaction
the ISP RAW offer carries the original group and framing unchanged. Its actual take is
`o_isp_raw_valid && i_isp_raw_ready`. The source uses `s_raw_valid && s_raw_ready`.
Wait for `o_payload_enable` before offering the first group. Exercise finite ISP and
RGB backpressure. The external model supplies a deterministic corresponding 4PPC RGB raster
on `i_isp_rgb*` and holds an offered group through `o_isp_rgb_ready`.

The real RGB adapter offers `m_valid` only after the context acceptance. Each normal
group carries the native tag, `m_keep=4'hf`, zero-based group index, SOF and EOL.
`m_last` identifies only the final group of the frame. Check the full offered tuple
during a finite stall including a tail stall. Neither geometric LAST nor RAW SOURCE
alone constitutes an accepted output STATUS.

`s_raw_source_valid && s_raw_source_ready` transfers a RAW read terminal. For a legal
terminal set `i_raw_source_read_quiescent=1` before offering it, then hold its fields.
The first matching terminal must match full frame capsule, lease, job, pair, member and
native tag. Success has `s_raw_source_ok=1` and error zero. A stale identity may be
accepted for classification and increments the stale count. It cannot establish success.
If offering a duplicate after a successful match, the retained terminal still controls
the original frame. Use a later legal matching terminal after a stale attempt.

`m_status_valid` is the held adapter STATUS. For success, require full expected RGB,
matching RAW terminal, quiescent ISP and input, matching context and tag, `m_status_ok=1`,
error zero and group count equal to the RGB transfers. `o_original_read_quiescent` may
be observed at STATUS. Accept STATUS under finite backpressure. `i_processed_source_fire`
is a separate one-cycle notification from the downstream owner, delivered after its
matching processed source retires. In the short leaf test supply it only after the
matching adapter STATUS was accepted and the external post stage is quiescent.
Keep owner publication and fields stable until `o_pool_idle`. Before the processed
notification and drain completion the original STATUS alone cannot release that ownership.

## Cancellation and directed checks

Cancel a valid started transaction while a public RGB offer is stalled. Keep the
producer and sink commitments. The already offered RGB tuple must remain stable until
accepted, and its transfer still counts. For a RAW beat already offered to the ISP and
stalled, keep the source offer stable and allow the ISP to take the promised beat.
Later RAW groups may drain without a new ISP offer. Deliver the matching RAW terminal
with the reader quiet after draining its outstanding work. After all presented RAW/RGB
work drains, the local cleanup may assert `o_isp_reset_n` low and emit a cleanup pulse.
The failed STATUS must carry the correct identity and report the actual output group
count. Use a cancellation after an actual ISP SOF and require one cleanup pulse and
a failed terminal, then complete the post notification, retirement and a legal recovery
without resetting. Test a coordinated reset with PIX stopped separately. Check a fresh
first successful transaction after restart.

Use identical timed stimuli in both arms and compare accepted events and stalls as well
as the independent expected identities, data and terminal counts. Include a legal first
transaction, one finite tail stall, a stale RAW SOURCE followed by the matching one,
cancellation/drain and recovery, and stopped-clock reset. Bound wall clock and simulation
cycles. A small external-ISP leaf test covers the public ownership and handshakes at
this boundary. Physical timing, camera ingress, DDR and full-raster throughput are separate.
