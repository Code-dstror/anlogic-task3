param(
    [Parameter(Mandatory=$true)][string]$ModelSimBin,
    [Parameter(Mandatory=$true)][string]$TdRoot,
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [switch]$Parent
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$source = if ($Parent) { Join-Path (Split-Path -Parent $project) 'camera_raw_r2' } else { $project }
$rtl = Join-Path $source 'src_fpga/rtl'
$ip = Join-Path $source 'src_fpga/ip'
$sim = Join-Path $TdRoot 'sim_release'
$includes = @('00_rtl', '01_include', '03_mono_config_v2_20261015', '04_include') |
    ForEach-Object { '+incdir+' + (Join-Path $rtl ('include/' + $_)) }
$includes += '+incdir+' + (Join-Path $ip 'camera_control_fifo_40x512/RTL/include')
$files = @(
    (Join-Path $sim 'common/al_phy_glbl.v'),
    (Join-Path $sim 'ph1/ph1_phy_gsr.v'),
    (Join-Path $sim 'ph1/ph1_logic_eram.v'),
    (Join-Path $sim 'ph1/ph1_logic_fifo.v'),
    (Join-Path $sim 'ph1/ph1_logic_ramfifo.v'),
    (Join-Path $ip 'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v'),
    (Join-Path $ip 'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v'),
    (Join-Path $ip 'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v'),
    (Join-Path $ip 'camera_control_fifo_40x512/camera_control_fifo_40x512.v')
)
$files += @(
    'reset_release_sync', 'control_fifo_40x512', 'control_message_fifo_ip', 'td_sdp_ram40',
    'frame_config_extension_validate', 'mono_config_legacy_scan_v1', 'mono_config_scan_v2',
    'mono_config_byte_store_v2', 'mono_config_bar_v2', 'mono_config_engine_v2', 'mono_config_service_v2',
    'frame_config_preset_owner', 'paired_raw_capture_drain_cdc', 'physical_pair_config_owner', 'frame_job_config_cdc'
) | ForEach-Object { Join-Path $rtl ($_ + '.v') }
$files += Join-Path $PSScriptRoot 'quality_config_carrier.v'
if ($Parent) { $includes += '+define+QUALITY_CONTROL_PARENT' }
$null = New-Item -ItemType Directory -Path $WorkDir -Force
Push-Location -LiteralPath $WorkDir
try {
    if (!(Test-Path -LiteralPath 'work')) {
        & (Join-Path $ModelSimBin 'vlib.exe') work
        if ($LASTEXITCODE -ne 0) { throw "ModelSim vlib exited $LASTEXITCODE" }
    }
    & (Join-Path $ModelSimBin 'vlog.exe') -work work @includes @files
    if ($LASTEXITCODE -ne 0) { throw "ModelSim vlog exited $LASTEXITCODE" }
} finally {
    Pop-Location
}
