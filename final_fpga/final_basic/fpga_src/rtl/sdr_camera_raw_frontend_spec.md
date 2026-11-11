# Second-camera RAW frontend

Imported contract from fixed `6effdfaef6:refactor/dual_basic`. Validation
numbers below describe donor history, not this candidate's qualification.
The integrated CAM1 selects the frozen 47x512 event FIFO explicitly; focused
verification must select that production depth and independent local inputs.

`sdr_camera_raw_frontend` owns only the second IMX415's startup configuration,
SDR receiver and crop. It instantiates no ISP, RGB processor, JPEG encoder,
frame store or clock PLL. Both cameras deliver cropped data to the same PIX
domain; frame admission, DDR ownership and shared processing belong to the
caller.

## Fixed first profile

Defaults are 1920×1080, FIRST_ROW=16, FIRST_GROUP=1, four RAW10 pixels per group.
Small WIDTH/HEIGHT/crop parameters exist for focused digital verification and
do not change the sensor recipe. WIDTH is positive and divisible by four.

The existing `imx415_config` / `imx415_mode_table` SDR recipe remains unchanged:
24 MHz MCLK, 720 Mb/s/lane, VMAX=2250 and the existing binning mode. The frontend
does not program a reduced sensor frame rate or claim external trigger sync.
An upper-level 1/N admission policy limits processed output, while the physical
receiver must continue draining the complete incoming stream.

`i_gain_code` belongs to SENSOR and is stable from reset through boot; the
caller provides the existing allowed range. `RUNTIME_GAIN_ENABLE=1` selects
startup-table gain override, not live AE. Configuration waits and I2C half
period default to the production values; tests shorten them. NACK leaves
configuration failed and reception disabled until a new cohort reset.

## RAW and event contract

`o_cropped_raw_data[39:0]` contains four unsigned samples with lane0 in bits
9:0. A crop transfer is `o_cropped_raw_valid && i_cropped_raw_ready`. SOF, EOL,
sequence and identity-valid travel with that exact transfer. No EOF is invented.

A single PIX-domain output group is held until it transfers. This register is
independent of the PHY/FIFO reset, so clock loss cannot retract a previously
presented cropped group during backpressure. It supports one group per cycle
when downstream is ready. Payload registers need no reset because held-valid
is reset. `o_cropped_raw_abort` is a one-cycle crop-error pulse, not a RAW valid
beat; an already presented group transfers before this pulse is emitted.

All whole-CSI events are forwarded from the actual receiver with their original
sequence, trust, kind, error and handshake. Kind1 FE proves only successful
completion of that CSI frame. A late CRC error outside the selected crop still
produces a negative terminal, even if every cropped pixel has already arrived.
The SOURCE owner must combine actual FE, crop result, exact identity and its
own accepted-write/drain obligations before committing a frame.

The inherited receiver FIFO is reset on a PHY failure. This can cancel an
unaccepted whole-CSI event; the separate receive-fault indication is the
required failure path. An event that has not handshaken has not committed.
The caller must not wait indefinitely for an FE after a receive fault or
treat a later restarted parser event as recovery of the old frame.

## Fault and reset contract

`i_reset_n` asynchronously asserts independent SENSOR, REF and PIX release
chains. Each local consumer releases only on its own clock. Sensor completion
enters REF through `enable_sync` and PIX through `done_sync`; error enters PIX
through `error_sync`; calibration-done enters PIX through `delay_sync`.
The stable eye-scan debug bundle is captured after synchronized done plus two
additional PIX edges.

`o_receive_fault` is a PIX-domain one-cycle indication for PHY-ready falling,
first observed identity fault, or one continuous receive-silence interval.
It is separate from RAW/event ABORT tokens. A held valid RAW or event is not
counted as silence. Its default timeout is 12,500,000 PIX cycles; any future
change in clock or true sensor frame rate must re-evaluate that duration.
Silence reporting rearms when traffic or configuration/calibration status
changes. One physical failure can produce more than one diagnostic cause;
the consumer must make negative termination idempotent.

The caller must invalidate the affected source on receive fault and drain or
discard the held output before resetting its processing owner. The frontend
never overwrites a stalled RAW beat with a synthetic abort. Global cohort reset
cancels outstanding data and events, resets sensor configuration, and permits
a new identity sequence. A PHY restart alone does not restore identity trust.

Passive `o_observe_raw_*` taps describe the uncropped receiver stream and its
actual handshake. They never control READY or alter packet acceptance.

## Validation

Latest focused result: `tmp/camera1/camera1-r3/qualification.json` relative to
the candidate root, **PASS, 14,921 checks**. Source hashes, tool paths and raw
logs are in that run. Earlier r2 validates an earlier output-stage source and
does not supersede r3. The run checks real I2C startup/NACK, exact RAW10 crop and
identity, continuous packet words, random RAW/event stalls, final-group stall,
outside-crop CRC failure, next-frame recovery, real-watchdog clock stop while
RAW is stalled, restart identity poisoning, cohort reset, official 8192-event
FIFO overflow and NACK reset recovery.

Electrical PHY/eye calibration are simulated boundaries. New synthesis,
placement/routing, timing, bitgen and board qualification are NOT_RUN by this
focused test. The first camera/main chain must be verified separately after
top-level integration.
