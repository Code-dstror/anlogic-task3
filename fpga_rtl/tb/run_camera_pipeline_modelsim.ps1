param(
    [string]$ModelSimBin = $env:MODELSIM_BIN,
    [string]$TdRoot = $env:TD_ROOT,
    [ValidateSet("all", "small", "gamma", "linear", "1080p", "4k")]
    [string]$Case = "all"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $PSScriptRoot "tool_paths.ps1")
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$td = Resolve-TdRoot -PreferredPath $TdRoot -RequirePh1SimulationModels
$primitive = Join-Path $td "sim_release\ph1\ph1_logic_eram.v"
$globalReset = Join-Path $td "sim_release\ph1\ph1_phy_gsr.v"

$rtl = @(
    $globalReset,
    $primitive,
    (Join-Path $repo "fpga_rtl\camera\isp\isp_line_ram_40x1024.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\raw\raw_blc.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\raw\raw_row_window.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\raw\raw_demosaic.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\raw\raw_isp_top.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\color\gamma_lut_10to8.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\color\color_pipeline_axis.v"),
    (Join-Path $repo "fpga_rtl\camera\isp\isp_core_top.v"),
    (Join-Path $repo "fpga_rtl\camera\camera_raw_crop.v"),
    (Join-Path $repo "fpga_rtl\camera\rgb_axis_packer.v"),
    (Join-Path $repo "fpga_rtl\camera\camera_rgb_pipeline.v"),
    (Join-Path $repo "fpga_rtl\tb\tb_camera_rgb_pipeline.v")
)

function Invoke-PipelineCase {
    param(
        [string]$Name,
        [int]$Width,
        [int]$Height,
        [int]$FullRun,
        [int]$GammaBypass
    )

    $caseDir = Join-Path $repo "tmp\modelsim\camera_pipeline_$Name"
    $workLib = Join-Path $caseDir "work"
    $compileLog = Join-Path $caseDir "compile.log"
    $runLog = Join-Path $caseDir "run.log"
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo "fpga_rtl\camera\isp\color\gamma22_10to8.dath") `
        -Destination (Join-Path $caseDir "gamma22_10to8.dath") -Force
    $sourceLink = Join-Path $caseDir "fpga_rtl"
    if (-not (Test-Path -LiteralPath $sourceLink)) {
        New-Item -ItemType Junction -Path $sourceLink `
            -Target (Join-Path $repo "fpga_rtl") | Out-Null
    }

    Push-Location $caseDir
    try {
        if (-not (Test-Path -LiteralPath $workLib)) {
            & "$modelsim\vlib.exe" $workLib
            if ($LASTEXITCODE -ne 0) { throw "$Name vlib failed" }
        }
        & "$modelsim\vmap.exe" work $workLib | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$Name vmap failed" }
        & "$modelsim\vlog.exe" -quiet -work $workLib -timescale 1ns/1ps `
            -l $compileLog @rtl
        if ($LASTEXITCODE -ne 0) { throw "$Name vlog failed" }
        $compileContent = Get-Content -LiteralPath $compileLog -Raw
        if ($compileContent -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
            throw "$Name compile log contains errors: $compileLog"
        }

        & "$modelsim\vsim.exe" -c -work work PH1_PHY_GSR tb_camera_rgb_pipeline `
            "-gWIDTH=$Width" "-gHEIGHT=$Height" "-gFULL_RUN=$FullRun" `
            "-gGAMMA_BYPASS=$GammaBypass" `
            -l $runLog -do "run -all; quit -f"
        if ($LASTEXITCODE -ne 0) { throw "$Name simulation failed to run" }
        $content = Get-Content -LiteralPath $runLog -Raw
        if ($content -notmatch "RESULT: PASS" -or
            $content -match "RESULT: FAIL" -or
            $content -match "\[TB\] ERROR" -or
            $content -match "(?m)^\s*(?:#\s*)?\*\*\s+(Error|Fatal):") {
            throw "$Name self-check failed: $runLog"
        }
        Write-Output "[ModelSim] $Name RESULT: PASS"
        if ($FullRun) {
            ($content -split "`r?`n" | Where-Object { $_ -match "\[TB\] RATE" }) |
                ForEach-Object { Write-Output $_.TrimStart('#', ' ') }
        }
    } finally {
        Pop-Location
    }
}

$caseFailures = @()
if ($Case -eq "all" -or $Case -eq "small") {
    try { Invoke-PipelineCase -Name "small" -Width 16 -Height 4 -FullRun 0 -GammaBypass 0 }
    catch { $caseFailures += $_.Exception.Message; Write-Warning $_.Exception.Message }
}
if ($Case -eq "gamma") {
    try { Invoke-PipelineCase -Name "gamma" -Width 16 -Height 4 -FullRun 0 -GammaBypass 0 }
    catch { $caseFailures += $_.Exception.Message; Write-Warning $_.Exception.Message }
}
if ($Case -eq "linear") {
    try { Invoke-PipelineCase -Name "linear" -Width 16 -Height 4 -FullRun 0 -GammaBypass 1 }
    catch { $caseFailures += $_.Exception.Message; Write-Warning $_.Exception.Message }
}
if ($Case -eq "all" -or $Case -eq "1080p") {
    try { Invoke-PipelineCase -Name "1080p" -Width 1920 -Height 1080 -FullRun 1 -GammaBypass 0 }
    catch { $caseFailures += $_.Exception.Message; Write-Warning $_.Exception.Message }
}
if ($Case -eq "all" -or $Case -eq "4k") {
    try { Invoke-PipelineCase -Name "4k" -Width 3840 -Height 2160 -FullRun 1 -GammaBypass 0 }
    catch { $caseFailures += $_.Exception.Message; Write-Warning $_.Exception.Message }
}
if ($caseFailures.Count -ne 0) {
    throw "Camera pipeline failures: $($caseFailures -join '; ')"
}
