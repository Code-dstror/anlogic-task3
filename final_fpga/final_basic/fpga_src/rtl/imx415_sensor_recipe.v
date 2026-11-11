`timescale 1ns/1ps

// One ordered recipe interface. Existing SDR/HDR register order is retained;
// only the selected SDR rate and reset-applied gain override register values.
module imx415_sensor_recipe #(
    parameter integer MODE_4K=0,
    parameter integer RUNTIME_GAIN_ENABLE=1
)(
    input wire [7:0] i_index,
    input wire i_hdr, i_sdr_30,
    input wire [7:0] i_gain_code,
    output reg [23:0] o_register,
    output wire o_wait, o_last
);
    wire [23:0] sdr_register,hdr_register;
    wire hdr_wait,hdr_last;
    imx415_mode_table #(.MODE_4K(MODE_4K)) u_sdr(
        .i_index(i_index),.o_register(sdr_register));
    imx415_hdr2_recipe_rom u_hdr(.i_index(i_index),.o_register(hdr_register),
        .o_wait_24ms(hdr_wait),.o_last(hdr_last));
    assign o_wait=i_hdr ? hdr_wait : i_index==8'd201;
    assign o_last=i_hdr ? hdr_last : i_index==8'd202;
    always @* begin
        o_register=sdr_register;
        if(RUNTIME_GAIN_ENABLE!=0)begin
            case(sdr_register[23:8])
                16'h3090:o_register={16'h3090,i_gain_code};
                16'h3091:o_register=24'h309100;
                default:begin end
            endcase
        end
        // Same 24 MHz MCLK / 720 Mb/s lanes / RAW10 binning. HMAX doubles
        // the line period; VMAX and geometry remain the existing values.
        if(MODE_4K==0 && i_sdr_30)begin
            case(sdr_register[23:8])
                16'h3028:o_register=24'h30282a;
                16'h3029:o_register=24'h302904;
                // Preserve integration: (2250-8)*H == (2250-1129)*(2H).
                16'h3050:o_register=24'h305069;
                16'h3051:o_register=24'h305104;
                16'h3052:o_register=24'h305200;
                default:begin end
            endcase
        end
        if(i_index==8'd201)o_register=24'h300000;
        if(i_index==8'd202)o_register=24'h300200;
        if(i_hdr)o_register=hdr_register;
    end
endmodule
