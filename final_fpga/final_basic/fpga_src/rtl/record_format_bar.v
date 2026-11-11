`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// USER BAR transaction owner; only a complete exact actual DFI ACK is terminal.
module record_format_bar #(
    parameter integer RECORD_V3_ENABLE=0,
    parameter integer NEUTRAL_STATS_ENABLE=0
) (
    input wire clk,rst_n,stream_ready,
    input wire write_valid,
    input wire [11:0] write_offset,
    input wire [31:0] write_data,
    input wire [3:0] write_strobes,
    output wire [1:0] write_response,
    input wire read_valid,
    input wire [11:0] read_offset,
    output reg read_response_valid,
    output reg [31:0] read_data,
    output reg [1:0] read_response,
    input wire [31:0] i_user_source_session,
    input wire i_user_source_session_ready,
    input wire i_app_enable,i_c2h_running,i_tx_busy,i_source_functional_quiescent,
    input wire i_session_armed,i_rearm_ready,
    output reg [146:0] cmd_data,
    output reg cmd_valid,
    input wire cmd_ready,
    input wire [146:0] rsp_data,
    input wire rsp_valid,
    output wire rsp_ready,
    output wire o_user_busy,
    output reg [15:0] o_user_selected_version,o_user_selected_header_length,
    output reg [31:0] o_user_selection_epoch,o_stale_ack_count
);
    reg owned,done,failed;
    reg [31:0] request_version,request_sequence,request_session;
    reg [31:0] response_sequence,response_session,error_code;
    wire user_boundary=!i_app_enable && !i_c2h_running && !i_tx_busy &&
        i_source_functional_quiescent && !i_session_armed && i_rearm_ready;
    wire request_field=write_offset==`PCIE_REG_RECORD_REQUEST_VERSION ||
        write_offset==`PCIE_REG_RECORD_REQUEST_SEQUENCE || write_offset==`PCIE_REG_RECORD_REQUEST_SESSION;
    wire command_field=write_offset==`PCIE_REG_RECORD_COMMAND;
    wire write_allowed=write_offset[1:0]==0 && !owned &&
        (request_field || (command_field && write_strobes==15 && write_data==`PCIE_RECORD_V2_COMMAND_SELECT));
    assign write_response=write_allowed ? 2'b00 : 2'b10;
    assign rsp_ready=stream_ready;
    assign o_user_busy=owned;
    wire [2:0] ack_error=rsp_data[66:64];
    wire [15:0] ack_header=rsp_data[82:67],ack_version=rsp_data[98:83];
    wire [31:0] ack_epoch=rsp_data[130:99];
    wire ack_shape=rsp_data[146:131]==0 && ack_error<=`PCIE_RECORD_V2_ERROR_RESET &&
        ((ack_version==`PCIE_PROTOCOL_VERSION && ack_header==`PCIE_HEADER_LENGTH) ||
         (ack_version==`PCIE_RECORD_V2_VERSION && ack_header==`PCIE_RECORD_V2_HEADER_LENGTH) ||
         (RECORD_V3_ENABLE && ack_version==`PCIE_RECORD_V4_VERSION && ack_header==`PCIE_RECORD_V4_HEADER_LENGTH));
    // A held, not-yet-enqueued command cannot have a real DFI decision ACK.
    wire ack_match=owned && !cmd_valid && ack_shape && rsp_data[31:0]==cmd_data[31:0] &&
        rsp_data[63:32]==cmd_data[63:32] &&
        (ack_error!=0 || {16'd0,ack_version}==cmd_data[95:64]);
    reg [31:0] register_value;
    reg read_known;
    function [31:0] merge;
        input [31:0] old_value,new_value;
        input [3:0] strobes;
        integer n;
        begin merge=old_value;for(n=0;n<4;n=n+1)if(strobes[n])merge[n*8+:8]=new_value[n*8+:8];end
    endfunction
    always @(*)begin
        register_value=0;read_known=read_offset[1:0]==0;
        case(read_offset)
            `PCIE_REG_RECORD_MAGIC:register_value=`PCIE_RECORD_V2_MAGIC;
            `PCIE_REG_RECORD_ABI_VERSION:register_value=`PCIE_RECORD_V2_ABI_VERSION;
            `PCIE_REG_RECORD_FEATURES:register_value=
                (32'd1<<`PCIE_RECORD_V2_FEATURE_VERSION2) |
                (32'd1<<`PCIE_RECORD_V2_FEATURE_SOURCE_STAMP) |
                (NEUTRAL_STATS_ENABLE ? (32'd1<<`PCIE_RECORD_V2_FEATURE_NEUTRAL_STATS) : 32'd0) |
                (RECORD_V3_ENABLE ? (32'd1<<`PCIE_RECORD_V4_FEATURE_VERSION4) |
                 (32'd1<<`PCIE_RECORD_V4_FEATURE_LANE_POINTS) : 32'd0);
            `PCIE_REG_RECORD_SUPPORTED_VERSIONS:register_value=RECORD_V3_ENABLE ? `PCIE_RECORD_V4_SUPPORTED_VERSIONS : `PCIE_RECORD_V2_SUPPORTED_VERSIONS;
            `PCIE_REG_RECORD_REQUEST_VERSION:register_value=request_version;
            `PCIE_REG_RECORD_REQUEST_SEQUENCE:register_value=request_sequence;
            `PCIE_REG_RECORD_REQUEST_SESSION:register_value=request_session;
            `PCIE_REG_RECORD_COMMAND:register_value=0;
            `PCIE_REG_RECORD_STATUS:register_value={29'd0,failed,done,owned};
            `PCIE_REG_RECORD_RESPONSE_SEQUENCE:register_value=response_sequence;
            `PCIE_REG_RECORD_RESPONSE_SESSION:register_value=response_session;
            `PCIE_REG_RECORD_ERROR:register_value=error_code;
            `PCIE_REG_RECORD_SELECTED_VERSION:register_value={16'd0,o_user_selected_version};
            `PCIE_REG_RECORD_SELECTED_HEADER_LENGTH:register_value={16'd0,o_user_selected_header_length};
            `PCIE_REG_RECORD_SELECTION_EPOCH:register_value=o_user_selection_epoch;
            default:read_known=0;
        endcase
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            owned<=0;done<=0;failed<=0;request_version<=1;request_sequence<=0;request_session<=0;
            response_sequence<=0;response_session<=0;error_code<=0;cmd_data<=0;cmd_valid<=0;
            o_user_selected_version<=`PCIE_PROTOCOL_VERSION;o_user_selected_header_length<=`PCIE_HEADER_LENGTH;
            o_user_selection_epoch<=0;o_stale_ack_count<=0;read_response_valid<=0;read_data<=0;read_response<=0;
        end else begin
            read_response_valid<=read_valid;
            if(read_valid)begin read_data<=register_value;read_response<=read_known?2'b00:2'b10;end
            if(cmd_valid&&cmd_ready)cmd_valid<=0;
            if(rsp_valid&&rsp_ready)begin
                if(!ack_match)begin if(!(&o_stale_ack_count))o_stale_ack_count<=o_stale_ack_count+1'b1;end
                else begin
                    owned<=0;done<=1;
                    response_sequence<=rsp_data[31:0];response_session<=rsp_data[63:32];
                    o_user_selected_version<=ack_version;o_user_selected_header_length<=ack_header;o_user_selection_epoch<=ack_epoch;
                    if(!i_user_source_session_ready || !i_user_source_session ||
                       i_user_source_session!=cmd_data[63:32])begin
                        failed<=1;error_code<=`PCIE_RECORD_V2_ERROR_SESSION;
                    end else if(!user_boundary)begin failed<=1;error_code<=`PCIE_RECORD_V2_ERROR_BUSY;end
                    else begin failed<=ack_error!=0;error_code<={29'd0,ack_error};end
                end
            end
            if(write_valid&&write_allowed)begin
                if(request_field)begin
                    case(write_offset)
                        `PCIE_REG_RECORD_REQUEST_VERSION:request_version<=merge(request_version,write_data,write_strobes);
                        `PCIE_REG_RECORD_REQUEST_SEQUENCE:request_sequence<=merge(request_sequence,write_data,write_strobes);
                        `PCIE_REG_RECORD_REQUEST_SESSION:request_session<=merge(request_session,write_data,write_strobes);
                        default:begin end
                    endcase
                end else begin
                    response_sequence<=request_sequence;response_session<=request_session;done<=1;failed<=1;
                    if(!stream_ready)error_code<=`PCIE_RECORD_V2_ERROR_RESET;
                    else if(!request_sequence)error_code<=`PCIE_RECORD_V2_ERROR_INVALID;
                    else if(request_version!=`PCIE_PROTOCOL_VERSION && request_version!=`PCIE_RECORD_V2_VERSION &&
                        (!RECORD_V3_ENABLE || request_version!=`PCIE_RECORD_V4_VERSION))
                        error_code<=`PCIE_RECORD_V2_ERROR_UNSUPPORTED;
                    else if(!i_user_source_session_ready || !i_user_source_session || request_session!=i_user_source_session)
                        error_code<=`PCIE_RECORD_V2_ERROR_SESSION;
                    else if(!user_boundary)error_code<=`PCIE_RECORD_V2_ERROR_BUSY;
                    else begin
                        cmd_data<={51'd0,request_version,request_session,request_sequence};cmd_valid<=1;
                        owned<=1;done<=0;failed<=0;error_code<=0;
                    end
                end
            end
        end
    end
endmodule
