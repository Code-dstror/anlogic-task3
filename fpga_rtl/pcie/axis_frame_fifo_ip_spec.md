# axis_frame_fifo_ip specification

## Purpose and clocking

This module adapts ready/valid traffic to the official Anlogic Soft FIFO 3.0.
`i_source_*` is synchronous to `i_source_clk`; `o_sink_*` is synchronous to
`i_sink_clk`. Both active-low reset inputs feed the vendor FIFO reset input.
The packed 147-bit word is `{slot_id[1:0], tlast, tkeep[15:0], tdata[127:0]}`.

The wrapper contains no storage, pointer, or CDC implementation. Those
functions are provided by the encrypted vendor IP configured as asynchronous,
512 words deep, show-ahead enabled, and two-stage synchronized.

## Handshake behavior

A source word is accepted only on `i_source_valid && o_source_ready`. A sink
word is consumed only on `o_sink_valid && i_sink_ready`. While stalled, the
vendor show-ahead output remains at the current head word.

```wavejson
{"signal":[{"name":"source_valid","wave":"01..0"},{"name":"source_ready","wave":"0.1.."},{"name":"fifo_we","wave":"0.10."},{"name":"sink_valid","wave":"0..1."},{"name":"sink_ready","wave":"0...1"},{"name":"fifo_re","wave":"0...1"}]}
```

## Verification

`tb_axis_frame_fifo_ip.v` exercises independent clocks, fill/drain ordering,
and sink backpressure against the TD PH1 simulation library.
