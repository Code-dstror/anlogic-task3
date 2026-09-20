param(
    [string]$ModelSimBin = "D:/App/modelsim/win64",
    [string]$TdRoot = "E:/APP/Anlogic/TD_6.2.1_Engineer_6.2.168.116"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$runDir = Join-Path $repo "tmp/modelsim/csi2_fifo"

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    if (-not (Test-Path "ph1")) { & "$ModelSimBin/vlib.exe" ph1 }
    & "$ModelSimBin/vmap.exe" ph1 ph1 | Out-Null
    $ph1Models = @(
        "$TdRoot/sim_release/common/al_phy_glbl.v",
        "$TdRoot/sim_release/ph1/ph1_logic_eram.v",
        "$TdRoot/sim_release/ph1/ph1_logic_fifo.v",
        "$TdRoot/sim_release/ph1/ph1_logic_ramfifo.v",
        "$TdRoot/sim_release/ph1/ph1_phy_eram.v",
        "$TdRoot/sim_release/ph1/ph1_phy_fifoctrl.v"
    )
    & "$ModelSimBin/vlog.exe" -work ph1 @ph1Models
    if ($LASTEXITCODE -ne 0) { throw "PH1 FIFO model compilation failed" }

    if (-not (Test-Path "work")) { & "$ModelSimBin/vlib.exe" work }
    & "$ModelSimBin/vmap.exe" work work | Out-Null
    & "$ModelSimBin/vlog.exe" -work work "+define+PH1" `
        (Join-Path $repo "fpga_rtl/vendor/anlogic_soft_fifo_3_0/Soft_FIFO/RTL/soft_fifo.v") `
        (Join-Path $repo "fpga_rtl/camera/csi/csi2_async_event_fifo.v") `
        (Join-Path $repo "fpga_rtl/camera/csi/csi2_raw10_word_core.v") `
        (Join-Path $repo "fpga_rtl/camera/csi/csi2_raw10_rx_stream.v") `
        (Join-Path $repo "fpga_rtl/tb/tb_csi2_receiver_fifo.v")
    if ($LASTEXITCODE -ne 0) { throw "CSI-2 FIFO receiver compilation failed" }

    & "$ModelSimBin/vsim.exe" -c -L ph1 work.tb_csi2_receiver_fifo `
        -l csi2_fifo.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "CSI-2 FIFO receiver simulation failed" }
    $log = Get-Content -LiteralPath "csi2_fifo.log" -Raw
    if ($log -notmatch "\[TB\] RESULT: PASS" -or $log -match "\[TB\] RESULT: FAIL") {
        throw "CSI-2 FIFO receiver self-check failed; inspect $runDir/csi2_fifo.log"
    }
    Write-Output "[ModelSim CSI-2 receiver with TD PH1 Soft FIFO] RESULT: PASS"
} finally {
    Pop-Location
}
