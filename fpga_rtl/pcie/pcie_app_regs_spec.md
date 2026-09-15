# pcie_app_regs specification

## Purpose and address rules

This single-outstanding AXI4-Lite slave implements the BAR0 user window at
`0x0008_0000`. It latches AW and W independently, accepts either ordering,
applies byte write strobes, and returns `SLVERR` for unaligned, unknown, or
high-address-alias accesses. Read-only identity, capability, status, transport,
and H2C counters use generated V1 protocol constants.

CONTROL exposes application enable and soft reset. TEST_LENGTH, TEST_PATTERN,
and TEST_TRIGGER drive the fixed source. TEST_TRIGGER is a one-cycle pulse for
each accepted write with bit zero set.

```wavejson
{"signal":[{"name":"awvalid","wave":"010...."},{"name":"awready","wave":"01....."},{"name":"wvalid","wave":"0.10..."},{"name":"wready","wave":"0.1...."},{"name":"bvalid","wave":"0..1.0."},{"name":"bready","wave":"1......"},{"name":"write_commit","wave":"0..10.."}]}
```

## Verification

`tb_pcie_app_regs.v` covers AW-first, W-first, simultaneous arrival, read/write
backpressure, WSTRB behavior, invalid offsets, and high-bit aliases.
