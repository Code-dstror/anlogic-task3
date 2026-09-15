param(
    [switch]$MaxCases,
    [string]$ModelSimBin = $env:MODELSIM_BIN
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $PSScriptRoot "tool_paths.ps1")
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$workDir = Join-Path $repo "tmp\modelsim\rtl"
$includeDir = Join-Path $repo "fpga_rtl\include"

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Push-Location $workDir
try {
    if (-not (Test-Path "work")) {
        & "$modelsim\vlib.exe" work
    }
    & "$modelsim\vmap.exe" work work | Out-Null
    & "$modelsim\vlog.exe" -work work -timescale 1ns/1ps "+incdir+$includeDir" `
        (Join-Path $repo "fpga_rtl\pcie\c2h_test_source.v") `
        (Join-Path $repo "fpga_rtl\pcie\c2h_frame_tx.v") `
        (Join-Path $repo "fpga_rtl\pcie\pcie_app_regs.v") `
        (Join-Path $repo "fpga_rtl\pcie\h2c_stream_checker.v") `
        (Join-Path $repo "fpga_rtl\pcie\pcie_inband_header_adapter.v") `
        (Join-Path $repo "fpga_rtl\tb\tb_c2h_transport.v") `
        (Join-Path $repo "fpga_rtl\tb\tb_pcie_inband_transport.v") `
        (Join-Path $repo "fpga_rtl\tb\tb_pcie_app_regs.v") `
        (Join-Path $repo "fpga_rtl\tb\tb_h2c_stream_checker.v")
    if ($LASTEXITCODE -ne 0) { throw "ModelSim vlog failed" }

    $plusArgs = @()
    if ($MaxCases) { $plusArgs += "+MAX_CASES" }
    & "$modelsim\vsim.exe" -c -work work tb_c2h_transport @plusArgs `
        -l c2h_transport.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "C2H simulation failed to run" }
    & "$modelsim\vsim.exe" -c -work work tb_pcie_inband_transport @plusArgs `
        -l pcie_inband_transport.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "In-band transport simulation failed to run" }
    & "$modelsim\vsim.exe" -c -work work tb_pcie_app_regs `
        -l pcie_app_regs.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "AXI4-Lite simulation failed to run" }
    & "$modelsim\vsim.exe" -c -work work tb_h2c_stream_checker `
        -l h2c_stream_checker.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "H2C checker simulation failed to run" }

    $logs = @("c2h_transport.log", "pcie_inband_transport.log", "pcie_app_regs.log", "h2c_stream_checker.log")
    foreach ($log in $logs) {
        $content = Get-Content -LiteralPath $log -Raw
        if ($content -notmatch "RESULT: PASS" -or
            $content -match "\[TB\] ERROR" -or
            $content -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
            throw "Self-check failed: $log"
        }
    }
    Write-Output "[ModelSim] RESULT: PASS"
} finally {
    Pop-Location
}
