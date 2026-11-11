param(
    [Parameter(Mandatory=$true)][ValidateSet('Preflight','Launch','Resume')][string]$Mode,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$LockSha256
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$lockPath = Join-Path $projectRoot 'docs/EXTENDED_SIMULATION_20261101.lock.json'
if ((Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $LockSha256) {
    throw 'Test lock differs from externally pinned SHA256'
}
$registry = Join-Path $projectRoot 'tmp/extended_20261101'
New-Item -ItemType Directory -Path $registry -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_ffff'
$stdout = Join-Path $registry "controller_$($Mode.ToLowerInvariant())_$stamp.log"
$stderr = Join-Path $registry "controller_$($Mode.ToLowerInvariant())_$stamp.error.log"
$pythonPath = 'python'
$controllerPath = Join-Path $PSScriptRoot 'supervise.py'
$arguments = @('-B','-u',$controllerPath,"--$($Mode.ToLowerInvariant())",'--lock-sha256',$LockSha256)
$process = Start-Process -FilePath $pythonPath -ArgumentList $arguments -WorkingDirectory $projectRoot `
    -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
[ordered]@{
    status = 'STARTED_HIDDEN'
    mode = $Mode
    pid = $process.Id
    create_time_utc = $process.StartTime.ToUniversalTime().ToString('o')
    test_lock_sha256 = $LockSha256
    state_path = (Join-Path $registry 'STATE.json')
    stdout = $stdout
    stderr = $stderr
} | ConvertTo-Json -Depth 3
