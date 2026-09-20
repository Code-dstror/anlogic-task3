# `rgb_axis_packer` specification

## Contract

`rgb_axis_packer` converts a four-pixel, 96-bit RGB888 video stream into a byte-contiguous 128-bit AXI-Stream frame. It uses one clock domain, an asynchronous active-low reset, and explicit packing registers rather than a RAM or handwritten FIFO.

The added control/status ports are exactly:

- `i_abort`: synchronous, one-cycle-or-longer abort request in `i_clk` domain.
- `o_frame_error`: one-cycle pulse when an active or buffered frame is aborted.
- `o_frame_done`: one-cycle pulse on the successful handshake of the final output beat.

Input lane `k` is `i_rgb_tdata[24*k +: 24] = {R,G,B}`. Output byte order is `R,G,B` for lane 0, then lanes 1 through 3. Byte zero occupies `o_axis_tdata[7:0]`. `i_rgb_tuser` marks SOF and is required for acceptance while idle. `i_rgb_tlast` marks EOL. `i_frame_height` is sampled at SOF and must remain valid for that transfer; a frame ends when the accepted EOL count reaches the sampled height. Width must be a multiple of four pixels because each accepted input transfer contains four pixels.

The semantic model is a byte deque. On an input handshake, append twelve bytes in lane and RGB order. On an output handshake, remove the first sixteen bytes, or all remaining bytes on the frame tail. Present an output whenever the deque contains sixteen bytes, or a completed input frame leaves a nonempty partial tail. `TKEEP[n]` is one exactly when byte `n` is valid. This model defines simultaneous input/output behavior: remove first, append after the surviving bytes.

When `TVALID=1` and `TREADY=0`, `TDATA`, `TKEEP`, and `TLAST` remain stable. An abort stops input immediately. If an output beat is already offered and stalled, the module preserves it until its handshake, then discards every pending byte and waits for a new SOF. This forced drain does not assert `o_frame_done`; a tail beat already visible at abort can still carry `TLAST` because retracting it would violate AXI-Stream stability. Abort without a stalled offered beat discards immediately.

Reset clears all buffered data and status without emitting done or error. A SOF-less transfer while idle is backpressured. The implementation targets a 125 MHz clock; timing closure remains a synthesis obligation.

## Verification plan

The self-checking testbench implements the byte-deque model independently. It covers reset, randomized input gaps, randomized output stalls, stable payload/control under stall, consecutive frames, widths 4/8/12/16 pixels, several heights, all four possible final `TKEEP` populations (4/8/12/16), exact RGB byte values, successful done pulses, and abort while a beat is stalled.

## Timing diagram

```wavejson
{ "signal": [
  { "name": "i_clk",          "wave": "p......." },
  { "name": "i_rgb_tvalid",   "wave": "01..0..." },
  { "name": "o_rgb_tready",   "wave": "1......." },
  { "name": "o_axis_tvalid",  "wave": "0.1...0." },
  { "name": "i_axis_tready",  "wave": "1..01..." },
  { "name": "o_axis_tlast",   "wave": "0.....10" },
  { "name": "o_frame_done",   "wave": "0.....10" }
] }
```

The diagram shows buffered input, output backpressure, and the final-beat handshake that produces `o_frame_done`.
