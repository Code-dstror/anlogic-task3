param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$TdRoot,
    [string]$ModelSimBin='D:/App/modelsim/win64'
)
$ErrorActionPreference='Stop'
if($Name -notmatch '^[A-Za-z0-9_-]+$'){throw 'Unsafe run name'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../../../..')).Path
$project=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$rtl=Join-Path $project 'src_fpga/rtl'
$ip=Join-Path $project 'src_fpga/ip'
. (Join-Path $repo 'src_fpga/simulation/tool_paths.ps1')
$td=Resolve-TdRoot -PreferredPath $TdRoot -RequirePh1SimulationModels
$ms=Resolve-ModelSimBin -PreferredPath $ModelSimBin
$run=Join-Path $project "tmp/camera1/$Name"
if(Test-Path -LiteralPath $run){throw "Preserve prior run: $run"}
New-Item -ItemType Directory -Path $run|Out-Null
$models=@('common/al_phy_glbl.v','ph1/ph1_logic_eram.v','ph1/ph1_logic_fifo.v',
    'ph1/ph1_phy_gclk_v2.v','ph1/ph1_logic_ramfifo.v','ph1/ph1_phy_eram.v','ph1/ph1_phy_fifoctrl.v')|
    ForEach-Object{Join-Path $td "sim_release/$_"}
$sources=@("$td/sim_release/ph1/ph1_phy_gsr.v",
    "$ip/camera_event_fifo_47x512/RTL/camera_event_fifo_47x512_soft_fifo_core.v", "$ip/camera_event_fifo_47x512/RTL/camera_event_fifo_47x512_soft_fifo.v",
    "$ip/camera_event_fifo_47x512/camera_event_fifo_47x512.v",
    "$ip/vendor/anlogic_camera/sensor/ui_imx415_reg.v",
    "$rtl/csi_rx_word_align_observed.v",
    "$ip/vendor/anlogic_camera/phy/csi_rx_word_gear_box.v",
    "$rtl/reset_release_sync.v","$rtl/camera_i2c_write.v","$rtl/imx415_mode_table.v",
    "$rtl/imx415_config.v","$rtl/imx415_sensor_recipe.v","$rtl/imx415_sensor_config.v",
    "$rtl/csi_clock_watchdog.v","$rtl/csi2_async_event_fifo.v",
    "$rtl/physical_csi_word_core.v","$rtl/physical_csi_rx_stream.v","$rtl/physical_camera_crop.v",
    "$ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v", "$ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v",
    "$ip/camera_packet_fifo_147x512/camera_packet_fifo_147x512.v",
    "$rtl/raw_capture_fifo_eram_safe.v","$rtl/hdr_csi_boundary_adapter.v",
    "$rtl/real_hdr_sensor_config.v","$rtl/imx415_hdr2_config_owner.v","$rtl/imx415_hdr2_recipe_rom.v",
    "$rtl/real_hdr_sensor_clock_mux.v","$rtl/real_hdr_event_cdc.v","$rtl/real_hdr_pair_cycle_gate.v",
    "$rtl/real_hdr_csi_word_core.v","$rtl/real_hdr_csi_dual_word_rx.v",
    "$rtl/real_hdr_member_crop10.v","$rtl/real_hdr_csi_capture_stream.v",
    "$rtl/real_hdr_physical_csi_rx.v","$rtl/sdr_camera_raw_frontend.v",
    "$PSScriptRoot/word_phy_boundary.sv","$PSScriptRoot/tb_camera1.sv")
$inputs=@($models+$sources+@($PSCommandPath,"$rtl/include/04_include/camera_physical_capture.vh","$rtl/include/04_include/pcie_protocol_v1.vh")|ForEach-Object{
    @{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLower()}})
$result=[ordered]@{status='RUNNING';td_root=$td;modelsim=$ms;inputs=$inputs;
    boundary='Electrical PHY and eye calibration only; actual watchdog, parser, official FIFO, crop and I2C run';
    synthesis='NOT_RUN';place_route='NOT_RUN';timing='NOT_RUN';board='NOT_RUN'}
Push-Location $run
try{
    & "$ms/vmap.exe" -c|Out-Null
    foreach($lib in @('work','ph1')){& "$ms/vlib.exe" $lib|Out-Null;& "$ms/vmap.exe" $lib $lib|Out-Null}
    & "$ms/vlog.exe" -quiet -work ph1 -l models.log @models|Out-Null
    if($LASTEXITCODE){throw 'Official FIFO models failed to compile'}
    & "$ms/vlog.exe" -quiet -sv -work work '+define+PH1' '+define+R8_STAGE1' "+incdir+$rtl/include/04_include" -l compile.log @sources|Out-Null
    if($LASTEXITCODE){throw 'Camera1 source compile failed'}
    & "$ms/vsim.exe" -c -L ph1 work.PH1_PHY_GSR ph1.glbl work.tb_camera1 -voptargs=+acc -l run.log -do 'run -all;quit -f'|
        ForEach-Object{if($_ -match 'RESULT:|FAIL|\*\* (Error|Fatal):'){Write-Output $_}}
    $logs=(@('models.log','compile.log','run.log')|ForEach-Object{Get-Content -LiteralPath $_ -Raw})-join"`n"
    if($LASTEXITCODE -or $logs -notmatch 'RESULT: PASS CAMERA1' -or $logs -match '\*\*\s+(Error|Fatal):'){
        throw 'Camera1 self-check failed'
    }
    $warnings=@($logs-split"`n"|Where-Object{$_ -match '\*\*\s+Warning:'})
    $unknown=@($warnings|Where-Object{$_ -notmatch "ph1_logic_eram\.v\(1287\): \(vopt-2697\) (MSB 172095|LSB 172024) of part-select into 'INIT_FILE' is out of bounds\."})
    if($unknown.Count){throw "Unclassified warnings: $($unknown-join';')"}
    foreach($item in $inputs){if((Get-FileHash -LiteralPath $item.path -Algorithm SHA256).Hash.ToLower()-ne$item.sha256){throw "Changed input: $($item.path)"}}
    $result.status='PASS';$result.metrics=@($logs-split"`n"|Where-Object{$_ -match 'RESULT: PASS CAMERA1'});$result.warnings=$warnings
}catch{$result.status='FAIL';$result.error=$_.Exception.Message;throw}
finally{
    $result.logs=@('models.log','compile.log','run.log')|Where-Object{Test-Path -LiteralPath $_}|ForEach-Object{
        @{path=(Join-Path $run $_);sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLower()}}
    $result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $run 'qualification.json') -Encoding utf8
    Pop-Location
}
Write-Output "Camera1 logs: $run"
