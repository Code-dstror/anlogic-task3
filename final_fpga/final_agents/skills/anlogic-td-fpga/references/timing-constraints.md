# Anlogic TD 6.2.1 — Timing & Physical Constraints Reference

Everything an agent needs to write correct `.adc` (physical) and `.sdc` (timing) constraint
files for TD 6.2.1, plus the object-query commands the constraints are built from.

Primary sources:

| Source | What it gives |
|---|---|
| `SWUG200_Timing_Constraints_User_Guide.txt` (106 pp, 2024.09) | every SDC command, full argument list, worked examples, STA theory, typical scenarios |
| `SWUG105_TCL_Command_User_Guide.txt` § 4.3–4.4 | the same SDC commands as documented for TCL scripting, incl. `read_adc`/`read_sdc` staging rules |
| `TD_User_Guide_V6.2.pdf` § 9.1 (ADC) and § 9.2 (SDC) | the authoritative ADC attribute/value table and the supported-SDC-subset list |
| live `td_commands_all.txt` (740 commands) | existence check for every command named below |

> **Extraction warning.** SWUG200's command chapters extracted cleanly (parameter lists survived
> as bullet lists, examples survived as code). SWUG200's *scenario* chapter (§5, 49–97) has
> badly mangled ASCII timing diagrams — only the command lines were recovered from it. TD UG
> § 9.1/9.2 tables extracted with columns interleaved; the tables below were reassembled from
> the interleaved rows and are marked where reconstruction was needed.

---

## 1. Two-file model: ADC (physical) + SDC (timing)

| | ADC | SDC |
|---|---|---|
| Full name | Anlogic Design Constraint | Synopsys Design Constraint |
| Extension | **must** be `.adc` (else `USR-8063`) | `.sdc` |
| Covers | pin attributes (Bank, Location, IOSTANDARD, drive, pull, slew, diff resistor, PCI clamp, pack-reg, in/out delay, VCM/VOD) and cell placement | clocks, I/O delays, timing exceptions, clock groups |
| Read by | `read_adc <file>` (or `read_ip_adc -ip <ip> -file <f>` for IP-scoped) | `read_sdc [-ip <ip>] <file>` |
| Cleared by | `clear_adc` | `clear_sdc` / `clear_user_sdc` |
| GUI | IO Constraint editor | Timing Wizard (`Ctrl+Alt+T`) |

### 1.1 Staging rules (hard requirements)

```
read_adc  MUST run BEFORE optimize_rtl
read_sdc  (and read_sdc -ip) MUST run BEFORE optimize_gate or map_macro
read_sdc  MUST be run a SECOND time after legalize_phy_inst, before place/route
```

Verbatim from SWUG105 §3.2.1 and §3.3.1:

> 注：`read_adc` 需在 `optmize_rtl` 前执行，`read_sdc` 及 `read_sdc -ip` 需在 `optimize_gate`
> 或 `map_macro` 前执行。

and §4.5.7 (`legalize_phy_inst`):

> Tcl 脚本运行流程时，在 `optimize_gate` 或 `pack` 命令后需使用 `legalize_phy_inst`，并且
> 需要 `read_sdc` 再次读入 SDC 文件，然后执行布局布线相关命令。

So the canonical non-project-mode order is:

```tcl
import_device ph1_100.db -package PH1A100SFG676 -speed 2
read_hdl -file {./top.v} -top top
read_adc ./top.adc            ;# BEFORE optimize_rtl
optimize_rtl
read_sdc ./top.sdc            ;# BEFORE optimize_gate
optimize_gate
legalize_phy_inst
read_sdc ./top.sdc            ;# read SDC AGAIN before place
place
route
bitgen -bit ./top.bit
```

### 1.2 GUI staging notes (same rules, expressed as GUI gates)

* `Add ADC File` and the `IO Constraint` editor are greyed out until **Syn Opt → Read Design**
  has completed.
* `Add SDC File` / `Timing Wizard` require **Syn Opt → Optimize RTL** to have completed;
  opening the Timing Wizard after Optimize RTL raises a warning that changes will not restart
  the Optimize RTL stage.
* A project may contain **multiple** `.adc` and multiple `.sdc` files in one constraint set.
  All added files default to *enabled*; they are parsed in the order added. Enable/disable via
  right-click → `File Properties`.
* `Save to adc file` writes all constraints into the normal ADC; `Save to phy-only adc file`
  writes only the physical (region/placement) part.

---

## 2. ADC file syntax

### 2.1 Pin constraints

```
set_pin_assignment  {pin_name}  {attributes}
```

* `pin_name` — the top-level port name. **Scalar ports go in braces**: `{sys_clk}`.
  Verbatim from the DRC list (`USR-8052`): naming a multi-bit port directly is an error
  ("指定的引脚名字有误或者指定了多位宽port 名") — index it, e.g. `{data[0]}`.
* `attributes` — one braced group containing `NAME = VALUE;` pairs separated by **semicolons**.
  Whitespace around `=` and `;` is free-form.
* Once an ADC file is added, **every port must have a LOCATION** (`USR-8056`: "LOCATION 没有指定
  必须指定"). Duplicate locations are rejected (`USR-8055`, `USR-8065`).
* A differential standard may only be constrained on the **positive** pin (`USR-8066`:
  "双端IO 标准只能约束pos 端"); TD then auto-assigns the negative side of the pair.

Canonical example (TD UG § 9.1, verbatim):

```
set_pin_assignment {sys_clk} {LOCATION=P23; IOSTANDARD=LVCMOS18;
DRIVESTRENGTH=4; PULLTYPE=PULLUP; SLEWRATE=MED; PCICLAMP=ON;
PACKREG=ON; OUTDEL=1;}
```

Multi-pin realistic form (spacing normalised; the semicolon-separated attribute block is the
part that must be verbatim):

```
set_pin_assignment { i_clk       } { LOCATION = A10; IOSTANDARD = LVCMOS33; }
set_pin_assignment { i_rst_n     } { LOCATION = B11; IOSTANDARD = LVCMOS33; }
set_pin_assignment { o_uart_tx   } { LOCATION = A13; IOSTANDARD = LVCMOS33; }
```

LVDS with VCM/VOD (TD UG § 9.1, verbatim):

```
set_pin_assignment {sys_clk} { LOCATION = A3; IOSTANDARD = LVDS33; VCM = 0.8; VOD = 350m }
```

### 2.2 Supported pin attributes and values

TD UG § 9.1 Table 9-1 says **10 attributes**: `BANK, LOCATION, IOSTANDARD, DRIVESTRENGTH,
PULLTYPE, PREEMPHASIS, SLEWRATE, DIFFRESISTOR, PCICLAMP, PACKREG` — with `InDelay` and
`OutDelay` additionally described in the IO-editor table (§4.1.2) and used as `INDEL` / `OUTDEL`
in the ADC example above. Treat the following as the full working set.

| Attribute | Valid values | Notes |
|---|---|---|
| `BANK` | `BANK1` … `BANK8` | Optional if `LOCATION` is given; TD derives the bank. **Bank list is device/package dependent** — `query_current_package -fio` prints the real bank list (e.g. `0|11|12|13|32|33` for PH1A60GEG324), so the `BANK1..8` enumeration in the UG is a generic template, `[RECONSTRUCTED]` as an exhaustive list. |
| `LOCATION` | Pin name (e.g. `P23`, `A10`) — package specific. Also accepts `VirtualIO`. | Setting `VirtualIO` puts the port on a non-physical IO: no bank, no routing resource, no electrical parameters. Once any ADC exists all ports must be located. |
| `IOSTANDARD` | `LVCMOS12`, `LVCMOS15`, `LVCMOS18`, `LVCMOS25`, `LVCMOS33`, `LVDS25`, `LVDS25_E`, `LVDS33`, `LVDS33_E`, `PCI33`, `LVTTL33`, `LVPECL33`, `LVPECL33_E` | Direction-restricted for differential: **input** may use `LVDS25`, `LVDS33`, `LVPECL33`; **output** may use `LVDS25_E`, `LVDS33_E`, `LVPECL33_E`. `_E` = emulated LVDS output (no pre-emphasis). Standard support is per-family — check the datasheet. Violations raise `USR-8057` (`...不能设LVDS25_E`) / `USR-8058` (`...不能被设置LVDS25`). Default is `LVCMOS25` for many devices. |
| `DRIVESTRENGTH` | `2`, `4`, `8`, `12`, `16`, `20`, `NA` | mA. Per-standard capability differs (e.g. LVCMOS25 is 4/8/12/16). Larger = stronger. |
| `PULLTYPE` | `PULLUP`, `PULLDOWN`, `NONE`, `KEEPER` | For differential standards only `NONE` is legal. `KEEPER` holds the last driven level. |
| `SLEWRATE` | `FAST`, `MED`, `SLOW` | Single-ended outputs. |
| `DIFFRESISTOR` | `100`, `NONE` | Differential inputs; 100 Ω on-die termination. |
| `PCICLAMP` | `ON`, `OFF` | Single-ended in/out; PCI-level clamp. |
| `PACKREG` | `AUTO`, `ON`, `OFF` | Pack the register into the pad. `AUTO` follows the global `pack_seq_in_io` parameter; explicit `ON`/`OFF` has higher priority. |
| `PREEMPHASIS` | (device dependent) | Pre-emphasis on LVDS **outputs** only; irrelevant for `*_E` emulated LVDS. Same-bank consistency required (`USR-8100`: at most one `PRE_EMP` value per bank). |
| `VCM` | `0.8`, `0.9`, `1.2` (V) | **Only for `LVDS25`/`LVDS33`.** Not supported on EF2. Default `1.2`. |
| `VOD` | `150`, `200`, `250`, `350`, `480` (mV) | **Only for `LVDS25`/`LVDS33`.** Default `350`. Setting `480` is discouraged. One `VOD` per bank (`USR-8090`). |
| `INDEL` / `InDelay` | device/IOB dependent | Input delay adjustment. |
| `OUTDEL` / `OutDelay` | device/IOB dependent | Output delay adjustment. |

VCM/VOD ranges from TD UG Table 9-2 (extracted with columns interleaved; rows reassembled
`[RECONSTRUCTED]`):

| Device | VOD (mV) | VCM (V) |
|---|---|---|
| `EG4` | 150, 200, 250, **350***, 480 | 0.8, 0.9, **1.2*** |
| `EF2` | 150, 200, 250, **350***, 480 | not supported |
| `EF3` | 150, 200, 250, **350***, 480 | 0.8, 0.9, **1.2*** |
| `AL3` | 150, 200, 250, **350*** | 0.8, 0.9, **1.2*** |

`*` = software default. Out-of-table values are rejected.

### 2.3 Cell (instance) placement constraints

```
set_inst_assignment {inst_name} {location = x34y37z0;}
```

* `inst_name` — the instance name. Find it in the post-synthesis netlist
  (`prj_gate_sim.v`) or in Chip Viewer. Hierarchical instances use `|`, e.g.
  `{_al_u451|lcd/lcd_rs_reg}`.
* The only supported attribute is `location`; the coordinate format is `x<X>y<Y>z<Z>`,
  which is the same `Location` column that `query_current_package -fio` prints.

Examples (TD UG § 9.1, verbatim):

```
set_inst_assignment {PLL_INST1} {location = x34y37z0;}
set_inst_assignment {PLL_INST2} {location = x0y0z0;}
set_inst_assignment { _al_u451|lcd/lcd_rs_reg} {location = x21y17z1;}
```

Related bound/region commands (exist in the live command list; only the error-message-mandated
syntax was recoverable from the PDFs — marked `[RECONSTRUCTED]` from `USR-8077`/`USR-8081`/
`USR-8083`):

```
create_bound {bound_name} -mode {auto|floating|fixed} -auto_effort {low|medium|high} \
            -width {int} -height {int} -origin {int int} -excluded {slice dsp bram} -reserved
add_cells_to_bound -bound {bound_name} -cells {cell_list} -top
remove_cells_from_bound -bound {bound_name} -cells {cell_list}
remove_bound {bound_name}
```

`-top` and `-cells` are mutually exclusive (`USR-8082`). Bound matching needs logic hierarchy
preserved: if `keep_hierarchy` is `flatten`, switch it to `auto` or `manual` (`USR-8088`).

### 2.4 Programmatic ADC manipulation

| Command | Purpose |
|---|---|
| `read_adc <file_path_name>` | read an ADC file into the current design |
| `read_ip_adc -ip <ip_model_name> -file <file_path_name>` | read an ADC scoped to a specific IP instance |
| `clear_adc` | drop all ADC constraints (then `read_adc` a replacement) |
| `export_adc [<file>]` | write current pin/cell constraints out as ADC |
| `add_back_anno_adc [<file>]` | back-annotate: derive/patch pin locations into ADC |
| `clear_inst_adc` | clear instance-level ADC |
| `import_ip_pin_list`, `import_io_table`, `import_io_liberty` | bulk pin/location import |
| `set_ippin_assignment`, `set_sippin_assignment`, `set_prpin_assignment`, `set_ipinst_assignment`, `set_pin_const_value` | IP- and instance-scoped pin/constant assignment variants |
| `print_iob_timing_diff`, `report_io`, `check_io`, `export_io`, `export_io_lib` | IO inspection and export |

`clear_adc` / `read_adc` replacement pattern (SWUG105 § 4.3.5):

```tcl
clear_adc
read_adc my_new_pin_location.adc
```

### 2.5 `query_current_package` — pin selection depends on this

```
query_current_package -fio
query_current_package -clock_io
query_current_package -lvds
query_current_package -single_ended
```

All four are **console-printing** commands: they return an empty string in TCL. Run them after
`import_device`, and read the log.

| Option | Prints |
|---|---|
| `-fio` | Functional IOs. Header `Idx | PE | Location | Type | IntBank | ExtBank`; also prints `List of IO Banks: ...` and `Package <name>`. `Type` values seen: `fio (hd)`. `Location` is the `x…y…z…` coordinate. |
| `-clock_io` | Clock-capable pads. Header `Sector | Location | Name | Config | IntBank | ExtBank`; `Config` = `gclkio0` … `gclkio3`; un-bonded entries show `-`. Use this to pick a clock input for `create_clock`. |
| `-lvds` | Legal differential pairs. Header `# | Type | IntBank | ExtBank | Name <[P],[N]> | Location <[P],[N]>`, e.g. `1 | LVDS | 11 | 11 | <A10 , A9> | <X0Y17Z0 , X0Y17Z1>`. Only the `<P>` name may appear in `set_pin_assignment`. |
| `-single_ended` | Single-ended IOs. Header `IO | Location`, e.g. `d10 | x0y7z3`. Note dedicated JTAG pins appear as `e10 | tck`, `e11 | tdi`, `e12 | tms`, `e13 | tdo`. |

Companion queries: `query_current_arch`, `list_devices`, `get_device_param`,
`get_inst_info`, `report_device_resource`, `print_iob_dvalue`, `print_no_highz_pins`.

---

## 3. SDC — object query commands

These are the building blocks for every constraint's `-from` / `-to` / `-through` / target.

### 3.1 Summary table

| Command | Returns | Syntax |
|---|---|---|
| `all_clocks` | all clocks in the design | `all_clocks [-o]` |
| `all_inputs` | all input **and bidirectional** ports | `all_inputs [-o]` |
| `all_outputs` | all output **and bidirectional** ports | `all_outputs [-o]` |
| `all_registers` | all registers | `all_registers [-o]` |
| `get_ports` | user-named input/output/inout **top-level** ports | `get_ports [-nocase] [-nowarn] [-o] <filter>` |
| `get_cells` | cell instances | `get_cells [-hierarchical] [-hier] [-nocase] [-nowarn] [-o] <filter>` |
| `get_nets` | nets | `get_nets [-hierarchical] [-hier] [-nocase] [-nowarn] [-o] <filter>` |
| `get_regs` | registers | `get_regs [-hierarchical] [-hier] [-nocase] [-nowarn] [-o] <filter>` |
| `get_pins` | pins of ports or cells (**not** package pins) | `get_pins [-hierarchical] [-hier] [-nocase] [-nowarn] [-o] <filter>` |
| `get_clocks` | clocks defined in the SDC | `get_clocks [-include_generated_clocks] [-nocase] [-nowarn] [-v] [-o] <filter>` |

### 3.2 Option semantics

* `-o` — *"return the translated name"*, added after TD 5.6. SWUG200 marks it **required**
  ("必选项") in every object-query chapter. Always pass `-o`.
* `-hierarchical` / `-hier` — recursive match at every hierarchy level. **Default mode requires
  the full hierarchical path**, where `/` separates levels. With `-hier`, you supply only the
  leaf name and TD recurses.
* `-nocase` — case-insensitive match.
* `-nowarn` — suppress the warning when nothing matches (otherwise an unmatched filter warns or
  errors).
* `<filter>` — one or more glob patterns. Multi-pattern form uses braces:
  `get_cells { A* B* C* }`, `get_pins { A*.o B*.o C*.i }`, `get_ports *`,
  `get_nets { A* B* C* }`.
* `get_clocks` extras: `-include_generated_clocks` (also return every generated clock derived
  from the matched master clocks); `-v` (inverse selection — everything *except* `<filter>`).

### 3.3 Object-model rules that bite

* `cell` = an instantiated module (RTL) or a post-synthesis primitive (LUT / RAM / DSP / PLL).
* `reg` = a register. `get_regs` works by first finding the net driven by the register's `Q`
  and then resolving the register name, so **`get_regs` name rules are identical to
  `get_nets` name rules**.
* `pin` = a signal pin *of a cell or port* — not a package pin. Use `get_ports` for package
  ports.
* `net` naming priority: (1) net attached to an I/O port is named after the port; (2) the net on
  a register `Q` is named after the register; (3) a user `wire` keeps its wire name.
  **Only categories (1) and (2) — plus top-level port nets — are safe to reference by name.**
  Category (3) nets, and any net generated during RTL→gate optimization, may be renamed or
  removed. Do not build constraints on arbitrary wire names.
* Hierarchy separator is `/` (e.g. `u_pll/pll_inst.clkc[0]` → cell `pll_inst` inside `u_pll`,
  pin `clkc[0]`). Parallel (`|`) and membership (`.`) separators appear in *timing-report* path
  names, not in constraint filters.

Examples:

```tcl
all_clocks -o                          ;# -> clocks: sys_clk
all_inputs -o                          ;# -> ports: sys_clk sys_rstn
all_outputs -o                         ;# -> ports: beep
all_registers -o                       ;# -> regs: test_reg1 test_reg2 test_reg3
get_ports *                            ;# -> Ports: beep sys_clk sys_rstn
get_cells -o -nocase reg               ;# case-insensitive exact-ish match
get_cells -o reg*                      ;# prefix match
get_cells -o A*                        ;# every cell starting with A
get_nets -o beep
get_nets -o reg*
get_regs -o -nocase reg
get_pins -o -nocase *.reg
get_pins -o *.*reg*
get_clocks -o *                        ;# -> clocks: sys_clk
```

---

## 4. SDC — clock definition commands

### 4.1 `create_clock`

```
create_clock -name {<clock name>} -period <time ns> [-waveform {<rise ns> <fall ns>}] \
             [<Target>] [-add]
```

| Argument | Meaning |
|---|---|
| `-name {<clock name>}` | **Mandatory**; error if omitted. The name is used by all other constraints and in reports. Under `-add`, the name is also mandatory (`USR-8104`). |
| `-period <time ns>` | Mandatory, positive, up to 3 decimal places. Legal range `(2 ps … INT_MAX/1001 ps)`; violation → `USR-8103`; non-numeric or negative → `USR-8102`. |
| `-waveform {<rise> <fall>}` | First rising and first falling edge times in ns (3 decimals). Omitted ⇒ phase 0, 50 % duty. Values outside the period error out. **Only two edges per period are supported.** |
| `[<Target>]` | Clock source point — normally an I/O package pin (`get_ports`) or a hard-core clock pin (`get_pins`, e.g. recovered serdes RX clock, internal oscillator). **Omit the target to define a virtual clock.** |
| `-add` | Add another clock on the same target instead of overwriting it. Without `-add`, the last `create_clock` on a target wins. Use for clock-MUX pins. |

Examples (SWUG200 § 3.2.4, verbatim):

```tcl
# 1. standard
create_clock -name clk_25m -period 40.000 -waveform {0.000 20.000} [get_ports {clk_25m}]
# 2. no -waveform
create_clock -name clk_25m -period 40.000  [get_ports {clk_25m}]
# 3. different phase
create_clock -name clk_50m -period 20.000 -waveform {5.000 15.000} [get_ports {clk_50m}]
# 4. different duty cycle
create_clock -name clk_100m -period 10.000 -waveform {0.000 3.000} [get_ports {clk_100m}]
# 5. -add, different frequency
create_clock -name clk_25m_add -period 50.000 -waveform {0.000 25.000} \
    [get_ports {clk_25m}] -add
# 6. -add, different frequency and duty
create_clock -name clk_50m_add -period 5.000 -waveform {0.000 3.000} \
    [get_ports {clk_50m}] -add
# 7. -add, different frequency, duty and phase
create_clock -name clk_100m_add -period 10.000 -waveform {1.000 5.000} \
    [get_ports {clk_100m}] -add
# 8. virtual clock (no target)
create_clock -name clk_virtual -period 10.000 -waveform {0.000 5.000}
# 9. hard-core serdes clock
create_clock -name clk_rserdes_1 -period 6.400 -waveform {0.000 3.200} \
    [get_pins {u_serdes_top/u_dual_hss/serdes_dual_inst.l0_rx_out2clk}]
```

Terminology: a **primary clock** enters through an external pin (or is emitted by a hard core
such as serdes CDR / internal oscillator). A **virtual clock** is not physically connected to
any netlist object and is the normal tool for I/O-delay constraints when the reference clock
does not exist inside the FPGA.

### 4.2 `create_generated_clock`

```
create_generated_clock -name <clock name> -source [<source>] [-master_clock <clock name>] \
    (-divide_by <factor> | -multiply_by <factor> | -edges {<e0> <e1> <e2>}) \
    [-edge_shift {<s0> <s1> <s2>}] [-invert] [-phase <0..360>] [-duty_cycle <0..100>] \
    [<Target>] [-add]
```

| Argument | Meaning |
|---|---|
| `-name <clock name>` | Mandatory. |
| `-source [<source>]` | Clock source point of the generated clock — any physically existing clock node (`get_pins` / `get_ports` / `get_nets`). |
| `-master_clock <clock name>` | Which driving clock on that source point is the master (one source point may carry several constrained clocks). |
| `-divide_by <factor>` | Positive, 3 decimals. **Mutually exclusive** with `-multiply_by` and `-edges`. |
| `-multiply_by <factor>` | Positive, 3 decimals. Mutually exclusive with the other two. |
| `-edges {<edge0> <edge1> <edge2>}` | Integer edge numbers of the **source** clock: source `<edge0>` → 1st rising edge of generated clock; `<edge1>` → 1st falling; `<edge2>` → 2nd rising. `edge0 >= 1`. |
| `-edge_shift {<s0> <s1> <s2>}` | Only legal together with a 3-integer `-edges`. Shifts each edge in ns; positive = later, negative = earlier. |
| `-invert` | Used together with `-divide_by`/`-multiply_by`; inverts the generated waveform. |
| `-phase <phase_num>` | Phase shift in degrees, `0 … 360`, 3 decimals. Values > 360 are taken modulo 360. |
| `-duty_cycle <duty_cycle_num>` | Duty cycle in percent, `0 … 100`, 3 decimals. **Used together with `-multiply_by`.** |
| `[<Target>]` | Generated-clock start point inside the FPGA. |
| `-add` | Add another generated clock on the same target. **Unlike `create_clock`, a second `create_generated_clock` on a target without `-add` is silently ignored** rather than overwriting (SWUG105/TD UG § 9.2). |

Exactly one of `-divide_by` / `-multiply_by` / `-edges` may be used. The input clock may be a
primary clock or another generated clock. A generated clock belongs to its master's clock
domain and reports the same start point as the master.

Examples (SWUG200 § 3.3.4 verbatim — note the source text has `multiply_by` and `-divede_by`
typos; correct spellings shown):

```tcl
# divide-by-2 with 180 degree phase
create_generated_clock -name pll_gen1 -source [get_pins {u_pll/pll_inst.clkc[0]}] \
    -divide_by 2 -phase 180 [get_nets {u_buttons_led0/clk_25m}]
# multiply-by-2 with 40% duty
create_generated_clock -name pll_gen2 -source [get_pins {u_pll/pll_inst.clkc[1]}] \
    -multiply_by 2 -duty_cycle 0.4 [get_nets {u_buttons_led1/clk_25m}]
# explicit edges + edge shift
create_generated_clock -name clk_50m -source [get_ports {clk_200m}] \
    -master_clock [get_clocks {clk_200m}] -edges {1 5 9} -edge_shift {-1 1 -1} \
    [get_nets {clk_50m}]
```

TD UG § 9.2 gives a fourth form (source text mis-spells the command as
`create_generation_clock`):

```tcl
create_generated_clock -divide_by 1.25 -source [get_ports clk] -name sys_clk [get_ports sys_clk]
```

### 4.3 `derive_clocks` (bulk auto-constraint of clock cells)

```
derive_clocks [-instance [<instance>]]
```

Without `-instance`, TD auto-constrains **every** clock cell in the design (PLL, LCLK, DBUF,
DBUF_HXT, …). The generated clock name is `"<cell name>.<output pin name>"`, and its frequency
and phase follow the cell's internal parameters exactly. The **reference clock must still be
constrained by the user.**

```tcl
derive_clocks -instance [get_cells {u_pll/pll_inst}]   ;# just one PLL
derive_clocks                                          ;# all clock cells
```

TD UG § 9.2 documents an equivalent/older command `derive_pll_clocks` whose generated-clock
name is `"PLL 单元名.PLL 输出接口名"`:

```tcl
derive_pll_clocks
```

### 4.4 `rename_clock`

```
rename_clock -name <clock name> [<Target>]
```

Only meaningful **after** `derive_clocks` (it renames auto-derived clocks). Normally driven by
Timing Wizard.

```tcl
derive_clocks
rename_clock -name {pll_l} [get_clocks {u_pll_clk/pll_inst.clkc[0]}]
rename_clock -name {pll_2} [get_clocks {u_pll_clk/pll_inst.clkc[1]}]
rename_clock -name {pll_3} [get_clocks {u_pll_clk/pll_inst.clkc[2]}]
```

### 4.5 `set_clock_latency`

```
set_clock_latency <delay value> [-min] [-max] [-rise] [-fall] [-early] [-late] \
                   [-source] [-clock] [<Target>]
```

| Argument | Meaning |
|---|---|
| `<delay value>` | Delay in ns, 3 decimals. |
| `-min` | Analyse at the **fast** corner. |
| `-max` | Analyse at the **slow** corner. |
| `-rise` / `-fall` | Apply to the rising / falling clock edge. |
| `-early` / `-late` | Minimum / maximum source delay within the same corner. |
| `-source` | This is **source latency** (off-chip, PCB). Without `-source` the value is **network latency**, which post-route STA replaces with the real routed delay. |
| `[<Target>]` | A `pins` or `clocks` collection; pins mean "the clock on those pins". Multiple clocks may be listed at once. |
| `-clock` | Only needed when the target is a pin driven by more than one clock — names which clock to apply to. |

```tcl
set_clock_latency -late  -source 1.2 [get_clocks {clk_25m}]
set_clock_latency -early -source 0.9 [get_clocks {clk_25m}]
set_clock_latency -source 1 [get_clocks {clk_50m}]
set_clock_latency 2 [get_clocks {clk_100m}]              ;# network latency
set_clock_latency -source 1 [get_clocks {pll_1 pll_2 pll_3}]
set_clock_latency 1.2 -rise [get_clocks CLK1]
set_clock_latency 0.9 -fall [get_clocks CLK1]
```

TD UG § 9.2 spells the `-clock` form as
`set_clock_latency -clock <list> -max -min -source target delay`, e.g.
`set_clock_latency -clock [get_clocks {clk_vga_25m}] -source 2`.

**Documentation defect:** TD UG § 9.2 also documents `remove_clock_latency -clock <list>
-source target`. **`remove_clock_latency` does not exist in TD 6.2.1** (absent from the live
740-command list). Use `clear_sdc` / re-issue the constraint instead.

### 4.6 `set_clock_uncertainty`

```
set_clock_uncertainty [-setup | -hold] <uncertainty value> [<Target>]
```

| Argument | Meaning |
|---|---|
| `-setup` | Value applies to max-delay (setup) analysis — *reduces* the setup required time. |
| `-hold` | Value applies to min-delay (hold) analysis — *increases* the hold required time. |
| (neither) | Applies to **both** checks. |
| `<uncertainty value>` | ns, 3 decimals. |
| `[<Target>]` | One clock or a list of clocks. |

Models clock skew and jitter. **Only per-clock uncertainty is supported — cross-clock-domain
uncertainty is not.** Primary-clock uncertainty is **not** propagated to downstream generated
clocks.

```tcl
set_clock_uncertainty -setup 1 [get_clocks {pll_2}]
set_clock_uncertainty -hold 1.1 [get_clocks {pll_2}]
set_clock_uncertainty 1.3 [get_clocks {pll_3}]
set_clock_uncertainty 1.3 [get_clocks {pll_1 pll_2 pll_3}]
set_clock_uncertainty 1.3 [all_clocks]
set_clock_uncertainty -setup -hold 0.5 [get_ports clk]    ;# TD UG form
```

**Documentation defect:** TD UG § 9.2 also documents
`remove_clock_uncertainty -setup -hold target`. **`remove_clock_uncertainty` does not exist in
TD 6.2.1** (absent from the live command list).

### 4.7 `set_clock_sense`

```
set_clock_sense -stop_propagation [-clocks [<list>]] [<Target>]
```

Stops the named clocks from propagating past the target netlist object. `[<Target>]` must be a
`pins` or `ports` collection. Without `-clocks`, every clock passing through the target is
affected.

```tcl
set_clock_sense -stop_propagation -clocks [get_clocks {clk_1}] [get_pins { rx_a_mux.o }]
```

### 4.8 `set_clock_route_enforce` / `set_clock_route`

```
set_clock_route_enforce [<net name>]
set_clock_route         [<net name>]
```

* `set_clock_route_enforce {net}` — force this clock net onto the **dedicated global clock
  interconnect only**. Use for multi-bank source-synchronous clocks to guarantee low skew.
* `set_clock_route {net}` — force this clock net to **not** use the dedicated global clock
  interconnect. Needed when the design has more clocks than the device has global clock
  resources. If you specify one clock manually you must specify **all** of them. Ignored if the
  RTL explicitly instantiates a BUFG-type resource.

**These two commands are mutually exclusive** — never use both in one design. Choosing wrong can
make place-and-route fail; TD emits an error at that point.

```tcl
set_clock_route_enforce {clk_1_net}
set_clock_route {clk_1_net}
```

---

## 5. SDC — I/O delay commands

### 5.1 `set_input_delay`

```
set_input_delay -clock <clock name> [-min | -max] <delay value> [<Target>] \
    [-add_delay] [-clock_fall] [-source_latency_included] [-network_latency_included] \
    [-reference_pin <pin>]
```

| Argument | Meaning |
|---|---|
| `-clock <clock name>` | The reference clock for this input delay. |
| `-max <value>` | Max input delay — used for **setup** analysis. |
| `-min <value>` | Min input delay — used for **hold** analysis. |
| `-add_delay` | Accumulate with other `set_input_delay` values on the same port. Without it, a later constraint on the same clock+pin **overwrites** the earlier one. |
| `-clock_fall` | Measure relative to the clock's **falling** edge; must be used with `-clock`. |
| `-source_latency_included` | The specified delay already contains clock source latency; TD subtracts it. |
| `-network_latency_included` | The specified delay already contains clock network latency; TD subtracts it. |
| `-reference_pin <pin>` | Reference point on the clock tree; TD uses that node's source and network latency. |
| `<delay value>` | ns, 3 decimals. May be negative. |
| `[<Target>]` | List of **input ports** only. |

System-synchronous vs source-synchronous: in system-synchronous mode the launch clock is the
external device's transmit clock (use a **virtual clock** if it is not present in the FPGA) and
the capture clock is the FPGA's internal sampling clock. If the launch clock also originates
inside the FPGA, TD automatically accounts for its internal delay.

```tcl
set_input_delay -clock [get_clocks clk_virtual] -min 2.000 [get_ports {{button[0]} {button[1]}}]
set_input_delay -clock [get_clocks clk_virtual] -max 8.000 [get_ports {{button[0]} {button[1]}}]
set_input_delay -max 0.8 -clock [get_clocks virtual_clk_d] -add_delay [get_ports {d_rgmii_rxdv}]
set_input_delay -min -0.6 -clock [get_clocks virtual_clk_d] -add_delay [get_ports {d_rgmii_rxdv}]
set_input_delay -max 0.8 -clock_fall -clock [get_clocks virtual_clk_d] -add_delay [get_ports {d_rgmii_rxdv}]
set_input_delay -min -0.6 -clock_fall -clock [get_clocks virtual_clk_d] -add_delay [get_ports {d_rgmii_rxdv}]
# TD UG condensed form
set_input_delay -clock sys_clk 1.0 [all_inputs]
```

Source-synchronous SDR/DDR templates (SWUG200 § 5.2, prose garbled but command lines intact):

```tcl
# SDR, edge-aligned
set_input_delay -clock input_clock -max max_delay [get_ports input_data]
set_input_delay -clock input_clock -min min_delay [get_ports input_data]
# SDR, falling-edge sampling
set_input_delay -clock input_clock -max max_delay -clock_fall [get_ports input_data]
set_input_delay -clock input_clock -min min_delay -clock_fall [get_ports input_data]
# DDR (rise and fall both constrained)
set_input_delay -clock input_clock -max rise_max_delay [get_ports input_data]
set_input_delay -clock input_clock -min rise_min_delay [get_ports input_data]
set_input_delay -clock input_clock -max fall_max_delay -clock_fall [get_ports input_data]
set_input_delay -clock input_clock -min fall_min_delay -clock_fall [get_ports input_data]
```

### 5.2 `set_output_delay`

```
set_output_delay -clock <clock name> [-min | -max] <delay value> [<Target>] \
    [-add_delay] [-clock_fall] [-source_latency_included] [-network_latency_included] \
    [-reference_pin <pin>]
```

Identical option semantics to `set_input_delay` (with "output" substituted). `[<Target>]` must
be **output ports**. Output delay may be positive or negative; the sign just says which side of
the clock edge the data sits on.

```tcl
set_output_delay -clock [get_clocks clk_virtual] -min 2.000 [get_ports {{button[0]} {button[1]}}]
set_output_delay -clock [get_clocks clk_virtual] -max 8.000 [get_ports {{button[0]} {button[1]}}]
set_output_delay -clock output_b_clk -max 1.0  [get_ports {b_rgmii_txdv}] -add_delay
set_output_delay -clock output_b_clk -min -0.8 [get_ports {b_rgmii_txdv}] -add_delay
set_output_delay -clock output_b_clk -clock_fall -max 1.0  [get_ports {b_rgmii_txdv}] -add_delay
set_output_delay -clock output_b_clk -clock_fall -min -0.8 [get_ports {b_rgmii_txdv}] -add_delay
# TD UG condensed form
set_output_delay -clock lcd_clk 3.0 [get_ports led_output]
```

Source-synchronous templates from SWUG200 § 5.2.11–5.2.16 (command lines only; the identifying
section titles survived):

```tcl
# system synchronous, rising-edge sampling
set_output_delay -clock dest_clock -max max_delay [get_ports output_data]
set_output_delay -clock dest_clock -min min_delay [get_ports output_data]
# system synchronous, falling-edge sampling
set_output_delay -clock dest_clock -max max_delay -clock_fall [get_ports output_data]
set_output_delay -clock dest_clock -min min_delay -clock_fall [get_ports output_data]
# system synchronous, dual edge
set_output_delay -clock dest_clock -max r_max_delay [get_ports output_data]
set_output_delay -clock dest_clock -min r_min_delay [get_ports output_data]
set_output_delay -clock dest_clock -max f_max_delay -clock_fall [get_ports output_data]
set_output_delay -clock dest_clock -min f_min_delay -clock_fall [get_ports output_data]
# source synchronous, forwarded clock (fw_clock)
set_output_delay -clock fw_clock -max max_delay [get_ports output_data]
set_output_delay -clock fw_clock -min min_delay [get_ports output_data]
set_output_delay -clock fw_clock -max max_delay -clock_fall [get_ports output_data]
set_output_delay -clock fw_clock -min min_delay -clock_fall [get_ports output_data]
set_output_delay -clock fw_clock -max r_max_delay [get_ports output_data]
set_output_delay -clock fw_clock -min r_min_delay [get_ports output_data]
set_output_delay -clock fw_clock -max f_max_delay -clock_fall [get_ports output_data]
set_output_delay -clock fw_clock -min f_min_delay -clock_fall [get_ports output_data]
```

### 5.3 `remove_input_delay` / `remove_output_delay`

```
remove_input_delay  [-max | -min] [-clock <clock>] <delay value> [<Target>]
remove_output_delay [-max | -min] [-clock <clock>] <delay value> [<Target>]
```

Both exist in the live command list. Documented only in TD UG § 9.2 with examples:

```tcl
remove_input_delay  -clock sys_clk  2     [get_ports {data[0]}]
remove_output_delay -clock sys_clk -0.55 [all_outputs]
```

### 5.4 I/O constraint selection rule

From SWUG200 § 3.10.3, verbatim intent:

> SDC 中可以用于I/O 约束的命令包括 `set_input_delay` / `set_output_delay` 和
> `set_max_delay` / `set_min_delay`。其中，只有那些从FPGA 管脚进入和/或输出都不经过任何
> 时序元件的纯组合逻辑路径可以用 `set_max_delay` / `set_min_delay` 来约束，其余I/O 时序
> 路径都建议由 `set_input_delay` / `set_output_delay` 来约束。如果对FPGA 的I/O 不加任何
> 约束，不仅综合和实现时不会考虑I/O 时序，而且在时序分析时不会有这些未约束的路径。

i.e. `set_max_delay`/`set_min_delay` for **pure combinational** pin-to-pin paths only;
everything else uses input/output delay. **Unconstrained I/O is not analysed at all** — it is
missing from the timing report, not "passing".

---

## 6. SDC — timing exception commands

All four exception commands share the same path-specification grammar:

| Option | Accepted object types |
|---|---|
| `-from [<source node>]` | `clocks`, `cells`, `regs`, `ports`, `pins` |
| `-rise_from [<source>]` | `clocks` or start points (rising edge) |
| `-fall_from [<source>]` | `clocks` or start points (falling edge) |
| `-through [<node>]` | `pins` or `nets` (for MCP, a list; paths must pass each in order) |
| `-to [<target node>]` | `clocks`, `regs`, `ports`, `pins` |
| `-rise_to [<target>]` | `clocks` or end points (rising edge) |
| `-fall_to [<target>]` | `clocks` or end points (falling edge) |

Rules that apply to all of them:

* With `-from`/`-to`, the object **must** be a genuine path start/end point.
  With a pin name, `-from` should be a **clock pin** and `-to` should be a register's
  **non-clock data input**. When `-from`/`-to` names a clock pin, the constraint covers every
  path driven by that clock. When `-from`/`-to` names a cell, it covers every register inside
  that cell. `-through` covers every path through that node.
* **Prefer clocks over nodes** for `-from`/`-to`: it is more efficient and less brittle.

### 6.1 `set_max_delay`

```
set_max_delay (-from|-rise_from|-fall_from [<src>]) [-through [<node>]] \
              (-to|-rise_to|-fall_to [<tgt>]) <Delay value> [-datapath_only]
```

Overrides the default **setup (recovery)** requirement of a path. `<Delay value>` in ns, 3
decimals. `-datapath_only` is supported **only** by `set_max_delay`: it removes clock
jitter/skew/pessimism and considers only the launching flop's Clock-to-Q, the interconnect
between flops, and the capturing flop's setup time. When combined with `-from`, hold analysis
for those paths is automatically false-pathed by the tool.

```tcl
set_max_delay -from [get_ports {x y}] -to [get_ports {sum}] 7
set_max_delay -from [get_clocks {clk0}] -to [get_clocks {clk1}] 4
set_max_delay -from [get_regs REG1] -to [get_regs REG2 ] -datapath_only 1
set_max_delay 40 -from [all_inputs] -to [all_outputs]
set_max_delay -from [get_ports {sw}] -to [get_ports {sm_bit}] \
              -through [get_nets {lcd/delay_cnt[2]}] 1        ;# TD UG form
```

### 6.2 `set_min_delay`

```
set_min_delay (-from|-rise_from|-fall_from [<src>]) [-through [<node>]] \
              (-to|-rise_to|-fall_to [<tgt>]) <Delay value>
```

Overrides the default **hold (removal)** requirement. No `-datapath_only`.

```tcl
set_min_delay -from [get_ports {x y}] -to [get_ports {sum}] 3
set_min_delay -from [get_clocks {clk0}] -to [get_clocks {clk1}] 2.5
set_min_delay 10 -from [all_inputs] -to [all_outputs]
```

### 6.3 `set_multicycle_path`

```
set_multicycle_path [-setup | -hold] [-start | -end] \
    (-from|-rise_from|-fall_from [<src>]) [-through [<node>]] \
    (-to|-rise_to|-fall_to [<tgt>]) <multiplier value>
```

| Option | Meaning |
|---|---|
| `-setup` | The multiplier applies to the setup (max-delay) calculation. **Changing the setup multiplier also changes the default hold check.** |
| `-hold` | The multiplier applies to the hold (min-delay) calculation. |
| `-start` | The multiplier counts **launch** clock cycles. Default for hold. |
| `-end` | The multiplier counts **capture** clock cycles. Default for setup. |
| `<multiplier value>` | Integer number of clock cycles. |

**The N/N-1 rule.** A bare `-setup N` multicycle moves the setup capture edge to the N-th edge,
and the hold check edge then automatically follows to edge N-1 — i.e. hold silently becomes
N-1 cycles, which is almost never what is wanted. Always pair it:

```tcl
# typical, verbatim from SWUG200 3.12.4
set_multicycle_path -setup -from [get_regs { rx_a_1d.q }] -to [get_regs { rx_a_2d.d }] 3
set_multicycle_path -hold  -end -from [get_regs {rx_a_1d.q}] -to [get_regs {rx_a_2d.d}] 2

# TD UG form, with -through
set_multicycle_path -setup -end -from [get_clocks {clk_vga_25m}] \
                    -through [get_nets {uart/uart_tx/num[3]}] 2
```

Cross-domain recipes from SWUG200 § 5.3.4 (command lines verbatim; the surrounding prose
diagrams are unrecoverable):

```tcl
# slow -> fast, N cycles
set_multicycle_path N   -setup      -from [get_clocks Slow_Clock] -to [get_clocks Fast_Clock]
set_multicycle_path N-1 -hold -end  -from [get_clocks Slow_Clock] -to [get_clocks Fast_Clock]
# fast -> slow
set_multicycle_path N   -setup -start -from [get_clocks Fast_Clock] -to [get_clocks Slow_Clock]
set_multicycle_path N-1 -hold         -from [get_clocks Fast_Clock] -to [get_clocks Slow_Clock]
# common 2-cycle capture case
set_multicycle_path 2 -setup -from [get_clocks Clock_A] -to [get_clocks Clock_B]
set_multicycle_path 1 -hold -end -from [get_clocks Slow_Clock] -to [get_clocks Fast_Clock]
```

### 6.4 `set_false_path`

```
set_false_path [-setup | -hold] \
    (-from|-rise_from|-fall_from [<src>]) [-through [<node>]] \
    (-to|-rise_to|-fall_to [<tgt>])
```

Removes the path(s) from timing analysis entirely.

* Without `-setup`/`-hold`, the false path applies to **both** setup/recovery and hold/removal.
* `-setup` restricts it to setup/recovery; `-hold` restricts it to hold/removal.
* Prefer clock objects: `-from`/`-to` with clocks covers every register/port driven by the
  source clock to everything captured by the destination clock, in one line.
* `set_false_path` blocks **one direction only**; the reverse direction still needs its own
  constraint. Use `set_clock_groups` when both directions should be blocked.

```tcl
set_false_path -from [get_clocks clk_25m] -to [get_clocks clk_25m_add]
set_false_path -from [get_regs {rx_b_1d}] -to [get_regs {tx_b2c}]
set_false_path -rise_from [get_clocks {rgmii_rxc}] -fall_to [get_clocks {Sdr_clk}]
set_false_path -rise_from [get_clocks {rgmii_rxc}] -rise_to [get_clocks {Sdr_clk}]
set_false_path -from [get_port reset] -to [all_registers]            ;# TD UG spelling: get_port
set_false_path -from [get_clocks async_clk1] -to [get_clocks async_clk2]
set_false_path -from [get_clocks async_clk2] -to [get_clocks async_clk1]
set_false_path -from [get_clocks clk] -to [get_clocks sys_clk]
set_false_path -from [get_clocks {clk_vga_25m}] -to [get_ports {sm_bit}] \
               -through [get_nets {dpram_top0/lfsr_done}]
```

Note: TD UG writes `get_port` (singular) in one example — that is a **typo**; the command is
`get_ports`.

Typical legitimate false paths called out by SWUG200 § 2.10: clock-domain crossings protected
by a two-flop synchroniser; registers written once at power-up; reset and test logic; the
write-clock↔read-clock paths of an asynchronous DRAM.

### 6.5 `set_clock_groups`

```
set_clock_groups [-name <group_name>] (-exclusive | -asynchronous) \
                 -group [<clock name>] [-group [<clock name>] ...]
```

| Option | Meaning |
|---|---|
| `-name <group_name>` | Group name; auto-assigned if omitted. |
| `-exclusive` | The clocks are mutually exclusive — they are never active at the same time (e.g. clock MUX branches). |
| `-asynchronous` | The clocks are asynchronous — completely different clock sources. |
| `-group [<clock name>]` | One clock set. Repeat the option for each additional set. |

Semantics:

* Cuts timing analysis **between** groups; it does **not** disable analysis within a group.
* Two directions are cut at once (unlike `set_false_path`, which is one-directional).
* **One `-group` only:** the listed clock set becomes mutually exclusive with *all other*
  clocks. **Multiple `-group` options:** those sets are mutually exclusive with each other.
* At least two effective groups are required for the constraint to do anything.
* `-exclusive` and `-asynchronous` are implemented identically (both expand to a set of
  `set_false_path` constraints), but choosing the semantically correct one documents intent.

```tcl
create_clock -name CLK2 -period 10.0 [get_ports CLK2]
create_clock -name CLK3 -period 5.0  [get_ports CLK3]
set_clock_groups -exclusive -group CLK2 -group CLK3

# one group => these clocks vs. everything else
set_clock_groups -group [get_clocks {clk_1}]
# two groups
set_clock_groups -group [get_clocks {clk_1}] -group [get_clocks {clk_2}]
# one group of two clocks
set_clock_groups -group [get_clocks {clk_1 clk_2}]
# three clocks in one group
set_clock_groups -group [get_clocks {clk_1 clk_2 clk_3}]
# two groups of two
set_clock_groups -group [get_clocks {clk_1 clk_3}] -group [get_clocks {clk_2 clk_4}]
# clock-MUX case: the two branches are exclusive
set_clock_groups -exclusive -group [get_clocks {clk_a_mux}] -group [get_clocks {clk_b_mux}]
# TD UG form
set_clock_groups -exclusive -group [get_clocks {clk_vga_25m}] -group [get_clocks {sys_clk}]
```

**Documentation defect:** TD UG § 9.2 writes `set_clock_group` (singular). The real command is
`set_clock_groups`; the singular form is **not** in the live command list.

### 6.6 `set_cross_domain_timing`

```
set_cross_domain_timing (all | self | domain)
```

A global (design-wide) switch that ignores clock-to-clock relationships in bulk:

| Value | Effect |
|---|---|
| `all` | **Default.** Analyse timing between any two clocks. |
| `self` | Analyse only paths within the *same clock*; ignore all cross-clock paths. |
| `domain` | Analyse only paths within the *same clock domain*; ignore cross-domain paths. A domain = a master clock plus every clock generated from it. |

**Use with care — this affects every clock in the design.**

```tcl
set_cross_domain_timing domain
```

**Documentation defect:** TD UG § 9.2 writes `set_clock_domain_timing self|domain|all`. The
real command is `set_cross_domain_timing`; `set_clock_domain_timing` is **not** in the live
command list.

### 6.7 Exception priority

From the Timing Exception Report model (SWUG201 § 3.1.3.7), each exception constraint's paths
are classified as **Active** (constraint in force), **Shadowed** (masked by a
higher-priority SDC command), or **Ignored** (false-pathed away). When two exceptions overlap,
the one that appears later / is more specific wins and the other becomes Shadowed. Use
`report_timing_exception` and `report_timing_ignored` to see the split — see
`timing-analysis.md`.

---

## 7. Asynchronous FIFO constraint template

SWUG200 § 5.3.2 (the prose is garbled; the command lines are verbatim). Combine
`set_max_delay -datapath_only` on the pointer/gray-code crossings with ordinary max/min delays
between the two clock domains:

```tcl
create_clock -name fifo_wrclk -period 6.4 -waveform {0 3.2} [get_ports {fifo_wrclk}]
create_clock -name fifo_rdclk -period 6.2 -waveform {0 3.1} [get_ports {fifo_rdclk}]

set_max_delay -from [get_clocks {fifo_wrclk}] -to [get_clocks {fifo_rdclk}] <value>
set_max_delay -from [get_clocks {fifo_rdclk}] -to [get_clocks {fifo_wrclk}] <value>

set_max_delay -from [get_regs {*wr_ptr_b2g[*]}] -to [get_regs {*wr_b2g_ff0[*]}] \
              -datapath_only <value>
set_max_delay -from [get_regs {*rd_ptr_b2g[*]}] -to [get_regs {*rd_b2g_ff0[*]}] \
              -datapath_only <value>
```

(Source text elides the numeric `<value>`; supply your own, normally the destination clock
period.)

---

## 8. Complete inventory: SDC commands TD 6.2.1 actually supports

Every command below was verified to exist in the live 740-command list.

| Group | Commands |
|---|---|
| Object queries | `all_clocks`, `all_inputs`, `all_outputs`, `all_registers`, `get_ports`, `get_cells`, `get_nets`, `get_regs`, `get_pins`, `get_clocks` |
| Clock definition | `create_clock`, `create_generated_clock`, `derive_clocks`, `derive_pll_clocks`, `rename_clock` |
| Clock attributes | `set_clock_latency`, `set_clock_uncertainty`, `set_clock_sense`, `set_clock_route`, `set_clock_route_enforce` |
| I/O delay | `set_input_delay`, `set_output_delay`, `remove_input_delay`, `remove_output_delay` |
| Exceptions | `set_max_delay`, `set_min_delay`, `set_multicycle_path`, `set_false_path`, `set_clock_groups`, `set_cross_domain_timing` |
| File I/O | `read_sdc`, `clear_sdc`, `clear_user_sdc`, `export_sdc`, `export_sdc_target`, `print_sdc_clock_tree`, `print_sdc_ui`, `read_clock_constr` |
| Misc / advanced | `remove_clock`, `clock`, `clockplan`, `analyze_clock`, `set_clock_net`, `set_skew_clock_buffers`, `report_clock_buffers`, `set_clock_route_enforce` |
| Derating / corners | `set_timing_derate`, `read_timing_derate_file`, `report_timing_derate`, `reset_analysis_corner`, `set_analysis_corner`, `report_analysis_corner`, `import_speed_derate` |
| Other packaging | `read_cwc_data`, `write_cwc_reg`, `export_cwc_file` (`export_congo_file`), `tune_congo` |

### 8.1 Commands documented in the PDFs but NOT present in TD 6.2.1

Do not use these — the documentation is stale:

| Documented as | Where | Reality |
|---|---|---|
| `remove_clock_latency` | TD UG § 9.2 e) | absent from the live command list |
| `remove_clock_uncertainty` | TD UG § 9.2 g) | absent from the live command list |
| `set_clock_group` (singular) | TD UG § 9.2 f) | real name is `set_clock_groups` |
| `set_clock_domain_timing` | TD UG § 9.2 h) | real name is `set_cross_domain_timing` |
| `get_port` (singular) | TD UG § 9.2 example | real name is `get_ports` |
| `create_generation_clock` | SWUG200 § 2.3 | real name is `create_generated_clock` |
| `multiply_by` written as bare `multiply_by` | SWUG200 § 3.3.4 example 2 | option is `-multiply_by` |
| `drive_clocks` | SWUG200 § 3.4.2 | real name is `derive_clocks` |
| `-divede_by` | SWUG200 § 3.3.3 | real spelling is `-divide_by` |

### 8.2 Related tooling (see `timing-analysis.md` for reports)

| Command | Purpose |
|---|---|
| `read_sdf <file>` / `write_sdf [-check_corner <SLOW/FAST/SLOW_FAST>] [-file <f>]` | SDF in/out for gate-level simulation |
| `check_sdf`, `build_sdf_tg`, `build_sdf_tg2`, `cut_sdf_connect`, `check_pvt_sdf` | SDF checking/building |
| `update_timing [-mode basic\|manhattan\|final] [-check_corner fast\|slow]` | refresh the timing DB after `import_db` or a netlist change |
| `check_timing [-file <f>] [-verbose]` | SDC health check |
| `report_timing_summary`, `report_timing_path`, `report_qor`, `report_clock_summary`, `report_clock_intersection`, `report_timing_exception`, `report_timing_ignored` | timing reports |

---

## 9. Gaps and uncertainties

* **SWUG200 § 5 (typical scenarios, pp. 49–97) is diagram-heavy and extracted badly.** The
  ASCII timing sketches (source-synchronous edge-aligned vs centre-aligned, system-synchronous
  SDR/DDR, clock-MUX) lost their pictures; only command lines and section titles survived. The
  exact numeric `max_delay`/`min_delay` values in those sections are placeholders (`max_delay`,
  `min_delay`, `rise_max_delay`, …) in the source text itself, so they were placeholders in the
  PDF too — not lost in extraction.
* **The BANK enumeration `BANK1..BANK8` in TD UG Table 9-1 is generic.** Real bank identifiers
  are device/package specific and look like `0`, `11`, `12`, `13`, `32`, `33`. Get them from
  `query_current_package -fio`. Marked `[RECONSTRUCTED]` above as an exhaustive list.
* **VCM/VOD range table (Table 9-2)** extracted with columns interleaved; rows were reassembled
  and are marked `[RECONSTRUCTED]`. The `AL3` device named in that table does not appear in
  `list_devices` — likely a legacy row retained from an older device family.
* **`set_pin_assignment` attribute count is inconsistent between documents:** TD UG § 9.1 says
  "10 attributes" and omits `INDEL`/`OUTDEL`, while its own worked example uses `OUTDEL=1` and
  the IO-editor table documents `InDelay`/`OutDelay`. The table in § 2.2 above lists the union.
* **`PREEMPHASIS` accepted values were not recoverable** — the PDF only says it applies to LVDS
  outputs and that emulated LVDS (`*_E`) has no pre-emphasis setting.
* **`create_bound` / `add_cells_to_bound` / `remove_cells_from_bound` syntax** was recovered
  from TD UG § 9.3 DRC error text (`USR-8077`/`USR-8081`/`USR-8083`), not from a command
  reference chapter. Marked `[RECONSTRUCTED]`.
* **Bound/cell constraint interactions** with `keep_hierarchy` (`USR-8088`) mean region
  constraints silently fail when hierarchy is flattened; check `keep_hierarchy=auto|manual`.
* The `-o` option on object queries is documented as mandatory from TD 5.6 onward, but the tool
  accepts the queries without it. Always pass `-o` to get resolved names.
