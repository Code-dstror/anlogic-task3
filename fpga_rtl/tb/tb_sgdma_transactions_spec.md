# tb_sgdma_transactions verification contract

## Scope

This self-checking Verilog-2001 testbench instantiates the encrypted vendor
`sgdma_ip` directly with the production-relevant PH1A, 128-bit AXI-Stream,
one-H2C/one-C2H, descriptor-bypass-disabled configuration. It operates at the
PCIe transaction boundary and intentionally excludes PHY/link training,
configuration-space enumeration, IOMMU/cache coherency, interrupts, and the
RK3576 Linux driver.

## Scenario

1. Release `core_rstn` on an 125 MHz `core_clk`.
2. Inject a one-DWORD CQ Memory Read to DMA BAR1 offset `0x3000` and require a
   CC completion containing config identifier `0x1fc30001`.
3. Use CQ Memory Writes to program C2H0 `first_desc` at offsets
   `0x5080..0x5088`, then set `RUN_STOP` at offset `0x1004`.
4. Require an eight-DWORD descriptor-fetch RQ at host address `0x00100000`.
5. Return one official 32-byte C2H streaming descriptor over RC. Its control is
   `DESC_MAGIC|STOPPED|COMPLETED|EOP`, payload destination is `0x00200000`, and
   result-writeback destination is `0x00300000`.
6. Supply one 16-byte C2H AXI-Stream beat and compare the emitted Memory Write
   payload exactly.
7. Require the two-DWORD result writeback `{length=16,status=0x52b40001}`.

## Pass and failure rules

The test passes only after all checks above. Any missing/mismatched CC, RQ,
payload, or result writeback increments the error count. A 100 microsecond
watchdog prevents an indefinite wait. The PowerShell runner also rejects any
`FAIL:` or `ERROR:` marker in the transcript.

## Timing sketch

```text
core_clk  _|-|_|-|_|-|_|-|_|-|_|-|_|-|_|-|_|-|_
CQ read       [config MRd]
CC                         [config CplD]
CQ writes                         [desc ptr][RUN]
RQ fetch                                          [MRd]
RC desc                                                [hdr+D0][D1..4][D5..7]
C2H stream                                                                   [16B]
RQ payload                                                                       [MWr hdr][16B]
RQ result                                                                                       [MWr hdr][status,len]
```
