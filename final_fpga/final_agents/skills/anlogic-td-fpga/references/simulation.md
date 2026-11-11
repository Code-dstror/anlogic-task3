# Simulation with Anlogic TD

For new Codex tasks use TD **6.2.3.210850** models from
`C:/Tools/Anlogic/TD_2026.2`: pass the explicit new `-TdRoot` or `--td-root`
to TD-model simulation runners and keep compilation outputs separate per version.

The measured command counts and library experiments below are from TD
6.2.168116. For Release 2026.2, see [td2026-2.md](td2026-2.md): recompile the
selected version's models into separate outputs and retain SDF warnings.

## Does TD have a built-in simulator?

**No.** TD ships simulation *model sources*, not a simulator and not pre-compiled
libraries. A third-party simulator is mandatory for cycle-accurate functional or
timing simulation.

This was confirmed three ways: there is no simulation engine in `<TD_ROOT>\bin\`
(`td.exe`, `run.exe`, `bw.exe`, `IpTool.exe`, … and no `vsim`/`vlog`/`vlib`); none
of TD's **740** TCL commands compiles libraries or runs a simulation; and the
simulation settings (`simulator`, `simulator_location`) are GUI-only project
properties — `get_param design simulator_location` errors.

TD's supported third-party simulators (SWUG107 Table 2-1) are:

| Simulator | Supported versions |
|---|---|
| Mentor Graphics ModelSim Simulator | 2020 |
| Mentor Graphics Questa Advanced Simulator | 2020 |
| Synopsys VCS | 2020, 2018 (file list only — not integrated into the TD GUI) |

ModelSim and Questa are the only ones integrated with the TD GUI. VCS is
supported only in the sense that TD can emit a `.f` file list for it.

So: **yes, Anlogic simulation on this machine depends on ModelSim** (ModelSim
SE-64 2020.4, installed at `C:/Tools/ModelSim`). If ModelSim is unavailable you can
still elaborate plain RTL with any Verilog simulator, but you cannot simulate the
vendor primitives (`PH1_PHY_*`, `AL_MAP_*`, …) that TD's netlists instantiate.

Check what is actually installed before promising a simulation:

```powershell
Get-Command vsim, vlog, vlib, vmap -ErrorAction SilentlyContinue
```

### TD cannot launch the simulator for you, and cannot compile the libraries

- **TD TCL cannot compile device libraries.** `td_commands_prompt.exe` rejects
  `-simulator` / `-family` / `-dir` / `-simulator_exec_path`. The *Simulation
  Libraries Compiler* is GUI-only inside `td.exe`; its verbatim command template
  (recovered from the binary) is just:
  `vlib work`, `vmap %1`, `vlog %1/common/*.*v`, `vlog %1/common/apm/*.*v`,
  `vlog %1/%2/*.*v`, run through `<modelsim.exe> -c -do <dofile>` with library
  names `common` and `PH1`. You can reproduce this headlessly yourself.
- **TD TCL cannot launch ModelSim.** There is no `simulate`/`launch_simulation`
  command; the GUI does it with a child process. **The agent must drive ModelSim
  directly.** Conveniently `vlib`/`vmap`/`vlog`/`vsim`/`run`/`add` all exist
  inside vsim's own Tcl shell, so a single `vsim -c -do x.do` can compile *and*
  run, exactly as the TD GUI does.

## Simulation stages

TD defines four simulation points, each corresponding to a flow stage:

| Stage | Available after | What it simulates |
|---|---|---|
| Behavioral | `read_design` (RTL only) | Your source RTL, pre-synthesis |
| Post-RTL | `optimize_rtl` | Netlist after RTL optimisation |
| Post-Gate | `optimize_gate` | Netlist mapped to device primitives |
| Post-Route | `optimize_route` | Placed & routed netlist; functional, or timing with SDF |

In TCL terms: run the flow, `open_run <run>`, then `write_verilog` / `write_sdf`.

## Getting a netlist and SDF out of TD

Do this **in the same TD process that built the design** — see the crash note
below.

```tcl
# ... create_project / add_files / launch_runs syn_1 / wait_run / launch_runs phy_1 / wait_run ...
open_run phy_1
write_verilog  $OUT/post_route.v
write_sdf -file $OUT/post_route.sdf      ;# needs the ROUTED run open
close_run
```

Verified output for the reference example:

- `post_route.v` ~78 KB, top module `top`, ports `i_clk i_rst_n o_led o_uart_busy o_uart_tx`
- `post_route.sdf` ~86 KB, header:
  `(SDFVERSION "3.0") (DESIGN "top") (VENDOR "Anlogic") (TIMESCALE 1ps)`
  with real `INTERCONNECT` delays and `SETUPHOLD`/`RECREM` cell timing.

`flow_full.tcl` does this automatically (`GEN_NETLIST`, default on).

### Two traps

1. **`write_sdf` with `syn_1` open writes a 0-byte file, silently.** It only
   produces useful back-annotation from the routed run. Always check
   `[file size $sdf] > 0` before using it. (With the gate run open it can also
   crash the process.)
2. **`open_project` without a preceding `import_device` poisons a later
   `open_run`.** On a project not built in this process, `open_run phy_1` then
   crashes TD with an access violation (`Oops! coredump`, exit `3221225477`, a
   `minidump-*.dmp`). `open_run syn_1` survives, which makes it look like a
   routed-db bug. Fix:

   ```tcl
   import_device ph1_60.db -package PH1A60GEG324 -speed 3
   open_project E:/work/demo.al -noanalyze
   open_run phy_1          ;# now works in a fresh process
   ```

   The simplest policy is still build → open → export in one script; the
   `import_device` line is what makes a separate process viable.

### `write_sdf` corner selection

`-check_corner` accepts **only** `slow`, `fast`, `SLOW`, `FAST`, `slow_fast`.
Anything else (`max`, `min`, `typ`, `worst`, `nominal`) fails with
`TMR-8023 Invalid param`. Default is `slow`. Example: a routed logic design gave
86,310 B for `slow` and 85,536 B for `fast`.

## Post-route simulation: the minimal library set

Verified working: a **post-route functional and timing simulation** of the
reference design completed with `Errors: 0` and correct UART frames. Exactly
**9** files are needed for a PH1 logic design:

| File | Why |
|---|---|
| `common/al_phy_glbl.v` | provides `glbl` |
| `ph1/ph1_phy_lslice.v` | slice primitive |
| `ph1/ph1_phy_pad.v` | I/O pad primitive |
| `ph1/ph1_phy_gclk_v2.v` | global clock |
| `ph1/ph1_phy_sclk_v2.v` | secondary clock (encrypted) |
| `ph1/ph1_phy_hr_bankref.v` | bank reference (encrypted) |
| `ph1/ph1_logic_io.v` | `PH1_LOGIC_IDDR`/`ODDR`, needed *by* `ph1_phy_pad.v` |
| `ph1/ph1_phy_gsr.v` | global set/reset |
| `ph1/ph1_phy_config_v2.sv` | **compile with `-sv`** |

Minimality was proven by omission — removing any file produces
`Module 'X' is not defined` naming the missing module. Notes:

- `ph1_phy_hp_pad.v` is **not** required for ordinary logic designs.
- The models are IEEE-1735 pragma-protect encrypted; ModelSim decrypts them
  natively.
- The testbench must instantiate the global reset: `PH1_PHY_GSR PH1_PHY_GSR();`
- Post-Gate (`post_rtl.v` from `write_verilog` at `optimize_gate`) additionally
  needs `common/al_map_lut.v` and `common/al_map_seq.v`.
- Post-RTL (`write_verilog`/`generate_simulation` at the RTL stage) needs only
  `common/al_phy_glbl.v`, `common/al_map_basic.v`, `ph1/ph1_phy_gsr.v`.
- Do **not** compile all of `sim_release/ph1/*` "to be safe" — the directory is
  ~1.4 GB (`serdes_dual` alone is 341 MB, `ddr4_cal` 183 MB). SerDes/DDR/PCIe/DSP
  designs need the matching extra files added to the list above.
- Warning counts in the thousands are benign here: `vsim-3722` (optional
  `CONFIG_V2` ports), `vsim-3016` (`LSLICE` port type), and `vsim-3448`
  (negative SDF check limits around −61 ps).

Working invocation, including SDF annotation (note `-sdftyp`, which is what
actually works — `-sdf max:...` is not required):

```powershell
& "$MS\vlog.exe" -timescale 1ns/1ps -incr -f postroute.f
& "$MS\vlog.exe" -timescale 1ns/1ps -incr -sv "$TD\sim_release\ph1\ph1_phy_config_v2.sv"
& "$MS\vsim.exe" -c -sdftyp "/postroute_tb/dut=<abs path>/post_route.sdf" `
      -l postroute_timing.log -do "$DO\postroute_timing_run.do" work.postroute_tb
```

A successful run logs `Loading timing data from ...post_route.sdf`, and a delay
shift appears in the waveform (in the verified run the start-bit edge moved from
20,971,950 ns to 20,971,938 ns). `-y`/`+libext+` are **not** needed — an explicit
file list is enough.

`scripts/sim_postroute.ps1` packages all of the above — it locates TD, compiles
the nine models (with `-sv` for the config file), then runs both the functional
and the SDF-annotated timing simulation and greps the verdict:

```powershell
$env:TD_ROOT = "C:/Tools/Anlogic/TD_6.2.168116"
.\scripts\sim_postroute.ps1 -Netlist <dir>\post_route.v `
                            -Sdf     <dir>\post_route.sdf `
                            -Tb      <dir>\tb_postroute.v `
                            -WorkDir <scratch>
```

Verified output from that script against the reference design:

```
=== vsim: timing (SDF annotated) ===
# [TB] FRAME 1 : o_uart_tx = 0x42 = 'B'   [start=0 d0..d7=01000010 stop=1]
# [TB] FRAME 2 : o_uart_tx = 0x43 = 'C'   [start=0 d0..d7=11000010 stop=1]
# [TB] RESULT: PASS - 2 UART 8N1 frames on o_uart_tx are well framed (post-route netlist)
# Errors: 0, Warnings: 2767
# Loading timing data from ...post_route.sdf
```

## Every stage was verified

| Simulation | Result | Evidence |
|---|---|---|
| Behavioural (RTL) | PASS | Frames `0x42` 'B', `0x43` 'C' decoded; `Errors: 0` |
| Post-route functional | PASS | Same frames decoded from the routed netlist |
| Post-route timing (+SDF) | PASS | `Loading timing data from …post_route.sdf`; edge shifted by the annotated delay |

## Device simulation libraries

TD ships model sources under `<TD_ROOT>\sim_release\`:

| Family | Directory | Global-reset model |
|---|---|---|
| shared | `common` | `al_phy_glbl.v` |
| PH1A / PH1P | `ph1` / `ph1p` | `PH1_PHY_GSR` / `PH1P_PHY_GSR` |
| PH2A | `ph2` | `PH2_PHY_GSR` |
| EF2 / EF3 / EF4 | `ef2` / `ef3` / `ef4` | `glbl` |
| EG4 | `eg4` | `glbl` |
| SF1 / SF2 | `sf1` / `sf2` | `glbl` |
| DR1 | `dr1` | `glbl` |

Files are named `<family>_logic_*.v`, `<family>_phy_*.v`, plus shared
`al_map_*.v` / `al_logic_*.v` in `common`.

Notes:

- `PH1A` and `PH1P` share the `ph1` `create_project` family but need **different**
  `sim_release` directories (`ph1` vs `ph1p`).
- The GUI's *Simulation Libraries Compiler* (Tools menu) does this compilation
  for you against ModelSim/Questa and writes a compiled library directory. It is
  a GUI tool; there is no documented TCL equivalent.
- No user-instantiable `GSR`/`STARTUP` primitive exists. `*_PHY_GSR` are
  zero-port, simulation-only cells.

## Testbench requirements

1. Add `` `timescale `` (e.g. `` `timescale 1ns/1ps ``).
2. Drive **all** inputs to a defined value at time 0.
3. Start clock sources **after** global reset (GSR) is released.
4. If the design (or a post-synthesis netlist) uses device primitives, instantiate
   the family global-reset model — `PH1_PHY_GSR` for PH1, `PH2_PHY_GSR` for PH2,
   `glbl` for EF2/EF3/EF4/EG4/SF1/SF2/DR1.

## Driving ModelSim headlessly

ModelSim SE-64 2020.4 executables live in `C:/Tools/ModelSim/win64`.

**Verified working behavioural run** (this exact sequence was executed and
returned `RESULT: PASS - all UART frames correct`, `Errors: 0`):

```powershell
$MS = "C:/Tools/ModelSim/win64"
$SRC = "<skill>\examples\uart_demo"

& "$MS\vlib.exe" work
& "$MS\vmap.exe" work work
& "$MS\vlog.exe" -timescale 1ns/1ps "$SRC\uart_tx.v" "$SRC\tb_uart_tx.v"
& "$MS\vsim.exe" -c -work work tb_top -do "run -all; quit -f"
```

Or drive it from a `.do` script (shipped as `scripts/sim_behavioral.do`):

```powershell
& "$MS\vsim.exe" -c -do "set SRC $SRC; do <skill>/scripts/sim_behavioral.do"
```

Rules learned the hard way:

- **`-c` is mandatory** for scripted/agent use; without it you get the GUI.
- **Never pass `-novopt` on 2020.4.** It is deprecated and `vsim` aborts with
  `(vsim-12110) ... -novopt option is now deprecated` followed by
  `Error loading design`. Plenty of older Anlogic example scripts (including
  TD's own shipped `cmd.do`) still contain it — strip it.
- `-do "run -all; quit -f"` is what makes the run terminate instead of hanging.
- Add `-L <compiled_lib_dir>` to point at TD device libraries, or compile the
  `sim_release` sources into your own library first.
- For timing simulation, annotate the SDF, e.g.
  `vsim -c -sdf max:/tb_top/dut=<file>.sdf -work work tb_top` (or a `-sdftyp`
  form); verify the exact switch against your ModelSim version.

TD's own shipped example (`<TD_ROOT>\board_designs\ANLOGIC\AP102\LED_AP102\sim\cmd.do`)
shows the intended shape — but note it uses `-gui` and `-novopt`, both of which
must change for headless 2020.4 use:

```tcl
vlib work
vmap work work
vlog -timescale 1ps/1ps -sv -f compile.f
vsim -L <compiled_device_lib> -gui -novopt work.<tb_top>
add wave *
run 1000ns
```

## A working testbench to copy

`examples/uart_demo/tb_uart_tx.v` in this skill is a verified self-checking
testbench. It compiles standalone (no device libraries), drives a UART frame,
samples each bit at its centre, and prints a machine-greppable verdict:

```
# --- sending 0x41 (01000001), LSB first
# ok   start = 0
# ok   data = 1
...
# RESULT: PASS - all UART frames correct
```

Grep for `RESULT:` to get a pass/fail verdict from a script. Use it as the model
for new testbenches: self-checking, prints an explicit `RESULT:` line, and has a
safety timeout so a hang cannot stall an agent forever.

## Practical guidance

- **Behavioural simulation is cheap and worth doing first.** It needs no device
  libraries at all — just your RTL and a testbench.
- **Post-route timing simulation is expensive and fragile.** It needs the full
  device primitive models plus a valid SDF, and vendor primitive models are often
  not simulator-clean. If static timing analysis reports positive slack with
  `Confidence: Routed` and 100% STA coverage, timing closure is already evidenced
  without a gate-level simulation.
- Prefer `report_timing_summary` (§7 of SKILL.md) as the primary timing evidence,
  and use timing simulation to investigate a specific suspected path.
