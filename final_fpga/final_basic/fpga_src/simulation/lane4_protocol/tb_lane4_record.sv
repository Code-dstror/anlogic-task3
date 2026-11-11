`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
// Explicit synthetic typed records, not an algorithm or JPEG image fixture.
// Actual candidate join -> official staging RAM -> metadata RAM/two-pass stream
// -> header RAM/replay; every accepted bit is compared with independent fixtures.
module tb_lane4_record;
    reg clk=0,rst_n=0;always #5 clk=~clk;
    reg [159:0] contexts[0:4];reg [1023:0] bases[0:4];
    reg [683:0] f22[0:4];reg [1355:0] f23[0:4];
    reg [3071:0] joined[0:4],stored[0:4];reg [511:0] headers[0:4];
    reg bv=0,tv=0,cv=0,v22=0,v23=0,mr=0;
    reg [159:0] frame_context=0;reg [3:0] features=0;reg terminal_error=0;
    reg [1023:0] base=0;reg [683:0] r22=0;reg [1355:0] r23=0;
    wire br,cr,rr22,rr23,mv,fault;wire [31:0] stale;wire [3071:0] ext;
    frame_record_v3_join joiner(.i_clk(clk),.i_rst_n(rst_n),.s_begin_valid(bv),.o_begin_ready(br),
        .s_begin_context(frame_context),.s_begin_features(features),.s_terminal_valid(tv),.s_terminal_error(terminal_error),
        .s_terminal_context(frame_context),.s_context2_extension(base),.s_context2_valid(cv),.o_context2_ready(cr),
        .s_f22_record(r22),.s_f22_valid(v22),.o_f22_ready(rr22),.s_f23_record(r23),.s_f23_valid(v23),.o_f23_ready(rr23),
        .s_f24_record(208'd0),.s_f24_valid(1'b0),.o_f24_ready(),.s_f25_record(265'd0),.s_f25_valid(1'b0),.o_f25_ready(),
        .m_extension(ext),.m_extension_valid(mv),.m_extension_ready(mr),.o_fault(fault),.o_stale_count(stale));
    reg stage_begin=0,stage_valid=0,stage_last=0;
    reg [127:0] stage_data=0;
    wire stage_ready,stage_complete,stage_shape,stage_read;
    wire [6:0] stage_index;wire [39:0] stage_word;
    ddr_extension_staging_ram stage(.i_clk(clk),.i_rst_n(rst_n),.i_begin(stage_begin),
        .i_session(frame_context[31:0]),.i_epoch(frame_context[63:32]),.i_sequence(frame_context[95:64]),.i_camera(frame_context[96]),
        .s_data(stage_data),.s_valid(stage_valid),.s_last(stage_last),.s_ready(stage_ready),
        .o_complete(stage_complete),.o_shape_valid(stage_shape),.i_read_enable(stage_read),.i_read_index(stage_index),.o_read_data(stage_word));
    reg owner_begin=0,extension_valid=0,proof_valid=0,req_valid=0,rsp_ready=0,stream_start=0,stream_ready=0;
    reg [15:0] slot=0;reg [31:0] generation=0,req_epoch=0;
    wire owner_ready,extension_ready,proof_ready,write_quiet,read_quiet,store_fault,req_ready,rsp_valid,rsp_ok,rsp_shape;
    wire [7:0] rsp_error;wire [31:0] bad_count,stale_write;wire stream_valid,stream_last;wire [127:0] stream_data;
    jpeg_record_metadata_store #(.RECORD_EXTENSION_WIDTH(3072),.BORROW_PENDING_EXTENSION(1),.STAGING_EXTENSION_ENABLE(1),.STREAM_READ(1)) storage(
        .i_clk(clk),.i_rst_n(rst_n),.s_begin_valid(owner_begin),.s_begin_ready(owner_ready),
        .s_begin_writer_tag(32'd7),.s_begin_sequence(frame_context[95:64]),.s_begin_session(frame_context[31:0]),.s_begin_epoch(frame_context[63:32]),.s_begin_camera(frame_context[96]),
        .s_extension(ext),.s_extension_valid(extension_valid),.s_extension_ready(extension_ready),.s_extension_shape_valid(stage_shape),
        .o_extension_read_enable(stage_read),.o_extension_read_index(stage_index),.i_extension_read_data(stage_word),
        .s_write_result_valid(proof_valid),.s_write_result_ready(proof_ready),.s_write_result_tag(32'd7),
        .s_write_result_sequence(frame_context[95:64]),.s_write_result_session(frame_context[31:0]),.s_write_result_epoch(frame_context[63:32]),.s_write_result_camera(frame_context[96]),
        .s_write_result_slot(slot),.s_write_result_generation(generation),.s_write_result_ok(1'b1),.s_write_result_error(8'd0),
        .o_write_quiescent(write_quiet),.o_read_quiescent(read_quiet),.o_protocol_fault(store_fault),
        .o_stale_write_count(stale_write),.o_bad_extension_count(bad_count),.o_bad_extension_seen(),.o_write_error(),
        .s_read_req_valid(req_valid),.s_read_req_ready(req_ready),.s_read_req_slot(slot),.s_read_req_generation(generation),
        .s_read_req_session(frame_context[31:0]),.s_read_req_sequence(frame_context[95:64]),.s_read_req_epoch(req_epoch),.s_read_req_camera(frame_context[96]),
        .o_metadata_available(),.m_read_rsp_valid(rsp_valid),.m_read_rsp_ready(rsp_ready),.m_read_rsp_ok(rsp_ok),.m_read_rsp_error(rsp_error),
        .m_read_rsp_slot(),.m_read_rsp_generation(),.m_read_rsp_session(),.m_read_rsp_sequence(),.m_read_rsp_epoch(),.m_read_rsp_camera(),
        .m_read_rsp_extension(),.s_read_req_version(16'd3),.m_read_rsp_shape_valid(rsp_shape),
        .s_read_stream_start(stream_start),.m_read_stream_data(stream_data),.m_read_stream_valid(stream_valid),.m_read_stream_last(stream_last),.m_read_stream_ready(stream_ready),
        .s_read_req_mask(1'b0),.m_read_rsp_mask_qualified(),.m_read_rsp_mask_pixels(),.m_read_rsp_source_type());
    reg [127:0] hdr_data=0;reg [15:0] hdr_keep=16'hffff;reg hdr_valid=0,hdr_last=0,meta_ready=0,ext_ready=0,payload_ready=0;
    wire hdr_ready,meta_valid,header_error,header_busy,ext_valid,ext_last,payload_valid,payload_last;
    wire [127:0] ext_data,payload_data;wire [15:0] payload_keep;
    wire [31:0] meta_crc,meta_length,meta_sequence;
    pcie_header_extension_ram #(.RECORD_V2_ENABLE(1),.RECORD_V3_ENABLE(1)) header_ram(
        .i_clk(clk),.i_rst_n(rst_n),.i_src_tdata(hdr_data),.i_src_tkeep(hdr_keep),.i_src_tvalid(hdr_valid),.o_src_tready(hdr_ready),.i_src_tlast(hdr_last),
        .i_selected_version(16'd3),.o_meta_valid(meta_valid),.i_meta_ready(meta_ready),.o_meta_frame_sequence(meta_sequence),.o_meta_payload_length(meta_length),
        .o_meta_width(),.o_meta_height(),.o_meta_pixel_format(),.o_meta_compression(),.o_meta_quality(),.o_meta_timestamp_ns(),.o_meta_status(),.o_meta_error_code(),
        .o_meta_slot_id(),.o_meta_payload_crc32(meta_crc),.o_meta_record_version(),.o_meta_record_extension(),
        .o_payload_tdata(payload_data),.o_payload_tkeep(payload_keep),.o_payload_tvalid(payload_valid),.i_payload_tready(payload_ready),.o_payload_tlast(payload_last),
        .o_header_error(header_error),.o_last_error(),.o_busy(header_busy),.o_extension_tdata(ext_data),.o_extension_tvalid(ext_valid),.o_extension_tlast(ext_last),.i_extension_tready(ext_ready));
    integer checks=0,n,k,limit,cycle,count,outfile,last_wait;
    reg [3071:0] observed,metadata_observed;
    reg stalled=0;reg [127:0] held;reg held_last;
    task check(input bit okay,input string why);
        begin checks++;if(!okay)$fatal(1,"LANE4 record n=%0d %s time=%0t",n,why,$time);end
    endtask
    task read_request(input bit wrong);
        begin
            req_epoch=frame_context[63:32]+wrong;req_valid=1;
            do @(posedge clk);while(!req_ready);
            @(negedge clk);req_valid=0;limit=0;
            while(!rsp_valid)begin @(negedge clk);limit++;check(limit<300,"bounded metadata validation");end
            check(wrong?(!rsp_ok&&!rsp_shape&&rsp_error==1):(rsp_ok&&rsp_shape&&rsp_error==0),"catalog identity and shape proof");
        end
    endtask
    task send_header_flit(input [127:0] value);
        begin
            hdr_valid=1;hdr_data=value;
            do @(posedge clk);while(!hdr_ready);
            @(negedge clk);hdr_valid=0;
        end
    endtask
    initial begin
        $readmemh("context.hex",contexts);$readmemh("base.hex",bases);$readmemh("f22.hex",f22);$readmemh("f23.hex",f23);
        $readmemh("joined.hex",joined);$readmemh("stored.hex",stored);$readmemh("header.hex",headers);
        outfile=$fopen("observed.hex","w");
        repeat(12)@(negedge clk);rst_n=1;repeat(12)@(negedge clk);
        for(n=0;n<5;n++)begin
            frame_context=contexts[n];base=bases[n];features=n==3?0:3;terminal_error=n==2;
            slot=frame_context[96]?3:0;generation=20+n;owner_begin=1;bv=1;
            #1;check(br&&owner_ready,"both real owners idle before admission");
            @(posedge clk);@(negedge clk);owner_begin=0;bv=0;
            r22=f22[n];r23=f23[n];v22=1;v23=1;cv=1;
            repeat(6)begin @(negedge clk);check(!mv&&!br,"terminal required before output");end
            tv=1;@(posedge clk);@(negedge clk);tv=0;
            repeat(13)begin @(negedge clk);check(mv&&ext===joined[n]&&!br,"complete joined extension stable under stall");end
            if(n!=3)check(!rr22&&!rr23&&!cr,"typed records held by real downstream ownership");
            stage_begin=1;@(posedge clk);@(negedge clk);stage_begin=0;
            for(k=0;k<24;k++)begin
                stage_valid=1;stage_last=k==23;stage_data=ext[k*128+:128];
                do @(posedge clk);while(!stage_ready);
                @(negedge clk);stage_valid=0;
                check(mv&&ext===joined[n],"join remains stable while staging serialized");
            end
            stage_last=0;limit=0;
            while(!stage_complete)begin @(negedge clk);limit++;check(limit<20,"staging final word bounded");end
            check(stage_shape,"actual staging shape accepts all four bands");
            extension_valid=1;
            do @(posedge clk);while(!extension_ready);
            @(negedge clk);extension_valid=0;mr=1;
            #1;check(cr&&(n==3||(rr22&&rr23)),"single final take releases exact reports");
            @(posedge clk);@(negedge clk);mr=0;cv=0;v22=0;v23=0;
            proof_valid=1;@(posedge clk);check(proof_ready,"real write-result accepted");@(negedge clk);proof_valid=0;
            limit=0;while(!write_quiet)begin @(negedge clk);limit++;check(limit<200,"77-word metadata copy bounded");end
            check(!fault&&!store_fault&&bad_count==0&&stale_write==0,"publication no faults");
            // Wrong epoch cannot obtain bytes from a prior or current record.
            read_request(1);check(!stream_valid,"stale request has no stream");rsp_ready=1;
            @(posedge clk);@(negedge clk);rsp_ready=0;repeat(3)@(negedge clk);
            read_request(0);
            for(k=0;k<4;k++)send_header_flit(headers[n][k*128+:128]);
            stream_start=1;@(posedge clk);@(negedge clk);stream_start=0;
            metadata_observed=0;count=0;cycle=0;stalled=0;last_wait=0;
            while(count<24)begin
                // Bounded sink stalls including thirteen cycles on final flit.
                stream_ready=cycle%7!=0;
                if(count==23&&last_wait<13)begin stream_ready=0;if(stream_valid)last_wait++;end
                hdr_valid=stream_valid&&stream_ready;hdr_data=stream_data;
                #1;stream_ready=stream_ready&&hdr_ready;hdr_valid=stream_valid&&stream_ready;
                if(stalled)check(stream_valid&&stream_data===held&&stream_last==held_last,"metadata stream stable while stalled");
                if(stream_valid&&!stream_ready)begin stalled=1;held=stream_data;held_last=stream_last;end else stalled=0;
                @(posedge clk);
                if(stream_valid&&stream_ready)begin
                    check(stream_data===stored[n][count*128+:128]&&stream_last==(count==23),"metadata all bits and last boundary preserved");
                    metadata_observed[count*128+:128]=stream_data;count++;
                end
                @(negedge clk);cycle++;check(cycle<600,"metadata replay finite");
            end
            check(last_wait==13,"metadata last flit stalls for thirteen cycles");
            stream_ready=0;hdr_valid=0;
            while(!meta_valid)@(negedge clk);
            check(meta_sequence==frame_context[95:64]&&meta_length==17&&meta_crc==32'ha5c30000+n&&!header_error,"header identity/length/CRC field preserved");
            repeat(5)begin @(negedge clk);check(meta_valid&&header_busy&&!payload_valid,"metadata held before accept");end
            meta_ready=1;@(posedge clk);@(negedge clk);meta_ready=0;
            observed=0;count=0;cycle=0;stalled=0;last_wait=0;
            while(count<24)begin
                ext_ready=cycle%5!=0;
                if(count==23&&last_wait<17)begin ext_ready=0;if(ext_valid)last_wait++;end
                #1;
                if(stalled)check(ext_valid&&ext_data===held&&ext_last==held_last,"header RAM replay stable under stall");
                if(ext_valid&&!ext_ready)begin stalled=1;held=ext_data;held_last=ext_last;end else stalled=0;
                check(header_busy&&!payload_valid,"header owns complete extension before final take");
                @(posedge clk);
                if(ext_valid&&ext_ready)begin
                    check(ext_data===stored[n][count*128+:128]&&ext_last==(count==23),"header RAM retains every slot and last boundary");
                    observed[count*128+:128]=ext_data;count++;
                end
                @(negedge clk);cycle++;check(cycle<600,"header replay finite");
            end
            check(last_wait==17,"header last flit stalls for seventeen cycles");
            ext_ready=0;check(observed===metadata_observed,"two actual RAM stream stages agree");$fdisplay(outfile,"%0768h",observed);
            rsp_ready=1;@(posedge clk);@(negedge clk);rsp_ready=0;repeat(3)@(negedge clk);
            payload_ready=1;hdr_keep=16'hffff;send_header_flit(128'h01020304050607080910111213141516);
            hdr_data=128'h17;hdr_keep=1;hdr_last=1;hdr_valid=1;
            #1;check(payload_valid&&payload_last&&payload_keep==1&&payload_data==128'h17,"17-byte payload last keep/data passed through");
            @(posedge clk);@(negedge clk);hdr_valid=0;hdr_last=0;hdr_keep=16'hffff;payload_ready=0;
            check(!header_busy&&br&&read_quiet,"all record owners release after final takes");
        end
        $fclose(outfile);
        // Reset invalidates the RAM catalog even though payload bits remain.
        rst_n=0;repeat(4)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);
        read_request(1);check(!rsp_ok&&!stream_valid&&!store_fault,"reset cannot publish cold cached payload");
        $display("RESULT: PASS LANE4 record checks=%0d synthetic_records=5 physical_RAMs=3 extension_bits=3072 header_bytes=448",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"LANE4 record watchdog");end
endmodule
