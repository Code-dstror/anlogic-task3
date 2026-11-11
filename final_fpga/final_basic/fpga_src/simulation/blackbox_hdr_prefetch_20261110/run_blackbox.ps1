#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ModelSimBin,
    [Parameter(Mandatory)] [string] $TdRoot,
    [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9_-]+$')] [string] $RunName,
    [ValidateSet('both', 'baseline', 'candidate')] [string] $Variant = 'both',
    [ValidateSet('perf', 'stall', 'cancel_ar', 'cancel_r', 'rresp', 'rid', 'rlast', 'overlap')]
    [string[]] $Scenario = @('perf', 'stall', 'cancel_ar', 'cancel_r', 'rresp', 'rid', 'rlast', 'overlap'),
    [ValidatePattern('^[0-9a-fA-F]{64}$')] [string] $CandidateSha256 =
        'a8f7a96c365d56b73997defe1454d23eb280516f38b8e8335824b4fe559db447'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
$stage = Join-Path $repo 'refactor/camera_raw_r2'
$source = Join-Path $stage 'src_fpga'
$experiment = Join-Path $stage 'experiments/hdr_read_prefetch_20261110'
$resultParent = Join-Path $repo 'tmp/hdr_rate_seed56_20261110/blackbox'
$runRoot = Join-Path $resultParent $RunName
$models = Join-Path (Resolve-Path -LiteralPath $TdRoot).Path 'sim_release'
$modelSim = (Resolve-Path -LiteralPath $ModelSimBin).Path
$wallSeconds = 55

if (Test-Path -LiteralPath $runRoot) {
    throw "Run already exists at $runRoot"
}
$null = [System.IO.Directory]::CreateDirectory($runRoot)

$scenarios = [ordered]@{
    perf = 0
    stall = 1
    cancel_ar = 2
    cancel_r = 3
    rresp = 4
    rid = 5
    rlast = 6
    overlap = 7
}
$cursorHashes = @{
    baseline = 'af790e6e66602350cfcde32df2ad8cd9622fa13f5cbbedacfc7cdd1051197f4f'
    candidate = $CandidateSha256.ToLowerInvariant()
}
$phaseModels = @(
    (Join-Path $models 'common/al_phy_glbl.v')
    (Join-Path $models 'ph1/ph1_logic_eram.v')
    (Join-Path $models 'ph1/ph1_phy_eram.v')
    (Join-Path $models 'ph1/ph1_phy_gsr.v')
)
$fixedSources = @(
    'rtl/hdr_pair_pixel_reader.v'
    'rtl/shared_raw10_decode_service.v'
    'rtl/shared_raw10_decoder_masked.v'
    'rtl/hdr_merge4.v'
    'rtl/td_sdp_ram40.v'
    'rtl/ddr_axi_two_client_arbiter.v'
    'rtl/ddr_response_bank16.v'
    'ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v'
    'simulation/blackbox_hdr_reader_round2_20261109/hdr_reader_carrier.v'
) | ForEach-Object { Join-Path $source $_ }
$testSource = Join-Path $PSScriptRoot 'hdr_prefetch_blackbox.sv'
$contractFiles = @(
    (Join-Path $stage 'docs/hdr_rate_seed56_20261110/HDR_READ_PUBLIC.md')
    (Join-Path $stage 'docs/hdr_rate_seed56_20261110/ARBITER_PORTS.txt')
    (Join-Path $stage 'docs/hdr_rate_seed56_20261110/READER_CARRIER_PORTS.txt')
    (Join-Path $stage 'docs/seed12_round2_20261109/HDR_READER_PUBLIC.md')
)
$tools = [ordered]@{}
foreach ($program in @('vlib', 'vmap', 'vlog', 'vsim')) {
    $tools[$program] = Join-Path $modelSim "$program.exe"
}

function Get-Sha256([string] $Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$variants = if ($Variant -eq 'both') { @('baseline', 'candidate') } else { @($Variant) }
$cursors = [ordered]@{}
foreach ($item in $variants) {
    $cursor = Join-Path $experiment "$item/hdr_pair_read_cursor.v"
    $actual = Get-Sha256 $cursor
    if ($actual -ne $cursorHashes[$item]) {
        throw "SHA256 mismatch for $item cursor. Expected $($cursorHashes[$item]), read $actual"
    }
    $cursors[$item] = $cursor
}
$inputPaths = @($PSCommandPath, $testSource) + $fixedSources + $phaseModels + $contractFiles +
    @($cursors.Values) + @($tools.Values)
$before = [ordered]@{}
foreach ($inputPath in $inputPaths) {
    $before[$inputPath] = Get-Sha256 $inputPath
}

$manifest = [ordered]@{
    started_utc = [DateTime]::UtcNow.ToString('o')
    worktree = $repo
    model_sim_bin = $modelSim
    td_root = (Resolve-Path -LiteralPath $TdRoot).Path
    powershell = $PSVersionTable.PSVersion.ToString()
    wall_timeout_seconds = $wallSeconds
    simulated_timeout_ns = 1000000
    clock_period_ps = 7502
    geometry = [ordered]@{ width = 68; height = 63; groups = 1071 }
    input_sha256 = $before
    commands = [System.Collections.Generic.List[object]]::new()
    cases = [System.Collections.Generic.List[object]]::new()
}

function Save-Manifest {
    $manifest | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $runRoot 'report.json') -Encoding utf8
}

function Invoke-BoundedTool([string] $Tool, [string[]] $Arguments, [string] $Directory, [string] $Name) {
    $exe = $tools[$Tool]
    $stdout = Join-Path $Directory "$Name.stdout.log"
    $stderr = Join-Path $Directory "$Name.stderr.log"
    $entry = [ordered]@{
        program = $exe
        arguments = $Arguments
        directory = $Directory
        stdout = $stdout
        stderr = $stderr
        status = 'RUNNING'
        exit_code = $null
    }
    $manifest.commands.Add($entry)
    Save-Manifest

    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $exe
    $info.WorkingDirectory = $Directory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        $info.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $info
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $null = $process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit($wallSeconds * 1000)) {
            $process.Kill($true)
            $entry.status = 'WALL_TIMEOUT'
        } else {
            $entry.exit_code = $process.ExitCode
            $entry.status = if ($process.ExitCode -eq 0) { 'OK' } else { 'NONZERO' }
        }
        [System.IO.File]::WriteAllText($stdout, $outputTask.GetAwaiter().GetResult())
        [System.IO.File]::WriteAllText($stderr, $errorTask.GetAwaiter().GetResult())
    } catch {
        $entry.status = 'TOOL_BLOCKED'
        [System.IO.File]::WriteAllText($stderr, $_.Exception.Message)
    } finally {
        $process.Dispose()
        $entry.wall_seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
        Save-Manifest
    }
    return $entry
}

function Require-Tool([string] $Tool, [string[]] $Arguments, [string] $Directory, [string] $Name) {
    $entry = Invoke-BoundedTool $Tool $Arguments $Directory $Name
    if ($entry.status -ne 'OK') {
        throw "Tool or compile failure $Name ($($entry.status), exit=$($entry.exit_code)). See $($entry.stdout) and $($entry.stderr)"
    }
    return $entry
}

$version = Require-Tool vsim @('-version') $runRoot 'version'
$manifest.model_sim_version = (Get-Content -Raw -LiteralPath $version.stdout).Trim()

foreach ($item in $variants) {
    $directory = Join-Path $runRoot $item
    $null = [System.IO.Directory]::CreateDirectory($directory)
    try {
        $null = Require-Tool vlib @('work') $directory 'vlib_work'
        $null = Require-Tool vlib @('ph1') $directory 'vlib_ph1'
        $null = Require-Tool vmap @('-c') $directory 'vmap_init'
        $null = Require-Tool vmap @('work', 'work') $directory 'vmap_work'
        $null = Require-Tool vmap @('ph1', 'ph1') $directory 'vmap_ph1'
        $null = Require-Tool vlog (@('-work', 'ph1') + $phaseModels) $directory 'vlog_ph1'
        $null = Require-Tool vlog (@('-sv', '-work', 'work', '-L', 'ph1') +
            $fixedSources + @($cursors[$item], $testSource)) $directory 'vlog_dut_and_fixture'
    } catch {
        Write-Output $_.Exception.Message
        $manifest.cases.Add([ordered]@{ variant = $item; scenario = 'compile'; status = 'BLOCKED' })
        Save-Manifest
        continue
    }
    foreach ($caseName in $Scenario) {
        $caseNumber = $scenarios[$caseName]
        $options = @('-c', '-L', 'ph1', '-t', 'ps', '-onfinish', 'exit',
            'work.hdr_prefetch_blackbox', 'ph1.glbl', "+CASE=$caseNumber")
        if ($item -eq 'candidate' -and $caseName -eq 'stall') {
            $options += '+REQUIRE_FULL'
        }
        $options += @('-do', 'run -all; quit -f -code 3')
        $entry = Invoke-BoundedTool vsim $options $directory "sim_$caseName"
        $output = Get-Content -LiteralPath $entry.stdout -ErrorAction SilentlyContinue
        $benchLines = @($output | Where-Object {
            $_ -match '^\s*#?\s*(CHECK_FAIL|BLACKBOX_PASS|METRIC|BUS|COVERAGE|CANCEL|RRESP_DIAG|PROTOCOL_DIAG)\s'
        })
        $pass = @($benchLines | Where-Object { $_ -match "\bBLACKBOX_PASS case=$caseNumber\s*$" }).Count -eq 1
        $failed = @($benchLines | Where-Object { $_ -match '\bCHECK_FAIL\b' }).Count -gt 0
        $status = if ($entry.status -eq 'OK' -and $pass -and !$failed) { 'PASS' } elseif ($failed) {
            'FAIL_ASSERTION'
        } elseif ($entry.status -eq 'WALL_TIMEOUT') { 'BLOCKED_WALL_TIMEOUT' } else { 'BLOCKED_TOOL_OR_ELABORATION' }
        $manifest.cases.Add([ordered]@{
            variant = $item
            scenario = $caseName
            status = $status
            log = $entry.stdout
            bench_markers = $benchLines
        })
        Save-Manifest
        Write-Output "$item/$caseName $status"
        $benchLines | Where-Object { $_ -notmatch '\bBLACKBOX_PASS\b' } | Write-Output
    }
}

$mismatches = @($inputPaths | Where-Object { (Get-Sha256 $_) -ne $before[$_] })
$manifest.changed_during_run = $mismatches
$manifest.ended_utc = [DateTime]::UtcNow.ToString('o')
Save-Manifest
Write-Output (Join-Path $runRoot 'report.json')
if ($mismatches.Count -gt 0 -or @($manifest.cases | Where-Object status -ne 'PASS').Count -gt 0) {
    exit 1
}
