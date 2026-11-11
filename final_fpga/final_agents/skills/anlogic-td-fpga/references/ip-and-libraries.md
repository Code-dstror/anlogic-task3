# Anlogic TD 6.2.1 — IP & Device Primitive Reference

Compact index of the IP available in TD 6.2.1, how HDL designers instantiate device
primitives, and the simulation-library / Simulation-Libraries-Compiler mapping.

Primary sources:

| Source | Role |
|---|---|
| `IPUG*.txt` (15 guides) | customization-wizard IP (SERDES, PCIe, High Speed IO, DSP MACRO, CGMAC, HXT, MIS, DDR) |
| `UG910/UG710/UG1310/UG1110/UG1211_*_Libraries_Guide_for_HDL_Designs.txt` | primitive names, ports and parameters per family |
| `SWUG107_Design_Simulation_User_Guide.txt` | Simulation Libraries Compiler + library mapping |
| `<root>\template\verilog\Device-Primitive\<FAMILY>\<Category>\*.v` | installed annotated primitive templates (verified on disk) |
| `<root>\sim_release\<family>\*.v` | installed simulation models (verified on disk) |

> **Extraction warnings.** The IPUG tables that map IP ports to primitive signals (IPUG028 /
> IPUG160 表4-1, IPUG010/IPUG014 表2-10/2-11) extracted with interleaved rows; named
> reconstructions are marked `[RECONSTRUCTED]`. Port and parameter names taken from the
> **installed templates** (`template\verilog\Device-Primitive\...`) and **simulation models**
> (`sim_release\...`) are ground truth and are not reconstructions.

---

## Part A — IP index

### A.1 Customization-wizard IPs

| IP | Device families / parts | What to instantiate | One-line description | Doc |
|---|---|---|---|---|
| **SERDES** (PH1A) | `SALPHOENIX®1A`: `PH1A400SFG900`, `PH1A400SFG676`, `PH1A90SBG484`, `PH1A90SEG324`, `PH1A90SEG325`, `PH1A180SFG676` | wizard emits wrapper `.v` + `_src.v`; GUI `Component name` becomes the module name; the hard primitive inside is `SERDES Dual` (ports mapped from `SERDES CORE`) | Configures one PH1A SERDES Dual hard core to a user-defined or industry-standard protocol and emits wrapper RTL + `.adc`/`.sdc` | IPUG010 v1.7 §1 p.1 |
| **SERDES** (PH1A100) | `SALPHOENIX®1A100` with SERDES: `PH1A100SFG676`, `PH1A100SFG676X` | same mechanism as IPUG010 | PH1A100 flavour of the SERDES-Dual customization IP | IPUG014 v1.2 §1 p.1 |
| **PCI Express** (PH1A) | `SALPHOENIX®1A`: `PH1A400SFG900`, `PH1A400SFG676`, `PH1A90SBG484`, `PH1A90SEG324`, `PH1A90SEG325`, `PH1A180SFG676`. Gen1/Gen2/Gen3, ×1/×2/×4 | GUI name → `<name>.v`; sub-files `*_ph1_pcie_basic_top.v`, `*_ph1_pcie_core_pll.v`, `*_ph1_pcie_cfg_rom.v`, `*_ph1_pcie_clock_ctrl.v`, `*_ph1_dbi_init_mux.v` | GUI wrapper around the PH1A PCIe hard core (Endpoint / Legacy EP / Root Port), optional pipeline + core PLL | IPUG011 v1.4 §1 p.1, 生成的文件 p.21 |
| **PCI Express** (PH1P) | `SALPHOENIX®1P` parts with a PCIe hard core: `PH1P100`/`SBG676`, `PH1P100`/`SBG677`; controller at `X69Y120Z0` | top module named `PCIe Inst` — the module name equals the configured IP name; emits `<IP>.v` + a random-suffix PCIe subsystem `.v` | Soft wrapper + init logic around `PH1P_PHY_PCIE_V1`, optionally carrying `PH1P_PHY_HXT_V1` | IPUG028 v1.1 §1 p.1, §2 p.3 |
| **PCI Express** (PH2A) | `SALPHOENIX®2A` parts with a PCIe hard core: `PH2A106`/`FLG676`, `PH2A106`/`FLG900`; controllers at `X147Y0Z0`, `X147Y180Z0` | `<IP>.v` (module name = IP name) | Soft wrapper + init around `PH2_PHY_PCIE_V1`, optional `PH2_PHY_HXT_V1` + `hxt_csr_load`. vs PH1P: x1/x2/x4/**x8**, 2.5/5.0/**8.0/16 Gb/s**, PIPE **5.2**, ≤4 PF & 256 VF, **512-bit** TX/RX path | IPUG160 v1.0 §1 p.1, §2 p.3 |
| **High Speed IO** (PH1A) | `PH1A60`, `PH1A90`, `PH1A180`, `PH1A400` **and** `PH1A100` | no generated-file table in the guide; built directly from 16 primitives | Configurable high-speed input/output/bidirectional IO structure (clock buffering + IOL + delay), up to 16 pins | IPUG013 v1.0 §1 p.2 |
| **High Speed IO** (PH2A) | `SALPHOENIX®2A`, HPIO type. Byte Mode 400–1600 Mbps; Bit Mode 200–800 Mbps | `<ip_name>.v` top; `RTL/ph2_hpio_top.v`, `ph2_hpio_byte_wrapper.v`, `ph2_hpio_byte.v`, `ph2_hpio_pair.v`, `ph2_hpio_bit_wrapper.v`; `adc/<ip_name>.adc` | HPIO Byte-mode / Bit-mode HDL templates (IOL, IOB, DPLL, Byteclk RX, IODIV) | IPUG023 v1.2 §1 p.1, 生成文件 p.14 |
| **High Speed IO** (PH1P) | `SALPHOENIX®1P`. PH1P35 supports HRIO **and** HDIO; PH1P100 supports HRIO only | `*.v` (wrapper + RTL); `Design.xml`, `DesignConfiguration.xml`, `Comp_inst.xml` | HRIO/HDIO IO Buffer + IO Logic primitive templates (2/4/7/8/10-bit serdes, dynamic delay cascade) | IPUG026 v1.0 §1 p.1, 生成的文件 p.11 |
| **DSP MACRO** (PH2A) | `SALPHOENIX®2A` | GUI `Component Name` (default `dsp_macro_0`); `<USERNAME>.ipc`, `<USERNAME>.v` | Ease-of-use wrapper over the DSP primitive: up to 8 switchable arithmetic expressions, ≤48-bit adder by port concatenation, cascadable | IPUG017 v1.0 §1 p.2, §4.3 p.15 |
| **CGMAC** (PH2A) | `SALPHOENIX®2A` | IP Catalog entry `CGMAC`; GUI `Component Name` = `<USERNAME>`; top `<USERNAME>.v`; param `CGMAC_CFG_FILE` (= `cgmac_core_ip_syn.txt`) | 100G MAC&PCS hard-core wrapper (100G/50G/40G/25G/10G MAC; PCS FlexO/FlexE/OTU/GFC/CPRI), optionally a CGMAC+HXT subsystem | IPUG024 v2.1 §1.3.2 p.7, 输出文件 p.57 |
| **HXT** (PH1P) | `PH1P100SBG676`, `PH1P100SBG677` | top `<USERNAME>.v`; files `hxt_x.v` (calls `PH1P_PHY_HXT_V1`), `define.v`, `hxt_parameter.v`, `.adc`/`.sdc` | `PH1P_PHY_HXT_V1` transceiver wrapper, ≤2 Quad / 8 Lane, ≤4 protocols | IPUG033 v1.2 §1 p.1, §2.3 p.18 |
| **HXT** (PH2A) | `PH2A106FLG676`, `PH2A106FLG900` | `<USERNAME>.v`; internals `USERNAME_hxt_quad` (≤×4), `USERNAME_csr_load`, `USERNAME_init`, `USERNAME_clk_aligner_ctrl`; primitive `PH2_PHY_HXT_V1` | `PH2_PHY_HXT_V1` wrapper, ≤4 Quad / 16 Lane, ≤8 preset line rates + dynamic switching | IPUG154 v1.1 §1 p.3, §2.3 p.18 |
| **MIS** / Memory Interface Solutions (PH1P) | `PH1P100SBG676`, `PH1P100SBG677`, `PH1P35MBG484`, `PH1P35MDG324` | Catalog `Tools → IP Catalog → Primitive IP → Memory and Storage → MIS – DDR2/DDR3/DDR4`; `Component Name` default `Comp_inst`; top `<IP_USERNAME>.v`; RTL `ph1p_ddrphy_wrapper_*.v` | DDR2/DDR3/DDR3L/DDR4 PHY-only or MC+PHY memory interface, DQ 8–72-bit | IPUG034 v1.2 §1 p.1, §1.2 p.2, 生成的文件 p.27 |
| **MIS** (PH2A) — **DDR4 only** | `PH2A` | Catalog `Tools → IP Catalog → Soft IP → Memory → MIS–DDR4`; `Component Name` default `Comp_inst`; `<IP_USERNAME>.v`; `ph2_ddrphy_wrapper_*.v`; `sim/fileset/fileset_mis.f` | DDR4-only MIS: PHY-only / Ping-Pong PHY / PPC cascade / Memory Controller, 8–72-bit DQ, DFI 5.0 | IPUG037 v2.0 §1 p.1, 生成的文件 p.13 |
| **DDR** (PH1A) | `PH1A400`, `PH1A180`, `PH1A90` | Catalog `Tool → IP Catalog → DDR3/4 SDRAM`; outputs `*.ipc`, `*.v`, `*.adc`, `*.mif`, `*.txt`; demo core module `PH1_LOGIC_DDR_SDRAM` | DDR3 (JESD79-3F) / DDR4 (JESD79-4) interface: Standard PHY, Ping-Pong PHY, or MC+Standard PHY (PPC + MCU + DDR PHY), ≤72-bit, multi-controller on PH1A400 | IPUG035 v1.2 §1 p.4, demo p.46 |

**Hard-IP primitives that wizard-generated wrappers instantiate** (names verbatim from the
installed `sim_release` models unless a guide is cited):

| Primitive | Family | Source |
|---|---|---|
| `SERDES Dual` / `SERDES CORE` | PH1A / PH1A100 | IPUG010 p.20-24; IPUG014 p.20-22 |
| `PH1_PHY_SERDES_DUAL` (+ `_V2`, `_V3`) | PH1A | `sim_release\ph1\ph1_phy_serdes_dual*.v` |
| `PH1P_PHY_PCIE_V1` | PH1P | IPUG028 §2 p.3 |
| `PH2_PHY_PCIE_V1` | PH2A | IPUG160 §2 p.3 |
| `PH1P_PHY_HXT_V1` | PH1P | IPUG028 §2 p.3; IPUG033 p.7 |
| `PH2_PHY_HXT_V1` | PH2A | IPUG160 §2 p.3; IPUG154 p.5 |
| `hxt_csr_load` | PH2A | IPUG160 §2 p.3-4 |
| `PH2_PHY_MATRIX_20TO20` | PH2A | IPUG154 §4.5.1 p.55; IPUG037 p.15 |
| `PH2_PHY_CGMAC_V1` | PH2A | `sim_release\ph2\ph2_phy_cgmac_v1.sv` |

### A.2 Hard-IP / specialised primitives with no dedicated IPUG

The IPUG set documents **no** MIPI, RISC-V/Cortex, temperature-sensor or oscillator *IP* — but
the corresponding *primitives* exist and are instantiable:

| Primitive(s) | Families | Source |
|---|---|---|
| `EF2_PHY_ADC`, `EG_PHY_ADC`, `PH1P_PHY_ADC`, `DR1_PHY_ADC` | EF2, EG4, PH1P, DR1 | Device-Primitive `Advanced`; `PH1P_PHY_ADC` documented UG1310 §55 p.154 (**PH1P50 only**) |
| `EF2_PHY_MCU`, `SF1_LOGIC_MCU`, `SF1_LOGIC_MCU_JTAG` | EF2, SF1 | Device-Primitive `Advanced` / `I,O` |
| `EF2_PHY_PSRAM_8`, `SF1_PHY_PSRAM`, `SF1_PHY_PSRAM_8`, `SF1_PHY_SHARESRAM` | EF2, SF1 | Device-Primitive `RAM,ROM` |
| `EF2_LOGIC_MIPIIO`, `EF2_PHY_MIPIIO`, `PH1P_LOGIC_DPHY_MIPI_TX/RX`, `PH1P_LOGIC_DPHY_LVDS_TX/RX`, `PH1P_LOGIC_DPHY_LVCMOS` | EF2, PH1P | Device-Primitive `I,O` (PH1P D-PHY: **PH1P35, PH1P50 only**) |
| `SF1_LOGIC_DSC`, `SF1_LOGIC_DSI` | SF1 | Device-Primitive `Hard-IP` |
| `SF2_PHY_VIDEO_PROCESSOR` | SF2 | Device-Primitive `Hard-IP` |
| `PH1_LOGIC_PVT`, `PH1_LOGIC_TS`, `PH1P_LOGIC_TVS`, `PH2_LOGIC_TVS`, `DR1_LOGIC_TS` | PH1A, PH1P, PH2A, DR1 | Device-Primitive `Advanced`; models in `sim_release\common\apm\logic_tvs.v` |
| `EG_PHY_DDR_8M_16`, `EG_PHY_SDRAM_2M_32` (SIP memories) | EG4 | Device-Primitive `RAM,ROM` |
| `EF2_PHY_INTFLASH`, `EF3_PHY_INTFLASH`, `EF4_PHY_INTFLASH`, `SF1_PHY_INTFLASH`, `SF2_PHY_INTFLASH` | EF2/EF3/EF4/SF1/SF2 | Device-Primitive `Config` |
| `PH1_PHY_TRNG` (true RNG), `PH1_PHY_TIE` | PH1A | `sim_release\ph1\` |
| `DR1_PHY_PROCESSOR_SYSTEM` (MCU subsystem) | DR1 | `sim_release\dr1\` |
| `PH1P_PHY_CLOCK_ALIGNER` / `PH1_PHY_CLK_ALIGNER` | PH1P / PH1A | `sim_release\ph1p\`, `sim_release\ph1\` |

---

## Part B — Device primitive instantiation for HDL designers

### B.1 Primitive naming convention per family

The prefix derives from the **marketing series**, not from the directory or part-family string.
The pattern is `<PREFIX>_{LOGIC,PHY,PHY_}<FUNCTION>`; there is no stricter rule.

| Family | Directory / device family | Primitive prefix(es) | Example primitive names actually listed |
|---|---|---|---|
| PH1A (+ PH1A100) | `PH1A` | `PH1_LOGIC_*`, `PH1_PHY_*` | `PH1_LOGIC_BUFG`, `PH1_LOGIC_SLICE`, `PH1_LOGIC_ERAM`, `PH1_PHY_PLL`, `PH1_PHY_GCLK_V2`, `PH1_PHY_LCLK_V2`, `PH1_LOGIC_HP_ISERDES` |
| PH1P | `PH1P` | `PH1P_LOGIC_*`, `PH1P_PHY_*` | `PH1P_LOGIC_BUFG`, `PH1P_LOGIC_ERAM`, `PH1P_PHY_PLL`, `PH1P_PHY_PLL_V2`, `PH1P_PHY_GCLK`, `PH1P_PHY_CLOCK_ALIGNER`, `PH1P_PHY_ADC` |
| PH2A | `PH2A` | `PH2_LOGIC_*`, `PH2_PHY_*` | `PH2_LOGIC_BUFG`, `PH2_LOGIC_BUFG_CE_DIV`, `PH2_PHY_SBUF`, `PH2_PHY_CBUF`, `PH2_PHY_DBUF`, `PH2_PHY_DPLL`, `PH2_PHY_ERAM`, `PH2_PHY_DSPMULT` |
| DR1 (SALDRAGON®1) | `DR1` | `DR1_LOGIC_*`, `DR1_PHY_*` | `DR1_LOGIC_BUFG`, `DR1_LOGIC_SLICE`, `DR1_LOGIC_ERAM`, `DR1_LOGIC_FIFO`, `DR1_PHY_PLL`, `DR1_PHY_GCLK`, `DR1_PHY_ADC` |
| EF2 (SALELF®2) | `EF2` | `EF2_LOGIC_*`, `EF2_PHY_*` | `EF2_LOGIC_BUFG`, `EF2_PHY_PLL`, `EF2_PHY_BRAM128K`, `EF2_PHY_MULT18`, `EF2_PHY_LSLICE`, `EF2_PHY_ADC` |
| EF3 (SALELF®3) | `EF3` | `EF3_LOGIC_*`, `EF3_PHY_*` | `EF3_LOGIC_BUFG`, `EF3_PHY_PLL`, `EF3_PHY_OSC`, `EF3_PHY_CONFIG_V2`, `EF3_PHY_LSLICE` |
| EF4 | `EF4` | `EF4_LOGIC_*`, `EF4_PHY_*` | `EF4_LOGIC_BUFG`, `EF4_PHY_PLL`, `EF4_PHY_MULT18`, `EF4_PHY_LSLICE`, `EF4_PHY_INTFLASH` |
| EG4 (SALEAGLE®) | `EG4` | **`EG_LOGIC_*`, `EG_PHY_*`** — note `EG_`, **never `EG4_`** | `EG_LOGIC_BUFG`, `EG_PHY_PLL`, `EG_PHY_BRAM32K`, `EG_PHY_MULT18`, `EG_PHY_LSLICE`, `EG_PHY_ADC` |
| SF1 (SALSWIFT®) | `SF1` | `SF1_LOGIC_*`, `SF1_PHY_*` | `SF1_LOGIC_BUFG`, `SF1_PHY_PLL`, `SF1_PHY_OSC`, `SF1_LOGIC_BRAM`, `SF1_LOGIC_DSC`, `SF1_LOGIC_MCU` |
| SF2 | `SF2` | `SF2_LOGIC_*`, `SF2_PHY_*` | `SF2_LOGIC_BUFG`, `SF2_PHY_PLL`, `SF2_PHY_GCLK`, `SF2_LOGIC_OSCDIV128`, `SF2_PHY_VIDEO_PROCESSOR` |
| all (shared) | `common` | **`AL_*`** | `AL_MAP_LUT1..LUT6`, `AL_MAP_LUT6P`, `AL_MAP_LUT6X`, `AL_MAP_LLMUX`, `AL_MAP_F7MUX`, `AL_MAP_F8MUX`, `AL_MAP_CARRY4`, `AL_MAP_ADDER`, `AL_MAP_ALU2B`, `AL_MAP_SEQ`, `AL_MAP_SEQ_GSR`, `AL_MAP_BLE_MULT18X18`, `AL_MAP_BLE_MULT9X9`, `AL_PHY_MULT18`, `AL_LOGIC_DEBUGHUB`, `AL_DFF_0/1/W/X`, `AL_LATCH_0/1/W/X`, `AL_MUX`, `AL_FADD`, plus `reg_ar_as_w1` and **`glbl`** |

**Three prefix traps:**

1. **File names are lowercase and can mislead about module names.** `common\al_map_lut.v`
   declares `AL_MAP_LUT1`; `common\al_phy_glbl.v` declares **`glbl`** (there is no `AL_PHY_GLBL`
   module). There is also an undocumented `apm_*` helper family under `common\apm\`
   (`apm_shifter_fixed`, `apm_shifter_variable`, `apm_memory_base/sprom/dprom/dpdram/sdpram/
   spram/tdpram`, `apm_byte_memory_*`).
2. **`EG_`, never `EG4_`.** `EG4` is only a *directory* name (`Device-Primitive\EG4\eg4_*.v`,
   `sim_release\eg4\`). No `EG4_*` primitive exists anywhere.
3. **`DR1_` and `DR1P_` co-exist.** `DR1P_LOGIC_TVS` is declared in
   `sim_release\common\apm\logic_tvs.v` alongside `PH2_LOGIC_TVS`, `PH1_LOGIC_TS`,
   `DR1_LOGIC_TS` and `PH1P_LOGIC_TVS`. `DR1P_` appears in **no** Device-Primitive template and
   in **no** guide — simulation-library only. Likewise `PH2A` never uses a `PH2A_` prefix (always
   `PH2_`), and PH1A / PH1A100 share `PH1_`.

**`_V2` / `_V3` is a part-revision split, not a guide version.** Example from the installed
`PH1A\Clock\ph1a_clock.v`: `PH1_PHY_LCLK` — *"Used for PH1A100 only"*;
`PH1_PHY_LCLK_V2` — *"Used for PH1A60,PH1A90,PH1A180,PH1A400 only"*. The same split applies to
`LCLK`, `GCLK`, `MLCLK`, `SCLK`, `ECC`, `MBOOT`, `DNA`, `CONFIG`, and elsewhere to `DSPMULT`,
`PCIE`, `SERDES_DUAL`, `HXT`, `ERAM`, `PLX`. **Confirm the exact part number before choosing a
suffix.**

### B.2 Where primitive templates live

```
<TD root>\template\verilog\Device-Primitive\<FAMILY>\<Category>\<family>_<category>.v
```

`<root>` = `C:/Tools/Anlogic/TD_6.2.168116`.

**Layout verified by direct enumeration — it matches exactly:**

| FAMILY | Categories present |
|---|---|
| `DR1` | Advanced · Arithmetic · Clock · Config · I,O · Logic,Register · RAM,ROM |
| `EF2` | Advanced · Arithmetic · Clock · Config · I,O · Logic,Register · RAM,ROM |
| `EF3` | Arithmetic · Clock · Config · I,O · Logic,Register · RAM,ROM *(no `Advanced`)* |
| `EF4` | Arithmetic · Clock · Config · I,O · Logic,Register · RAM,ROM *(no `Advanced`)* |
| `EG4` | Advanced · Arithmetic · Clock · Config · I,O · Logic,Register · RAM,ROM |
| `PH1A` | Advanced · Arithmetic · Clock · Config · I,O · Logic,Register · RAM,ROM |
| `PH1P` | Advanced · Arithmetic · Clock · Config · I,O · Logic,Register · RAM,ROM |
| `PH2A` | Advanced · Arithmetic · Clock · Config · I,O · Logic,Register · RAM,ROM |
| `SF1` | Advanced · Arithmetic · Clock · Config · **Hard-IP** · I,O · Logic,Register · RAM,ROM |
| `SF2` | Arithmetic · Clock · Config · **Hard-IP** · I,O · Logic,Register · RAM,ROM *(no `Advanced`)* |

`Hard-IP` exists only for SF1/SF2; `Advanced` is absent for EF3/EF4/SF2; `I,O`, `Logic,Register`
and `RAM,ROM` are literal directory names containing commas.

One file per (family, category), named `<lowercase family>_<lowercase category>.v`, keeping
commas and hyphens literally:

```
dr1_advanced.v   dr1_arithmetic.v   dr1_clock.v   dr1_config.v
dr1_i_o.v        dr1_logic_register.v             dr1_ram_rom.v
sf1_hard-ip.v    sf2_hard-ip.v      ph2a_clock.v  ef2_ram_rom.v   eg4_advanced.v
```

> **Important caveat about what these files are.** Each `<family>_<category>.v` declares only a
> *container* module (e.g. `module ph1a_clock;`). The real primitive names live in header
> **comments** of the form `// <Description>  (<PRIMITIVE_NAME>)`, often with a
> `// Used for <parts> only` gate. So these templates are the best annotated **parameter**
> source, but they are **not** guaranteed complete against the guides. Verified gaps:
> * `PH2_PHY_PLL` — documented in UG1110 §43 (p.100) and present as
>   `sim_release\ph2\ph2_phy_pll.v`, but **no `PH2_PHY_PLL` block exists anywhere** in
>   `template\verilog\Device-Primitive` (`PH2A\Clock\ph2a_clock.v` carries only
>   `PH2_PHY_DPLL` and `PH2_PHY_OSCDIV`). Do not invent its parameter names — generate via the
>   IP Generator or copy from the simulation model.
> * `PH2_PHY_OSC` — sim model exists (`sim_release\ph2\ph2_phy_osc.v`), no template.
> * `DR1\Config\dr1_config.v` lists only `DR1_LOGIC_DNA`, while
>   `sim_release\dr1\dr1_logic_config.v` also declares `DR1_LOGIC_GSRN`, `DR1_LOGIC_ECC`,
>   `DR1_LOGIC_GCTRL`.
> * `EF4\I,O\ef4_i_o.v` mislabels `EF4_PHY_INTFLASH` (a Config/Flash primitive listed under
>   I/O) — a generation artefact.

For an authoritative module/port list, cross-check `sim_release\<family>\`.

### B.3 PLL, global clock, and GSR primitives

#### B.3.1 PLL primitives per family

| Family | PLL primitive(s) | Template present | Doc |
|---|---|---|---|
| PH1A (+ PH1A100) | `PH1_PHY_PLL` | yes | UG910 §27 p.64 |
| PH1P | `PH1P_PHY_PLL` (**PH1P100 only**), `PH1P_PHY_PLL_V2` (**PH1P35, PH1P50 only**) | yes | UG1310 §46 p.97, §47 p.105 |
| PH2A | `PH2_PHY_PLL` **and** `PH2_PHY_DPLL` (De-Skew PLL) | `PH2_PHY_PLL` **missing**; `PH2_PHY_DPLL` present | UG1110 §43 p.100, §44 p.108 |
| DR1 | `DR1_PHY_PLL` | yes | UG1211 §25 p.63 |
| EF2 / EF3 / EF4 | `EF2_PHY_PLL` / `EF3_PHY_PLL` / `EF4_PHY_PLL` | yes | (no Libraries Guide supplied) |
| EG4 | `EG_PHY_PLL` | yes | — |
| SF1 | `SF1_PHY_PLL` | yes | — |
| SF2 | `SF2_PHY_PLL` (`PLL_LOC="PLL1"`) | yes | — |

Related oscillator / clock-multiplier primitives: `PH1_PHY_OSC`, `PH1_PHY_OSCDIV`,
`PH1P_PHY_OSC`, `PH1P_PHY_OSCDIV`, `PH2_PHY_OSC`, `PH2_PHY_OSCDIV`, `DR1_PHY_OSC`,
`DR1_PHY_OSCDIV`, `EF2/EF3/EF4_PHY_OSC`, `EG_PHY_OSC`, `SF1_PHY_OSC`, `SF1_PHY_OSCDIV`,
`SF2_PHY_OSC`, `SF2_LOGIC_OSCDIV32`, `SF2_LOGIC_OSCDIV128`.

#### B.3.2 PLL parameter summary

`FIN` is explicitly *"实际应用不使用"* / *"no use in fact"* — it only tags the reference
frequency for the software. **There is no user-facing "clock input range" parameter**; the legal
`refclk` range comes from the device datasheet.

| Function | PH1A `PH1_PHY_PLL` | PH1P `PH1P_PHY_PLL(_V2)` | PH2A `PH2_PHY_PLL` | DR1 | SF2 |
|---|---|---|---|---|---|
| Input divider | `REFCLK_DIV` 1–128 | `REFCLK_DIV` 1–128 | `REFCLK_DIV` 1–128 | `REFCLK_DIV` | `REFCLK_DIV` 1–128 |
| Feedback divider | `FBCLK_DIV` 1–128 | `FBCLK_DIV` 1–128 | `FBCLK_DIV` 1–128 | — | `FBCLK_DIV` 1–128 |
| Output dividers | `CLKC0_DIV`…`CLKC6_DIV`, 1–128 | same | `CLKC0_DIV`…`CLKC7_DIV` | `CLKC*_DIV` | `CLKC0_DIV`…`CLKC6_DIV` |
| Pre-div2 per output | `CLKC*_DIV2_ENABLE` | uses `CLKC*_DUTY_INT` | — | — | — |
| Duty cycle | `CLKC*_DUTY50` (`ENABLE`/`DISABLE`, dflt `ENABLE`), `CLKC*_DUTY_INT` 1–127 | same | same | — | `CLKC*_DUTY50` |
| Fine phase (static) | `CLKC0..6_FPHASE` 0–7 + `CLKC*_FPHASE_RSTSEL` 0/1 | same | `CLKC*_FPHASE` 0–7 | — | `CLKC*_FPHASE` 0–7 |
| Coarse phase (static) | `CLKC0..6_CPHASE` 0–127, `CLKC*_CPHASE_DIV2` 0/1 | `CLKC*_CPHASE` 0–127 | `CLKC*_CPHASE` | — | `CLKC*_CPHASE` 0–127 |
| Dynamic phase | `DYN_PHASE_PATH_SEL`, `DYN_FPHASE_EN`, `PHASE_PATH_SEL` 0–6, `DYN_CPHASE_CLKC*_DIV_EN`, `DYN_CPHASE_CLKC*_DIV2_EN`; ports `psclk`/`psclksel[2:0]`/`psstep`/`psdown`/`psdone` | + `DYN_CPHASE_EN`, `PADDRW`/`PDATAW` = 32 | ports `psclk`/`psclksel`/`psstep`/`psdown`/`psdone` | — | `DYN_CPHASE_CLKC*_DIV_EN`, same ports |
| Feedback modes | `FEEDBK_MODE`: `"NORMAL"`,`"SOURCESYNC"`,`"NOCOMP"`,`"ZERODELAY"`; `FBKCLK` (`CLKC0_EXT`…`CLKC6_EXT`), `FBKCLK_INT` (`"SSCCLK"`,`"CLKC0_INT"`…`"CLKC5_INT"`,`"VCO_PHASE0"`); `PLL_FEED_TYPE`: `"INTERNAL"`/`"EXTERNAL"` | `PLL_FEED_TYPE`, `PLL_FASTLOOP` | `FBKCLK`/`FBKCLK_INT` extended to `CLKC7_*`; `FIN0`/`FIN1` for the two `refclk` inputs | — | as PH1A |
| Loop bandwidth | `LPF_RES` 0–7, `LPF_CAP` 0–3, `ICP_CUR` 0–31, `GMC_GAIN` 0–7, `INTPI` 0–3 (VCO level) | `LPF_RES` 0–3, `LPF_CAP` 0–31, `ICP_CUR` 0–31 | `LPF_RES` 0–15, `ICP_CUR`, `GMC_GAIN` | — | `LPF_RES` 0–7, `LPF_CAP` 0–3, `ICP_CUR` 0–31, `GMC_GAIN` 0–7, `INTPI` |
| Fractional / SSC | `FRAC_ENABLE`, `DITHER_ENABLE`, `SDM_FRAC` 0–4095, `SSC_ENABLE`, `SSC_MODE` `"UP"/"DOWN"/"CENTER"`, `SSC_FREQ_DIV`, `SSC_RNGE`, `SSC_AMP` 0–3 %, `EXT_USR_FREQ_EN`, `FREQ_OFFSET`, `HIGH_SPEED_EN` | `FRAC_ENABLE`, `SDM_FRAC`, `SSC_*`, `CLKC0_FRAC`, `PI_OUT_SEL`, `PI_FRAC_EN`, `CLKC0_PI_SHIFT_EN` | `FRAC_ENABLE`, `SDM_FRAC`, `SSC_*`, `CLKC0_FRAC_EN` | — | `FRAC_ENABLE`, `DITHER_ENABLE`, `SDM_FRAC`, `SSC_*` |
| Misc | `WORK_MODE` `"WAKE_UP"/"USERS"`, `PD_DIG`, `REFCLK_USR_RST`, `PLL_USR_RST`, `MPHASE_ENABLE`, `DERIVE_PLL_CLOCKS`, `GEN_BASIC_CLOCK`, `REFCLK_DET_BYP` | `WORK_MODE` `"USER"/"LOCK_BEFORE_WAKE_UP"`, `PD_DIG`, `SSC_RST`, `CLKC*_FRAC_EN` | `refclk_sel`, `ssc_reset`, `int_lock`, `wakeup` | — | `PLL_USR_CLKC_RST`, `PLL_USR_PD` |

**`PH1_PHY_PLL` complete port list** (verbatim, UG910 §27.2 p.65-66 and the installed template):

```
PH1_PHY_PLL
  refclk  fbclk  wakeup  drp_clk  drp_rstn  clkcb[7:0]  clkc[7:0]  drp_err  drp_rdy
  drp_rdata[7:0]  psdone  drp_sel  drp_rd  drp_wr  drp_addr[7:0]  drp_wdata[7:0]
  pllpd  psclksel[2:0]  psstep  psdown  ssc_en  psclk  clkc_en[7:0]  pllreset
  clkc_rst[1:0]  ext_freq_mod_clk  ext_freq_mod_en  ext_freq_mod_val[16:0]
  cps_step[1:0]  lock  refclk_rst
```

Critical port notes: `pllpd` **high = PLL OFF**; `wakeup` **must be tied 1**; `ssc_en` **must be
tied 1 when SSC is used**; `clkc_rst[0]` resets `clkout_c[0:3]` and `clkc_rst[1]` resets
`clkout_c[4:6]`.

#### B.3.3 Complete PH1A PLL instantiation

50 MHz in → 100 MHz (`clkc[0]`) + 200 MHz (`clkc[1]`) out, internal feedback, static lock.
VCO = `refclk / REFCLK_DIV * FBCLK_DIV * CLKCn_DIV` = 50/1 × 16 × 1 = 800 MHz.
Every parameter and port name below is verbatim from the installed template.

```verilog
// PH1A PLL: refclk 50 MHz -> clkc[0] = 100 MHz, clkc[1] = 200 MHz. VCO = 800 MHz.
PH1_PHY_PLL #(
  .FBKCLK              ( "CLKC0_EXT"  ),  // "CLKC0_EXT".."CLKC6_EXT". Feedback clock path.
  .FBKCLK_INT          ( "VCO_PHASE0" ),  // "SSCCLK","CLKC0_INT".."CLKC5_INT","VCO_PHASE0".
  .REFCLK_DIV          ( 1            ),  // 1~128.  Input divide.
  .FBCLK_DIV           ( 16           ),  // 1~128.  Feedback divide.
  .CLKC0_FPHASE        ( 0            ),  // 0~7.    Output fine tuning.
  .CLKC0_CPHASE        ( 0            ),  // 0~127.  Output coarse tuning.
  .CLKC0_DIV           ( 8            ),  // 1~128.
  .CLKC0_DIV2_ENABLE   ( "DISABLE"    ),  // "ENABLE","DISABLE".
  .CLKC0_DUTY50        ( "ENABLE"     ),  // "ENABLE","DISABLE".
  .CLKC0_DUTY_INT      ( 1            ),  // 1~127, range {1, CLKC0_DIV-1}; unused when CLKC0_DIV=1.
  .CLKC0_ENABLE        ( "ENABLE"     ),  // "ENABLE","DISABLE".
  .CLKC0_FPHASE_RSTSEL ( 0            ),  // 0 when CLKC0_FPHASE=0~3, 1 when 4~7.
  .CLKC0_USR_RST       ( "ENABLE"     ),  // "ENABLE","DISABLE".
  .PREDIV_MUXC0        ( "VCO"        ),  // "VCO","CLK6_INT","CLK_INT_MAIN","REFCLK".
  .DIVOUT_MUXC0        ( "DIV"        ),  // "DIV","REFCLK".
  .CLKC1_FPHASE        ( 0            ),
  .CLKC1_CPHASE        ( 0            ),
  .CLKC1_DIV           ( 4            ),
  .CLKC1_DUTY50        ( "ENABLE"     ),
  .CLKC1_ENABLE        ( "ENABLE"     ),
  .CLKC1_USR_RST       ( "ENABLE"     ),
  .PREDIV_MUXC1        ( "VCO"        ),
  .DIVOUT_MUXC1        ( "DIV"        ),
  .WORK_MODE           ( "USER"       ),  // "USER","WAKE_UP".
  .FEEDBK_MODE         ( "NORMAL"     ),  // "NORMAL","SOURCESYNC","NOCOMP","ZERODELAY".
  .PLL_FEED_TYPE       ( "INTERNAL"   ),  // "INTERNAL","EXTERNAL".
  .PD_DIG              ( "DISABLE"    ),
  .REFCLK_USR_RST      ( "DISABLE"    ),
  .PLL_USR_RST         ( "DISABLE"    ),
  .LPF_RES             ( 2            ),  // 0~7.
  .LPF_CAP             ( 2            ),  // 0~3.
  .ICP_CUR             ( 12           ),  // 0~31.
  .GMC_GAIN            ( 2            ),  // 0~7.
  .INTPI               ( 0            ),  // 0~3. VCO level.
  .FRAC_ENABLE         ( "DISABLE"    ),
  .DITHER_ENABLE       ( "DISABLE"    ),
  .SDM_FRAC            ( 0            ),  // 0~4095.
  .SSC_ENABLE          ( "DISABLE"    ),
  .SSC_MODE            ( "CENTER"     ),  // "UP","DOWN","CENTER".
  .SSC_FREQ_DIV        ( 0            ),
  .SSC_RNGE            ( 242          ),
  .MPHASE_ENABLE       ( "DISABLE"    ),
  .DYN_PHASE_PATH_SEL  ( "DISABLE"    ),
  .DYN_FPHASE_EN       ( "DISABLE"    ),
  .PHASE_PATH_SEL      ( 0            ),  // 0~6.
  .REFCLK_OUT_ENABLE   ( "DISABLE"    ),
  .CLK_MAIN_ENABLE     ( "DISABLE"    ),
  .REFCLK_DET_BYP      ( "DISABLE"    ),  // "DISABLE" = enable detection, "ENABLE" = bypass.
  .DERIVE_PLL_CLOCKS   ( "DISABLE"    ),  // SDC constraint enable.
  .GEN_BASIC_CLOCK     ( "DISABLE"    )
) u_PH1_PHY_PLL (
  .refclk           ( refclk     ),  // 1  in   PLL reference clock input.
  .refclk_rst       ( refclk_rst ),  // 1  in   PLL reference clock reset.
  .fbclk            ( fbclk      ),  // 1  in   Feedback clock (unused when PLL_FEED_TYPE="INTERNAL").
  .clkc             ( clkc       ),  // 8  out  PLL clock output.
  .clkcb            ( clkcb      ),  // 8  out  PLL clock output, inverted w.r.t. clkc.
  .wakeup           ( 1'b1       ),  // 1  in   MUST be tied 1.
  .lock             ( pll_lock   ),  // 1  out  PLL lock, high active.
  .pllreset         ( pllreset   ),  // 1  in   PLL reset, high active.
  .clkc_rst         ( clkc_rst   ),  // 2  in   clkc_rst[0]->clkout_c[0:3], clkc_rst[1]->clkc[4:6].
  .clkc_en          ( clkc_en    ),  // 8  in   Output clock enable.
  .pllpd            ( pllpd      ),  // 1  in   Power switch, HIGH = PLL OFF.
  .cps_step         ( cps_step   ),  // 2  in   Dynamic coarse adjust.
  .psclk            ( psclk      ),  // 1  in   Dynamic phase adjustment clock.
  .psclksel         ( psclksel   ),  // 3  in   Selects one output for phase shift.
  .psstep           ( psstep     ),  // 1  in   Phase-shift trigger, rising edge.
  .psdown           ( psdown     ),  // 1  in   Phase-shift direction.
  .psdone           ( psdone     ),  // 1  out  Phase shift complete.
  .ssc_en           ( 1'b0       ),  // 1  in   SSC enable; tie 1 when SSC is used.
  .drp_clk          ( drp_clk    ),  // 1  in   Dynamic reconfiguration clock.
  .drp_rstn         ( drp_rstn   ),  // 1  in   Dynamic reconfiguration reset, low active.
  .drp_sel          ( drp_sel    ),  // 1  in   Dynamic reconfiguration chip select, high active.
  .drp_rd           ( drp_rd     ),  // 1  in   Dynamic reconfiguration read enable.
  .drp_wr           ( drp_wr     ),  // 1  in   Dynamic reconfiguration write enable.
  .drp_addr         ( drp_addr   ),  // 8  in   Dynamic reconfiguration address.
  .drp_wdata        ( drp_wdata  ),  // 8  in   Dynamic reconfiguration write data.
  .drp_rdata        ( drp_rdata  ),  // 8  out  Dynamic reconfiguration read data.
  .drp_rdy          ( drp_rdy    ),  // 1  out  Read-data end flag.
  .drp_err          ( drp_err    ),  // 1  out  Dynamic reconfiguration error, high active.
  .ext_freq_mod_clk ( 1'b0       ),  // 1  in   External SSC modulation clock (depth < 3%).
  .ext_freq_mod_en  ( 1'b0       ),  // 1  in   External SSC modulation enable.
  .ext_freq_mod_val ( 17'd0      )   // 17 in   External SSC amplitude adjust.
);

wire clk_100m = clkc[0];
wire clk_200m = clkc[1];
```

**PH2A note.** `PH2_PHY_PLL` is documented (UG1110 §43 p.100) and exists as
`sim_release\ph2\ph2_phy_pll.v` (ports `refclk[1:0]`, `refclk_sel`, `fbclk`, `clkc[7:0]`,
`clkcb[7:0]`, `clkc_rst[1:0]`, `pllpd`, `pllreset`, `lock`, `int_lock`, `psdone`, `psclk`,
`psdown`, `psstep`, `psclksel`, `clkc_en`, `cps_step`, `ssc_reset`, `dig_out`, `wakeup`) — but
there is **no `PH2_PHY_PLL` template block on disk**, so no authoritative vendor parameter list
exists. Generate with the IP Generator or copy from the model; **do not guess parameter names.**
`PH2_PHY_DPLL` *is* templated.

#### B.3.4 Global clock / global buffer primitives

| Family | Global / regional clock buffer primitives |
|---|---|
| PH1A | `PH1_LOGIC_BUFG` (no parameters; ports `i`, `o` only), `PH1_PHY_GCLK`, `PH1_PHY_GCLK_V2`, `PH1_PHY_LCLK`, `PH1_PHY_LCLK_V2`, `PH1_PHY_MLCLK`, `PH1_PHY_MLCLK_V2`, `PH1_PHY_SCLK`, `PH1_PHY_SCLK_V2`, `PH1_PHY_IOCLK`, `PH1_PHY_HP_MLCLK`, `PH1_PHY_HP_IOCLK` |
| PH1P | `PH1P_LOGIC_BUFG`, `PH1P_PHY_GCLK`, `PH1P_PHY_LCLK`, `PH1P_PHY_MLCLK`, `PH1P_PHY_SCLK`, `PH1P_PHY_SCLK_V2`, `PH1P_PHY_HCLK`, `PH1P_PHY_IOCLK`, `PH1P_PHY_CLOCK_ALIGNER` |
| PH2A | `PH2_LOGIC_BUFG`, `PH2_LOGIC_BUFG_CE`, `PH2_LOGIC_BUFG_CE_1`, `PH2_LOGIC_BUFG_CE_DIV`, `PH2_LOGIC_BUFG_CTRL`, `PH2_LOGIC_BUFG_HXT`, `PH2_LOGIC_BUFG_MUX`, `PH2_LOGIC_BUFG_MUX_1`, `PH2_LOGIC_BUFG_MUX_CTRL`, `PH2_PHY_SBUF`, `PH2_PHY_SBUF_H`, `PH2_PHY_CBUF` (glitchless clock mux), `PH2_PHY_DBUF` (divider buffer), `PH2_PHY_DBUF_HXT`, `PH2_PHY_HP_BYTECLK_RX`, `PH2_PHY_HP_IODIV` |
| DR1 | `DR1_LOGIC_BUFG`, `DR1_PHY_GCLK`, `DR1_PHY_LCLK`, `DR1_PHY_MLCLK`, `DR1_PHY_SCLK`, `DR1_PHY_IOCLK` |
| EF2/EF3/EF4 | `EFx_LOGIC_BUFG`, `EFx_LOGIC_BUFGMUX`, `EFx_LOGIC_BUFIO` |
| EG4 | `EG_LOGIC_BUFG`, `EG_LOGIC_BUFGMUX`, `EG_LOGIC_BUFIO` |
| SF1 | `SF1_LOGIC_BUFG`, `SF1_LOGIC_BUFGMUX`, `SF1_LOGIC_BUFIO` |
| SF2 | `SF2_LOGIC_BUFG`, `SF2_PHY_GCLK`, `SF2_PHY_HSIO_CLK` |

`PH1_PHY_GCLK_V2` (verbatim from `PH1A\Clock\ph1a_clock.v`) — the glitchless clock MUX:

```verilog
PH1_PHY_GCLK_V2 #(
  .PRESELECT   ( "CLK0"   ),  // "CLK0","CLK1". Initial clock output selection.
  .HOLD        ( "YES"    ),  // "YES","NO".    Output hold; YES -> holds HIGH, else LOW.
  .SEL_TRIGGER ( "POS"    ),  // "POS","NEG".   Sampling edge selection.
  .GSR         ( "ENABLE" )   // "ENABLE","DISABLE". Global reset enable.
) u_PH1_PHY_GCLK_V2 (
  .seln   ( seln   ),  // 2 in   Clock select, LOW active.
  .cen    ( cen    ),  // 2 in   Register clock enable, LOW active.
  .drct   ( drct   ),  // 2 in   Glitchless switch enable:
                       //        2'b00 = glitchless (loses one falling edge);
                       //        2'b11 = normal (may glitch).
  .clkin  ( clkin  ),  // 2 in
  .clkout ( clkout )   // 1 out
);
```

Doc constraints (UG910 §20.3 p.51): if either `clkin` is held HIGH the GCLK block does not work
(force one input LOW); do not enable both `seln` and `cen`; with `drct=2'b00` level inputs are
unsupported; with `drct=2'b11` and `seln=2'b00` the output is unknown.

PH2A buffer parameter sets (verbatim):

```verilog
PH2_PHY_CBUF #(               // Global Clock Select Buffer (glitchless mux)
  .PRESELECT ( "CLK0" ), .HOLD ( "YES" ), .SEL_TRIGGER ( "POS" ), .GSR ( "DISABLE" ),
  .SELINV0 ( "SIG" ), .SELINV1 ( "SIG" ), .CEINV0 ( "SIG" ), .CEINV1 ( "SIG" ) );

PH2_PHY_SBUF #(               // Single-input global clock buffer
  .GSR ( "DISABLE" ), .CE_BYPASS ( "ENABLE" ), .USRCLKINV ( "SIG" ),
  .CEINV ( "SIG" ), .RSTMODE ( "ASYNC" ) );

PH2_PHY_DBUF #(               // Global clock divider buffer
  .DIV ( 1 ), .GSR ( "DISABLE" ), .RST_MODE ( "ASYNC" ), .CEINV ( "SIG" ),
  .USRCLKINV ( "SIG" ), .CE_BYPASS ( "ENABLE" ), .CLKOUT_MODE ( "GND" ) );
                              // CLKOUT_MODE: "GND","BYPASS","DIV2TO8","CLKDIV1"

PH2_LOGIC_BUFG_CE_DIV #(
  .DIV ( 1 ),                 // 1,2,3,4,5,6,7,8
  .CLKINV ( "SIG" ), .CEINV ( "SIG" ), .RST_MODE ( "SYNC" ),
  .CLKOUT_MODE ( "CLKDIV1" )  // "BYPASS","DIV2TO8","CLKDIV1"
);
```

#### B.3.5 GSR and configuration primitives

* **There is no user-instantiable `GSR` or `STARTUP` primitive template.** `GSR` appears as a
  **parameter** on many primitives, with values `"ENABLE"` / `"DISABLE"`:
  `PH1_LOGIC_SLICE.GSR` (default `"ENABLE"`, UG910 §15.3 p.48), `PH1_PHY_GCLK_V2.GSR`,
  `PH1P_PHY_GCLK.GSR`, `PH2_PHY_CBUF/SBUF/DBUF.GSR` (default `"DISABLE"`),
  `PH2_PHY_ERAM.GSR` (default `"ENABLE"`), `PH2_LOGIC_BUFG.GSR`, `DR1_LOGIC_SLICE.GSR`.
* Related user-visible reset parameters: `USR_GSRN_EN` (EF2/EF3/EF4/EG `*_PHY_CONFIG`),
  `USER_GSRN` (PH1A/PH1P/PH2A/DR1 DSP primitives — *"Whether to use the global reset signal"*).
* **The GSR cells exist only as zero-port simulation models** — they are not instantiated from
  RTL:

```verilog
module PH1_PHY_GSR();   // sim_release\ph1\ph1_phy_gsr.v
module PH1P_PHY_GSR();  // sim_release\ph1p\ph1p_phy_gsr.v
module PH2_PHY_GSR();   // sim_release\ph2\ph2_phy_gsr.v
module DR1_PHY_GSR();   // sim_release\dr1\dr1_phy_gsr.v
module SF2_PHY_GSR();   // sim_release\sf2\sf2_phy_gsr.v
module glbl();          // sim_release\common\al_phy_glbl.v (also ef2/ef3/ef4/eg4/sf1)
```

  Their internal signals are `done_gwe`, `gsr`, `gsrn`, `usr_gsrn_en`; `gsr` starts at 1 /
  `gsrn` at 0 and is released after `#20_000` / `#10_000`.
* **Testbench requirement.** Any design instantiating device primitives must also instantiate the
  family's global-reset model and release GSR before starting clocks:
  `PH1_PHY_GSR` (PH1A/PH1A100), `PH1P_PHY_GSR` (PH1P), `PH2_PHY_GSR` (PH2A), `DR1_PHY_GSR` (DR1),
  `SF2_PHY_GSR` (SF2), and **`glbl`** for EF2 (`ef2_phy_glbl.v`), EF3, EF4, EG4
  (`eg_phy_glbl.v`), SF1, plus the shared `common\al_phy_glbl.v`.
* **Configuration primitives** (the nearest thing to `STARTUP`):

| Family | Configuration primitives |
|---|---|
| PH1A | `PH1_LOGIC_MBOOT` (**PH1A100 only**), `PH1_LOGIC_MBOOT_V2`, `PH1_LOGIC_DNA`, `PH1_LOGIC_DNA_V2`, `PH1_LOGIC_ICAP_V2`, `PH1_LOGIC_ECC` (**PH1A100 only**), `PH1_LOGIC_ECC_V2` |
| PH1P | `PH1P_LOGIC_MBOOT` / `_V2`, `PH1P_LOGIC_DNA`, `PH1P_LOGIC_ICAP`, `PH1P_LOGIC_DEVICE_VERSION`, `PH1P_LOGIC_DUALBOOT`, `PH1P_LOGIC_ECC` |
| PH2A | `PH2_LOGIC_MBOOT`, `PH2_LOGIC_DNA`, `PH2_LOGIC_ICAP`, `PH2_LOGIC_ECC` |
| DR1 | `DR1_LOGIC_DNA`, `DR1_LOGIC_ECC` |
| EF2/EF3/EF4 | `EFx_LOGIC_MBOOT`, `EFx_LOGIC_DNA`, `EFx_PHY_CONFIG`, `EFx_PHY_INTFLASH`; EF3 adds `EF3_LOGIC_MBOOT_V2`, `EF3_LOGIC_DNA_V2`, `EF3_LOGIC_FREEZEIO_V2`, `EF3_PHY_CONFIG_V2` (**EF3LA0 only**) |
| EG4 | `EG_LOGIC_MBOOT`, `EG_LOGIC_DNA`, `EG_PHY_CONFIG` |
| SF1 | `SF1_LOGIC_CCLK`, `SF1_LOGIC_MBOOT`, `SF1_LOGIC_DNA`, `SF1_PHY_INTFLASH` |
| SF2 | `SF2_LOGIC_MBOOT`, `SF2_LOGIC_DNA`, `SF2_LOGIC_DEVICE_VERSION`, `SF2_PHY_INTFLASH` |

### B.4 Other primitive categories

#### B.4.1 IO buffers and DDR IO registers

| Family | I/O primitives |
|---|---|
| PH1A | `PH1_LOGIC_IBUF`, `PH1_LOGIC_OBUF`, `PH1_LOGIC_IOBUF`, `PH1_LOGIC_IBUFDIFF`, `PH1_LOGIC_IOTRIBUF`, `PH1_LOGIC_IDDR`, `PH1_LOGIC_ODDR`, `PH1_LOGIC_IDDRx2`, `PH1_LOGIC_ODDRx2`, `PH1_LOGIC_IDDRx2l`, `PH1_LOGIC_ODDRx2l`, `PH1_LOGIC_HP_ISERDES`, `PH1_LOGIC_HP_OSERDES` |
| PH1P | `PH1P_LOGIC_IBUF`, `PH1P_LOGIC_OBUF`, `PH1P_LOGIC_IOBUF`, `PH1P_LOGIC_IBUF_DIFF`, `PH1P_LOGIC_OBUF_DIFF`, `PH1P_LOGIC_IOBUF_DIFF`, `PH1P_LOGIC_IOTRIBUF`, `PH1P_LOGIC_IDDR`, `PH1P_LOGIC_ODDR`, `PH1P_LOGIC_IDDRx2`, `PH1P_LOGIC_ODDRx2`, `PH1P_LOGIC_HD_IDDR`, `PH1P_LOGIC_HD_ODDR`, `PH1P_LOGIC_HR_ISERDES`, `PH1P_LOGIC_HR_OSERDES` |
| PH2A | `PH2_LOGIC_IBUF`, `PH2_LOGIC_OBUF`, `PH2_LOGIC_IOBUF`, `PH2_LOGIC_IBUFDIFF`, `PH2_LOGIC_IOTRIBUF`, `PH2_LOGIC_HD_IDDR/_ODDR/_IDDRx2/_ODDRx2/_IDDRx2L/_ODDRx2L`, `PH2_LOGIC_HP_IDDR`, `PH2_LOGIC_HP_ODDR`, `PH2_LOGIC_HP_ISERDES`, `PH2_LOGIC_HP_OSERDES` |
| DR1 | `DR1_LOGIC_IOBUF`, `DR1_LOGIC_IOTRIBUF`, `DR1_LOGIC_IDDR`, `DR1_LOGIC_ODDR`, `DR1_LOGIC_IDDRx2`, `DR1_LOGIC_ODDRx2`, `DR1_LOGIC_IDDRx2l`, `DR1_LOGIC_ODDRx2l` |
| EF2 / EG4 | `EFx_LOGIC_IDDR`, `EFx_LOGIC_ODDR`, `EFx_LOGIC_IDDRx2`, `EFx_LOGIC_ODDRx2`, `EFx_LOGIC_ODDRx2l`, `EFx_LOGIC_IDELAY`, `EFx_LOGIC_ODELAY`; EF2 adds `EF2_LOGIC_MIPIIO`, `EF2_PHY_MIPIIO` |
| SF1 | `SF1_LOGIC_IBUF`-style set + `SF1_LOGIC_MCU_JTAG`, `SF1_LOGIC_IDELAY`, `SF1_LOGIC_ODELAY` |
| SF2 | `SF2_LOGIC_IBUF/OBUF/IOBUF/IBUF_DIFF/OBUF_DIFF/IOBUF_DIFF/IOTRIBUF`, `SF2_LOGIC_HS_ISERDES`, `SF2_LOGIC_HS_OSERDES` |

Dynamic-delay primitives: `PH1_LOGIC_DYNAMIC_IDELAY`, `PH1_LOGIC_DYNAMIC_HP_IDELAY`,
`PH1_LOGIC_DYNAMIC_HP_ODELAY`, `PH1P_LOGIC_DYNAMIC_IDELAY`, `PH1P_LOGIC_DYNAMIC_HR_IDELAY`,
`PH1P_LOGIC_DYNAMIC_HR_ODELAY`, `PH1P_LOGIC_DYNAMIC_HD_IDELAY`, `PH1P_LOGIC_DYNAMIC_HD_ODELAY`,
`PH2_LOGIC_DYNAMIC_HP_IDELAY`, `PH2_LOGIC_DYNAMIC_HP_ODELAY`, `PH2_LOGIC_DYNAMIC_HD_IDELAY`,
`PH2_LOGIC_DYNAMIC_HD_ODELAY`, `DR1_LOGIC_DYNAMIC_IDELAY`, `SF1_LOGIC_DYNAMIC_IDELAY`,
`SF2_LOGIC_DYNAMIC_HS_IDELAY`, `SF2_LOGIC_DYNAMIC_HS_ODELAY`.

PH1A DDR IO registers (verbatim usage style from UG910 §4–§9):

```verilog
PH1_LOGIC_IDDR   u_iddr   ( .q0(q0), .q1(q1), .clk(clk), .d(d),   .rst(rst) );
PH1_LOGIC_ODDR   u_oddr   ( .q(q),   .clk(clk), .d0(d0), .d1(d1), .rst(rst) );
PH1_LOGIC_IDDRx2 u_iddrx2 ( .q0(q0), .q1(q1), .q2(q2), .q3(q3), .clk(clk), .d(d), .rst(rst) );
PH1_LOGIC_ODDRx2 u_oddrx2 ( .q(q), .clk(clk), .d0(d0), .d1(d1), .d2(d2), .d3(d3), .rst(rst) );
```

#### B.4.2 Block RAM / distributed RAM primitives

| Family | Memory primitives |
|---|---|
| PH1A | `PH1_LOGIC_ERAM`, `PH1_LOGIC_DRAM`, `PH1_LOGIC_DRAM32X16`, `PH1_LOGIC_DRAM32X16R8`, `PH1_LOGIC_DRAM64X8`, `PH1_LOGIC_DRAM64X8R16`, `PH1_LOGIC_FIFO`, `PH1_LOGIC_RAMFIFO` |
| PH1P | `PH1P_LOGIC_ERAM`, `PH1P_LOGIC_DRAM` (+`32X16`,`32X16R8`,`64X8`,`64X8R16`), `PH1P_LOGIC_FIFO`, `PH1P_LOGIC_RAMFIFO` |
| PH2A | `PH2_PHY_ERAM`, `PH2_PHY_ERAM_144K` — the only two memory primitives in the family |
| DR1 | `DR1_LOGIC_ERAM`, `DR1_LOGIC_DRAM` (+ variants), `DR1_LOGIC_FIFO`, `DR1_LOGIC_RAMFIFO` |
| EF2 | `EF2_LOGIC_BRAM`, `EF2_PHY_BRAM32K`, `EF2_PHY_BRAM128K`, `EF2_PHY_BRAM256K`, `EF2_LOGIC_DRAM`, `EF2_LOGIC_DRAM16X4`, `EF2_LOGIC_FIFO`, `EF2_LOGIC_RAMFIFO`, `EF2_PHY_PSRAM_8` |
| EF3 | `EF3_LOGIC_BRAM`, `EF3_LOGIC_DRAM`, `EF3_LOGIC_DRAM16X4`, `EF3_LOGIC_FIFO`, `EF3_LOGIC_RAMFIFO` |
| EF4 | `EF4_LOGIC_BRAM`, `EF4_LOGIC_DRAM`, `EF4_LOGIC_DRAM16X4`, `EF4_LOGIC_RAMFIFO` |
| EG4 | `EG_LOGIC_BRAM`, `EG_PHY_BRAM32K`, `EG_LOGIC_DRAM`, `EG_LOGIC_DRAM16X4`, `EG_LOGIC_FIFO`, `EG_LOGIC_RAMFIFO`, `EG_PHY_DDR_8M_16`, `EG_PHY_SDRAM_2M_32` |
| SF1 | `SF1_LOGIC_BRAM`, `SF1_LOGIC_DRAM`, `SF1_LOGIC_DRAM16X4`, `SF1_LOGIC_FIFO`, `SF1_LOGIC_RAMFIFO`, `SF1_PHY_PSRAM`, `SF1_PHY_PSRAM_8`, `SF1_PHY_SHARESRAM` |
| SF2 | `SF2_LOGIC_ERAM`, `SF2_LOGIC_DRAM` (+ variants), `SF2_LOGIC_FIFO`, `SF2_LOGIC_RAMFIFO` |

`PH1_LOGIC_ERAM` key parameters (verbatim from `PH1A\RAM,ROM\ph1a_ram_rom.v`):

```verilog
PH1_LOGIC_ERAM #(
  .DATA_WIDTH_A(20), .DATA_WIDTH_B(20), .ADDR_WIDTH_A(10), .ADDR_WIDTH_B(10),
  .DATA_DEPTH_A(1024), .DATA_DEPTH_B(1024),
  .MODE("DP"),              // "DP","SP","PDPW","FIFO"
  .REGMODE_A("NOREG"),      // "NOREG","OUTREG"
  .WRITEMODE_A("NORMAL"),   // "NORMAL","READBEFOREWRITE","WRITETHROUGH"
  .RESETMODE_A("ASYNC"),    // "SYNC","ASYNC"
  .CLKMODE("ASYNC"),        // "ASYNC","SYNC"
  .OREGSET_A("SET"),        // "SET","RESET"
  .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
  .ECC_DECODE("DISABLE"), .ECC_ENCODE("DISABLE"),
  .SSROVERCE("ENABLE"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
  .FORCE_KEEP("OFF"), .INIT_FILE("NONE"), .FILL_ALL("NONE"),
  .IMPLEMENT("20K")         // "20K","20K(FAST)"
) u_eram ( ... );
```

`PH2_PHY_ERAM` essentials (verbatim): `.MODE("RAM")` / `"FIFO20K"`; `.DATA_WIDTH_A/B` ∈
{1,2,5,10,20,40}; `.RESETMODE_A/B` ∈ `"ASYNC_RESET"`, `"SYNC_RESET"`,
`"ASYNC_RESET_SYNC_RELEASE"`; `.WRITEMODE_A/B` ∈ `"WRITE_DISABLE_READ"`, `"READ_BEFORE_WRITE"`,
`"WRITE_BEFORE_READ"`; `.GSR("ENABLE")`; cascade net `CS{A,B}_MASK`; `ADDRCAS_A/B` ∈
`"NORMAL"`,`"CASFB"`; `CASCADE_ORDER_A/B` ∈ `"NONE"`,`"FIRST"`,`"MIDDLE"`,`"LAST"`; and
`INIT_00`…`INIT_3F` / `INITP_00`…`INITP_0F`.

#### B.4.3 DSP / multiplier primitives

| Family | DSP primitives |
|---|---|
| PH1A | `PH1_PHY_DSPMULT`, `PH1_PHY_DSPADD`, `PH1_PHY_DSPTADD`, `PH1_PHY_DSPREG`, `PH1_PHY_DSPMREG`, `PH1_PHY_DSPLOGIC`, `PH1_LOGIC_MULT` |
| PH1P | `PH1P_PHY_DSPMULT` (**PH1P100 only**), `PH1P_PHY_DSPMULT_V2` (**PH1P35,PH1P50 only**), `PH1P_PHY_DSPADD` (**PH1P100 only**), `PH1P_PHY_DSPTADD`, `PH1P_PHY_DSPLOGIC`, `PH1P_PHY_DSPSIOU`, `PH1P_PHY_DSPSIOU_V2`, `PH1P_LOGIC_MULT` |
| PH2A | `PH2_PHY_DSPMULT`, `PH2_PHY_DSPADD`, `PH2_PHY_DSPTADD`, `PH2_PHY_DSPLOGIC`, `PH2_PHY_DSPSIOU` (no `PH2_LOGIC_MULT`) |
| DR1 | `DR1_PHY_DSPMULT`, `DR1_PHY_DSPADD`, `DR1_PHY_DSPTADD`, `DR1_PHY_DSPREG`, `DR1_PHY_DSPMREG`, `DR1_PHY_DSPLOGIC`, `DR1_PHY_DSPSIOU`, `DR1_LOGIC_MULT` |
| EF2/EF3 | `EFx_PHY_MULT18` (EF3: **EF3L15, EF3L40, EF3L45, EF3L70, EF3L90 only**), `EFx_LOGIC_MULT` |
| EF4 | `EF4_PHY_MULT18` — the only DSP primitive in the family |
| EG4 | `EG_PHY_MULT18`, `EG_LOGIC_MULT` |
| SF1 | `SF1_LOGIC_MULT` |
| SF2 | `SF2_PHY_MULT18`, `SF2_LOGIC_MULT` |
| common | `AL_MAP_BLE_MULT18X18`, `AL_MAP_BLE_MULT9X9`, `AL_PHY_MULT18` |

Shared DSP parameter across PH1A/PH1P/PH2A/DR1: `.USER_GSRN("ENABLE")` — *"Whether to use the
global reset signal."*

#### B.4.4 Clock divider / gating / slice primitives

`PH1_LOGIC_SEQ_DIV`, `PH1P_LOGIC_SEQ_DIV`, `PH2_LOGIC_SEQ_DIV`, `DR1_LOGIC_SEQ_DIV`,
`EF2/EF3_LOGIC_SEQ_DIV`, `EG_LOGIC_SEQ_DIV`, `SF1_LOGIC_SEQ_DIV`, `SF2_LOGIC_SEQ_DIV` (all =
*"Divide"*); `*_LOGIC_SHIFTER` (Shifter Register — PH1A, PH1P, DR1);
`*_LOGIC_LSLICE` / `*_LOGIC_MSLICE` (EF2/EF3/EF4/EG4/SF1/SF2), `*_LOGIC_SLICE` (PH1A/PH1P/DR1),
and **`PH2_PHY_SLICE`** for PH2A (note `PHY`, not `LOGIC`); `PH2_LOGIC_BUFG_CE` / `_CE_1` /
`_CE_DIV` / `_CTRL` (clock gating with CE); `PH2_PHY_HP_IODIV`; `SF2_LOGIC_OSCDIV32` /
`SF2_LOGIC_OSCDIV128`.

#### B.4.5 Hard-IP wrapper primitives

Only two families have a literal `Hard-IP` template category: SF1 (`SF1_LOGIC_DSC` DSC SIP,
`SF1_LOGIC_DSI` DSI SIP) and SF2 (`SF2_PHY_VIDEO_PROCESSOR`).

Hard IP reachable outside that directory (wizard-generated or `PHY` category) — module names
verbatim from the installed simulation models; `_V1/_V2/_V3` are generation variants on disk:

| Hard IP | Verbatim module names |
|---|---|
| SERDES | `PH1_PHY_SERDES_DUAL`, `PH1_PHY_SERDES_DUAL_V2`, `PH1_PHY_SERDES_DUAL_V3` |
| PCIe | `PH1_PHY_PCIE`, `PH1_PHY_PCIE_V2`, `PH1_PHY_PCIE_V3`, `PH1P_PHY_PCIE_V1`, `PH2_PHY_PCIE_V1` |
| HXT transceiver | `PH1P_PHY_HXT_V1`, `PH2_PHY_HXT_V1` |
| CGMAC | `PH2_PHY_CGMAC_V1` |
| MATRIX interconnect | `PH2_PHY_MATRIX_20TO20` |
| DDR PHY (PH1A) | `PH1_LOGIC_DDRPHY_BYTE`, `PH1_LOGIC_DDRPHY_PZQ`, `PH1_PHY_DDR_PAD`, `PH1_PHY_DDR_BANK`, `PH1_PHY_DDR4_CAL` |
| DDR PHY (PH1P) | `PH1P_PHY_DDRPHY_BYTE`, `PH1P_PHY_DDRPHY_BANKREF`, `PH1P_PHY_DDRPHY_PAD`, `PH1P_PHY_DDRPHY_PAD_V2`, `PH1P_PHY_DDRPHY_PAD_V3` |
| DDR PHY (PH2A) | `PH2_PHY_DDRPHY` |
| MIPI | `PH1_PHY_MIPIIO`, `PH1P_PHY_MIPIIO_RX`, `PH1P_PHY_MIPIIO_TX`, `DR1_PHY_MIPIIO` |
| MCU subsystem (DR1 FPSoC) | `DR1_PHY_PROCESSOR_SYSTEM` |
| Misc PH1A | `PH1_PHY_TRNG` (true RNG), `PH1_PHY_TIE` |

---

## Part C — Simulation libraries

### C.1 Simulation Libraries Compiler

| Item | Value |
|---|---|
| Tool name | **Simulation Libraries Compiler** (the 图3-1 caption also prints "Simulation Library Compiler") |
| Invocation | TD GUI menu **`Tools → Simulation Libraries Compiler`** (SWUG107 §3.1 p.4, §4.2.1 p.7) |
| Separate executable | **None.** `<TD>\bin` contains only `td.exe` and `td_commands_prompt.exe`, and SWUG105 defines **no** TCL command for compiling simulation libraries. **GUI-only.** |
| Project required | **No** — "启动TD 就可以使用该功能，无需打开工程" (§4.2.1 p.8). (`Project Simulation` is the separate tool that *does* need an open, compiled project.) |
| Supported simulators | **ModelSim** and **QuestaSim** only |
| `Simulator` | selects ModelSim / QuestaSim |
| `Executable Path` | simulator executable; on Windows TD auto-detects it if it is on `PATH` |
| `Device Family` | family library to compile; supports an `all` choice (default = compile everything) |
| `Compiled Library Location` | output root — "TD 将在该路径下创建相应的文件夹保存对应器件库的编译结果" |
| `Recompile` | recompile already-compiled libraries; default off |
| Logs | progress + warnings go to the TD `console`; "Log 文件自动保存在编译库目录下" |
| When to recompile | "如果更改了TD 工具或者仿真工具版本就需要重新编译器件库" (§4.2 p.7) |

### C.2 Device-family → simulation library name mapping

**This is the mapping as SWUG107 表4-1 (p.8) states it. The table has 7 rows — there is no
`EF4`, no `DR1`, and no separate `PH1A`/`PH1P` row.**

| Library name | Device name (verbatim) | Series |
|---|---|---|
| `common` | 器件公共库 | shared by all families |
| `EF2` | SALELF® 2 系列 | SALELF 2 |
| `EF3` | SALELF® 3 系列 | SALELF 3 |
| `EG` | SALEAGLE® 系列 | SALEAGLE (EG4) |
| `PH1` | SALPHOENIX®1A 系列 | **PH1A only — the table names 1A explicitly** |
| `PH2` | SALPHOENIX®2A 系列 | PH2A |
| `SF1` | SALSWIFT® 系列 | SALSWIFT (SF1) |

Cross-check against the `Device Family` **dropdown text** (§4.2.1 p.8), which lists
"`common` 库、`EF2`、`EF3`、`EF4`、`EG`、`PH1`、`PH2`、`SF1` 以及 `all`":

| Library name | In 表4-1? | In the dropdown? | On disk (`sim_release\`)? |
|---|---|---|---|
| `common` | ✅ | ✅ | ✅ `common\` |
| `EF2` | ✅ | ✅ | ✅ `ef2\` |
| `EF3` | ✅ | ✅ | ✅ `ef3\` |
| **`EF4`** | ❌ **no row** | ✅ | ✅ `ef4\` |
| `EG` | ✅ | ✅ | ✅ `eg4\` (dir spelled `eg4`; modules are `EG_*`) |
| `PH1` | ✅ (SALPHOENIX®1A) | ✅ | ✅ `ph1\` — **shared by PH1A and PH1A100** |
| `PH2` | ✅ | ✅ | ✅ `ph2\` |
| `SF1` | ✅ | ✅ | ✅ `sf1\` |
| **`all`** | ❌ | ✅ | n/a (a dropdown-only aggregate choice) |
| **`DR1`** | ❌ | ❌ | ✅ `dr1\` |
| **`PH1P`** | ❌ | ❌ | ✅ `ph1p\` |
| **`SF2`** | ❌ | ❌ | ✅ `sf2\` |

**Summary of the answer a future agent needs:** the compiler's library names are
`common`, `EF2`, `EF3`, `EF4`, `EG`, `PH1`, `PH2`, `SF1` (+ the `all` aggregate), while the
**on-disk directory names are lowercase and additionally include `dr1`, `ph1p`, `sf2`**. The
document itself defers: "TD 支持的器件库以界面选项为准" — *the real dropdown is authoritative*.
PH1A, PH1A100 and PH1P are **not** distinguished in 表4-1 by separate library names, but they do
have separate directories on disk (`ph1` vs `ph1p`).

### C.3 `sim_release` directory inventory (verified on disk)

`<root>\sim_release\` contains **11 lowercase subdirectories**:

| Directory | Files | Corresponds to | 表4-1 name |
|---|---|---|---|
| `common\` | 13 (+ `apm\` subdir) | shared: `AL_*`, `reg_*`, `glbl`, `apm_*` | `common` |
| `dr1\` | 61 | SALDRAGON®1 (DR1) FPSoC | *(absent)* |
| `ef2\` | 39 | SALELF®2 | `EF2` |
| `ef3\` | 42 | SALELF®3 | `EF3` |
| `ef4\` | 25 | EF4 | *(absent from table, present in dropdown)* |
| `eg4\` | 31 | SALEAGLE® (EG4) — models use `EG_*` | `EG` |
| `ph1\` | 85 | SALPHOENIX®1A **and** 1A100 | `PH1` |
| `ph1p\` | 82 | SALPHOENIX®1P | *(absent)* |
| `ph2\` | 63 | SALPHOENIX®2A | `PH2` |
| `sf1\` | 42 | SALSWIFT® | `SF1` |
| `sf2\` | 46 | SF2 | *(absent)* |

The per-family **file-naming prefixes** inside each directory are documented in
`device-database.md` §3 (note `eg4\` uses `eg_*`, not `eg4_*`, and `common\` holds the
`al_map_*` mapping primitives every family needs).

### C.4 Using the compiled library in a simulator

1. Set the simulator under **`Project → Project Setting → Simulation`**:
   * `simulator` — ModelSim or QuestaSim
   * `simulator_location` — path to the simulator executable
   * `flow_sim_filelist` — generate per-stage file lists (testbench, sources, IP sim files,
     primitives). Needed for VCS; **VCS requires this box ticked**, otherwise the default
     ModelSim settings apply. The generated `.f` **must sit next to the testbench file**.
2. If the library **has** been compiled, `Project Simulation` emits a `.do` script that loads the
   device library **as a mapped library**: "若用户已经编译器件库，则仿真脚本将以映射库的形式加载
   器件库文件" (图4-9 p.11).
3. If it has **not** been compiled, the `.do` script instead adds the primitive source directory
   and the simulator compiles the primitives itself (图4-10 p.11) — slower.
4. "如果用户使用了多个TD 版本编译了同一器件库，仿真脚本中将映射最新工具版本的器件库" — the
   newest compiled version wins.
5. A VCS flow is described separately (Makefile + compile options, §5 p.12+; waveforms via DVE
   or Verdi).
6. Supported simulation stages: **Behavioral, Post RTL, Post Gate, Post Route**.

### C.5 Output locations

* Compiled output goes under the user-chosen **`Compiled Library Location`**, one folder per
  device library, created by TD.
* The log file is written into that same compiled-library directory.
* **The TD install is not modified**: pristine sim sources stay at
  `<TD root>\sim_release\<family>\`; only the user-chosen location receives compiled output.
* IP-generated simulation artefacts are separate: MIS emits `sim/fileset/fileset_mis.f` relative
  to `<mis_path>`; CGMAC emits `cgmac_core_ip_sim.txt` and `cgmac_core_ip_syn.txt`.

---

## Part D — Gaps, contradictions and reconstructions

| Item | Status |
|---|---|
| `PH2_PHY_PLL` vendor parameter table | **MISSING from `Device-Primitive`.** Documented (UG1110 §43 p.100) and present as `sim_release\ph2\ph2_phy_pll.v`, but a full-tree grep finds **no `PH2_PHY_PLL` block anywhere**; `PH2A\Clock\ph2a_clock.v` carries only `PH2_PHY_DPLL` and `PH2_PHY_OSCDIV`. Do not invent its parameter names. |
| `PH2_PHY_OSC` | Sim model exists; **not** in `PH2A\Clock\ph2a_clock.v` (only `PH2_PHY_OSCDIV`). |
| `GSR` / `STARTUP` user primitive | **Does not exist.** GSR is a parameter (`"ENABLE"`/`"DISABLE"`); `*_PHY_GSR` are zero-port simulation-only cells; EF2/EF3/EF4/EG4/SF1 designs use the zero-port `glbl` model. |
| `DR1\Config\dr1_config.v` | **Incomplete** — lists only `DR1_LOGIC_DNA`; `sim_release\dr1\dr1_logic_config.v` also declares `DR1_LOGIC_GSRN`, `DR1_LOGIC_ECC`, `DR1_LOGIC_GCTRL`. |
| `EF4\I,O\ef4_i_o.v` | Mislabels `EF4_PHY_INTFLASH` (a Config/Flash primitive under I/O) — generation artefact, not a real I/O primitive. |
| Template completeness generally | `Device-Primitive\*.v` files declare only a container module; real primitive names live in header comments. Treat them as the best annotated **parameter** source, and cross-check `sim_release\<family>\` for the authoritative module/port list. |
| `EF4` simulation library | In the dropdown and on disk, **absent from 表4-1**. |
| `PH1P`, `DR1`, `SF2` simulation libraries | On disk, **absent from 表4-1 and from the dropdown sentence**. The doc defers to the live UI. |
| IPUG028 §3.9.3 vs §3.2 | **Self-contradict** on the polarity of `Generate PCIe Without HXT`. Unresolved. |
| `[RECONSTRUCTED]` items | IPUG028/IPUG160 表4-1 (PCIe-signal ↔ primitive-signal rows interleaved); IPUG010/IPUG014 表2-10/2-11 (备注 column drift). |
| No IPUG for | MIPI, RISC-V/MCU, temperature sensor, oscillator, ADC, PLL — these exist only as primitives (Part A.2). EF2/EF3/EF4/EG4/SF1/SF2 have **no** Libraries Guide in this doc set; their primitive names above come from the installed templates and models. |
