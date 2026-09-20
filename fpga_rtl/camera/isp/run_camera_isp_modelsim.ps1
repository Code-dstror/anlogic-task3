param(
    [ValidateSet('core','gamma','1080','4k')]
    [string]$Test = 'core',
    [string]$ModelSimBin = $env:MODELSIM_BIN,
    [string]$TdRoot = $env:TD_ROOT
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repoRoot 'fpga_rtl/tb/tool_paths.ps1')
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$td = Resolve-TdRoot -PreferredPath $TdRoot -RequirePh1SimulationModels
$buildDir = Join-Path $repoRoot "tmp/camera_isp_$Test"
$primitive = Join-Path $td 'sim_release/ph1/ph1_logic_eram.v'
$globalReset = Join-Path $td 'sim_release/ph1/ph1_phy_gsr.v'
$rtl = @(
    (Join-Path $PSScriptRoot 'isp_line_ram_40x1024.v'),
    (Join-Path $PSScriptRoot 'raw/raw_blc.v'),
    (Join-Path $PSScriptRoot 'raw/raw_row_window.v'),
    (Join-Path $PSScriptRoot 'raw/raw_demosaic.v'),
    (Join-Path $PSScriptRoot 'raw/raw_isp_top.v'),
    (Join-Path $PSScriptRoot 'color/gamma_lut_10to8.v'),
    (Join-Path $PSScriptRoot 'color/color_pipeline_axis.v'),
    (Join-Path $PSScriptRoot 'isp_core_top.v')
)

New-Item -ItemType Directory -Force $buildDir | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot 'color/gamma22_10to8.dath') `
    (Join-Path $buildDir 'gamma22_10to8.dath')
Push-Location $buildDir
try {
    if (Test-Path 'work') {
        Remove-Item -Recurse -Force 'work'
    }
    & "$modelsim/vlib.exe" work
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & "$modelsim/vmap.exe" work work | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'vmap failed' }
    $tb = if ($Test -eq 'core') { Join-Path $PSScriptRoot 'tb/tb_camera_isp_core.v' } elseif ($Test -eq 'gamma') { Join-Path $PSScriptRoot 'tb/tb_camera_isp_gamma.v' } else { Join-Path $PSScriptRoot 'tb/tb_camera_isp_4k.v' }
    & "$modelsim/vlog.exe" -quiet -work work $globalReset $primitive @rtl $tb
    if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
    $top = if ($Test -eq 'core') { 'tb_isp_core_top_invariants' } elseif ($Test -eq 'gamma') { 'tb_camera_isp_gamma' } else { 'tb_raw_4k_check' }
    $resolutionArgs = if ($Test -eq '1080') { @('-gW=1920', '-gH=1080') } else { @() }
    & "$modelsim/vsim.exe" -c -work work PH1_PHY_GSR $top @resolutionArgs `
        -l run.log -do 'run -all; quit -f'
    if ($LASTEXITCODE -ne 0) { throw 'vsim failed' }
    $log = Get-Content -LiteralPath 'run.log' -Raw
    if ($log -notmatch '@@@TB PASS' -or
        $log -match '(@@@TB FAIL|\bFAIL(?:URE)?\b|(?m)^# Error,)' ) {
        throw "ISP $Test self-check failed; inspect $buildDir/run.log"
    }
    Write-Output "[ModelSim ISP $Test] RESULT: PASS"
} finally {
    Pop-Location
}
