# pcie_video_transport specification

`pcie_video_transport` is the reusable board transport boundary. The only C2H
application input is 128-bit AXI-Stream (`i_src_tdata`, `i_src_tkeep`,
`i_src_tvalid`, `o_src_tready`, `i_src_tlast`) containing `[64-byte header]
[payload]`. The module exposes the complete SGDMA AXI4-Lite master unchanged so
an external address decoder/register fabric owns all user registers. It also
passes H2C AXI-Stream through and exports PCIe physical pins, user clock/reset,
link/channel status, and transport diagnostics.

The user domain is `o_user_clk`. PCIe user reset and `i_app_reset_n` reset only
the C2H application transport; AXI4-Lite and H2C remain governed by the endpoint
user reset. `i_app_enable=0` prevents new source handshakes. A partial header is
paused, not discarded, across enable toggles. One complete header may be
prefetched while link/C2H is not running, but metadata is not accepted and no
C2H byte is emitted until all admission conditions are true.

After metadata acceptance, a payload framing error or loss of enable/link/C2H
sets `o_recovery_required`. Ready remains low and no next record is accepted
until `i_app_reset_n=0`; software must reset/discard the partial DMA record.
Header-only failures drain to their own TLAST and do not require recovery.

Timing scenario: header prefetch, metadata wait, regenerated header output,
payload output with arbitrary stalls, final output handshake, frame-done pulse.
All AXI tuples are stable while valid and not ready.
