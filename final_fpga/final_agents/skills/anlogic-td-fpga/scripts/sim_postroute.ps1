#=============================================================================
# Simulate an Anlogic TD post-route netlist with ModelSim, functionally and
# with SDF timing annotation.
#
# Usage:
#   $env:TD_ROOT = "C:/Tools/Anlogic/TD_6.2.168116"   # optional
#   .\sim_postroute.ps1 -Netlist <path>\post_route.v `
#                       -Sdf     <path>\post_route.sdf `
#                       -Tb      <path>\tb_postroute.v `
#                       -TopTb   postroute_tb `
#                       -DutPath /postroute_tb/dut `
#                       -WorkDir <scratch dir>
#
# The netlist and SDF come from TD (see references/simulation.md):
#     open_run phy_1
#     write_verilog <path>\post_route.v
#     write_sdf     -file <path>\post_route.sdf
#
# Only the PH1 device models actually instantiated by a LOGIC netlist are
# compiled. SerDes/DDR/PCIe/DSP designs need additional sim_release files.
#=============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Netlist,
    [Parameter(Mandatory = $true)][string]$Sdf,
    [Parameter(Mandatory = $true)][string]$Tb,
    [string]$TopTb   = "postroute_tb",
    [string]$DutPath = "/postroute_tb/dut",
    [string]$Family  = "ph1",
    [string]$WorkDir = ".\sim_postroute",
    [string]$TdRoot  = $env:TD_ROOT,
    [string]$ModelSim = $env:MODELSIM_BIN
)

$ErrorActionPreference = "Stop"

# --- locate TD ---------------------------------------------------------------
if (-not $TdRoot) {
    $candidates = @()
    foreach ($d in (Get-PSDrive -PSProvider FileSystem).Root) {
        $candidates += Get-ChildItem -Path $d -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName "bin\td_commands_prompt.exe") }
    }
    if ($candidates.Count -eq 0) { throw "Cannot find the TD install. Pass -TdRoot." }
    $TdRoot = $candidates[0].FullName
}
$simRel = Join-Path $TdRoot "sim_release"
if (-not (Test-Path $simRel)) { throw "No sim_release under $TdRoot" }
Write-Host "TD_ROOT = $TdRoot"

foreach ($f in @($Netlist, $Sdf, $Tb)) {
    if (-not (Test-Path $f)) { throw "Missing file: $f" }
}
# Resolve to absolute paths BEFORE changing directory below.
$Netlist = (Resolve-Path $Netlist).Path
$Tb      = (Resolve-Path $Tb).Path
$Sdf     = (Resolve-Path $Sdf).Path
if ((Get-Item $Sdf).Length -eq 0) {
    throw "SDF is 0 bytes. write_sdf only works with the ROUTED run (phy_1) open."
}
if (-not [System.IO.Path]::IsPathRooted($WorkDir)) {
    $WorkDir = Join-Path (Get-Location).Path $WorkDir
}

$vlib = Join-Path $ModelSim "vlib.exe"
$vlog = Join-Path $ModelSim "vlog.exe"
$vsim = Join-Path $ModelSim "vsim.exe"
foreach ($e in @($vlib, $vlog, $vsim)) {
    if (-not (Test-Path $e)) { throw "ModelSim executable not found: $e" }
}

# --- minimal PH1 logic model set (verified; see references/simulation.md) ----
$models = @(
    (Join-Path $simRel "common\al_phy_glbl.v"),
    (Join-Path $simRel "$Family\ph1_phy_lslice.v"),
    (Join-Path $simRel "$Family\ph1_phy_pad.v"),
    (Join-Path $simRel "$Family\ph1_phy_gclk_v2.v"),
    (Join-Path $simRel "$Family\ph1_phy_sclk_v2.v"),
    (Join-Path $simRel "$Family\ph1_phy_hr_bankref.v"),
    (Join-Path $simRel "$Family\ph1_logic_io.v"),
    (Join-Path $simRel "$Family\ph1_phy_gsr.v")
)
$svModels = @( (Join-Path $simRel "$Family\ph1_phy_config_v2.sv") )

$missing = @($models + $svModels) | Where-Object { -not (Test-Path $_) }
if ($missing) {
    Write-Warning "These model files were not found (a different family may need different names):"
    $missing | ForEach-Object { Write-Warning "  $_" }
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Push-Location $WorkDir
try {
    Write-Host "`n=== vlib/vmap ==="
    & $vlib work | Out-Null
    & (Join-Path $ModelSim "vmap.exe") work work | Out-Null

    Write-Host "=== vlog: device models ==="
    $have = @($models | Where-Object { Test-Path $_ })
    if ($have.Count) { & $vlog -timescale 1ns/1ps -incr @have }
    # ph1_phy_config_v2.sv must be compiled with -sv
    $svHave = @($svModels | Where-Object { Test-Path $_ })
    if ($svHave.Count) { & $vlog -timescale 1ns/1ps -incr -sv @svHave }

    Write-Host "=== vlog: netlist + testbench ==="
    & $vlog -timescale 1ns/1ps -incr $Netlist $Tb

    Write-Host "`n=== vsim: functional ==="
    & $vsim -c -l functional.log -do "run -all; quit -f" work.$TopTb

    Write-Host "`n=== vsim: timing (SDF annotated) ==="
    & $vsim -c -sdftyp "$DutPath=$Sdf" `
            -l timing.log -do "run -all; quit -f" work.$TopTb

    Write-Host "`n=== verdict (grep for RESULT:/Errors:) ==="
    foreach ($lg in @("functional.log", "timing.log")) {
        if (Test-Path $lg) {
            Write-Host "--- $lg"
            Select-String -Path $lg -Pattern "RESULT:|Errors:|Loading timing data" |
                ForEach-Object { $_.Line }
        }
    }
}
finally {
    Pop-Location
}
