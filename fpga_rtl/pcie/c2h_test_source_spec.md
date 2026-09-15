# c2h_test_source specification

## Purpose and behavior

This user-clock-domain source turns one test trigger into one metadata record
and a payload of the configured length. Modes generate incrementing bytes,
one fixed byte, or deterministic pseudo-random data. Metadata is held until its
ready/valid handshake; payload is held during downstream backpressure.

Triggers received while busy are ignored by this module and counted by the
top-level register logic. Length validation remains the transmitter's
responsibility so invalid-length behavior can be tested end to end.

```wavejson
{"signal":[{"name":"start","wave":"010...."},{"name":"busy","wave":"01....0"},{"name":"meta_valid","wave":"01.0..."},{"name":"meta_ready","wave":"0.1...."},{"name":"src_valid","wave":"0..1..0"},{"name":"src_ready","wave":"1...01."},{"name":"src_last","wave":"0....10"}]}
```

## Verification

The source is exercised through `tb_c2h_transport.v`, including source gaps
and sink backpressure.
