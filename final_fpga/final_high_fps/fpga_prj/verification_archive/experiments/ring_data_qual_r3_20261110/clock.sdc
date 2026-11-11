create_clock -name DFI -period 7.502 -waveform {0.229 3.980} [get_ports clk]
create_clock -name PIX -period 8.000 -waveform {0.000 4.000} [get_ports pixel_clk]
