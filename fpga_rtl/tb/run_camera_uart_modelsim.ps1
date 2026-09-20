param(
    [string]$ModelSimBin = $env:MODELSIM_BIN
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $PSScriptRoot "tool_paths.ps1")
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$workDir = Join-Path $repo "tmp\modelsim\camera_uart"
$workLib = Join-Path $workDir "work"
$compileLog = Join-Path $workDir "compile.log"
$runLog = Join-Path $workDir "run.log"

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Push-Location $workDir
try {
    if (-not (Test-Path -LiteralPath $workLib)) {
        & "$modelsim\vlib.exe" $workLib
    }
    & "$modelsim\vmap.exe" work $workLib | Out-Null
    & "$modelsim\vlog.exe" -work $workLib -timescale 1ns/1ps -l $compileLog `
        (Join-Path $repo "fpga_rtl\camera\camera_uart_status.v") `
        (Join-Path $repo "fpga_rtl\tb\tb_camera_uart_status.v")
    if ($LASTEXITCODE -ne 0) { throw "Camera UART vlog failed" }
    & "$modelsim\vsim.exe" -c -work work tb_camera_uart_status -l $runLog `
        -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "Camera UART simulation failed to run" }
    $content = Get-Content -LiteralPath $runLog -Raw
    if ($content -notmatch "RESULT: PASS" -or $content -match "RESULT: FAIL" -or
        $content -match "\[TB\] ERROR" -or
        $content -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
        throw "Camera UART self-check failed: $runLog"
    }
    Write-Output "[ModelSim] RESULT: PASS"
} finally {
    Pop-Location
}
