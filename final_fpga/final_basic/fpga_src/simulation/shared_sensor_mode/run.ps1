param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Name,
    [Parameter(Mandatory=$true)][string]$TdRoot,
    [Parameter(Mandatory=$true)][string]$ModelSimBin
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../../../..')).Path
$project = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$rtl = Join-Path $project 'src_fpga/rtl'
$ip = Join-Path $project 'src_fpga/ip'
$include = Join-Path $rtl 'include/04_include'
. (Join-Path $repo 'src_fpga/simulation/tool_paths.ps1')
$td = Resolve-TdRoot -PreferredPath $TdRoot -RequirePh1SimulationModels
$ms = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$run = Join-Path $project "tmp/shared_sensor_mode/$Name"
if (Test-Path -LiteralPath $run) { throw "Preserve prior run: $run" }

$models = @('common/al_phy_glbl.v','ph1/ph1_logic_eram.v','ph1/ph1_logic_fifo.v',
    'ph1/ph1_phy_gclk_v2.v','ph1/ph1_logic_ramfifo.v','ph1/ph1_phy_eram.v','ph1/ph1_phy_fifoctrl.v') |
    ForEach-Object { Join-Path $td "sim_release/$_" }
$sources = @("$td/sim_release/ph1/ph1_phy_gsr.v",
    "$ip/vendor/anlogic_camera/sensor/ui_imx415_reg.v",
    "$ip/vendor/anlogic_camera/phy/csi_rx_word_gear_box.v",
    "$PSScriptRoot/../camera1/word_phy_boundary.sv", "$PSScriptRoot/tb_shared_sensor_mode.sv")
foreach ($fifo in 'camera_event_fifo_47x512','camera_packet_fifo_147x512') {
    $sources += @("$ip/$fifo/RTL/${fifo}_soft_fifo_core.v", "$ip/$fifo/RTL/${fifo}_soft_fifo.v", "$ip/$fifo/$fifo.v")
}
$sources += @('reset_release_sync','camera_i2c_write','imx415_mode_table','imx415_hdr2_recipe_rom',
    'imx415_sensor_recipe','imx415_sensor_config','csi_rx_word_align_observed','csi_clock_watchdog',
    'csi2_async_event_fifo','physical_csi_word_core','physical_csi_rx_stream','physical_camera_crop',
    'raw_capture_fifo_eram_safe','hdr_csi_boundary_adapter','real_hdr_sensor_clock_mux',
    'real_hdr_event_cdc','real_hdr_pair_cycle_gate','real_hdr_csi_word_core','real_hdr_csi_dual_word_rx',
    'real_hdr_member_crop10','real_hdr_csi_capture_stream','real_hdr_physical_csi_rx','sdr_camera_raw_frontend') |
    ForEach-Object { Join-Path $rtl "$_.v" }
$inputs = @($models + $sources + @($PSCommandPath, "$include/camera_physical_capture.vh", "$include/pcie_protocol_v1.vh") |
    ForEach-Object {
        $path = (Resolve-Path -LiteralPath $_).Path
        @{path=$path; sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}
    })
New-Item -ItemType Directory -Path $run | Out-Null
$result = [ordered]@{
    status='RUNNING'; td_root=$td; modelsim=$ms; inputs=$inputs; commands=@();
    boundary='Camera1 electrical PHY/eye scan boundary; running WORD clocks and externally delivered qualified pair events. Actual two frontend instances, watchdog, CSI parser, official FIFO models, clock mux, configuration and I2C.';
    synthesis='NOT_RUN'; place_route='NOT_RUN'; timing='NOT_RUN'; board='NOT_RUN'
}
$budget = [Diagnostics.Stopwatch]::StartNew()

function Invoke-ModelSimStep([string]$step,[string]$tool,[string[]]$toolArguments) {
    $remaining = 180000 - [int]$budget.ElapsedMilliseconds
    if ($remaining -le 0) { throw '180 second simulation budget expired' }
    $executable = Join-Path $ms "$tool.exe"
    $result.commands += @{exe=$executable; args=$toolArguments}
    $arguments = ($toolArguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $process = Start-Process -FilePath $executable -ArgumentList $arguments -WorkingDirectory $run `
        -WindowStyle Hidden -RedirectStandardOutput (Join-Path $run "$step.out.log") `
        -RedirectStandardError (Join-Path $run "$step.err.log") -PassThru
    if (!$process.WaitForExit($remaining)) {
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        throw "180 second simulation budget expired in $step"
    }
    if ($process.ExitCode -ne 0) { throw "$step failed with exit code $($process.ExitCode)" }
}

try {
    Invoke-ModelSimStep 'vmap-copy' 'vmap' @('-c')
    foreach ($lib in 'work','ph1') {
        Invoke-ModelSimStep "vlib-$lib" 'vlib' @($lib)
        Invoke-ModelSimStep "vmap-$lib" 'vmap' @($lib,$lib)
    }
    Invoke-ModelSimStep 'models' 'vlog' (@('-quiet','-work','ph1','-l','models.log') + $models)
    Invoke-ModelSimStep 'compile' 'vlog' (@('-quiet','-sv','-work','work','+define+PH1','+define+R8_STAGE1',
        "+incdir+$include",'-l','compile.log') + $sources)
    Invoke-ModelSimStep 'run' 'vsim' @('-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_shared_sensor_mode',
        '-l','run.log','-do','run -all; quit -f')
    $log = Get-Content -LiteralPath (Join-Path $run 'run.log') -Raw
    $metrics = @($log -split "`n" | Where-Object { $_ -match 'RESULT: PASS SHARED_SENSOR_MODE checks=' })
    if ($metrics.Count -ne 1 -or $log -match '\*\*\s+(Error|Fatal):') { throw 'Mode-switch self-check failed' }
    foreach ($inputFile in $inputs) {
        if ((Get-FileHash -LiteralPath $inputFile.path).Hash.ToLowerInvariant() -ne $inputFile.sha256) {
            throw "Changed input: $($inputFile.path)"
        }
    }
    $result.status = 'PASS'
    $result.metrics = $metrics
    $metrics | Write-Output
} catch {
    $result.status = 'FAIL'
    $result.error = $_.Exception.Message
    throw
} finally {
    $result.seconds = $budget.Elapsed.TotalSeconds
    $result.logs = @(Get-ChildItem -LiteralPath $run -File -Filter '*.log' | ForEach-Object {
        @{path=$_.FullName; sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}
    })
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'qualification.json') -Encoding utf8
    Write-Output "Shared sensor mode logs: $run"
}
