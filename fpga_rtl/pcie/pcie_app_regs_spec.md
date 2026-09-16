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

After reset, board-test registers select the fixed JPEG fixture: TEST_PATTERN
is 3 and TEST_LENGTH is `C2H_TEST_JPEG_FIXTURE_LENGTH` (331). Both defaults use
the shared fixture constant from `fpga_rtl/include/c2h_test_fixture.vh`, so
they cannot drift.
Software can explicitly write TEST_PATTERN 0, 1, or 2 and TEST_LENGTH to retain
the incrementing, A5, and XOR test-payload modes. In mode 3, the source ignores
the programmed TEST_LENGTH and emits the fixture's real 331-byte length.

```wavejson
{"signal":[{"name":"awvalid","wave":"010...."},{"name":"awready","wave":"01....."},{"name":"wvalid","wave":"0.10..."},{"name":"wready","wave":"0.1...."},{"name":"bvalid","wave":"0..1.0."},{"name":"bready","wave":"1......"},{"name":"write_commit","wave":"0..10.."}]}
```

## Verification

`tb_pcie_app_regs.v` covers AW-first, W-first, simultaneous arrival, read/write
backpressure, WSTRB behavior, invalid offsets, and high-bit aliases.
