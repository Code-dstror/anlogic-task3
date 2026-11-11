# Four-band F23 focused checks

The existing `stage3_lane_candidates_terminal4` already contains the requested
four-band path. These tests require `FULLHEIGHT_ROI_ENABLE=0`; production RTL is
not rewritten. Each case is checked against a scalar rectangle/list oracle,
including all 1356 record bits. Full 480×270 cases exercise both `MONO_PRESET=0`
and the narrowed `MONO_PRESET=1` implementation. Generic small cases retain
configurable geometry and tail keeps. No TD/vendor models are needed.

```powershell
& 'python' -B `
  refactor/hdr_lane4/src_fpga/simulation/lane4/core_run.py `
  --modelsim-bin D:/App/modelsim/win64 --name fourband_check
```

Use a fresh run name. The runner records commands and source/fixture SHA256 in
`tmp/lane4_core/<name>/qualification.json`; compile/run reject warnings, errors
and missing PASS markers. This is functional evidence only: synthesis, P&R,
physical timing and board qualification are NOT_RUN by this runner.

Coverage includes all eight side statistics, row transitions 66/67, 134/135,
201/202 and final row269, x239/240, equal-strength raster ties, dense maximum
2040 L1 magnitude (`gx=gy=1020`), negative gradients, flat-image rejection,
ratios0–3/signs0–2, exact threshold/gx/ratio boundaries, atomic configuration,
127-cycle result stalls, consume/refill, dropped reports, bad configuration,
numeric/context/keep/marker/coordinate errors, missing/extra EOF, source error,
foreign terminal, reset/cancel, interrupted START and subsequent recovery.
Dense input has 32400 consecutive four-pixel events; its matching completion is
the next edge. Coincident final EOF and source completion must return error7.
Count thresholds16320 and16384 verify valid/paired decisions without truncation.

For each production side, at most240×68=16320 samples fit14 count bits. The
largest native-x sum is the right-side sum
`68 * 4 * sum(range(240,480)) = 23,468,160`, fitting26 bits. Maximum strength is
`16320 * 2040 = 33,292,800 < 2^25`, leaving261632 below the 25-bit modulus.
Eight MONO accumulators declare816 state bits (14+26+25+11+13+13 per side),
compared with952 generic bits; the independently held record declares1356 bits.
These are RTL declarations, not mapped LUT/FF or physical resource results.

One existing generic control limitation is explicitly emitted in the log:
simultaneous old-frame finish and new START snapshots the correct old sparse
record, but `terminal_identity` follows the newly locked context. This task does
not alter that behavior. It is only safe to treat the terminal identity as an
old-frame result when admission excludes that overlap; production integration
must verify that condition separately. The standalone generic interface does
not provide that exclusion itself.
