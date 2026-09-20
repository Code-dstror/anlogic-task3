param(
    [string]$Netlist,
    [string]$Sdf,
    [string]$ModelSimBin = $env:MODELSIM_BIN,
    [string]$TdRoot = $env:TD_ROOT
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $PSScriptRoot "tool_paths.ps1")
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$tdRoot = Resolve-TdRoot -PreferredPath $TdRoot -RequirePh1SimulationModels
$simRelease = Join-Path $tdRoot "sim_release"
$workDir = Join-Path $repo "tmp\modelsim\postroute"
$tb = Join-Path $repo "fpga_rtl\tb\tb_pcie_c2h_postroute.v"

if (-not $Netlist) { $Netlist = Join-Path $repo "tmp\td_reports\pcie_c2h_post_route.v" }
if (-not $Sdf) { $Sdf = Join-Path $repo "tmp\td_reports\pcie_c2h_post_route.sdf" }
foreach ($path in @($Netlist, $Sdf, $tb)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing simulation input: $path" }
}
$Netlist = (Resolve-Path -LiteralPath $Netlist).Path
$Sdf = (Resolve-Path -LiteralPath $Sdf).Path

$commonV = @((Join-Path $simRelease "common\al_phy_glbl.v"))
$ph1V = @(
    (Join-Path $simRelease "ph1\ph1_logic_io.v"),
    (Join-Path $simRelease "ph1\ph1_phy_dramhardcon.v"),
    (Join-Path $simRelease "ph1\ph1_phy_eram.v"),
    (Join-Path $simRelease "ph1\ph1_phy_f78mux.v"),
    (Join-Path $simRelease "ph1\ph1_phy_gclk_v2.v"),
    (Join-Path $simRelease "ph1\ph1_phy_gsr.v"),
    (Join-Path $simRelease "ph1\ph1_phy_hr_bankref.v"),
    (Join-Path $simRelease "ph1\ph1_phy_lslice.v"),
    (Join-Path $simRelease "ph1\ph1_phy_mslice.v"),
    (Join-Path $simRelease "ph1\ph1_phy_pad.v"),
    (Join-Path $simRelease "ph1\ph1_phy_pll.v"),
    (Join-Path $simRelease "ph1\ph1_phy_sclk_v2.v")
)
$ph1Sv = @(
    (Join-Path $simRelease "ph1\ph1_phy_config_v2.sv"),
    (Join-Path $simRelease "ph1\ph1_phy_pcie_v3.sv")
)

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Push-Location $workDir
try {
    if (Test-Path -LiteralPath "work") { Remove-Item -LiteralPath "work" -Recurse -Force }
    & "$modelsim\vlib.exe" work
    if ($LASTEXITCODE -ne 0) { throw "vlib failed" }
    & "$modelsim\vmap.exe" work work | Out-Null

    & "$modelsim\vlog.exe" -work work -timescale 1ns/1ps @commonV @ph1V
    if ($LASTEXITCODE -ne 0) { throw "TD Verilog library compile failed" }
    & "$modelsim\vlog.exe" -work work -timescale 1ns/1ps -sv @ph1Sv
    if ($LASTEXITCODE -ne 0) { throw "TD SystemVerilog library compile failed" }
    & "$modelsim\vlog.exe" -work work -timescale 1ns/1ps $Netlist $tb
    if ($LASTEXITCODE -ne 0) { throw "routed netlist compile failed" }

    $vendorWarningSuppressions = "2685,2718,2958"
    & "$modelsim\vsim.exe" -c -work work -suppress $vendorWarningSuppressions `
        tb_pcie_c2h_postroute `
        -l postroute_functional.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "post-route functional simulation failed" }
    # TD 6.2.1 emits eight PCIe-hard-IP IOPATH/SETUPHOLD records that the
    # matching PH1 V3 protected model does not expose as specify paths.
    # -sdfnoerror keeps those vendor-model mismatches as visible warnings while
    # allowing all matching routed delays to be annotated and simulated.
    & "$modelsim\vsim.exe" -c -work work -sdfnoerror `
        -suppress "$vendorWarningSuppressions,3448,8756" `
        -sdftyp "/tb_pcie_c2h_postroute/u_dut=$Sdf" tb_pcie_c2h_postroute `
        -l postroute_sdf.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "post-route SDF simulation failed" }

    foreach ($log in @("postroute_functional.log", "postroute_sdf.log")) {
        $content = Get-Content -LiteralPath $log -Raw
        if ($content -notmatch "RESULT: PASS" -or $content -match "\*\* Error") {
            throw "Post-route self-check failed: $log"
        }
    }
    Write-Output "[ModelSim/TD routed SDF] RESULT: PASS"
} finally {
    Pop-Location
}
