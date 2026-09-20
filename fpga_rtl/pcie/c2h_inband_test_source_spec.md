# c2h_inband_test_source specification

This synthesizable Verilog-2001 board-test composition emits one complete
in-band record per accepted `i_start`. It reuses `c2h_test_source` and
`c2h_frame_tx`, runs on `i_clk`, resets asynchronously low, and holds its
AXI-stream tuple under backpressure.

There is no local FSM; state and illegal-state recovery are owned by the two
instantiated and separately specified modules. `o_busy` is their busy union.

Timing scenario: start pulse in IDLE, four header transfers, one or more payload
transfers, final TLAST handshake, busy deassertion and sequence increment.
