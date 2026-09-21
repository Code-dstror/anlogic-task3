# CSI-2 asynchronous event FIFO

## Interface and ownership

`csi2_async_event_fifo` carries 47-bit pixel and event items from the recovered
word clock to the pixel clock. Both domains receive the same active-low
asynchronous reset source, which must assert when either clock domain is
restarted. The Anlogic Soft FIFO 3.0 instance has `ASYNC_RST_SYNC_RELS=1`; its
`rst` input asserts both domains and the protected IP releases each domain
locally. The wrapper does not combine already synchronized resets.

`o_write_ready` is gated by the vendor write reset-done flag, `full`, and the
504-word almost-full threshold. `o_read_valid` is gated by the vendor read
reset-done flag, `valid`, and `empty`. The wrapper writes and reads only on
the corresponding `valid && ready` clock edge. The consumer must hold its
read-side backpressure and frame-abort contract separately.

## Reset sequence

1. Assert `i_reset_n=0` while clocks may be stopped. Write ready and read
   valid must be low; unread items are invalidated.
2. Hold reset long enough for both clocks to observe it, then deassert it.
   The vendor IP releases each side after local clock edges. If one clock is
   stopped, that side remains unavailable until it starts and reset completes.
3. Start a new frame after the write reset-done flag; no pre-reset item may
   reappear after read reset completes.

The board top drives the upstream reset from the camera PLL lock chain. A
system integration must also assert this reset on pixel-clock loss. A reset
that omits a stopped domain is outside this wrapper's contract.

## Timing example

```json
{"signal":[{"name":"write_clk","wave":"p......."},{"name":"read_clk","wave":"0...p..."},{"name":"i_reset_n","wave":"0.1....."},{"name":"o_write_ready","wave":"0..1...."},{"name":"o_read_valid","wave":"0.....1."}]}
```

`tb_csi2_async_event_fifo_reset.v` checks asynchronous assertion, a delayed
read clock, an item held until that clock starts, and reset flushing. The
existing receiver and CSI-to-RGB tests cover normal traffic, overflow, frame
error recovery, and backpressure using the same vendor FIFO model.
