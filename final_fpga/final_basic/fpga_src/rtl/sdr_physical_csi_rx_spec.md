# Second-camera SDR physical receiver

Imported contract from fixed `6effdfaef6:refactor/dual_basic`, with the R6
diagnostic-capable stream interface retained. This candidate must establish
its own qualification; no donor result or mutable source dependency is used.

`sdr_physical_csi_rx` is derived from this candidate's frozen
`real_hdr_physical_csi_rx.v`. It keeps the same controlled sampling PHY and
gearbox, candidate-owned byte/word alignment, calibration barrier, `physical_csi_rx_stream`, official
47-bit event FIFO and physical sequence authority. It removes the HDR parser,
HDR member FIFOs, mode synchronizers and mode multiplexers. The controlled IP
is unchanged. Both eyes use the owned aligners: packet-done cancels acquisition,
disable cancels valid history, and skew beyond the existing five-cycle window
cannot clamp to tap5 and publish. The PH1A scanner scores only a freshly
acquired packet after every tap settles, scans 32 physical delay codes, and
permits at most two activity-triggered scans. A scan without a passing window
never grants publication; a manual override remains explicit. No source is
imported from the new DSI reference example.

## Interface and ownership

The four-lane physical input is non-stallable. `o_raw_data[39:0]` contains four
unsigned RAW10 samples, lowest lane in bits 9:0. A pixel transfer occurs only
on `o_raw_valid && i_raw_ready`. SOF marks the first RAW group after actual CSI
FS; EOL marks the final RAW group of a sensor line. ABORT is a control token,
not pixel data. All these outputs, source sequence/identity, counters and
whole-CSI event outputs belong to `i_pixel_clk`.

With `FRAME_EVENTS_ENABLE=1`, ordered events use kind 0=FS, 1=successful actual
FE, 2=negative ABORT, 3=capacity DROP diagnostic. The source sequence is assigned
by the actual parser FS and survives a normal PHY restart; a restart after
published traffic invalidates trust rather than resetting the sequence to one.
Only the coordinated source-cohort reset starts a new identity cohort. Both
RAW and event consumers must accept an ABORT before the FIFO advances past it.

Finite FIFO capacity only absorbs short bursts and CDC latency. Exhaustion
poisons the affected frame and cannot create a successful FE. A geometry/crop
completion is not a CSI success indication. Event/RAW handshake and recovery
semantics otherwise remain those of `physical_csi_rx_stream`.

## Clocks and reset

The production sensor recipe uses 24 MHz INCK and 720 Mb/s/lane SDR input:
360 MHz forwarded clock and 90 MHz WORD clock. Physical pins and actual local
clock placement require the candidate ADC/SDC and subsequent implementation.
This wrapper does not generate a second pixel clock.

`i_reset_n` is a source-cohort request received from REF. Its release reaches
WORD and PIX through distinct `reset_release_sync` instances before it reaches
identity state or PHY-ready synchronization. The PHY/watchdog can assert a
decoder reset on clock loss while the cohort remains alive. Calibration runs
with packet feedback active and publication disabled, then resets decoding for
four WORD cycles and waits for the actual FIFO write-ready before publication.
Ordinary backpressure never restarts this barrier.

The PHY reset also resets the underlying event FIFO. Thus a PHY failure can
cancel an unaccepted receiver event or RAW beat; the parent frontend reports a
separate receive fault and the SOURCE owner must negatively terminate the
affected frame. This interface does not manufacture an FE or infer success
from FIFO emptiness. The parent adds its own PIX output holding register so an
already presented cropped RAW beat survives this local PHY reset.

## Verification boundary

`../simulation/camera1/run.ps1` tests this actual wrapper, parser, CRC/ECC logic,
official FIFO and crop. Only electrical sampling/eye calibration are replaced
at the PHY boundary; the real clock watchdog runs with a shorter test timeout.
Packet-aligned words enter after the actual gearbox. This is digital protocol
evidence, not lane signal-integrity, bit alignment, LCLK placement, STA or board
qualification. Those gates remain NOT_RUN for the new second receiver.
