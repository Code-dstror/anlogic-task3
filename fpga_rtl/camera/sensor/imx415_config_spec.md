# `imx415_config` specification

After reset, `o_xclr` remains low for `WAIT_CYCLES`, is released, and receives another stabilization wait. The controller writes table indices 0 through 200, writes `STANDBY=0`, waits `WAIT_CYCLES` (240,000 cycles at 24 MHz equals 10 ms), writes `XMSTA=0`, then holds `o_done`. Any I²C NACK enters a fail-closed state with `o_error` held until reset.

```wavejson
{ "signal": [
  { "name": "i_rst_n", "wave": "01.........." },
  { "name": "o_xclr", "wave": "0..1........" },
  { "name": "table writes", "wave": "x...=.=.=..x", "data": ["0","...","200"] },
  { "name": "STANDBY", "wave": "x........=x", "data": ["0"] },
  { "name": "XMSTA", "wave": "x.........=", "data": ["0"] },
  { "name": "o_done", "wave": "0..........1" }
] }
```

Verification checks all 203 decoded transactions, XCLR and wake waits, completion ordering, reset during a transaction, and fail-closed behavior for all NACK positions.
