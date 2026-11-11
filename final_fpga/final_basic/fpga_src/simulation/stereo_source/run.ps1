param([Parameter(Mandatory=$true)][string]$Name,
      [string]$ModelSimBin='D:/App/modelsim/win64')
$ErrorActionPreference='Stop'
if($Name -notmatch '^[A-Za-z0-9_-]+$'){throw 'Unsafe run name'}
$project=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$rtl=Join-Path $project 'src_fpga/rtl'
$run=Join-Path $project "tmp/stereo_source/$Name"
if(Test-Path -LiteralPath $run){throw "Preserve previous run: $run"}
New-Item -ItemType Directory -Path $run|Out-Null
$sources=@("$rtl/physical_capture_router.v","$rtl/physical_identity_source_fence.v",
    "$rtl/stereo_capture_source4.v","$PSScriptRoot/tb_stereo_source.sv")
$inputs=@($sources+@($PSCommandPath)|ForEach-Object{
    @{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLower()}})
$result=[ordered]@{status='RUNNING';modelsim=$ModelSimBin;inputs=$inputs;
    synthesis='NOT_RUN';place_route='NOT_RUN';timing='NOT_RUN';board='NOT_RUN'}
Push-Location $run
try{
    & "$ModelSimBin/vmap.exe" -c|Out-Null
    & "$ModelSimBin/vlib.exe" work|Out-Null
    & "$ModelSimBin/vmap.exe" work work|Out-Null
    & "$ModelSimBin/vlog.exe" -quiet -sv -l compile.log @sources|Out-Null
    if($LASTEXITCODE){throw 'Stereo source compile failed'}
    & "$ModelSimBin/vsim.exe" -c work.tb_stereo_source -voptargs=+acc -l run.log -do 'run -all;quit -f'|
        ForEach-Object{if($_ -match 'RESULT:|FAIL|\*\* (Error|Fatal):'){Write-Output $_}}
    $logs=(Get-Content compile.log -Raw)+(Get-Content run.log -Raw)
    if($LASTEXITCODE -or $logs -notmatch 'RESULT: PASS STEREO_SOURCE' -or $logs -match '\*\*\s+(Error|Fatal|Warning):'){
        throw 'Stereo source self-check failed'
    }
    foreach($item in $inputs){if((Get-FileHash -LiteralPath $item.path -Algorithm SHA256).Hash.ToLower()-ne$item.sha256){throw "Changed input: $($item.path)"}}
    $result.status='PASS';$result.metrics=@($logs-split"`n"|Where-Object{$_ -match 'RESULT: PASS STEREO_SOURCE'})
}catch{$result.status='FAIL';$result.error=$_.Exception.Message;throw}
finally{
    $result.logs=@('compile.log','run.log')|Where-Object{Test-Path $_}|ForEach-Object{
        @{path=(Join-Path $run $_);sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLower()}}
    $result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $run 'qualification.json') -Encoding utf8
    Pop-Location
}
Write-Output "Stereo source logs: $run"
