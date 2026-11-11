# Verified reference example — UART demo on PH1A60GEG324

A complete, working Anlogic TD project used to validate this skill end to end on
**TD 6.2.1 Engineer (build 6.2.168116)**. Use it as a known-good starting point
and as a regression test after changing any script in `scripts/`.

| File | Purpose |
|---|---|
| `top.v` | Top level: heartbeat LED + UART byte streamer |
| `uart_tx.v` | Parameterized 8N1 UART transmitter |
| `demo.adc` | Pin constraints (`LOCATION` + `IOSTANDARD`) |
| `demo.sdc` | Timing constraints (50 MHz clock, false paths) |
| `tb_uart_tx.v` | Self-checking behavioural testbench (verified PASS) |

## Target

| | |
|---|---|
| Family | `ph1` |
| Device (package) | `PH1A60GEG324` |
| Device db | `ph1_60.db` |
| Speed | `3` |
| Top module | `top` |

## Ports and pins

| Port | Dir | Pin | Standard |
|---|---|---|---|
| `i_clk` | in | `A10` (clock-capable, `gclkio0`) | LVCMOS33 |
| `i_rst_n` | in | `B11` | LVCMOS33 |
| `o_uart_tx` | out | `A13` | LVCMOS33 |
| `o_uart_busy` | out | `A14` | LVCMOS33 |
| `o_led` | out | `A15` | LVCMOS33 |

`A10` is taken from `query_current_package -clock_io` — use a clock-capable pad
for any clock input. See `references/device-pins-ph1a60geg324.md`.

## Run it

```powershell
# Full project flow: create -> synth -> P&R -> bitstream -> reports -> netlist+SDF
python <skill>/scripts/run_td.py <skill>/scripts/flow_full.tcl --workdir <workspace>
```

`flow_full.tcl` defaults point at this example. To relocate it, override the
CONFIG block variables (`HDL_FILES`, `ADC_FILES`, `SDC_FILES`, `PROJECT_DIR`).

Stepwise (non-project) variant, which drives every stage explicitly:

```powershell
python <skill>/scripts/run_td.py <skill>/scripts/flow_single_run.tcl --workdir <workspace>
```

Both were verified to produce identical timing results.

## Verified results

Both the project-mode and the stepwise non-project flow produced:

```
Device              : PH1A60GEG324
Speed               : 3
STA coverage        : 100.00%
Confidence          : Routed
	SWNS: 15.447ns, STNS: 0.000ns     <- setup met
	HWNS:  0.170ns, HTNS: 0.000ns     <- hold met
```

```
| QoR metrics               |         value               |
|     Setup WNS             |        15447                |   (picoseconds -> 15.447 ns)
|     Setup TNS             |            0                |
|     Num of violated S-EP  |            0                |
|     Hold WNS              |          170                |
|     Hold TNS              |            0                |
|     Num of violated H-EP  |            0                |
|     Wire length           |        11248                |
|     #slices               |           82  (0.21%)       |
|     #RAMs / #DSPs         |            0 / 0            |
```

Artifacts produced:

| Artifact | Size | Notes |
|---|---|---|
| `<proj>_Runs/phy_1/<proj>.bit` | ~2.8 MB | Bitstream |
| `<proj>_Runs/best_result/<proj>.bit` | ~2.8 MB | `save_best_bits` copy |
| `reports/final.timing` | ~119 KB | `report_timing_summary` |
| `reports/final.qor` | ~1.3 KB | **QoR metrics are in picoseconds** |
| `reports/post_route.v` | ~78 KB | Routed netlist for simulation |
| `reports/post_route.sdf` | ~86 KB | Real back-annotation (SDF 3.0, timescale 1ps) |

The `.bit` is ~2.8 MB even though the device holds far less, because the file is
uncompressed — this is normal, not a sign of a wrong device.

## Simulation results

All three simulation levels were run and pass:

| Level | Result | Evidence |
|---|---|---|
| Behavioural (RTL) | PASS | Frames `0x41/0x55/0x00/0xFF` decoded, 0 bit errors |
| Post-route functional | PASS | Frames `0x42` 'B', `0x43` 'C' decoded from the routed netlist |
| Post-route timing (+SDF) | PASS | `Loading timing data from …post_route.sdf`, 0 errors |

```powershell
# behaviour, no device libraries needed
vsim -c -do "set SRC <here>; do <skill>/scripts/sim_behavioral.do"

# post-route, functional + SDF-annotated timing
<skill>/scripts/sim_postroute.ps1 -Netlist reports/post_route.v `
                                  -Sdf reports/post_route.sdf `
                                  -Tb <a post-route testbench> -WorkDir <scratch>
```

## Notes learned from this example

- `QoR` values are **picoseconds**: `Setup WNS 15447` is the same number as
  `SWNS: 15.447ns` in the timing report.
- The bitstream lands in `phy_1/`, and `save_best_bits` copies it to
  `best_result/`. Read it from `phy_1/` if you never called `save_best_bits`.
- `write_sdf` only produces a useful file when the **routed** run is open. With
  `syn_1` open it silently writes a 0-byte file.
- A `PRJ-7003 ... Device speed "3" is invalid ... auto change to default`
  warning appears during `create_project` but is harmless here — the `.al` still
  records `<Speed>3</Speed>` and the flow completes.
