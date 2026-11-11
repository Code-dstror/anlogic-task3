[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TdRoot,
    [string]$ModelSimBin = 'D:/App/modelsim/win64',
    [string]$BaselineSha256 = 'c107e8ee115b244570b0e7fb879fc18dcd1af5b49e31ea5c23a116f4aec75d99',
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$CandidateSha256
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$repo = (Resolve-Path -LiteralPath (Join-Path $project '../..')).Path
$runParent = Join-Path $repo 'tmp/hdr_rate_seed56_20261110/tone_blackbox'
$runName = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + "-$PID"
$runDir = (New-Item -Path (Join-Path $runParent $runName) -ItemType Directory).FullName
Write-Host "RUN $runDir"

$models = @(
    'sim_release/common/al_phy_glbl.v'
    'sim_release/ph1/ph1_logic_eram.v'
    'sim_release/ph1/ph1_phy_eram.v'
    'sim_release/ph1/ph1_logic_mult.v'
    'sim_release/ph1/ph1_phy_dspmult.v'
    'sim_release/ph1/ph1_phy_dspmult_v2.v'
    'sim_release/ph1/ph1_phy_dspsiou.v'
    'sim_release/ph1/ph1_phy_dspadd_v2.v'
    'sim_release/ph1/ph1_phy_dsptadd_v2.v'
    'sim_release/ph1/ph1_phy_dsplogic_v2.v'
) | ForEach-Object { Join-Path $TdRoot $_ }
$gsr = Join-Path $TdRoot 'sim_release/ph1/ph1_phy_gsr.v'
$wrappers = @(
    'src_fpga/simulation/assets/tone96_rom0_sim.v'
    'src_fpga/simulation/assets/tone96_rom1_sim.v'
    'src_fpga/ip/dsp_mult_fixed/mult_18s18s_p1/RTL/mult_18s18s_p1_multiplier.v'
    'src_fpga/ip/dsp_mult_fixed/mult_18s18s_p1/RTL/mult_18s18s_p1_multiplier_top.v'
    'src_fpga/ip/dsp_mult_fixed/mult_18s18s_p1/mult_18s18s_p1.v'
) | ForEach-Object { Join-Path $project $_ }
$mifs = @('tone96_0.mif', 'tone96_1.mif') | ForEach-Object {
    Join-Path $project "src_fpga/ip/coefficients/$_"
}
$bench = Join-Path $PSScriptRoot 'tb_tone.sv'
$contractDir = Join-Path $project 'docs/hdr_rate_seed56_20261110'
$dutSources = [ordered]@{
    baseline = Join-Path $project 'experiments/hdr_tone2_20261110/baseline/hdr_tone96_shared4.v'
    candidate = Join-Path $project 'experiments/hdr_tone2_20261110/candidate/hdr_tone96_shared4.v'
}
$simulators = @('vmap', 'vlib', 'vlog', 'vsim') | ForEach-Object { Join-Path $ModelSimBin "$_.exe" }
$inputPaths = @($PSCommandPath, $bench, (Join-Path $contractDir 'TONE_PUBLIC.md'),
    (Join-Path $contractDir 'TONE_PORTS.vh'), $gsr) + $models + $wrappers + $mifs +
    @($dutSources.baseline, $dutSources.candidate) + $simulators
$commands = [Collections.Generic.List[object]]::new()
$scenarios = [Collections.Generic.List[object]]::new()
$comparisons = [Collections.Generic.List[object]]::new()
$builds = [Collections.Generic.List[object]]::new()
$frozenPaths = [Collections.Generic.List[string]]::new()
$cases = @('cadence', 'numeric', 'flow')
$result = [ordered]@{
    status = 'BLOCKED'
    run_dir = $runDir
    td_root = $TdRoot
    modelsim_bin = $ModelSimBin
    powershell = $PSVersionTable.PSVersion.ToString()
    wall_seconds_per_process = 60
    simulation_watchdog_cycles = 50000
    input_hashes_before = @()
    commands = $commands
    builds = $builds
    scenarios = $scenarios
    comparisons = $comparisons
}

function Get-Hashes([string[]]$Paths) {
    foreach ($path in $Paths) {
        $file = Get-FileHash -LiteralPath $path -Algorithm SHA256
        [ordered]@{ path = $file.Path; sha256 = $file.Hash.ToLowerInvariant() }
    }
}

function Convert-ToneMif([string]$Path) {
    $lines = [IO.File]::ReadAllLines($Path)
    $header = $lines[0..5] -join ' '
    if ($header -notmatch '^DEPTH\s*=\s*512;\s*WIDTH\s*=\s*40;\s*ADDRESS_RADIX\s*=\s*HEX;\s*DATA_RADIX\s*=\s*HEX;\s*CONTENT\s+BEGIN$' -or
        $lines[-1] -notmatch '^END;\s*$') {
        throw "Unexpected MIF format in $Path"
    }
    $rows = [string[]]::new(512)
    for ($line = 6; $line -lt $lines.Length - 1; $line++) {
        if ($lines[$line] -notmatch '^\s*([a-f0-9]+)\s*:\s*([a-f0-9]{1,10})\s*;\s*$') {
            throw "Invalid MIF address entry at line $($line + 1) in $Path"
        }
        $address = [Convert]::ToInt32($Matches[1], 16)
        if ($address -lt 0 -or $address -ge $rows.Length -or $rows[$address]) {
            throw "Duplicate or out-of-range MIF address at line $($line + 1) in $Path"
        }
        $rows[$address] = $Matches[2].ToUpperInvariant().PadLeft(10, '0')
    }
    if ($rows -contains $null -or $rows -contains '') {
        throw "Incomplete MIF address set in $Path"
    }
    [IO.File]::WriteAllLines("$Path.dath", $rows, [Text.Encoding]::ASCII)
}

function Invoke-ModelSim(
    [string]$Program, [string[]]$Arguments, [string]$WorkingDirectory, [string]$LogName
) {
    $programPath = Join-Path $ModelSimBin "$Program.exe"
    $logPath = Join-Path $WorkingDirectory $LogName
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $programPath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $localIni = Join-Path $WorkingDirectory 'modelsim.ini'
    [void]$startInfo.Environment.Remove('MODELSIM')
    if (Test-Path -LiteralPath $localIni) {
        $startInfo.Environment['MODELSIM'] = $localIni
    }
    $command = [ordered]@{
        exe = $programPath; args = $Arguments; cwd = $WorkingDirectory; log = $logPath
        exit_code = $null; wall_seconds = $null; timed_out = $false
    }
    $commands.Add($command)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $process = [Diagnostics.Process]::Start($startInfo)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(60000)) {
            $command.timed_out = $true
            $process.Kill($true)
            $process.WaitForExit()
        }
        $timer.Stop()
        $command.wall_seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
        $command.exit_code = $process.ExitCode
        $output = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($logPath, $output + "`n--- stderr ---`n" + $errorText)
    } finally {
        $process.Dispose()
    }
    $command
}

function Confirm-Command($Command) {
    if ($Command.timed_out -or $Command.exit_code -ne 0) {
        throw "Tool failed or timed out. See $($Command.log)"
    }
}

try {
    $result.input_hashes_before = @(Get-Hashes $inputPaths)
    if ((Get-FileHash -LiteralPath $dutSources.baseline).Hash -ne $BaselineSha256 -or
        (Get-FileHash -LiteralPath $dutSources.candidate).Hash -ne $CandidateSha256) {
        throw 'DUT source SHA256 differs from the requested pair'
    }
    $version = Invoke-ModelSim 'vsim' @('-version') $runDir 'version.log'
    Confirm-Command $version
    $result['modelsim_version'] = (Get-Content -LiteralPath $version.log -TotalCount 1).Trim()
    $benchCopy = Join-Path $runDir 'tb_tone.sv'
    Copy-Item -LiteralPath $bench -Destination $benchCopy
    $frozenPaths.Add($benchCopy)

    foreach ($variant in $dutSources.Keys) {
        $working = (New-Item -Path (Join-Path $runDir $variant) -ItemType Directory).FullName
        $sourceCopy = Join-Path $working 'hdr_tone96_shared4.v'
        $build = [ordered]@{ variant = $variant; status = 'BLOCKED'; problem = $null }
        $builds.Add($build)
        try {
            Copy-Item -LiteralPath $dutSources[$variant] -Destination $sourceCopy
            $expectedHash = if ($variant -eq 'baseline') { $BaselineSha256 } else { $CandidateSha256 }
            if ((Get-FileHash -LiteralPath $sourceCopy).Hash -ne $expectedHash) {
                throw "Copied DUT changed during freeze: $sourceCopy"
            }
            $frozenPaths.Add($sourceCopy)
            $romDir = (New-Item -Path (Join-Path $working 'rom_init') -ItemType Directory).FullName
            foreach ($mif in $mifs) {
                $mifCopy = Join-Path $romDir (Split-Path -Path $mif -Leaf)
                Copy-Item -LiteralPath $mif -Destination $mifCopy
                Convert-ToneMif $mifCopy
                $frozenPaths.Add($mifCopy)
                $frozenPaths.Add("$mifCopy.dath")
            }

            Confirm-Command (Invoke-ModelSim 'vmap' @('-c') $working 'setup_ini.log')
            foreach ($library in @('ph1', 'work')) {
                Confirm-Command (Invoke-ModelSim 'vlib' @($library) $working "vlib_$library.log")
                Confirm-Command (Invoke-ModelSim 'vmap' @($library, $library) $working "vmap_$library.log")
            }
            $frozenPaths.Add((Join-Path $working 'modelsim.ini'))
            Confirm-Command (Invoke-ModelSim 'vlog' (@('-work', 'ph1', '+define+PH1') + $models) $working 'vlog_ph1.log')
            Confirm-Command (Invoke-ModelSim 'vlog' (@('-work', 'work', '-L', 'ph1', '+define+PH1', $gsr) +
                $wrappers + @($sourceCopy)) $working 'vlog_dut.log')
            Confirm-Command (Invoke-ModelSim 'vlog' @('-sv', '-work', 'work', $benchCopy) $working 'vlog_tb.log')
            $build.status = 'PASS'
        } catch {
            $build.problem = $_.Exception.Message
            Write-Host "BLOCKED ${variant}: $($build.problem)"
            continue
        }

        $stride = if ($variant -eq 'baseline') { 4 } else { 2 }
        $latency = if ($variant -eq 'baseline') { 14 } else { 12 }
        foreach ($case in $cases) {
            $arguments = @('-c', '-onfinish', 'exit', '-L', 'ph1', '-wlf', "$case.wlf",
                "-gHDR_STRIDE=$stride", "-gHDR_FIRST_LATENCY=$latency",
                'work.PH1_PHY_GSR', 'ph1.glbl', 'work.tb_tone', "+CASE=$case",
                '-do', 'onerror {quit -f -code 1}; run -all; quit -f -code 0')
            $execution = Invoke-ModelSim 'vsim' $arguments $working "$case.log"
            $simLog = Get-Content -LiteralPath $execution.log
            $lines = @($simLog | Where-Object {
                $_ -match 'TONE_(PASS|FAIL|CADENCE|NUMERIC|FLOW|TRANSITION)\s'
            })
            $trace = Join-Path $working "${case}_public.txt"
            $status = 'BLOCKED_TOOL'
            if ($simLog -match 'Failed to open readmem file') {
                $status = 'BLOCKED_DEPENDENCY'
            } elseif ($lines -match 'TONE_FAIL ') {
                $status = if ($lines -match 'kind=fixture ') { 'FAIL_FIXTURE' }
                    elseif ($lines -match 'kind=liveness ') { 'FAIL_LIVENESS' }
                    else { 'FAIL_DUT' }
            } elseif (!$execution.timed_out -and $execution.exit_code -eq 0 -and
                      ($lines -match "TONE_PASS case=$case ") -and (Test-Path -LiteralPath $trace)) {
                $status = 'PASS'
            }
            $traceHash = if (Test-Path -LiteralPath $trace) { (Get-FileHash -LiteralPath $trace).Hash.ToLowerInvariant() }
            $scenarios.Add([ordered]@{
                variant = $variant; scenario = $case; status = $status; log = $execution.log
                wall_seconds = $execution.wall_seconds; trace_sha256 = $traceHash; markers = $lines
            })
            Write-Host "$status $variant $case $($execution.wall_seconds)s"
            $lines | Write-Host
        }
    }

    foreach ($case in $cases) {
        $passed = @($scenarios | Where-Object { $_.scenario -eq $case -and $_.status -eq 'PASS' })
        $comparison = if ($passed.Count -ne 2) { 'NOT_RUN' }
            elseif ($passed[0].trace_sha256 -eq $passed[1].trace_sha256) { 'MATCH' }
            else { 'DIFFERENT' }
        $comparisons.Add([ordered]@{ scenario = $case; public_trace = $comparison })
        Write-Host "TRACE $case $comparison"
    }
    if (($scenarios | Where-Object { $_.status -like 'FAIL_*' }) -or
        ($comparisons | Where-Object { $_.public_trace -eq 'DIFFERENT' })) {
        $result.status = 'FAIL'
    } elseif ($scenarios.Count -eq 6 -and !($scenarios | Where-Object { $_.status -ne 'PASS' })) {
        $result.status = 'PASS'
    }
} catch {
    $result['problem'] = $_.Exception.Message
    Write-Host "BLOCKED $($result.problem)"
} finally {
    try {
        $result['input_hashes_after'] = @(Get-Hashes $inputPaths)
        $result['frozen_input_hashes'] = @(Get-Hashes ($frozenPaths.ToArray()))
        $result['input_hashes_unchanged'] = (ConvertTo-Json -InputObject $result.input_hashes_before -Compress) -ceq
            (ConvertTo-Json -InputObject $result.input_hashes_after -Compress)
        if (!$result.input_hashes_unchanged) {
            $result.status = 'BLOCKED'
            $result['problem'] = 'An input hash changed or could not be captured before execution'
        }
    } catch {
        $result.status = 'BLOCKED'
        $result['hash_problem'] = $_.Exception.Message
    }
    $resultPath = Join-Path $runDir 'result.json'
    ConvertTo-Json -InputObject $result -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding utf8
    Write-Host "$($result.status) $resultPath"
}

if ($result.status -ne 'PASS') { exit 1 }
