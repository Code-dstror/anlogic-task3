`timescale 1ns / 1ps

// Serialize ring control through two official 40-bit FIFO message channels.
module jpeg_frame_service (
    input wire i_user_clk, i_user_rst_n, i_dfi_clk, i_dfi_rst_n,
    input wire [31:0] i_user_session_id,
    input wire i_user_initialized, i_ddr_ready,
    input wire i_bar_write_valid, input wire [11:0] i_bar_write_offset,
    input wire [31:0] i_bar_write_data, input wire [3:0] i_bar_write_strobes,
    output wire [1:0] o_bar_write_response,
    input wire i_bar_read_valid, input wire [11:0] i_bar_read_offset,
    output wire o_bar_read_response_valid, output wire [31:0] o_bar_read_data,
    output wire [1:0] o_bar_read_response,
    output wire o_req_valid, input wire i_req_ready,
    output wire [1:0] o_req_op, output wire o_req_camera,
    output wire [15:0] o_req_slot,
    output wire [31:0] o_req_generation, o_req_session,
    input wire i_rsp_valid, output wire o_rsp_ready,
    input wire [3:0] i_rsp_code, input wire [15:0] i_rsp_slot,
    input wire [31:0] i_rsp_generation, i_rsp_session, i_rsp_epoch, i_rsp_capture_id,
    input wire i_rsp_camera, input wire [7:0] i_rsp_quality,
    input wire [15:0] i_rsp_width, i_rsp_height,
    input wire [24:0] i_rsp_payload_length,
    input wire i_rsp_pinned, input wire [2:0] i_rsp_state,
    output wire o_user_ready, o_dfi_ready
);
    wire paired_reset=i_user_rst_n&&i_dfi_rst_n;
    wire user_reset,dfi_reset;
    reset_release_sync u_user_reset(.i_clk(i_user_clk),.i_async_rst_n(paired_reset),.o_rst_n(user_reset));
    reset_release_sync u_dfi_reset(.i_clk(i_dfi_clk),.i_async_rst_n(paired_reset),.o_rst_n(dfi_reset));
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] ddr_ready_sync;
    always @(posedge i_user_clk or negedge user_reset)
        if(!user_reset) ddr_ready_sync<=0;else ddr_ready_sync<={ddr_ready_sync[0],i_ddr_ready};
    wire [146:0] command_source,command_sink,response_source,response_sink;
    wire command_source_valid,command_source_ready,command_sink_valid,command_sink_ready;
    wire response_source_valid,response_source_ready,response_sink_valid,response_sink_ready;
    wire cmd_user_done,cmd_dfi_done,rsp_user_done,rsp_dfi_done;
    assign o_user_ready=cmd_user_done&&rsp_user_done&&ddr_ready_sync[1]&&i_user_initialized;
    assign o_dfi_ready=cmd_dfi_done&&rsp_dfi_done&&i_ddr_ready;
    control_message_fifo_ip #(.MESSAGE_WIDTH(147)) u_command_fifo(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_user_clk),.i_source_rst_n(user_reset),.i_source_data(command_source),
        .i_source_valid(command_source_valid),.o_source_ready(command_source_ready),.o_source_reset_done(cmd_user_done),
        .i_sink_clk(i_dfi_clk),.i_sink_rst_n(dfi_reset),.o_sink_data(command_sink),.o_sink_valid(command_sink_valid),
        .i_sink_ready(command_sink_ready),.o_sink_reset_done(cmd_dfi_done));
    control_message_fifo_ip #(.MESSAGE_WIDTH(147)) u_response_fifo(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_dfi_clk),.i_source_rst_n(dfi_reset),.i_source_data(response_source),
        .i_source_valid(response_source_valid),.o_source_ready(response_source_ready),.o_source_reset_done(rsp_dfi_done),
        .i_sink_clk(i_user_clk),.i_sink_rst_n(user_reset),.o_sink_data(response_sink),.o_sink_valid(response_sink_valid),
        .i_sink_ready(response_sink_ready),.o_sink_reset_done(rsp_user_done));
    jpeg_frame_bar u_bar(.i_clk(i_user_clk),.i_rst_n(i_user_rst_n),.i_stream_ready(o_user_ready),
        .i_session_initialized(i_user_initialized),.i_session_id(i_user_session_id),
        .i_write_valid(i_bar_write_valid),.i_write_offset(i_bar_write_offset),.i_write_data(i_bar_write_data),.i_write_strobes(i_bar_write_strobes),
        .o_write_response(o_bar_write_response),.i_read_valid(i_bar_read_valid),.i_read_offset(i_bar_read_offset),
        .o_read_response_valid(o_bar_read_response_valid),.o_read_data(o_bar_read_data),.o_read_response(o_bar_read_response),
        .o_command_data(command_source),.o_command_valid(command_source_valid),.i_command_ready(command_source_ready),
        .i_response_data(response_sink),.i_response_valid(response_sink_valid),.o_response_ready(response_sink_ready));
    reg response_busy,response_part;
    reg [127:0] response0,response1;
    assign o_req_valid=command_sink_valid&&o_dfi_ready&&!response_busy;
    assign command_sink_ready=i_req_ready&&o_dfi_ready&&!response_busy;
    assign o_req_op=command_sink[1:0];assign o_req_camera=command_sink[2];
    assign o_req_slot=command_sink[18:3];assign o_req_generation=command_sink[50:19];assign o_req_session=command_sink[82:51];
    assign o_rsp_ready=o_dfi_ready&&!response_busy;
    assign response_source_valid=response_busy;
    assign response_source={1'b0,response_part,17'd0,response_part?response1:response0};
    always @(posedge i_dfi_clk or negedge dfi_reset) begin
        if(!dfi_reset) begin response_busy<=0;response_part<=0;response0<=0;response1<=0;end
        else begin
            if(i_rsp_valid&&o_rsp_ready) begin
                response_busy<=1;response_part<=0;
                response0<={i_rsp_session,i_rsp_generation,i_rsp_epoch,i_rsp_capture_id};
                response1<={38'd0,i_rsp_code,i_rsp_state,i_rsp_pinned,i_rsp_camera,i_rsp_slot,
                            i_rsp_quality,i_rsp_height,i_rsp_width,i_rsp_payload_length};
            end
            if(response_source_valid&&response_source_ready) begin
                if(response_part) response_busy<=0;else response_part<=1;
            end
        end
    end
endmodule
