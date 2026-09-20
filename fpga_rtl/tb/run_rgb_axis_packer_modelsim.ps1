param(
    [string]$ModelSimBin = $env:MODELSIM_BIN
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $PSScriptRoot "tool_paths.ps1")
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$workDir = Join-Path $repo "tmp\modelsim\rgb_axis_packer"

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Push-Location $workDir
try {
    if (-not (Test-Path "work")) {
        & "$modelsim\vlib.exe" work
    }
    & "$modelsim\vmap.exe" work work | Out-Null
    & "$modelsim\vlog.exe" -work work -timescale 1ns/1ps -l compile.log `
        (Join-Path $repo "fpga_rtl\camera\rgb_axis_packer.v") `
        (Join-Path $repo "fpga_rtl\tb\tb_rgb_axis_packer.v")
    if ($LASTEXITCODE -ne 0) { throw "ModelSim vlog failed" }
    $compileContent = Get-Content -LiteralPath "compile.log" -Raw
    if ($compileContent -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
        throw "RGB packer compile log contains errors: $workDir\compile.log"
    }

    & "$modelsim\vsim.exe" -c -work work tb_rgb_axis_packer `
        -l rgb_axis_packer.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "RGB packer simulation failed to run" }
    $content = Get-Content -LiteralPath "rgb_axis_packer.log" -Raw
    if ($content -notmatch "RESULT: PASS" -or
        $content -match "\[TB\] ERROR" -or
        $content -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
        throw "RGB packer self-check failed: $workDir\rgb_axis_packer.log"
    }
    Write-Output "[ModelSim] RESULT: PASS"
} finally {
    Pop-Location
}
