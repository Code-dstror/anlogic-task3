param(
    [string]$ModelSimBin = $env:MODELSIM_BIN
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $PSScriptRoot "tool_paths.ps1")
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$workDir = Join-Path $repo "tmp\modelsim\video_transport"
$includeDir = Join-Path $repo "fpga_rtl\include"

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Push-Location $workDir
try {
    if (-not (Test-Path "work")) {
        & "$modelsim\vlib.exe" work
    }
    & "$modelsim\vmap.exe" work work | Out-Null
    & "$modelsim\vlog.exe" -work work -timescale 1ns/1ps -l compile.log "+incdir+$includeDir" `
        (Join-Path $repo "fpga_rtl\tb\stubs\pcie_sgdma_endpoint.v") `
        (Join-Path $repo "fpga_rtl\pcie\pcie_inband_header_adapter.v") `
        (Join-Path $repo "fpga_rtl\pcie\c2h_frame_tx.v") `
        (Join-Path $repo "fpga_rtl\pcie\pcie_video_transport.v") `
        (Join-Path $repo "fpga_rtl\tb\tb_pcie_video_transport.v")
    if ($LASTEXITCODE -ne 0) { throw "ModelSim vlog failed" }
    $compileContent = Get-Content -LiteralPath "compile.log" -Raw
    if ($compileContent -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
        throw "Video transport compile log contains ModelSim errors: $workDir\compile.log"
    }

    & "$modelsim\vsim.exe" -c -work work tb_pcie_video_transport `
        -l pcie_video_transport.log -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "Video transport simulation failed to run" }

    $content = Get-Content -LiteralPath "pcie_video_transport.log" -Raw
    if ($content -notmatch "RESULT: PASS" -or
        $content -match "\[TB\] ERROR" -or
        $content -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
        throw "Video transport self-check failed: $workDir\pcie_video_transport.log"
    }
    Write-Output "[ModelSim] RESULT: PASS"
    Write-Output "[ModelSim] NOTE: simulation-only endpoint double; no vendor PCIe/SGDMA functional proof"
} finally {
    Pop-Location
}
