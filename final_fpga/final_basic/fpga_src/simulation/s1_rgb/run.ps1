param(
    [Parameter(Mandatory=$true)][string]$TdRoot,
    [string]$OutputDirectoryName='output-r3',
    [string]$ModelSimBin='D:/App/modelsim/win64',
    [string]$PythonExe='python'
)
$ErrorActionPreference='Stop'
$candidate=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$run=Join-Path $PSScriptRoot $OutputDirectoryName
New-Item -ItemType Directory -Force -Path $run | Out-Null
& $PythonExe -B (Join-Path $PSScriptRoot 'reference.py') --output $run
if($LASTEXITCODE -ne 0){throw 'Independent scalar reference failed'}
$models=@('common/al_phy_glbl.v','ph1/ph1_logic_mult.v','ph1/ph1_phy_dspmult.v',
    'ph1/ph1_phy_dspmult_v2.v','ph1/ph1_phy_dspsiou.v','ph1/ph1_phy_dspadd_v2.v',
    'ph1/ph1_phy_dsptadd_v2.v','ph1/ph1_phy_dsplogic_v2.v') |
    ForEach-Object {Join-Path $TdRoot "sim_release/$_"}
$ip=Join-Path $candidate 'src_fpga/ip/stage3/fdct_mac19s14s_z33s_p34_m1p1'
$macSources=@("$ip/RTL/fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0.v", "$ip/fdct_mac19s14s_z33s_p34_m1p1.v")
$sources=@((Join-Path $TdRoot 'sim_release/ph1/ph1_phy_gsr.v'))
foreach($name in @('preprocess_light_haze_row','preprocess_light_haze_restore4','preprocess_light_haze_rgb4')){
    $sources+=Join-Path $candidate "src_fpga/rtl/$name.v"
}
foreach($top in @('tb_s1_row','tb_s1_restore','tb_s1_wrapper')){$sources+=Join-Path $PSScriptRoot "$top.sv"}
$hashes=[ordered]@{}
foreach($f in @($models)+$macSources+$sources+@($PSCommandPath,(Join-Path $PSScriptRoot 'reference.py'))){
    $hashes[$f]=(Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant()
}
Push-Location $run
try {
    if(-not(Test-Path modelsim.ini)){& "$ModelSimBin/vmap.exe" -c | Out-Null}
    foreach($lib in @('ph1','work')) {
        if(-not(Test-Path $lib)){& "$ModelSimBin/vlib.exe" $lib | Out-Null}
        & "$ModelSimBin/vmap.exe" $lib $lib | Out-Null
    }
    & "$ModelSimBin/vlog.exe" -quiet -work ph1 -l models.log @models | Out-Null
    if($LASTEXITCODE -ne 0){throw 'TD models compile failed'}
    # Keep the generator's Verilog semantics. In -sv its constant-only
    # always @(*) instruction table can retain its zero initializer.
    & "$ModelSimBin/vlog.exe" -quiet -mfcu -work work -timescale 1ns/1ps -l mac_compile.log @macSources | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Unmodified vendor MAC compile failed'}
    & "$ModelSimBin/vlog.exe" -quiet -sv -work work '+define+PH1' -timescale 1ns/1ps -l compile.log @sources | Out-Null
    if($LASTEXITCODE -ne 0){throw 'S1 RTL compile failed'}
    $summary=@()
    foreach($top in @('tb_s1_row','tb_s1_restore','tb_s1_wrapper')) {
        & "$ModelSimBin/vsim.exe" -c -L ph1 work.PH1_PHY_GSR ph1.glbl "work.$top" "+ROOT=$($run.Replace('\','/'))" -l "$top.log" -do 'run -all; quit -f' | Out-Null
        $body=Get-Content "$top.log" -Raw
        if($LASTEXITCODE -ne 0 -or $body -notmatch 'RESULT: PASS' -or $body -match '\*\*\s+(Error|Fatal):'){throw "S1 self-check failed: $top"}
        $unexpected=@($body -split "`n" | Where-Object {$_ -match '\*\*\s+Warning:' -and
            $_ -notmatch 'fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0.v\(466\): \(vopt-(2685|2718)\) \[TFMPC\] - (Too few port connections|Missing connection)'})
        if($unexpected.Count){throw "Unclassified warning: $($unexpected -join '; ')"}
        $summary+=@($body -split "`n" | Where-Object {$_ -match 'RESULT: PASS'})
    }
    foreach($f in @('models.log','mac_compile.log','compile.log')) {
        if((Get-Content $f -Raw) -match '\*\*\s+(Warning|Error|Fatal):'){throw "Unexpected tool diagnostic: $f"}
    }
    foreach($f in $hashes.Keys) {
        if((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hashes[$f]){throw "Source changed: $f"}
    }
    [ordered]@{status='PASS';contract='S1-spatial-v1';td_root=$TdRoot;modelsim=$ModelSimBin;
        summary=$summary;inputs=$hashes;reference=(Get-Content reference.json -Raw | ConvertFrom-Json);
        synthesis='NOT_RUN';physical_timing='NOT_RUN';board='NOT_RUN'} |
        ConvertTo-Json -Depth 6 | Set-Content qualification.json -Encoding utf8
    $summary | Write-Output
} finally {Pop-Location}
