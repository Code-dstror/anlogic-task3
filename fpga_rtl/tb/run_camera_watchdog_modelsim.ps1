param(
    [string]$ModelSimBin = $env:MODELSIM_BIN
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $PSScriptRoot "tool_paths.ps1")
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$runDir = Join-Path $repo "tmp\modelsim\camera_watchdog"
$workLib = Join-Path $runDir "work"
$compileLog = Join-Path $runDir "compile.log"
$runLog = Join-Path $runDir "run.log"
$rtl = @(
    (Join-Path $repo "fpga_rtl\camera\imx415_camera_axis.v"),
    (Join-Path $repo "fpga_rtl\tb\tb_camera_watchdog.v")
)

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    if (-not (Test-Path -LiteralPath $workLib)) {
        & "$modelsim\vlib.exe" $workLib
        if ($LASTEXITCODE -ne 0) { throw "watchdog vlib failed" }
    }
    & "$modelsim\vmap.exe" work $workLib | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "watchdog vmap failed" }
    & "$modelsim\vlog.exe" -work $workLib -timescale 1ns/1ps `
        -l $compileLog @rtl
    if ($LASTEXITCODE -ne 0) { throw "watchdog vlog failed" }
    $compileContent = Get-Content -LiteralPath $compileLog -Raw
    if ($compileContent -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
        throw "watchdog compile log contains errors: $compileLog"
    }

    & "$modelsim\vsim.exe" -c -work work tb_camera_watchdog `
        -l $runLog -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "watchdog simulation failed to run" }
    $content = Get-Content -LiteralPath $runLog -Raw
    if ($content -notmatch "\[TB\] RESULT: PASS" -or
        $content -match "\[TB\] RESULT: FAIL" -or
        $content -match "\[TB\] ERROR" -or
        $content -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
        throw "watchdog self-check failed: $runLog"
    }
    Write-Output "[ModelSim camera watchdog] RESULT: PASS"
} finally {
    Pop-Location
}
