$outPath = Join-Path $PSScriptRoot 'gamma22_10to8.dath'
$lines = for ($index = 0; $index -lt 1024; $index++) {
    $normalized = $index / 1023.0
    $encoded = [Math]::Round(255.0 * [Math]::Pow($normalized, 1.0 / 2.2), [MidpointRounding]::AwayFromZero)
    '{0:X2}' -f [int]$encoded
}
[IO.File]::WriteAllLines($outPath, $lines, [Text.UTF8Encoding]::new($false))
