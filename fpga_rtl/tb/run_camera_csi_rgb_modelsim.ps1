param(
    [string]$ModelSimBin = $env:MODELSIM_BIN,
    [string]$TdRoot = $env:TD_ROOT
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $PSScriptRoot "tool_paths.ps1")
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$td = Resolve-TdRoot -PreferredPath $TdRoot -RequirePh1SimulationModels
$runDir = Join-Path $repo "tmp\modelsim\camera_csi_rgb"
$ph1Lib = Join-Path $runDir "ph1"
$workLib = Join-Path $runDir "work"
$compileLog = Join-Path $runDir "compile.log"
$runLog = Join-Path $runDir "run.log"

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Copy-Item -LiteralPath (Join-Path $repo "fpga_rtl\camera\isp\color\gamma22_10to8.dath") `
    -Destination (Join-Path $runDir "gamma22_10to8.dath") -Force

$ph1Models = @(
    (Join-Path $td "sim_release\common\al_phy_glbl.v"),
    (Join-Path $td "sim_release\ph1\ph1_logic_eram.v"),
    (Join-Path $td "sim_release\ph1\ph1_logic_fifo.v"),
    (Join-Path $td "sim_release\ph1\ph1_logic_ramfifo.v"),
    (Join-Path $td "sim_release\ph1\ph1_phy_eram.v"),
    (Join-Path $td "sim_release\ph1\ph1_phy_fifoctrl.v")
)

$rtl = @(
    (Join-Path $td "sim_release\ph1\ph1_phy_gsr.v"),
    (Join-Path $repo "fpga_rtl\vendor\anlogic_soft_fifo_3_0\Soft_FIFO\RTL\soft_fifo.v"),
    (Join-Path $repo "fpga_rtl\camera\csi\csi2_async_event_fifo.v"),
    (Join-Path $repo "fpga_rtl\camera\csi\csi2_raw10_word_core.v"),
    (Join-Path $repo "fpga_rtl\camera\csi\csi2_raw10_rx_stream.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\isp_line_ram_40x1024.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\raw\raw_blc.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\raw\raw_row_window.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\raw\raw_demosaic.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\raw\raw_isp_top.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\color\gamma_lut_10to8.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\color\color_pipeline_axis.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\isp_core_top.v"),
    (Join-Path $repo "fpga_rtl\camera\camera_raw_crop.v"),
    (Join-Path $repo "fpga_rtl\camera\rgb_axis_packer.v"),
    (Join-Path $repo "fpga_rtl\camera\camera_rgb_pipeline.v"),
    (Join-Path $repo "fpga_rtl\tb\tb_camera_csi_rgb.v")
)

Push-Location $runDir
try {
    if (-not (Test-Path -LiteralPath $ph1Lib)) { & "$modelsim\vlib.exe" $ph1Lib }
    if (-not (Test-Path -LiteralPath $workLib)) { & "$modelsim\vlib.exe" $workLib }
    & "$modelsim\vmap.exe" ph1 $ph1Lib | Out-Null
    & "$modelsim\vmap.exe" work $workLib | Out-Null
    & "$modelsim\vlog.exe" -quiet -work $ph1Lib @ph1Models
    if ($LASTEXITCODE -ne 0) { throw "PH1 model compilation failed" }
    & "$modelsim\vlog.exe" -work $workLib "+define+PH1" -timescale 1ns/1ps `
        -l $compileLog @rtl
    if ($LASTEXITCODE -ne 0) { throw "CSI RGB integration compilation failed" }
    & "$modelsim\vsim.exe" -c -L ph1 -work work PH1_PHY_GSR tb_camera_csi_rgb `
        -l $runLog -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "CSI RGB integration simulation failed" }
    $content = Get-Content -LiteralPath $runLog -Raw
    if ($content -notmatch "\[TB\] RESULT: PASS" -or
        $content -match "\[TB\] RESULT: FAIL" -or
        $content -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
        throw "CSI RGB integration self-check failed: $runLog"
    }
    Write-Output "[ModelSim CSI FIFO to RGB pipeline] RESULT: PASS"
} finally {
    Pop-Location
}
