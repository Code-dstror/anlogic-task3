# `camera_i2c_write` specification

The module performs one open-drain I²C write per `i_start`: device write byte `0x34`, 16-bit register address high byte first, then the register value. SCL and SDA phases advance from the single `i_clk` domain at `HALF_PERIOD` cycle intervals. SDA changes while SCL is low except for START and STOP. The slave drives each ninth-bit ACK; any sampled NACK completes STOP and latches `o_error`. `o_done` is the one-state completion indication before return to idle.

```wavejson
{ "signal": [
  { "name": "o_scl", "wave": "1.01010101." },
  { "name": "io_sda", "wave": "10========1", "data": ["7","6","5","4","3","2","1","0"] },
  { "name": "ACK", "wave": "x........0x" }
] }
```

Reset releases both bus lines and clears status. Verification uses an open-drain serial slave and injects NACK independently on each of the four byte positions.
