param(
    [string]$ModelSimBin = $env:MODELSIM_BIN,
    [string]$TdRoot = $env:TD_ROOT
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
. (Join-Path $PSScriptRoot "tool_paths.ps1")
$modelsim = Resolve-ModelSimBin -PreferredPath $ModelSimBin
$tdRoot = Resolve-TdRoot -PreferredPath $TdRoot -RequirePh1SimulationModels
$workDir = Join-Path $repo "tmp\modelsim\vendor_pcie_probe"
$vendor = Join-Path $repo "fpga_rtl\vendor\anlogic_pcie_sgdma"
$ph1 = Join-Path $tdRoot "sim_release\ph1"

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Push-Location $workDir
try {
    foreach ($library in @("ph1", "work")) {
        if (-not (Test-Path $library)) { & "$modelsim\vlib.exe" $library }
        & "$modelsim\vmap.exe" $library $library | Out-Null
    }

    # Explicit dependency closure for this PH1A PCIe x1 configuration.  In
    # particular, compile PCIe V3, not every multi-hundred-MiB SerDes model.
    $ph1Models = @(
        (Join-Path $tdRoot "sim_release\common\al_phy_glbl.v"),
        (Join-Path $ph1 "ph1_logic_clk.v"),
        (Join-Path $ph1 "ph1_logic_eram.v"),
        (Join-Path $ph1 "ph1_phy_gsr.v"),
        (Join-Path $ph1 "ph1_phy_gclk_v2.v"),
        (Join-Path $ph1 "ph1_phy_hclk.v"),
        (Join-Path $ph1 "ph1_phy_sclk_v2.v"),
        (Join-Path $ph1 "ph1_phy_pll.v"),
        (Join-Path $ph1 "ph1_phy_pcie_v3.sv")
    )
    & "$modelsim\vlog.exe" -work ph1 -sv -timescale 1ns/1ps @ph1Models 2>&1 |
        Tee-Object -FilePath "compile_ph1.log"
    if ($LASTEXITCODE -ne 0) { throw "PH1 PCIe model compilation failed; see compile_ph1.log" }

    $sources = @(
        (Join-Path $repo "fpga_rtl\pcie\c2h_frame_tx.v"),
        (Join-Path $repo "fpga_rtl\pcie\pcie_inband_header_adapter.v"),
        (Join-Path $repo "fpga_rtl\pcie\pcie_video_transport.v"),
        (Join-Path $repo "fpga_rtl\vendor\anlogic_soft_fifo_3_0\Soft_FIFO\RTL\soft_fifo.v"),
        (Join-Path $repo "fpga_rtl\pcie\axis_frame_fifo_ip.v"),
        (Join-Path $repo "fpga_rtl\pcie\pcie_sgdma_endpoint.v"),
        (Join-Path $vendor "sgdma\src_enc\sgdma_ip_all.enc.v"),
        (Join-Path $vendor "sgdma\bridge\case_ep\al_pcie_if_ep.v"),
        (Join-Path $vendor "sgdma\bridge\tx_if\axi4_st_mux.v"),
        (Join-Path $vendor "sgdma\bridge\tx_if\pcie_tx_client02rq_new.v"),
        (Join-Path $vendor "sgdma\bridge\tx_if\pcie_tx_client12cc.v"),
        (Join-Path $vendor "sgdma\bridge\rx_if\pcie_rx_bypass2rc.v"),
        (Join-Path $vendor "sgdma\bridge\rx_if\pcie_rx_trgt2cq.v"),
        (Join-Path $vendor "sgdma\bridge\sideband_if\pcie_sideband_dbi2mgmt.v"),
        (Join-Path $vendor "sgdma\bridge\sideband_if\pcie_sideband_msi.v"),
        (Join-Path $vendor "sgdma\sgdma_subsys.v"),
        (Join-Path $vendor "al_ip\PH1_LOGIC_PCIE_ph1_dbi_init_mux.v"),
        (Join-Path $vendor "al_ip\PH1_LOGIC_PCIE_ph1_pcie_basic_top.v"),
        (Join-Path $vendor "al_ip\PH1_LOGIC_PCIE_ph1_pcie_cfg_rom.v"),
        (Join-Path $vendor "al_ip\PH1_LOGIC_PCIE_ph1_pcie_clock_ctrl.v"),
        (Join-Path $vendor "al_ip\PH1_LOGIC_PCIE_ph1_pcie_core_pll.v"),
        (Join-Path $vendor "al_ip\PH1_LOGIC_PCIE.v"),
        (Join-Path $vendor "al_ip\sgdma_pll.v"),
        (Join-Path $repo "fpga_rtl\tb\tb_vendor_pcie_probe.v")
    )
    & "$modelsim\vlog.exe" -work work -timescale 1ns/1ps `
        "+incdir+$(Join-Path $repo 'fpga_rtl\include')" `
        "+define+AXI4ST_BUS_EN=1" "+define+AXI4L_MBUS_EN=1" `
        "+define+USR_IRQ_EN=1" "+define+MSI_EN=1'b1" "+define+PH1=1" `
        @sources 2>&1 | Tee-Object -FilePath "compile_design.log"
    if ($LASTEXITCODE -ne 0) { throw "Vendor SGDMA/design compilation failed; see compile_design.log" }

    # The V3 PHY model opens this generator-produced DBI initialization table
    # by basename at runtime.  Stage the reviewed collateral in ignored output.
    Copy-Item -LiteralPath (Join-Path $vendor "al_ip\al_pcie_ip.txt") `
        -Destination (Join-Path $workDir "al_pcie_ip.txt") -Force

    & "$modelsim\vsim.exe" -c -L ph1 work.tb_vendor_pcie_probe `
        -l "vendor_pcie_probe.log" -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { throw "Vendor PCIe probe failed to run" }

    $log = Get-Content -LiteralPath "vendor_pcie_probe.log" -Raw
    if ($log -notmatch "vendor PCIe/SGDMA model elaborated" -or
        $log -notmatch "RESULT: DIAGNOSTIC_NONPASS" -or
        $log -match "(?m)^# \*\* Error") {
        throw "Probe did not reach its bounded diagnostic endpoint"
    }
    Write-Output "[ModelSim/TD PH1 PCIe] RESULT: DIAGNOSTIC_NONPASS (elaboration/run probe only; no Root Complex)"
} finally {
    Pop-Location
}
