# Anlogic Soft FIFO 3.0 vendor snapshot

- Source: `D:/wxd/APP/TD_6.2.1_Engineer_6.2.168.116/ip/depot/Soft_FIFO_3.0`
- Installed TD build: `6.2.168.116`
- Imported: `2026-09-14`
- Target use: asynchronous 147-bit by 512-word AXI-Stream frame FIFO

Every vendor file in this directory is a byte-for-byte copy. Do not edit the
encrypted `Soft_FIFO/RTL/soft_fifo.v`. The project wrapper configures the
official IP with the following resolved generator parameters:

- `COMMON_CLK_EN=0`, `MEMORY_TYPE=0` (PH1 EMB20K area option)
- write/read width `147`, write/read address width `9` (depth `512`)
- show-ahead enabled, output register disabled
- almost-full threshold `504`, almost-empty threshold `2`
- asynchronous reset with synchronous release, two CDC synchronizer stages

`Component.xml`, `Dependency.tcl`, `Layout.tcl`, and `plugin_mid.tcl` are kept
as provenance and configuration evidence. `SHA256SUMS.txt` records the exact
imported content.
