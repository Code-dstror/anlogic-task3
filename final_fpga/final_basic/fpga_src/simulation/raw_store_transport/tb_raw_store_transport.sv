`timescale 1ns / 1ps

module tb_raw_store_transport;
    localparam [15:0] WIDTH=8,HEIGHT=2;
    localparam [31:0] SESSION=7,EPOCH=3,FRAME_BYTES=20;
    localparam [127:0] FIRST_BEAT=128'h0f0e0d0c0b0a09080706050403020100;
    localparam [127:0] LAST_BEAT=128'hfedcba9876543210fedcba9813121110;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg stop=0,begin_valid=0,begin_camera=0;
    reg [383:0] capture_frame=0;
    reg [1:0] finish_valid=0,finish_ok=0;
    wire begin_ready,begin_accepted;
    wire [1:0] capture_slot,finish_ready;
    wire [383:0] job_frame;
    wire [63:0] job_id;
    wire [1:0] job_bayer;
    wire job_time_valid,legacy_job,legacy_valid,decode_valid;
    wire retire_done,retire_error,empty,fault,read_quiet;

    reg record_enable=0,output_ready=1,retire_valid=0;
    reg [127:0] retire_identity=0;
    wire record_valid,retire_ready;
    wire [31:0] record_length;
    wire [127:0] record_identity,raw_data,wire_data;
    wire [15:0] raw_keep,wire_keep;
    wire raw_valid,raw_last,raw_ready,raw_done,raw_ok,raw_drained;
    wire formatter_ready,formatter_drained,formatter_done,wire_valid,wire_last;

    wire [3:0] arid;
    wire [27:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arvalid,rready;
    reg arready=0,rvalid=0,rlast=0;
    reg [1:0] rresp=0;
    reg [127:0] rdata=0;

    stereo_raw_store #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.EXTERNAL_DECODER(1),
        .RAW_EXPORT_ENABLE(1),.VERIFY_DECODE_ACTIVE(1)) dut(
        .clk(clk),.rst_n(rst_n),.i_enable(1'b1),.i_stop(stop),.i_session(SESSION),.i_epoch(EPOCH),
        .s_frame(capture_frame),.s_begin_valid(begin_valid),.i_begin_camera(begin_camera),
        .s_begin_ready(begin_ready),.o_begin_accepted(begin_accepted),.o_capture_slot(capture_slot),
        .i_finish_valid(finish_valid),.i_finish_ok(finish_ok),.o_finish_ready(finish_ready),
        .o_job_valid(legacy_job),.i_job_ready(1'b0),.o_job_frame(job_frame),.o_job_lease(),
        .o_job_id(job_id),.o_job_bayer(job_bayer),.o_job_time_valid(job_time_valid),
        .i_retire_valid(1'b0),.i_retire_job_id(64'd0),.i_release_quiet(1'b1),
        .o_retire_ready(),.o_retire_done(retire_done),.o_retire_error(retire_error),
        .i_req_valid(1'b0),.o_req_ready(),.i_req_op(3'd0),.i_req_camera(1'b0),.i_req_slot(2'd0),
        .i_req_generation(32'd0),.i_req_session(32'd0),.i_req_lease(64'd0),.i_req_job_id(64'd0),
        .o_rsp_valid(),.i_rsp_ready(1'b1),.o_rsp_code(),.o_rsp_camera(),.o_rsp_slot(),
        .o_rsp_generation(),.o_rsp_session(),.o_rsp_sequence(),.o_rsp_epoch(),
        .i_processing_done(1'b0),.i_processing_error(1'b0),.i_processing_job_id(64'd0),
        .o_native_done(),.o_native_error(),.o_native_job_id(),
        .m_fifo_data(),.m_fifo_valid(legacy_valid),.m_fifo_ready(1'b0),
        .o_read_quiet(read_quiet),.o_empty(empty),.o_fault(fault),
        .o_decode_start_valid(),.i_decode_start_ready(1'b0),.o_decode_release(),.o_decode_cancel(),.o_decode_run(),
        .o_decode_data(),.o_decode_keep(),.o_decode_valid(decode_valid),.o_decode_last(),.i_decode_ready(1'b0),
        .i_decode_raw(40'd0),.i_decode_raw_valid(1'b0),.o_decode_raw_ready(),.i_decode_sof(1'b0),.i_decode_eol(1'b0),
        .i_decode_done(1'b0),.i_decode_aborted(1'b0),.i_decode_quiet(1'b0),.i_decode_active(1'b0),
        .m_axi_arid(arid),.m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),
        .m_axi_arburst(arburst),.m_axi_arvalid(arvalid),.m_axi_arready(arready),
        .m_axi_rid(4'd1),.m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid),.m_axi_rready(rready),
        .i_raw_export(1'b1),.i_raw_cancel(1'b0),.o_raw_record_valid(record_valid),
        .i_raw_record_ready(record_enable&&formatter_ready),.o_raw_record_length(record_length),
        .o_raw_record_identity(record_identity),.o_raw_data(raw_data),.o_raw_keep(raw_keep),
        .o_raw_valid(raw_valid),.o_raw_last(raw_last),.i_raw_ready(raw_ready),
        .o_raw_done_valid(raw_done),.o_raw_done_ok(raw_ok),.o_raw_drained(raw_drained),
        .i_raw_retire_valid(retire_valid),.o_raw_retire_ready(retire_ready),.i_raw_retire_identity(retire_identity));

    raw_video_record_formatter formatter(
        .i_clk(clk),.i_rst_n(rst_n),.i_start_valid(record_enable&&record_valid),.o_start_ready(formatter_ready),
        .i_abort(raw_done&&!raw_ok),.o_drained(formatter_drained),.i_payload_bytes(FRAME_BYTES),
        .i_width(job_frame[220:205]),.i_height(job_frame[236:221]),.i_sequence(job_frame[108:77]),
        .i_session(job_frame[76:45]),.i_epoch(job_frame[140:109]),.i_camera(job_frame[4]),
        .i_bayer_phase(job_bayer),.i_time_valid(job_time_valid),.i_capture_time_ns(job_frame[204:141]),.i_job_id(job_id),
        .s_data(raw_data),.s_keep(raw_keep),.s_valid(raw_valid),.s_last(raw_last),.s_ready(raw_ready),
        .m_data(wire_data),.m_keep(wire_keep),.m_valid(wire_valid),.m_last(wire_last),
        .m_ready(output_ready),.o_done(formatter_done));

    integer checks=0,phase=0,payload_count=0,wire_count=0,wire_success=0;
    reg [127:0] first_header=0;
    always @(posedge clk)if(rst_n)begin
        if(raw_valid&&raw_ready)payload_count++;
        if(wire_valid&&output_ready)begin
            if(wire_count==0)first_header=wire_data;
            wire_count++;
        end
        if(formatter_done)wire_success++;
        if(legacy_valid||legacy_job||decode_valid)$fatal(1,"RAW leaked a JPEG replay token");
    end

    task automatic check(input logic condition,input string reason);
        checks++;
        if(condition!==1'b1)$fatal(1,"phase=%0d %s",phase,reason);
    endtask

    // The writer's BEGIN and matching SOURCE/all-B terminal are the fixture
    // boundary. The directory, slot arbitration and AXI reader are production.
    task automatic begin_frame(input bit eye,input [31:0] seq,output reg [1:0] slot);
        @(negedge clk);
        capture_frame=0;
        capture_frame[371:368]=4'b1110;
        capture_frame[238:237]=2'd1;
        capture_frame[236:221]=HEIGHT;
        capture_frame[220:205]=WIDTH;
        capture_frame[204:141]=64'd2000+seq;
        capture_frame[140:109]=EPOCH;
        capture_frame[108:77]=seq;
        capture_frame[76:45]=SESSION;
        capture_frame[4]=eye;
        begin_camera=eye;begin_valid=1;
        do @(posedge clk);while(!begin_ready);
        check(begin_accepted,"capture uses an available slot");
        slot=capture_slot;
        @(negedge clk);begin_valid=0;
    endtask

    task automatic finish_frame(input bit eye,input bit success);
        @(negedge clk);
        check(finish_ready[eye],"matching allocated writer ready for terminal");
        finish_valid[eye]=1;finish_ok[eye]=success;
        @(negedge clk);finish_valid=0;
    endtask

    task automatic take_record(input bit eye,input [31:0] seq,input [1:0] slot,output reg [127:0] identity);
        wait(record_valid);
        identity=record_identity;
        repeat(4)begin
            @(negedge clk);
            check(record_valid&&record_identity==identity&&!arvalid,"record offer and identity hold before acceptance");
        end
        check(record_length==64+FRAME_BYTES&&job_frame[4]==eye&&job_frame[108:77]==seq,
            "metadata and packed payload length from the reserved frame");
        check(identity=={16'h5241,SESSION,job_frame[44:13],13'd0,eye,slot,seq},"record identity binds the exact eye and slot");
        record_enable=1;
        @(negedge clk);record_enable=0;
    endtask

    task automatic accept_address(input bit eye,input [1:0] slot);
        wait(arvalid);
        repeat(4)begin
            @(negedge clk);
            check(arvalid&&araddr==28'h2000000+{1'b0,eye,26'd0}+{2'd0,slot,24'd0},"held AR targets the leased frame");
            check(arid==1&&arlen==1&&arsize==4&&arburst==1,"20 packed bytes use a bounded two-beat burst");
        end
        arready=1;
        @(negedge clk);arready=0;
    endtask

    task automatic send_beat(input [127:0] data,input bit last,input [1:0] response);
        @(negedge clk);rvalid=1;rdata=data;rlast=last;rresp=response;
        do @(posedge clk);while(!rready);
        @(negedge clk);rvalid=0;
    endtask

    task automatic safe_ack(input [127:0] identity,input bit expected_ready);
        @(negedge clk);retire_valid=1;retire_identity=identity;
        @(posedge clk);check(retire_ready==expected_ready,"only the drained matching SAFE is accepted");
        @(negedge clk);retire_valid=0;
        if(expected_ready)begin
            wait(retire_done);
            check(!retire_error,"SAFE releases the exact RAW owner");
            @(negedge clk);
        end
    endtask
    reg [1:0] slot0,slot1;
    reg [127:0] identity;
    integer before_payload;
    initial begin
        repeat(8)@(negedge clk);rst_n=1;
        repeat(8)@(negedge clk);
        check(empty&&read_quiet&&!fault,"fresh cold cohort");

        phase=1;
        begin_frame(0,10,slot0);
        repeat(24)@(negedge clk);
        check(!record_valid&&!arvalid,"writing frame cannot publish an unqualified record");
        finish_frame(0,1);
        take_record(0,10,slot0,identity);
        accept_address(0,slot0);
        send_beat(FIRST_BEAT,0,0);
        output_ready=0;
        fork
            send_beat(LAST_BEAT,1,0);
            begin
                wait(raw_valid);
                repeat(12)begin
                    @(posedge clk);
                    check(wire_valid&&wire_last&&wire_keep==16'h000f&&wire_data==LAST_BEAT&&!rready&&!raw_done,
                        "partial last beat holds end to end under finite backpressure");
                end
                @(negedge clk);output_ready=1;
            end
        join
        wait(raw_done&&formatter_drained);
        check(raw_ok&&raw_drained&&wire_count==6&&payload_count==2&&wire_success==1,
            "four header beats and two packed beats complete with true reader terminal");
        check(first_header[31:0]==32'h57415241,"RAW record has independent ARAW magic");
        begin_frame(1,20,slot1);
        repeat(20)begin
            @(negedge clk);
            check(!empty&&!retire_done&&!record_valid&&record_identity==identity&&finish_ready[1],
                "host ACK delay keeps old slot while other eye owns a write");
        end
        safe_ack(identity^128'd1,0);
        check(!empty&&raw_done&&!retire_done,"wrong identity cannot release ownership");
        safe_ack(identity,1);
        check(finish_ready[1],"other eye still writing after local retirement");

        phase=2;
        finish_frame(1,1);
        take_record(1,20,slot1,identity);
        accept_address(1,slot1);
        wait(raw_ready);
        @(negedge clk);output_ready=0;before_payload=payload_count;
        fork
            begin send_beat(FIRST_BEAT,0,0);send_beat(LAST_BEAT,1,0);end
            begin
                wait(raw_valid);
                repeat(3)@(negedge clk);
                stop=1;
                repeat(8)begin
                    @(posedge clk);
                    check(wire_valid&&!wire_last&&wire_data==FIRST_BEAT&&!rready&&!raw_done,
                        "STOP preserves the already presented RAW beat");
                end
                @(negedge clk);output_ready=1;
            end
        join
        wait(raw_done&&formatter_drained);
        check(!raw_ok&&raw_drained&&payload_count==before_payload+1&&wire_success==1,
            "STOP drains the accepted burst and emits no successful terminal");
        safe_ack(identity,1);
        stop=0;

        phase=3;
        begin_frame(0,29,slot0);
        finish_frame(0,0);
        repeat(24)@(negedge clk);
        check(empty&&!record_valid,"bad capture terminal never reaches the record outlet");
        begin_frame(0,30,slot0);
        finish_frame(0,1);
        take_record(0,30,slot0,identity);
        accept_address(0,slot0);
        before_payload=payload_count;
        send_beat(FIRST_BEAT,0,2);
        send_beat(LAST_BEAT,1,0);
        wait(raw_done&&formatter_drained);
        check(!raw_ok&&raw_drained&&!fault&&payload_count==before_payload,"RRESP failure drains without publishing packed bytes");
        safe_ack(identity,1);

        phase=4;
        begin_frame(0,35,slot0);
        finish_frame(0,1);
        wait(dut.u_owner.directory_valid&&dut.u_owner.directory_last);
        // Registered STOP and the directory's final read arrive together.
        @(posedge clk);stop<=1;
        @(negedge clk);
        check(!record_valid&&!arvalid&&!raw_done,"STOP wins before an unpresented record offer");
        wait(empty);
        check(read_quiet&&!arvalid&&!raw_done,"unexposed slot releases without a DMA terminal");
        @(negedge clk);stop=0;

        phase=5;
        begin_frame(0,36,slot0);
        finish_frame(0,1);
        wait(record_valid);
        @(posedge clk);@(negedge clk);stop=1;
        before_payload=payload_count;
        take_record(0,36,slot0,identity);
        wait(raw_done&&formatter_drained);
        check(!raw_ok&&raw_drained&&!arvalid&&payload_count==before_payload,
            "STOP preserves an already held offer then ends it without launching AR");
        safe_ack(identity,1);
        stop=0;

        phase=6;
        begin_frame(0,40,slot0);
        finish_frame(0,1);
        take_record(0,40,slot0,identity);
        accept_address(0,slot0);
        send_beat(FIRST_BEAT,1,0);
        repeat(12)@(negedge clk);
        check(fault&&!read_quiet&&!raw_done&&!raw_drained&&rready,"short RLAST leaves the missing response debt outstanding");
        safe_ack(identity,0);
        send_beat(LAST_BEAT,1,0);
        wait(raw_done&&formatter_drained);
        check(fault&&!raw_ok&&!raw_drained&&!empty,"AXI shape fault retains the lease until cold recovery");
        safe_ack(identity,0);
        $display("RESULT: PASS RAW_STORE_TRANSPORT checks=%0d",checks);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1,"RAW store watchdog phase=%0d ar=%b r=%b/%b record=%b raw=%b done=%b fault=%b",
            phase,arvalid,rvalid,rready,record_valid,raw_valid,raw_done,fault);
    end
endmodule
