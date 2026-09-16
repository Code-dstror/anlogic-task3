# c2h_test_source specification

## Purpose and behavior

This user-clock-domain source turns one test trigger into one metadata record
and a payload. Metadata is held until its ready/valid handshake; the complete
`TDATA`, `TKEEP`, and `TLAST` tuple is held during downstream backpressure.

`i_pattern_select` defines these modes:

| Value | Mode | Payload and metadata length behavior |
| --- | --- | --- |
| 0 | Incrementing bytes | Byte `n` is `n[7:0]`; uses `i_payload_length`. |
| 1 | Fixed A5 | Every valid byte is `8'hA5`; uses `i_payload_length`. |
| 2 | Deterministic XOR | Byte `n` is `n[7:0] ^ n[15:8] ^ 8'h5A`; uses `i_payload_length`. |
| 3 | Fixed JPEG fixture | Complete 331-byte baseline JPEG fixture; ignores `i_payload_length`. |

Mode 3 is a real, fixed 1×1 grayscale JPEG. Its payload length and metadata
payload length are always `C2H_TEST_JPEG_FIXTURE_LENGTH` (331), and its width
and height are always `C2H_TEST_JPEG_FIXTURE_WIDTH` / `HEIGHT` (1 / 1).
`compression` remains JPEG (`8'd1`). The programmed length is deliberately
ignored in this mode: it cannot create a truncated fixture, add padding, or
cause metadata to describe a different byte count. `TKEEP` is contiguous from
lane zero, and `TLAST` is asserted only on the beat carrying the last fixture
byte.

Triggers received while busy are ignored by this module and counted by the
top-level register logic. Length validation remains the transmitter's
responsibility so invalid-length behavior can be tested end to end.

```wavejson
{"signal":[{"name":"start","wave":"010...."},{"name":"busy","wave":"01....0"},{"name":"meta_valid","wave":"01.0..."},{"name":"meta_ready","wave":"0.1...."},{"name":"src_valid","wave":"0..1..0"},{"name":"src_ready","wave":"1...01."},{"name":"src_last","wave":"0....10"}]}
```

## Verification

The source is exercised through `tb_c2h_transport.v`, including source gaps
and sink backpressure. Its mode-3 case checks every emitted payload beat against
an explicit 128-bit case-table oracle with AXI lane zero in bits `[7:0]`; the
oracle does not use the source's packed-vector slice. `tests/test_c2h_jpeg_fixture.py`
verifies that this oracle reconstructs the canonical fixture byte-for-byte,
including final disabled lanes, plus JPEG markers, OpenCV decode, fixture
dimensions, mode mapping, register defaults, and modeled AXI final-beat/
backpressure semantics in the Ubuntu Python test environment.
