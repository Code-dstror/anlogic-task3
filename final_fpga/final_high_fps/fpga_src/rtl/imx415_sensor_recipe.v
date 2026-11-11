`timescale 1ns/1ps
`include "rate_control_v1.vh"
`include "geometry_control_v1.vh"

// One ordered recipe interface. Existing SDR/HDR register order is retained;
// only the selected SDR rate and reset-applied gain override register values.
module imx415_sensor_recipe #(
    parameter integer MODE_4K=0,
    parameter integer RUNTIME_GAIN_ENABLE=1, UHD_ENABLE=0
)(
    input wire [7:0] i_index,
    input wire i_hdr,
    input wire [2:0] i_sdr_profile,
    input wire [7:0] i_gain_code,
    output reg [23:0] o_register,
    output wire o_wait, o_last
);
    wire [23:0] sdr_register,hdr_register;
    wire hdr_wait,hdr_last;
    reg [11:0] sdr_hmax,sdr_shr0;
    reg override_timing;
    wire sensor_uhd15=UHD_ENABLE!=0&&i_sdr_profile==`GEOMETRY_SENSOR_UHD15;
    wire sensor_uhd20=UHD_ENABLE!=0&&i_sdr_profile==`GEOMETRY_SENSOR_UHD20;
    imx415_mode_table #(.MODE_4K(MODE_4K),.RUNTIME_GEOMETRY_ENABLE(UHD_ENABLE)) u_sdr(
        .i_index(i_index),.i_uhd(sensor_uhd15||sensor_uhd20),.o_register(sdr_register));
    imx415_hdr2_recipe_rom u_hdr(.i_index(i_index),.o_register(hdr_register),
        .o_wait_24ms(hdr_wait),.o_last(hdr_last));
    assign o_wait=i_hdr ? hdr_wait : i_index==8'd201;
    assign o_last=i_hdr ? hdr_last : i_index==8'd202;
    // Keep exposure near 16.6 ms at the unchanged sensor/lane clocks.
    // UHD15 and UHD20 share the line period and 746 lines of integration.
    always @* begin
        override_timing=1'b1;
        case(i_sdr_profile)
            `GEOMETRY_SENSOR_UHD15,`GEOMETRY_SENSOR_UHD20:begin
                sdr_hmax=12'd1600;
                sdr_shr0=sensor_uhd20 ? 12'd1504 : 12'd2254;
                override_timing=UHD_ENABLE!=0;
            end
            `RATE_SENSOR_PROFILE_LEGACY_30:begin sdr_hmax=11'd1066;sdr_shr0=11'd1129;end
            `PCIE_RATE_CODE_FPS40:begin sdr_hmax=11'd800;sdr_shr0=11'd757;end
            `PCIE_RATE_CODE_FPS45:begin sdr_hmax=11'd711;sdr_shr0=11'd570;end
            `PCIE_RATE_CODE_FPS48:begin sdr_hmax=11'd667;sdr_shr0=11'd459;end
            default:begin override_timing=1'b0;sdr_hmax=0;sdr_shr0=0;end
        endcase
    end
    always @* begin
        o_register=sdr_register;
        if(RUNTIME_GAIN_ENABLE!=0)begin
            case(sdr_register[23:8])
                16'h3090:o_register={16'h3090,i_gain_code};
                16'h3091:o_register=24'h309100;
                default:begin end
            endcase
        end
        if(MODE_4K==0 && override_timing)begin
            case(sdr_register[23:8])
                16'h3028:o_register={16'h3028,sdr_hmax[7:0]};
                16'h3029:o_register={16'h3029,4'd0,sdr_hmax[11:8]};
                16'h3050:o_register={16'h3050,sdr_shr0[7:0]};
                16'h3051:o_register={16'h3051,4'd0,sdr_shr0[11:8]};
                16'h3052:o_register=24'h305200;
                default:begin end
            endcase
        end
        // UHD20 keeps the all-pixel table's VMAX of 2250.
        if(sensor_uhd15)case(sdr_register[23:8])
            16'h3024:o_register=24'h3024b8;
            16'h3025:o_register=24'h30250b;
            16'h3026:o_register=24'h302600;
            default:begin end
        endcase
        if(i_index==8'd201)o_register=24'h300000;
        if(i_index==8'd202)o_register=24'h300200;
        if(i_hdr)o_register=hdr_register;
    end
endmodule
