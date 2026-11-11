`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
// Real official RAM, six persistent slots, two-pass replay and the C2H formatter.
module tb_sparse_transport;
    reg clk=0,rst_n=0;always #5 clk=~clk;
    reg [16383:0] source[0:5],expected[0:5];
    reg [16383:0] bad_vectors[0:5];
    reg stage_begin=0,stage_valid=0,stage_last=0;
    reg [127:0] stage_data=0;
    wire stage_ready,stage_complete,stage_good;
    wire stage_re;wire [8:0] stage_ri;wire [39:0] stage_rd;
    integer current=0,checks=0,k,n,limit,word_reads=0,stream_beats=0;
    reg begin_valid=0,ext_valid=0,proof_valid=0;
    reg [15:0] slot=0;reg [31:0] generation=0;
    wire begin_ready,ext_ready,proof_ready,write_quiet,read_quiet,fault,bad_seen;
    wire [31:0] stale,bad_count;wire [7:0] write_error;
    reg req_valid=0,rsp_ready=0,stream_start=0;
    reg [15:0] req_slot=0;reg [31:0] req_generation=0,req_sequence=0;
    reg req_camera=0;wire req_ready,rsp_valid,rsp_ok,rsp_shape;
    wire [7:0] rsp_error;wire [127:0] stream_data;wire stream_valid,stream_last,stream_ready;
    wire [31:0] sequence_id=100+current;
    wire camera=current>=3;
    ddr_extension_staging_ram #(.RECORD_EXTENSION_WIDTH(16384)) staging(
        .i_clk(clk),.i_rst_n(rst_n),.i_begin(stage_begin),.i_session(32'h12345678),
        .i_epoch(32'd300),.i_sequence(sequence_id),.i_camera(camera),
        .s_data(stage_data),.s_valid(stage_valid),.s_last(stage_last),.s_ready(stage_ready),
        .o_complete(stage_complete),.o_shape_valid(stage_good),
        .i_read_enable(stage_re),.i_read_index(stage_ri),.o_read_data(stage_rd));
    jpeg_record_metadata_store #(.RECORD_EXTENSION_WIDTH(16384),.BORROW_PENDING_EXTENSION(1),
        .STAGING_EXTENSION_ENABLE(1),.STREAM_READ(1)) store(
        .i_clk(clk),.i_rst_n(rst_n),.s_begin_valid(begin_valid),.s_begin_ready(begin_ready),
        .s_begin_writer_tag(sequence_id+1000),.s_begin_sequence(sequence_id),
        .s_begin_session(32'h12345678),.s_begin_epoch(32'd300),.s_begin_camera(camera),
        .s_extension(16384'd0),.s_extension_valid(ext_valid),.s_extension_ready(ext_ready),
        .s_extension_shape_valid(stage_good),.o_extension_read_enable(stage_re),
        .o_extension_read_index(stage_ri),.i_extension_read_data(stage_rd),
        .s_write_result_valid(proof_valid),.s_write_result_ready(proof_ready),
        .s_write_result_tag(sequence_id+1000),.s_write_result_sequence(sequence_id),
        .s_write_result_session(32'h12345678),.s_write_result_epoch(32'd300),.s_write_result_camera(camera),
        .s_write_result_slot(slot),.s_write_result_generation(generation),
        .s_write_result_ok(1'b1),.s_write_result_error(8'd0),
        .o_write_quiescent(write_quiet),.o_read_quiescent(read_quiet),.o_protocol_fault(fault),
        .o_stale_write_count(stale),.o_bad_extension_count(bad_count),.o_bad_extension_seen(bad_seen),.o_write_error(write_error),
        .s_read_req_valid(req_valid),.s_read_req_ready(req_ready),.s_read_req_slot(req_slot),
        .s_read_req_generation(req_generation),.s_read_req_session(32'h12345678),
        .s_read_req_sequence(req_sequence),.s_read_req_epoch(32'd300),.s_read_req_camera(req_camera),
        .o_metadata_available(),.m_read_rsp_valid(rsp_valid),.m_read_rsp_ready(rsp_ready),
        .m_read_rsp_ok(rsp_ok),.m_read_rsp_error(rsp_error),.m_read_rsp_slot(),.m_read_rsp_generation(),
        .m_read_rsp_session(),.m_read_rsp_sequence(),.m_read_rsp_epoch(),.m_read_rsp_camera(),
        .m_read_rsp_extension(),.s_read_req_version(16'd4),.m_read_rsp_shape_valid(rsp_shape),
        .s_read_stream_start(stream_start),.m_read_stream_data(stream_data),
        .m_read_stream_valid(stream_valid),.m_read_stream_last(stream_last),.m_read_stream_ready(stream_ready),
        .s_read_req_mask(1'b0),.m_read_rsp_mask_qualified(),.m_read_rsp_mask_pixels(),.m_read_rsp_source_type());

    reg meta_valid=0;wire meta_ready;
    reg [31:0] payload_length=1;
    reg [127:0] payload_data=0;reg [15:0] payload_keep=0;
    reg payload_valid=0,payload_last=0;wire payload_ready;
    wire [127:0] axis_data;wire [15:0] axis_keep;wire axis_valid,axis_last;
    reg axis_ready=0,transport=1;
    wire done,aborted,accepted;wire [31:0] last_error;
    c2h_frame_tx #(.RECORD_V2_ENABLE(1),.RECORD_V4_ENABLE(1),.RECORD_EXTENSION_WIDTH(16384),
        .BORROW_EXTENSION(1),.STREAM_EXTENSION(1)) tx(
        .i_clk(clk),.i_rst_n(rst_n),.i_transport_enable(transport),.i_link_up(1'b1),.i_c2h_running(1'b1),
        .i_meta_valid(meta_valid),.o_meta_ready(meta_ready),.i_meta_frame_sequence(req_sequence),
        .i_meta_payload_length(payload_length),.i_meta_width(16'd1920),.i_meta_height(16'd1080),
        .i_meta_pixel_format(8'd0),.i_meta_compression(8'd1),.i_meta_quality(8'd75),.i_meta_timestamp_ns(64'd0),
        .i_meta_status(32'd0),.i_meta_error_code(32'd0),.i_meta_slot_id(req_slot),
        .i_meta_payload_crc32(32'hc0ffee01),.i_meta_record_version(16'd4),.i_meta_record_extension(16384'd0),
        .i_extension_tdata(stream_data),.i_extension_tvalid(stream_valid),.i_extension_tlast(stream_last),
        .o_extension_tready(stream_ready),.i_src_tdata(payload_data),.i_src_tkeep(payload_keep),
        .i_src_tvalid(payload_valid),.o_src_tready(payload_ready),.i_src_tlast(payload_last),
        .o_axis_tdata(axis_data),.o_axis_tkeep(axis_keep),.o_axis_tuser(),.o_axis_tvalid(axis_valid),
        .i_axis_tready(axis_ready),.o_axis_tlast(axis_last),.o_tx_busy(),.o_transport_ready(),
        .o_active_slot_id(),.o_last_error(last_error),.o_frame_accept(accepted),.o_frame_done(done),.o_frame_abort(aborted));
    integer cycles=0,received=0,payload_received=0,active_read=0,stall_checks=0;
    reg monitor=0,held=0;reg [144:0] held_axis;
    always @(negedge clk)begin
        cycles=cycles+1;
        axis_ready=(cycles%7!=0 && cycles%11!=0 && cycles%13!=0);
    end
    task check(input bit condition,input string reason);
        begin checks++;if(!condition)$fatal(1,"SPARSE transport %s current=%0d time=%0t",reason,current,$time);end
    endtask
    always @(posedge clk)if(rst_n && monitor)begin
        if(held)begin check(axis_valid && {axis_last,axis_keep,axis_data}===held_axis,"AXIS stable in stall");stall_checks++;end
        held=axis_valid && !axis_ready;
        if(held)held_axis={axis_last,axis_keep,axis_data};
        if(axis_valid && axis_ready)begin
            if(received==0)check(axis_data[63:48]==2112 && axis_data[47:32]==4 && axis_data[95:64]==req_sequence,"base header version/length/source");
            if(received>=4 && received<132)check(axis_data===expected[active_read][(received-4)*128+:128],"six-slot extension exact bytes");
            if(received<132)check(axis_keep==16'hffff && !axis_last,"full header beat KEEP/LAST");
            else begin
                check(axis_keep==(payload_length-payload_received>=16 ? 16'hffff : (16'hffff>>(16-(payload_length-payload_received)))),"payload terminal KEEP");
                check(axis_last==(payload_length-payload_received<=16),"payload TLAST");
                payload_received=payload_received+$countones(axis_keep);
            end
            received++;
        end
        check(!aborted,"no formatter abort");
        if(stage_re)word_reads++;
        if(stream_valid && stream_ready)stream_beats++;
    end
    task stage_extension(input [16383:0] data);
        begin
            stage_begin=1;@(posedge clk);@(negedge clk);stage_begin=0;
            for(k=0;k<128;k++)begin
                stage_data=data[k*128+:128];stage_valid=1;stage_last=k==127;
                do @(posedge clk);while(!stage_ready);
                @(negedge clk);stage_valid=0;
                if(k%5==0)@(negedge clk);
            end
            stage_last=0;limit=0;
            while(!stage_complete)begin @(negedge clk);limit++;check(limit<20,"staging bounded tail");end
        end
    endtask
    task request(input bit wrong);
        begin
            req_generation=(active_read==0 && generation==99) ? (wrong ? 20 : 99) : 20+active_read+wrong;
            req_sequence=100+active_read;
            req_slot=active_read;req_camera=active_read>=3;req_valid=1;
            do @(posedge clk);while(!req_ready);
            @(negedge clk);req_valid=0;limit=0;
            while(!rsp_valid)begin @(negedge clk);limit++;check(limit<440,"metadata bounded validation");end
            check(wrong ? (!rsp_ok && !rsp_shape && rsp_error==1) : (rsp_ok && rsp_shape && rsp_error==0),"catalog identity and v4 shape");
        end
    endtask
    task length_probe(input [31:0] length,input bit legal);
        begin
            payload_length=length;meta_valid=1;
            do @(posedge clk);while(!meta_ready);
            @(negedge clk);meta_valid=0;
            check(legal ? (accepted && !aborted) : (!accepted && aborted),"metadata maximum length acceptance fence");
            if(legal)begin
                // No claim of a 16MiB payload run: abort this metadata-only probe.
                transport=0;@(posedge clk);@(negedge clk);
                check(aborted,"transport cancellation returns formatter to idle");
                transport=1;repeat(3)@(negedge clk);
            end
        end
    endtask
    integer order[0:5];integer sent,part,j;
    initial begin
        $readmemh("source.hex",source);$readmemh("expected.hex",expected);$readmemh("bad.hex",bad_vectors);
        order[0]=5;order[1]=1;order[2]=4;order[3]=0;order[4]=3;order[5]=2;
        repeat(12)@(negedge clk);rst_n=1;repeat(12)@(negedge clk);
        // Six independently held writer slots, including both camera partitions.
        for(n=0;n<6;n++)begin
            current=n;slot=n;generation=20+n;begin_valid=1;
            do @(posedge clk);while(!begin_ready);
            @(negedge clk);begin_valid=0;
            stage_extension(source[n]);check(stage_good,"staging accepts v4 count boundary");
            ext_valid=1;do @(posedge clk);while(!ext_ready);@(negedge clk);ext_valid=0;
            proof_valid=1;do @(posedge clk);while(!proof_ready);@(negedge clk);proof_valid=0;
            limit=0;while(!write_quiet)begin @(negedge clk);limit++;check(limit<430,"410-word copy bounded");end
            check(!fault && !bad_seen && bad_count==0 && stale==0 && write_error==0,"publication clean");
        end
        for(n=0;n<6;n++)begin
            active_read=order[n];request(1);check(!stream_valid,"stale generation cannot stream");
            rsp_ready=1;@(posedge clk);@(negedge clk);rsp_ready=0;repeat(4)@(negedge clk);
            request(0);
            received=0;payload_received=0;held=0;monitor=1;
            case(n)0:payload_length=1;1:payload_length=15;2:payload_length=16;3:payload_length=17;4:payload_length=31;default:payload_length=32;endcase
            meta_valid=1;do @(posedge clk);while(!meta_ready);@(negedge clk);meta_valid=0;
            stream_start=1;@(posedge clk);@(negedge clk);stream_start=0;
            limit=0;while(received<132)begin
                @(negedge clk);limit++;check(limit<3500,"128-flit replay bounded");
                if(received<132)check(!begin_ready,"borrowed header retains metadata owner");
            end
            rsp_ready=1;@(posedge clk);@(negedge clk);rsp_ready=0;
            sent=0;
            while(sent<payload_length)begin
                part=payload_length-sent>=16?16:payload_length-sent;
                payload_data=0;for(j=0;j<part;j++)payload_data[j*8+:8]=sent+j;
                payload_keep=16'hffff>>(16-part);payload_last=sent+part==payload_length;payload_valid=1;
                do @(posedge clk);while(!payload_ready);
                @(negedge clk);payload_valid=0;sent=sent+part;
            end
            limit=0;while(!done)begin @(negedge clk);limit++;check(limit<30,"last payload handshake releases frame");end
            check(payload_received==payload_length && received==132+(payload_length+15)/16,"132 header beats plus payload");
            monitor=0;repeat(5)@(negedge clk);
        end
        // Reusing one slot invalidates the old generation while other slots survive.
        current=0;slot=0;generation=99;begin_valid=1;do @(posedge clk);while(!begin_ready);@(negedge clk);begin_valid=0;
        stage_extension(source[0]);ext_valid=1;do @(posedge clk);while(!ext_ready);@(negedge clk);ext_valid=0;
        proof_valid=1;do @(posedge clk);while(!proof_ready);@(negedge clk);proof_valid=0;
        while(!write_quiet)@(negedge clk);
        active_read=0;request(1);check(!rsp_ok,"old generation rejected after slot reuse");
        // malformed count, point reserved, padding, ordering, disabled, and local-error count
        for(n=0;n<6;n++)begin current=0;stage_extension(bad_vectors[n]);check(!stage_good,"invalid extension fails closed");end
        length_probe(0,0);length_probe(`PCIE_MAX_PAYLOAD-1,1);
        length_probe(`PCIE_MAX_PAYLOAD,1);length_probe(`PCIE_MAX_PAYLOAD+1,0);
        check(!fault,"no global metadata protocol fault from read staleness");
        $display("RESULT: PASS SPARSE_TRANSPORT checks=%0d stalls=%0d stream_beats=%0d",checks,stall_checks,stream_beats);$finish;
    end
    initial begin #3000000;$fatal(1,"SPARSE transport watchdog");end
endmodule
