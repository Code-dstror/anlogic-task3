> SUPERSEDED 2026-10-31: FPGA dehaze was withdrawn. These assets describe
> the abandoned S1 candidate; do not run them against the final no-dehaze source set.
> Reproduction uses the frozen71734f2f donor; current checks use ../no_dehaze/.

# S1 RGB / row / owner checks

The four production S1 leaves are copied byte-for-byte from frozen donor
71734f2fe44ecad71a60b0556421abde55493224. This candidate must earn its own
source-bound results; donor PASS and resource reports are not qualifications.

Run from the repository root with a fresh output name:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File refactor/dual_lane_s1/src_fpga/simulation/s1_rgb/run.ps1 -TdRoot D:/App/TD_Release_2026.2.210.850 -OutputDirectoryName output-new
```

The runner uses official TD DSP models and compiles the unchanged vendor MAC
as Verilog separately from SystemVerilog benches. `reference.py` generates
8 coefficient patterns over all 1080 rows, all 130816 possible clamp pairs,
and 327680 MAC identity/range checks. Lanes pack B/G/R at k*24/+8/+16;
Y occupies k*8. Signed rounding, cap80 and the continuous dark floor are exact.

`tb_s1_row` checks 8640 rows including band boundaries and the six-clock
background MAC. `tb_s1_restore` checks 8192 groups, continuous input, finite
random stalls, final-beat hold and clear/reset recovery. `tb_s1_wrapper`
checks 960 groups, frozen owner/history, continuous 480-group rows, malformed
EOL rejection and release only after accepted last output plus drain.

Generated vectors, libraries, logs and input hashes live in ignored output*
directories. These checks do not run synthesis, physical implementation or
board tests. No resource optimization or IP regeneration is performed here.
