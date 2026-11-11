param(
    [Parameter(Mandatory)][string] $TdRoot,
    [string] $ModelSimRoot = 'D:/App/modelsim/win64',
    [string[]] $Case,
    [ValidateRange(1, 2147483647)][int] $Seed = 874831,
    [ValidateRange(1, 50)][int] $TimeoutSeconds = 50
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 is required for native ArgumentList and timeout handling.'
}

$cases = @(
    'formatter_lengths', 'formatter_abort', 'formatter_reset',
    'store_order_and_safe', 'store_4k', 'store_stop_offer',
    'store_cancel_ar', 'store_cancel_await_r', 'store_cancel_payload',
    'store_stop_last', 'store_cancel_combined', 'store_rresp', 'store_rresp_final',
    'store_bad_rid', 'store_early_rlast', 'store_missing_rlast', 'store_reset_pending_raw'
)
if (!$Case) { $Case = $cases }
foreach ($selected in $Case) {
    if ($selected -cnotin $cases) { throw "Unknown case: $selected" }
}
if (($Case | Select-Object -Unique).Count -ne $Case.Count) {
    throw 'Supply each case at most once per run.'
}

$elapsed = [Diagnostics.Stopwatch]::StartNew()
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$stage = (Resolve-Path -LiteralPath (Join-Path $source '..')).Path
$td = (Resolve-Path -LiteralPath $TdRoot).Path
$sim = (Resolve-Path -LiteralPath $ModelSimRoot).Path
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmss.fffZ') + '-' + $PID
$runDir = Join-Path $stage "tmp/blackbox_raw_20261107/$runId"
[void](New-Item -ItemType Directory -Path $runDir)

$rtl = @(
    'rtl/td_sdp_ram40.v', 'rtl/hdr_pair_directory.v', 'rtl/stereo_raw_owner.v',
    'rtl/stereo_raw_reader.v', 'rtl/stereo_raw_store.v', 'rtl/raw_video_record_formatter.v',
    'ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v'
) | ForEach-Object { Join-Path $source $_ }
$models = @(
    'sim_release/common/al_phy_glbl.v', 'sim_release/ph1/ph1_logic_eram.v',
    'sim_release/ph1/ph1_phy_eram.v', 'sim_release/ph1/ph1_phy_gsr.v'
) | ForEach-Object { Join-Path $td $_ }
$testbenches = @('raw_blackbox_support.sv', 'tb_raw_formatter_blackbox.sv', 'tb_stereo_raw_blackbox.sv') |
    ForEach-Object { Join-Path $PSScriptRoot $_ }
$include = Join-Path $source 'rtl/include/00_rtl'
$hashPaths = $rtl + $models + $testbenches + @(
    (Join-Path $PSScriptRoot 'IO_CONTRACT.md'), $PSCommandPath
) + @(Get-ChildItem -LiteralPath $include -File | ForEach-Object FullName)
$commands = [Collections.Generic.List[object]]::new()
$outcomes = [Collections.Generic.List[object]]::new()

function Get-InputHashes {
    foreach ($item in $hashPaths) {
        $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $item
        [ordered]@{ path = $hash.Path; sha256 = $hash.Hash.ToLowerInvariant() }
    }
}

function Invoke-CappedTool {
    param([string] $Label, [string] $Exe, [string[]] $Argv)

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $logPath = Join-Path $runDir "$Label.log"
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Exe
    $info.WorkingDirectory = $runDir
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Argv) { $info.ArgumentList.Add($argument) }

    $timedOut = $false
    $exitCode = $null
    $launchError = $null
    try {
        $process = [Diagnostics.Process]::Start($info)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (!$process.WaitForExit(1000 * $TimeoutSeconds)) {
                $timedOut = $true
                $process.Kill($true)
                [void]$process.WaitForExit(5000)
            }
            if ($process.HasExited) { $exitCode = $process.ExitCode }
            $stdoutText = if ($stdout.IsCompletedSuccessfully) { $stdout.Result } else { '' }
            $stderrText = if ($stderr.IsCompletedSuccessfully) { $stderr.Result } else { '' }
            $stdoutText + $stderrText | Set-Content -LiteralPath $logPath -Encoding utf8NoBOM
        } finally {
            $process.Dispose()
        }
    } catch {
        $launchError = $_.Exception.Message
        $launchError | Set-Content -LiteralPath $logPath -Encoding utf8NoBOM
    }
    $watch.Stop()
    $result = [ordered]@{
        label = $Label
        argv = @($Exe) + $Argv
        cwd = $runDir
        timeout_seconds = $TimeoutSeconds
        seconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
        exit_code = $exitCode
        timed_out = $timedOut
        launch_error = $launchError
        log = $logPath
    }
    $commands.Add($result)
    $result
}

function Assert-ToolExit {
    param($Result)
    if ($Result.timed_out -or $Result.launch_error -or $Result.exit_code -ne 0) {
        throw "$($Result.label) did not complete successfully. See $($Result.log)."
    }
}

$before = @()
$after = @()
$errorText = $null
$inputStable = $false
try {
    $before = @(Get-InputHashes)
    Assert-ToolExit (Invoke-CappedTool -Label vsim-version -Exe (Join-Path $sim 'vsim.exe') -Argv '-version')
    Assert-ToolExit (Invoke-CappedTool -Label vlog-version -Exe (Join-Path $sim 'vlog.exe') -Argv '-version')
    Assert-ToolExit (Invoke-CappedTool -Label vlib -Exe (Join-Path $sim 'vlib.exe') -Argv 'work')
    $compileArgs = @('-sv', '-timescale', '1ns/1ps', "+incdir+$include") + $models + $rtl + $testbenches
    Assert-ToolExit (Invoke-CappedTool -Label vlog -Exe (Join-Path $sim 'vlog.exe') -Argv $compileArgs)

    foreach ($name in $Case) {
        $simArgs = @('-c', '-quiet', '-onfinish', 'stop', '-wlf', "$name.wlf")
        if ($name.StartsWith('formatter_')) {
            $simArgs += 'work.tb_raw_formatter_blackbox'
        } else {
            if ($name -in @('store_4k', 'store_cancel_ar')) { $simArgs += @('-gWIDTH=16', '-gHEIGHT=208') }
            $simArgs += @('work.tb_stereo_raw_blackbox', 'work.glbl', 'work.PH1_PHY_GSR')
        }
        $simArgs += @("+CASE=$name", "+SEED=$Seed", '-do', 'run -all; quit -code 0')
        $result = Invoke-CappedTool -Label $name -Exe (Join-Path $sim 'vsim.exe') -Argv $simArgs
        $passed = Select-String -LiteralPath $result.log -SimpleMatch "BLACKBOX_PASS $name cycles=" -Quiet
        $fatal = Select-String -LiteralPath $result.log -Pattern '\*\* (Fatal|Error):' -Quiet
        $status = if ($result.timed_out -or $result.launch_error) {
            'BLOCKED'
        } elseif ($result.exit_code -eq 0 -and $passed -and !$fatal) {
            'PASS'
        } else {
            'FAIL'
        }
        $outcomes.Add([ordered]@{ case = $name; status = $status; seconds = $result.seconds; log = $result.log })
        Write-Output ('{0,-29} {1,-7} {2,6:N3}s' -f $name, $status, $result.seconds)
    }
} catch {
    $errorText = $_.Exception.Message
    Write-Output $errorText
} finally {
    try {
        $after = @(Get-InputHashes)
        $inputStable = (ConvertTo-Json -InputObject $before -Compress) -ceq (ConvertTo-Json -InputObject $after -Compress)
    } catch {
        $errorText = $_.Exception.Message
    }
    $elapsed.Stop()
    $tdExe = Join-Path $td 'bin/td.exe'
    $tdFileVersion = if (Test-Path -LiteralPath $tdExe) { (Get-Item -LiteralPath $tdExe).VersionInfo.FileVersion } else { $null }
    $manifest = [ordered]@{
        run_id = $runId
        source_head = (git -C $repo rev-parse HEAD)
        powershell = $PSVersionTable.PSVersion.ToString()
        model_sim_root = $sim
        td_root = $td
        td_exe_file_version = $tdFileVersion
        seed = $Seed
        cases_requested = $Case
        cases = $outcomes
        commands = $commands
        sources_stable = $inputStable
        input_sha256_before = $before
        input_sha256_after = $after
        infrastructure_error = $errorText
        elapsed_seconds = [Math]::Round($elapsed.Elapsed.TotalSeconds, 3)
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDir 'run.json') -Encoding utf8NoBOM
    Write-Output "Evidence $runDir"
}

if ($errorText -or !$inputStable -or $outcomes.Count -ne $Case.Count -or ($outcomes | Where-Object status -ne PASS)) {
    exit 1
}
