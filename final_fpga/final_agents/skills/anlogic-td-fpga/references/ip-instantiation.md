# IP instantiation — scriptable via `.ipc`

**Bottom line: you do not need the GUI `IpTool.exe` to instantiate an IP.** The
artifact TD actually consumes is a small XML file, `<ip_name>.ipc`. `add_files`
accepts it directly, and because it is plain XML you can write it yourself.

This matters because `<TD_ROOT>\ip\` (28 directories) is **not** ready-to-use HDL
— it holds encrypted blobs (`uart/uart.enc.dat`), encrypted RTL
(`ddr/*_enc.sv`), generator scripts (`ph2a/fifo.tcl`, 125 KB) and
IPC-generator inputs (`serdes/Component.xml`, `Dependency.tcl`). Configuring a
complex IP (SerDes, DDR, PCIe) is GUI-only. But *instantiating* a configured IP,
and hand-authoring the simple ones (PLL, ECC, DNA), is fully scriptable.

## Verified workflow

```tcl
create_project ipcdemo $OUT -family ph1 -device PH1A60GEG324 -speed 3
open_project $OUT/ipcdemo.al
top_module top

add_files E:/path/to/ecc_once.ipc      ;# -> PRJ-1202 : Add files success.  rc=0
```

The `.al` then carries a dedicated FileSet — proof the IP was *registered*, not
merely remembered as a path:

```xml
<IP_FILE>
    <File Path="../../path/to/al_ip/ecc_once.ipc">
    </File>
</IP_FILE>
```

`add_dir` collects `.ipc` too (`PRJ-1201 : Add File .../ecc_once.ipc`), matching
SWUG105's note that it picks up `.v/.vhd/.vhdl/.sv/.ipc`.

**Do not also add the generated `.v`.** Once an `.ipc` is registered, adding the
HDL it generates fails with
`PRJ-9201 ERROR: ... already exists in IP .../ecc_once.ipc`. The `.ipc` *is* the
registration; the `.v` comes along with it.

## `.ipc` format

Plain XML, UTF-8. Two real shipped examples to model from:

- `<TD_ROOT>\board_designs\ANLOGIC\AP102\SEU_AP102\prj\SEU_EXAMPLE_AP102\al_ip\ecc_once.ipc` (401 B)
- `<TD_ROOT>\board_designs\ANLOGIC\AP102\DNA_AP102\prj\DNA_EXAMPLE_AP102\al_ip\PLL.ipc` (1651 B)

ECC (minimal case — a whole IP in 15 lines):

```xml
<?xml version='1.0' encoding='UTF-8'?>
<ECCConfig>
    <GeneralConfig>
        <Device>PH1A180SFG676</Device>
        <IP_ID>59</IP_ID>
        <Type>PH1_ECC_ONCE</Type>
        <Version>1.0</Version>
        <create_VHDL>false</create_VHDL>
        <inst>ecc_once</inst>
    </GeneralConfig>
    <GeneratedFiles>
        <Verilog Enable="true">ecc_once.v</Verilog>
    </GeneratedFiles>
</ECCConfig>
```

PLL (a real configuration — note the three `Page` blocks that mirror the GUI tabs):

```xml
<?xml version='1.0' encoding='utf-8'?>
<PLLConfig version="1.0">
    <GeneralConfig>
        <Type>PLL</Type>
        <Device>PH1A180SFG676</Device>
        <create_VHDL>true</create_VHDL>
    </GeneralConfig>
    <Page1>
        <speed_grade>Any</speed_grade>
        <input_frequency>25.0000000000000000MHz</input_frequency>
        <feedback_mode>Normal</feedback_mode>
        <clk_num>CLKC0</clk_num>
        <power_down_up>DISABLE</power_down_up>
        <ssc_enable>DISABLE</ssc_enable>
        <enable_reset>ENABLE</enable_reset>
        <pll_lock>ENABLE</pll_lock>
    </Page1>
    <Page2>
        <bandwidth_setting>Medium</bandwidth_setting>
    </Page2>
    <Page3>
        <setting>frequncy_setting</setting>
        <multiplication_factor>1</multiplication_factor>
        <division_factor>2</division_factor>
        <clocks>
            <clock>
                <id>0</id>
                <clock_division_factor>80</clock_division_factor>
                <clock_frequency>12.5000000000000000MHz</clock_frequency>
                <phase_shift>0.0000000000000000deg</phase_shift>
                <duty_cycle>0.5</duty_cycle>
                <clkB>false</clkB>
                <clkEN>false</clkEN>
                <bufg_option>BUFG</bufg_option>
            </clock>
        </clocks>
    </Page3>
</PLLConfig>
```

Key fields: `<Device>` must match your target, `<Type>` selects the IP, `<inst>`
names the generated instance, and `<GeneratedFiles>` declares which HDL outputs
to emit. Note the shipped examples target `PH1A180SFG676` — change `<Device>` to
your part before use.

**Pragmatic approach:** rather than hand-writing a `.ipc` for a complex IP
(SerDes/DDR/PCIe — deep GUI-driven parameter trees, hundreds of fields),
configure it once in `IpTool.exe`, then reuse the generated `.ipc` as a template
and version it with your design. Only the simple IPs (PLL, ECC, DNA) are worth
hand-authoring.

## Companion IP commands (all real, in the main TD shell)

| Command | Use |
|---|---|
| `read_ip_adc -ip <ip> -file <adc>` | per-IP pin/location constraints |
| `read_sdc -ip <ip> <sdc>` | per-IP timing constraints |
| `export_ip_sdc -module <list> -file <f>` | extract an IP's SDC |
| `set_ip_property` / `print_ip_config` | inspect/modify IP config |
| `report_ip_tree` | list instantiated IPs |
| `export_ip_lib` | export an IP library |

Note the per-IP constraint commands are how you constrain an IP without editing
the top-level `.adc`/`.sdc` — see `timing-constraints.md`.

## What is NOT scriptable

| Tool | Evidence |
|---|---|
| `IpTool.exe` (IP configurator) | no-arg and `--help` both exit 1 with empty output; GUI-only, launched by `td.exe` |
| `mpack.exe` (Module Packager) | rejects `-h`/`-tcl`/`-batch`/`-proj_path`/`-ip_name` with "Unknown option"; `-app_path <dir>` just opens the GUI and hangs |
| `hpfTool.exe` (HPF export) | rejects `-h`/`-app_path`/`-proj_path`; `-tcl`/`-batch` hang. Also **DR1-FPSoC-only** (needs exactly one PS IP), so irrelevant to plain-FPGA families |
| `design_integrator.exe` with no args | hangs (GUI). **But `-h` works and `-batch <tcl>` is genuinely headless** — see below |

## Design Integrator — headless but not yet worth depending on

`design_integrator.exe` is more scriptable than it first appears: `-h` prints a
real CLI, and only the **no-argument** case hangs. Verified headless run:

```powershell
& "$TD\bin\design_integrator.exe" -app_path "$TD" -proj_path "E:\work\dgen" `
    -device PH1A60GEG324 -speed 3 -batch "E:\work\di_gen.tcl"
```

```tcl
# di_gen.tcl  -- arguments are POSITIONAL
si_create_design probeD
si_design_save
si_design_check
si_generate_design
# -> GUI-2000 : The Design Integrator files have been generated successfully
# writes hdl/<name>.v, <name>.xml, <name>.address.xml, <name>.violation
```

Traps, all measured:

- Calling any `si_*` command **without** an initialised context crashes the
  process (access violation, exit `-1073741819`). Always pass
  `-proj_path`/`-device`/`-speed`.
- Arguments are positional: `si_create_design -design_name probe1` created a
  literal directory named `-design_name`.
- Batch stdout is not captured by the console — have the script write its own file.
- Only ~105 of its 177 TCL commands are real; 72 are a scripted-GUI harness
  (`si_click_menu_item`, `si_click_toolbar_item`, `si_graphics_view_zoom`,
  `si_move_splitter`, …).

**Status: deferred.** The empty-design create→generate round trip is verified,
but `si_design_add_inst` / `si_design_add_connection` signatures are
**unestablished**, so scripted designs *containing IPs* are unproven. Do not
build on this without first exporting a working design's TCL from the GUI.
