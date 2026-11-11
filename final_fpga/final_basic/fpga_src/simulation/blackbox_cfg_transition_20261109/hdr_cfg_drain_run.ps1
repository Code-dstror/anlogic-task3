#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('baseline', 'candidate')]
    [string] $Variant,

    [Parameter(Mandatory)]
    [string] $ModelSimBin,

    [Parameter(Mandatory)]
    [string] $TdRoot,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string] $RunId
)

$ErrorActionPreference = 'Stop'
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$wallWatchdogMs = 55000
$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$r2Root = Split-Path -Parent $sourceRoot
$resultsRoot = Join-Path $r2Root 'tmp/blackbox_hdr_cfg_drain_20261109'
$runDirectory = Join-Path $resultsRoot "$Variant-$RunId"
$null = New-Item -Path $resultsRoot -ItemType Directory -Force
$null = New-Item -Path $runDirectory -ItemType Directory
$iniPath = Join-Path $runDirectory 'modelsim.ini'
$evidencePath = Join-Path $runDirectory 'evidence.json'
$commands = [System.Collections.Generic.List[object]]::new()
$evidence = [ordered]@{
    result = 'RUNNING'
    variant = $Variant
    wall_watchdog_ms = $wallWatchdogMs
    sim_watchdog_us = 100
    modelsim_bin = $ModelSimBin
    td_root = $TdRoot
    command = @('pwsh', '-NoProfile', '-File', $PSCommandPath, '-Variant', $Variant,
        '-ModelSimBin', $ModelSimBin, '-TdRoot', $TdRoot, '-RunId', $RunId)
    work_directory = $runDirectory
    commands = $commands
}

function Save-Evidence {
    $evidence['wall_ms'] = $timer.ElapsedMilliseconds
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding utf8
}

function Get-InputHashes([string[]] $Paths) {
    $hashes = [ordered]@{}
    foreach ($path in $Paths) {
        if (!$hashes.Contains($path)) {
            $hashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return $hashes
}

function Invoke-SimulatorTool([string] $Tool, [string] $Stage, [string[]] $ToolArgs) {
    $executable = Join-Path $ModelSimBin "$Tool.exe"
    $logPath = Join-Path $runDirectory "$Stage.log"
    $entry = [ordered]@{ stage = $Stage; argv = @($executable) + $ToolArgs; log = $logPath }
    $commands.Add($entry)
    Save-Evidence

    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $executable
    $start.WorkingDirectory = $runDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $null = $start.Environment.Remove('MODELSIM')
    if (Test-Path -LiteralPath $iniPath) {
        $start.Environment['MODELSIM'] = $iniPath
    }
    foreach ($argument in $ToolArgs) {
        $start.ArgumentList.Add($argument)
    }

    $remaining = $wallWatchdogMs - $timer.ElapsedMilliseconds
    if ($remaining -le 0) {
        throw "Wall watchdog reached before $Stage"
    }
    $process = [System.Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit([int]$remaining)) {
            $process.Kill($true)
            [System.IO.File]::WriteAllText($logPath, "Wall watchdog reached during $Stage")
            throw "Wall watchdog reached during $Stage"
        }
        $log = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [System.IO.File]::WriteAllText($logPath, $log)
        $entry['exit_code'] = $process.ExitCode
        if ($process.ExitCode -ne 0) {
            throw "ModelSim stage $Stage exited $($process.ExitCode). See $logPath"
        }
        return $log
    } finally {
        $process.Dispose()
    }
}

try {
    $modelRoot = Join-Path $TdRoot 'sim_release'
    $ph1Sources = @(
        'common/al_phy_glbl.v'
        'ph1/ph1_logic_eram.v'
        'ph1/ph1_logic_fifo.v'
        'ph1/ph1_logic_ramfifo.v'
        'ph1/ph1_phy_eram.v'
        'ph1/ph1_phy_fifoctrl.v'
        'ph1/ph1_phy_gsr.v'
    ) | ForEach-Object { Join-Path $modelRoot $_ }
    $includeDirs = @(
        'rtl/include/00_rtl'
        'rtl/include/03_mono_config_v2_20261015'
        'rtl/include/04_include'
        'ip/camera_control_fifo_40x512/RTL/include'
    ) | ForEach-Object { Join-Path $sourceRoot $_ }
    $gateSource = Join-Path $sourceRoot 'rtl/real_hdr_pair_cycle_gate.v'
    if ($Variant -eq 'baseline') {
        $gateSource = Join-Path $r2Root 'tmp/fieldfix_20261109/baseline/real_hdr_pair_cycle_gate.v'
    }
    $workSources = @(
        (Join-Path $PSScriptRoot 'hdr_cfg_drain_carrier.v')
        $gateSource
        (Join-Path $sourceRoot 'rtl/physical_pair_config_owner.v')
        (Join-Path $sourceRoot 'rtl/frame_config_preset_owner.v')
        (Join-Path $sourceRoot 'rtl/paired_raw_capture_drain_cdc.v')
        (Join-Path $sourceRoot 'rtl/reset_release_sync.v')
        (Join-Path $sourceRoot 'rtl/control_message_fifo_ip.v')
        (Join-Path $sourceRoot 'rtl/control_fifo_40x512.v')
        (Join-Path $sourceRoot 'ip/camera_control_fifo_40x512/camera_control_fifo_40x512.v')
        (Join-Path $sourceRoot 'ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v')
        (Join-Path $sourceRoot 'ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v')
        (Join-Path $modelRoot 'ph1/ph1_phy_gsr.v')
        (Join-Path $PSScriptRoot 'hdr_cfg_drain_tb.sv')
    )
    $includeFiles = foreach ($directory in $includeDirs) {
        Get-ChildItem -LiteralPath $directory -File -Recurse | Sort-Object FullName |
            Select-Object -ExpandProperty FullName
    }
    $inputPaths = $ph1Sources + $workSources + $includeFiles + @(
        (Join-Path $r2Root 'docs/fieldfix_20261109/HDR_DRAIN_PUBLIC.md')
        $PSCommandPath
    )
    $evidence['input_sha256'] = Get-InputHashes $inputPaths
    if ($Variant -eq 'baseline' -and $evidence.input_sha256[$gateSource] -ne
        '68e0b67235a1d0b765e31f4adc48a3765980a627ce84f69f529d523b460c2b59') {
        throw 'Board-source gate SHA-256 differs from the public contract'
    }
    $evidence['modelsim_version'] = (Invoke-SimulatorTool 'vsim' 'version' @('-version')).Trim()
    $null = Invoke-SimulatorTool 'vmap' 'init_map' @('-c')
    $null = Invoke-SimulatorTool 'vlib' 'create_ph1' @('ph1')
    $null = Invoke-SimulatorTool 'vlib' 'create_work' @('work')
    $null = Invoke-SimulatorTool 'vmap' 'map_ph1' @('ph1', 'ph1')
    $null = Invoke-SimulatorTool 'vmap' 'map_work' @('work', 'work')
    $null = Invoke-SimulatorTool 'vlog' 'compile_ph1' (@('-work', 'ph1') + $ph1Sources)
    $includeArgs = $includeDirs | ForEach-Object { "+incdir+$_" }
    $null = Invoke-SimulatorTool 'vlog' 'compile_work' (@('-sv', '-work', 'work', '-L', 'ph1') + $includeArgs + $workSources)
    $log = Invoke-SimulatorTool 'vsim' 'simulate' @(
        '-c', '-t', '1ps', '-onfinish', 'stop', '-L', 'ph1',
        'work.hdr_cfg_drain_tb', 'ph1.glbl', '-do',
        'onerror {quit -force -code 2}; run -all; quit -force -code 0'
    )
    $after = Get-InputHashes $inputPaths
    foreach ($path in $after.Keys) {
        if ($after[$path] -ne $evidence.input_sha256[$path]) {
            throw "Simulation input changed during run. See $path"
        }
    }
    $matches = [regex]::Matches($log, '(?m)^#?\s*RESULT (PASS|FAIL) ([^\r\n]+)')
    if ($matches.Count -ne 1) {
        throw "Expected one terminal TB result. Observed $($matches.Count)"
    }
    $evidence['result'] = $matches[0].Groups[1].Value
    $evidence['terminal'] = $matches[0].Groups[2].Value
    $log -split '\r?\n' | Where-Object { $_ -match '^#?\s*(OBS|RESULT) ' } | Write-Output
} catch {
    $evidence['result'] = 'BLOCKED'
    $evidence['terminal'] = $_.Exception.Message
} finally {
    Save-Evidence
}
Write-Output "$($evidence.result) $($evidence.terminal)"
Write-Output "Evidence $evidencePath"
switch ($evidence.result) {
    'PASS' { exit 0 }
    'FAIL' { exit 1 }
    default { exit 2 }
}
