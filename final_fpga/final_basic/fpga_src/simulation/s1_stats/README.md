> SUPERSEDED 2026-10-31: FPGA dehaze was withdrawn. These assets describe
> the abandoned S1 candidate; do not run them against the final no-dehaze source set.
> Reproduction uses the frozen71734f2f donor; current checks use ../no_dehaze/.

# S1 statistics checks

Run the new candidate from the repository root with a fresh name:

```powershell
& 'python' -B refactor/dual_lane_s1/src_fpga/simulation/s1_stats/run.py --name new_stats --td-root D:/App/TD_Release_2026.2.210.850 --modelsim-bin D:/App/modelsim/win64
```

Frozen donor: 71734f2fe44ecad71a60b0556421abde55493224. The production stats
leaf and its independent numerical test assets are copied unchanged; results
are generated anew under this candidate's tmp/s1_stats/<name>.

The single PIX-domain observation interface advances on valid && ready:
RGB24 plus Y8, 320x180 raster samples, EOL every320, last at57600. RGB packs
R/G/B at23:16/15:8/7:0. SOURCE and F20 status must both qualify the identical
frame. The four 10-bit G and four 8-bit C values are frozen at MAIN admission;
owner pin survives cancellation until release. History age is at most4.

Official selected-release ERAM models and the existing20x1024 IP wrapper are
used. Checks cover2048 final buckets, all64 gain truth-table entries,
continuous same-bin/ABAB forwarding, exact quantile rank1439/1440, four-band
means, strict night equality, SOURCE/F20 order, bad identity/status, negative
SOURCE, cancellation, reset, replay, immutable-control rejection, pin lifetime
and temporal G+/-16/C+/-4. The first compatible publication uses raw values.

The runner hashes actual RTL, generated vectors, benches and model sources
before and after execution. Sandbox DLL startup failures remain failed attempts;
use this machine's registered native execution policy. Synthesis, physical
implementation, bitstream and board qualification are separate gates.
