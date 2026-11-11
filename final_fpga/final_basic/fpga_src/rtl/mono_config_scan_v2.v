// Sparse candidate profile: legacy four-ROI analysis requests are unsupported.
`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
// Read every raw shadow word. Unsupported modes/owners are never advertised by
// module availability; both schema2 masks default to zero at the service top.
module mono_config_scan_v2 #(
    parameter integer WIDTH=1920,HEIGHT=1080,LANE_GAUSSIAN_ONLY=1,
    parameter [7:0] LEGACY_SUPPORTED=0,
    parameter [2:0] V2_SUPPORTED_MODES=0,
    parameter [5:0] V2_SUPPORTED_ENABLES=0
)(
    input wire clk,rst_n,cancel,
    input wire start_valid,output wire start_ready,input wire [31:0] start_mode,
    input wire word_valid,output wire word_ready,input wire [31:0] word_data,
    output reg result_valid,input wire result_ready,output reg [2:0] result_error
);
    `include "mono_config_transport_v2.vh"
    localparam [7:0] PROFILE_LEGACY_SUPPORTED = LEGACY_SUPPORTED & 8'hcf;
    wire legacy_start_ready,legacy_word_ready,legacy_result_valid;
    wire [2:0] legacy_error;
    reg scanning,waiting,shape_bad,value_bad,unsupported,legacy_unsupported;
    reg [4:0] index;
    reg [7:0] schema;
    reg [1:0] product_mode;
    reg [5:0] enables;
    reg [31:0] base_mode;
    assign start_ready=rst_n&&!cancel&&!scanning&&!waiting&&!result_valid&&legacy_start_ready;
    assign word_ready=rst_n&&!cancel&&scanning&&legacy_word_ready;
    wire start_fire=start_valid&&start_ready;
    wire word_fire=word_valid&&word_ready;
    mono_config_legacy_scan_v1 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.LANE_GAUSSIAN_ONLY(LANE_GAUSSIAN_ONLY)) legacy(
        .clk(clk),.rst_n(rst_n),.cancel(cancel),.start_valid(start_fire),.start_ready(legacy_start_ready),.start_mode(start_mode),
        .word_valid(word_fire),.word_ready(legacy_word_ready),.word_data(word_data),
        .result_valid(legacy_result_valid),.result_ready(waiting&&!result_valid),.result_error(legacy_error));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            scanning<=0;waiting<=0;index<=0;schema<=0;product_mode<=0;enables<=0;base_mode<=0;
            shape_bad<=0;value_bad<=0;unsupported<=0;legacy_unsupported<=0;result_valid<=0;result_error<=0;
        end else begin
            if(result_valid&&result_ready)result_valid<=0;
            if(start_fire)begin
                scanning<=1;waiting<=0;index<=0;base_mode<=start_mode;
                shape_bad<=0;value_bad<=0;unsupported<=0;legacy_unsupported<=0;
            end
            if(word_fire)begin
                if(index==0)begin
                    schema<=word_data[7:0];product_mode<=word_data[9:8];enables<=word_data[15:10];
                    legacy_unsupported<=(word_data[15:8]&~PROFILE_LEGACY_SUPPORTED)!=0;
                    shape_bad<=base_mode!=`PCIE_CFG_MODE_COLOR||word_data[31:16]!=0||
                        word_data[9:8]==`PCIE_CFG_V2_MODES_HDR_LZ_CONFLICT||(word_data[15]&&!word_data[14]);
                    unsupported<=!((V2_SUPPORTED_MODES>>word_data[9:8])&1'b1)||
                        (word_data[15:10]&~V2_SUPPORTED_ENABLES)!=0;
                end else begin
                    case(index)
                        2:if(product_mode==`PCIE_CFG_V2_MODES_MONO_HDR)begin
                            if(word_data[2:0]!=3'd4||word_data[12:3]!=10'd50||word_data[22:13]!=10'd50)value_bad<=1;
                        end else if(word_data!=0)value_bad<=1;
                        3:begin
                            if(word_data[31:13]!=0)shape_bad<=1;
                            if(product_mode==`PCIE_CFG_V2_MODES_MONO_HDR)begin
                                if(word_data[12:9]!=`PCIE_CFG_EXT_HDR_QUALIFICATION_REQUIRED)value_bad<=1;
                            end else if(word_data!=0)value_bad<=1;
                        end
                        4:if(product_mode!=`PCIE_CFG_V2_MODES_MONO_HDR&&word_data!=0)value_bad<=1;
                        // The RAW owner accepts a 32-bit delta and nonzero
                        // wait/age. Reject unsupported timers before COMMIT;
                        // delta low32 may be zero and remains unrestricted.
                        5:if(word_data!=0)value_bad<=1;
                        6,7:if(product_mode==`PCIE_CFG_V2_MODES_MONO_HDR ? word_data==0 : word_data!=0)value_bad<=1;
                        11:if(!mono_v2_dehaze_generation_valid(enables[1],word_data))value_bad<=1;
                        default:if(word_data!=0)shape_bad<=1;
                    endcase
                end
                if(index==31)begin scanning<=0;waiting<=1;end
                else index<=index+1'b1;
            end
            if(waiting&&legacy_result_valid&&!result_valid)begin
                waiting<=0;result_valid<=1;
                // Every non-schema2 byte pattern retains the old validator's
                // unsupported-before-invalid result, including bad schema bits.
                if(schema!=`PCIE_CFG_V2_SCHEMA)result_error<=legacy_unsupported?`PCIE_CFG_ERROR_UNSUPPORTED:legacy_error;
                else if(shape_bad)result_error<=`PCIE_CFG_ERROR_INVALID;
                else if(unsupported)result_error<=`PCIE_CFG_ERROR_UNSUPPORTED;
                else if(value_bad)result_error<=`PCIE_CFG_ERROR_INVALID;
                else result_error<=`PCIE_CFG_ERROR_OK;
            end
            if(cancel)begin scanning<=0;waiting<=0;result_valid<=0;index<=0;end
        end
    end
endmodule
