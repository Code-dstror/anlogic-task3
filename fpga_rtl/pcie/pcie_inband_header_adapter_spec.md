# pcie_inband_header_adapter specification

This Verilog-2001 block runs entirely on `i_clk`; active-low asynchronous reset
`i_rst_n` discards a partial record. It accepts exactly four full-width header
beats followed by 1..`PCIE_MAX_PAYLOAD` payload bytes. Header beats require
`TKEEP=16'hffff` and `TLAST=0`. It validates magic, protocol version, 64-byte
header length, payload length, `flags==1`, and both reserved regions. Status,
error and CRC fields are opaque and are preserved byte-exactly.

FSM transitions are `HEADER -> META -> PAYLOAD -> HEADER`. A header-only error
uses `HEADER -> DRAIN -> HEADER`; DRAIN ends only on an accepted `TLAST` or
reset and never scans payload for magic. `META` holds every decoded field until
the metadata handshake. `PAYLOAD` is a combinational ready/valid bridge, so the
source tuple remains stable whenever the downstream is stalled. `o_busy`
includes partial headers, META, PAYLOAD, and DRAIN.

`i_app_enable` is outside this module. Pausing it in the wrapper preserves a
partial header; the source must resume the same AXI-stream record. Application
reset is the only way to discard that partial header.

Timing scenario: four accepted header beats, an arbitrary metadata wait, then
payload beats; no payload handshake can occur before metadata acceptance.

Verification covers lengths 1, 15, 16, 17, maximum-minus-one and maximum,
random source gaps, random downstream stalls, exact metadata preservation,
malformed-header drain, and reset of a partial header.
