`timescale 1ns/1ps
`default_nettype none
// Controlled derivative of the H12 sensor clock selector. Both PLL outputs
// run continuously. The owner holds XCLR low for the existing 16 cfg clocks
// while selection settles; selection is admitted only after owners drain.
module real_hdr_sensor_clock_mux (
    input wire i_sdr_clk,
    input wire i_hdr_clk,
    input wire i_reset_n,
    input wire i_select_hdr,
    output wire o_clk
);
    // UG910 v1.7 PDF62-64: active-low one-hot selection, no dynamic CE,
    // drct=00 uses the primitive's mutual exclusion for glitchless switching.
    // All deselected on reset. NEG/NO holds a deselected output low in the
    // selected TD2026.2 model; finishing a pulse may take input-clock edges.
    wire [1:0] select_n;
    assign select_n = i_reset_n ? {~i_select_hdr,i_select_hdr} : 2'b11;
    PH1_PHY_GCLK_V2 #(
        .PRESELECT("CLK0"),
        .HOLD("NO"),
        .SEL_TRIGGER("NEG"),
        .GSR("DISABLE")
    ) u_sensor_gclk (
        .clkin({i_hdr_clk,i_sdr_clk}),
        .seln(select_n),
        .cen(2'b00),
        .drct(2'b00),
        .clkout(o_clk)
    );
endmodule
`default_nettype wire
