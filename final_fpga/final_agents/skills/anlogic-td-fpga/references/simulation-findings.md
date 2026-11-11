# Anlogic TD 6.2.1 design-simulation flow — empirical findings

All commands below were executed and their output captured; every claim has a log or
exit code behind it. Workspace scratch root: `C:/Work/td-example\sim\`.

Environment
- TD: `C:/Tools/Anlogic/TD_6.2.168116` (build 6.2.168116, `td_commands_prompt.exe` = TCL batch shell, Tcl 8.6.15, **740** commands)
- ModelSim: `C:/Tools/ModelSim/win64` — `ModelSim SE-64 vsim 2020.4` (2020.10 Oct 13 2020)
- Design: `demo.al`, top `top`, `ph1_60.db -package PH1A60GEG324 -speed 3`, routed (bitstream generated)

---

## 1. Can TD's TCL compile the device simulation libraries?  **NO.**

- `info commands` (740 commands) filtered for `sim|lib|compile|questa|modelsim`:
  **no** `vlib/vlog/vcom/vsim`, no `compile_simlib`, no `modelsim`/`questa` command.
  Only `process_vlog_files` merely contains the substring "vlog".
- The only sim-ish commands are: `generate_simulation`, `generate_gate`, `generate_serdes`
  (IP/SerDes model generators), `write_verilog`, `write_sdf`, `optimize_gate -macrosim/-mapsim/-packsim`.
- `td_commands_prompt.exe` does **not** accept the library-compiler CLI options: passing
  `-simulator modelsim -family PH1 -dir {...} -simulator_exec_path {...}` yields
  `wrong # args: should be "source ?-encoding name? fileName"` — the first argument is treated as a TCL script file.
- TD's library compiler lives **inside the Qt GUI (`td.exe`)**. Strings extracted from `td.exe`
  (`strings` dump: `sim\td_exe_strings.txt`, anchored at line 97459) give the *verbatim template*
  the GUI writes and then executes as `<modelsim.exe> -c -do <dofile>`:

```
# Create work library
vlib work
# Include path
set %1 %2
# compiled simulation library
vmap %1
# sim_release file path
vlog %1/common/*.*v
vlog %1/common/apm/*.*v
vlog %1/%2/*.*v
```

  Related GUI strings: `compile_simlib%1%2%3%4%5%6`, ` -simulator modelsim`, ` -simulator questasim`,
  ` -family %1`, ` -dir {%1}`, ` -simulator_exec_path {%1}`, `%1 -c -do `, `%1/anlogic_lib`,
  `Simulation Libraries Compiler`, `simulator_location`, `flow_sim_filelist`, `$TD_PATH`, `/sim_release`.

**Headless equivalent (verified, exit 0):** run ModelSim's own `vlib/vmap/vlog` over the
`sim_release` sources — see `build_libs.ps1` and §3.

## 2. Can TD's TCL generate the per-stage sim netlists?  **YES — verified for all stages.**

| Stage | How to produce it (headless) | Primitive set in the netlist |
|---|---|---|
| Elaborated/RTL | `import_db <run>/<prj>_elaborate.db; write_verilog x.v` | `AL_DFF_W/AL_DFF_X/AL_MUX/glbl` |
| **Post-RTL** | `import_db <run>/<prj>_rtl.db; write_verilog x.v` → `post_rtl_stage.v` | `AL_DFF_X/AL_FADD/AL_MUX/glbl` |
| **Post-Gate** | `open_run syn_1; write_verilog x.v` → `post_rtl.v` (identical to `optimize_gate -packsim x.v`) | `AL_MAP_LUT1..6, AL_MAP_SEQ_GSR, PH1_PHY_LSLICE, PH1_PHY_PAD, PH1_PHY_CONFIG_V2, glbl` |
| **Post-Route** | `open_run phy_1; write_verilog x.v; write_sdf -file x.sdf` | `PH1_PHY_LSLICE, PH1_PHY_PAD, PH1_PHY_CONFIG_V2, PH1_PHY_GCLK_V2, PH1_PHY_SCLK_V2, PH1_PHY_HR_BANKREF, glbl` |

`optimize_gate -macrosim/-mapsim/-packsim` also emits sim netlists directly (verified, exit 0):
`opt_macrosim.v` (78,665 B), `opt_mapsim.v` (52,465 B), `opt_packsim.v` (74,085 B).

`write_sdf` details: only valid with the **routed** run open; a gate-stage DB crashes the process.
`-check_corner` accepts **`slow`|`fast`|`SLOW`|`FAST`|`slow_fast`** only
(`min/typ/max/typical/worst/best/nominal` → `TMR-8023 ERROR: Invalid param ...`).
Default = slow (86,310 B); `fast` = 85,536 B. Output header: `(SDFVERSION "3.0")(DESIGN "top")(VENDOR "Anlogic")(TIMESCALE 1ps)`.

## 3. The routed-DB crash in a fresh process — reproduced AND worked around

- Reproduced: fresh `td_commands_prompt.exe` → `open_project demo.al` → `open_run phy_1`
  → `Oops! coredump minidump-20260911-212955.dmp`, exit `-1073741819` (0xC0000005).
- **Workaround (no single-process requirement):** call `import_device` *before* opening:
```tcl
import_device ph1_60.db -package PH1A60GEG324 -speed 3
open_project C:/Work/td-example/tdtest/demo.al -noanalyze
import_db     C:/Work/td-example/tdtest/demo_Runs/phy_1/demo_pr.db   ;# or: open_run phy_1
write_verilog C:/Work/td-example/sim/post_route.v
write_sdf -file C:/Work/td-example/sim/post_route.sdf
```
  Verified in a *separate fresh process* from the build: exit 0, `post_route.v` 78,316 B,
  `post_route.sdf` 86,310 B (byte-identical size to the parent's artifact). Same for
  `open_run phy_1` (`netlist_route3.tcl`, exit 0). So the crash is specifically
  "open_project without import_device, then import the routed DB" — the device/arch import
  (`import_device`) must come first.

## 4. Does TD simulation REQUIRE ModelSim?  **YES for PH1 (a third-party simulator is mandatory; there is no built-in simulator).**

Doc evidence (`SWUG107_Design_Simulation_User_Guide.txt`):
- §2.2 Table 2-1: supported simulators per device library = *Mentor Graphics ModelSim Simulator 2020*,
  *Questa Advanced Simulation 2020*, *Synopsys VCS 2020/2018*.
- §2.2 note: "第三方仿真工具 ... 已关联到TD设计环境中 ... VCS 暂未关联TD."
- §4.2: "TD 软件提供仿真模型作为库文件，在设计仿真之前用户需要应用第三方仿真工具编译这些文件"
  (TD ships the models as *source* libraries; the user must compile them with a third-party simulator).
- §5 Table 5-1: Windows 10 64-bit → ModelSim 是, Questa 是, VCS 不支持.
- §4.1: the project must be pointed at a `simulator` + `simulator_location` (an external executable).

Empirical evidence:
- `bin/` contains no simulator/waveform engine (`td.exe`, `run.exe`, `td_commands_prompt.exe`, IP tools only).
- The 740 TCL commands contain no simulate/run-simulation entry point.
- `get_param design simulator|simulator_location|flow_sim_filelist` → errors: the sim settings are
  GUI-only project properties, not TCL parameters.
- `td.exe` strings show the Simulator combobox is hardcoded to `ModelSim` / `Questasim`
  and the run is executed as `<simulator_exe> -c -do <dofile>`.
- A waveform could only be produced by running ModelSim.

## 5. Can TD launch ModelSim headlessly?  **NO — not from TCL. The agent must drive ModelSim itself.**

- No `simulate`/`launch_simulation`/`run_simulation`/`modelsim`/`questa` TCL command exists.
- `td.exe` (GUI) launches it via QProcess (`The Run Simulation Files process has been launched.`)
  using `<simulator_exe> -c -do <dofile>`; that path is unreachable from `td_commands_prompt.exe`.
- `vlib`, `vmap`, `vlog`, `vcom`, `vsim`, `run`, `add` ARE available **inside** ModelSim's own TCL shell
  (`vsim -c -do script.do` can therefore do compile+run in one invocation, exactly like TD's GUI).

---

## EXACT WORKING COMMAND LINES

### A. Compile the device simulation libraries (headless "Simulation Libraries Compiler")
The relevant PH1 file set is small; TD itself would compile all of `common` + `ph1/*.*v`
(~1.4 GB of encrypted SerDes/DDR/PCIe models) — unnecessary for a logic design.
```powershell
$MS="C:/Tools/ModelSim/win64"; $SR="C:/Tools/Anlogic/TD_6.2.168116\sim_release"
$LIB="C:/Work/td-example\sim\anlogic_lib"
& "$MS\vlog.exe" -work "$LIB\common" -quiet $SR\common\*.v $SR\common\apm\*.v
& "$MS\vlog.exe" -work "$LIB\PH1" -quiet `
    $SR\ph1\ph1_phy_lslice.v $SR\ph1\ph1_phy_pad.v $SR\ph1\ph1_phy_gclk_v2.v `
    $SR\ph1\ph1_phy_sclk_v2.v $SR\ph1\ph1_phy_hr_bankref.v $SR\ph1\ph1_logic_io.v $SR\ph1\ph1_phy_gsr.v
& "$MS\vlog.exe" -work "$LIB\PH1" -sv -quiet $SR\ph1\ph1_phy_config_v2.sv
```
Library *names* are `common` and `PH1` (that is what TD's generated `-L common -L PH1` refers to).
Note: `sim_release` models are IEEE-1735 `pragma protect` encrypted; ModelSim decrypts them
(the `Mentor Graphics Corporation` key owner is present). Fully encrypted files
(`ph1_phy_sclk_v2.v`, `ph1_phy_hr_bankref.v`) compile but show as `PROTECTED DU <hash>` in `vdir`.

### B. Behavioral (RTL) simulation — PASS
```powershell
$MS="C:/Tools/ModelSim/win64"; $S="C:/Work/td-example\sim"
Set-Location "$S\behav"; & "$MS\vlib.exe" work; & "$MS\vmap.exe" work work
& "$MS\vlog.exe" -timescale 1ns/1ps -incr -sv -f "$S\f\behav.f"
& "$MS\vsim.exe" -c -l behav_vsim.log -do "$S\do\behav_run.do" work.demo_tb
```
`f\behav.f` = `demo\top.v`, `demo\uart_tx.v`, `sim\tb\demo_tb.v`.
Evidence: `FRAME 1 = 0x42 'B'  [start=0 d0..d7=01000010 stop=1]`, `FRAME 2 = 0x43 'C'`,
`RESULT: PASS - 2 UART 8N1 frames`, finished t=42,030,270 ns (~2.8 s wall).

### C. Post-route simulation (device sources compiled from sim_release) — PASS, functional + timing
```powershell
Set-Location "$S\postroute"; & "$MS\vlib.exe" work; & "$MS\vmap.exe" work work
& "$MS\vlog.exe" -timescale 1ns/1ps -incr -f "$S\f\postroute.f"
& "$MS\vlog.exe" -timescale 1ns/1ps -incr -sv <TD>\sim_release\ph1\ph1_phy_config_v2.sv
# functional
& "$MS\vsim.exe" -c -l postroute_func.log -do "$S\do\postroute_run.do" work.postroute_tb
# timing, SDF back-annotated
& "$MS\vsim.exe" -c -sdftyp "/postroute_tb/dut=$S/post_route.sdf" -l postroute_timing.log `
    -do "$S\do\postroute_timing_run.do" work.postroute_tb
```
Timing evidence: `Loading instances from ... post_route.sdf`, `Loading timing data from ... post_route.sdf`,
`Errors: 0`, start-bit edge moves 20,971,950 ns → 20,971,938 ns vs functional (delays really applied),
and the same correct frames `0x42 'B'` / `0x43 'C'`, `RESULT: PASS`.

### D. TD-canonical one-shot form (mirrors TD's own generated .do) — PASS
```powershell
Set-Location "$S\td_style_run"
& "$MS\vsim.exe" -c -l td_style.log -do "$S\do\td_style_postroute.do"     # 495 s
```
`do\td_style_postroute.do` does: `vlib work; vmap work work; vmap common <lib>/common; vmap PH1 <lib>/PH1;
vlog -work work post_route.v tb/postroute_tb.v;
vsim -t ps -voptargs="+acc" -L common -L PH1 -sdftyp /postroute_tb/dut=<sdf> work.postroute_tb; add wave *; run -all`
→ `RESULT: PASS`, SDF loaded, `Errors: 0`.

### E. SDF option forms in ModelSim 2020.4
`-sdftyp /postroute_tb/dut=<sdf>` works (this is TD's own `-sdftyp u_dut=<sdf>` form; TD names its
generated DUT instance `u_dut`). `-sdf max:/dut=<sdf>` was not needed.

---

## EXACT sim_release FILE LIST PER STAGE (verified by omission: the minimal set was confirmed by
deliberately compiling a reduced set and reading the "Module 'X' is not defined" errors)

**Post-Route** (9 files; works with `post_route.v`):
```
sim_release/common/al_phy_glbl.v          -> glbl
sim_release/ph1/ph1_phy_lslice.v          -> PH1_PHY_LSLICE
sim_release/ph1/ph1_phy_pad.v             -> PH1_PHY_PAD
sim_release/ph1/ph1_phy_gclk_v2.v         -> PH1_PHY_GCLK_V2 (+NAND2/NAND4/NOT/ph1_gclk_csb_*)
sim_release/ph1/ph1_phy_sclk_v2.v         -> PH1_PHY_SCLK_V2   (fully encrypted)
sim_release/ph1/ph1_phy_hr_bankref.v      -> PH1_PHY_HR_BANKREF (fully encrypted)
sim_release/ph1/ph1_logic_io.v            -> PH1_LOGIC_IDDR/ODDR (needed by ph1_phy_pad.v)
sim_release/ph1/ph1_phy_gsr.v             -> PH1_PHY_GSR  (instantiated by the testbench)
sim_release/ph1/ph1_phy_config_v2.sv      -> PH1_PHY_CONFIG_V2  *** compile with -sv ***
```
`ph1_phy_hp_pad.v` is NOT required by this design (proven by elaborating without it).
Omission test errors: `PH1_PHY_GCLK_V2`, `PH1_PHY_SCLK_V2`, `PH1_LOGIC_IDDR/IDDRx2/ODDR/ODDRx2`
(from `ph1_phy_pad.v`), `PH1_PHY_HR_BANKREF`.

**Post-Gate** (`post_rtl.v`): `common/al_phy_glbl.v`, `common/al_map_lut.v`, `common/al_map_seq.v`,
`ph1/ph1_phy_lslice.v`, `ph1/ph1_phy_pad.v`, `ph1/ph1_logic_io.v`, `ph1/ph1_phy_gsr.v`,
`ph1/ph1_phy_config_v2.sv` (-sv). Verified: elaborate + run OK.

**Post-RTL** (`post_rtl_stage.v`): `common/al_phy_glbl.v`, `common/al_map_basic.v`, `ph1/ph1_phy_gsr.v`.
Verified: elaborate + run OK.

Flags that matter: `-timescale 1ns/1ps` (netlist + TB carry their own `timescale`),
`-sv` for `ph1_phy_config_v2.sv` only, `-incr` optional, `#` comments are accepted in `-f` files.
The testbench MUST instantiate the GSR primitive at TB level (`PH1_PHY_GSR PH1_PHY_GSR();` for PH1,
`PH2_PHY_GSR` for PH2, `glbl glbl();` for EF2/EF3/EF4/EG/SF1 — SWUG107 fig. 4-5); the netlist's
`glbl` block that reads `PH1_PHY_GSR.gsr` otherwise has no driver.

## Errors hit and how they were resolved
1. `open_run phy_1` in a fresh process → access violation + `minidump-*.dmp`. **Fixed** by
   `import_device ph1_60.db -package PH1A60GEG324 -speed 3` before `open_project` (§3).
2. `write_sdf` with the gate-stage run open → process crash, 0-byte SDF. **Fixed**: only write the SDF
   with the routed run open (`open_run phy_1` / `import_db <prj>_pr.db`).
3. `write_sdf -check_corner max` → `TMR-8023 Invalid param`. Valid: `slow|fast|SLOW|FAST|slow_fast`.
4. `Module 'PH1_PHY_CONFIG_V2' is not defined` → compile `ph1_phy_config_v2.sv` with `-sv`.
5. First post-route attempt used a real-delay UART decoder; timescale/`$timeformat` ambiguity
   (ModelSim's `%t` defaults to the 1 ps resolution while the module unit is 1 ns) made frame 2 decode
   as 0xE8. **Fixed** by clock-counted sampling (434 clk/bit for 115200 @ 50 MHz) and `$timeformat(-9,3," ns",15)`;
   the design is correct (0x42 → 0x43).
6. Non-fatal: 2,711 (functional) / 2,767 (timing) warnings — mostly `vsim-3722` missing optional
   `PH1_PHY_CONFIG_V2` ports, `vsim-3016` port-type mismatch on `PH1_PHY_LSLICE.ib`, and 54 `vsim-3448`
   "negative timing check limit (-61 ps) set to zero" from SDF SETUPHOLD. None affect the result.

## What does NOT work / open questions
- No TD TCL entry point for: library compilation, launching a simulator, or selecting
  simulator/`simulator_location`/`flow_sim_filelist` (GUI-only project properties).
- `generate_simulation` needs `-package` and then reports `USR-8001 ERROR: Can't get db_name option.`
  It is an IP/SerDes simulation-package generator, **not** the testbench/netlist generator
  (TD's TB text is a hardcoded template inside `td.exe`, extracted at strings line 97436).
- TD would compile **all** of `ph1/*.*v` (~1.4 GB incl. 341 MB `ph1_phy_serdes_dual.v`,
  183 MB `ph1_phy_ddr4_cal.v`, 176 MB `ph1_phy_pcie.sv`); only the subset above was verified.
  Designs that instantiate SerDes/DDR/PCIe/DSP hard macros will need the matching extra files.
- `open_run phy_1` without `import_device` remains a genuine TD bug in a fresh process.

## Artifacts (all absolute)
Netlists/SDF (from TD): `sim\post_route.v` (78,316 B), `sim\post_route.sdf` (86,310 B),
`sim\post_route_or.v|.sdf`, `sim\post_rtl.v` (post-gate), `sim\post_rtl_stage.v` (post-RTL),
`sim\post_elaborate.v`, `sim\opt_macrosim.v|opt_mapsim.v|opt_packsim.v`,
`sim\corner_slow.sdf` (86,310 B), `sim\corner_fast.sdf` (85,536 B).
TCL: `sim\netlist_gen.tcl`, `netlist_route.tcl`, `netlist_route2.tcl`, `netlist_route3.tcl`,
`netlist_rtl_stage.tcl`, `probe3_optgate.tcl`, `probe4_sdf_corner.tcl`, `probe_sim_cmds.tcl`,
`probe2_sim_settings.tcl` (+ `*_out.txt` logs).
ModelSim scripts: `sim\do\behav_run.do`, `behav_all.do`, `postroute_run.do`,
`postroute_timing_run.do`, `td_style_postroute.do`; filelists `sim\f\behav.f`, `sim\f\postroute.f`;
drivers `sim\run_all.ps1`, `sim\build_libs.ps1`, `sim\closure.ps1`.
Testbenches: `sim\tb\demo_tb.v` (behavioral), `sim\tb\postroute_tb.v` (netlist + `PH1_PHY_GSR`).
Evidence strings: `sim\td_exe_strings.txt` (TD GUI templates), `sim\probe*_out.txt`.
Logs: `sim\behav\behav_stdout.log`, `behav_vsim.log`;
`sim\postroute\postroute_func_stdout.log|postroute_func.log`,
`sim\postroute\postroute_timing_stdout.log|postroute_timing.log`;
`sim\td_style_run\td_style_stdout.log|td_style.log`.
