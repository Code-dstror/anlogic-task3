# Physical clocks for the 24 MHz INCK / 720 Mb/s-per-lane profile.
create_clock -name sys_clk -period 40.000 [get_ports {sys_clk}]
create_clock -name mipi_ref_clk -period 10.000 [get_ports {mipi_ref_clk_p}]
create_clock -name mipi_hs_clk -period 2.777778 [get_ports {mipi_clk_hs_rx_p}]
derive_clocks
# Different oscillators plus recovered camera clock. Related PLL outputs are
# deliberately in the same group. Data crosses through official async FIFO;
# stable enable/reset/status cross through explicit synchronizers.
set_clock_groups -asynchronous \
    -group [get_clocks {sys_clk u_pixel_pll/pll_inst.clkc[0]}] \
    -group [get_clocks {mipi_ref_clk u_camera_pll/pll_inst.clkc[0] u_camera_pll/pll_inst.clkc[1] u_camera_pll/pll_inst.clkc[2]}] \
    -group [get_clocks {mipi_hs_clk u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_0.clkdivout u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_0.clkout}]
# Board data-eye constraints and automatic delay-window margin require real
# FMC/sensor signal characterization; no guessed input delays are supplied.
