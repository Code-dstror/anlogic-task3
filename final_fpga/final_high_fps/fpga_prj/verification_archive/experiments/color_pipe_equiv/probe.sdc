create_clock -name PIX -period 8.000 [get_ports clk]
set_clock_uncertainty -hold 0.050 [get_clocks PIX]
