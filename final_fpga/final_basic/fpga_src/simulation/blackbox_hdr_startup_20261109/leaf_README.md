# HDR pair gate: independent leaf test

The scoreboard uses the public [token and terminal contract](../../../docs/seed12fix_20261109/GATE_PUBLIC.md) and [port declarations](../../../docs/seed12fix_20261109/GATE_PORTS.txt). It never observes DUT internals. It counts accepted input tokens and SOURCE handshakes on the PIX rising edge, and checks every passive RAW pulse against the submitted RAW4, SOF/EOL and cohort identity. SOURCE `valid` and its identity, status and error must hold throughout backpressure and until transfer.

From the repository root, using the local Python and ModelSim paths recorded in `ENVIRONMENT.local.md`:

```powershell
$leaf = 'refactor/camera_raw_r2/src_fpga/simulation/blackbox_hdr_startup_20261109/leaf_run.py'
& 'python' -I -B $leaf baseline --modelsim-bin 'D:/App/modelsim/win64'
& 'python' -I -B $leaf candidate --modelsim-bin 'D:/App/modelsim/win64'
```

The baseline source must be the frozen copy at `refactor/camera_raw_r2/tmp/seed12fix_20261109/baseline/real_hdr_pair_cycle_gate.v`; the runner does not obtain or modify it. Each invocation preserves compiler and simulator logs, commands, tool version, SHA256 of inputs and verdict in its own `refactor/camera_raw_r2/tmp/blackbox_hdr_startup_20261109/leaf_*` directory. Exit 0 is PASS, 1 an HDL assertion failure and 2 a tool or input problem. ModelSim can exit successfully after a `$fatal`; the runner requires the bench's PASS marker and rejects its FAIL marker.

The bench runs a 10 ns PIX clock with the public short profile (`TIMEOUT_CYCLES=512`, `EXTERNAL_PHASE_ENABLE=0`). It allows 64 edges for finite service when the scenario has no reason to wait for a peer. The wall and simulation watchdogs are 45 s and 200 us. The cold case starts with a held group-zero SHORT FS; independent cases also exercise missing identity, missing cycle validity, a valid SHORT that must wait for its LONG, and an invalid SHORT matching a LONG that has emitted RAW. The positive path distinguishes qualified warmup, the first real gate SOURCE and pair completion; it also covers independent SOURCE stalls, STOP drain and reset into a fresh cohort.

After a matched failure and retirement of its negative SOURCE, the sensor side must withdraw `i_stable` and earn warmup again. The leaf explicitly verifies a good warmup pair with no RAW or SOURCE, then reasserts stability. The first two candidate runs (`leaf_candidate_20261109T141129_754168Z` and `leaf_candidate_20261109T141230_604144Z`) retain the original assertion failures: the initial fixture had skipped that precondition and tried to STOP a group with no observed RAW. The final STOP case closes admission only after observing the old group's LONG RAW.

With ModelSim SE-64 2020.4 and identical final bench bytes, the [frozen baseline](../../../tmp/blackbox_hdr_startup_20261109/leaf_baseline_20261109T141349_023412Z/result.json) fails at 705 ns because the group-zero SHORT FS is still stalled. The [candidate](../../../tmp/blackbox_hdr_startup_20261109/leaf_candidate_20261109T141337_423279Z/result.json) passes all 13 scenarios and finishes at 2126 ns.

The short RAW4 geometry and synthetic verified FE are a gate-level stimulus. This test does not qualify the CSI packet parser, vendor FIFO, writer or host path, sustained rate, synthesis, P&R, physical timing or board behavior.
