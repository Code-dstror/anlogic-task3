# Compatibility entry; every project chat shares the maintained repository bridge.
$ErrorActionPreference = 'Stop'
$tdRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
& (Join-Path $tdRepo 'server/td/td.ps1') @args
exit $LASTEXITCODE
