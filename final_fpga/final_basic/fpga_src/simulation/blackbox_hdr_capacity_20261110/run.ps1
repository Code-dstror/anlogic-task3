[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*$')]
    [string] $RunId,
    [Parameter(Mandatory)]
    [string] $TdRoot,
    [Parameter(Mandatory)]
    [string] $ModelSimBin,
    [ValidateSet('first', 'late-peer', 'slow100', 'fast100', 'slow400', 'fast400', 'slow3200', 'fast3200')]
    [string[]] $Cases = @('late-peer', 'slow100', 'fast100', 'slow400', 'fast400', 'slow3200', 'fast3200')
)

$ErrorActionPreference = 'Stop'
$stage = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$repo = (Resolve-Path -LiteralPath (Join-Path $stage '../..')).Path
$contract = Join-Path $stage 'docs/hdr_rate_seed56_20261110/OWNER_CAPACITY_PUBLIC'
$manifest = Get-Content -Raw -LiteralPath "$contract.json" | ConvertFrom-Json
$bench = Join-Path $PSScriptRoot 'tb_hdr_capacity.sv'
$run = Join-Path $repo "tmp/hdr_rate_seed56_20261110/capacity_blackbox/$RunId"
$null = New-Item -ItemType Directory -Path $run
$ModelSimBin = (Resolve-Path -LiteralPath $ModelSimBin).Path
$TdRoot = (Resolve-Path -LiteralPath $TdRoot).Path
$casesToRun = @('first') + @($Cases | Where-Object { $_ -ne 'first' } | Select-Object -Unique)
$wall = $manifest.wall_limit_seconds_per_case

$stageSources = @($manifest.sources | ForEach-Object { Join-Path $stage $_ })
$tdModels = @($manifest.td_models | ForEach-Object { Join-Path $TdRoot $_ })
$tdWork = @($manifest.td_work_sources | ForEach-Object { Join-Path $TdRoot $_ })
$includeFiles = @($manifest.include_files | ForEach-Object { Join-Path $stage $_ })
$inputs = @("$contract.json", "$contract.md", "$contract.ports", $PSCommandPath, $bench) +
          $stageSources + $tdModels + $tdWork + $includeFiles
$flags = @($manifest.defines | ForEach-Object { "+define+$_" }) +
         @($manifest.include | ForEach-Object { '+incdir+' + (Join-Path $stage $_) })

function Get-InputHashes {
    foreach ($file in $inputs) {
        $hash = Get-FileHash -LiteralPath $file -Algorithm SHA256
        [ordered]@{ path = $hash.Path; sha256 = $hash.Hash.ToLowerInvariant() }
    }
}

function Invoke-ModelSim {
    param([string] $Tool, [string[]] $Arguments, [string] $Log, [int] $Seconds)

    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $ModelSimBin "$Tool.exe"
    $start.WorkingDirectory = $run
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.CreateNoWindow = $true
    $null = $start.Environment.Remove('MODELSIM')
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }

    $command = [ordered]@{ exe = $start.FileName; argv = $Arguments; cwd = $run; wall_limit_s = $Seconds; log = $Log }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = [System.Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $command.timed_out = !$process.WaitForExit(1000 * $Seconds)
        if ($command.timed_out) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        $command.exit_code = $process.ExitCode
        $command.elapsed_s = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
        [IO.File]::WriteAllText((Join-Path $run $Log), $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult())
        $command | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $run 'commands.jsonl')
        return $command
    } finally {
        $process.Dispose()
    }
}

function Invoke-Setup {
    param([string] $Tool, [string[]] $Arguments, [string] $Log)

    $result = Invoke-ModelSim $Tool $Arguments $Log $wall
    if ($result.exit_code -ne 0 -or $result.timed_out) {
        throw "ModelSim setup $Tool failed. See $(Join-Path $run $Log)"
    }
}

$before = @(Get-InputHashes)
$before | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run 'inputs-before.json')
$results = [ordered]@{}
$traceMatches = [ordered]@{}
$overallPass = $true
try {
    $production = @($stageSources | Where-Object { (Split-Path -Leaf $_) -ne 'owner_service_carrier.v' }) + $includeFiles
    $sourceIdentity = @(foreach ($file in $production) {
        $relative = [IO.Path]::GetRelativePath($repo, $file).Replace('\', '/')
        $fixed = & git -C $repo rev-parse "$($manifest.baseline):$relative"
        if ($LASTEXITCODE -ne 0) { throw "Cannot identify baseline blob for $relative" }
        $actual = & git -C $repo hash-object "--path=$relative" $file
        if ($LASTEXITCODE -ne 0) { throw "Cannot hash current blob for $relative" }
        [ordered]@{ path = $relative; baseline_blob = $fixed; worktree_blob = $actual; matches = $fixed -ceq $actual }
    })
    [ordered]@{ commit = $manifest.baseline; files = $sourceIdentity } | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $run 'production-identity.json')
    if ($sourceIdentity.Count -ne 26 -or @($sourceIdentity | Where-Object { !$_.matches }).Count -ne 0) {
        throw 'Opaque production closure differs from the fixed 26-file baseline. See production-identity.json.'
    }

    Invoke-Setup 'vsim' @('-version') 'vsim-version.log'
    Invoke-Setup 'vlog' @('-version') 'vlog-version.log'
    Invoke-Setup 'vmap' @('-c') 'vmap-init.log'
    Invoke-Setup 'vlib' @('ph1') 'vlib-ph1.log'
    Invoke-Setup 'vlib' @('work') 'vlib-work.log'
    Invoke-Setup 'vmap' @('ph1', 'ph1') 'vmap-ph1.log'
    Invoke-Setup 'vmap' @('work', 'work') 'vmap-work.log'
    Invoke-Setup 'vlog' (@('-work', 'ph1') + $tdModels) 'vlog-ph1.log'
    Invoke-Setup 'vlog' (@('-work', 'work') + $flags + $tdWork + $stageSources) 'vlog-production.log'
    Invoke-Setup 'vlog' @('-sv', '-work', 'work', $bench) 'vlog-test.log'

    @('onerror {quit -force -code 2}', 'run -all', 'quit -force -code 0') |
        Set-Content -LiteralPath (Join-Path $run 'run.do') -Encoding ascii

    foreach ($case in $casesToRun) {
        $argv = @('-c', '-L', 'ph1', '-t', 'ps', '-onfinish', 'stop', '-do', 'do run.do',
                  '-l', "$case.transcript.log", '-wlf', "$case.wlf", 'work.tb_hdr_capacity') +
                @($manifest.globals) + "+CASE=$case"
        $result = Invoke-ModelSim 'vsim' $argv "$case.stdout.log" $wall
        $log = Join-Path $run $result.log
        $markers = @(Select-String -LiteralPath $log -Pattern "HDRCAP PASS scenario=$case\s")
        $passed = !$result.timed_out -and $result.exit_code -eq 0 -and $markers.Count -eq 1
        $results[$case] = [ordered]@{
            pass = $passed
            timed_out = $result.timed_out
            exit_code = $result.exit_code
            elapsed_s = $result.elapsed_s
            log = $result.log
        }
        if ($passed) {
            Select-String -LiteralPath $log -Pattern 'HDRCAP (EYE|WINDOW|RECOVERY|PASS) ' |
                ForEach-Object { Write-Output ($_.Line -replace '^.*?(HDRCAP )', '$1') }
            Write-Output "$case PASS in $($result.elapsed_s)s"
        } else {
            $overallPass = $false
            Write-Output "$case FAIL in $($result.elapsed_s)s. See $log"
            if ($case -eq 'first') { break }
        }
    }

    foreach ($phase in @(100, 400, 3200)) {
        $slow = $results["slow$phase"]
        $fast = $results["fast$phase"]
        if ($null -eq $slow -or $null -eq $fast) { continue }
        $slowTrace = @(Select-String -LiteralPath (Join-Path $run $slow.log) -Pattern 'HDRCAP (SOF|SOURCE_OFFER) ' |
                       ForEach-Object { $_.Line -replace '^.*?(HDRCAP )', '$1' })
        $fastTrace = @(Select-String -LiteralPath (Join-Path $run $fast.log) -Pattern 'HDRCAP (SOF|SOURCE_OFFER) ' |
                       ForEach-Object { $_.Line -replace '^.*?(HDRCAP )', '$1' })
        # Concurrent lanes can log in either order on the same pixel edge.
        $sameInput = $slowTrace.Count -eq 720 -and $fastTrace.Count -eq 720 -and
                     (($slowTrace | Sort-Object) -join "`n") -ceq (($fastTrace | Sort-Object) -join "`n")
        $traceMatches["$phase"] = $sameInput
        if (!$sameInput) { $overallPass = $false }
        Write-Output "phase $phase identical SOF/SOURCE offer trace $sameInput"
    }
} finally {
    $after = @(Get-InputHashes)
    $after | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run 'inputs-after.json')
    $unchanged = ($before | ConvertTo-Json -Depth 4 -Compress) -ceq ($after | ConvertTo-Json -Depth 4 -Compress)
    [ordered]@{
        input_hashes_unchanged = $unchanged
        requested = $casesToRun
        cases = $results
        identical_phase_input = $traceMatches
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'result.json')
    Write-Output "Run evidence $run"
}

if (!$overallPass -or !$unchanged) { exit 1 }
