# Fixed reciprocal profile short check

`run.py` compiles the isolated candidate with the explicitly selected TD PH1
models. It compares every non-control-status map output on every active cycle
between `AUTO_FIXED_LUT_ENABLE=1` and a default-parameter manual instance which
receives a real BEGIN, 257 WORDs and COMMIT for generation 1. The auto instance
receives no load. Constant observations have the independently calculated
result A=96, t=128, reciprocal=512; accepted tile and pinned ERAM data are checked.

The 257 frozen ROM entries are checked against the startup guide's integer
formula. Cold reset, first-frame absence of history, qualified history,
accepted main-read drain during cancel/history-reset, partial-frame cancel,
negative SOURCE, failed F20 status and reset of an owned partial frame are
covered. Direct auto BEGIN/WORD/COMMIT each handshake and return existing core
error 4 with generation 1; a held response and cfg_abort cannot stop observation,
publish a bad frame, change a pin or invalidate the fixed table.

The core carries 24-bit observer RGB/8-bit Y with SOF/EOL/final-sample markers;
the short geometry is 120x120 source -> 20x20 observation -> one populated tile.
All samples advance on valid/ready. Main requests use the original two-stage
20-bit ERAM reply and pinned-bank lifetime. Everything uses one clk/rst_n domain;
the existing asynchronous reset assertion/synchronous release remains intact.
This check does not qualify HD RGB restoration, top-level CFG, throughput,
synthesis, P&R, timing or board operation. Complementary integration checks live
under `../main`.

Run from the repository root (use a fresh name to retain every attempt):

```powershell
& 'python' -B `
  refactor/hdr_dehaze_auto/src_fpga/simulation/autof21/core/run.py `
  --name short_r3 --td-root D:/App/TD_Release_2026.2.210.850 `
  --modelsim-bin D:/App/modelsim/win64
```

Evidence is written to `tmp/autof21/core/<name>/qualification.json` with exact
source/model hashes and raw compile/run logs. `short_r1` failed before compilation
because sandboxed ModelSim launch returned Windows error 623. The same bounded
command in native Windows passed in `short_r2`; `short_r3` records the final map
source identity after comment cleanup and wrapper parameter-order preservation:
3,207 cycle comparisons,
3 maps/tiles, 1 pinned read, 3 immutable-table rejects, 648 held-status cycles,
257 ROM entries and 2 cold resets. Synthesis/P&R/timing/board: NOT_RUN.
