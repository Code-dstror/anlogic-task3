param([Parameter(Mandatory)][string]$SimDirectory)
$ErrorActionPreference='Stop'
$candidate=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$run=[IO.Path]::GetFullPath($SimDirectory)
if(!$run.StartsWith($candidate+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Simulation directory must be inside this candidate'
}
$destination=Join-Path $run 'rom_init'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$receipts=@()
foreach($name in @('lane0_q','lane1_q','lane2_q','lane3_q','lane4_q','lane5_q','lane6_q','lane7_q','reciprocal','ac_huffman')) {
    $source=Join-Path $candidate "src_fpga/rtl/jpeg/quant_data/$name.mif"
    $text=[IO.File]::ReadAllText($source)
    $depthMatch=[regex]::Match($text,'(?m)^DEPTH\s*=\s*(\d+)\s*;')
    if(!$depthMatch.Success){throw "Missing depth: $source"}
    $depth=[int]$depthMatch.Groups[1].Value
    $words=[string[]]::new($depth)
    foreach($match in [regex]::Matches($text,'(?m)^\s*([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+)\s*;')) {
        $address=[Convert]::ToInt32($match.Groups[1].Value,16)
        if($address -ge $depth -or $null -ne $words[$address]){throw "Bad ROM address: $source"}
        $words[$address]=$match.Groups[2].Value
    }
    if(@($words|Where-Object {$null -eq $_}).Count){throw "Unspecified ROM words: $source"}
    $target=Join-Path $destination "$name.mif.dath"
    if(Test-Path -LiteralPath $target){throw "Preserve existing simulation ROM: $target"}
    [IO.File]::WriteAllLines($target,$words,[Text.Encoding]::ASCII)
    $receipts+=[ordered]@{source=$source;source_sha256=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant();
        destination=$target;sha256=(Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant();words=$depth}
}
$receipts|ConvertTo-Json -Depth 3|Set-Content -LiteralPath (Join-Path $destination 'inputs.json') -Encoding utf8
Write-Output $destination
