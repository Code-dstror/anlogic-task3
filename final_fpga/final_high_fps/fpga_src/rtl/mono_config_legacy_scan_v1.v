`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
`ifndef F21_AUTO_FIXED_LUT_PROFILE
`define F21_AUTO_FIXED_LUT_PROFILE 0
`endif
// Dedicated exact sequential qualification of the current FULL/HDR preset
// contract. All 1024 arbitrary shadow bits are read before any success.
// This is not a compressor: malformed omitted bits remain an error.
module mono_config_legacy_scan_v1 #(
    parameter integer WIDTH=1920,HEIGHT=1080,LANE_GAUSSIAN_ONLY=1
) (
    input wire clk,rst_n,cancel,
    input wire start_valid,output wire start_ready,input wire [31:0] start_mode,
    input wire word_valid,output wire word_ready,input wire [31:0] word_data,
    output reg result_valid,input wire result_ready,output reg [2:0] result_error
);
    `include "legacy_stage2_config_transport.vh"
    localparam [1023:0] FULL_PATTERN=stage2_unpack_extension(208'd3);
    reg scanning;
    reg [4:0] word_index;
    reg [7:0] features;
    reg [31:0] mode;
    reg preset_bad,value_bad;
    wire hdr=features[`PCIE_CFG_EXT_FEATURE_HDR];
    wire dehaze=features[`PCIE_CFG_EXT_FEATURE_DEHAZE];
    wire lane=features[`PCIE_CFG_EXT_FEATURE_F22]||features[`PCIE_CFG_EXT_FEATURE_F23];
    wire [7:0] first_features=word_data[15:8];
    wire [7:0] base_features=first_features&8'hfb;
    wire feature_form=base_features==0||base_features==8'h08||base_features==8'h30||base_features==8'h38;
    wire hdr_geometry=WIDTH>=8&&WIDTH%4==0&&HEIGHT>=3;
    wire dehaze_geometry=WIDTH>=6&&WIDTH<=1920&&WIDTH%6==0&&HEIGHT>=6&&HEIGHT<=1080&&HEIGHT%6==0;
    // The authenticated four-strip FULL preset has last Y=270 and right=480.
    // These checks retain the old general validator's compiled-image limits.
    wire lane_geometry=WIDTH>=4&&WIDTH<=3840&&WIDTH%4==0&&HEIGHT>=1&&HEIGHT<=2160&&
        (WIDTH+3)/4>=480&&(HEIGHT+3)/4>=270;
    wire geometry_ok=(!hdr||hdr_geometry)&&(!dehaze||dehaze_geometry)&&(!lane||lane_geometry);
    wire mode_unsupported=LANE_GAUSSIAN_ONLY!=0&&lane&&mode!=32'd2;
    reg word_matches;
    always @*begin
        word_matches=1;
        case(word_index)
            0:word_matches=word_data[31:16]==0&&feature_form&&word_data[7:0]==(first_features==0?8'd0:8'd1);
            1:word_matches=word_data==0;
            2:word_matches=hdr ? word_data[2:0]==3'd4&&word_data[12:3]==10'd50&&word_data[22:13]==10'd50 : word_data==0;
            3:word_matches=hdr ? word_data[31:13]==0&&word_data[12:9]==`PCIE_CFG_EXT_HDR_QUALIFICATION_REQUIRED : word_data==0;
            4,5,6,7:word_matches=hdr||word_data==0;
            8:word_matches=word_data==(dehaze?FULL_PATTERN[256+:32]:32'd0);
            9:word_matches=word_data==(dehaze?FULL_PATTERN[288+:32]:32'd0);
            10:word_matches=word_data==(dehaze?FULL_PATTERN[320+:32]:32'd0);
            11:word_matches=dehaze?(`F21_AUTO_FIXED_LUT_PROFILE?word_data==1:word_data!=0):word_data==0;
            default:word_matches=word_data==(lane?FULL_PATTERN[word_index*32+:32]:32'd0);
        endcase
    end
    assign start_ready=rst_n&&!scanning&&!result_valid&&!cancel;
    assign word_ready=rst_n&&scanning&&!cancel;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin scanning<=0;word_index<=0;features<=0;mode<=0;preset_bad<=0;value_bad<=0;result_valid<=0;result_error<=0;end
        else begin
            if(result_valid&&result_ready)result_valid<=0;
            if(start_valid&&start_ready)begin scanning<=1;word_index<=0;features<=0;mode<=start_mode;preset_bad<=0;value_bad<=0;end
            if(word_valid&&word_ready)begin
                if(word_index==0)features<=first_features;
                if(!word_matches)preset_bad<=1;
                // Keep legacy preset/unsupported priority. Pure timer range
                // errors are INVALID, matching the current RAW owner limits.
                if(hdr&&((word_index==5&&word_data!=0)||
                    ((word_index==6||word_index==7)&&word_data==0)))value_bad<=1;
                if(word_index==31)begin
                    scanning<=0;result_valid<=1;
                    if(preset_bad||!word_matches||mode_unsupported)result_error<=`PCIE_CFG_ERROR_UNSUPPORTED;
                    else if(features==0||!geometry_ok||value_bad)result_error<=`PCIE_CFG_ERROR_INVALID;
                    else result_error<=`PCIE_CFG_ERROR_OK;
                end else word_index<=word_index+1'b1;
            end
            if(cancel)begin scanning<=0;result_valid<=0;word_index<=0;end
        end
    end
endmodule
