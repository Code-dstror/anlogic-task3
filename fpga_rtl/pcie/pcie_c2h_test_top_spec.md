# pcie_c2h_test_top specification

## Purpose and composition

This board milestone top connects the official PCIe/SGDMA endpoint to the V1
BAR register block, fixed C2H source/transmitter, and H2C checker. Its physical
ports are the 25 MHz clock, PERST#, PCIe differential reference clock, one RX
lane, and one TX lane. The current single-slot test path runs wholly in the
SGDMA user-clock domain.

The application-facing video/JPEG contract is implemented at
`c2h_frame_tx`: metadata ready/valid plus 128-bit payload AXI-Stream. A future
independent producer clock uses `axis_frame_fifo_ip`, whose storage and CDC are
the official Anlogic Soft FIFO 3.0 rather than handwritten logic.

```wavejson
{"signal":[{"name":"APP_ENABLE","wave":"01......"},{"name":"TEST_TRIGGER","wave":"010....."},{"name":"source_busy","wave":"0.1...0."},{"name":"tx_busy","wave":"0..1...0"},{"name":"frame_done","wave":"0......1"},{"name":"consumed_sequence","wave":"x......=" ,"data":["+1"]}]}
```

## Error and status behavior

The BAR status reports link, user reset, C2H-running, TX/source busy, and error
state. Completion increments the consumed sequence. Abort increments the DMA
error count; oversize payload errors also increment overflow count. A trigger
while the fixed source is busy increments drop count.

## Verification

Behavioral submodules are self-checked in ModelSim. The full top is verified by
TD synthesis, place/route, timing, bitstream generation, and routed SDF smoke
simulation. Enumeration and real DMA remain board-level acceptance items.
