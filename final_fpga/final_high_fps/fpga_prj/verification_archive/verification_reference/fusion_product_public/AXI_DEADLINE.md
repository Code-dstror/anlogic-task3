# Inherited AXI service deadline and recovery

The integration handoff originally said finite response delays without stating the existing
service deadline. That omission does not make arbitrarily large response delays a positive
transaction profile. This addendum does not change production RTL or its watchdog value.

The ancestor's public specification is `../../../../src_fpga/rtl/ddr/ddr_axi_two_client_arbiter_spec.md`,
specifically its TIMEOUT_CYCLES and coordinated-recovery paragraphs. The current selected
`ddr_axi_two_client_arbiter` retains TIMEOUT_CYCLES=4096. Its SHA256 is
`380eeec665aa03ab2c0fffb944747afcbe4399f3182ab917496d0a6dfe73b446`, identical across
camera_rate_r2, camera_rate_r3, camera_raw_r2, camera_hdr_quality_r1 and this fusion project.
The ancestor's older response-memory implementation is not a description of the current RAM
implementation; only the unchanged external watchdog/recovery behavior is used here.

Let k be the rising DFI edge accepting the final W beat of a burst. BVALID sampled on any edge
k+1 through k+4096 satisfies this wait deadline. If BVALID is still zero on k+4096, a sticky
hard recovery fault is asserted. A response already present but held by BREADY is excluded
from the wait counter. Actual channel progress resets the appropriate direction's counter.
AW, W and DDR R service also have the inherited bounded-progress watchdog. Client-side R
backpressure after responses have entered the owned buffer is not missing DDR service.

A BFM that waits 4096 subsequent rising edges and then presents BVALID at the following falling
edge is serviced at k+4097, outside this profile. That was the a08/a10 stimulus. Retain those
original FAIL logs as a handoff contract gap, not a passing positive transaction or an RTL fix.
The exact-deadline positive case may wait 4095 edges and drive the following falling edge,
so BVALID is sampled at k+4096. The independent scoreboard must continue checking all valid
product and retirement properties under that within-window service.

On hard timeout, no successful product is allowed; stop new grants and retain all already
accepted AXI obligations. A late matching B is still drained. Fault/negative SOURCE is expected
and does not mean successful JPEG/DMA retirement. Recovery requires a coordinated reset of
both clients, their ownership/CDC state, the arbiter and the modeled DDR endpoint. Resetting
only the arbiter or claiming SAFE from elapsed time is forbidden.

For the short external test: inject the just-outside-window response, observe fault and no
record/TLP success, return every accepted R/B and verify zero outstanding obligations. PERST,
link, APP and PLL-ready controls are not the configuration-level cold-reset authority: they
deliberately retain DDR/native/product ownership. The current carrier has no driven external
configuration-cold-reset pin, so no test may force an internal reset or assume link loss clears it.

End that faulted simulation only after the above external debt checks, then use a completely
fresh simulator invocation to model FPGA reconfiguration/power-on together with fresh DDR and
host endpoints. The official GSR, initial configuration state and whole DUT are reinitialized.
BOOT/configure/ARM and complete a distinct seq21/native-buffer first product in that new run.
This demonstrates a full cold reconstruction, not same-session or PERST-only recovery. It is
not authorization to reset/reprogram a board and does not define a new RK timeout policy.
