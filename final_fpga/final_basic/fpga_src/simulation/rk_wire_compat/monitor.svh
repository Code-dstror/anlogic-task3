// Feed the existing six-slot/C2H bench a CTX2 produced by the actual builder.
// Input events emulate completed ISP/JPEG work; the selected formatter, replay,
// ownership checker and generated ERAM are normal production RTL.
reg [7:0] jpeg[0:PAYLOAD_SIZE-1];
integer stream_log;
initial begin $readmemh("jpeg.hex",jpeg);stream_log=$fopen("axis.txt","w");end
wire hdr=current==2 || current==5;
wire [5:0] enables=current==1 ? 6'h30 : (current==4 || current==5) ? 6'h0f : 6'd0;
wire dehaze_used=current==5;
wire [63:0] pair_identity={32'd0,sequence_id};
wire [1023:0] ctx_data;
wire ctx_valid,ctx_ready;
frame_record_extension_builder #(.NEUTRAL_STATS_ENABLE(0)) context_builder(
    .i_clk(clk),.i_rst_n(rst_n),.s_begin_valid(begin_valid&&begin_ready),.o_begin_ready(ctx_ready),
    .i_source_session(32'h12345678),.i_source_epoch(32'd300),.i_source_sequence(sequence_id),
    .i_source_camera({7'd0,camera}),.i_source_kind(8'd1),.i_source_format(8'd1),.i_exposure_role({7'd0,hdr}),
    .i_exposure_valid(1'b0),.i_actual_exposure(32'd0),.i_exposure_group(32'd0),
    .i_gain_valid(1'b0),.i_actual_gain(32'd0),.i_calibration_valid(1'b0),.i_calibration_id(32'd0),
    .i_time_quality(8'd0),.i_pair_valid(hdr),.i_pair_id(pair_identity),.i_job_valid(hdr),.i_job_id(pair_identity),
    .i_write_tag_valid(1'b0),.i_write_tag(64'd0),.i_qualified(hdr),.i_processing_member(8'd0),
    .i_processing_mode({2'b10,enables}),.i_record_flags({13'd0,dehaze_used,1'b0,hdr}),
    .s_stats_valid(1'b0),.o_stats_ready(),.s_stats_context(160'd0),.s_statistics(184'd0),
    .m_extension_valid(ctx_valid),.m_extension_ready(1'b1),.m_extension_data(ctx_data),
    .o_stale_count(),.o_error_count(),.o_input_fault());
always @(posedge clk) if(rst_n)begin
    if(accepted)$fdisplay(stream_log,"S %0d",req_slot);
    if(axis_valid&&axis_ready)$fdisplay(stream_log,"B %h %h %b",axis_data,axis_keep,axis_last);
    if(done)$fdisplay(stream_log,"D");
    if(aborted)$fdisplay(stream_log,"A");
end
