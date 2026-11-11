# Actual camera silence and repeated fault recovery

The new candidate-only `run_silence_recovery.py` reuses the six explicit boundary
stubs from `src_fpga/simulation/runtime_stress/cfg_silence_run.py`, replacing the
frozen Git lookup with an explicit candidate source root. It compiles the complete
actual `real_hdr_camera_observe_axis` and `production_source_identity_guard`.
No production block is copied into a behavioral monitor. The stubs retain exact
candidate port/parameter headers. Source bytes are copied and hashed before
compilation, and original/copied hashes are checked again after simulation.

```powershell
& 'python' -I -B `
  refactor/hdr_rx_runtime/src_fpga/simulation/runtime_recovery/run_silence_recovery.py `
  --source-root refactor/hdr_rx_runtime `
  --output-root refactor/hdr_rx_runtime/tmp/runtime_silence_20261029 `
  --name NEW_UNIQUE_NAME --modelsim-bin D:/App/modelsim/win64
```

ModelSim requires native execution on this Windows machine. No TD models are
used by these two actual modules and the six boundary stubs.

The 2026-10-29 `r2/RESULTS.json` records PASS with zero warnings:

| Check | Result |
| --- | --- |
| Configuration and calibration gates, threshold-minus-one gap, RAW valid under ready=0 | No false silence fault |
| Reduced threshold 64, continued silence | Exactly one one-cycle receive-fault/abort pulse |
| Healthy FS with recovery quiet denied | Quarantine remains asserted |
| Healthy consumed FS after quiet allowed | Quarantine clears without cohort reset |
| Two silence episodes, two parser identity-loss episodes, two PHY ready-loss episodes | Six pulses, six recoveries, same live cohort; 32 assertions total |
| Complete wrapper default parameter, no SILENCE_CYCLES override | 12,500,000th empty PIX edge at 100,000,564 ns after 568 ns falling-edge stimulus; exact 100 ms threshold at 125 MHz |
| Default-threshold recovery with quiet veto and healthy FS | PASS; 12 assertions total |

The reduced test took 2.140 seconds and the default test 5.813 seconds.
`r1` failed while Python decoded a UTF-8 candidate source using Windows GBK;
ModelSim did not start. The runner now decodes source text explicitly as UTF-8.

The PHY/parser, I2C and ISP boundaries are stubs. This test verifies actual
watchdog/edge-detector/guard behavior and the supplied quiet authority. It does
not prove actual packet reception, crop quiet, SOURCE retirement, JPEG closure,
slot protection, electrical behavior, or board recovery. Those remain covered
by the real receiver/physical chain benches and the separate complete TOP run.
No production RTL, main bench/runner/oracle, server, board or automation changed.
Synthesis, P&R, timing, bitgen and board are NOT_RUN.
