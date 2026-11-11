`timescale 1ns / 1ps
`include "raw_video_v1.vh"

// The RAW owner holds its descriptor and its offered payload until handshake.
module raw_video_record_formatter #(
    parameter integer SEPARATE_DATA_RESET=0
) (
    input wire i_clk,i_rst_n,
    input wire i_start_valid,output wire o_start_ready,
    input wire i_abort,output wire o_drained,
    input wire [31:0] i_payload_bytes,
    input wire [15:0] i_width,i_height,
    input wire [31:0] i_sequence,i_session,i_epoch,
    input wire i_camera,input wire [1:0] i_bayer_phase,input wire i_time_valid,
    input wire [63:0] i_capture_time_ns,i_job_id,
    input wire [127:0] s_data,input wire [15:0] s_keep,
    input wire s_valid,s_last,output wire s_ready,
    output reg [127:0] m_data,output wire [15:0] m_keep,
    output wire m_valid,m_last,input wire m_ready,
    output wire o_done,
    input wire i_data_reset_n
);
    localparam [31:0] MAGIC=`PCIE_RAW_VIDEO_MAGIC;
    localparam [15:0] VERSION=`PCIE_RAW_VIDEO_VERSION, HEADER_BYTES=`PCIE_RAW_VIDEO_HEADER_BYTES;
    localparam [7:0] FORMAT_RAW10=`PCIE_RAW_VIDEO_FORMAT_RAW10, TIME_VALID=`PCIE_RAW_VIDEO_FLAG_TIMESTAMP_VALID;
    localparam [2:0] HEADER0=0,HEADER1=1,HEADER2=2,HEADER3=3,BODY=4,IDLE=5;
    reg [2:0] phase;
    wire data_reset_n=SEPARATE_DATA_RESET!=0 ? i_data_reset_n : i_rst_n;
    wire header=!phase[2];
    wire body=phase==BODY;
    wire last_fire=s_valid && s_ready && s_last;

    assign o_drained=data_reset_n && phase==IDLE;
    assign o_start_ready=o_drained && !i_abort;
    assign m_valid=data_reset_n && (header || (body && s_valid));
    assign m_keep=body ? s_keep : 16'hffff;
    assign m_last=body && s_last;
    assign s_ready=data_reset_n && body && m_ready;
    assign o_done=last_fire && !i_abort;

    always @* begin
        case (phase)
            HEADER0:m_data={i_height,i_width,i_payload_bytes,HEADER_BYTES,VERSION,MAGIC};
            HEADER1:m_data={i_time_valid ? TIME_VALID : 8'd0,{6'd0,i_bayer_phase},
                FORMAT_RAW10,{7'd0,i_camera},i_epoch,i_session,i_sequence};
            HEADER2:m_data={i_job_id,i_capture_time_ns};
            BODY:m_data=s_data;
            default:m_data=128'd0;
        endcase
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) phase<=IDLE;
        else case (phase)
            IDLE:if (i_start_valid && o_start_ready) phase<=HEADER0;
            // The current header is already presented even if abort arrives.
            HEADER0,HEADER1,HEADER2,HEADER3:if (m_ready) phase<=i_abort ? IDLE : phase+3'd1;
            BODY:if (last_fire || (i_abort && !s_valid)) phase<=IDLE;
            default:phase<=IDLE;
        endcase
    end
endmodule
