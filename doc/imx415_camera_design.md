# IMX415 RGB camera IP design contract

User scope: IMX415 through the example's FMC physical pins, RGB888 output,
128-bit AXI-Stream with TKEEP and frame TLAST. 1080p60 is the first target;
3840x2160 at 30 fps is the expansion target. No PCIe/JPEG transport is inside
the camera IP. All RAM/FIFO storage uses TD vendor IP/primitives.

## Architecture and implementation ownership

`csi_raw10_rx` (vendor PHY, checked packet decoder, vendor asynchronous FIFO)
feeds a handshake-aware crop stage, the migrated 4PPC ISP, and
`rgb_axis_packer`. The public stream consists only of R,G,B bytes, earliest
byte at TDATA[7:0]. TLAST terminates a frame, not a line. Internal RAW/RGB
streams use SOF and EOL. Configurations are elaboration-time parameters in
the board example; reusable data-path inputs are held constant until reset.

The CSI receiver may issue a sequenced abort item. It resets the ISP, aborts
packing without retracting an already offered AXIS beat, and reacquires SOF.
Consumers must discard any partially emitted frame when frame_error occurs.
No finite FIFO guarantees lossless capture against unlimited backpressure.

## Storage and clock plan

- PHY source snapshot and Anlogic PH1 primitives; no replacement PHY model.
- Anlogic Soft_FIFO 3.0 for asynchronous receive buffering.
- PH1 ERAM primitives for ISP line stores and gamma tables.
- Small packing/pipeline registers are registers, not inferred RAM/FIFO.
- Pixel domain target: 125 MHz, four pixels per accepted beat.
- Sensor clock: 24 MHz, driven directly from the reference PLL output,
  removing the example's extra divide-by-two.
- Sensor PLL/MIPI timing must match 24 MHz INCK. Profile target: 720 Mb/s
  per lane, four lanes, HS clock 360 MHz. The Linux IMX415 driver clock and
  link-rate tables are an independent cross-check of these register facts:
  https://github.com/torvalds/linux/blob/master/drivers/media/i2c/imx415.c
- Frame timing uses HMAX=533 for binning / 1066 for full-pixel and VMAX=2250.
  Nominal rates from 72 MHz are about 60.04 / 30.02 fps. Sensor mode and
  physical capture rates still require board measurement.

## Sensor controller state plan

Reset dominates all events. Hold XCLR low for a parameterized power-on wait;
release it and wait for stabilization; write the 201-entry reviewed table;
stop and latch failure on any NACK; write STANDBY=0; wait 10 ms; write
XMSTA=0; assert configuration done. Reconfiguration requires reset.

The I2C writer uses a single input clock with a tick enable (no fabric-generated
SCL clock domain). Sequence: IDLE -> START -> bit LOW/HIGH (8 times) -> ACK
LOW/HIGH -> next byte or STOP LOW/HIGH/RELEASE -> DONE. Four bytes are sent:
0x34, register high byte, register low byte, data. NACK causes STOP and failure.

## Verification plan

Independent byte/pixel scoring, random stalls/gaps, reset, back-to-back frames,
malformed packet/ECC/CRC, FIFO overflow and recovery, crop bounds, RGB byte
order and final masks. Real TD RAM/FIFO models are used for storage simulation.
Run 1080/4K complete frames; report simulation throughput separately from
physical frame rate. TD synthesis, placement/routing and final timing are
separate evidence. Physical PHY signal integrity and image quality require a
connected board and are never inferred from protocol simulation.

The public RTL checks are compile, ast, readability, comment, naming, profile,
testbench, toolchain. Their actual outcomes are reported at delivery.
