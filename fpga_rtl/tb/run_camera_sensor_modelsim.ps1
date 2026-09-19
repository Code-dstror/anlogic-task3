param(
    [string]$ModelSimBin = $env:MODELSIM_BIN
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $PSScriptRoot "tool_paths.ps1")
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$workDir = Join-Path $repo "tmp\modelsim\camera_sensor"

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Push-Location $workDir
try {
    if (-not (Test-Path "work")) {
        & "$modelsim\vlib.exe" work
    }
    & "$modelsim\vmap.exe" work work | Out-Null
    & "$modelsim\vlog.exe" -work work -timescale 1ns/1ps -l compile.log `
        (Join-Path $repo "fpga_rtl\vendor\anlogic_camera\sensor\ui_imx415_reg.v") `
        (Join-Path $repo "fpga_rtl\camera\sensor\camera_i2c_write.v") `
        (Join-Path $repo "fpga_rtl\camera\sensor\imx415_mode_table.v") `
        (Join-Path $repo "fpga_rtl\camera\sensor\imx415_config.v") `
        (Join-Path $repo "fpga_rtl\tb\tb_camera_sensor.v")
    if ($LASTEXITCODE -ne 0) { throw "ModelSim vlog failed" }
    $compileContent = Get-Content -LiteralPath "compile.log" -Raw
    if ($compileContent -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
        throw "Camera sensor compile log contains errors: $workDir\compile.log"
    }

    & "$modelsim\vsim.exe" -c -work work tb_camera_sensor `
        -l camera_sensor.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "Camera sensor simulation failed to run" }
    $content = Get-Content -LiteralPath "camera_sensor.log" -Raw
    if ($content -notmatch "RESULT: PASS" -or
        $content -match "\[TB\] ERROR" -or
        $content -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
        throw "Camera sensor self-check failed: $workDir\camera_sensor.log"
    }
    Write-Output "[ModelSim] RESULT: PASS"
} finally {
    Pop-Location
}
