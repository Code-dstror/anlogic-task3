`timescale 1ns/1ps
module tb_sparse_ordered;
    reg sc=0,dc=0,rst_n=0;always #5 sc=~sc;always #7 dc=~dc;
    reg [16383:0] fixtures[0:5];
    reg [159:0] identity=0;reg [1023:0] base=0;
    reg [683:0] f22=0;reg [176:0] lane=0;
    reg jb=0,jt=0,cv=0,v22=0,lv=0;
    wire jbr,cr,r22,lr,jvalid,jready,jfault;wire [2047:0] summary;
    wire [31:0] stale;wire stream_start,jstream_valid,jstream_ready;wire [127:0] jstream;
    wire lane_re;wire [8:0] lane_ri;reg [39:0] lane_rd=0;reg lane_rv=0;
    integer current=0,checks=0,k,n,limit,read_words=0,stream_takes=0;
    always @(posedge sc)begin
        lane_rv<=rst_n && lane_re;
        if(lane_re)lane_rd<=fixtures[current][2048+lane_ri*40+:40];
        if(rst_n)begin
            if(cv && cr)cv<=0;
            if(v22 && r22)v22<=0;
            if(lv && lr)lv<=0;
        end
    end
    frame_record_v3_join joiner(
        .i_clk(sc),.i_rst_n(rst_n),.s_begin_valid(jb),.o_begin_ready(jbr),
        .s_begin_context(identity),.s_begin_features(4'd3),.s_terminal_valid(jt),.s_terminal_error(current==5),
        .s_terminal_context(identity),.s_context2_extension(base),.s_context2_valid(cv),.o_context2_ready(cr),
        .s_f22_record(f22),.s_f22_valid(v22),.o_f22_ready(r22),.s_f23_record(lane),.s_f23_valid(lv),.o_f23_ready(lr),
        .s_f24_record(208'd0),.s_f24_valid(1'b0),.o_f24_ready(),.s_f25_record(265'd0),.s_f25_valid(1'b0),.o_f25_ready(),
        .m_extension(summary),.m_extension_valid(jvalid),.m_extension_ready(jready),.i_stream_start(stream_start),
        .m_stream_data(jstream),.m_stream_valid(jstream_valid),.m_stream_ready(jstream_ready),
        .o_lane_read_enable(lane_re),.o_lane_read_index(lane_ri),.i_lane_read_data(lane_rd),.i_lane_read_valid(lane_rv),
        .o_fault(jfault),.o_stale_count(stale));
    reg sv=0,jpegv=0,jpegl=0,rv=0;
    reg [127:0] jpegdata=0;reg [15:0] jpegkeep=0;
    wire sr,jpegr,rr,sfault,dfault,sreset,dreset;
    wire sink_sv,sink_jv,sink_jl,sink_rv,sink_ok,ext_valid,ext_good;
    wire [127:0] sink_data;wire [15:0] sink_keep;wire [24:0] sink_length;
    reg sink_jr=0,sink_rr=0,ext_ready=0,re=0;reg [8:0] ri=0;wire [39:0] rd;
    wire [31:0] seq=100+current;
    ordered_frame_cdc #(.CONTEXT_ENABLE(1),.WRITE_TAG_ENABLE(1),.RECORD_EXTENSION_ENABLE(1),
        .RECORD_EXTENSION_WIDTH(16384),.BORROW_EXTENSION(1),.EXTENSION_RAM_ENABLE(1),.STREAM_EXTENSION(1)) cdc(
        .i_source_clk(sc),.i_source_rst_n(rst_n),.i_start_valid(sv),.o_start_ready(sr),.i_capture_id(seq),
        .i_width(16'd1920),.i_height(16'd1080),.i_timestamp_ns(64'd0),.i_session_id(32'h12345678),
        .i_mode_epoch(32'd300),.i_camera_id(current>=3),.i_quality(8'd75),.i_format(8'd1),.i_write_tag(seq+1000),
        .i_start_mask(1'b0),.i_start_source_type(3'd0),.i_jpeg_tdata(jpegdata),.i_jpeg_tkeep(jpegkeep),
        .i_jpeg_tlast(jpegl),.i_jpeg_tvalid(jpegv),.o_jpeg_tready(jpegr),.i_result_valid(rv),.o_result_ready(rr),
        .i_result_id(seq),.i_result_ok(1'b1),.i_result_length(25'd17),.i_result_error(8'd0),
        .i_result_quality(8'd75),.i_result_epoch(32'd300),.i_record_extension(summary),
        .i_record_extension_valid(jvalid),.o_record_extension_ready(jready),.o_source_protocol_fault(sfault),
        .i_extension_stream_data(jstream),.i_extension_stream_valid(jstream_valid),
        .o_extension_stream_ready(jstream_ready),.o_extension_stream_start(stream_start),
        .i_sink_clk(dc),.i_sink_rst_n(rst_n),.o_start_valid(sink_sv),.i_start_ready(1'b1),
        .o_capture_id(),.o_width(),.o_height(),.o_timestamp_ns(),.o_session_id(),.o_mode_epoch(),.o_camera_id(),
        .o_quality(),.o_format(),.o_write_tag(),.o_start_mask(),.o_start_source_type(),
        .o_jpeg_tdata(sink_data),.o_jpeg_tkeep(sink_keep),.o_jpeg_tlast(sink_jl),.o_jpeg_tvalid(sink_jv),
        .i_jpeg_tready(sink_jr),.o_result_valid(sink_rv),.i_result_ready(sink_rr),.o_result_id(),
        .o_result_ok(sink_ok),.o_result_length(sink_length),.o_result_error(),.o_result_quality(),.o_result_epoch(),
        .o_record_extension(),.o_record_extension_valid(ext_valid),.i_record_extension_ready(ext_ready),
        .o_extension_shape_valid(ext_good),.i_extension_read_enable(re),.i_extension_read_index(ri),.o_extension_read_data(rd),
        .o_protocol_fault(dfault),.i_fence_request(1'b0),.i_source_fence_idle(1'b0),
        .i_source_fence_session(32'h12345678),.i_sink_fence_session(32'h12345678),
        .i_raw_enqueued(64'd0),.i_raw_consumed(64'd0),.i_raw_consume_fire(1'b0),.i_sink_fence_quiet(1'b0),
        .o_source_fence_proven(),.o_source_fence_fault(),.o_sink_fence_fault(),
        .o_source_reset_done(sreset),.o_sink_reset_done(dreset));
    task check(input bit condition,input string why);
        begin checks++;if(!condition)$fatal(1,"SPARSE ordered %s case=%0d time=%0t",why,current,$time);end
    endtask
    integer dcycles=0,payloads=0;
    always @(negedge dc)begin dcycles++;sink_jr=dcycles%4!=0;end
    always @(posedge dc)if(rst_n && sink_jv && sink_jr)begin
        if(payloads==0)check(sink_keep==16'hffff && !sink_jl && sink_data==128'h0f0e0d0c0b0a09080706050403020100,"first JPEG beat preserved across CDC");
        else check(sink_keep==1 && sink_jl && sink_data[7:0]==16,"last JPEG byte preserved");
        payloads++;
    end
    always @(posedge sc)if(rst_n && jstream_valid && jstream_ready)stream_takes++;
    reg [39:0] expected_word;
    initial begin
        $readmemh("source.hex",fixtures);
        repeat(12)@(negedge sc);rst_n=1;wait(sreset&&dreset);repeat(5)@(negedge sc);
        for(n=0;n<6;n++)begin
            current=n;payloads=0;base=fixtures[n][1023:0];
            identity={16'd1,16'd0,8'd1,base[183:160],base[159:128],base[127:96],base[95:64]};
            f22={identity,fixtures[n][1152+:524]};lane={identity,fixtures[n][1104+:9],fixtures[n][1096+:8]};
            jb=1;do @(posedge sc);while(!jbr);@(negedge sc);jb=0;
            cv=1;v22=1;lv=1;sv=1;do @(posedge sc);while(!sr);@(negedge sc);sv=0;
            jpegv=1;jpegdata=128'h0f0e0d0c0b0a09080706050403020100;jpegkeep=16'hffff;jpegl=0;
            do @(posedge sc);while(!jpegr);@(negedge sc);
            jpegdata=16;jpegkeep=1;jpegl=1;do @(posedge sc);while(!jpegr);@(negedge sc);jpegv=0;
            rv=1;jt=1;@(posedge sc);@(negedge sc);jt=0;
            limit=0;while(!rr)begin @(negedge sc);limit++;check(limit<4500,"borrowed JOIN streaming completes");end
            @(posedge sc);@(negedge sc);rv=0;cv=0;v22=0;lv=0;
            limit=0;while(!ext_valid)begin @(negedge dc);limit++;check(limit<4500,"all 128 tokens reach staging");end
            $display("ORDERED_STATE case=%0d shape=%b joinfault=%b sourcefault=%b sinkfault=%b stale=%0d",n,ext_good,jfault,sfault,dfault,stale);
            check(ext_good && !jfault && !sfault && !dfault && stale==0,"legal joined extension accepted end to end");
            repeat(7)begin @(negedge dc);check(ext_valid && !sink_rv,"FENCE waits for real extension acceptance");end
            for(k=0;k<410;k++)begin
                ri=k;re=1;@(posedge dc);@(negedge dc);re=0;
                expected_word=k==409 ? {16'd0,fixtures[n][16360+:24]} : fixtures[n][k*40+:40];
                check(rd===expected_word,"410 physical words including last 3B match independent extension");read_words++;
            end
            ext_ready=1;@(posedge dc);@(negedge dc);ext_ready=0;
            limit=0;while(!sink_rv)begin @(negedge dc);limit++;check(limit<10,"FENCE closes after extension");end
            check(sink_ok && sink_length==17 && payloads==2,"successful JPEG result remains paired");
            sink_rr=1;@(posedge dc);@(negedge dc);sink_rr=0;
            repeat(5)@(negedge sc);
        end
        check(stream_takes==768,"six complete extension streams accepted exactly once");
        $display("RESULT: PASS SPARSE_ORDERED checks=%0d words=%0d flits=%0d",checks,read_words,stream_takes);$finish;
    end
    initial begin #3000000;$fatal(1,"SPARSE ordered watchdog");end
endmodule
