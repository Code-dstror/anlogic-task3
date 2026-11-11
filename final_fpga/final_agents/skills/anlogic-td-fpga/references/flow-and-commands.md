# Anlogic TD 6.2.1 — Flow & TCL Command Reference

Scope: all measured counts/defaults in this digest describe **6.2.168116**.
Codex's default for new tasks is **6.2.3.210850** at
`C:/Tools/Anlogic/TD_2026.2`; pass that `--td-root` explicitly.
For Release 2026.2 use [td2026-2.md](td2026-2.md) and the matching official manual;
in particular `logic_level_opt`, route timing and RAMOptimize changed.

The authoritative end-to-end command reference for driving Tang Dynasty V6.2.168116 from TCL.
Organised by flow stage, with exact argument syntax and copy-pasteable examples for every
command.

Primary sources:

| Source | Role |
|---|---|
| `<repo>/references/vendor/安路科技_TD_技术文档/SWUG/SWUG105_TCL_Command_User_Guide.pdf` (90 pp, 2024.11) | primary — command chapters 4.1–4.9, script-mode chapter 3, parameter tables 4-1/4-2 |
| live `info commands` (740 names) | **authoritative existence check** — regenerate with `'info commands' \| & '<root>\bin\td_commands_prompt.exe' -nogui`, or use the snapshot this file was verified against |
| `<repo>/references/vendor/安路科技_TD_技术文档/cmd/help_comment_phy.json`, `help_comment_opt.json` | the tool's own machine-readable option tables (ground truth for commands SWUG105 omits) |
| `<repo>/references/vendor/安路科技_TD_技术文档/scripts/DefaultFlow.tcl`, `MultiSeed.tcl`, `PRFlow.tcl`, `SynIpFlow.tcl` | the tool's own shipped flow scripts — ground truth for operational command sequences |
| a generated run's `settings.cfg` / `<project>.tcl` | the real per-run script and parameter file TD writes into `<project>_Runs/<run>/` |
| `<repo>/references/vendor/安路科技_TD_技术文档/strategies/official_strategy_ph{1,2}.json` | the built-in strategy packages (named bags of `set_param` triples) |
| `<repo>/references/vendor/安路科技_TD_技术文档/TD_User_Guide_V6.2.pdf` § 9.6, § 9.7 | parameter **effects** and the strategy-package catalogue |

> **Verification rule used throughout.** Every command named in this file was checked against
> `td_commands_all.txt`, which itself was verified complete (`info commands` returns exactly
> **740**). Commands in the live list but *not* documented by SWUG105 are marked **[LIVE-ONLY]**.
> Commands SWUG105 documents but which are **absent** from the live list are marked
> **[PHANTOM — DO NOT USE]**.
>
> **The parameter data in §4 is MEASURED, not transcribed.** TD 6.2.1 was driven directly
> (`td_commands_prompt.exe -nogui <script>`) against a real project, and `report_param -detail`
> was used to enumerate the true parameter database — corroborated by the tool's own
> `demo_Runs\{syn_1,phy_1}\run.log`. **Where SWUG105's tables disagree with the measurements,
> this file follows the measurements and says so.** The single most important consequence is in
> §4.5: **`set_param` validates nothing at all.**
>
> **Extraction warnings.** SWUG105 Tables 4-1/4-2 (the `set_param` tables) extracted as a flat
> one-cell-per-line dump with all row boundaries lost. They were re-paired positionally and are
> reproduced in §4.4/§4.10 marked `[RECONSTRUCTED TABLE]`. The per-parameter *effects* are not in
> SWUG105 at all — §4.2.2 explicitly delegates to "TD User Guide chapter 9.6", which is where the
> effect text in §5 comes from.

---

## 1. The TD TCL command model

### 1.1 Entry points

| Entry point | Platform | How |
|---|---|---|
| GUI Console | Windows / Linux | type TCL commands into the TD Console pane |
| `td_commands_prompt` | Windows | `Start → All Programs → td_commands_prompt`, or directly `"<root>\bin\td_commands_prompt.exe" -nogui` |
| `td.sh` | Linux | `<td_install_dir>/td.sh` starts command mode |
| `td.sh <script>` | Linux | `<td_install_dir>/td.sh demo.tcl` starts command mode **and** runs the script |

`<root>` = the selected TD install directory; for new Codex tasks use
`C:/Tools/Anlogic/TD_2026.2`. The measurements below retain their old-version scope.

Notes verified against the real install:

* `td_commands_prompt.exe` **accepts a TCL file as a positional argument**:
  `td_commands_prompt.exe -nogui <script.tcl>` runs the script headless. (Verified live; the flag
  order `<exe> -nogui <file>` works.)
* The token `td -nogui` is **not** documented anywhere in SWUG105 — the documented headless
  entry points are `td_commands_prompt` and `td.sh` only.
* Running an interactive command:
  `'info commands' | & '<root>\bin\td_commands_prompt.exe' -nogui` prints the banner and then
  the result. Output is line-buffered and unreliable through a pipe; for anything important,
  write to a file from inside TCL (`set f [open out.txt w]; puts $f ...; close $f`) or pass a
  script file as a positional argument.
* Piping/redirection caveat: `query_current_package` and friends **print to the console**; they
  return an empty string. Do not try to capture them with `set x [...]`.

### 1.2 Stage gating — the single most important semantic rule

> 在Console 窗口中，Tcl 命令须在适当的阶段运行，例如在 `open_run phy_1` 后不能在Console 运行
> Syn 阶段的Flow Step 命令(`elaborate`/`optimize_rtl`/`optimize_gate` 等)。

In the Console, commands must be issued at the appropriate stage: after `open_run phy_1` you
**cannot** run Syn-stage flow-step commands (`elaborate` / `optimize_rtl` / `optimize_gate`).

Hard ordering rules (violating these silently produces wrong results or an error):

```
read_adc   →  BEFORE optimize_rtl
read_sdc   →  BEFORE optimize_gate  (or map_macro)
legalize_phy_inst → after optimize_gate / pack, BEFORE place
read_sdc   →  read AGAIN after legalize_phy_inst, BEFORE place/route
```

### 1.3 Batch invocation

```tcl
source demo.tcl
```

`source` is in the live command list. SWUG105 does **not** document `source -echo`.

### 1.4 The three script modes

**A. Project (multi-run) mode** — `[VERBATIM]` structure from SWUG105 §3.1.1:

```
1. create_project
2. open_project
3. top_module
4. add_files              (sources + .adc + .sdc)
5. create_run             (syn_1 and phy_1 already exist by default — do not re-create)
6. set_param              a) -run is mandatory in multi-run scripts
                          b) set_seed_param + set_param flow enable_seed on for multi-seed
7. launch_runs, wait_run
8. save_best_bits
9. close_project
```

**B. Non-project (stepwise) mode** — `[VERBATIM]` structure from SWUG105 §3.2.1:

```
1. import_device
2. set_param
3. read_hdl
4. read_adc / read_sdc + Syn stage commands + reports
   read_adc BEFORE optimize_rtl;  read_sdc BEFORE optimize_gate or map_macro
5. legalize_phy_inst
6. read_sdc again
7. place / route + reports
```

**C. Single-run mode (reuse an existing project)** — `[VERBATIM]` from SWUG105 §3.3.1:

```
1. import_device
2. open_project -single_run
3. set_param (with -run)
4. constraints + Syn-stage commands + reports
5. legalize_phy_inst
6. read_sdc again
7. place / route + reports
```

### 1.5 Complete verbatim example flows

> **⚠ These are transcribed VERBATIM from the guide and one line in them is BROKEN.**
> SWUG105's own examples contain `set_param ... rtl reg_threshold 0`, which is a **ghost
> parameter** — `set_param` accepts it silently and it does nothing (measured; see §4.5).
> The line is left in place below so the transcription is faithful and recognisable, but **delete
> it** (or replace it with a real `rtl` parameter from §4.1) before using any of these scripts.

**Multi-run + multi-seed (project mode)** — SWUG105 pp.9–10, `[VERBATIM]`:

```tcl
create_project test ./ -family ph1 -device PH1A100SFG676 -speed 2
open_project ./test.al

top_module run_led

add_files ./run_led.v
add_files ./top.adc
add_files ./top.sdc

# Creating a new run phy_2
create_run -constrset constraint_1 -syn_run syn_1 phy_2

set_param -run syn_1 flow qor_monitor on
set_param -run syn_1 rtl reg_threshold 0   ;# GHOST PARAMETER - does nothing; delete this line
set_param -run syn_1 gate pack_seq_in_io off
set_param -run phy_1 place pr_strategy 1
set_param -run phy_2 place pr_strategy 2

# Set multi_seed for active run
set_param -run phy_1 flow enable_seed on
set_seed_param -num 6 -init 5 -step 5 -jobs 3

# Resetting Syn run will automatically reset all Phy runs under the Syn run.
reset_runs syn_1
launch_runs {syn_1 phy_1 phy_2} -jobs 2

wait_run syn_1 -quiet
wait_run phy_1 -quiet
wait_run phy_2 -quiet

save_best_bits
close_project
```

**Non-project stepwise (the canonical full-flow script)** — SWUG105 §3.2.2, `[VERBATIM]`:

```tcl
import_device ph1_100.db -package PH1A100SFG676 -speed 2

set_param flow qor_monitor on
set_param rtl reg_threshold 0   ;# GHOST PARAMETER - does nothing; delete this line
set_param gate pack_seq_in_io off
set_param place pr_strategy 1

read_hdl -file {./run_led.v} -top run_led

read_adc ./top.adc
optimize_rtl

read_sdc ./top.sdc
optimize_gate
legalize_phy_inst
read_sdc ./top.sdc

export_db ./gate.db
report_qor -step gate -file gate.qor
report_area -file gate.area

place
report_qor -step place -file place.qor
update_timing -mode manhattan
report_timing_summary -file place_timing_smry.rpt

route
export_db ./route.db
report_qor -step route -file route.qor
report_area -file route.area
update_timing -mode final
report_timing_summary -file route_timing_smry.rpt

bitgen -bit ./run_led.bit
```

**Intermediate-artifact generation (project mode with `launch_runs -step`)** — SWUG105 pp.14–15,
`[VERBATIM]`:

```tcl
import_device ph1_100.db -package PH1A100SFG676 -speed 2
create_project test ./ -family ph1 -device PH1A100SFG676 -speed 2
open_project ./test.al
top_module run_led

add_files ./run_led.v
add_files ./top.adc
add_files ./top.sdc

set_param -run syn_1 flow qor_monitor on
set_param -run syn_1 rtl reg_threshold 0   ;# GHOST PARAMETER - does nothing; delete this line
set_param -run syn_1 gate pack_seq_in_io off
set_param -run phy_1 place pr_strategy 1

reset_runs syn_1
launch_runs -step rtl syn_1
wait_run syn_1 -quiet
open_run syn_1
write_verilog ./rtl.v

launch_runs -step gate syn_1
wait_run syn_1 -quiet
open_run syn_1
write_verilog ./gate.v

launch_runs -step bitgen phy_1
wait_run phy_1 -quiet
close_project
```

---

## 2. Flow-stage map

```
                     ┌── PROJECT MODE ──────────────────────────────────────────┐
 create_project ─ open_project ─ top_module ─ add_files ─ create_run ─ set_param
                     └──────────── launch_runs / wait_run / open_run ───────────┘

                     ┌── STEPWISE (non-project or single-run) ──────────────────┐
 import_device
   → set_param (flow/rtl)
   → elaborate | read_hdl                    [Read Design / RTL]
   → read_adc            *** before optimize_rtl ***
   → optimize_rtl                            [Optimize RTL]
   → read_sdc            *** before optimize_gate ***
   → optimize_gate  ==  map_macro → map → pack
   → legalize_phy_inst
   → read_sdc (again)    *** before place ***
   → place                                   [Optimize Placement]
   → route                                   [Optimize Route]
   → phys_opt / fix_hold (optional, post-route)
   → bitgen                                  [Generate Bitstream]
                     └──────────────────────────────────────────────────────────┘
```

| Stage name (GUI) | Step names | Commands |
|---|---|---|
| — | `design` | `import_device`, `create_project`, `open_project`, `add_files`, `top_module` |
| Read Design | `read_design` / `design` | `elaborate` or `read_hdl`, `read_adc`, `read_ip_adc` |
| Optimize RTL | `rtl` / `opt_rtl` | `optimize_rtl` |
| Optimize Gate | `gate` / `opt_gate` | `optimize_gate` or `map_macro`+`map`+`pack`, then `legalize_phy_inst`, `read_sdc` |
| Optimize Placement | `place` / `opt_place` | `place` |
| Optimize Route | `route` / `opt_route` | `route` |
| Generate Bitstream | `bitgen` | `bitgen` |

Internal run-step names used by the shipped flow machinery (ground truth from
`DefaultFlow.tcl` / `demo.tcl`):

```tcl
set stepList  {read_design opt_rtl opt_gate opt_place opt_route bitgen}
set preSteps  {non elaborate rtl gate place pr}
```

---

## 3. Command reference by flow stage

### 3.1 Project management

#### `create_project`
```
create_project <project_name> <project_directory> -family <device_family> -device <device_part_number> [-speed <speed_grade>]
```
`project_name` (the `.al` file name, no suffix) must come **before** `project_directory`, but the
two may otherwise appear anywhere. `-family`, `-device` mandatory. Omit `-speed` for the device
default. Forbidden characters — directory: `*\/|:”?<>C` and no leading digit; project name:
`*\/|:”?<>CS` and no leading digit.
```tcl
create_project test ./ -family ph1 -device PH1A100SFG676 -speed 2
create_project test -family ph1 -device PH1A100SFG676 ./
```
See `device-database.md` for the complete family/device/package/speed table.

#### `open_project`
```
open_project [-single_run] <project_file>
```
Opens via the `.al` file. **Default is multi-run mode**; `-single_run` opens it for stepwise
execution.
```tcl
open_project ./example.al
open_project -single_run ./test.al
```
**[LIVE-ONLY]** The tool's own flow uses two undocumented forms:
`open_project ${prj_name}.al -single_run`, and
`open_project {${prj_name}.prj} -noanalyze` (opens the internal `.prj` without re-analysing).
`-noanalyze` is **not** in SWUG105's syntax.

#### `close_project`
```
close_project
```
No options.
```tcl
close_project
```

#### `top_module`
```
top_module <top_name>
```
Project mode: set the design's top module.
```tcl
top_module my_top
top_module run_led
```

#### `add_files`
```
add_files [-list <.list/.slist file>] [<file_path_name>]
```
Adds HDL sources, `.adc`, `.sdc`, and IP files. A group of files goes in braces, space separated.
`-list <file.list>` uses a GUI-exported list (`Project → Export → Export Source File List`);
`-list <file.slist>` is a user-created list (one path per line; relative paths resolve against
the `.al` directory) and **cannot specify a fileset**.
```tcl
add_files {./src/devine.v ./src/top.v}
add_files -list srcfiles.list
add_files -list srcfiles.slist
add_files ./top.adc
add_files ./top.sdc
```

#### `add_dir`
```
add_dir [-r] <dir>
```
Adds every `.v/.vhd/.vhdl/.sv/.ipc` under `dir`. **Does not add `.adc`/`.sdc`.** `-r` recurses.
```tcl
add_dir -r ./src
```
(Note: SWUG105's syntax line for `add_dir` is mis-transcribed as `add_files [-r] <dir>`; the
chapter heading and example both use `add_dir`. `add_dir` is confirmed in the live list.)

#### `add_include_dir`
```
add_include_dir <dir>
```
Adds an include search path; recursive by default.
```tcl
add_include_dir ./src/include_files
```

#### `add_define` / `add_directive`  **[LIVE-ONLY]**
No SWUG105 chapter. Both are in the live list and are the project-mode equivalents of
`read_hdl -define` and synthesis directives.
```tcl
add_define NAME=VALUE
add_directive {attribute_name value}
```

#### `import_device`
```
import_device -package <package_name> [-speed <speed_number>] db_name
```
Imports the target device. `-package` and `db_name` mandatory; omit `-speed` for the device
default. `db_name` is the `Device` column of `list_devices` plus `.db`.
```tcl
import_device ph1_100.db -package PH1A100SFG676 -speed 2
import_device ph1_60.db  -package PH1A60GEG324  -speed 3
```
Wrong speed grade ⇒ `USR-8316 ERROR: Import device error, invalid speed grade setting`.

`import_device` is **mandatory before `open_project` in single-run mode and before any stepwise
command**. The shipped flow always calls it first.

**[LIVE-ONLY]** help DB adds `-basic` and `-ext`:
`import_device db_name -package <string> -speed <string> -basic -ext`.

Related device commands (all in the live list): `set_device`, `load_device`, `dump_device`,
`export_device`, `set_device_info`, `get_device_param`, `set_device_param`, `list_devices`,
`list_packages`, `query_current_arch`, `query_current_package`, `read_device_id`,
`report_device_resource`.

#### `create_run`
```
create_run [-syn_run <syn_run_name>] -constrset <constrset_name> <run_name>
```
Creates a multi-run. For a **phy** run, `-syn_run` names the syn run it inherits from. `-constrset`
mandatory. Run names: no `*\/|:”?[]<>C`, no leading digit.
```tcl
create_run -constrset constraint_1 syn_1
create_run -syn_run syn_1 -constrset constraint_1 phy_2
```
`syn_1` and `phy_1` exist by default after `create_project` — do not re-create them.

#### `launch_runs`
```
launch_runs [-step <design/rtl/gate/place/route/bitgen>] [-jobs <int>] <run_name_list>
```
Starts runs to the given step. **Without `-step`, syn runs to `gate` and phy runs to `bitgen`.**
`-jobs` range 1–6, default 1.
```tcl
launch_runs {phy_1 phy_2} -jobs 2
launch_runs -step rtl   syn_1
launch_runs -step gate  syn_1
launch_runs -step bitgen phy_1
```

#### `open_run`
```
open_run <run_name>
```
Opens the db of whatever step that run has currently finished.
```tcl
open_run syn_1
```

#### `wait_run`
```
wait_run <run_name> [-quiet]
```
Blocks until the run finishes. `-quiet` suppresses the streaming log.
```tcl
wait_run phy_1 -quiet
```

#### `reset_runs`
```
reset_runs <run_name_list> [-prev_step] [-f]
```
Rolls a run back. Without `-prev_step` it returns to the initial state. `-f` also deletes the
run's folder (**only effective without `-prev_step`**). **Resetting a syn run automatically
resets all phy runs under it.**
```tcl
reset_runs {phy_1 phy_2}
reset_runs syn_1
reset_runs phy_1 -prev_step
```

#### `close_run`, `delete_runs`, `copy_run`, `save_project_as`  **[LIVE-ONLY]**
No SWUG105 chapter. Live in the 740 list.
```tcl
close_run phy_1
delete_runs {phy_2 phy_3}
copy_run -src phy_1 -dst phy_3          ;# [RECONSTRUCTED] argument form not documented
save_project_as ./backup/test.al
```

#### `save_best_bits`
```
save_best_bits
```
Picks the best-timing bitgen result across all runs and copies it to
`<project_name>_Runs/best_result`.
```tcl
save_best_bits
```

#### `save_design`
```
save_design
```
After `open_run`, persists any Console-driven design modifications back into the db so later
steps see them.
```tcl
open_run syn_1
# ... console edits ...
save_design
```

#### `set_param`
```
set_param [-run <run_name>] <step_name> <param> <value>
```
`-run` is **mandatory** in the GUI Console and in multi-run scripts, and **must be omitted** in
non-project mode. `<step_name>` ∈ `flow | design | rtl | gate | place | route | timing | sim |
bitgen` (but only `flow`, `rtl`, `gate`, `place`, `route` have documented parameters).
**`set_param` must be issued before the corresponding step's command.** Full parameter inventory
in §4; effects in §5.
```tcl
set_param gate map_strategy 2
set_param -run phy_1 route fix_hold on
set_param -run syn_1 rtl default_reg_initial 0     ;# then launch_runs -step design syn_1
set_param flow qor_monitor on                      ;# non-project mode, no -run
```

#### `report_param`
```
report_param [-file <file_path_name>] [-detail] [-stage <flow/design/rtl/gate/place/route/timing/sim/bitgen>]
```
Prints the db's parameters. With no options, prints only **non-default** parameters.
`-detail` also prints defaults. `-stage` limits to one stage.
```tcl
report_param
report_param -stage place
report_param -detail -file all_params.txt
```

#### `clear_param`
```
clear_param
```
Resets every parameter in the db to its default and clears unregistered parameters.
```tcl
clear_param
```

#### `set_seed_param`
```
set_seed_param [-num <int>] [-init <int>] [-step <int>] [-jobs <int>] [-save <int>] \
               [-genBit <on/off>] [-disable] [-random <on/off>] [-filter <on/off>] \
               [-rwns <double>] [-pwns <double>] [-congestion <int>] [-farm <on/off>] \
               [-ip <lsf_server_address>] [-queue <lsf_queue_name>]
```
Configures multi-seed for the **active phy run**; only effective in multi-run scripts.
Multi-seed is *sticky* — it remembers the last configuration.

| Option | Default | Meaning |
|---|---|---|
| `-num <int>` | 1 | number of seeds |
| `-init <int>` | 0 | lowest seed value |
| `-step <int>` | 10 | seed stride |
| `-jobs <int>` | 3 | concurrent seeds (auto-maximised on a farm) |
| `-save <int>` | 1 | how many seed results to keep |
| `-genBit <on/off>` | on | generate bitfiles for seeds |
| `-disable` | — | turn multi-seed off |
| `-random <on/off>` | off | random seed generation |
| `-filter <on/off>` | off | early-abort bad seeds using `-rwns`/`-pwns`/`-congestion` |
| `-rwns <double>` | 0 ns | abort a seed whose route WNS is below this |
| `-pwns <double>` | 0 ns | abort a seed whose place WNS is below this |
| `-congestion <int>` | 100 | abort a seed whose congestion exceeds this (% resource use) |
| `-farm <on/off>` | off | run on an LSF farm |
| `-ip <addr>` | — | LSF server address |
| `-queue <name>` | — | LSF queue name |

```tcl
set_seed_param -num 10 -jobs 5 -save 2
set_seed_param -num 6 -init 5 -step 5 -jobs 3
```

**`enable_seed` is NOT a command.** It exists only as a `flow`-step `set_param` parameter:
```tcl
set_param -run phy_1 flow enable_seed on
set_seed_param -num 6 -init 5 -step 5 -jobs 3
```

#### `report_seed_param`
```
report_seed_param
```
Prints the current multi-seed configuration.
```tcl
report_seed_param
```

#### `select_seed`, `stop_seed`  **[LIVE-ONLY]**
Used with multi-seed runs; no SWUG105 chapter.
```tcl
select_seed <seed_id>     ;# [RECONSTRUCTED] argument form not documented
stop_seed                 ;# [RECONSTRUCTED] argument form not documented
```

#### `generate_elaborate_package`
```
generate_elaborate_package
```
Produces a portable elaborated-db package:
`<project dir>/elaborate_package/<project_name>_elaborate.db`, containing `elaborate.db`, the
constraint files and the run script. **Requires the active syn run to have run at least to
`read_design`, then `open_run`.** Parameter settings in the original project are reset to
defaults in the generated db.
```tcl
open_run syn_1
generate_elaborate_package
```

#### Shipped-flow-only run plumbing  **[LIVE-ONLY]**
These appear in `DefaultFlow.tcl` / `MultiSeed.tcl` / `demo.tcl` and are what actually makes a
generated run script work. You normally do not call them by hand, but you need to know they
exist when reading run logs.

| Command | Use |
|---|---|
| `commit_param -step <design\|rtl\|gate\|place\|route\|bitgen>` | commits the run's parameter set at the head of every step. **Uses `-step design`, not `-step read_design`.** |
| `load_run_param -run <run>` | loads a run's saved parameter set |
| `flow_status -file <f>` | writes the per-step flow status file |
| `export_flow_status -s <start> -e <end>` | writes the run's overall status |
| `flow_continue_check -step <place\|route> -wns <val> [-congestion <val>] [-name <prj>]` | implements the seed `-filter` early-abort |
| `export_flow_script` | emits a standalone flow script |
| `export_bitgen_param -file .bitgen_param.f` | dumps the effective bitgen parameters |
| `clean_project`, `zip_project` | project housekeeping |

### 3.2 Source & constraints

#### `read_hdl`
```
read_hdl [-help] [-file <file_path_name>] [-dir <dir_path>] \
         [-global_include <global_include_file_path_name>] [-included_dir <included_dir_path>] \
         [-define <define_name/define_name=define_value>] -top <top_module_name>
```
Non-project mode: read and parse HDL. **At least one of `-file` / `-dir` is required.** `-top` is
mandatory. `-file` accepts `.v`, `.sv`, `.vhd`, and **multiple files must be inside double
quotes**, space separated. Language overrides via a `prefix::` form:

| Form | Meaning `[VERBATIM]` |
|---|---|
| `read_hdl -file "in1.v in2.sv in3.vhd"` | parse each by its own suffix |
| `read_hdl -file "sv::in1.v"` | ignore suffix, parse as SystemVerilog |
| `read_hdl -file "vlib::lib1::in3.vhd"` | parse into VHDL library `lib1` |

`-define` takes `NAME` or `NAME=VALUE`; multiple inside `""`, space separated.
```tcl
read_hdl -file {./run_led.v} -top run_led
read_hdl -file "in1.v in2.sv in3.vhd"
read_hdl -define "NAME1 NAME2=VALUE2" -file {./src/top.v} -top top
```
Forbidden characters in file paths/names (except `/`): `*\/|:”?<>C`, no leading digit.

`read_verilog` **[LIVE-ONLY, effectively an alias]** — appears in the live list and once in
SWUG105, but only as a stray example under `read_hdl`. Prefer `read_hdl`.

#### `read_adc`
```
read_adc <file_path_name>
```
Reads the physical-constraint `.adc`. Relative paths resolve against the **TCL script's**
directory. **Must run before `optimize_rtl`.**
```tcl
read_adc ./src/constraints/top.adc
```
Real `.adc` content (ground truth, `demo.adc`):
```tcl
set_pin_assignment	{ i_clk       }	{ LOCATION = A10; IOSTANDARD = LVCMOS33; }
set_pin_assignment	{ i_rst_n     }	{ LOCATION = B11; IOSTANDARD = LVCMOS33; }
```
Full ADC syntax: `timing-constraints.md` §2.

#### `read_ip_adc`
```
read_ip_adc -ip <ip_model_name> -file <file_path_name>
```
Both options mandatory.
```tcl
read_ip_adc -ip my_ip -file ./ip_srcs/my_ip.adc
```

#### `read_sdc`
```
read_sdc [-ip <ip_model_name>] <file_path_name>
```
Without `-ip` it is the whole-project SDC; with `-ip` it is that IP's SDC. **Must run before
`optimize_gate` or `map_macro`, and again after `legalize_phy_inst` before place/route.**
```tcl
read_sdc ./src/constraints/top.sdc
read_sdc -ip my_ip ./ip_srcs/my_ip.sdc
```
Real `.sdc` content (ground truth, `demo.sdc`):
```tcl
create_clock -name sys_clk -period 20.000 [get_ports {i_clk}]
set_false_path -from [get_ports {i_rst_n}]
set_false_path -to [get_ports {o_uart_tx}]
```
Full SDC syntax: `timing-constraints.md`.

#### `clear_adc`
```
clear_adc
```
Clears ADC constraint information (pin + instance).
```tcl
clear_adc
read_adc my_new_pin_location.adc
```

#### `clear_sdc`
```
clear_sdc
```
Clears **all** SDC — user SDC and IP SDC.
```tcl
clear_sdc
read_sdc my_new_constraints.sdc
read_sdc -ip my_ip my_new_ip_constraints.sdc
```
**[LIVE-ONLY]** the shipped flow uses `clear_sdc -user` to clear only user SDC. `clear_user_sdc`
also exists as a separate command.

#### `clear_user_sdc` / `clear_inst_adc` / `clear_prj_params`  **[LIVE-ONLY]**
```tcl
clear_user_sdc
clear_inst_adc
clear_prj_params
```

#### `write_verilog`
```
write_verilog [<file_path_name>]
```
Writes the intermediate Verilog netlist. Without a path, produces `<top>_out.v` in the cwd.
Stage: after `open_run`, any step.
```tcl
write_verilog ./sim_netlist/top.v
write_verilog ./rtl.v
write_verilog ./gate.v
```
**[LIVE-ONLY]** sibling: `write_hdl`.

#### `write_sdf`
```
write_sdf [-h/-help] [-check_corner <SLOW/FAST/SLOW_FAST>] [-file <file_path_name>]
```
Writes the standard delay file. `-check_corner` default **`SLOW_FAST`**. Without `-file`,
produces `<top_module_name>.sdf` in the cwd.
```tcl
write_sdf ./sim_netlist/top.sdf
write_sdf -check_corner SLOW -file ./top_slow.sdf
```

#### `import_db`
```
import_db <db_file_path_name>
```
Imports a design checkpoint. Used at the head of a resume / incremental step.
```tcl
import_db ./place.db
import_db route.db
```
**[LIVE-ONLY]** note: TD UG DRC `USR-8018` says `import_db` is deprecated in favour of
`import_design` — but **`import_design` is not in the live 740-command list**, while `import_db`
is. Keep using `import_db`.

#### `export_db`
```
export_db <db_file_path_name>
```
Exports a design checkpoint.
```tcl
export_db ./place.db
export_db ./gate.db
export_db ./route.db
```

#### Other source/constraint commands in the live list  **[LIVE-ONLY]**
`export_adc`, `export_sdc`, `export_sdc_target`, `export_constrSet`, `write_csv`,
`generate_simulation`, `read_sdf`, `read_verilog`, `remove_source`, `clear_design`,
`export_files`, `import_cswi`, `import_paramlib`, `import_specifications`, `import_arch`.
No SWUG105 chapter; run `<cmd> -help` before relying on argument order.

### 3.3 Stepwise implementation

#### `elaborate`
```
elaborate [-help] -top <top_module_name>
```
Project / single-run mode: parse HDL sources. (Non-project mode uses `read_hdl` instead.)
`-top` mandatory.
```tcl
elaborate -top my_top
elaborate -top run_led
```

#### `optimize_rtl`
```
optimize_rtl
```
RTL optimisation. **No options.**
```tcl
optimize_rtl
```
**[LIVE-ONLY]** related: `preprocess`, `analyze`, `elaborate` (all exist; undocumented).

#### `optimize_gate`
```
optimize_gate [-maparea <report_file_path>] [-packarea <report_file_path>]
```
Resource mapping + packing — the integration of `map_macro`, `map` and `pack` in one step.
`-maparea` / `-packarea` redirect the post-`map` / post-`pack` area reports.
```tcl
optimize_gate
optimize_gate -packarea ./pack.area
```
The tool's own flow calls it as `optimize_gate ${area_option} ${prj_name}_gate.area`, where
`area_option` is `-packarea` or `-maparea` (ground truth: `settings.cfg`).

#### `map_macro` / `map` / `pack`
```
map_macro     ;# device mapping: RAM, DSP, SHIFTER, carry chains, PAD
map           ;# optimise combinational logic and map to LUTs
pack          ;# pack resources into SLICEs
```
No options. Use these when you need per-sub-step area reports; otherwise `optimize_gate`.
```tcl
map_macro
map
pack
```

#### `legalize_phy_inst`
```
legalize_phy_inst
```
Netlist normalisation. **Mandatory between `optimize_gate`/`pack` and `place`**, and must be
followed by a second `read_sdc`.
```tcl
optimize_gate
legalize_phy_inst
read_sdc ./test.sdc
place
route
```
**[LIVE-ONLY]** related: `direct_legalization`, `legalization`, `initplace`, `repack`,
`reanalyze`.

#### `place`
```
place [-eco] [-keep_pad] [-export_adc]
```
Runs placement. SWUG105 documents it as option-less; the shipped help DB `help_comment_phy.json`
gives `[-eco] [-keep_pad] [-export_adc]` (ground truth).
```tcl
place
place -eco
```

#### `route`
```
route [-eco] [-incremental] [-verbose]
```
Runs routing. Same situation as `place`: SWUG105 documents it option-less, the help DB gives the
options above.
```tcl
route
route -incremental
```
**[LIVE-ONLY]** related: `multi_try_route`, `imux_route`, `mpnr_route_net`, `route_clock`.

#### `bitgen`
```
bitgen [-bit <bitfile_path_name>] [-bin <binfile_path_name>] [-gen_mask] [-hd <string>] \
       [-id <string>] [-version <string>] [-security] [-no_date_info] [-compress] \
       [-embedded_compress] [-seu_all] [-unused_io_status <pullup/pulldown/keeper/none>] \
       [-g { param_1:value_1 param_2:value_2 ... param_n:value_n }]
```

**General options:**

| Option | Meaning |
|---|---|
| `-bit <path>` | bit file. **At least one of `-bit` / `-bin` is required.** |
| `-bin <path>` | bin file. |
| `-gen_mask` | also emit a bitstream **mask** file so SRAM readback does not check masked code points. Requires `-bit`. Needed if the project has DRAM init values and you will readback/verify SRAM. |
| `-hd <string>` | prepend 16 bytes of header info to the bin for offline download. Requires `-bin`. 32 hex digits; default `00000000AA5599669100050000000000`. |
| `-id <string>` | prepend a 2-byte bin id. Requires `-bin`. 4 hex digits. |
| `-version <string>` | version field written into the bitstream and readable back on the Download screen. Requires `-bit` or `-bin`. 2 hex digits, default `00`. |
| `-security` | disable SRAM readback. |
| `-no_date_info` | omit the creation timestamp (makes bit files byte-comparable). |
| `-compress` | also emit a compressed bit file (`*_compress.bit`, `*_compress.bin`); the uncompressed file is still produced. Requires `-bit`. |
| `-embedded_compress` | compress the bin for embedded loading (`*.huf`, `*.ttf`). |
| `-seu_all` | enable full-bitstream SEU checking. **PH1A100 and PH1A400 only.** |
| `-unused_io_status <pullup\|pulldown\|keeper\|none>` | startup state of unused IOs; default `pullup`. |

**Register options via `-g`:** `param` names and `value` spellings must **exactly** match the
GUI `Generate Bitstream Properties` options (`Process → Properties`). Format is
`-g {param:value param:value ...}`.
```tcl
bitgen -bit ./run_led.bit
bitgen -bit top.bit -g {security:1}
bitgen -bit top.bit -g {mclk_freq:5MHz boot_mode:mspix4}
bitgen -bit top.bit -bin top.bin -gen_mask -unused_io_status none
```
The complete `-g` option/value catalogue is the "Generate Bitstream Properties" tables in
TD UG § 9.6 — reproduced in §6 below.

#### Optimisation commands (post-route)

#### `phys_opt`
```
phys_opt [-effort <low/medium/high/ultra>] -post_route
```
Post-route physical optimisation. `-post_route` is **mandatory** per SWUG105; `-effort` defaults
to `medium`. Run after `import_db` of a routed db.
```tcl
import_db route.db
phys_opt -post_route -effort high
```
Input DB help DB (`help_comment_phy.json`) documents a **richer option set**:
`[-effort <level>] [-register_opt] [-lut_merge] [-simplify_lut] [-merge_lut1]
[-force_replication_on_nets <net>] [-fanout_threshold <num>] [-post_route] [-mode] [-hold_fix]
[-post_clock_route]`. It also spells the effort values `low|middle|high|ultra` and mentions
`-post_place`. **[UNRESOLVED]** both spellings appear in shipped material — treat `medium` as
SWUG105-canonical, `middle` as a possible legacy alias, and verify with `phys_opt -help`.

#### `fix_hold`
```
fix_hold
```
Standalone post-route hold fix. No options.
```tcl
import_db route.db
fix_hold
```
The shipped flow implements the "fix hold after route" pattern by turning the *route-stage*
parameter off, routing, then fixing hold separately:
```tcl
set_param route fix_hold off
set_param flow qor_monitor off
route
fix_hold
set_param route fix_hold on
set_param flow qor_monitor on
report_qor -step route -file route.qor
```
**[LIVE-ONLY]** related: `dp_fix_hold`, `fix_hold_move`, `fix_timing`.

### 3.4 Reports

#### `report_area`
```
report_area [-file <file_path_name>] [-verbose] [-io_info]
```
`-io_info` adds detailed IO information; `-verbose` adds detail.
```tcl
report_area -file ./place.area -io_info
report_area -file gate.area
```

#### `report_logic_level`
```
report_logic_level [-h/-help] -file <file_path_name> [-worst_n <int>] [-no_header]
```
`-file` is **mandatory** (output is too large for the console). `-worst_n` limits to the N
worst-setup-slack paths.
```tcl
report_logic_level -file ./gate.logiclvl
report_logic_level -file gate.lvl -worst_n 20
```

#### `report_hfn`
```
report_hfn <rtl/gate/place/route> [-net <net_name>] [-limit <int>] [-min <int>] [-max <int>] \
           [-file <file_path_name>] [-timing]
```
Stage is mandatory. Default: top 20 nets by fanout, descending. `-net` and (`-limit`/`-min`/
`-max`) are mutually exclusive.
```tcl
report_hfn gate
report_hfn place -net {rst} -timing
report_hfn route -min 100 -timing
```

#### `report_analysis`
```
report_analysis <mode> [-timing] [-congesiton] [-file <file_path_name>] [-max_path_num <int>]
```
See `timing-analysis.md` §10.10 for the spelling caveat on `-congesiton`.
```tcl
report_analysis final -congestion -file ./congestion_analysis.rpt
```

#### `report_cells`
```
report_cells <cell_name> [-help] [-connection] [-pin_loc] [-mode <basic/manhattan/final>] \
             [-timing] [-hold]
```
```tcl
report_cells {o_dat_reg[1]} -connection -mode manhattan -timing -hold
report_cells -bram -dsp -export_adc -file $backAnnotation      ;# ground truth, MultiSeed.tcl
```

#### `report_nets`
```
report_nets <net_name> [-help] [-connection] [-mode <basic/manhattan/final>] [-timing] [-hold] \
            [-of_pins <pin_name>]
```
```tcl
report_nets {datgen_din[0]} -connection -mode manhattan -timing -hold
```
Option-name discrepancy: SWUG105 §4.7.6 documents `-pin_output_limit <int>`; the shipped help DB
documents `-pin_display_limit <number>`. **[UNRESOLVED]** — check `report_nets -help`.

#### `report_qor`
```
report_qor -step <gate/place/route> [-file <file_path_name>]
```
`-step` mandatory. `optimize_gate`/`pack`/`place`/`route` call it automatically; output lands in
`<project>_Runs/{syn_*,phy_*}/<step>.qor` (project mode) or the cwd (non-project mode).
```tcl
report_qor -step gate  -file gate.qor
report_qor -step place -file place.qor
report_qor -step route -file route.qor
```

#### Timing reports
`report_timing_summary`, `report_timing_path`, `report_clock_intersection`,
`report_clock_summary`, `report_timing_exception`, `report_timing_ignored`, `update_timing`,
`check_timing`, `report_timing_status` — see `timing-analysis.md` §10 for full syntax.

`report_timing_status` **[LIVE-ONLY]** is a compact per-clock status file used by the shipped
flow; SWUG105 never documents it:
```tcl
report_timing_status -file ${prj_name}_gate.ts
report_timing_status -file ${prj_name}_phy.ts
```

#### More reports in the live list  **[LIVE-ONLY]**
`report_ram_utilization`, `report_clock_utilization` (help DB: `-dramhardcon -file <string>`),
`report_imux_utilization`, `report_routing_resource`, `report_route_status`,
`report_placement_status`, `report_design_status`, `report_design_cell_num`, `report_congestion`
(help DB: `[-step] [-th] [-line] [-direction] [-level]`), `report_wirelength`,
`report_path_margin`, `report_async_reg`, `report_dangling`, `print_grid_utilization`,
`show_area`, `print_ext_qor`, `write_qor_params`, `non_default_params`, `report_io`,
`report_bounds`, `report_modules`, `report_pr_critical_paths`, `report_timing`,
`report_timing_correlation`, `report_routing_correlation`, `report_hyper_paths`,
`report_path_skew`, `report_liberty_timing_arc`, `report_liberty_clock_path`.

`report_clock_utilization` usage from the shipped flow:
```tcl
report_clock_utilization -file place_clock_utilization.txt
report_clock_utilization -file route_clock_utilization.txt
```

---

## 4. Parameterisation — the complete `set_param` inventory

> **This section is MEASURED, not transcribed.** The parameter database below was enumerated by
> running TD 6.2.1 directly (`td_commands_prompt.exe -nogui <script>`) against a real project and
> calling `report_param -detail`, then corroborated against the tool's own recorded
> `demo_Runs\{syn_1,phy_1}\run.log`. **Where SWUG105's Tables 4-1/4-2 disagree, the measurements
> win** — and they disagree in several important places.

### 4.1 The authoritative parameter database — 46 parameters, 7 stages

```
flow design rtl gate place route timing sim bitgen         <- the 9 valid set_param steps
```

**`timing` and `sim` are valid step names with EMPTY parameter sets** — and enumerating them
with `report_param -detail -stage` **crashes TD**. See the crash note in §4.2. Do not loop over
them.

The `flow`, `design`, `rtl`, `gate`, `place`, `route` and `bitgen` stages hold **46** registered
parameters (count re-measured against the live tool; see the verified inventory in §4.1b):

| step | param | default | note |
|---|---|---|---|
| `flow` | `enable_seed` | `off` | |
| `flow` | `hfn_to_clock` | `1000000000` | |
| `flow` | `message` | `standard` | |
| `flow` | `qor_monitor` | `on` | |
| `flow` | `speedup_effort` | `0` | |
| `flow` | `syn_ip_flow` | `off` | |
| `flow` | `thread` | `auto` | |
| `design` | `default_reg_initial` | `auto` | **step is `design`, not `rtl`** |
| `design` | `hdl_warning_level` | `normal` | **step is `design`, not `rtl`** |
| `rtl` | `fix_undriven` | `0` | |
| `rtl` | `gated_clock_conversion` | `off` | **SWUG105 omits** |
| `rtl` | `infer_fsm` | `auto` | **SWUG105 says `off` — wrong** |
| `rtl` | `infer_rom` | `on` | |
| `rtl` | `infer_shifter` | `on` | |
| `rtl` | `keep_hierarchy` | `auto` | |
| `rtl` | `merge_equal` | `on` | |
| `rtl` | `min_control_set` | `8` | |
| `rtl` | `min_ripple_len` | `auto` | |
| `rtl` | `seq_syn` | `on` | |
| `gate` | `eram_cascade_height` | `auto` | |
| `gate` | `map_mode` | `auto` | |
| `gate` | `map_strategy` | `1` | |
| `gate` | `pack_effort` | `medium` | |
| `gate` | `pack_seq_in_io` | `auto` | |
| `gate` | `report` | `standard` | |
| `place` | `effort` | `medium` | |
| `place` | `hfn_opt_effort` | `medium` | |
| `place` | `logic_level_opt` | `off` | |
| `place` | `macro_performance` | `auto` | |
| `place` | `max_fanout` | `999999` | |
| `place` | `opt_timing` | `medium` | |
| `place` | `post_place_opt` | `auto` | |
| `place` | `preplace_floorplan` | `off` | **SWUG105 omits (it is in TD UG § 9.6)** |
| `place` | `pr_strategy` | `1` | |
| `route` | `effort` | `normal` | |
| `route` | `fix_hold` | **`on`** | **SWUG105 says `off` — wrong** |
| `route` | `hold_fix_iteration` | `5` | **SWUG105 omits entirely** |
| `route` | `post_route_opt` | `auto` | |
| `route` | `timing` | **`on`** | **SWUG105's value list (`normal`/`off`/`greedy`) does not even contain the real default** |
| `bitgen` | `bin` | `off` | **the `bitgen` step is not empty — 7 params SWUG105 omits** |
| `bitgen` | `compress` | `off` | |
| `bitgen` | `gen_mask` | `off` | |
| `bitgen` | `max_stream` | `on` | |
| `bitgen` | `time_info` | `on` | |
| `bitgen` | `unused_io_status` | `pullup` | |
| `bitgen` | `version` | `0x00` | |

`report_param -detail` is the **only** reliable enumeration: it lists every parameter that
actually exists, with its current setting and its default. Use it, not the PDFs.

### 4.2 ⚠ `set_param` VALIDATES NOTHING — the top operational hazard

**Measured: `set_param` returns `rc = 0` for bogus values AND for non-existent parameter names.**
Every one of these succeeded:

```tcl
set_param gate   map_mode             ZZZJUNK   ;# rc=0  bogus value accepted
set_param rtl    infer_fsm            ZZZJUNK   ;# rc=0
set_param place  pr_strategy          999       ;# rc=0  out of every documented range
set_param place  pr_strategy          18        ;# rc=0  (PH2 doc range stops at 17)
set_param route  fix_hold             ZZZJUNK   ;# rc=0
set_param flow   qor_monitor          ZZZJUNK   ;# rc=0
set_param place  effort               ZZZJUNK   ;# rc=0
set_param place  totally_bogus_param  1         ;# rc=0  <-- PARAMETER DOES NOT EXIST
set_param place  prr_strategy         3         ;# rc=0  <-- TYPO, silently ignored
set_param rtl    reg_threshold        7         ;# rc=0  <-- PARAMETER DOES NOT EXIST
```

**Only the step name is validated:**

```tcl
set_param bogusstep foo bar                   ;# rc=1  (error)
set_param read_design default_reg_initial 1   ;# rc=1  run-step name, not a set_param step
set_param opt_rtl fix_undriven 1              ;# rc=1
set_param opt_place effort high               ;# rc=1
set_param pr post_route_opt high              ;# rc=1
```

Consequence: **a typo in a parameter name or value produces no error, no warning, and no
effect.** The parameter silently does not exist and your optimisation never happens. Always
validate before shipping a script:

```tcl
# get_param is a USEFUL but NOT FULLY RELIABLE existence test - see the false-positive
# warning below. Use it as a cheap first filter, and report_param -detail as ground truth.
if { [catch { get_param place effort } rc] } {
    puts "WARNING: parameter place/effort may not exist - verify against report_param -detail"
}
```

`get_param <step> <param>` (undocumented in SWUG105, syntax recovered by measurement) returns the
current value on stdout with rc = 0 for registered parameters, and rc = 1 with no message for
most things that do not exist — including non-existent steps:

```tcl
get_param place effort         ;# rc=0 -> medium
get_param gate  map_mode       ;# rc=0 -> auto
get_param place total_bogus    ;# rc=1
get_param bogusstep bogusparam ;# rc=1
get_param rtl reg_threshold    ;# rc=1   <-- proves reg_threshold is not real
get_param place shifter_opt    ;# rc=1   <-- not registered
```

> **WARNING — `get_param` has FALSE POSITIVES. It is not a sound existence test.**
> `get_param rtl retiming` returns **rc = 0 with the value `off`**, and
> `get_param place pack_mode` returns **rc = 0 with the value `auto`** — yet *neither name
> appears in any stage's parameter table* from `report_param -detail`. They appear to be
> answered from a defaults/legacy table rather than the registered set. So a green `get_param`
> does **not** prove the parameter will have an effect.
>
> **Ground truth is `report_param -detail`** (see §4.1). Use `get_param` only to read a value
> you already know is registered, or as a fast negative filter. When it matters, confirm the
> name is in the `report_param -detail` table.
>
> Also note: `report_param` writes to the **real process stdout, which `catch` does NOT
> capture** — `set rc [catch { report_param -detail } r]` leaves `$r` empty. Either let it print
> and redirect the whole TD session to a log, or run it with no `catch` wrapper.

> **CRASH — do not enumerate the `timing` or `sim` stages.**
> `report_param -detail -stage timing` and `-stage sim` **kill TD** with an access violation
> (exit `3221225477`, `minidump-*.dmp`). Both step names are accepted by `set_param`/
> `report_param` but hold *empty* parameter sets, and enumerating them dereferences nothing.
> Iterate only over `flow design rtl gate place route bitgen`.

### 4.1b Measured inventory (verify with `report_param -detail`)

| Stage | # | Parameters (defaults) |
|---|---|---|
| `flow` | 7 | `enable_seed`(off), `hfn_to_clock`(1000000000), `message`(standard), `qor_monitor`(on), `speedup_effort`(0), `syn_ip_flow`(off), `thread`(auto) |
| `design` | 2 | `default_reg_initial`(auto), `hdl_warning_level`(normal) |
| `rtl` | 10 | `fix_undriven`(0), `gated_clock_conversion`(off), `infer_fsm`(**auto**), `infer_rom`(on), `infer_shifter`(on), `keep_hierarchy`(auto), `merge_equal`(on), `min_control_set`(8), `min_ripple_len`(auto), `seq_syn`(on) |
| `gate` | 6 | `eram_cascade_height`(auto), `map_mode`(auto), `map_strategy`(1), `pack_effort`(medium), `pack_seq_in_io`(auto), `report`(standard) |
| `place` | 9 | `effort`(medium), `hfn_opt_effort`(medium), `logic_level_opt`(off), `macro_performance`(auto), `max_fanout`(999999), `opt_timing`(medium), `post_place_opt`(auto), `pr_strategy`(1), `preplace_floorplan`(off) |
| `route` | 5 | `effort`(normal), `fix_hold`(**on**), `hold_fix_iteration`(5), `post_route_opt`(auto), `timing`(**on**) |
| `bitgen` | 7 | `bin`(off), `compress`(off), `gen_mask`(off), `max_stream`(on), `time_info`(on), `unused_io_status`(pullup), `version`(0x00) |
| `timing`, `sim` | 0 | empty — **do not enumerate (crashes)** |

**Total: 46 registered parameters across 7 usable stages.** Confirm on the live tool rather than
trusting this table if the TD build differs.

Names that appear in the strategy JSONs or in TD UG §9.6 but are **registered nowhere**:
`retiming`, `pack_mode`, `shifter_opt`, `crit_path_opt`, `timing_driven_mode`,
`aggressive_opt`, `enhanced_beeline_opt`, `resource_sharing`, `shifter_style`,
`min_shifter_len`, `min_shifter_size`, `reg_threshold`, `mapper_lut_delay`,
`merge_tiny_lut`, `add_map_lut_struct`, `multi_thread_mapping`, `opt_eram_const`.
Set the registered knobs instead.

### 4.3 Two disjoint step vocabularies — do not mix them

| Vocabulary | Valid tokens |
|---|---|
| `set_param <step>` | `flow design rtl gate place route timing sim bitgen` |
| `launch_runs -step` / `commit_param -step` | syn: `read_design opt_rtl opt_gate`; phy: `opt_place opt_route bitgen`; also `design rtl gate place route bitgen` |

Mixing them is a hard error for `set_param` (`rc=1`) and a silent no-op in the other direction.
The internal run-step names reconstructed by the shipped flow machinery are
`read_design opt_rtl opt_gate opt_place opt_route bitgen` — **none of these is a `set_param`
step.**

### 4.4 `-run` rules

| Mode | `-run` |
|---|---|
| GUI Console | **mandatory** |
| multi-run TCL script | **mandatory** |
| non-project mode | **must be omitted** |

The tool's own per-run scripts use the bare three-argument form
(`set_param route fix_hold off`), because the run context is already active.

### 4.5 Parameters SWUG105 documents that DO NOT EXIST

| SWUG105 claim | Measured reality |
|---|---|
| `place pack_mode` (`auto`/`lower_pin_density`/`adaptive_pin_density`/`more_lut_pair`, default `auto`) | **not registered.** `get_param place pack_mode` → error. The real gate-stage knob is `pack_effort`. (TD UG § 9.6 does describe `pack_mode` for PH2 — it may exist only for PH2 or may have been removed; it is absent for PH1A.) |
| `rtl reg_threshold` (used 5× in SWUG105's *own recommended* scripts) | **not registered.** Verified three ways: `set_param` accepts it silently; `get_param rtl reg_threshold` → rc=1; absent from `report_param -detail`; absent from the real `syn_1/run.log` and `phy_1/run.log`. **Do not use.** |
| `rtl (Read Design)` pair `default_reg_initial` / `hdl_warning_level` | belong to the **`design`** step, not `rtl` |
| `place pr_strategy` "PH1: 1–11; PH2: 1–5, 12–17" | **unverified and probably not enforced** — `999`, `18`, `11`, `17`, `12` were all accepted. Only the default `1` is confirmed. Treat the ranges as documentation claims, not enforced behaviour. |
| `place opt_timing` values `medium/off/low/high/ultra` | parameter exists; the value list is unverified for the same reason |
| `timing` / `sim` steps | accepted step names with **empty** parameter sets |

### 4.6 Parameters that EXIST but SWUG105 never mentions (10)

| step | param | default |
|---|---|---|
| `rtl` | `gated_clock_conversion` | `off` |
| `place` | `preplace_floorplan` | `off` |
| `route` | `hold_fix_iteration` | `5` |
| `bitgen` | `bin` | `off` |
| `bitgen` | `compress` | `off` |
| `bitgen` | `gen_mask` | `off` |
| `bitgen` | `max_stream` | `on` |
| `bitgen` | `time_info` | `on` |
| `bitgen` | `unused_io_status` | `pullup` |
| `bitgen` | `version` | `0x00` |

`bin`, `compress`, `gen_mask`, `unused_io_status` and `version` mirror the corresponding `bitgen`
*command* options. `preplace_floorplan` also exists as a **standalone live command**.

### 4.7 Defaults where SWUG105 is WRONG

| param | SWUG105 says | measured | verdict |
|---|---|---|---|
| `route fix_hold` | `off` | **`on`** | **SWUG105 wrong.** A fresh TD 6.2.1 project has hold fixing **on**. This explains the shipped flow's `set_param route fix_hold off` … `route` … `fix_hold` … `set_param route fix_hold on` dance: it turns the default *off*, routes, fixes hold separately, then restores it. |
| `rtl infer_fsm` | `off` | **`auto`** | **SWUG105 wrong.** |
| `route timing` | `normal` | **`on`** | **SWUG105 wrong, and its value list (`normal/off/greedy`) does not even contain the real default.** |
| all other 47 | — | match | SWUG105 is otherwise accurate on defaults |

### 4.8 Parameter names that DO NOT EXIST

Verified against the measured database. If you were about to write one of these, use the real name:

| Wrong name | Real name |
|---|---|
| `ppr_strategy` | **`pr_strategy`** (step `place`) |
| `prr_strategy` | **`pr_strategy`** (a plausible typo; silently ignored) |
| `map_timing_driven` | **`timing_driven_mode`** — which is itself **not registered** (see §4.9) |
| `map_effort` | **`pack_effort`** (step `gate`) — there is no `map_effort` |
| `place_effort` | **`effort`** with step `place` |
| `route_effort` | **`effort`** with step `route` |
| `fsm_encoding` | **`infer_fsm`** (step `rtl`, values include `one_hot`) |
| `duplicate_inputs` | no real equivalent; closest is `net_dup_with_macro_loads`, itself not registered |
| `global_clock` | not a `set_param` at all — clock routing is SDC: `set_clock_route`, `set_clock_route_enforce`, `set_clock_net` |
| `reg_threshold`, `retiming`, `use_io_insertion`, `pack_mode` | not registered |

### 4.9 The 35 strategy-JSON-only parameters are NOT registered — `set_strategy` is a no-op

`<repo>/references/vendor/安路科技_TD_技术文档/strategies/official_strategy_ph1.json` / `official_strategy_ph2.json` define 13 strategies
per family (192 `{step,param,val}` rows). Schema `[VERBATIM structure]`:

```json
"<StrategyName>": {
    "description": "<English prose>",
    "is_syn": "syn" | "phy",
    "params": [ { "step": "<step>", "param": "<name>", "val": "<value>" }, ... ]
}
```

35 parameter names appear in those files that are absent from SWUG105's tables — and
**measurement shows none of them is a registered parameter of TD 6.2.1's `set_param` database:**

```tcl
get_param place aggressive_opt         ;# rc=1
get_param place aggr_neighbor_dist     ;# rc=1
get_param place enhanced_beeline_opt   ;# rc=1
get_param place timing_driven_mode     ;# rc=1
get_param place split_data_from_clock  ;# rc=1
get_param place shifter_opt            ;# rc=1
get_param place crit_path_opt          ;# rc=1
```

`set_strategy` **requires `-run`** and had **no observable effect** in single-run mode:

```tcl
set_strategy phy_1 TimingHigh         ;# rc=1 (error - no -run)
set_strategy TimingHigh               ;# rc=1 (error - no -run)
set_strategy -run phy_1 TimingHigh    ;# rc=0 (accepted)
```

After the accepted call, every `TimingHigh` parameter was still at its old value:

| param | `TimingHigh` says | measured after applying | changed? |
|---|---|---|---|
| `place effort` | `high` | `medium` | **no** |
| `place opt_timing` | `high` | `medium` | **no** |
| `place logic_level_opt` | `on` | `off` | **no** |
| `place post_place_opt` | `high` | `auto` | **no** |
| `route post_route_opt` | `high` | `auto` | **no** |

**Conclusion:** the strategy parameters are consumed by the run engine through a mechanism not
reachable via `set_param`/`get_param` in single-run mode. Whether `set_strategy` takes effect
inside a **multi-run** project (`open_project` *without* `-single_run`) was **not verified** —
that is the one open question here. The strategy *names* and their documented effects are still
useful (see §6); just do not assume the parameters are settable by hand.

The witnessed values, for reference (these are the only values ever seen; no ranges or defaults
are published anywhere):

**Syn-side:** `gate add_map_lut_struct` (`on`,`high`), `gate multi_thread_mapping` (`partition`),
`gate mapper_lut_delay` (`1600`,`2200` ph1; `1200` ph2), `gate merge_tiny_lut` (`on`),
`gate opt_eram_const` (`on`), `gate eram_cascade_addr` (`on`, ph2 only),
`rtl shifter_style` (`shifter_reg`), `rtl min_shifter_len` (`2`), `rtl min_shifter_size` (`6`),
`rtl resource_sharing` (`auto`), `rtl cascade_uram` (`on`, ph2 only).

**Phy-side (`place` unless noted):** `aggressive_opt` (`20`,`21`), `aggr_neighbor_dist` (`5`),
`enhanced_beeline_opt` (`2`,`3` ph1; `2` ph2), `timing_driven_mode` (`on`), `shifter_opt` (`on`),
`crit_path_opt` (`on`), `split_data_from_clock` (`on`), `ofv` (`70`),
`opt_max_density` (`50`), `target_density` (`0.6`,`0.7`), `target_density_pp` (`0.7`,`0.75`),
`enhanced_gp` (`on`), `non_crit_opt` (`on`), `enable_congestion_recovery` (`on`),
`dram_area_factor` (`12`, ph2 only), `enlarge_macro_net_weight` (`on`),
`net_dup_with_macro_loads` (`on`), `mcflg_eram_anchor_driven` (`medium`),
`mcflg_uram_anchor_driven` (`medium`, ph2 only), `gr_update` (`minimum`), `remap_opt` (`off`),
`opt_speedup` (`3`), `dp_speedup` (`on`), `route opt_level` (`5`),
`route postrt_opt_extra_round` (`4`).

### 4.10 SWUG105's Tables 4-1 / 4-2 as transcribed `[RECONSTRUCTED TABLE]`

Kept for traceability: this is what the PDF *says*, so you can see where it diverges. **§4.1
supersedes both tables.**

> Extraction defect: both tables emerged as a flat one-cell-per-line dump with row boundaries
> lost; rows were re-paired positionally. Two value cells were split across extracted lines
> (`infer_fsm`: `off/manual/auto/one_hot/` + `sequential`; `map_mode`: `auto/area_prior/` +
> `logic_level_prior/balance_explore`) and were re-joined. In Table 4-2 the param name extracted
> as `macro_ performance` **with a space** (text-layer wrap artefact), the `macro_performance`
> value cell split across four lines, and the step cell of the last row (`timing`) is missing
> entirely.

**Table 4-1 (Syn)** — step / param / value / default:

| step (as printed) | param | value | default |
|---|---|---|---|
| `flow` | `message` | `standard`/`simple`/`verbose` | `standard` |
| `flow` | `qor_monitor` | `on`/`off` | `on` |
| `flow` | `syn_ip_flow` | `off`/`ip` | `off` |
| `flow` | `thread` | `auto`/`2`/`4`/`8`/`16`/`32` | `auto` |
| `rtl` (Read Design) | `default_reg_initial` | `auto`/`0`/`1` | `auto` |
| `rtl` (Read Design) | `hdl_warning_level` | `normal`/`simple` | `normal` |
| `rtl` (Optimize RTL) | `fix_undriven` | `0`/`1`/`auto` | `0` |
| `rtl` (Optimize RTL) | `infer_fsm` | `off`/`manual`/`auto`/`one_hot`/`sequential` | `off` ← **wrong** |
| `rtl` (Optimize RTL) | `infer_rom` | `on`/`off` | `on` |
| `rtl` (Optimize RTL) | `infer_shifter` | `on`/`off` | `on` |
| `rtl` (Optimize RTL) | `keep_hierarchy` | `auto`/`flatten`/`all` | `auto` |
| `rtl` (Optimize RTL) | `merge_equal` | `on`/`off` | `on` |
| `rtl` (Optimize RTL) | `min_control_set` | `1`–`999999` (int) | `8` |
| `rtl` (Optimize RTL) | `min_ripple_len` | `auto`/`0`–`999999` (int) | `auto` |
| `rtl` (Optimize RTL) | `seq_syn` | `on`/`off` | `on` |
| `gate` | `eram_cascade_height` | `auto`/`0`–`16` | `auto` |
| `gate` | `map_mode` | `auto`/`area_prior`/`logic_level_prior`/`balance_explore` | `auto` |
| `gate` | `map_strategy` | `1`/`2`/`3`/`4`/`5` | `1` |
| `gate` | `pack_effort` | `medium`/`high`/`low` | `medium` |
| `gate` | `pack_seq_in_io` | `auto`/`on`/`off` | `auto` |
| `gate` | `report` | `standard`/`simple`/`verbose` | `standard` |

**Table 4-2 (Phy)** — step / param / value / default:

| step (as printed) | param | value | default |
|---|---|---|---|
| `flow` | `enable_seed` | `off`/`on` | `off` |
| `flow` | `hfn_to_clock` | `1000000000` or less | `1000000000` |
| `flow` | `speedup_effort` | `0`/`1`/`2`/`3`/`4`/`5` | `0` |
| `place` | `effort` | `medium`/`high` | `medium` |
| `place` | `hfn_opt_effort` | `medium`/`low`/`high` | `medium` |
| `place` | `logic_level_opt` | `off`/`on` | `off` |
| `place` | `macro_performance` | `auto`/`dsp_wirelength`/`dsp_crit_path`/`ram_wirelength`/`ram_crit_path`/`dsp_ram_wirelength`/`dsp_ram_crit_path`/`macro_congestion` | `auto` |
| `place` | `max_fanout` | `9`–`999999` (int) | `999999` |
| `place` | `opt_timing` | `medium`/`off`/`low`/`high`/`ultra` | `medium` |
| `place` | `pack_mode` | `auto`/`lower_pin_density`/`adaptive_pin_density`/`more_lut_pair` | `auto` ← **not registered** |
| `place` | `post_place_opt` | `auto`/`medium`/`high`/`ultra` | `auto` |
| `place` | `pr_strategy` | PH1 `1`–`11`; PH2 `1`–`5`, `12`–`17` | `1` (ranges unenforced) |
| `route` | `effort` | `normal`/`routability` | `normal` |
| `route` | `fix_hold` | `off`/`on`/`High` (**`High` PH2 only**) | `off` ← **wrong, real default `on`** |
| `route` | `post_route_opt` | `auto`/`medium`/`high`/`ultra`/`off` | `auto` |
| `route` | `timing` | `normal`/`off`/`greedy` | `normal` ← **wrong, real default `on`** |

### 4.11 `report_param` behaviour (measured)

| Form | Output |
|---|---|
| `report_param` | only parameters whose **setting differs from default**; 3-column table; on a fully-default project it prints **nothing at all** |
| `report_param -stage <step>` | same, restricted to one stage |
| `report_param -detail` | **all** registered parameters for the selected stage(s), 4 columns (`Parameters \| Settings \| Default Values \| Note`); a `*` in `Note` marks a non-default setting |
| `report_param -detail -file <f>` | same, but the file form has **3 columns — the `Note` column is omitted** |

```tcl
report_param -stage place                          ;# one stage, non-defaults only, to console
report_param -detail                               ;# all stages, all params, to console
report_param -detail -stage place -file p.txt      ;# one stage to file, 3 columns
```

Parse the file form with **3** columns, the console form with **4**.

### 4.12 Parameter-setting scripts (corrected)

```tcl
# --- Project mode, per run ---
set_param -run syn_1 flow qor_monitor on
set_param -run syn_1 gate pack_seq_in_io off
set_param -run phy_1 place pr_strategy 1
set_param -run phy_2 place pr_strategy 2
set_param -run phy_1 flow enable_seed on
set_seed_param -num 6 -init 5 -step 5 -jobs 3

# --- Non-project mode, no -run ---
set_param flow  qor_monitor on
set_param gate  pack_seq_in_io off
set_param place pr_strategy 1
```

Every one of those parameter names is registered. **Do not copy the guide's own examples
verbatim** — they include `set_param rtl reg_threshold 0   ;# GHOST PARAMETER - does nothing; delete this line`, which silently does nothing.


## 5. Parameter effects (from TD User Guide § 9.6)

SWUG105 §4.2.2 explicitly delegates parameter meanings to *TD User Guide* chapter 9.6. That
chapter is the source of this section. "Applicable devices" is as stated there (`ALL` = every
family).

### 5.1 Syn Global (`flow`)

| Param | Devices | Values (first = default) | Effect / advice |
|---|---|---|---|
| `message` | ALL | `standard`, `simple`, `verbose` | log verbosity. `simple` shortens; `verbose` adds optimisation detail. |
| `qor_monitor` | ALL | `on`, `off` | print the `report_qor` performance report automatically at the end of synthesis, placement and routing. |
| `syn_ip_flow` | ALL | `off`, `ip` | `ip` compiles the design into a netlist (stops after Syn Opt, emits `ip.v`) so the sources are hidden and the result can be a submodule of another project. |
| `thread` | ALL | `auto`, `1`, `2`, `4`, `8`, `16`, `32` | max thread count. `auto` = CPU count. Exceeding the CPU count runs at CPU count. |

### 5.2 Read Design — **step `design`**, not `rtl`

**Correction to SWUG105.** SWUG105 labels this group "`rtl` (Read Design)". The measured step
header is **`Print Design Property`** — the real step name is **`design`**, and
`set_param rtl default_reg_initial 0` is not the same as `set_param design default_reg_initial 0`.

| Param | Devices | Values | Effect / advice |
|---|---|---|---|
| `default_reg_initial` | ALL | `auto`, `0`, `1` | initial value of registers that have no explicit initial value: `0`/`1` force it (only for registers without async set); `auto` lets the tool choose whatever optimises better. |
| `hdl_warning_level` | ALL | `normal`, `simple` | `simple` suppresses large numbers of unimportant HDL warnings (e.g. non-synthesizable delays). |

### 5.3 Optimize RTL (`rtl`)

| Param | Devices | Values | Effect / advice |
|---|---|---|---|
| `fix_undriven` | ALL | `0`, `1`, `standard`, `auto` | what to do with pins/nets that have no driver: tie low, tie high, tool-chosen (with multiplexer behaviour matching `0`), or fully automatic. |
| `gated_clock_conversion` | ALL | `off`, `on` | **registered in TD 6.2.1 but completely undocumented in SWUG105.** Convert gated clocks into clock-enable logic. Default `off`. Effect text is not in TD UG § 9.6 either — verify empirically. |
| `infer_fsm` | ALL | `off`, `manual`, `auto`, `one_hot`, `sequential` | FSM inference and encoding. `manual` honours the user's `fsm_encoding` synthesis directive; `auto` infers all FSMs and picks the best encoding (except user-directed ones); `one_hot` / `sequential` force the encoding. **Measured default is `auto`** (SWUG105 says `off`). |
| `infer_rom` | ALL | `on`, `off` | `on` infers ROM as RAM (saves LUTs); `off` implements ROM in LUTs (more LUTs). |
| `infer_shifter` | **PH1, PH2** | `on`, `off` | `on` implements shift registers with the SHIFTER resource (saves DFFs); `off` uses ordinary registers. |
| `keep_hierarchy` | ALL | `auto`, `flatten`, `all` | `auto` flattens everything except `(* keep_hierarchy *)` modules; `flatten` flattens all user modules into the top; `all` preserves all hierarchy. Preserving hierarchy reduces area/timing volatility across code edits but costs area and may worsen timing. **Region/bound constraints need `auto` or `manual`, not `flatten`.** |
| `merge_equal` | ALL | `on`, `off` | merge logically equivalent modules to save area. |
| `min_control_set` | ALL | `1`–`999999` (default `8`) | minimum DFF count for a shared control set (CLK/CE/SET/RESET). Larger ⇒ fewer DFFs share control logic (more LUT area, freer DFF placement). Recommended range **2–32**. Raise if placement is hard; lower if area is too large. |
| `min_ripple_len` | ALL | `auto`, `0`–`999999` | minimum input-vector width for implementing adders/subtracters/comparators with the carry chain. Below the threshold the logic is implemented in LUTs. Raise it when carry chains cause routing difficulty; lower it when a small adder needs the carry chain to meet timing. Override locally with `(* use_ripple *)`. **Recommended 6–32.** |
| `seq_syn` | ALL | `on`, `off` | merge logically equivalent DFFs. Keep `on`. |
| `reg_threshold` | — | — | **GHOST PARAMETER — DOES NOT EXIST.** Used 5× in SWUG105's own recommended examples, but `get_param rtl reg_threshold` → rc=1, it is absent from `report_param -detail`, and absent from the real run logs. `set_param rtl reg_threshold 0   ;# GHOST PARAMETER - does nothing; delete this line` is silently ignored. **Do not use.** |

### 5.4 Optimize Gate (`gate`)

| Param | Devices | Values | Effect / advice |
|---|---|---|---|
| `eram_cascade_height` | PH1, PH2 | `auto`, `0`–`16` | max ERAM cascade length. `auto` = 0 (no cascade) for PH1 and 2 for PH2. PH1 ERAM cascades have high delay — cascade only when necessary and keep the number small. PH2 tolerates larger values (less routing pressure, harder placement). `0`/`1` = no cascade; `>= 2` cascades. |
| `map_mode` | PH1, PH2 | `auto`, `area_prior`, `logic_level_prior`, `balance_explore` | mapping mode for macros and LUTs. `balance_explore` is the high-effort balance mode. |
| `map_strategy` | PH1, PH2 | `1`–`5` (default `1`) | LUT-mapping strategy. Higher = stronger logic-level improvement, at the cost of area and runtime (`5` is markedly slower). |
| `pack_effort` | ALL | `medium`, `high`, `low` | how tightly to pack DFFs+LUTs into SLICEs. `high` uses fewer SLICEs but can cause local routing congestion; `low` uses more SLICEs but eases congestion. |
| `pack_seq_in_io` | ALL | `auto`, `on`, `off` | `on` maps DFFs into the IO pad. EG/EF/SF default to packing DFFs into IO; PH only packs DFFs that must go there. `on` improves IO-path timing **but if IO locations are unconstrained they are placed randomly, which can make timing worse.** |
| `report` | ALL | `standard`, `simple`, `verbose` | area-report verbosity. |

### 5.5 Phy Global (`flow`)

| Param | Devices | Values | Effect / advice |
|---|---|---|---|
| `enable_seed` | ALL | `off`, `on` | `on` runs placement with multiple seeds, exploring several place-and-route results. Improves the chance of better timing; increases server load. Configure with `set_seed_param` first. |
| `hfn_to_clock` | PH1A60, PH1A90, PH1A180, PH1A400, PH2 | `1000000000` (or lower) | nets with fanout above this value **and** sufficient slack are routed using clock-tree resources. Use when clock-tree resources are not tight. |
| `speedup_effort` | PH1, PH2 | `0`–`5` (default `0`) | runtime optimisation for place & route. Higher = faster, but timing results may degrade. |

### 5.6 Optimize Placement (`place`)

| Param | Devices | Values | Effect / advice |
|---|---|---|---|
| `effort` | ALL | `medium`, `high` | net-length optimisation effort. Higher = longer runtime. |
| `hfn_opt_effort` | ALL | `medium`, `low`, `high` | how aggressively to split high-fanout nets. Higher = finer splitting, more resources. |
| `logic_level_opt` | PH1, PH2 | `off`, `on` | optimise logic levels **before** placement. Turn on when logic levels are too deep; costs area and runtime. |
| `macro_performance` | ALL | `auto`, `dsp_wirelength`, `dsp_crit_path`, `ram_wirelength`, `ram_crit_path`, `dsp_ram_wirelength`, `dsp_ram_crit_path`, `macro_congestion` | optimisation target for DSP/ERAM/URAM placement. Use a wirelength option when macro utilisation is high; a `crit_path` option when critical paths involve macros; `macro_congestion` to reduce DSP/RAM-induced congestion. |
| `max_fanout` | ALL | `9`–`999999` (default `999999` = disabled) | global fanout threshold. Nets above it are split into multiple nets (CLK excluded). Splitting costs resources. |
| `opt_timing` | PH1, PH2 | `medium`, `off`, `low`, `high`, `ultra` | in-placement timing optimisation effort. Raise when post-place timing is poor. |
| `pack_mode` | PH2 | `auto`, `lower_pin_density`, `adaptive_pin_density`, `more_lut_pair` | packing strategy for hard-to-route designs (lower/adaptive pin density) or LUT-heavy designs (`more_lut_pair`). **NOT REGISTERED in TD 6.2.1 for PH1A** — `get_param place pack_mode` → error. TD UG § 9.6 documents it for PH2 only. Prefer `gate pack_effort`. |
| `post_place_opt` | ALL | `auto`, `medium`, `high`, `ultra` | post-placement timing optimisation effort. Higher = better timing/congestion, longer runtime. |
| `pr_strategy` | ALL | PH1: `1`–`11`; PH2: `1`–`5`, `12`–`17` (default `1`) | placement/routing strategy. `1` default; `2`–`4` congestion relief; `5`–`9` timing optimisation; `10`–`17` progressively stronger optimisation measures. **For designs that do not converge, try successive strategies — stronger measures raise the chance of fixing timing/congestion but cost runtime.** |
| `preplace_floorplan` | PH1, PH2 | `off`, `on` | use floorplan to guide placement. Turn on when you want hierarchy-driven placement; reduces result volatility across design edits. |

### 5.7 Optimize Routing (`route`)

| Param | Devices | Values | Effect / advice |
|---|---|---|---|
| `effort` | ALL | `normal`, `routability` | `routability` tries more optimisation passes to avoid congestion, at the cost of runtime. |
| `fix_hold` | ALL | `off`, `on`, `High` (**`High` PH2 only**) | post-route hold-violation fixing. **Measured default is `on`** (SWUG105 says `off`). Use `on` (or `High`) when hold must be fixed after routing. **Expensive if the hold violation comes from bad constraints or a bad design — fix the constraint first.** `hold_fix_iteration` (default `5`) controls the iteration count and is undocumented in SWUG105. |
| `post_route_opt` | PH1, PH2 | `auto`, `medium`, `high`, `ultra`, `off` | post-route timing optimisation effort. Higher = better, slower. |
| `timing` | ALL | `normal`, `off`, `greedy` | `normal` stops once setup converges. `off` ignores timing to route fast. `greedy` maximises post-route slack, potentially very slow. **Measured default is `on` — a value SWUG105's list does not contain. Treat the value list as unreliable.** |

### 5.8 Generate Bitstream parameters

**Correction to SWUG105.** The `bitgen` `set_param` step is **not** empty: `report_param -detail`
shows seven registered parameters — `bin`, `compress`, `gen_mask`, `max_stream`, `time_info`,
`unused_io_status`, `version` (see §4.1). SWUG105 omits the whole group.

There are therefore **two different mechanisms** for configuring bitstream generation:

```tcl
set_param bitgen gen_mask off           ;# the 7 registered set_param bitgen parameters
bitgen -bit top.bit -gen_mask           ;# the equivalent bitgen COMMAND option
bitgen -bit top.bit -g {security:1}     ;# a GUI "Generate Bitstream Properties" option
```

The `-g` catalogue below is the GUI `Generate Bitstream Properties` option set; pass it as
`bitgen -g {param:value ...}` with names/case matching the GUI **exactly**. Several of these names
(`security`, `mclk_freq`, `boot_mode`, …) do **not** overlap the seven `set_param bitgen`
parameters.

**General Option** — `bin` (`off`/`on`), `bin_compress` (`off`/`on`, emits `*.huf`/`*.ttf`),
`header` (`off`/`on`), `id` (`off`/`on`), `gen_mask` (`off`/`on`), `max_stream` (`on`/`off`,
PH1/PH2), `seu_all` (`off`/`on`, PH1A100/PH1A400), `time_info` (`on`/`off`),
`unused_io_status` (`pullup`/`pulldown`/`keeper`/`none`), `version` (`0x00`–`0xff`),
`compress` (`off`/`on`, PH1/PH2).

**Control Option** — `security` (`0` allow JTAG/slave-PCM readback, `1` forbid),
`stateholdio` (`off`/`on`, PH2), `mclk_freq` (PH1: `2MHz`/`3MHz`/`5MHz`/`11MHz`/`22MHz`/`33MHz`;
PH2 adds `44MHz` and `EXT_CLK`), `pcm_reconfig` (`0`/`1`, PH1), `cascade_mode`
(`normal`/`bypass`/`flow through`), `osc_clk_disable` (`0`/`1`, PH1A60/90/180/400, PH2).

**Startup Option** — `pll1_lock_wait` (`0`/`1`), `pll0_lock_wait` (`0`/`1`), `done_cycle`,
`goe_cycle`, `gsrn_cycle`, `gwe_cycle` (PH1 3-bit, PH2 4-bit phase codes; defaults differ per
family), `mult_boot_en` (`0`/`1`; PH1 default `1`, PH2 default `0`).

**Attribute Option** — `boot_mode` (`mspix1`/`mspix2`/`mspix4`, PH1/PH2).

```tcl
bitgen -bit top.bit -g {security:1}
bitgen -bit top.bit -g {mclk_freq:5MHz boot_mode:mspix4}
```

---

## 6. Strategy packages

> **MEASURED WARNING — read §4.9 first.** `set_strategy` **requires `-run`** and had **no
> observable effect** in single-run mode: after `set_strategy -run phy_1 TimingHigh` was accepted
> (rc=0), all five `TimingHigh` parameters were still at their old values, and all 35
> strategy-only parameters returned rc=1 from `get_param`. Whether it works in **multi-run** mode
> was not verified. Treat the strategy packages below as **documented intent**, and if you need a
> strategy's effect in a script, set the parameters explicitly (§4.1) instead.

TD UG § 9.7 catalogues the built-in strategy packages. Strategy names are **verbatim** and are what
the strategy JSON keys hold (13 per family, `<repo>/references/vendor/安路科技_TD_技术文档/strategies/official_strategy_ph{1,2}.json`).

| Flow | Strategy | What it does | Cost / limitation |
|---|---|---|---|
| Syn | `Default_Synthesis_Strategy` | software default optimisation | — |
| Syn | `AdderChainThresholdHigh` | raises the infer-adder-chain threshold, fewer adder chains, helps logic level when short adder chains cascade | area increases; LUT-implemented adders may not optimise logic level |
| Syn | `AreaOptimizeMedium` | more area-reduction attempts while retaining timing and logic-level quality | runtime increases noticeably |
| Syn | `AreaOptimizeHigh` | further area reduction, with no logic-level protection | runtime increases more; logic level may rise |
| Syn | `LogicLevelOptimize` | optimisation weighted toward reducing logic level | area increases |
| Syn | `MacroOptimize` | more shifter use, stronger eram/uram/dsp cascading, stronger eram merging — reduces routing-resource demand | on large devices may worsen placement, creating long wires |
| Syn | `RAMOptimize` | stronger ERAM cascading and merging | may worsen placement, creating long wires |
| Phy | `Default_PhysicalDesign_Strategy` | software default optimisation | — |
| Phy | `CongestionMedium` | timing optimisation plus density control and HFN reduction | may hurt placement timing; congestion control can be insufficient |
| Phy | `CongestionHigh` | medium plus reduced dram/macro surround density, aimed at large devices | may hurt placement timing; congestion control can be insufficient |
| Phy | `MacroTiming` | shortens macro nets and optimises macro placement to strongly improve macro-related paths | placement runtime increases; local congestion may fluctuate so routing is not guaranteed better |
| Phy | `RuntimeOptimize` | fewer place/route steps to shorten total flow runtime; **does not pursue timing** | timing will most likely not converge — "仅用作布线尝试", a routing smoke test only |
| Phy | `TimingMedium` | adds commonly useful timing-improving parameters | runtime increases somewhat |
| Phy | `TimingHigh` | medium plus stronger shifter handling and WNS-path optimisation, plus extra post-route optimisation | runtime increases further |
| Phy | `TimingUltra` | high plus stronger ERAM/long-path placement optimisation and maximum post-route effort | both placement and routing times increase, routing especially |

`set_strategy` argument forms measured: `set_strategy phy_1 TimingHigh` → **rc=1** (needs `-run`);
`set_strategy TimingHigh` → **rc=1**; `set_strategy -run phy_1 TimingHigh` → **rc=0** but no
observable parameter change.

---

## 7. Cross-check results and known documentation defects

### 7.1 Commands SWUG105 documents that are ABSENT from the live 740 list

**Zero.** Every command SWUG105 documents in detail exists. The apparent misses are prose typos:

| PDF text | Real command | Context |
|---|---|---|
| `drive_clocks` | `derive_clocks` | §4.4.14 prose |
| `optmize_rtl` | `optimize_rtl` | §3.2.1 prose |
| `create_generation_clock` | `create_generated_clock` | §4.4.13 prose (headings/examples are correct) |
| `get_port` | `get_ports` | TD UG § 9.2 example |
| `set_clock_group` | `set_clock_groups` | TD UG § 9.2 f) |
| `set_clock_domain_timing` | `set_cross_domain_timing` | TD UG § 9.2 h) |

TD UG § 9.2 also documents `remove_clock_latency` and `remove_clock_uncertainty` — **neither
exists in TD 6.2.1.** Do not use them.

### 7.2 Flow-stage-critical commands SWUG105 never documents **[LIVE-ONLY]**

Grouped by how much the gap hurts.

**A. Used by the tool's own shipped flow — highest priority**

`commit_param`, `flow_status`, `flow_continue_check`, `report_timing_status`,
`export_flow_status`, `export_flow_script`, `report_clock_utilization`, `load_run_param`,
`clear_inst_adc`, `clear_sdc -user`, `insert_debugger`, `setup_debugger`,
`import_chipprobe_config`, `compile_probe`, `export_bitgen_param`, `export_sdc_target`,
`clear_prj_params`, `open_project -noanalyze`.

**B. Project/run management** — `save_project_as`, `close_run`, `delete_runs`, `copy_run`,
`set_strategy`, `select_seed`, `stop_seed`, `set_device`, `clear_design`, `remove_source`,
`export_files`, `add_define`, `add_directive`, `clean_project`, `zip_project`,
`create_and_launch_auto_rerun`.

`enable_seed` is **not** a command — it is only a `flow`-step `set_param` parameter.

**C. Source/constraint** — `read_verilog`, `clear_user_sdc`, `write_hdl`, `export_sdc`,
`write_csv`, `generate_simulation`, `export_adc`, `import_cswi`, `import_paramlib`,
`export_constrSet`.

**D. Stepwise** — `preprocess`, `analyze`, `direct_legalization`, `create_syn_ip`, `initplace`,
`legalization`, `reanalyze`, `repack`, `dp_fix_hold`, `eco_lock_design`, `fix_hold_move`,
`fix_timing`, `mpnr_route_net`, `multi_try_route`, `imux_opt`, `imux_route`, `tune_congo`,
`spreading`.

**E. Reporting** — `report_timing`, `report_ram_utilization`, `report_route_status`,
`report_placement_status`, `report_design_status`, `report_congestion`,
`report_routing_resource`, `report_path_margin`, `report_async_reg`, `report_dangling`,
`report_design_cell_num`, `report_wirelength`, `report_timing_correlation`, `report_io`,
`report_bounds`, `report_imux_utilization`, `report_modules`, `report_pr_critical_paths`,
`print_grid_utilization`, `show_area`, `print_ext_qor`, `write_qor_params`,
`non_default_params`, `ext_qor_script`.

**F. Parameterisation** — `get_param`, `get_config_param`, `get_device_param`,
`set_device_param`, `set_misc_setting`, `set_property`, `get_property`, `reset_property`,
`list_property`, `set_user_params`, `set_strategy`, `non_default_params`, `export_params`,
`import_paramlib`, `clear_prj_params`.

### 7.3 Other unresolved discrepancies

| Item | Status |
|---|---|
| `phys_opt -effort` values `medium` (SWUG105) vs `middle` (shipped help DB) | unresolved; both spellings appear in shipped material |
| `phys_opt -post_route` (SWUG105, mandatory) vs `-post_place` (help DB) | unresolved |
| `report_nets -pin_output_limit` (SWUG105) vs `-pin_display_limit` (help DB) | unresolved |
| `report_analysis -congesiton` | misspelled in SWUG105; reproduced verbatim, not corrected |
| `import_db` / `export_db` deprecated per DRC `USR-8017`/`USR-8018`, which recommend `import_design`/`export_design` | **`import_design` and `export_design` are not in the live 740 list.** DRC text is stale; keep using `import_db`/`export_db`. |
| `add_dir` syntax line in SWUG105 is written `add_files [-r] <dir>` | heading + example both use `add_dir`; `add_dir` confirmed live |
| `read_hdl`'s own example uses `read_verilog` and braces where the prose demands double quotes | doc inconsistency; both commands are live |
| `macro_performance` extracted as `macro_ performance` | text-layer wrap artefact; real name has no space (confirmed in the strategy JSONs) |
| `commit_param` uses `-step design` while `set_param` uses `rtl` for the same conceptual stage | **partly false** — measured: `set_param` also uses **`design`** for `default_reg_initial`/`hdl_warning_level`. Both commands use `design`; SWUG105's "`rtl` (Read Design)" label is the error. `commit_param` and `set_param` are still not interchangeable. |
| SWUG105 default `route fix_hold off` / `rtl infer_fsm off` / `route timing normal` | **all three measured defaults differ** (`on` / `auto` / `on`). See §4.7. |
| SWUG105 `place pack_mode` | **not a registered parameter.** See §4.5. |
| SWUG105 `rtl reg_threshold` | **ghost parameter.** See §4.5. |
| SWUG105 "no `set_param bitgen` parameters" | **false** — 7 registered. See §4.6. |
| `tool` sub-step names in `DefaultFlow.tcl` (`read_design`, `opt_rtl`, `opt_gate`, `opt_place`, `opt_route`) | run-step names, **not** `set_param` step names |

---

## 8. Gaps a future agent should know

* **⚠ `set_param` validates nothing.** A typo in a parameter name or value is a silent no-op
  (rc=0, no warning, no effect). **Always gate parameter assignment behind
  `catch { get_param <step> <param> }`** — `get_param`'s rc is the only reliable existence test.
  See §4.2.
* **`reg_threshold` is a ghost.** It appears in SWUG105's *own recommended example scripts* five
  times and does not exist. If you copy examples from that guide verbatim you will silently lose
  an optimisation step. See §4.5.
* **The 50-parameter set in §4.1 is complete and measured.** If a parameter name is not in that
  table, it is not registered. There is no third source of parameters.
* **`timing` and `sim` are valid `set_param` step names with empty parameter sets.** They are not
  typos and not undocumented groups — they simply have no parameters.
* **The 35 strategy-JSON-only parameters are not registered.** They are consumed by the run engine
  by some other route. `set_strategy -run <run> <name>` was accepted but changed nothing in
  single-run mode; **multi-run behaviour was not verified.** To be certain a strategy's effect is
  applied, set the individual registered parameters explicitly.
* **`select_seed` / `stop_seed` / `copy_run` argument forms are not documented.** Marked
  `[RECONSTRUCTED]`.
* **The `-g` bitgen option catalogue** comes from TD UG § 9.6's GUI tables; the exact
  `param:value` spellings for the *startup* options (`done_cycle`, `goe_cycle`, `gsrn_cycle`,
  `gwe_cycle`) are bit-pattern strings whose per-family defaults differ. Always copy the value
  from the GUI's own dropdown rather than guessing. Note the overlap with the 7 registered
  `set_param bitgen` parameters (§4.1) — `bin`, `compress`, `gen_mask`, `max_stream`,
  `time_info`, `unused_io_status`, `version` exist in **both** forms.
* **`td -nogui` does not exist as a documented entry point.** Use `td_commands_prompt.exe`
  (Windows) or `td.sh` (Linux). **Verified working headless invocation:**
  `td_commands_prompt.exe -nogui <script.tcl>` — the TCL file is a **positional argument**;
  `-source <file>` does **not** work.
* **Console capture is unreliable.** For `query_current_package` and similar
  print-don't-return commands, either let them print into the log or have the TCL script
  redirect stdout; `set x [cmd]` yields an empty string. Piping a command into
  `td_commands_prompt.exe -nogui` on stdin also loses output; pass a script file instead.
* **Safest way to get the truth about this toolchain** is to ask the tool, not the PDFs:
  `<root>\bin\td_commands_prompt.exe -nogui <probe.tcl>` where `probe.tcl` calls
  `report_param -detail`, `get_param`, `help <cmd>`, or writes its results to a file with
  `set f [open out.txt w]; puts $f ...; close $f`. Absolute output paths inside TCL scripts can
  be rejected — `cd` to the target directory (or use the process working directory) and write a
  bare relative filename.
