`timescale 1ns/1ps
`default_nettype none

// One shared physical word stream, independent bounded member FIFOs.
// 147x512 official FIFO per member; no complete-frame image storage here.
module real_hdr_csi_capture_stream #(
    parameter integer SENSOR_WIDTH=1944,SENSOR_HEIGHT=1097,
    parameter integer CROP_X=12,CROP_Y=8,WIDTH=1920,HEIGHT=1080
) (
    input wire i_word_clk,i_pixel_clk,i_reset_n,i_decoder_reset_n,i_identity_rst_n,
    input wire i_publish_enable,i_cycle_enable,
    input wire [31:0] i_word,
    input wire i_word_valid,
    output wire o_fifo_write_ready,o_wait_for_sync,o_packet_done,o_packet_continue,o_identity_fault,
    output wire [146:0] m0_data,m1_data,
    output wire m0_valid,m1_valid,
    input wire m0_ready,m1_ready,
    output reg [31:0] o_crc_errors,o_overflow_errors,o_format_errors,
    output wire [31:0] o_sequence_count0,o_sequence_count1,
    output wire o_fs0_observe_valid,o_fs1_observe_valid,
    output wire [15:0] o_fs0_number,o_fs1_number
);
    // Identity is a coordinated cohort reset request. Its deassertion
    // must reach WORD and PIX through separate local release chains: the
    // parser also uses this signal in ordinary data/CE logic.
    wire identity_word_reset_n,identity_pixel_reset_n;
    reset_release_sync u_identity_word_reset(
        .i_clk(i_word_clk),.i_async_rst_n(i_identity_rst_n),.o_rst_n(identity_word_reset_n));
    reset_release_sync u_identity_pixel_reset(
        .i_clk(i_pixel_clk),.i_async_rst_n(i_identity_rst_n),.o_rst_n(identity_pixel_reset_n));
    wire decoder_async_n=i_reset_n&&i_decoder_reset_n;
    wire publish_async_n=i_reset_n&&i_publish_enable;
    reg [1:0] decoder_release,word_release,pixel_release;
    always @(posedge i_word_clk or negedge decoder_async_n)begin
        if(!decoder_async_n)decoder_release<=0;else decoder_release<={decoder_release[0],1'b1};
    end
    always @(posedge i_word_clk or negedge publish_async_n)begin
        if(!publish_async_n)word_release<=0;else word_release<={word_release[0],1'b1};
    end
    always @(posedge i_pixel_clk or negedge publish_async_n)begin
        if(!publish_async_n)pixel_release<=0;else pixel_release<={pixel_release[0],1'b1};
    end
    wire [47:0] decoded_data[0:1];
    wire [1:0] decoded_valid,decoded_ready,decoded_sof,decoded_eol,decoded_abort;
    wire [3:0] decoded_error[0:1];
    wire [31:0] decoded_group[0:1],decoded_sequence[0:1];
    wire [1:0] decoded_identity,decoded_cycle;
    wire [15:0] decoded_number[0:1];
    wire parser_fault;
    wire unused_ecc,unused_crc,unused_length;
    real_hdr_csi_dual_word_rx #(.EXPECTED_RAW_BYTES((SENSOR_WIDTH*12)/8)) u_parser(
        .i_clk(i_word_clk),.i_reset_n(decoder_release[1]),.i_identity_rst_n(identity_word_reset_n),
        .i_cycle_enable(i_cycle_enable),.i_word(i_word),.i_word_valid(i_word_valid),
        .i_long_ready(decoded_ready[0]),.i_short_ready(decoded_ready[1]),
        .o_long_data(decoded_data[0]),.o_short_data(decoded_data[1]),
        .o_long_valid(decoded_valid[0]),.o_short_valid(decoded_valid[1]),
        .o_long_sof(decoded_sof[0]),.o_short_sof(decoded_sof[1]),.o_long_eol(decoded_eol[0]),.o_short_eol(decoded_eol[1]),
        .o_long_abort(decoded_abort[0]),.o_short_abort(decoded_abort[1]),.o_long_error(decoded_error[0]),.o_short_error(decoded_error[1]),
        .o_long_sequence_count(o_sequence_count0),.o_short_sequence_count(o_sequence_count1),
        .o_long_group(decoded_group[0]),.o_short_group(decoded_group[1]),
        .o_long_event_sequence(decoded_sequence[0]),.o_short_event_sequence(decoded_sequence[1]),
        .o_long_identity_valid(decoded_identity[0]),.o_short_identity_valid(decoded_identity[1]),
        .o_long_cycle_valid(decoded_cycle[0]),.o_short_cycle_valid(decoded_cycle[1]),
        .o_long_event_frame_number(decoded_number[0]),.o_short_event_frame_number(decoded_number[1]),
        .o_long_fs_observe_valid(o_fs0_observe_valid),.o_short_fs_observe_valid(o_fs1_observe_valid),
        .o_long_fs_number(o_fs0_number),.o_short_fs_number(o_fs1_number),
        .o_long_fs_observe_sequence(),.o_short_fs_observe_sequence(),.o_long_fs_observe_trusted(),.o_short_fs_observe_trusted(),
        .o_identity_fault(parser_fault),.o_wait_for_sync(o_wait_for_sync),.o_packet_done(o_packet_done),.o_packet_continue(o_packet_continue),
        .o_header_ecc_error(unused_ecc),.o_payload_crc_error(unused_crc),.o_length_error(unused_length));
    reg [1:0] fault_sync;
    always @(posedge i_pixel_clk or negedge identity_pixel_reset_n)begin
        if(!identity_pixel_reset_n)fault_sync<=0;else fault_sync<={fault_sync[0],parser_fault};
    end
    assign o_identity_fault=fault_sync[1];
    wire [146:0] fifo_data[0:1];
    wire [1:0] fifo_valid,fifo_ready;
    wire [1:0] read_valid,read_ready;
    wire [146:0] read_data[0:1];
    assign m0_data=read_data[0];assign m1_data=read_data[1];
    assign m0_valid=read_valid[0];assign m1_valid=read_valid[1];
    assign read_ready={m1_ready,m0_ready};
    assign o_fifo_write_ready=&fifo_ready;
    genvar member;
    generate for(member=0;member<2;member=member+1)begin:g_member
        wire [39:0] crop_data;
        wire crop_valid,crop_sof,crop_eol,crop_abort;
        wire [3:0] crop_error;
        wire [31:0] crop_group,crop_sequence;
        wire crop_identity,crop_cycle;
        wire [15:0] crop_number;
        real_hdr_member_crop10 #(.SENSOR_WIDTH(SENSOR_WIDTH),.SENSOR_HEIGHT(SENSOR_HEIGHT),
            .CROP_X(CROP_X),.CROP_Y(CROP_Y),.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_crop(
            .i_clk(i_word_clk),.i_reset_n(decoder_release[1]),
            .s_data(decoded_data[member]),.s_valid(decoded_valid[member]),.s_ready(decoded_ready[member]),
            .s_sof(decoded_sof[member]),.s_eol(decoded_eol[member]),.s_abort(decoded_abort[member]),.s_error(decoded_error[member]),
            .s_group(decoded_group[member]),.s_sequence(decoded_sequence[member]),
            .s_identity_valid(decoded_identity[member]),.s_cycle_valid(decoded_cycle[member]),.s_frame_number(decoded_number[member]),
            .m_data(crop_data),.m_valid(crop_valid),.m_ready(i_publish_enable?fifo_ready[member]:1'b1),
            .m_sof(crop_sof),.m_eol(crop_eol),.m_abort(crop_abort),.m_error(crop_error),
            .m_group(crop_group),.m_sequence(crop_sequence),.m_identity_valid(crop_identity),.m_cycle_valid(crop_cycle),.m_frame_number(crop_number),
            .o_geometry_errors(),.o_complete_frames());
        assign fifo_data[member]={18'd0,crop_number,crop_cycle,crop_identity,crop_sequence,crop_group,
            crop_error,crop_abort,crop_eol,crop_sof,crop_data};
        assign fifo_valid[member]=crop_valid&&i_publish_enable;
        raw_capture_fifo_eram_safe u_fifo(
            .i_source_clk(i_word_clk),.i_source_rst_n(word_release[1]),
            .i_source_data(fifo_data[member]),.i_source_valid(fifo_valid[member]),.o_source_ready(fifo_ready[member]),.o_source_reset_done(),
            .i_sink_clk(i_pixel_clk),.i_sink_rst_n(pixel_release[1]),
            .o_sink_data(read_data[member]),.o_sink_valid(read_valid[member]),.i_sink_ready(read_ready[member]),.o_sink_reset_done(),.o_available_count());
    end endgenerate
    integer n;
    always @(posedge i_pixel_clk or negedge identity_pixel_reset_n)begin
        if(!identity_pixel_reset_n)begin o_crc_errors<=0;o_overflow_errors<=0;o_format_errors<=0;end
        else begin
            for(n=0;n<2;n=n+1)if(read_valid[n]&&read_ready[n]&&read_data[n][42])begin
                case(read_data[n][46:43])
                    2:o_crc_errors<=o_crc_errors+1;
                    3:o_overflow_errors<=o_overflow_errors+1;
                    4:o_format_errors<=o_format_errors+1;
                    default:begin end
                endcase
            end
        end
    end
endmodule
`default_nettype wire
