# h2c_stream_checker specification

## Purpose and behavior

The checker accepts H2C0 AXI-Stream beats in `i_clk` and compares each kept
byte with an incrementing byte pattern that restarts at zero after `TLAST`.
It reports cumulative byte, frame, and mismatch counts and the first mismatch
offset. All mismatches in an accepted beat are counted.

`o_axis_tready` is asserted outside reset. Inputs are sampled only on the
ready/valid handshake.

```wavejson
{"signal":[{"name":"tvalid","wave":"01.01.0"},{"name":"tready","wave":"01....."},{"name":"tkeep","wave":"x=.x=.x","data":["ffff","000f"]},{"name":"tlast","wave":"0...1.0"},{"name":"byte_count","wave":"x.=.=..","data":["16","20"]},{"name":"frame_count","wave":"x...=..","data":["1"]}]}
```

## Verification

`tb_h2c_stream_checker.v` checks a correct multi-beat frame and multiple bad
bytes within one accepted beat.
