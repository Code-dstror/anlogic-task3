# SDR runtime recovery checks

This candidate-only runner reads the explicit `--source-root`, copies its RTL/IP
and the selected TD models into a new output directory, then seals every input
with SHA256. It checks the original and compiled bytes again after simulation.
It does not call Git, a server, TD synthesis, or board tools.

From the repository root, use this machine's paths from `ENVIRONMENT.local.md`:

```powershell
$python = 'python'
$runner = 'refactor/hdr_rx_runtime/src_fpga/simulation/runtime_recovery/run_validation.py'
$common = @('--source-root','refactor/hdr_rx_runtime','--output-root','tmp/runtime_fix_20261028/validation/results','--modelsim-bin','D:/App/modelsim/win64','--td-root','D:/App/TD_Release_2026.2.210.850')
& $python -I -B $runner @common --suite word --name word_recovery
& $python -I -B $runner @common --suite word --strict --name word_strict
& $python -I -B $runner @common --suite matrix --name receiver_matrix
& $python -I -B $runner @common --suite physical --name crop_router_raw
```

Each name must be new; the runner never overwrites an earlier run. ModelSim may
require native execution because its executable cannot start inside the Windows
sandbox on this machine.

`word` covers the parser's opt-in recovery and its unchanged strict default,
genuine held tokens, CRC rejection, overflow/drop termination, pending identities,
decoder reset without count rewind, and 32-bit saturation. Both modes separately
run the saturation bench. The b68 startup protection remains: a malformed header
before any FS does not poison future identity.

`matrix` extends the original 37 receiver cases through the real alignment,
gearbox, parser, official 512-entry FIFO, guard and SOURCE fence. Each admitted
identity retires RAW and native SOURCE exactly once with the same status. Random
finite ready stalls exercise all four output/control paths. After a runtime bad
header or PHY loss, the boundary frame clears quarantine while remaining ignored;
the next seven of eight full frames succeed. The old open frame retires negatively.
CRC, length, truncated RAW stimulus, missing/duplicate FE, FS reentry and corrected
headers keep their previous expectations. Additional checks deny recovery quiet,
observe silent waiting, and repeat four faults in the same live cohort while
preserving the first RX loss record and monotonic source counter.

Its PHY wrapper supplies deserialized bytes and health, and its crop/context
boundary completes promptly. It does not prove electrical reception or actual TOP
quiet. WORD is 10 ns, PIX 14 ns, lane 0 is the least significant byte, RAW10 has four
native samples per 40-bit group, and transfer state advances on valid plus ready.

`physical` uses the actual official 8192-entry dual-clock FIFO, 8x2 crop from a
larger raster, router, guard, SOURCE fence and RAW formatter. It checks decoded
pixels and packed RAW bytes, independent held positive/negative SOURCE, queued FS,
lost terminal during a midraster PHY/FIFO/parser reset, real owner cleanup, repeated
runtime faults, quiet denial and exact per-owner retirement. WORD is 10 ns and PIX
13 ns. Recovery quiet includes source/router/RAW owner idle and crop/raw output
quiet; an extra test veto exercises the guard's quiet authority. This is a focused
chain, not the full production frontend or TOP.

The successful 2026-10-28 runs are under
`tmp/runtime_fix_20261028/validation/results/r02_*`: word 107+3 checks, strict word
107+3, receiver matrix 39 CASE records / 43 retirement-count checks, physical 5392
checks. All four runs have zero warnings and stable input hashes. The earlier
`r01_*` records preserve ModelSim's sandbox DLL startup failure; no RTL compiled
in those attempts.

Full TOP quiet, algorithm history reset, RT first-trigger recording, complete ISP
and JPEG products, synthesis, P&R, timing, bitgen and board qualification are
separate gates; these benches do not claim them.
