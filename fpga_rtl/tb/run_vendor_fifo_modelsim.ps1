param(
    [string]$ModelSimBin = $env:MODELSIM_BIN,
    [string]$TdRoot = $env:TD_ROOT
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $PSScriptRoot "tool_paths.ps1")
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$tdRoot = Resolve-TdRoot -PreferredPath $TdRoot -RequirePh1SimulationModels
$workDir = Join-Path $repo "tmp\modelsim\vendor_fifo"

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Push-Location $workDir
try {
    if (-not (Test-Path "ph1")) {
        & "$modelsim\vlib.exe" ph1
    }
    & "$modelsim\vmap.exe" ph1 ph1 | Out-Null

    $ph1FifoModels = @(
        "$tdRoot\sim_release\common\al_phy_glbl.v",
        "$tdRoot\sim_release\ph1\ph1_logic_eram.v",
        "$tdRoot\sim_release\ph1\ph1_logic_fifo.v",
        "$tdRoot\sim_release\ph1\ph1_logic_ramfifo.v",
        "$tdRoot\sim_release\ph1\ph1_phy_eram.v",
        "$tdRoot\sim_release\ph1\ph1_phy_fifoctrl.v"
    )
    & "$modelsim\vlog.exe" -work ph1 @ph1FifoModels
    if ($LASTEXITCODE -ne 0) { throw "PH1 FIFO model compilation failed" }

    if (-not (Test-Path "work")) {
        & "$modelsim\vlib.exe" work
    }
    & "$modelsim\vmap.exe" work work | Out-Null
    & "$modelsim\vlog.exe" -work work "+define+PH1" `
        (Join-Path $repo "fpga_rtl\vendor\anlogic_soft_fifo_3_0\Soft_FIFO\RTL\soft_fifo.v") `
        (Join-Path $repo "fpga_rtl\pcie\axis_frame_fifo_ip.v") `
        (Join-Path $repo "fpga_rtl\tb\tb_axis_frame_fifo_ip.v")
    if ($LASTEXITCODE -ne 0) { throw "Soft FIFO wrapper compilation failed" }

    & "$modelsim\vsim.exe" -c -L ph1 work.tb_axis_frame_fifo_ip `
        -l axis_frame_fifo_ip.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "Soft FIFO simulation failed to run" }

    $log = Get-Content -LiteralPath "axis_frame_fifo_ip.log" -Raw
    if ($log -notmatch "\[TB\] RESULT: PASS" -or
        $log -match "\[TB\] RESULT: FAIL") {
        throw "Soft FIFO self-check failed"
    }
    Write-Output "[ModelSim/TD PH1 Soft FIFO] RESULT: PASS"
} finally {
    Pop-Location
}
