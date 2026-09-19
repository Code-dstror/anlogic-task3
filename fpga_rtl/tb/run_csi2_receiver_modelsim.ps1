param([string]$ModelSimBin = "D:/App/modelsim/win64")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$runDir = Join-Path $repo "tmp/modelsim/csi2_receiver"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    if (-not (Test-Path work)) { & "$ModelSimBin/vlib.exe" work }
    & "$ModelSimBin/vmap.exe" work work | Out-Null
    & "$ModelSimBin/vlog.exe" -work work `
        (Join-Path $repo "fpga_rtl/camera/csi/csi2_raw10_word_core.v") `
        (Join-Path $repo "fpga_rtl/tb/tb_csi2_raw10_word_core.v")
    if ($LASTEXITCODE -ne 0) { throw "CSI-2 receiver compile failed" }
    & "$ModelSimBin/vsim.exe" -c work.tb_csi2_raw10_word_core `
        -l csi2_receiver.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "CSI-2 receiver simulation failed" }
    $log = Get-Content csi2_receiver.log -Raw
    if ($log -notmatch "\[TB\] RESULT: PASS" -or $log -match "\[TB\] RESULT: FAIL") {
        throw "CSI-2 receiver self-check failed"
    }
    Write-Output "[ModelSim CSI-2 receiver] RESULT: PASS"
} finally { Pop-Location }
