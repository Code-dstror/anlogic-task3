# Requires PowerShell 7 for argument-safe native process invocation.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ModelSimBin,
    [Parameter(Mandatory)][string]$TdRoot,
    [Parameter(Mandatory)][string]$BaselineCursor,
    [Parameter(Mandatory)][string]$RunRoot
)

$ErrorActionPreference = 'Stop'
$wallLimitMs = 55000
$runPath = [System.IO.Path]::GetFullPath($RunRoot)
if (Test-Path -LiteralPath $runPath) {
    throw "Run directory already exists. Choose a fresh -RunRoot: $runPath"
}
$modelBinPath = (Get-Item -LiteralPath $ModelSimBin).FullName
$tdRootPath = (Get-Item -LiteralPath $TdRoot).FullName
$baselinePath = (Get-Item -LiteralPath $BaselineCursor).FullName
$sourceRoot = (Get-Item -LiteralPath "$PSScriptRoot/../..").FullName
$candidatePath = (Get-Item -LiteralPath "$sourceRoot/rtl/hdr_pair_read_cursor.v").FullName
$tdVersionExe = (Get-Item -LiteralPath "$tdRootPath/bin/td_commands_prompt.exe").FullName

$ph1Sources = @(
    "$tdRootPath/sim_release/common/al_phy_glbl.v"
    "$tdRootPath/sim_release/ph1/ph1_logic_eram.v"
    "$tdRootPath/sim_release/ph1/ph1_phy_eram.v"
    "$tdRootPath/sim_release/ph1/ph1_phy_gsr.v"
)
$workSources = @(
    "$sourceRoot/rtl/hdr_pair_pixel_reader.v"
    "$sourceRoot/rtl/shared_raw10_decode_service.v"
    "$sourceRoot/rtl/shared_raw10_decoder_masked.v"
    "$sourceRoot/rtl/hdr_merge4.v"
    "$sourceRoot/rtl/ddr_response_bank16.v"
    "$sourceRoot/rtl/td_sdp_ram40.v"
    "$sourceRoot/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v"
    "$PSScriptRoot/hdr_reader_carrier.v"
    "$PSScriptRoot/hdr_reader_bb.sv"
)
$ph1Sources = @($ph1Sources | ForEach-Object { (Get-Item -LiteralPath $_).FullName })
$workSources = @($workSources | ForEach-Object { (Get-Item -LiteralPath $_).FullName })
$auxiliaryInputs = @(
    $PSCommandPath
    (Get-Item -LiteralPath "$PSScriptRoot/../../../docs/seed12_round2_20261109/HDR_READER_PUBLIC.md").FullName
)

function Get-InputHashes([string[]]$Paths) {
    foreach ($path in $Paths) {
        $digest = Get-FileHash -LiteralPath $path -Algorithm SHA256
        [ordered]@{ path = $digest.Path; sha256 = $digest.Hash.ToLowerInvariant() }
    }
}

function Invoke-Logged([string]$Program, [string[]]$Arguments, [string]$Step) {
    $executable = (Get-Item -LiteralPath "$modelBinPath/$Program.exe").FullName
    $command = [ordered]@{ cwd = $buildPath; executable = $executable; argv = $Arguments }
    Add-Content -LiteralPath "$buildPath/commands.jsonl" -Value (ConvertTo-Json -InputObject $command -Compress)
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new($executable)
    $processInfo.WorkingDirectory = $buildPath
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $null = $processInfo.Environment.Remove('MODELSIM')
    if (Test-Path -LiteralPath "$buildPath/modelsim.ini") {
        $processInfo.Environment['MODELSIM'] = "$buildPath/modelsim.ini"
    }
    foreach ($argument in $Arguments) {
        $processInfo.ArgumentList.Add($argument)
    }
    $remainingMs = $wallLimitMs - [int]$buildClock.ElapsedMilliseconds
    if ($remainingMs -le 0) {
        throw "55-second wall limit reached before $Step in $buildPath"
    }
    $process = [System.Diagnostics.Process]::Start($processInfo)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = !$process.WaitForExit($remainingMs)
        if ($timedOut) {
            $process.Kill($true)
        }
        $process.WaitForExit()
        Set-Content -LiteralPath "$buildPath/$Step.stdout.log" -Value $stdout.GetAwaiter().GetResult() -NoNewline
        Set-Content -LiteralPath "$buildPath/$Step.stderr.log" -Value $stderr.GetAwaiter().GetResult() -NoNewline
        if ($timedOut) {
            throw "55-second wall limit reached during $Step in $buildPath"
        }
        if ($process.ExitCode -ne 0) {
            throw "$Step exited $($process.ExitCode). See the logs in $buildPath"
        }
    } finally {
        $process.Dispose()
    }
}

$null = New-Item -ItemType Directory -Path $runPath
$digests = @{}
$manifests = @{}
foreach ($build in 'baseline', 'candidate') {
    $buildPath = (New-Item -ItemType Directory -Path "$runPath/$build").FullName
    $buildClock = [System.Diagnostics.Stopwatch]::StartNew()
    $cursor = if ($build -eq 'baseline') { $baselinePath } else { $candidatePath }
    $designFiles = @($cursor) + $workSources
    $allInputs = $ph1Sources + $designFiles + $auxiliaryInputs
    $before = @(Get-InputHashes $allInputs)
    $manifests[$build] = $before
    $before | ConvertTo-Json | Set-Content -LiteralPath "$buildPath/inputs.before.json"
    [ordered]@{
        modelsim_bin = $modelBinPath
        td_root = $tdRootPath
        td_commands_prompt = @(Get-InputHashes @($tdVersionExe))[0]
        wall_limit_ms = $wallLimitMs
        case_watchdog_edges = 200000
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$buildPath/tools.json"

    try {
        Invoke-Logged 'vsim' @('-version') 'vsim-version'
        Invoke-Logged 'vlog' @('-version') 'vlog-version'
        Invoke-Logged 'vlib' @('work') 'vlib-work'
        Invoke-Logged 'vlib' @('ph1') 'vlib-ph1'
        Invoke-Logged 'vmap' @('-c') 'vmap-local-ini'
        Invoke-Logged 'vmap' @('work', 'work') 'vmap-work'
        Invoke-Logged 'vmap' @('ph1', 'ph1') 'vmap-ph1'
        Invoke-Logged 'vlog' (@('-work', 'ph1') + $ph1Sources) 'vlog-ph1'
        Invoke-Logged 'vlog' (@('-sv', '-work', 'work', '-L', 'ph1') + $designFiles) 'vlog-work'
        Invoke-Logged 'vsim' @('-c', '-t', '1ps', '-onfinish', 'stop', '-L', 'ph1',
            'work.hdr_reader_bb', 'ph1.glbl', '-do',
            'onerror {quit -f -code 1}; run -all; quit -f -code 0') 'simulation'
    } finally {
        $after = @(Get-InputHashes $allInputs)
        $after | ConvertTo-Json | Set-Content -LiteralPath "$buildPath/inputs.after.json"
        if ((ConvertTo-Json -InputObject $before -Compress) -cne
            (ConvertTo-Json -InputObject $after -Compress)) {
            throw "Simulation input changed during ${build}: $buildPath"
        }
        Set-Content -LiteralPath "$buildPath/wall_ms.txt" -Value $buildClock.ElapsedMilliseconds
    }

    $logPath = "$buildPath/simulation.stdout.log"
    $markers = @(Select-String -LiteralPath $logPath -Pattern '^\s*(?:#\s*)?BB_(?:START|CANCEL|RESULT|PASS|FAIL)\b' | ForEach-Object { $_.Line })
    $markers | Set-Content -LiteralPath "$buildPath/results.log"
    Write-Output "[$build] $buildPath"
    $markers | Write-Output
    if (@($markers -match '\bBB_PASS\b').Count -ne 1 -or
        @($markers -match '\bBB_RESULT\b').Count -ne 4 -or
        @($markers -match '\bBB_FAIL\b').Count -ne 0) {
        throw "Four cases did not reach the independent oracle's PASS in $buildPath"
    }
    if ($build -eq 'candidate' -and
        @($markers -match '\bBB_RESULT case=full\b.*\bpeak_(?:long|short)=512\b').Count -ne 1) {
        throw "Candidate never reached exactly 512 unread groups in $buildPath"
    }

    $pixelFiles = @('first', 'full', 'cancel', 'recovery' | ForEach-Object { "$buildPath/$_.pixels" })
    $digests[$build] = @(Get-InputHashes $pixelFiles)
    $digests[$build] | ConvertTo-Json | Set-Content -LiteralPath "$buildPath/pixels.sha256.json"
    foreach ($entry in $digests[$build]) {
        Write-Output "$($entry.sha256) $([System.IO.Path]::GetFileName($entry.path))"
    }
}

$sharedA = @($manifests.baseline | Where-Object { $_.path -cne $baselinePath })
$sharedB = @($manifests.candidate | Where-Object { $_.path -cne $candidatePath })
if ((ConvertTo-Json -InputObject $sharedA -Compress) -cne
    (ConvertTo-Json -InputObject $sharedB -Compress)) {
    throw "Baseline and candidate did not use identical inputs apart from the cursor"
}
if (Compare-Object $digests.baseline.sha256 $digests.candidate.sha256 -SyncWindow 0) {
    throw "Baseline and candidate differed in captured RAW14/motion/marker bytes"
}
Write-Output 'AB_PASS same common inputs and identical output evidence for each case'
