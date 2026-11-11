#-----------------------------------------------------------------------------
# Timing constraints for PH1A60GEG324 demo
# Board clock is 50 MHz -> 20 ns period
#-----------------------------------------------------------------------------
create_clock -name sys_clk -period 20.000 [get_ports {i_clk}]

# Reset is asynchronous to the clock; treat as a false path on the input.
set_false_path -from [get_ports {i_rst_n}]

# Outputs are not timing-critical for this demo; relax them.
set_false_path -to [get_ports {o_uart_tx}]
set_false_path -to [get_ports {o_led}]
set_false_path -to [get_ports {o_uart_busy}]
