# Anlogic TD 6.2.1 — Debug, Probe & Programming Reference

Debug/probe insertion, JTAG debug access, the BitWizard flash-file tool, device operation modes
and the Download dialog, programming/download TCL commands, the OneCable requirement, and the
Encrypt Tool.

Toolchain under test: **Tang Dynasty V6.2.168116**, install root
`C:/Tools/Anlogic/TD_6.2.168116` (build stamp `16:32:07 Jun 12 2025`).

Companion reference files: `flow-and-commands.md` (project/run/step/report/parameter reference),
`timing-constraints.md` (ADC + SDC), `timing-analysis.md` (timing reports),
`device-database.md` (family/package/speed/resource tables), `ip-and-libraries.md` (IP and
primitive instantiation).

> **Evidence grading used throughout.** SWUG111 contains **zero TCL command names** — it is
> entirely GUI. Likewise SWUG110 documents `bw.exe` but never mentions `bw_commands_prompt.exe`.
> The command syntax in this file therefore comes from the **live interpreter** rather than the
> PDFs, and every statement is tagged:
>
> | Grade | Meaning |
> |---|---|
> | `[HELP]` | verbatim from the live interpreter's own usage table (`help` with no arguments in `td_commands_prompt.exe`) — this is the tool's own grammar |
> | `[PROBE]` | observed by running the command and reading the resulting `XXX-nnnn ERROR:` message |
> | `[PDF:SWUGnnn §x]` | stated in the named PDF section |
> | `[RECONSTRUCTED]` | assembled from surrounding evidence; the raw evidence is quoted |
> | `[NOT DOCUMENTED]` | the name is in the live 740-command list but appears in no PDF and no usage table — unsupported |
>
> **Unsafe commands:** `test_mark_debug`, `gen_bsdl` and `read_cwc_data` **crash the interpreter**
> (minidump) when called with no arguments. Do not probe them for arity.

---

## 0. Sources, evidence grades and how to run TCL

### 0.1 Source inventory

| ID | Document / artefact | Usable content? |
|---|---|---|
| SWUG111 | `TangDynasty 调试工具使用指南` (Debug Tools User Guide, v1.0 2024-11) | **Yes** — but it is 100 % GUI. Contains **zero** TCL command names. |
| SWUG110 | `TangDynasty BitWizard 使用指南` (v1.1 2024-12) | **Yes** — dense and clean. |
| SWUG113 | `TangDynasty Encrypt Tool User Guide` (v1.0 2024-10) | **Yes** — short but clean; one code block lost to an image. |
| UG009 | `OneCable1.0 用户使用说明` (v1.3 2024-10) | **Yes** — clean; one command line lost to an image. |
| — | `td_commands_all.txt` (740 names, live `info commands`) | Authoritative name list. |
| — | `help` dump from the live interpreter | **Authoritative argument syntax** (see §0.2). |
| — | `config.json`, `cpld_flash.json` | Authoritative machine-readable config. |
| — | SWUG105 TCL Command User Guide | Used for `bitgen` (§5.1), for how to invoke the TCL shells (§0.3) and for the device-db appendix (§4.5). It documents **no** programming, flash, efuse or debug command. |
| — | TD_User_Guide_V6.2 | Used for ChipProbe GUI (§1.7), error codes, Generate-Bitstream options. |

### 0.2 Evidence grades used in this document

Every syntax statement below carries one of these grades. Nothing is invented.

| Grade | Meaning |
|---|---|
| **[HELP]** | Copied verbatim from the live interpreter's own usage table (`help` in `td_commands_prompt.exe`, TD 6.2.168116). This is the tool's own grammar. |
| **[PROBE]** | Observed by actually running the command in the live interpreter and reading the resulting `XXX-nnnn ERROR:` message. Raw messages are quoted. |
| **[PDF:SWUGnnn §x]** | Stated in the named PDF section. |
| **[RECONSTRUCTED]** | Not directly stated anywhere; assembled from surrounding evidence. The raw evidence is quoted. |
| **[NOT DOCUMENTED]** | The name exists in the live 740-command list but appears in no PDF and in no usage table. Any use is unsupported. |

### 0.3 How to run TCL

```powershell
# Batch: script path is the single positional argument; "-h" is NOT an option.
& "C:/Tools/Anlogic/TD_6.2.168116\bin\td_commands_prompt.exe" -nogui E:/work/script.tcl

# Interactive shell (prompt is "td > ")
& "C:/Tools/Anlogic/TD_6.2.168116\bin\td_commands_prompt.exe"
```

* Windows TD CMD window: `Start → All Programs → td_commands_prompt` [PDF:SWUG105 §2.2.1]
* Linux: `/td_install_dir/td.sh` (interactive) or `/td_install_dir/td.sh demo.tcl` [PDF:SWUG105 §2.2.2]
* In the GUI, the **Console** window runs the same commands — but *stage-gated*: after
  `open_run phy_1` you may not run Syn-stage step commands such as
  `elaborate` / `optimize_rtl` / `optimize_gate` [PDF:SWUG105 §2.1].
* Passing `-h` to the executable is misinterpreted as a file name:
  `couldn't read file "-h": no such file or directory` [PROBE]. There are no
  command-line switches on `td_commands_prompt.exe`.
* Getting the tool's own grammar: run `help` with **no arguments** in the
  interpreter. It prints one `USR-1002 :` usage line per documented command.
  `help <command>` prints the *same* full list — it does **not** filter, and
  `<command> -help` prints nothing in command-line mode [PROBE].

---

## 1. Debug / probe flow

### 1.1 What actually exists

Two distinct debug instruments, plus a source-level marker:

| Instrument | Mechanism | TCL family |
|---|---|---|
| **ChipWatcher (CWC)** | Logic analyser inside the FPGA; samples internal nets into block RAM, read back over JTAG. No external equipment. [PDF:SWUG111 §2.1] | `insert_debugger`, `setup_debugger`, `compile_watcher`, `config_chipwatcher`, `export_chipwatcher`, `report_cwc_status`, `mark_debug`, `unmark_debug`, `debug_mode`, `debug_deskew`, `add_watcher_node` |
| **ChipProbe** | Routes internal signals out to **spare I/O pins** so an oscilloscope/logic analyser can observe them. Design is not changed functionally. [TD_User_Guide_V6.2 §8.5] | `add_probe`, `delete_probe`, `enable_probe`, `disable_probe`, `compile_probe`, `import_chipprobe_config`, `export_chipprobe_config` |
| **Mark Debug** | `MARK_DEBUG` attribute in RTL; the tool auto-assigns each marked signal to a ChipWatcher instance keyed on its driving clock. [PDF:SWUG111 §2.2.2] | `mark_debug`, `unmark_debug`, `test_mark_debug` |

> **Important negative finding.** SWUG111 — the document the task names as the
> source for the probe TCL flow — **contains no TCL at all**. A full-text search
> for `insert_debugger|add_probe|delete_probe|enable_probe|disable_probe|
> import_chipprobe_config|export_chipprobe_config|compile_probe|setup_debugger|
> create_watcher|compile_watcher|config_chipwatcher|export_chipwatcher|
> add_watcher_node|mark_debug|unmark_debug|test_mark_debug|debug_mode|
> debug_deskew` across **all** extracted PDFs returns **zero** matches. Every
> command syntax in §1.2–§1.4 therefore comes from the live interpreter's own
> usage table **[HELP]** and from runtime probing **[PROBE]**, not from a PDF.

### 1.2 ChipProbe TCL commands

| Command | Syntax **[HELP]** | Stage | Example |
|---|---|---|---|
| `add_probe` | `add_probe -h -help -src <string> -pin <string> -loc <string> -reg -clk <string> -rst <string>` | After the design is loaded (post `read_design`/`optimize_gate`); needs a resolved netlist before `compile_probe` | `add_probe -src {u_top/state_cnt[3:0]} -pin {probe0[3:0]} -loc {A10 A11 A12 A13} -reg -clk {sys_clk}` |
| `delete_probe` | `delete_probe -h -help probe_name` | Any time before `compile_probe` | `delete_probe probe0` |
| `enable_probe` | `enable_probe -h -help probe_name` | Any time before `compile_probe` | `enable_probe probe0` |
| `disable_probe` | `disable_probe -h -help probe_name` | Any time before `compile_probe` | `disable_probe probe0` |
| `compile_probe` | `compile_probe -h -help` | After ≥1 enabled probe exists; before place & route | `compile_probe` |
| `import_chipprobe_config` | `import_chipprobe_config -h -help cfg_file` | Before/at probe setup | `import_chipprobe_config E:/work/probe.cpc` |
| `export_chipprobe_config` | `export_chipprobe_config -h -help cfg_file` | After probe setup | `export_chipprobe_config E:/work/probe.cpc` |

**[PROBE] raw evidence**

```
td > compile_probe
KIT-1003 : compile_probe:  no probe has been added.

td > import_chipprobe_config x
KIT-8211 ERROR: Please specify a cpc file(*.cpc).

td > export_chipprobe_config x
KIT-8211 ERROR: Please specify a cpc file(*.cpc).
```

`KIT-8211` fixes the ChipProbe configuration file extension: **`.cpc`**.

Argument semantics [RECONSTRUCTED from the option names plus TD_User_Guide_V6.2 §8.5,
which describes the matching GUI fields]:

| Option | GUI counterpart | Meaning |
|---|---|---|
| `-src <net>` | *Source node name* | Internal net to bring out |
| `-pin <name>` | probe entry name | Name of the probe |
| `-loc <site>` | *Pin Location* | Output pad site (package PE name, e.g. `A10`) |
| `-reg` | "使用 register 来锁存" | Insert a register on the exported signal |
| `-clk <net>` | *Clock signal* | Clock for that register |
| `-rst <net>` | *Reset signal* | Reset for that register |

Raw text backing the reconstruction (TD_User_Guide_V6.2 §8.5, page 201):
> "5. 添加完后，给内部信号选择一个输出引脚。若需要使用register 来锁存引出的内部信号，
> 则需要选择一个Clock signal，也可为其添加一个Reset signal … 用户还可在Pin Location
> 处通过右键Change Location 改变输出引脚。勾选Enabled 下面的小方框可激活某一个内部信号"

GUI entry point: `Tools → Debug Tools → ChipProbe`; only signals whose filter type is
**Probe** can be exported; after setup TD demands **Recompile Bitgen**
[TD_User_Guide_V6.2 §8.5]. Relevant error codes:

| Code | Text | Meaning |
|---|---|---|
| `KIT-8001` | 获取逻辑BRAM 列表失败 | bit/BID/cable mismatch |
| `KIT-8203` | ChipProbe 所选择的IO 位置已经被占用 | pad taken (dedicated I/O, ADC-file location, or LVDS pair) |
| `KIT-8207` | ChipProbe 所要添加的Probe 名字已经存在 | duplicate probe name |
| `GUI-8305` | chipprobe 编译失败 | check warnings preceding the error |
| `GUI-8308` | 增加probe 失败 | probe does not exist |

### 1.3 ChipWatcher TCL commands

| Command | Syntax **[HELP]** | Stage in the flow | Example |
|---|---|---|---|
| `insert_debugger` | `insert_debugger dir -cwc <string> -mdn <string> -h -help` | After the design is read and **before** physical optimisation; creates the CWC instrumentation in `dir` | `insert_debugger E:/work/dbg -cwc E:/work/chip.cwc` |
| `setup_debugger` | `setup_debugger dir -help -bit <string>` | **After** bitstream generation (it consumes a `.bit`) | `setup_debugger E:/work/dbg -bit E:/work/top.bit` |
| `compile_watcher` | `compile_watcher -h -help -ucode <string>` | After nodes/instances are configured, before bitgen | `compile_watcher -ucode E:/work/dbg/top.ucode` |
| `config_chipwatcher` | `config_chipwatcher -h -help -sp -sync -dir <string> file_name -init_filter` | After insertion, before `compile_watcher` | `config_chipwatcher -dir E:/work/dbg E:/work/chip.cwc` |
| `export_chipwatcher` | `export_chipwatcher -h -help -sp -dir <string> file_name -add_bid` | After configuration/compile | `export_chipwatcher -dir E:/work/dbg E:/work/out.cwc` |
| `report_cwc_status` | `report_cwc_status -help` | Any time after configuration; read-only | `report_cwc_status` |
| `debug_mode` | usage line reads `debug_mode status` **[HELP]**, but the argument is an **ON/OFF status** **[PROBE]** | Before running the debug flow | `debug_mode on` |
| `debug_deskew` | no usage line — **[NOT DOCUMENTED]**; accepts `-h` silently, accepts no positional args **[PROBE]** | N/A | `debug_deskew` |
| `add_watcher_node` | no usage line — **[NOT DOCUMENTED]**; accepts an argument and returns silently **[PROBE]** | N/A | `add_watcher_node <node>` |
| `test_mark_debug` | no usage line — **[NOT DOCUMENTED]** | **Do not call** | — |
| `create_watcher` | **DOES NOT EXIST.** Not in `td_commands_all.txt`, not in `info commands` of TD 6.2.168116. Dropped from this document. | — | — |

**[PROBE] raw evidence**

```
td > export_chipwatcher x
KIT-1004 : export chip watcher configuration to file(x) successfully.

td > debug_mode status
PRG-8000 ERROR: Unkown ON/OFF status.

td > debug_deskew
RUN-1002 : start command "start_timer"
USR-8001 ERROR: Cannot find top model.
TMR-8007 WARNING: Timing lib is unavailable. Skip timing analysis.

td > test_mark_debug
Oops! coredump minidump-20260911-213209.dmp
```

`test_mark_debug` with zero arguments **crashed the interpreter** (minidump written).
It is an internal, unsupported entry point — treat it as unusable.

`report_cwc_status` prints the whole CWC configuration. Verbatim header of its output:

```
RUN-1001 : print cwc global configuration
RUN-1001 : ----------------------------------------------
RUN-1001 :   Project  |  Chip  |  Cwc File  |  Bit File
RUN-1001 : ----------------------------------------------
RUN-1001 : print net viewer configuration
RUN-1001 : ---------------------------------------------------------------------
RUN-1001 :   Node  |  Type  |  Enabled  |  Trigger Clock  |  Watcher Instances
RUN-1001 : ---------------------------------------------------------------------
RUN-1001 : print chipwatcher instances configuration
RUN-1001 : ------------------------------------------------------------------------------------------------------
RUN-1001 :   Wathcer  |  Sample Depth  |  Clock  |  Input Pipe Stage  |  Output Pipe State  |  Power On trigger
RUN-1001 : ------------------------------------------------------------------------------------------------------
```

(`Wathcer` and `Output Pipe State` are the tool's own typos; `Output Pipe State`
is SWUG111's *Output Pipe Stages*.)

### 1.4 Mark-Debug (source attribute) flow

**Verilog forms — all equivalent, case-insensitive, only at the signal declaration** [PDF:SWUG111 §2.2.2.2]:

```verilog
(*MARK_DEBUG = "TRUE"*) reg test;      // recommended form
reg test; //synthesis MARK_DEBUG = TRUE
reg test; //synthesis MARK_DEBUG = 1
reg test; //synthesis MARK_DEBUG
reg test; /*synthesis MARK_DEBUG = TRUE*/
reg test; /*synthesis MARK_DEBUG = 1*/
reg test; /*synthesis MARK_DEBUG*/
```

**VHDL form** [PDF:SWUG111 §2.2.2.3]:

```vhdl
signal test : std_logic;
attribute MARK_DEBUG : BOOLEAN;
attribute MARK_DEBUG of test_cnt : signal is TRUE;
```

Constraint: input/output ports connected to an **IO Logic Model** must not be
marked — IO Logic cannot be mapped and **Opt Gate** fails [PDF:SWUG111 §2.2.2.3,
§2.2.2.8]. Signals already connected to a ChipWatcher IP, and signals marked in
source, cannot be re-marked from the Mark Debug GUI [PDF:SWUG111 §2.2.2.8].

**TCL equivalents**

| Command | Syntax **[HELP]** | Stage | Example |
|---|---|---|---|
| `mark_debug` | `mark_debug -h -help nets` | After Read Design (nets must resolve in the design) | `mark_debug {u_top/state_cnt u_top/lock}` |
| `unmark_debug` | `unmark_debug -h -help nets` | Same | `unmark_debug {u_top/state_cnt}` |

**[PROBE]** `mark_debug xx` / `unmark_debug xx` on a design without those nets fail
silently (error message empty) — they need real net names from an open design.

### 1.5 Recommended TCL ordering

**[RECONSTRUCTED]** — no PDF states this ordering. Basis: (a) the `[HELP]` usage
lines (only `setup_debugger` consumes a `-bit`; only `insert_debugger` takes an
output *directory*), (b) the SWUG111 GUI flow diagram (Figure 2-1), which reads
`Start → 1.Add ChipWatcher IP in Design / 2.Add Mark Debug in Design → Read Design
→ 3.Add Mark Debug in ChipWatcher / 4.Add signal in ChipWatcher → Optimize Gate →
PHY Opt → Optimize RTL → Download bit file → Trigger and Watch`, and (c) the four
insertion points SWUG111 enumerates: source IP instantiation, source Mark Debug,
post-Read-Design Mark Debug, post-Optimize-Gate insertion.

```tcl
# ---- 1. project + design -------------------------------------------------
import_device ph1_60.db -package PH1A60GEG324 -speed 3
open_project E:/work/demo.al
launch_runs -step opt_gate syn_1        ;# syn: read_design | opt_rtl | opt_gate
wait_run syn_1 -quiet

# ---- 2. probe / watcher insertion (after Read Design, before phy) --------
debug_mode on
insert_debugger E:/work/dbg -cwc E:/work/chip.cwc
mark_debug {u_top/state_cnt u_top/lock}          ;# or MARK_DEBUG in RTL earlier
add_probe -src {u_top/state_cnt[3:0]} -pin {probe0[3:0]} -loc {A10 A11 A12 A13}
compile_probe
config_chipwatcher -dir E:/work/dbg E:/work/chip.cwc
report_cwc_status                                 ;# verify: sample depth / clocks / pipe stages
export_chipwatcher -dir E:/work/dbg E:/work/chip.cwc

# ---- 3. physical implementation -----------------------------------------
compile_watcher -ucode E:/work/dbg/top.ucode
launch_runs -step bitgen phy_1          ;# phy: opt_place | opt_route | bitgen
wait_run phy_1 -quiet

# ---- 4. bind the debugger to the generated bitstream, then download ------
setup_debugger E:/work/dbg -bit E:/work/demo_Runs/best_result/demo.bit
connect_cable -open -host_name localhost
download -mode jtag -bit E:/work/demo_Runs/best_result/demo.bit -spd 6000 -cable 0
```

`insert_debugger` and `setup_debugger` both returned `OK` with no project open
and no output **[PROBE]** — they are configuration steps, not hardware steps.

### 1.6 GUI Debugger / ChipWatcher operation (SWUG111)

**Opening the ChipWatcher UI** — three equivalent routes [PDF:SWUG111 §2.2.2.6]:
toolbar ChipWatcher icon; double-click `ChipWatcher` under Hierarchy;
`Tools → Debug Tools → ChipWatcher`.

**Global enable/disable** — right-click `ChipWatcher` under Hierarchy
[PDF:SWUG111 §2.3]:

| Action | Effect |
|---|---|
| **Enable ChipWatcher** | Default state; name shown in black. Required before running the Flow, otherwise the UI refuses to open. |
| **Disable ChipWatcher** | Everything inserted after Optimize Gate is voided and its resources are released (source-instantiated IP and Mark-Debug instances excepted). Changing back to Enable does **not** re-run the flow — you must recompile all Opt Phy steps. |
| **Clear Up ChipWatcher** | Deletes all post-Read-Design marks and all post-Optimize-Gate nodes; source IP / source Mark Debug survive. Cannot be undone; flow state is unchanged so you must re-add nodes and recompile. |

**Four insertion methods** [PDF:SWUG111 §2.2]:

| # | Method | Where | Notes |
|---|---|---|---|
| 1 | Insert ChipWatcher IP from IP Catalog | In RTL source | Up to **64** ChipWatcher IP instances |
| 2 | `MARK_DEBUG` in RTL source | In RTL source | Auto-defaults: depth 1024, Data Enable ✓, Trigger Enable ✓, Power On Trigger ✗, Input/Output Pipe Stage 0 |
| 3 | Mark Debug GUI | After **Read Design** | Right-click → Mark Debug / Unmark Debug / Unmark Debug ALL / Find Net In Instance |
| 4 | ChipWatcher settings GUI | After **Optimize Gate** (use `Reset runs` on `phy(active)` if PHY Opt already ran) | Add **netlist** signals, not just source signals |

Marked signals display a **blue "bug"** icon; unmarking a source-marked signal turns
it **grey** (the source is not modified). Locked (IP) signals cannot be modified;
bug-marked signals cannot be deleted [PDF:SWUG111 §2.2.3.3].

**ChipWatcher settings window** — two pages [PDF:SWUG111 §2.2.3.4]:

* **Net View** — flat node list (Probed / Unmarked tabs). Columns: `Name`,
  `Data Enable`, `Trigger Enable`, `Trigger Clock`, `Instance`. Context menu:
  `Add Nodes`, `Delete`, `Sort Bus` (Ascending a→z / Descending z→a, default
  Descending), `Set Clock`, `Enable`, `Disable`, `View In Instance View`.
  Signals with no derivable clock show **`No Trigger Clock`** and are excluded
  from all instances until a clock is set manually (typical for input pins,
  constants, and buses containing constants).
* **Instance View** — one row per ChipWatcher instance; right pane edits
  `Clock`, `Sample Depth`, `Power On Trigger`, `Input Pipe Stages`,
  `Output Pipe Stages`. Context menu: `Rename`, `Enable`, `Disable`,
  `Move to Instance`, `Sort Bus`.

Saving with an unclocked node raises a **CRITICAL** dialog and refuses to save
[PDF:SWUG111 §2.2.3.4]. One instance holds at most **256 probes**; a 257th signal
on the same trigger clock spawns a new instance automatically [PDF:SWUG111 §2.2.3.1].

**Watch window** — `Watch` button; enabled only after Generate Bitstream produced a
`.bit`, or when *Power On Trigger* is ticked. A yellow exclamation on the icon
means the design has timing violations and captured data may be distorted
[PDF:SWUG111 §2.2.3.2].

Download pane fields [PDF:SWUG111 §2.4.2]: `Device` (auto), `Bit File` (auto,
read-only), `Download Speed` (**default 6 Mbps**), `Current Device` (for cascaded
chains). Toggle the pane with `View → Jtag Configuration`.

Waveform toolbar [PDF:SWUG111 §2.4.3.2]: `Find`, `Instant Trigger`,
`Single Trigger`, `Continue Trigger`, `Stop`, `Add Signals`,
`Delete Selected Signals`, `Expand all`, `Collapse all`, `Copy`, `Paste`,
`Previous edge`, `Next edge`, `Add a new time bar`, `Delete current time bar`,
`Previous time bar`, `Next time bar`, `Show edge statistic bar`, `Clear Graphs`,
`Fit for View`.

Trigger pane [PDF:SWUG111 §2.4.3.4]:

| Field | Range / values | Default |
|---|---|---|
| Number of windows | 1 … Sample Depth | 1 |
| Window of depth | 1 … ⌊Sample Depth / Number of windows⌋ | full depth for 1 window |
| Trigger Position in window | 0 … Sample Depth−1 | — |
| Trigger Condition | `Basic AND`, `Basic OR` | — |
| 1-bit signal condition | `don't care`, `high`, `low`, `rising edge`, `falling edge`, `edge` | `don't care` |
| Bus operators | comparison operators plus `edge` (per-bit rise/fall with `Mask Enable`) | `don't care` |

A trigger signal not added to the trigger pane is **don't care**; adding no trigger
signal at all makes every condition don't-care [PDF:SWUG111 §2.4.3.4]. Status
values shown while capturing: `Idle`, `Wait for trigger`, `Reading data`,
`Finished` [PDF:SWUG111 §2.4.3.3].

**Power-On Trigger** [PDF:SWUG111 §2.4.3.6]: tick `Power On Trigger` on the
instance → open `Watch`, set signals + conditions (only Power-On instances are
editable) → save and close → run the rest of PHY Opt and generate the bitstream →
download. Triggering then happens automatically after configuration.

### 1.7 Probe / watcher data files

| Extension | Produced by | Contents / constraints |
|---|---|---|
| `.cpc` | `export_chipprobe_config` / ChipProbe GUI | ChipProbe configuration. Extension enforced by `KIT-8211` **[PROBE]**. Internal schema not documented. |
| `.cwc` | `export_chipwatcher`, or the ChipWatcher GUI **Export** button | ChipWatcher configuration (instances, clocks, depths, nodes). Required for offline debug. **Must sit in the same folder as the matching `.bit`**, otherwise `Watch` reports a missing bit file [PDF:SWUG111 §2.5]. Internal schema not documented. |
| `.bit` | Generate Bitstream / `Export` | Debug-enabled bitstream (`compiled.bit` on export). Mandatory offline file. |
| `.data` | `Export` (only after waveforms are configured and saved in `Watch`) | Waveform configuration. Optional, but required if Power-On Trigger or saved trigger conditions are to be reused [PDF:SWUG111 §2.5]. |
| `.csv` | Watch → `File → Export Wave Data` | Waveform dump. Column `Sample` = sample index; column `Trigger` = 1 at the successful trigger point; remaining columns are probe values [PDF:SWUG111 §2.4.3.5]. |
| `minidump-*.dmp` | Crash handler | Written next to the executable when the interpreter dies (observed for `test_mark_debug`, `gen_bsdl`, `read_cwc_data`). |

Offline debug procedure [PDF:SWUG111 §2.5]: (1) after Generate Bitstream, open
ChipWatcher and press **Export** → `compiled.bit`, `compiled.cwc`, optional
`compiled.data` (with multiple runs, the active run is exported); (2) open
ChipWatcher **without opening a project** and select the `.cwc`; all settings load
read-only; (3) press `Watch` to download and observe.

### 1.8 Limits and resource cost

| Quantity | Range | Default | Source |
|---|---|---|---|
| ChipWatcher IP instances inserted in source | ≤ **64** | — | [PDF:SWUG111 §2.2.1] |
| `Number of Probes` (per IP) | **1 – 256** | 1 | [PDF:SWUG111 §2.2.1.1] |
| Probes per ChipWatcher **instance** in the settings GUI | **256** (257th → new instance) | — | [PDF:SWUG111 §2.2.3.1] |
| `Sample Data Depth` | **128 – 65536** (GUI text: "支持范围最小128，最大65536"; §2.2.3.4 phrases it as 128 … 64K) | **1024** (`1K`) | [PDF:SWUG111 §2.2.1.1, §2.2.3.4] |
| `Probe Width` | **1 – 1024** | 1 | [PDF:SWUG111 §2.2.1.1] |
| `Input Pipe Stages` | 0 – **6** | 0 | [PDF:SWUG111 §2.2.1.1] |
| `Output Pipe Stages` | 0 – **6** | 0 | [PDF:SWUG111 §2.2.1.1] |
| Probe editor pages | 8 pages × 32 probes = 256 | page 0 | [PDF:SWUG111 §2.2.1.1] |

Resource behaviour [PDF:SWUG111 §2.2.1.1, §2.2.2.8]:

* Sample depth ↑ → **block-RAM consumption ↑** ("设置深度越大，消耗的RAM 资源就越多").
* Clearing `Data Enable` on a probe saves RAM (that probe produces no waveform).
* Clearing `Trigger Enable` on a probe saves logic (that probe cannot trigger).
* `Input Pipe Stages` adds registers to *all* probe roles; `Output Pipe Stages`
  adds registers only for data-capturing probes, and when both are set the totals
  **add** ("寄存器打拍级数是Input Pipe Stages 和Output Pipe Stage 叠加的").
* More probes, wider probes and a faster trigger clock all make timing closure
  harder; counter with more pipe stages, fewer/narrower probes, or a slower
  trigger clock.

---

## 2. JTAG-based debug access

These commands drive the JTAG TAP directly through a programming cable. They are
**not** documented in SWUG110/SWUG111/SWUG113/UG009 — every syntax below is
**[HELP]** (live usage table) with **[PROBE]** runtime confirmations.

### 2.1 Hardware and driver required

| Requirement | Detail | Source |
|---|---|---|
| Cable | AL-LINK (AL-LINK-V3.0) or AL-LINK-FT. Both are JTAG programmers/debuggers using a 2.54 mm 10-pin ribbon. | [PDF:SWUG110 §2.1, §2.2] |
| Host name | `connect_cable` without `-host_name` fails: `PRG-8000 ERROR: host name is empty.` **[PROBE]**. Without any cable: `PRG-9505 ERROR: USB device open error, please re-connect the USB cable!` **[PROBE]** | — |
| Windows driver (AL-LINK / OneCable) | AL-LINK needs a driver installed on first connection (device appears as "AL-LINK" under 其它设备). AL-LINK-FT uses **WinUSB** on `USB Serial Converter A` (VID/PID `0403/6042`) and the **FTDI CDM** driver on `USB Serial Converter B` for the UART. | [PDF:SWUG110 §7.1.1, UG009 §3] |
| Linux | No driver needed; grant device permission, e.g. `chmod 0666 /dev/bus/usb/003/006`, then `./td.sh -gui &` | [PDF:SWUG110 §7.1.2] |
| Remote access | `hwserver.exe -r -f <MHz>` on the hardware PC; TD connects via `Tools → Debug Server Setting` | [PDF:UG009 §4.3] and `hwserver.exe` usage below |

### 2.2 Command reference

| Command | Syntax **[HELP]** | Notes |
|---|---|---|
| `connect_cable` | `connect_cable -h -help -host_name <string> -allink -current -close -usr_args <string> -open -auto_start -time_out <integer>` | `-host_name` is mandatory in practice **[PROBE]** |
| `JTAG_REG_ACCESS` | `JTAG_REG_ACCESS -h -help -w -r -addr <string> -data <string> -spd <integer> -cable <integer> -host_name <string> -addr_len <integer> -chip <string> -m <string>` | `-w` or `-r` mandatory **[PROBE]** |
| `JTAG_REG_ACCESS_VEC` | `JTAG_REG_ACCESS_VEC -h -help -w -r -addr <string> -data <string> -vec <string> -exp <string> -mask <string> -spd <integer> -cable <integer> -host_name <string> -both` | Vectorised form; adds `-vec` (vector file), `-exp` (expected), `-mask`, `-both` |
| `JTAG_AXIS_APB_ACCESS` | `JTAG_AXIS_APB_ACCESS -h -help -w -r -addr <string> -data <string> -spd <integer> -cable <integer> -host_name <string> -total_dev <integer> -cur_dev <integer> -chip <string> -mc <string> -loc <string>` | AXIS→APB bridge access; multi-device chain options |
| `gen_jtag_axis_vec` | `gen_jtag_axis_vec -h -help -w <list> -r <list> -spd <integer> -vec <string> -total_dev <integer> -cur_dev <integer> -chip <string>` | Offline: build a vector file of AXIS reads/writes. `-w`/`-r` take **lists**. `-vec` mandatory **[PROBE]** |
| `jtag_adc_access` | `jtag_adc_access -h -help -w -r -addr <string> -data <string> -spd <integer> -cable <integer> -host_name <string> -total_dev <integer> -cur_dev <integer>` | ADC block access over JTAG |
| `ps_tap_register_operate` | `ps_tap_register_operate -h -help -w -r -addr <string> -data <string> -spd <integer> -cable <integer> -chip <string> -total_dev <integer> -cur_dev <integer>` | PS TAP register access |
| `ps_register_operate` | `ps_register_operate -h -help -w -r -name <string> -data <string> -spd <integer> -cable <integer> -host_name <string> -chip <string> -l <list> -svf <string> -vec <string> -comment -dl` | Named PS register (not address); can emit `-svf`/`-vec` instead of driving hardware |
| `ps_efuse_operate` | `ps_efuse_operate -h -help -w -r -name <string> -data <string> -spd <integer> -cable <integer> -host_name <string> -chip <string> -l <list> -svf <string> -vec <string> -comment -dl -iopll <integer>` | PS eFuse access. **[PROBE]** with no args: `PRG-8000 ERROR: Only support DR1M device` → the command is gated to DR1M-class parts |
| `read_pvt` | `read_pvt -h -help -chip <string> -sensor <integer> -type <string> -cable <integer> -host_name <string> -total_dev <integer> -cur_dev <integer>` | PVT sensor readout |
| `serdes_access` | `serdes_access -serdes_id <integer> -cable <integer> -host_name <string> -chip <string> -r -w -g <list> -cr <integer> -bit <string> -spd <integer> -total_dev <integer> -cur_dev <integer> -bypass <string>` | SERDES PHY register access (used by HXT Margin Analysis "Jtag Read" mode) |
| `check_reg` | `check_reg -h -help -file <string> -reg <string> -cable <integer> -host_name <string>` | Register-value check against a file |
| `read_phy_data` | `read_phy_data -addr <string> -cable <integer> -host_name <string>` | PHY data read |
| `write_phy_data` | `write_phy_data -addr <string> -cable <integer> -host_name <string> value` | PHY data write; `value` is positional |
| `read_vpi_reg` | `read_vpi_reg -chip <string> -reg_val <string> -name <string>` | VPI register read (simulation-style access) |
| `write_vpi_reg` | `write_vpi_reg -chip <string> -reg_val <string> -name <string>` | VPI register write |
| `list_devices` | `list_devices -help -type <string>` | Enumerates Family / Device / Package / Speed. Full table reproduced below. |
| `list_packages` | `list_packages -help -type <string>` | Package enumeration |

**[PROBE] raw evidence**

```
td > JTAG_REG_ACCESS
PRG-9531 ERROR: PHY Configuration: -w/-r is necessary argument

td > JTAG_REG_ACCESS_VEC
PRG-9531 ERROR: PHY Configuration: -w/-r is necessary argument

td > JTAG_AXIS_APB_ACCESS
PRG-9505 ERROR: USB device open error, please re-connect the USB cable!

td > jtag_adc_access
PRG-9505 ERROR: USB device open error, please re-connect the USB cable!

td > gen_jtag_axis_vec
PRG-8000 ERROR: -vec is an necessary argument.
```

Note: `JTAG_AXIS_APB_ACCESS` and `jtag_adc_access` validate nothing before touching
the cable — they are hardware-first commands.

### 2.3 Copy-pasteable examples

> Argument **values** below are illustrative; the option **sets** are exactly the
> `[HELP]` usage lines. `-spd` is the JTAG clock setting (see §3.3 for the
> documented AL-Link TCK speeds), `-cable` selects the enumerated cable index.

```tcl
# --- open the cable -------------------------------------------------------
connect_cable -open -host_name localhost
#   remote hardware server:  connect_cable -open -host_name 192.0.2.10

# --- identify the chain ---------------------------------------------------
read_device_id -cable 0 -host_name localhost

# --- single register read / write ----------------------------------------
JTAG_REG_ACCESS -r -addr 0x0000 -addr_len 8 -spd 1000 -cable 0 -host_name localhost
JTAG_REG_ACCESS -w -addr 0x0000 -data 0x00000001 -addr_len 8 -spd 1000 -cable 0 -host_name localhost

# --- vector read with expected data and mask -----------------------------
JTAG_REG_ACCESS_VEC -r -vec E:/work/reg.vec -exp E:/work/reg.exp -mask E:/work/reg.msk \
                    -spd 1000 -cable 0 -host_name localhost

# --- offline: build the vector file first, no hardware needed ------------
gen_jtag_axis_vec -r {0x0000 0x0004 0x0008} -spd 1000 -vec E:/work/axis.vec

# --- AXIS/APB bridge ------------------------------------------------------
JTAG_AXIS_APB_ACCESS -w -addr 0x0010 -data 0xDEADBEEF -spd 1000 -cable 0 -host_name localhost

# --- ADC over JTAG --------------------------------------------------------
jtag_adc_access -r -addr 0x0000 -spd 1000 -cable 0 -host_name localhost

# --- PS-side access (DR1M parts for efuse) -------------------------------
ps_tap_register_operate -r -addr 0x0000 -spd 1000 -cable 0 -chip DR1M90GEG484
ps_register_operate -w -name <reg_name> -data 0x1 -spd 1000 -cable 0 -chip DR1M90GEG484
ps_efuse_operate -r -name <efuse_name> -spd 1000 -cable 0 -chip DR1M90GEG484

# --- SERDES / PHY / PVT --------------------------------------------------
serdes_access -serdes_id 0 -r -spd 1000 -cable 0 -host_name localhost
read_pvt -sensor 0 -type temp -cable 0 -host_name localhost
read_phy_data -addr 0x0000 -cable 0 -host_name localhost
```

### 2.4 Device table (live, from `list_devices`)

Verbatim from the interpreter's own output (TD 6.2.168116):

| Family | Device | Packages | Speed |
|---|---|---|---|
| `dr1` | `dr1_90` | DR1M90GEG400, DR1M90GEG484, DR1M90GEG484A, DR1M90MEG484, DR1V90GEG400, DR1V90GEG484, DR1V90MEG484 | 2/3 (GEG484A: 3) |
| `ef2` | `ef2_1` | EF2L15BG256B, EF2L15LG100B, EF2L15LG144B | NA |
| `ef2` | `ef2_2` | EF2L25BG256B, EF2L25XG42B | NA |
| `ef2` | `ef2_4` | EF2L45BG256B, EF2L45LG144B, EF2L45UG132B, EF2M45LG100B, EF2M45LG144B, EF2M45LG48B | NA |
| `ef2` | `ef2_s4` | EF2M45VG81C, EF2S45VG81C | NA |
| `ef3` | `ef3_1` | EF3L15CG256B | NA |
| `ef3` | `ef3_4` | EF3L40CG324B, EF3L40CG332B | NA |
| `ef3` | `ef3_5` | EF3L50CG256B | NA |
| `ef3` | `ef3_7` | EF3L70CG256B | NA |
| `ef3` | `ef3_9` | EF3L90CG324B, EF3L90CG400B | NA |
| `ef3` | `ef3_10` | EF3LA0CG484B, EF3LA0CG642B | NA |
| `ef3` | `ef3_45` | EF3L45CG256B, EF3L45CG256BH | NA |
| `ef4` | `ef4_9` | EF4L90CG324A | NA |
| `eg4` | `eagle_15` | EG4A15BG256, EG4X15BG256 | NA |
| `eg4` | `eagle_20` | EG4A20BG256, EG4A20NG88, EG4X20BG256, EG4X20LG144 | NA |
| `eg4` | `eagle_s20` | EG4D20EG176, EG4S20BG256, EG4S20CG324, EG4S20NG88 | NA |
| `ph1` | `ph1_35p` | PH1P35MBG484, PH1P35MDG324, PH1P35MEG324, PH1P35MEG324A, PH1P35MHG324 | 3, 3, 3, A, 3 |
| `ph1` | `ph1_50p` | PH1P50GEG324, PH1P50MEG324A, PH1P50SBG484 | 3, A, 3 |
| `ph1` | `ph1_60` | PH1A60GEG324 | 3 |
| `ph1` | `ph1_60c` | PH1A60GEG324C | 3 |
| `ph1` | `ph1_90` | PH1A90SBG484, PH1A90SEG324, PH1A90SEG325 | 2/3 |
| `ph1` | `ph1_100` | PH1A100GCG324, PH1A100GSG324, PH1A100SFG676, PH1A100SFG676X | 2/3 |
| `ph1` | `ph1_100p` | PH1P100GEG324, PH1P100SBG484, PH1P100SBG676, PH1P100SBG677 | 3 |
| `ph1` | `ph1_180` | PH1A180SFG676 | 2/3 |
| `ph1` | `ph1_400` | PH1A400SFG676, PH1A400SFG900, PH1A400SFX900 | 2/3 |
| `ph2` | `ph2_106` | PH2A106FLG676, PH2A106FLG900 | 2/3/1 |
| `sf1` | `sf1_6` | SF1N60VG81C, SF1S60CG121I, SF1S60VG81C, SF1S60VG81E | NA |
| `sf2` | `sf2_1` | SF2S50VG90C | NA |

---

## 3. BitWizard (`bw.exe` / `bw_commands_prompt.exe`)

### 3.1 What the two executables are

Both live in `<TD_ROOT>\bin\`:

| Executable | Size (bytes) | What it is | Evidence |
|---|---|---|---|
| `bw.exe` | 15 005 960 | **BitWizard GUI** — hosts both *BitWriter* (programming) and *ChipLinker* (SVF generation). "在TD 安装目录下，~\bin\，也可用过bw.exe 工具单独启动" [PDF:SWUG110 §4, §5]. It also embeds the same TCL command table (the binary contains the identical `Usage: create_bound …`, `Usage: musk_multi_drive_conn …` strings). | [PDF:SWUG110 §4/§5], binary string scan |
| `bw_commands_prompt.exe` | 12 588 304 | **Tcl command shell** for the programming layer. Prompt is `bw >`; `info patchlevel` = `8.6.15`; **179** commands. | [PROBE] |
| `svf2aje.exe` | 89 352 | SVF ⇄ AJE converter (CLI). | [PDF:SWUG110 §6.2] |
| `hwserver.exe` | 475 400 | Remote hardware server for TD/FD (CLI). | [PDF:UG009 §4.3] |
| `td_commands_prompt.exe` | 76 680 976 | Full TD command shell (740 commands). | [PROBE] |

> SWUG110 **never mentions** `bw_commands_prompt.exe`. Its existence and command
> set were established by running it [PROBE].

**CLI options**

* `bw.exe` — **none documented and none present**: the binary has no top-level
  usage string; SWUG110 launches it as a GUI from `~\bin\`. Its scriptable
  surface is `bw_commands_prompt.exe` / the TD console.
* `bw_commands_prompt.exe <script.tcl>` — **DOES NOT WORK. The script is silently
  ignored.** Verified: passing a script path executes nothing, produces no output
  and no error, and exits `0`. Do not use this form; it will look like success
  while doing nothing. (`-h` yields `couldn't read file "-h": no such file or
  directory`, which is why the argument *looks* like a file operand — but no
  file is ever sourced.)
* **Correct way to run a `bw` script: pipe it in as ONE physical line.** The
  `bw` shell consumes stdin one line at a time, so:
  * a multi-line script cannot be piped in — each line is evaluated separately,
    and the first `set ...` line alone is a syntax error;
  * `set x 1` newline `puts $x` fails with `can't read "x": no such variable`
    because the `set` line was its own incomplete command.
  Join every statement with an explicit `; ` onto a single line and pipe that:

  ```powershell
  'set BIT {E:/w/demo.bit}; set rc [catch { bit_to_bin -bit $BIT -bin E:/w/demo.bin } r]; puts "rc=$rc"' |
      & "$TD\bin\bw_commands_prompt.exe" -nogui
  ```

  Because `bw` redefines its own TCL environment, console capture through a pipe
  is unreliable for long output — have the script `open` a results file and
  `puts $fh ...` into it, then read that file back.
* On both shells the log directory is created relative to `bin\`; when that path
  is not writable you see, harmlessly:
  `create logfile <...>/bin//log/bw_<date>.log failed` [PROBE].

### 3.2 Command set of `bw_commands_prompt.exe` (179 names; ≈101 standard Tcl built-ins, ≈78 TD programming commands)

Programming / flash / efuse / SVF commands present **here but NOT in the TD
740-command list** (so they are BitWizard-only):

```
change_cpld_frame      create_flash_file     erase_spi            gen_device_mapping
get_flash_manufacturer get_flash_unique_id   get_gui_param        get_name_from_id
insert_err             list_cable            merge_files_for_svf  merge_flash_file
program_dualboot       program_dualbootef    program_encrypt_key  program_featureef
program_key_lock       program_multibootef    program_spi          program_spibin
program_spidir         program_spidircustom  program_spief        read_flash
read_sram              set_error             set_gui_param        split_tdo
api_test
```

Commands present in **both** shells: `JTAG_AXIS_APB_ACCESS`, `JTAG_REG_ACCESS`,
`JTAG_REG_ACCESS_VEC`, `adsr_to_fuse`, `aes_encrypt`, `avc_gcap_convert`,
`bit_convert`, `bit_to_bin`, `bit_to_vec`, `check_reg`, `connect_cable`,
`debug_mode`, `download`, `encrypt`, `eram_operate`, `export_program_log`,
`fuse_to_adsr`, `gcap`, `gen_aes_key_svf`, `gen_error_bit_file`,
`gen_jtag_axis_vec`, `gen_partial_bit`, `gen_tandem_bit`, `get_bit_info`,
`hmac_bit`, `huffman_compress`, `jtag_adc_access`, `m_pack_file`,
`merge_dualboot_bit`, `modify_register`, `program`, `program_efuse`,
`program_svf`, `ps_efuse_operate`, `ps_register_operate`,
`ps_tap_register_operate`, `read_device_id`, `read_efuse`, `read_phy_data`,
`read_pvt`, `reformat_pkg`, `serdes_access`, `svfgen`, `transfer_crc`,
`write_phy_data`.

Notable **absences** in `bw_commands_prompt.exe`: `get_bit_from_partial`,
`help`, and every `Mode_Macro` name (see §4.3).

### 3.3 Download speeds (AL-Link, BitWriter)

[PDF:SWUG110 §4.3]:

| UI value | TCK |
|---|---|
| `16MHz` | 16 MHz |
| `8MHz` | 8 MHz |
| `5MHz` | 5 MHz — **default** |
| `3MHz` | 3 MHz |
| `2MHz` | 2 MHz |
| `1MHz` | 1 MHz |
| `500kHz` | 500 kHz |
| `200kHz` | 200 kHz |

ChipLinker default is lower: `200kHz～16MHz`, default **1 MHz**, because generated
SVF files use a 1 MHz reference clock [PDF:SWUG110 §5.2.1].

### 3.4 Output file formats

[PDF:SWUG110 §3.5] — produced in `<project>/best_result/`:

| Format | Notes |
|---|---|
| `.bit` | Binary configuration file **with** header. Used by BitWriter/ChipLinker with a cable. |
| `.bin` | Binary configuration file **without** header. Usable by BitWriter with a cable, or by a custom configuration scheme. |
| `.rbf` | Like `.bin` but each group of 4 bytes is byte-reversed: `*.bin` `DD BB 66 22` → `*.rbf` `22 66 BB DD`. |
| `*_byteReverse.bin` | Like `.bin` but each byte has its bits reversed: `*.bin` `DD BB 66 22` → `*_byteReverse.bin` `BB DD 66 44`. |
| `*.SVF` | Serial Vector File, generated by ChipLinker. |
| `*_compress.bit`, `*_compress.bin` | Present only for compression-capable devices when `compress` is on. |

> **No `.spi` and no `.mcs`/Intel-HEX output is documented.** The "MCS-like" role
> for third-party programmers is filled by **SVF** (ChipLinker) and by the
> byte-swapped `.rbf` / `*_byteReverse.bin` binaries. Genuine HEX output exists
> only through the conversion commands `fuse_to_hex`, `bas_to_hex`, `bin_to_hex`,
> `pcm_vec_to_hex` (§5.2) — none of which is described in SWUG110/SWUG111/SWUG113/UG009.

Bitstream generation options that drive these files [PDF:SWUG110 §3.1–§3.4]:

* **General Option**: `bin`, `bin_compress` (Huffman soft-compression),
  `compress`, `gen_mask` (ERAM check mask), `header` (16-byte header for AL-Link
  Pro offline programming), `id` (2 user bytes), `max_stream` (fixed maximum size),
  `time_info`, `unused_io_status`, `version`.
* **Control Option**: `cascade_mode` (pull Done high only after all cascaded
  devices load), `mclk_freq` (MSPI Flash read clock), `osc_clk_disable`,
  `security` (block configuration-RAM readback), `stateholdio`.
* **Attribute Option**: `boot_mode` (MSPI ×1/×2/×4). Other families expose more.
* `mclk_freq` value sets per family (TD_User_Guide_V6.2, Generate Bitstream –
  Control Option): PH1 `2MHz 3MHz 5MHz 11MHz 22MHz 33MHz`; PH2 `2MHz 3MHz 5MHz
  11MHz 22MHz 33MHz 44MHz EXT_CLK`.
* `cascade_mode`: `normal` (non-cascaded), `bypass` (serial bypass cascade),
  `master serial` / `master spi` / `flow through` (PCM cascade).

### 3.5 Workflow for producing flash-programming files

**A. Bitstream-level merge — GUI "Create Flash File"** [PDF:SWUG110 §4.2.1]
(merges bitstream files): fields `Absolute address`, `Relative address`,
`Set Start Address`, `Hex File`.

**B. Dual-boot image — GUI "Merge Dualboot Bit"** [PDF:SWUG110 §4.2.3]:
`Default Bit File` (main region; the Device model is read from the bitstream),
`Start Address` (dual-boot load address), `Golden Bit File` (backup region),
`Merge Bit File` (output).
TCL equivalent: `merge_dualboot_bit -bit1 <string> -bit2 <string> -bin <string>
-start_addr <string> -chip <string> -header <string> -using_golden_feature`
**[HELP]**. **[PROBE]** with no args:
`PRG-8001 ERROR: MergeDualbootBit: Please specify a valid default bit file`.

```tcl
merge_dualboot_bit -bit1 E:/work/default.bit -bit2 E:/work/golden.bit \
                   -bin E:/work/dualboot.bin -start_addr 0x0E0000 \
                   -chip PH1A60GEG324
```

**C. Encryption files — GUI "Encrypt"** [PDF:SWUG110 §4.2.2]:
*Generate encrypt bit*: `Source bit file` (Device + Encrypt mode
**AES128 / AES256 / SM4** read from the bitstream), `Hkey file` (HMAC key, needed
for AES256/SM4), `Key file`, `Key number`, and the outputs `Key exp file`,
`Encrypt bit file`, `Encrypt bin file`, `Encrypt key svf file`,
`Offline download cable` (binary key for AL-Link Pro), and
`Generate program key file with key lock enabled`.
*Program encrypt key*: `Encrypt bit file`, `Key exp file`,
`Auto programing encrypt key into effuse`, `Auto programing encrypt key lock`,
`Speed` — **"为确保efuse 烧录正常，速率必须限制在1MHz"**, and the buttons
`Program Encrypt Key Into effuse`, `Program Encrypt Key Lock`,
`Download Encrypt File`.

> Lock warning: "若efuse 烧录包含Lock 功能，则在烧录后efuse 既不能执行写操作，
> 也不能支持回读操作" — after locking, eFuse is **neither writable nor readable**.
> The lock option likewise warns: 此选项谨慎使用.

**D. Flash images with the GUI download mode bar** [PDF:SWUG110 §4.3] — see §4.

**E. SVF generation — ChipLinker** [PDF:SWUG110 §5.3.2]. Ten generator variants:

| Variant | Purpose | Options |
|---|---|---|
| **SVF for SRAM** | Program configuration RAM | Add Comments, Enable Header, Frequency (100 kHz–10 MHz), Enable TIR/TDR/HIR/HDR, Enable Statehold IO, Generate Aje File |
| **SVF for SPI** | Program Flash | the above plus Jtag Studio, Length mode (Normal/Short, default Normal), Flash Vendor, Flash Name, Start Address(Hex), Golden Lock, bg_mode, rf_mode, Verify, Enable Loop |
| **Verify SPI Only** | Read back and verify Flash | Add Comments, Enable Header, Jtag Studio, Flash Vendor, Flash Name, Start Address(Hex), bg_mode, TIR/TDR/HIR/HDR, Generate Aje File |
| **Erase SPI(4k)** | Flash sector erase | + `Erase Area`: `all` / `primary` / `golden` (device-dependent), Enable Loop |
| **Check Device** | Read device ID | Add Comments, Enable Header, TIR/TDR/HIR/HDR, Generate Aje File |
| **Refresh** | Device refresh | as Check Device |
| **Erase SRAM** | Erase configuration RAM | as Check Device |
| **Check Status Done** | Read Done status | as Check Device |
| **Check Status Lock** | Verify Golden region locked (some devices only) | as Check Device |
| **SVF for User Data** | Program user data | + Flash Vendor, Flash Name, `User Data File`, `User Data Address`, Enable Loop |

`bg_mode` / `rf_mode` semantics [PDF:SWUG110 §5.6.2]:
* `rf_mode` (refresh) — resets any running function before programming, and the
  device reloads the newly programmed version afterwards (takes effect immediately).
* `bg_mode` (background) — running function is undisturbed; the new version needs
  a power cycle or an external reset (`programn`) to take effect.
* `bg_mode + rf_mode` — undisturbed during programming, reloads afterwards.
* `Verify` — adds Flash readback verification; increases programming time.
* `Enable loop` — polls the Flash BUSY bit instead of waiting a datasheet-typical
  time. **"此选项对嵌入式配置AJE 方案有效，AL-Link、AL-Link FT 不支持此指令"** —
  AL-Link and AL-Link FT do **not** support it.

Other ChipLinker controls: `Program` (program the default generated SVF),
`Add` / `Delete`, `Speed` (200 kHz–16 MHz, default 1 MHz), `Program SVF`
(program a user-supplied SVF), `Merge SVF` (merge several SVFs),
`Add Flash` wizard (`Vendor Name`, `Device Name`, `Manufacture /Device ID`,
`Volumn`, plus `Enable QE` `Command`/`Data`/`Delay` and `Maximum Time` for
4 KB / 32 KB / 64 KB sector erase, chip erase and page program),
`Device Chains` (auto chain scan / manual selection for cascaded devices)
[PDF:SWUG110 §5.2–§5.4].
The `Bypass` column in the file list is the **JTAG BYPASS instruction length**
[PDF:SWUG110 §5.3.1].

**F. AJE (Anlogic JTAG Embedded)** [PDF:SWUG110 §6]:
`AJE` files let an MCU/CPU drive TCK/TMS/TDI/TDO from GPIO and configure the FPGA
through JTAG. Generate them either by ticking `Generate Aje File` in any ChipLinker
SVF dialog, or on the command line:

```text
svf2aje.exe -svffile  V.svf -ajefile  file.aje                 # compressed (default)
svf2aje.exe -svffile  V.svf -ajefile  file.aje -full           # uncompressed
svf2aje.exe -ajefile  file.aje -svffile file4.svf -r           # reverse: AJE -> SVF
svf2aje.exe -svffile PH4Led_L1SRAM.svf -ajefile PH4LedSRAM.aje -max_size 64
```

`size` ∈ `1 2 4 8 16 32 64`, default `64`, meaning `max_size*1000` [PDF:SWUG110 §6.2].

### 3.6 `bw.exe` GUI workflow — numbered procedure

**BitWriter (programming)** — [PDF:SWUG110 §4]:

1. Launch: toolbar button in TD, or `Tools → BitWriter`, or `~\bin\bw.exe` standalone.
2. Press **Refresh** in the device/cable bar — TD issues a read-ID command; on a
   valid ID the device model appears. `Bit Version` shows the bitstream version,
   `Debug Server` shows the cable model (AL-LINK).
3. Choose the download mode in the mode bar: **Program SRAM / Verify SRAM /
   Program Flash / Dual Boot / Multi Boot / Program SPIBIN / Flash Read /
   Verify Flash / Erase Flash / Read Save SRAM**.
4. Set the TCK **Speed** (see §3.3).
5. Select files in the file-selection bar: `.bit`, `.bin`, `.svf`. Use `Add` /
   `Delete` on the toolbar to manage the list.
6. For a merged Flash image use **Create Flash File**; for a dual-boot image use
   **Merge Dualboot Bit**; for encrypted images use **Encrypt**.
7. Press **Run**; watch the control/information pane and progress bar.
8. Press **Stop** to abort.
9. If the run reports an error, read the `PRG-nnnn` code in the information pane
   (e.g. `PRG-9526` = encrypted file used with a mode other than
   `program_spi`/`verify_spi`; `PRG-9527` = dual-boot backup file missing).

**ChipLinker (SVF generation)** — [PDF:SWUG110 §5]:

1. Launch: `Tools → ChipLinker`, or `~\bin\bw.exe` standalone.
2. Press **Refresh** to enumerate cables.
3. Set **Speed** (keep the 1 MHz default when the SVF will be replayed by
   `Program SVF`).
4. Press **Add** and select the bitstream(s). The list shows `File`, `Device`,
   `Package`, `File Info`, `Bit Version`, `Level` (cascade depth), `Option`,
   `SVF File`, `Bypass`.
5. Set `Option` to one of the ten `Create SVF` variants (§3.5 E) and fill its
   options; set `SVF File` as the output name.
6. Press **OK** to generate. Tick **Generate Aje File** to also emit the `.aje`.
7. Optional: use **Merge SVF** to combine several SVF files, **Program SVF** to
   replay an SVF onto the target, **Add Flash** to describe a non-listed Flash
   part, and **Device Chains** to handle cascaded devices.

**AL-LINK driver installation (Windows)** — [PDF:SWUG110 §7.1.1]: connect the
cable with a USB Type-B cable; in Device Manager under 其它设备 an "AL-LINK" device
appears; install the vendor driver for it. Linux needs no driver — only
permissions (§2.1).

---

## 4. Device operation modes and the Download dialog

### 4.1 `Mode` — verbatim from `<repo>/references/vendor/安路科技_TD_技术文档/config/config.json`

```json
"Mode": ["PROGRAM_SRAM", "VERIFY_SRAM", "PROGRAM_FLASH", "DUAL_BOOT", "MULTI_BOOT", "PROGRAM_SPIBIN", "FLASH_READ", "VERIFY_FLASH", "ERASE_FLASH", "CHECK_FLASH_STATUS", "TOGGLE_RISCV_POR_RST_N", "DIRECT_FLASH_WRITE", "DIRECT_FLASH_READ", "PROGRAM_RISCV_IMG", "READ_SAVE_SRAM"],
"Options": ["Mode", "Speed", "MemorySize", "Default", "Golden", "StartAddress", "GoldenLock", "DataLength_Dec", "Sector", "HexFile", "DebugMode", "ErrorMax", "SaveFile", "UpdateBit"],
```

### 4.2 Mode table — index, macro, function, GUI control

Option indices used by `Mode_Options_Mapping`:

`0 Mode · 1 Speed · 2 MemorySize · 3 Default · 4 Golden · 5 StartAddress · 6 GoldenLock · 7 DataLength_Dec · 8 Sector · 9 HexFile · 10 DebugMode · 11 ErrorMax · 12 SaveFile · 13 UpdateBit`

| # | Mode | `Mode_Macro` | What it does | Download-dialog controls (`Mode_Options_Mapping`) |
|---|---|---|---|---|
| 0 | `PROGRAM_SRAM` | `jtag` | Download the bitstream into configuration RAM; lost at power-down. For bring-up/rapid verification. [PDF:SWUG110 §4.3.1] | **Mode, Speed** |
| 1 | `VERIFY_SRAM` | `x_rdbk` | Read back configuration RAM and verify it (software-generated reference, excludes user ERAM data). [PDF:SWUG110 §4.3.2] | **Mode** |
| 2 | `PROGRAM_FLASH` | `program_spi -v` | Program the bitstream into Flash; retained through power-down. [PDF:SWUG110 §4.3.3] | **Mode, Speed, MemorySize** |
| 3 | `DUAL_BOOT` | `dual_boot -v` | Program main region (`Default`) **and** backup region (`Golden`) bitstreams at a given `StartAddress` into Flash. [PDF:SWUG110 §4.3.4] | **Mode, Speed, MemorySize, Default, Golden, StartAddress** |
| 4 | `MULTI_BOOT` | `multi_boot -v` | Program the main (`Default`) bitstream plus a jump bitstream; `StartAddress` **must equal `dynamic_addr`**. [PDF:SWUG110 §4.3.5] | **Mode, Speed, MemorySize, StartAddress** |
| 5 | `PROGRAM_SPIBIN` | `program_spibin -v` | Download a raw `.bin` into a chosen Flash offset. [PDF:SWUG110 §4.3.6] | **Mode, Speed, MemorySize, StartAddress** |
| 6 | `FLASH_READ` | `rdbk_spi` | Read Flash, with selectable address and length, and save to a file. [PDF:SWUG110 §4.3.7] | **Mode, Speed, MemorySize, StartAddress, DataLength_Dec, SaveFile** |
| 7 | `VERIFY_FLASH` | `verify_spi` | Verify data written to Flash. [PDF:SWUG110 §4.3.8] | **Mode, MemorySize** |
| 8 | `ERASE_FLASH` | `erase_spi` | Chip erase the Flash. [PDF:SWUG110 §4.3.9] | **Mode, Speed** |
| 9 | `CHECK_FLASH_STATUS` | `rdbk_spisr` | **Not described in SWUG110.** | **Mode, Speed** |
| 10 | `TOGGLE_RISCV_POR_RST_N` | `t_riscv_por_reset_n` | **Not described in SWUG110.** Toggles the RISC-V power-on-reset input. | **Mode, Speed** |
| 11 | `DIRECT_FLASH_WRITE` | `program_spidir` | **Not described in SWUG110.** | **Mode, MemorySize, Sector, StartAddress, UpdateBit** |
| 12 | `DIRECT_FLASH_READ` | `rdbk_spidir` | **Not described in SWUG110.** | **Mode, MemorySize, StartAddress, DataLength_Dec, SaveFile** |
| 13 | `PROGRAM_RISCV_IMG` | `program_riscv` | **Not described in SWUG110.** Programs a RISC-V image; uses `HexFile`. | **Mode, HexFile** |
| 14 | `READ_SAVE_SRAM` | `save_sram` | Read configuration RAM back and save it to a file in **frame format**. [PDF:SWUG110 §4.3.10] | **Mode, Speed, SaveFile** |

GUI control correspondence, evidence status:

| Dialog control | Evidence |
|---|---|
| **Mode** | Documented as the BitWriter *下载模式栏* with exactly these ten named modes [PDF:SWUG110 §4.3.1–§4.3.10]. The remaining five modes exist only in `config.json`. |
| **Speed** | `SpeedList` = `["200KHz","500KHz","1MHz","2MHz","3MHz","5MHz","8MHz","16MHz"]`; SWUG110 §4.3 lists the identical UI set `200kHz … 16MHz` with 5 MHz as the default. |
| **MemorySize** | `MemorySizeList` = `[1,2,4,8,16,32,64,128,256,512]`. Unit is **Mbit** (inferred): `flash.json` records `MemorySize` as `"32M"` / `"256M"` for Flash parts, and the gating field `DefaultFlashSize` uses the same numeric scale (128, 256, 8, 4). |
| **Default / Golden** | Main-region and backup-region bitstream selectors [PDF:SWUG110 §4.2.3, §4.3.4]. |
| **StartAddress** | Flash load/offset address [PDF:SWUG110 §4.3.4, §4.3.5]. |
| **GoldenLock** | Golden-region lock. Corresponding SVF option `Golden Lock` [PDF:SWUG110 §5.3.2.2] and the Flash-side `GoldenLock` block in `flash.json` (`Cmd`, `Upper8/Upper4/Upper2` address ranges, `Support`). |
| **DataLength_Dec** | Read/verify length in **decimal**. Not described in SWUG110. |
| **Sector** | Used only by `DIRECT_FLASH_WRITE`. Not described in SWUG110. |
| **HexFile** | Used only by `PROGRAM_RISCV_IMG`. Not described in SWUG110. |
| **DebugMode** | Present in `Options` but mapped to **no** mode — always available. Not described in SWUG110. |
| **ErrorMax** | Present in `Options` but mapped to **no** mode — always available. Not described in SWUG110; matches `download -error_max <integer>` (§5.1). |
| **SaveFile** | Output file for `FLASH_READ`, `DIRECT_FLASH_READ`, `READ_SAVE_SRAM`. |
| **UpdateBit** | `UpdateBit` = `["Update", "Don't update"]`; used only by `DIRECT_FLASH_WRITE`. Not described in SWUG110. |

**`SpeedList` (verbatim)**

```json
"SpeedList":["200KHz", "500KHz", "1MHz", "2MHz", "3MHz", "5MHz", "8MHz", "16MHz"],
"UpdateBit":["Update", "Don't update"],
"MemorySizeList": [1, 2, 4, 8, 16, 32, 64, 128, 256, 512],
```

**`Mode_Options_Mapping` (verbatim)**

```json
"Mode_Options_Mapping": {
    "PROGRAM_SRAM": [0, 1],
    "PROGRAM_FLASH": [0, 1, 2],
    "VERIFY_SRAM": [0],
    "DUAL_BOOT": [0, 1, 2, 3, 4, 5],
    "MULTI_BOOT": [0, 1, 2, 5],
    "FLASH_READ": [0, 1, 2, 5, 7, 12],
    "PROGRAM_SPIBIN": [0, 1, 2, 5],
    "VERIFY_FLASH": [0, 2],
    "CHECK_FLASH_STATUS": [0, 1],
    "TOGGLE_RISCV_POR_RST_N": [0, 1],
    "DIRECT_FLASH_WRITE": [0, 2, 8, 5, 13],
    "DIRECT_FLASH_READ": [0, 2, 5, 7, 12],
    "PROGRAM_RISCV_IMG": [0, 9],
    "ERASE_FLASH":[0, 1],
    "READ_SAVE_SRAM":[0, 1, 12]
},
```

**`Mode_Macro` (verbatim)**

```json
"Mode_Macro": {
    "PROGRAM_SRAM": "jtag",
    "PROGRAM_FLASH": "program_spi -v",
    "VERIFY_SRAM": "x_rdbk",
    "DUAL_BOOT": "dual_boot -v",
    "MULTI_BOOT": "multi_boot -v",
    "FLASH_READ": "rdbk_spi",
    "PROGRAM_SPIBIN": "program_spibin -v",
    "VERIFY_FLASH": "verify_spi",
    "CHECK_FLASH_STATUS": "rdbk_spisr",
    "TOGGLE_RISCV_POR_RST_N": "t_riscv_por_reset_n",
    "DIRECT_FLASH_WRITE": "program_spidir",
    "DIRECT_FLASH_READ": "rdbk_spidir",
    "PROGRAM_RISCV_IMG": "program_riscv",
    "ERASE_FLASH": "erase_spi",
    "READ_SAVE_SRAM": "save_sram"
}
```

### 4.3 What the `Mode_Macro` strings are — and are not

Verified against the `bw_commands_prompt.exe` interpreter (`info commands $name`) **[PROBE]**:

| Macro string | Is it a command in `bw_commands_prompt.exe`? | In the TD 740 list? |
|---|---|---|
| `program_spi -v` | **Yes** — `program_spi` exists | no |
| `verify_spi` | **Yes** | no |
| `erase_spi` | **Yes** | no |
| `program_spibin -v` | **Yes** — `program_spibin` exists | no |
| `program_spidir` | **Yes** | no |
| `jtag` | **No** | no |
| `x_rdbk` | **No** | no |
| `dual_boot -v` | **No** (`dual_boot` absent) | no |
| `multi_boot -v` | **No** (`multi_boot` absent) | no |
| `rdbk_spi` | **No** | no |
| `rdbk_spisr` | **No** | no |
| `t_riscv_por_reset_n` | **No** | no |
| `rdbk_spidir` | **No** | no |
| `program_riscv` | **No** | no |
| `save_sram` | **No** | no |

> So `Mode_Macro` is **not** a command table. For the five modes whose macro names
> *are* real commands, the string is literally "command + flags"
> (`program_spi -v`). For the other ten it is an opaque mode identifier.
>
> **[RECONSTRUCTED]** The most likely consumer is `download -mode <string>`
> (§5.1) — `download` has a `-mode <string>` option and is the only TD command in
> the live usage table with a free-form mode string. **This is an inference, not a
> documented fact**; the raw evidence is (a) `download`'s usage line
> containing `-mode <string>`, (b) `config.json` being titled
> `"Comment": "Device Operation Mode"` and residing in `<repo>/references/vendor/安路科技_TD_技术文档/config/`, i.e. beside
> the GUI, and (c) the absence of those names from `info commands`. No PDF
> documents the accepted `-mode` values.

### 4.4 Per-device gating — the `Device` object

Each entry of `Data.Device` (keys `"0"` … `"21"`) has these fields:

| Field | Type | Effect on the dialog |
|---|---|---|
| `Mode_List` | array of **`Mode` indices** | The only modes offered for that device. An empty array means no operation mode is offered. |
| `isDualBootSupport` | string `"TRUE"` / `"FALSE"` (note: **strings**, not JSON booleans) | When `"FALSE"`, dual-boot controls (Default / Golden / StartAddress pairing) are not offered. |
| `isAddressEditable` | string `"TRUE"` / `"FALSE"` | When `"FALSE"`, the address field is display-only and must use the value from `GolenBitAddress`. |
| `GolenBitAddress` | array of address strings | The address(es) to pre-load into the (possibly locked) address field. Mostly one entry; devices 4 and 5 have two, device 15 has two, device 0/1/14/19 have a **single empty string** `[""]` (no address available). |
| `isSupportGolendLock` | string `"TRUE"` / `"FALSE"` | **`"FALSE"` for all 22 devices** in this build — the Golden-lock control is never enabled by this file. |
| `DefaultFlashSize` | integer (same unit as `MemorySizeList`) | Default value of `MemorySize`. **Absent for device `"5"`.** |

Note the misspellings are in the file and must be preserved: **`GolenBitAddress`**
(single `d`) and **`isSupportGolendLock`** (`Golend`).

Full table (mode indices expanded to names):

| `Device` | Modes offered | `isDualBootSupport` | `isAddressEditable` | `GolenBitAddress` | `DefaultFlashSize` |
|---|---|---|---|---|---|
| `0` | DIRECT_FLASH_WRITE, DIRECT_FLASH_READ | FALSE | FALSE | `[""]` | 128 |
| `1` | *(none — empty list)* | FALSE | FALSE | `[""]` | 128 |
| `2` | PROGRAM_SRAM, VERIFY_SRAM, PROGRAM_FLASH, DUAL_BOOT, MULTI_BOOT, PROGRAM_SPIBIN, FLASH_READ, VERIFY_FLASH, ERASE_FLASH, READ_SAVE_SRAM | TRUE | TRUE | `["0x0E0000"]` | 128 |
| `3` | modes 0–9 + READ_SAVE_SRAM | TRUE | FALSE | `["0x041000"]` | 4 |
| `4` | modes 0–9 + READ_SAVE_SRAM | TRUE | FALSE | `["0x061000", "0x080000"]` | 8 |
| `5` | modes 0–9 + READ_SAVE_SRAM | TRUE | FALSE | `["0x061000", "0x080000"]` | *(key absent)* |
| `6` | modes 0–9 + READ_SAVE_SRAM | TRUE | FALSE | `["0x081000"]` | 8 |
| `7` | modes 0–9 + TOGGLE_RISCV_POR_RST_N, PROGRAM_RISCV_IMG, READ_SAVE_SRAM | TRUE | FALSE | `["0x041000"]` | 4 |
| `8` | modes 0–8 + READ_SAVE_SRAM | TRUE | TRUE | `["0x0810000"]` | 128 |
| `9` | modes 0–8 + READ_SAVE_SRAM | TRUE | TRUE | `["0x01010000"]` | 256 |
| `10` | modes 0–8 + READ_SAVE_SRAM | TRUE | TRUE | `["0x01010000"]` | 256 |
| `11` | modes 0–8 + READ_SAVE_SRAM | TRUE | TRUE | `["0x0810000"]` | 256 |
| `12` | modes 0–8 + READ_SAVE_SRAM | TRUE | TRUE | `["0x0410000"]` | 256 |
| `13` | modes 0–8 + READ_SAVE_SRAM | TRUE | TRUE | `["0x012D0000"]` | 256 |
| `14` | PROGRAM_SRAM, VERIFY_SRAM, READ_SAVE_SRAM | FALSE | FALSE | `[""]` | 256 |
| `15` | modes 0–8 + READ_SAVE_SRAM | TRUE | TRUE | `["0x041000", "0x061000"]` | 256 |
| `16` | modes 0–8 + READ_SAVE_SRAM | TRUE | TRUE | `["0x0250000"]` | 256 |
| `17` | modes 0–8 + READ_SAVE_SRAM | TRUE | TRUE | `["0x0250000"]` | 128 |
| `18` | modes 0–8 + READ_SAVE_SRAM | TRUE | FALSE | `["0x040000"]` | 8 |
| `19` | PROGRAM_SRAM, VERIFY_SRAM, READ_SAVE_SRAM | FALSE | FALSE | `[""]` | 256 |
| `20` | modes 0–9 + READ_SAVE_SRAM | TRUE | FALSE | `["0x041000"]` | 8 |
| `21` | modes 0–9 + READ_SAVE_SRAM | TRUE | FALSE | `["0x101000"]` | 8 |

Where "modes 0–8" = PROGRAM_SRAM, VERIFY_SRAM, PROGRAM_FLASH, DUAL_BOOT,
MULTI_BOOT, PROGRAM_SPIBIN, FLASH_READ, VERIFY_FLASH, ERASE_FLASH, and
"modes 0–9" additionally includes CHECK_FLASH_STATUS.

### 4.5 `Device` keys are opaque numeric IDs — mapping NOT determined

**Answer: NO.** The numeric keys `"0"` … `"21"` in `<repo>/references/vendor/安路科技_TD_技术文档/config/config.json →
Data.Device` are **opaque device-type IDs**. Their mapping to family and package
could **not** be determined from any provided input. Searches performed:

| Search | Result |
|---|---|
| `<repo>/references/vendor/安路科技_TD_技术文档/config/config.json`, `cpld_flash.json`, `flash.json` | no device-name field anywhere |
| Whole install tree (`<TD_ROOT>`) for text files containing `isDualBootSupport` / `GolenBitAddress` / `Mode_Macro` | **one** hit — `<repo>/references/vendor/安路科技_TD_技术文档/config/config.json` itself |
| Whole install tree (`*.csv`, `*.json`) for `PH1A60GEG324` | **one** hit — `arch/device_resource/device_resource.csv`, which has **no numeric ID column** (columns: `Family,Device,User IOs,LUTs,DFFs,DSPs,PLLs,ERAMs(Kbits),DRAMs(Kbits),URAMs(Kbits),Serdes Lanes,PCIE,Hard Cores,SIP,MIN. VOLTAGE,REF. VOLTAGE,MAX. VOLTAGE`) |
| All four PDFs + TD_User_Guide + SWUG105 | no numeric device-ID table |
| `SWUG105` 附录一 "Device db 文件名" | maps **family → package → `*.db` file name** only (PH1: `ph1_35p/50p/60/60c/90/100/100p/180/400`; PH2: `ph2_106`), no numeric IDs |

What **can** be inferred from the file alone (presented as inference, **not** a mapping):

* Device `7` is the **only** entry whose `Mode_List` contains
  `TOGGLE_RISCV_POR_RST_N` (index 10) and `PROGRAM_RISCV_IMG` (index 13), so it is a
  RISC-V-capable part (DR1 or SF1 class — those are the families with `RISCv*1`
  hard cores in `device_resource.csv`).
* Devices `0` and `1` are the most restricted (`0`: DIRECT_FLASH_WRITE /
  DIRECT_FLASH_READ only; `1`: no mode at all), with `isDualBootSupport = FALSE`.
* Devices `14` and `19` are SRAM-only (`PROGRAM_SRAM`, `VERIFY_SRAM`,
  `READ_SAVE_SRAM`), consistent with parts that have no external configuration Flash.
* `cpld_flash.json` holds **48** entries (`"0"` … `"47"`) mapping to embedded-Flash
  part numbers (`GD25VQ40C`, `GD25VQ80C`, `GD25WQ80E`, `GD25WQ16E`, `GD25WQ40E`,
  `GD25Q80C`, `P25Q40L`, `P25Q80L`). These indexes are a **different** enumeration
  from `config.json`'s `Device` keys (6 vs 22 entries, different key ranges), so they
  must not be conflated. The families with on-die Flash per `device_resource.csv`
  are EF2 (4 Mb), EF3 (4/8 Mb), SF1 (8 Mb) and SF2 (4 Mb).
* `isSupportGolendLock` is `"FALSE"` for every device, so the `GoldenLock` option is
  gated off everywhere in this build.

---

## 5. TCL programming / download commands

Every name in this section was checked against `td_commands_all.txt` (740 names).
Names that failed the check are listed and dropped in §5.9.

### 5.1 Primary programming commands

| Command | Syntax (verbatim from `help`) | PDF-documented? | Runtime evidence |
|---|---|---|---|
| `download` | `download -h -help -v -d -mode <string> -s -spd <integer> -bit <string> -bas <string> -bit2 <string> -bin <string> -bin2 <string> -hex2 <string> -svf <string> -vec <string> -output <string> -wait <integer> -data_length <integer> -start_addr <string> -rdbk <string> -sec <integer> -cable <integer> -error_max <integer> -chip <string> -golden_lock -total_dev <integer> -cur_dev <integer> -bypass <string> -flashsize <integer> -spi_qe_cmd <string> -spi_qe_data <string> -check_lock -xread -using_golden_feature -host_name <string>` | **not documented in SWUG110/111/113/UG009** | Bare `download` opens the USB device: `PRG-9505 ERROR: USB device open error…`, then `PRG-9525 ERROR: Chip validation failed!` **[PROBE]** — a real hardware operation, not a GUI launcher |
| `program` | `program -h -help -mode <string> -s -p -spd <integer> -output <string> -input <string> -error_max <integer> -cable <integer> -r -ss -sps -tckCnt <string> -host_name <string>` | **not documented** | — |
| `program_svf` | `program_svf -h -help -svf <string> -rdbk <string> -spd <integer> -cable <integer> -host_name <string>` | **not documented** | `PRG-8001 ERROR: ProgramSvf:  Please specify the svf file name` **[PROBE]** |
| `svfgen` | `svfgen -h -help -scan_mode <string> -level <integer> -total <integer> -svf <string> -bas <string> -bit <string> -bin <string> -bin2 <string> -hex <string> -hex2 <string>  -opt <string> -tool <string> -len_mode <string> -bg_mode <string> -rf_mode <string> -bypass <string> -merge <list> -programn_pin_low -verify -freq <string> -golden_lock -enable_loop -verify_partial -size <string>  -flashsize <integer> -dis_hir_hdr_tir_tdr -boundary_reg <string> -chip <string> -start_addr <string> -num <integer> -tde -aje -full -mode <string> -usrdata_addr <string> -usrdata <string> -no_id_check -spi_qe_cmd <string> -spi_qe_data <string> -debug -flow <string> -non_burst -stateholdio -using_64k_erase -statehold_bypass_mode <string> -prog_spi_tck <integer> -loc <string> -mc <string> -g <list> -erase_area <string> -flash <string> -header -aje -full -mcu_on` | **not documented** | `PRG-8001 ERROR: SvfGen: Please specify the svf file name` **[PROBE]** |
| `bitgen` | `bitgen -h -help -max_stream -info -attr_info -log_file <string> -fuse <string> -input_fuse <string> -bit <string> -bas <string> -bin <string> -bmk <string> -bma <string> -gen_mask -entdo -por_off -c -f <string> -g <list> -s -hd <string> -id <string> -version <string> -security -mcu -128 <string> -256 <string> -no_date_info -phy_top -pcie -compress -dispersed -full_0 -hmac -mc <string> -d <string> -enc_mode <string> -key_file <string> -hmac_key_file <string> -config_cr -cfg -cfg_file <string> -m <string> -no_program_done -seu_all -embedded_compress -unused_io_status <string> -check_mf -no_id_check -freg <string> -pcm_based -ipc <list> -hpio_reg <string> -hpio_reg_read <string> -cmac_reg <string> -ecc_modify -close_crc -all_fuse <string> -ecc_info <string> -pcap_bit -ph2_pcie_input <list> -ph2_pcie_output <list> -trim <string> -pcie_100ms_linkup -ip_noop_cfg <string> -essential_insts_file <string> -resource <string> -dram_address <string>` | **YES — SWUG105 §4.9.1** (general options + `-g` register form) | — |

**`download` option-by-option mapping.** The usage line is authoritative; the
"likely dialog control" column is **[RECONSTRUCTED]** from name matching only and
is not documented anywhere:

| `download` option | Likely dialog control / meaning |
|---|---|
| `-mode <string>` | **Mode** — candidate values are the `Mode_Macro` strings of §4.3 (inference) |
| `-spd <integer>` | **Speed** |
| `-flashsize <integer>` | **MemorySize** |
| `-data_length <integer>` | **DataLength_Dec** |
| `-start_addr <string>` | **StartAddress** |
| `-sec <integer>` | **Sector** |
| `-error_max <integer>` | **ErrorMax** |
| `-output <string>` / `-rdbk <string>` | **SaveFile** / readback output |
| `-bit` `-bit2` `-bin` `-bin2` `-hex2` `-svf` `-vec` `-bas` | file inputs (main/golden, bit/bin/SVF/vector/BAS) |
| `-golden_lock`, `-check_lock`, `-using_golden_feature` | **GoldenLock** / golden-region behaviour |
| `-chip`, `-cable`, `-host_name`, `-total_dev`, `-cur_dev`, `-bypass` | target selection and JTAG chain placement |
| `-spi_qe_cmd`, `-spi_qe_data` | Flash Quad-Enable command/data (matches the `EnableQE` block in `flash.json`) |
| `-xread`, `-wait`, `-v`, `-d`, `-s` | readback / timing / verbosity / debug flags; meaning not documented |

```tcl
# Open the cable first; -host_name is required in practice.
connect_cable -open -host_name localhost

# Program the FPGA configuration RAM.
download -mode jtag -bit E:/work/demo.bit -spd 6000 -cable 0 -host_name localhost

# Program external SPI Flash (bitstream), then verify.
download -mode program_spi -v -bit E:/work/demo.bit -flashsize 128 \
         -spd 3000 -chip PH1A60GEG324 -cable 0 -host_name localhost
download -mode verify_spi -bit E:/work/demo.bit -chip PH1A60GEG324 \
         -cable 0 -host_name localhost

# Read Flash 1 MiB from offset 0 and save it.
download -mode rdbk_spi -start_addr 0x000000 -data_length 1048576 \
         -output E:/work/flash_dump.bin -chip PH1A60GEG324 -cable 0 -host_name localhost

# Program a raw .bin at an offset; same for dual-boot (needs both bitstreams).
download -mode program_spibin -bin E:/work/blob.bin -start_addr 0x081000 \
         -flashsize 128 -cable 0 -host_name localhost
download -mode dual_boot -bit E:/work/default.bit -bit2 E:/work/golden.bit \
         -start_addr 0x0E0000 -flashsize 128 -cable 0 -host_name localhost

# Replay a generated SVF.
svfgen -bit E:/work/demo.bit -svf E:/work/demo_spi.svf -mode program_spi \
       -freq 1MHz -flashsize 128 -header
program_svf -svf E:/work/demo_spi.svf -spd 1000 -cable 0 -host_name localhost
```

**`bitgen` copy-pasteable examples** (from SWUG105 §4.9.1, verbatim):

```tcl
bitgen -bit top.bit -g {security:1}
bitgen -bit top.bit -g {mclk_freq:5MHz boot_mode:mspix4}
bitgen -bit ./run_led.bit
```

`-g` syntax: `-g {param_1:value_1 param_2:value_2 … param_n:value_n}` with `:`
between param and value and spaces between pairs; **param and value are
case-sensitive and must match the GUI Process→Properties spelling exactly**; all
Control / Startup / Attribute options are reachable this way, while the General
Options have their own dedicated flags [PDF:SWUG105 §4.9.1].

### 5.2 Bitstream / format conversion and image building

| Command | Syntax (verbatim from `help`) | PDF-documented? | Notes |
|---|---|---|---|
| `bit_to_vec` | `bit_to_vec -h -help -d -v -m <string> -bit <string> -bas <string> -hex <string> -bin <string> -bit2 <string> -svf <string> -vec <string> -chip <string> -data_length <integer> -start_addr <string> -elf_flash -encrypt -encrypt2 -verify -fc -freq <double> -total_dev <integer> -cur_dev <integer> -bypass <string> -flashsize <integer> -rz -fall -no_id_check -dl -sr -spi_qe_cmd <string> -spi_qe_data <string> -xrdbk_using_isc_enable -cont -slt -jtag8 -erase_done -force_dram_mask -print_pcm_comment -freg <string> -sec <integer> -row <integer> -column <integer> -minor <integer> -progress_off -ecc -set_delay <integer> -eram_verify -bg_program -crc_off -delay <integer> -xread -rst_crc` | **not documented** | Central format converter (bit ↔ bas/hex/bin/svf/vec) plus programming parameters |
| `bit_to_bin` | not in help | **not documented** | In the 740 list |
| `bit_to_bas` | not in help | **not documented** | In the 740 list |
| `bin_to_hex` | `bin_to_hex -h -help -bin <string> -hex <string>` | **not documented** | Raw binary → HEX text |
| `bas_to_hex` | `bas_to_hex -h -help -bas <string> -hex <string>` | **not documented** | BAS → HEX |
| `hex_to_bit` | `hex_to_bit -h -help -bit <string> -hex <string>` | **not documented** | HEX → `.bit` |
| `fuse_to_hex` | `fuse_to_hex -h -help -fuse <string> -hex <string> -chip <string> -reverse` | **not documented** | Fuse map → HEX |
| `fuse_to_adsr` | not in help | **not documented** | In the 740 list |
| `adsr_to_fuse` | not in help | **not documented** | In the 740 list |
| `fuse_to_log` | not in help | **not documented** | In the 740 list |
| `pcm_vec_to_hex` | `pcm_vec_to_hex -h -help -vec <string> -hex <string>` | **not documented** | PCM vector → HEX |
| `bit_convert` | not in help | **not documented** | In the 740 list |
| `vec_to_state` | not in help | **not documented** | In the 740 list |
| `merge_dualboot_bit` | `merge_dualboot_bit -h -help -bit1 <string> -bit2 <string> -bin <string> -start_addr <string> -chip <string> -header <string> -using_golden_feature` | **not documented** (the GUI equivalent *Merge Dualboot Bit* is [PDF:SWUG110 §4.2.3]) | `PRG-8001 ERROR: MergeDualbootBit: Please specify a valid default bit file` **[PROBE]** |
| `gen_partial_bit` | `gen_partial_bit -bit <string> -bin <string> -output <string> -g <list>` | **not documented** | `PRG-8000 ERROR: please select input file use -bit/bin` **[PROBE]** |
| `get_bit_from_partial` | not in help | **not documented** | `PRG-8000 ERROR: -partial parameter is necessary.` **[PROBE]** → takes `-partial` |
| `gen_tandem_bit` | not in help | **not documented** | `PRG-8000 ERROR: please using -bin parameter to specify output file.` **[PROBE]** |
| `gen_error_bit_file` | not in help | **not documented** | `PRG-8000 ERROR: open log file failed!` **[PROBE]** → needs a log input |
| `get_bit_info` | `get_bit_info -chip <string> -fa <string> -fo <integer> -bit <string> -error <list> -error_file <string> -m <string> -vec <string> -log <string> -wl <integer> -bl <integer> -full_clk_vec -pre_process_log -vec_list <list> -matrix -save_log -rz -real_bl` | **not documented** | Returns `OK` with no arguments **[PROBE]** |
| `m_pack_file` | `m_pack_file -h -help -hy <string> -xgn <string> -type <string> -bin <string> -version <string>` | **not documented** | Third-party package → bin |
| `reformat_pkg` | `reformat_pkg -h -help -pkg <string>` | **not documented** | Package reformat |
| `huffman_compress` | `huffman_compress -help -in <string> -ttf <string> -huf <string> -decode` | **not documented** | Backs the `bin_compress` option of §3.4 |
| `export_fuse_info`, `print_cpld_cfgreg` | no help entry for either | **not documented** | CPLD fuse / CFG-register inspection |
| `gen_bsdl` | not in help | **not documented** | **[PROBE] calling it with no arguments crashed the interpreter** (`coredump minidump-…dmp`). Use with real arguments only. |
| `gen_aes_key_svf` | not in help | **not documented** | `PRG-8000 ERROR: Please use -bin <string> or -key_exp to specify the input file` **[PROBE]** → accepts `-bin` and `-key_exp` |
| `change_cpld_frame`, `gen_device_mapping`, `get_name_from_id`, `list_cable`, `create_flash_file`, `merge_flash_file`, `merge_files_for_svf`, `read_flash`, `read_sram`, `split_tdo` | — | — | **NOT in the TD 740 list** — these exist only in `bw_commands_prompt.exe` (§3.2) |

### 5.3 BRAM readback / writeback

| Command | Syntax (verbatim from `help`) | PDF-documented? |
|---|---|---|
| `rdbk_bram` | `rdbk_bram -h -help -bram <string> -dir <string> -device <string> -out -cable <integer> -total_dev <integer> -cur_dev <integer> -bypass <string> -host_name <string> -spd <integer>` | **not documented** |
| `rdbk_bram18` | `rdbk_bram18 -h -help -bram <string> -dir <string> -device <string> -out -cable <integer> -total_dev <integer> -cur_dev <integer> -bypass <string> -host_name <string> -spd <integer>` | **not documented** |
| `rdbk_bram20` | `rdbk_bram20 -h -help -bram <string> -dir <string> -device <string> -out -cable <integer> -axis -total_dev <integer> -cur_dev <integer> -bypass <string> -chip <string> -host_name <string> -spd <integer>` | **not documented** |
| `rdbk_bram32` | `rdbk_bram32 -h -help -bram <string> -dir <string> -device <string> -out -cable <integer> -total_dev <integer> -cur_dev <integer> -bypass <string> -host_name <string> -spd <integer>` | **not documented** |
| `write_bram` | `write_bram -h -help -bram <string> -input <string> -device <string> -cable <integer> -total_dev <integer> -cur_dev <integer> -bypass <string> -host_name <string>` | **not documented** |
| `write_bram18` | `write_bram18 -h -help -bram <string> -input <string> -device <string> -cable <integer> -total_dev <integer> -cur_dev <integer> -bypass <string> -host_name <string>` | **not documented** |
| `write_bram20` | `write_bram20 -h -help -bram <string> -input <string> -device <string> -cable <integer> -logic -axis -total_dev <integer> -cur_dev <integer> -bypass <string> -host_name <string>` | **not documented** |
| `write_bram32` | `write_bram32 -h -help -bram <string> -input <string> -device <string> -cable <integer> -total_dev <integer> -cur_dev <integer> -bypass <string> -host_name <string>` | **not documented** |
| `list_bram` | `list_bram -h -help -device <string> -cable <integer> -host_name <string>` | **not documented** |

**[PROBE]**: `rdbk_bram` → `KIT-8009 ERROR: Please specify an BRAM RID to read back.`;
`write_bram` → `KIT-8014 ERROR: Please specify a BRAM ID to write.`
The 18/20/32 suffixes denote the BRAM width class; `rdbk_bram20` adds `-axis` and
`-chip`, `write_bram20` adds `-logic` and `-axis`.

```tcl
# Discover the BRAM map, dump one, edit it, write it back.
list_bram -device PH1A60GEG324 -cable 0 -host_name localhost
rdbk_bram -bram <RID> -dir E:/work/bram -out -device PH1A60GEG324 \
          -cable 0 -host_name localhost -spd 1000
write_bram -bram <RID> -input E:/work/bram/<RID>.dat -device PH1A60GEG324 \
           -cable 0 -host_name localhost

# Dedicated-width variants
rdbk_bram18 -bram <RID> -dir E:/work/bram -out -device PH1A60GEG324 -cable 0 -host_name localhost
rdbk_bram20 -bram <RID> -dir E:/work/bram -out -axis -chip PH1A60GEG324 -cable 0 -host_name localhost
rdbk_bram32 -bram <RID> -dir E:/work/bram -out -device PH1A60GEG324 -cable 0 -host_name localhost
```

### 5.4 eFuse access

| Command | Syntax (verbatim from `help`) | PDF-documented? | Runtime evidence |
|---|---|---|---|
| `program_efuse` | no help entry | **not documented** | `PRG-8000 ERROR: Please specify the efuse name and value` **[PROBE]** → `program_efuse <name> <value>` |
| `read_efuse` | no help entry | **not documented** | Hardware: `PRG-9505 ERROR: USB device open error…` **[PROBE]** |
| `export_fuse_info` | no help entry | **not documented** | In the 740 list |
| `ps_efuse_operate` | `ps_efuse_operate -h -help -w -r -name <string> -data <string> -spd <integer> -cable <integer> -host_name <string> -chip <string> -l <list> -svf <string> -vec <string> -comment -dl -iopll <integer>` | **not documented** | `PRG-8000 ERROR: Only support DR1M device` **[PROBE]** |
| `ps_register_operate` | `ps_register_operate -h -help -w -r -name <string> -data <string> -spd <integer> -cable <integer> -host_name <string> -chip <string> -l <list> -svf <string> -vec <string> -comment -dl` | **not documented** | — |
| `ps_tap_register_operate` | `ps_tap_register_operate -h -help -w -r -addr <string> -data <string> -spd <integer> -cable <integer> -chip <string> -total_dev <integer> -cur_dev <integer>` | **not documented** | Returns `OK` with no arguments **[PROBE]** |

The eFuse **key/lock** workflow is documented only as GUI steps [PDF:SWUG110 §4.2.2.2]:
`Program Encrypt Key Into effuse`, `Program Encrypt Key Lock`,
`Download Encrypt File`, with the hard constraint
**Speed must be limited to 1 MHz for eFuse programming**, and the lock warning
quoted in §3.5 C. The TD error list adds
`写Efuse 存储区域时出现错误` and `写Efuse 时输入的域名不正确 / 输入器件中Efuse 包含的域`
[TD_User_Guide_V6.2].

```tcl
program_efuse <efuse_name> <value>
read_efuse -cable 0 -host_name localhost
export_fuse_info
ps_efuse_operate -w -name <efuse_name> -data <value> -spd 1000 -cable 0 -chip DR1M90GEG484
```

### 5.5 ERAM, device ID, readback and logging

| Command | Syntax (verbatim from `help`) | PDF-documented? | Runtime evidence |
|---|---|---|---|
| `eram_operate` | `eram_operate -h -help -bit <string> -bin <string> -read <string> -partial <string> -cable <integer> -host_name <string> -spd <integer> -total <integer> -level <integer> -bypass <string> -svf <string> -err_only -refresh -check_status -chip <string> -frame <integer> -shift <integer> -parse_log <string> -gen_pcm <string> -mode <string> -vec <string> -verify -td_log <string> -uram_adc <string> -fail_eram <string> -gold_eram <string> -crc` | **not documented** | `PRG-8000 ERROR: please select input file use -bit/bin` **[PROBE]** |
| `read_device_id` | `read_device_id -level <integer> -total <integer> -bypass <string> -cable <integer> -host_name <string>` | **not documented** | Hardware: `PRG-9505 ERROR: USB device open error…` **[PROBE]** |
| `export_program_log` | `export_program_log -svf <string>` | **not documented** | `Logging option is off` **[PROBE]** |
| `read_cwc_data` | no help entry | **not documented** | **[PROBE] crashed the interpreter with no arguments** |
| `read_cwc_reg` / `write_cwc_reg` / `write_cwc_vec` / `set_cwc` | no help entries | **not documented** | In the 740 list |
| `report_cwc_status` | `report_cwc_status -help` | **not documented** | Prints the CWC configuration report (§1.3) |
| `write_bit_config` | no help entry | **not documented** | In the 740 list |
| `read_pnl` / `write_pnl` | `read_pnl file_name -h -verbose -merge_equal -trans -merge_pnl -ooc <string> -static <string> -file <string> -help` / `write_pnl file_name -help -h -g -cro -clk -v -mode <string> -model <string>` | **not documented** | Design/netlist files |
| `gcap` | `gcap -h -help -type <string> -expected <string> -mode <string> -vec <string> -comment` | **not documented** | Golden-configuration access pattern |
| `avc_gcap_convert` | `avc_gcap_convert -h -help -avc <string> -out <string> -mode <string> -rz -fall -comment` | **not documented** | AVC ⇄ GCAP conversion |
| `get_config_param` | `get_config_param option_name -chip <string>` | **not documented** | Read a configuration option |
| `transfer_crc` | no help entry | **not documented** | In the 740 list |

```tcl
read_device_id -cable 0 -host_name localhost
get_config_param <option_name> -chip PH1A60GEG324

# ERAM: program / read back / verify, or emit an SVF instead of driving hardware.
eram_operate -bit E:/work/demo.bit -cable 0 -host_name localhost -spd 1000
eram_operate -bit E:/work/demo.bit -read E:/work/eram_out.bin -cable 0 -host_name localhost
eram_operate -bit E:/work/demo.bit -svf E:/work/eram.svf -check_status

export_program_log -svf E:/work/demo_spi.svf
```

### 5.6 Encrypt-related programming commands

See §7 for the full encrypt-tool treatment. Programming-side names:

| Command | Syntax (verbatim from `help`) | PDF-documented? |
|---|---|---|
| `encrypt` | `encrypt -h -help -mode <string> -key <string> -key_file <string> -key_exp <string> -plain_bit <string> -plain_bas <string> -plain_hex <string> -plain_bin <string> -encrypt_bit <string> -encrypt_bas <string> -encrypt_bin <string> -encrypt_hex <string> -hd <string> -id <string> -plain_test <string> -encrypt_test <string> -hmac_key_file <string>` | **not documented**; mode set matches SWUG110 §4.2.2.1 [PROBE below] |
| `aes_encrypt` | `aes_encrypt -h -help -key <string> -key_file <string> -key_exp <string> -plain_bit <string> -plain_bas <string> -plain_bin <string> -encrypt_bit <string> -encrypt_bas <string> -encrypt_bin <string> -hd <string> -id <string> -plain_test <string> -encrypt_test <string>` | **not documented** |
| `hmac_bit` | `hmac_bit -input <string> -output <string> -hkey_file <string>` | **not documented** |

### 5.7 The `read_*` readback family, and `read_cfg…`

There is **no** `read_cfg*` command in TD 6.2.1. Verified absent:
`read_cfg` — not in `td_commands_all.txt`. The `read_` commands that exist and are
relevant to programming/readback are: `read_device_id`, `read_efuse`,
`read_flash` *(bw-only)*, `read_phy_data`, `read_pvt`, `read_sram` *(bw-only)*,
`read_cwc_data`, `read_cwc_reg`, `read_vpi_reg` *(and the unrelated design-side
`read_hdl`, `read_verilog`, `read_adc`, `read_sdc`, `read_pnl`, …)*.

### 5.8 Command-time error codes seen (verbatim)

```
PRG-8000 ERROR: host name is empty.
PRG-8000 ERROR: Unkown ON/OFF status.
PRG-8000 ERROR: -vec is an necessary argument.
PRG-8000 ERROR: Please specify the efuse name and value
PRG-8000 ERROR: Only support DR1M device
PRG-8000 ERROR: please select input file use -bit/bin
PRG-8000 ERROR: please using -bin parameter to specify output file.
PRG-8000 ERROR: open log file failed!
PRG-8000 ERROR: -partial parameter is necessary.
PRG-8000 ERROR: Please use -bin <string> or -key_exp to specify the input file
PRG-8001 ERROR: ProgramSvf:  Please specify the svf file name
PRG-8001 ERROR: SvfGen: Please specify the svf file name
PRG-8001 ERROR: MergeDualbootBit: Please specify a valid default bit file
PRG-8001 ERROR: Encrypt: Please specify the option: -mode <aes128/aes256/sm4>.
PRG-8100 ERROR: hmac: please use "-input" option to specify the input file
PRG-8511 ERROR: Encrypt:: key() should be made up of 32 hex numbers.
PRG-9505 ERROR: USB device open error, please re-connect the USB cable!
PRG-9525 ERROR: Chip validation failed! Please check the connection or type of chip!
PRG-9531 ERROR: PHY Configuration: -w/-r is necessary argument
KIT-1003 : compile_probe:  no probe has been added.
KIT-1004 : export chip watcher configuration to file(x) successfully.
KIT-8009 ERROR: Please specify an BRAM RID to read back.
KIT-8014 ERROR: Please specify a BRAM ID to write.
KIT-8211 ERROR: Please specify a cpc file(*.cpc).
USR-8001 ERROR: Option -file to choose pubkey
USR-8001 ERROR: please input -file option or -show_module option
```

Download-time codes from the TD error list [TD_User_Guide_V6.2, PRG table]:
`PRG-9518` ELF Flash register status error · `PRG-9519` Verify Flash error ·
`PRG-9520` cable already in use by another function · `PRG-9521` verify vs.
selected file mismatch · `PRG-9522` chip-erase failure (increase erase wait) ·
`PRG-9523` ELF download Done did not rise · `PRG-9525` device ID not found in the
supported library · `PRG-9526` **encrypted file used with a mode other than
`program_spi`/`verify_spi`** · `PRG-9527` dual-boot backup-region file missing ·
`PRG-9528` ELF internal-Flash write error · `PRG-9531` JTAG DDR register access
error · `PRG-5008` bitstream Feature value altered · `PRG-5009` recomputed CRC
mismatch.

### 5.9 Names checked and dropped

| Name | Status |
|---|---|
| `create_watcher` | **Not in `td_commands_all.txt`.** Dropped. |
| `read_cfg` / `read_cfg*` | **Not in `td_commands_all.txt`.** Dropped. |
| `program_spi`, `verify_spi`, `erase_spi`, `program_spibin`, `program_spidir`, `program_spidircustom`, `program_spief`, `program_dualboot`, `program_dualbootef`, `program_multibootef`, `program_featureef`, `program_encrypt_key`, `program_key_lock`, `read_flash`, `read_sram`, `create_flash_file`, `merge_flash_file`, `merge_files_for_svf`, `change_cpld_frame`, `gen_device_mapping`, `get_name_from_id`, `list_cable`, `split_tdo`, `insert_err`, `set_error`, `get_gui_param`, `set_gui_param`, `api_test`, `get_flash_manufacturer`, `get_flash_unique_id` | **Not TD commands** — they exist only in `bw_commands_prompt.exe` (§3.2). Listed there, excluded from the TD command tables. |

Commands referenced by the task and verified present: `download`, `program`,
`program_svf`, `svfgen`, `gen_aes_key_svf`, `rdbk_bram`, `rdbk_bram18`,
`rdbk_bram20`, `rdbk_bram32`, `write_bram`, `write_bram18`, `write_bram20`,
`write_bram32`, `eram_operate`, `program_efuse`, `ps_efuse_operate`,
`ps_tap_register_operate`, `read_efuse`, `export_program_log`, `gen_bsdl`,
`gen_partial_bit`, `get_bit_from_partial`, `merge_dualboot_bit`,
`gen_tandem_bit`, `gen_error_bit_file`, `read_device_id`.

---

## 6. OneCable hardware requirement (UG009)

### 6.1 What it is

**AL-LINK-FT** (product name `ANFPGA®-LINK-FT`) is Anlogic's current online
debugger/programmer; it is the hardware that implements the **OneCable** scheme.
It ships with a USB Type-B cable and a 2.54 mm 10-pin ribbon
[PDF:UG009 §1].

| Property | Value |
|---|---|
| Driver | **WinUSB** |
| Power | 5 V / 500 mA |
| Size / weight | 84 × 42.5 × 20 mm; net 43 g, gross 173 g |
| Packaging | 170 × 115 × 45 mm |
| Status LED | **red steady** = no VREF detected (check ribbon / target power); **green steady** = VREF present, usable; **green blinking** = operation in progress |
| VREF | supplied **by the target board**, 1.5 V ≤ VREF ≤ 3.3 V |

### 6.2 Supported devices and packages

"AL-LINK-FT 调试器及OneCable 调试系统支持上海安路信息科技股份有限公司全系列
FPSoC 器件，包括 **DR1M90、DR1V90** 等产品" [PDF:UG009 §1].

Cross-referenced against the live `list_devices` table, the `dr1` family and its
packages are:

| Device | Packages | Speed |
|---|---|---|
| `dr1_90` | DR1M90GEG400, DR1M90GEG484, DR1M90GEG484A, DR1M90MEG484, DR1V90GEG400, DR1V90GEG484, DR1V90MEG484 | 2/3 (GEG484A only 3) |

The same cable is also listed in SWUG110 as supporting 全系列FPSoC and usable for
PL-side JTAG download and ChipWatcher [PDF:SWUG110 §2.2].

### 6.3 JTAG signal definition (2×5, 2.54 mm)

[PDF:UG009 §2]

| Pin | Signal | Description | Direction (target-board view) |
|---|---|---|---|
| 1 | `TCK` | test clock | input |
| 3 | `TDO` | test data out | output |
| 4 | `VREF` | JTAG reference voltage (1.5–3.3 V, from target) | — |
| 5 | `TMS` | test mode select | input |
| 6 | `RSTN` | JTAG reset — *recommended not to connect* | — |
| 7 | `TXD` | target UART data in (from debugger UART out) | input |
| 8 | `RXD` | target UART data out (to debugger UART in) | output |
| 9 | `TDI` | test data in | input |
| 2, 10 | `GND` | — | — |

The debugger has **no internal pull-up/pull-down resistors** on JTAG signals;
add them on the target board — recommended value **4.7 kΩ** [PDF:UG009 §2].

### 6.4 Driver / installation requirement

Windows:
1. Connect the AL-LINK-FT to the PC.
2. Open **UsbDriverTool** (administrator rights). Two devices appear:
   `USB Serial Converter A` and `USB Serial Converter B`, both VID/PID **0403/6042**.
   A = USB→JTAG, B = USB→UART.
3. Select `USB Serial Converter A` → right-click → **Install WinUSB**.
4. Repeat for `USB Serial Converter B`, installing the **FTDI default driver
   (FTDI CDM)**. On success a virtual COM port number appears in Device Manager.

Troubleshooting [PDF:UG009 §6]: driver install failure → confirm no yellow
exclamation marks in Device Manager and (re)install the Anlogic FTDI/WinUSB
drivers; target not detected → check the status LED is green and the target is
connected and powered; serial port unresponsive → `USB Serial Converter B` must use
the FTDI default driver; HwServer/OpenOCD cannot see the AL-LINK-FT → check the
port-number rules, `Cable Select`, that no other program holds the cable, and that
no TD Download / CWC / PVT Sensor window is still open.

### 6.5 Three TD debug modes

Reached via `Tools → Debug Server Setting` [PDF:UG009 §4]:

| Mode | Meaning |
|---|---|
| **AL LINK OLD** | legacy AL-Link as the cable. **Old AL-Link does not support FPSoC PS-side C debugging** — only PL operations (bitstream download, CWC capture). |
| **AL-LINK-FT(Local Host)** | AL-LINK-FT driving a board attached to this PC. Configurable: `Local Port`, `JTAG CLK Freq`, `Cable Select` (+ `Refresh`). For FD+TD joint debug, **FD and TD must use the same port number**. |
| **AL-LINK-FT(Remote)** | AL-LINK-FT attached to another PC. That PC runs `HwServer`; the debugging PC adds a server entry with the hardware PC's IPv4/IPv6 address or a domain name and port. |

Port-number rules, applied to every port field in the documentation
[PDF:UG009 §4.2, §4.3, §5]:
1. > 1024 (0–1023 are well-known ports bound to specific services);
2. must be free;
3. must be permitted by the local firewall policy.

`HwServer` (from `<TD_ROOT>\bin\`) — **exact CLI recovered from the binary**
(UG009 shows the command line only inside a screenshot, so this replaces the image):

```text
Anlogic hwserver v1.0c (g1deb3940) Build Date 2024-12-09 17:36:53
Usage: hwserver.exe [-d] [-v|-r] [-V vid] [-p pid] [-f freq]
        -d: Enable debug messages
        -v: Use jtag_vpi protocol
        -r: Use remote bitbang protocol
        -x: Use TDRPC protocol
        -j: Use intel jtag server protocol
        -b: Use AL-LINK OLD adapter
        -z: Use Dummy adapter (only for debug)
        -l: List current available debug adapters
        -L: List current available debug adapters in csv format
        -s <port>: RBB server port (def. 5555)
        -w <port>: VPI server port (def. 5556)
        -c A|B|C|D: Select ftdi channel
        -V VID: Specify usb vid, (def. 0403)
        -p PID: Specify usb pid, (def. 6042)
        -I SN: Specify usb serial number
        -i ID: Specify usb bus id
        -f FREQ: Specify jtag clock frequency in MHz
```

This confirms UG009's prose: **port 5555** by default, **`-r`** selects the RBB
server that TD uses, **`-f 15`** sets a 15 MHz JTAG clock
[PDF:UG009 §4.3]. Example (windows hardware server):

```powershell
& "C:/Tools/Anlogic/TD_6.2.168116\bin\hwserver.exe" -r -s 5555 -f 15
```

### 6.6 What OneCable adds over plain JTAG

| Capability | Plain JTAG / old AL-Link | AL-LINK-FT (OneCable) |
|---|---|---|
| PL JTAG bitstream download | yes | yes |
| ChipWatcher (CWC) online capture | yes | yes |
| FLASH read/write and verify | limited | yes |
| **EMMC, NAND and other NVM program/verify** | no | **yes** |
| **PS-side C program on-chip debug (OpenOCD)** | **no** — old AL-Link explicitly cannot | **yes** |
| **UART serial communication** (2nd FTDI channel) | no | **yes** |
| **Remote debug over TCP/IP** | no | **yes** (`HwServer`) |
| **TD + FD joint debug over one cable** | no | **yes** (TD uses FD-OpenOCD's built-in RBB Server) |

Joint TD+FD procedure [PDF:UG009 §5]: set TD to OneCable local mode → optionally
download the bitstream from TD, then **close the download window** so the cable is
released (also close any CWC / PVT Sensor window, or FD's OpenOCD will fail to
start) → in FD, `Debug Configurations → Debugger`, set `Rbb port` equal to TD's
port (default **5555**) → optionally tick `Program FPGA` in the `Startup` tab and
choose a bitstream → run OpenOCD. While OpenOCD runs, TD can still download
bitstreams and capture CWC data through OpenOCD's RBB Server.
**Warning:** because TD depends on FD's OpenOCD RBB Server, keep OpenOCD running
during TD bitstream download / CWC capture; if you must close it, first let any
download finish or stop the CWC capture — otherwise TD's connection drops and the
program errors out.

---

## 7. Encrypt tool (SWUG113)

### 7.1 Two jobs, two tool sets

| Layer | Purpose | Commands / UI |
|---|---|---|
| **Source encryption** | Protect Verilog / SystemVerilog / VHDL source (IEEE-1735-style protected envelopes) | GUI `Tools → Encrypt Tool`; `hdl_encrypt`; `resource_encrypt` |
| **Bitstream encryption** | Encrypt the bitstream (AES128 / AES256 / SM4), generate the key SVF, HMAC the bitstream | `encrypt`, `aes_encrypt`, `hmac_bit`, `gen_aes_key_svf`; GUI `BitWriter → Encrypt` [PDF:SWUG110 §4.2.2] |
| **Licensing** | Generate / validate license files | `gen_license`, `generate_license`, `validate_license`, `val_license` |

### 7.2 Encrypt Tool GUI [PDF:SWUG113 §3, §4]

Open with `Tools → Encrypt Tool`. Two source panes:

* **Encrypt module all** (default) — encrypts whole files. If a file contains
  user-supplied 加密起止语 (encryption start/end pragmas), only the enclosed blocks
  are encrypted. Accepts **Verilog `.v`, VHDL `.vhd`/`.vhdl`, SystemVerilog `.sv`**.
* **Encrypt module body** — encrypts everything **except the module port list**;
  no pragmas needed. Supports only **Verilog `.v` and SystemVerilog `.sv`** — VHDL
  is **not supported** in this mode, and files that *do* contain encryption pragmas
  are rejected with an "encryption pragma nested" failure dialog.

Other controls:

| Control | Behaviour |
|---|---|
| `Add → Add Files / Add File Lists` | Add files directly, or add a `.list` file listing source paths |
| `Save path → Original path` | Output beside the source: `test.v → test.enc.vp`, `test.sv → test.enc.svp`, `test.vhd → test.enc.vhdp` |
| `Save path → Another path` | `Browse…` to choose an output folder (forced on when `Merge` is ticked) |
| `Merge` | ≥2 files of the **same language** merged into one output; default output name = module name of the first file + `enc` + extension; requires `Another path` |
| `Vendor Key` | **`anlogic-rsa-009` is mandatory and cannot be unchecked.** Additional keys (e.g. `MGC-VERIF_SIM_RSA-1`) may be ticked for third-party simulation. |
| `Key Seed` | Optional random seed of unlimited length. Same seed → identical ciphertext; different/absent seed → different ciphertext |

Resulting file names for the "all" example are `test.enc.vp / .svp / .vhdp`
[PDF:SWUG113 §3, §4.2].

### 7.3 Documented TCL invocation

The only TCL shown in SWUG113 [PDF:SWUG113 §3, item 5] — used to add user-defined
vendor keys because the GUI cannot:

```tcl
hdl_encrypt -file "xxx" -key "anlogic-rsa-009.pubkey user.pubkey"
```

* `-file` — source file(s) to encrypt; **multiple files separated by spaces**
* `-key` — vendor key(s); multiple `user.pubkey` separated by spaces;
  **must include `anlogic-rsa-009.pubkey`**

### 7.4 Full argument sets (live usage table)

| Command | Syntax (verbatim from `help`) | PDF |
|---|---|---|
| `hdl_encrypt` | `hdl_encrypt -help -file <string> -o <string> -lang <string> -merge <string> -key <string> -key_seed <string> -show_module <string>` | `-file`, `-key` documented in SWUG113 §3; the rest not documented |
| `resource_encrypt` | `resource_encrypt -help -file <string> -test` | **not documented in SWUG113** |
| `encrypt` | `encrypt -h -help -mode <string> -key <string> -key_file <string> -key_exp <string> -plain_bit <string> -plain_bas <string> -plain_hex <string> -plain_bin <string> -encrypt_bit <string> -encrypt_bas <string> -encrypt_bin <string> -encrypt_hex <string> -hd <string> -id <string> -plain_test <string> -encrypt_test <string> -hmac_key_file <string>` | **not documented in SWUG113**; the mode values match the GUI's `Encrypt mode (AES128/AES256/SM4)` [SWUG110 §4.2.2.1] |
| `aes_encrypt` | `aes_encrypt -h -help -key <string> -key_file <string> -key_exp <string> -plain_bit <string> -plain_bas <string> -plain_bin <string> -encrypt_bit <string> -encrypt_bas <string> -encrypt_bin <string> -hd <string> -id <string> -plain_test <string> -encrypt_test <string>` | **not documented** |
| `hmac_bit` | `hmac_bit -input <string> -output <string> -hkey_file <string>` | **not documented** |
| `gen_aes_key_svf` | no help entry; accepts `-bin`, `-key_exp` **[PROBE]** | **not documented** (GUI equivalent *Encrypt key svf file* [SWUG110 §4.2.2.1]) |
| `gen_license` | no help entry; returns `OK` with no arguments **[PROBE]** | **not documented** |
| `generate_license` | no help entry | **not documented** |
| `validate_license` | `validate_license -h -help -file <string> -feature <string>` | **not documented** |
| `val_license` | `val_license -h -help -f <string>` | **not documented** |

**[PROBE] raw evidence**

```
td > hdl_encrypt
USR-8001 ERROR: please input -file option or -show_module option

td > resource_encrypt
USR-8001 ERROR: Option -file to choose pubkey

td > encrypt
PRG-8001 ERROR: Encrypt: Please specify the option: -mode <aes128/aes256/sm4>.

td > aes_encrypt
PRG-8511 ERROR: Encrypt:: key() should be made up of 32 hex numbers.

td > hmac_bit
PRG-8100 ERROR: hmac: please use "-input" option to specify the input file

td > gen_aes_key_svf
PRG-8000 ERROR: Please use -bin <string> or -key_exp to specify the input file

td > validate_license
RUN-1001 : please specify a feature to be validate.

td > val_license
RUN-1001 : Open license file C:/Tools/Anlogic/TD_6.2.168116/license/Anlogic.lic
RUN-1001 : License validation success!
```

Facts these fix:

* `encrypt -mode` takes exactly **`aes128` / `aes256` / `sm4`** (lower-case, as
  printed by the tool).
* `aes_encrypt -key` must be **32 hex digits** (AES-128 key).
* `resource_encrypt -file` designates the **pubkey** (it is *not* a source file).
* `val_license` reads the default license at
  `<TD_ROOT>/license/Anlogic.lic` when no `-f` is given.

### 7.5 Copy-pasteable examples

> **VERIFIED END-TO-END (live TD 6.2.1).** The source-encryption path was run
> successfully and the result was synthesised. Two non-obvious details, both
> required to make it work:
>
> 1. **`-o` is a DIRECTORY, not a filename.** Passing a file path fails with
>    `USR-8001 ERROR: make path errno` (and leaves a 0-byte file behind). Omit
>    `-o` entirely and the output lands **next to the source** as
>    `<name>.enc.vp`, overwriting silently with only
>    `USR-6001 WARNING: file ... exist, cover it`.
> 2. **`-key` needs an absolute path** to the public key; a bare filename fails
>    with `read src keyfile ... failed` / `pubkey_message get failed`. The vendor
>    keys ship in `<TD_ROOT>/pubkey/`.
>
> **The generated `.enc.vp` is NOT directly readable by TD.** Passing it to
> `read_hdl`/`add_files` makes the module an undefined black box
> (`HDL-7144 CRITICAL-WARNING: instantiate unknown module ...`,
> `HDL-8007 ERROR: ... is a black box`). **Rename the output to `.v` and TD
> decrypts and elaborates it normally** — verified: with a `.v` extension the same
> bytes elaborate (`HDL-1007 : elaborate module ...`) and pass
> `optimize_rtl`/`optimize_gate`. So the delivery step is
> *encrypt → rename `.enc.vp` → `.v` → ship*.

```tcl
# --- source encryption (verified workflow) -------------------------------
set TD  {C:/Tools/Anlogic/TD_6.2.168116}
set OUT {E:/work/enc_out}
file mkdir $OUT

# -o is a directory. Result: $OUT/uart_tx.enc.vp  (5314 bytes for a 3 KB source)
hdl_encrypt -file E:/rtl/uart_tx.v -o $OUT -key $TD/pubkey/anlogic-rsa-009.pubkey
#   USR-1001 : encrypt success

# Then RENAME before use - TD will not read the .vp extension:
#   copy /y $OUT/uart_tx.enc.vp  E:/deliver/uart_tx.v

# Output is IEEE-1735 pragma-protect:
#   `pragma protect version = 1
#   `pragma protect encrypt_agent = "Anlogic"
#   `pragma protect key_keyowner = "Anlogic", key_keyname = "anlogic-rsa-009"
#   `pragma protect key_method = "rsa"
#   `pragma protect data_method = "AES128-CBC"

# Inspect a protected file's module list instead of encrypting:
hdl_encrypt -show_module "rtl/core.enc.vp"

# Key-resource encryption (argument is the public key, not source):
resource_encrypt -file "$TD/pubkey/anlogic-rsa-009.pubkey"
```

`<TD_ROOT>/pubkey/` contents (these are the `-key` inputs):

| Key file | Purpose |
|---|---|
| `anlogic-rsa-008.pubkey`, `anlogic-rsa-009.pubkey` | Anlogic's own vendor keys — use these for TD |
| `CDS_RSA_KEY_VER_1.pubkey` | Cadence |
| `MGC-VERIF-SIM-RSA-1/2.pubkey` | Mentor/Siemens |
| `SNPS-VCS-RSA-1/2.pubkey` | Synopsys |
| `UV-ENC-RSA-1.pubkey` | (vendor envelope key) |

Multiple keys can be supplied space-separated in one `-key` string, which is
what you want when a module must be readable by both TD and a third-party
simulator — encrypt once with the union of the keys the consumers hold.

```tcl
# --- bitstream encryption (mode values per the live error message) -------
encrypt -mode aes128 -key_file E:/work/aes.key -plain_bit E:/work/demo.bit \
        -encrypt_bit E:/work/demo_enc.bit -encrypt_bin E:/work/demo_enc.bin
encrypt -mode aes256 -key_file E:/work/aes.key -hmac_key_file E:/work/hmac.key \
        -plain_bit E:/work/demo.bit -encrypt_bit E:/work/demo_enc.bit
aes_encrypt -key 000102030405060708090A0B0C0D0E0F \
            -plain_bit E:/work/demo.bit -encrypt_bit E:/work/demo_enc.bit
hmac_bit -input E:/work/demo.bit -output E:/work/demo_hmac.bit \
         -hkey_file E:/work/hmac.key

# --- key SVF for eFuse programming ---------------------------------------
gen_aes_key_svf -key_exp E:/work/aes.key -svf E:/work/key.svf
gen_aes_key_svf -bin E:/work/key.bin

# --- licensing -----------------------------------------------------------
gen_license
validate_license -file <license_file> -feature <feature_name>
val_license -f E:/work/Anlogic.lic
```

### 7.6 IEEE-1735-style protected source — what is and is not recoverable

* SWUG113 describes 加密起止语 ("encryption start/end pragmas") as a **fixed
  format**, allows **multiple independent pairs per file**, and **forbids
  nesting**; it warns that incorrect pragma syntax silently changes the encrypted
  region or errors out [PDF:SWUG113 §4.1].
* **The pragma text itself was NOT recovered.** In the extracted PDF text, §4.1
  §4.2 and §4.3 consist only of figure captions —
  "图 4-1 90Verilog/System Verilog 加密起止语示例",
  "图 4-2 VHDL 加密起止语示例",
  "图 4-3 Verilog 多个加密起止语示例 (正确/错误)" — with **no code lines**, i.e.
  the examples live in raster images. Note also the extraction artefact `90Verilog`
  (a stray `90` prefixed to the caption).
* Consequently **no pragma spelling is asserted here**. The document also never
  uses the string "IEEE 1735"; the `.vp`/`.svp`/`.vhdp` output extensions and the
  mandatory `anlogic-rsa-009.pubkey` vendor key are the concrete, verifiable facts.
  Anyone needing the exact pragma must read the images in
  `SWUG113_Encrypt_Tool_User_Guide.pdf` pages 5–6.

---

## 8. Gap list

1. **SWUG111 documents no TCL.** All ChipWatcher/ChipProbe TCL syntax in §1 comes
   from the live interpreter (§0.2 [HELP]/[PROBE]), not from the named PDF.
2. **`create_watcher` does not exist**; `add_watcher_node`, `debug_deskew`,
   `report_cwc_status`, `test_mark_debug`, `read_cwc_data`, `read_cwc_reg`,
   `write_cwc_reg`, `write_cwc_vec`, `set_cwc` have no usage entry.
   `test_mark_debug` and `read_cwc_data` **crash the interpreter** when called with
   no arguments; `gen_bsdl` likewise.
3. **Ordering of the debug TCL flow** (§1.5) is [RECONSTRUCTED]; no document states it.
4. **`Mode_Macro` values are not documented as `download -mode` inputs.** The
   linkage is inferred; ten of the fifteen strings are not commands anywhere.
5. **`config.json` numeric `Device` IDs are opaque.** No mapping to family/package
   exists in any provided input (§4.5). This is the single largest unknown.
6. **`GoldenLock`, `DebugMode` and `ErrorMax` are never referenced by
   `Mode_Options_Mapping`** — they are unconditional in the dialog.
7. **`DefaultFlashSize` is missing for `Device` `"5"`.**
8. **Several `download` / `program` flags (`-s`, `-p`, `-ss`, `-sps`, `-xread`,
   `-wait`, `-v`, `-d`, `-tckCnt`) have no documented meaning.**
9. **The Encrypt Tool pragma syntax is image-only** (§7.6).
10. **`bw.exe` has no CLI switches**; `bw_commands_prompt.exe` is undocumented in
    SWUG110 and was characterised purely by execution.
11. **`gen_partial_bit` / `get_bit_from_partial` / `gen_tandem_bit` /
    `gen_error_bit_file` / `gen_bsdl` / `gen_aes_key_svf` / `program_efuse` /
    `read_efuse` have no usage entry**; their argument sets are partially known
    from [PROBE] error strings only.
12. **No PDF states the `.cwc`, `.data` or `.cpc` internal schema.** Only their
    roles and co-location rules are documented.
