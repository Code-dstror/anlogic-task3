#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TdRoot,
    [Parameter(Mandatory)][string]$ModelSimBin,
    [Parameter(Mandatory)][ValidateSet('baseline', 'candidate')][string]$Build,
    [Parameter(Mandatory)][ValidateSet('liveness', 'profiles', 'negative_ack', 'fault_at_sof', 'stopped_reset')][string]$Case
)

$ErrorActionPreference = 'Stop'
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$r2 = (Resolve-Path -LiteralPath "$PSScriptRoot/../../..").Path
$td = (Resolve-Path -LiteralPath $TdRoot).Path
$sim = (Resolve-Path -LiteralPath $ModelSimBin).Path
$runName = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + "-$Build-$Case"
$runDir = Join-Path $r2 "tmp/blackbox_cfg_transition_20261109/$runName"
if (Test-Path -LiteralPath $runDir) { throw "Run directory exists: $runDir" }
$null = New-Item -ItemType Directory -Path $runDir
$commands = [Collections.Generic.List[object]]::new()

function Invoke-SimTool([string]$Tool, [string[]]$ToolArgs, [string]$Name) {
    $program = Join-Path $sim "$Tool.exe"
    $commands.Add([ordered]@{ executable = $program; arguments = $ToolArgs; log = "$Name.log" })
    $commands | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$runDir/commands.json" -Encoding utf8
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $program
    $start.WorkingDirectory = $runDir
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $ToolArgs) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    $remainingMs = [Math]::Max(1, 55000 - [int]$stopwatch.ElapsedMilliseconds)
    if (!$process.WaitForExit($remainingMs)) {
        $process.Kill($true)
        $null = $process.WaitForExit(2000)
        throw "Wall watchdog in $Name. Evidence directory: $runDir"
    }
    $outTask.Result | Set-Content -LiteralPath "$runDir/$Name.log" -Encoding utf8
    if ($errTask.Result) { $errTask.Result | Add-Content -LiteralPath "$runDir/$Name.log" -Encoding utf8 }
    return $process.ExitCode
}

function Require-SimTool([string]$Tool, [string[]]$ToolArgs, [string]$Name) {
    $code = Invoke-SimTool $Tool $ToolArgs $Name
    if ($code -ne 0) { throw "$Name exited $code. Maintainer diagnostic: $runDir/$Name.log" }
}

function ModelSim-Path([string]$Path) { (Resolve-Path -LiteralPath $Path).Path.Replace('\', '/') }

$protocolPath = Join-Path $r2 'docs/pcie_protocol_v1.json'
$protocol = Get-Content -Raw -LiteralPath $protocolPath | ConvertFrom-Json -AsHashtable
$cfg = $protocol.config_transaction
$cfgV2 = $protocol.advanced_config_v2
$abi = @(
    foreach ($entry in $protocol.registers.GetEnumerator()) {
        if ($entry.Key -like 'CFG_*') { "localparam [11:0] $($entry.Key) = 12'h$($entry.Value.Substring(2));" }
    }
    "localparam [1:0] COLOR = 2'd$($cfg.modes.COLOR);"
    foreach ($entry in $cfg.commands.GetEnumerator()) {
        "localparam [31:0] COMMAND_$($entry.Key) = 32'd$($entry.Value);"
    }
    foreach ($entry in $cfg.status_bits.GetEnumerator()) {
        "localparam [31:0] STATUS_$($entry.Key) = 32'd$(1 -shl $entry.Value);"
    }
    "localparam [31:0] ERROR_RESET = 32'd$($cfg.error_codes.RESET);"
    "localparam integer EXT_WORD_COUNT = $($cfgV2.word_count);"
    "localparam integer SCHEMA_2 = $($cfgV2.schema);"
    "localparam integer HDR_QUALIFICATION_REQUIRED = $($protocol.advanced_config.hdr_qualification_required);"
    foreach ($entry in $cfgV2.modes.GetEnumerator()) {
        "localparam [1:0] $($entry.Key) = 2'd$($entry.Value);"
    }
    foreach ($entry in $cfgV2.enables.GetEnumerator()) {
        "localparam [5:0] ENABLE_$($entry.Key) = 6'd$($entry.Value);"
    }
    foreach ($field in $cfgV2.fields) {
        "localparam integer $($field.name)_LSB = $($field.offset);"
        "localparam integer $($field.name)_WIDTH = $($field.width);"
    }
)
$abi | Set-Content -LiteralPath "$runDir/cfg_protocol.svh" -Encoding ascii

$source = "$r2/src_fpga"
$engineRoot = "$source/rtl"
if ($Build -eq 'baseline') { $engineRoot = "$r2/tmp/fieldfix_20261109/baseline" }
$rtlNames = @('td_sdp_ram40', 'reset_release_sync', 'control_fifo_40x512', 'control_message_fifo_ip',
    'mono_config_byte_store_v2', 'mono_config_legacy_scan_v1', 'mono_config_scan_v2', 'mono_config_bar_v2')
$fifo = "$source/ip/camera_control_fifo_40x512"
$rtl = @(
    $rtlNames | ForEach-Object { ModelSim-Path "$source/rtl/$_.v" }
    ModelSim-Path "$engineRoot/mono_config_engine_v2.v"
    ModelSim-Path "$engineRoot/mono_config_service_v2.v"
    ModelSim-Path "$source/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v"
    ModelSim-Path "$fifo/camera_control_fifo_40x512.v"
    ModelSim-Path "$fifo/RTL/camera_control_fifo_40x512_soft_fifo.v"
    ModelSim-Path "$fifo/RTL/camera_control_fifo_40x512_soft_fifo_core.v"
)
$includes = @(
    '00_rtl', '01_include', '02_jpeg', '03_mono_config_v2_20261015', '04_include' |
        ForEach-Object { ModelSim-Path "$source/rtl/include/$_" }
    ModelSim-Path "$fifo/RTL/include"
)
$ph1Names = @('ph1_logic_eram', 'ph1_logic_fifo', 'ph1_logic_ramfifo', 'ph1_phy_eram', 'ph1_phy_fifoctrl')
$models = @(
    ModelSim-Path "$td/sim_release/common/al_phy_glbl.v"
    $ph1Names | ForEach-Object { ModelSim-Path "$td/sim_release/ph1/$_.v" }
)
$gsr = ModelSim-Path "$td/sim_release/ph1/ph1_phy_gsr.v"
$bench = ModelSim-Path "$PSScriptRoot/cfg_transition_tb.sv"
$hashedInputs = @($rtl + $models + $gsr + $bench + $PSCommandPath + $protocolPath + "$runDir/cfg_protocol.svh")
foreach ($includeDir in $includes) {
    $hashedInputs += @(Get-ChildItem -LiteralPath $includeDir -File | ForEach-Object FullName)
}
$inputHashes = foreach ($path in $hashedInputs) {
    $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256
    [ordered]@{ path = $hash.Path; sha256 = $hash.Hash.ToLowerInvariant() }
}
[ordered]@{
    build = $Build; scenario = $Case; td_root = $td; modelsim_bin = $sim
    wall_watchdog_ms = 55000; simulation_watchdog_ns = 1500000; inputs = @($inputHashes)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$runDir/inputs.json" -Encoding utf8

Require-SimTool 'vsim' @('-version') 'version'
Require-SimTool 'vlib' @('work') 'create_work'
Require-SimTool 'vlib' @('ph1') 'create_ph1'
Require-SimTool 'vmap' @('-c') 'create_ini'
Require-SimTool 'vmap' @('ph1', 'ph1') 'map_ph1'
Require-SimTool 'vlog' (@('-work', 'ph1', '+define+PH1') + $models) 'compile_td_models'
$defineArgs = @('+define+PH1', '+define+C15_F23_FULLHEIGHT_PROFILE=1')
$includeArgs = @($includes | ForEach-Object { "+incdir+$_" })
Require-SimTool 'vlog' (@('-work', 'work', '-L', 'ph1') + $defineArgs + $includeArgs + $gsr + $rtl) 'compile_design'
Require-SimTool 'vlog' @('-sv', '-work', 'work', '+incdir+.', $bench) 'compile_bench'

@'
onerror {quit -code 1 -f}
onbreak {quit -code 0 -f}
run 1500 us
quit -code 0 -f
'@ | Set-Content -LiteralPath "$runDir/run.do" -Encoding ascii
$result = Invoke-SimTool 'vsim' @('-c', '-t', 'ps', '-onfinish', 'stop', '-L', 'ph1',
    'work.cfg_transition_tb', 'ph1.glbl', 'work.PH1_PHY_GSR', "+case=$Case", '-do', 'do run.do') 'simulation'
$markers = @(Select-String -LiteralPath "$runDir/simulation.log" -Pattern '^(# )?(\*\* Fatal: )?CFG_EVIDENCE ' |
    ForEach-Object Line)
$markers | Write-Output
$pass = @($markers | Where-Object { $_ -match "CFG_EVIDENCE PASS case=$Case\b" }).Count -eq 1
$failedCheck = @($markers | Where-Object { $_ -match 'CFG_EVIDENCE FAIL\b' }).Count -ne 0
$livenessFail = @($markers | Where-Object { $_ -match 'CFG_EVIDENCE FAIL LIVENESS\b' }).Count -eq 1
$status = 'FAIL'
if ($pass -and !$failedCheck -and $result -eq 0) { $status = 'PASS' }
if ($Build -eq 'baseline' -and $Case -eq 'liveness' -and $livenessFail -and !$pass) { $status = 'REPRODUCED_FAIL' }
[ordered]@{
    build = $Build; scenario = $Case; status = $status; simulator_exit = $result
    elapsed_ms = $stopwatch.ElapsedMilliseconds; markers = $markers
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$runDir/result.json" -Encoding utf8
"$status $Build $Case $runDir" | Write-Output
if ($status -ne 'PASS') { exit 1 }
