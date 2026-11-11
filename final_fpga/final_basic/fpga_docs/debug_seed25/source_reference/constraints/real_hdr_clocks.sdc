# IMX415 physical SDR/HDR: constrain the faster HDR receive rate.
create_clock -name sys_clk_25m -period 40.000 [get_ports {sys_clk}]
create_clock -name board_ref_clk_100m -period 10.000 [get_ports {board_ref_clk_100m}]
create_clock -name mipi_hs_clk -period 2.222222 [get_ports {mipi_clk_hs_rx_p}]
derive_clocks

# TD2026.2 adds this SDC component to each min-check default. Reserve an
# extra 50ps for the measured near-zero PIX/USER hold paths; setup and the
# existing clock periods stay unchanged. Recheck local removal after route.
set_clock_uncertainty -hold 0.050 [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
set_clock_uncertainty -hold 0.050 [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}]

# DDR_DFI_HOLD_GUARD_BEGIN
# 312ef57e routed evidence: all 128 endpoints have active min guards, but
# seed13 still reports -0.211/-0.232 ns at dfi_wrdata[216]/[222]. Tighten
# this same fixed connected bus to give hold repair 250 ps more target margin.
# A routed path meeting this 0.350 ns guard also meets the former 0.100 ns
# target. Existing shown setup paths have >=4.521 ns margin; this is not an
# all-bit setup guarantee. Recheck all 128 max/min paths after the new route.
# Keep library hold, skew, uncertainty, setup checks and frozen DDR IP intact.
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[0]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[1]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[2]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[3]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[4]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[5]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[6]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[7]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[8]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[9]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[10]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[11]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[12]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[13]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[14]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[15]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[72]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[73]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[74]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[75]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[76]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[77]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[78]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[79]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[80]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[81]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[82]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[83]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[84]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[85]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[86]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[87]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[144]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[145]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[146]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[147]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[148]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[149]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[150]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[151]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[152]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[153]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[154]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[155]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[156]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[157]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[158]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[159]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[216]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[217]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[218]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[219]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[220]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[221]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[222]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[223]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[224]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[225]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[226]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[227]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[228]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[229]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[230]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[231]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[288]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[289]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[290]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[291]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[292]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[293]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[294]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[295]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[296]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[297]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[298]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[299]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[300]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[301]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[302]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[303]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[360]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[361]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[362]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[363]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[364]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[365]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[366]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[367]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[368]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[369]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[370]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[371]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[372]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[373]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[374]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[375]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[432]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[433]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[434]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[435]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[436]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[437]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[438]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[439]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[440]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[441]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[442]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[443]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[444]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[445]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[446]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[447]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[504]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[505]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[506]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[507]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[508]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[509]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[510]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[511]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[512]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[513]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[514]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[515]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[516]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[517]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[518]}] 0.350
set_min_delay -to [get_pins {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[519]}] 0.350
# DDR_DFI_HOLD_GUARD_END
