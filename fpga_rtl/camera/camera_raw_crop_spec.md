# `camera_raw_crop` specification

`camera_raw_crop` accepts a four-pixel RAW10 ready/valid stream and forwards the rectangular region defined by the elaboration-time `WIDTH`, `HEIGHT`, `FIRST_ROW`, and `FIRST_GROUP` parameters. Configuration is static until reset. `i_raw_sof` resets the input coordinate to row/group zero and `i_raw_eol` advances to the next row. Output SOF is the first selected group. The last selected group of each row is held in a 40-bit register while right-margin groups are consumed, then released with output EOL only after the real input EOL is accepted. This lets a CSI payload CRC error abort the row before downstream logic observes its end.

Unselected input transfers do not depend on downstream readiness. Selected transfers obey backpressure and hold data and markers while stalled. A valid abort item, an incomplete selected line, coordinate overflow, or a new SOF before completion emits a one-cycle `o_abort`, discards the frame, and requires a later SOF for recovery. No RAM or FIFO is inferred.

```wavejson
{ "signal": [
  { "name": "i_clk",       "wave": "p......." },
  { "name": "i_raw_valid", "wave": "01...0.." },
  { "name": "o_raw_ready", "wave": "1..0.1.." },
  { "name": "o_valid",     "wave": "01...0.." },
  { "name": "o_sof",       "wave": "010....." },
  { "name": "o_eol",       "wave": "0...10.." }
] }
```

Verification covers crop origin phase, extra source rows/groups, random output stalls, immediate consecutive frames, short selected lines, abort, and next-SOF recovery.
