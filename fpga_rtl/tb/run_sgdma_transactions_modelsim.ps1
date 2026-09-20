param(
    [string]$ModelSimBin = $env:MODELSIM_BIN,
    [string]$OutputDir = "tmp/modelsim/sgdma_transactions"
)

$ErrorActionPreference = "Stop"
$toolPaths = Join-Path $PSScriptRoot "tool_paths.ps1"
. $toolPaths
$ModelSimBin = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$out = Join-Path $repo $OutputDir
New-Item -ItemType Directory -Force $out | Out-Null
$work = Join-Path $out "work"
$enc = Join-Path $repo "fpga_rtl/vendor/anlogic_pcie_sgdma/sgdma/src_enc/sgdma_ip_all.enc.v"
$tb = Join-Path $repo "fpga_rtl/tb/tb_sgdma_transactions.v"
Push-Location $out
try {
    if (-not (Test-Path $work)) { & (Join-Path $ModelSimBin "vlib.exe") $work }
    & (Join-Path $ModelSimBin "vmap.exe") work $work | Out-Null
    $compileLog = Join-Path $out "compile.log"
    & (Join-Path $ModelSimBin "vlog.exe") -work work $enc $tb 2>&1 | Tee-Object -FilePath $compileLog
    if ($LASTEXITCODE -ne 0) { throw "vlog failed: $LASTEXITCODE" }
    $log = Join-Path $out "sgdma_transactions.log"
    & (Join-Path $ModelSimBin "vsim.exe") -c -lib work tb_sgdma_transactions -do "run -all; quit -f" -l $log
    if ($LASTEXITCODE -ne 0) { throw "vsim failed: $LASTEXITCODE" }
    $text = Get-Content -Raw $log
    if (($text -match "FAIL:|ERROR:") -or
        ($text -notmatch "PASS: encrypted SGDMA CQ/CC, descriptor fetch, C2H payload and writeback")) {
        throw "simulation did not pass; inspect $log"
    }
    Write-Host "PASS: $log"
} finally {
    Pop-Location
}
