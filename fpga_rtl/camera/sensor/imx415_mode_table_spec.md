# `imx415_mode_table` specification

This combinational adapter reads one of the 201 reviewed entries from `ui_imx415reg` and returns `{address[15:0], value[7:0]}`. It preserves the vendor address/order while overriding reviewed clock, frame-timing, and MIPI timing values for a 24 MHz INCK and 720 Mb/s per-lane profile. `MODE_4K=0` selects 2x2-binned 1080p timing; `MODE_4K=1` selects full-pixel 4K timing. The decode is control logic rather than storage.

```wavejson
{ "signal": [
  { "name": "i_index", "wave": "=.=.=.", "data": ["0","1","200"] },
  { "name": "o_register", "wave": "=.=.=.", "data": ["300001","300100","407401"] }
] }
```

Verification compares all table entries against the vendor reference plus the explicit reviewed override map.
