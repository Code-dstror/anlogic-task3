# HDR merge focused simulation

Run `../../../tools/run_hdr_merge_short.py` from the project with explicit
`--modelsim-bin` and `--td-root`. The repository-root command and current
results are in `../../../docs/HDR_FUNCTIONAL_PORT.md`.

These testbenches derive from sealed R3 pair_overlap, full_overlap_rx_r3 and
hdr_boundary_fix fixtures. They use the merge candidate's actual RTL and
fixed 6f seven-guard aligner. New donor diagnostics are replaced with
testbench-only observations and existing public error semantics. `pair`
adds held SOURCE and independent terminal retirement checks.

`pair_baseline` reads fixed 6f owner bytes using git show. `boundary_baseline`
reads fixed 6f owner/capture/dual/core bytes and instantiates the old physical
INDEPENDENT_BURSTS=1 contract on the same actual byte chain. These reproduce
the original restrictions; their PASS means the baseline defect is present.
No test changes vendor files, sensor recipes, clocks or constraints.

Run work libraries/source snapshots are under `runs/<name>` and are
regenerable. Compact logs/JSON are archived under project docs/validation.
Each name is unique; historical runs are never overwritten.
