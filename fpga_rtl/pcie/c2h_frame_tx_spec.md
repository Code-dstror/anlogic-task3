# c2h_frame_tx specification

## Purpose and interface

The transmitter accepts one metadata record and one 128-bit payload stream,
then emits `[64-byte header][payload]` on C2H0. All ports are synchronous to
`i_clk`; `i_rst_n` is asynchronous-assert, synchronous behavior after release.
The metadata record is accepted only when transport enable, link-up, and the
SGDMA C2H-running status are all true.

The header uses the generated V1 protocol constants. It is four full beats;
the payload follows without byte packing. Payload length is limited to 16 MiB.
`TKEEP` and `TLAST` are checked against the declared payload length.

## Backpressure and completion

State, output data, keep, last, and slot ownership advance only on
`o_axis_tvalid && i_axis_tready`. `o_frame_done` pulses only for the accepted
final payload beat. Invalid length or inconsistent source framing pulses
`o_frame_abort` and records an error instead.

```wavejson
{"signal":[{"name":"meta_valid","wave":"01.0..."},{"name":"meta_ready","wave":"01.0..."},{"name":"axis_valid","wave":"0.1....0"},{"name":"axis_ready","wave":"1..0.1.."},{"name":"axis_data","wave":"x.=.=.=x","data":["H0","H1","H2/PAY"]},{"name":"axis_last","wave":"0.....10"},{"name":"frame_done","wave":"0.....10"}]}
```

## Verification

`tb_c2h_transport.v` checks byte-exact headers and payloads, boundary lengths,
tail keep masks, last, and randomized/extended backpressure.
