`timescale 1ns / 1ps

module tb_shared_decode_start;
    // 20 bytes over two 128-bit reads. The split base gives two bursts at a
    // real 4 KiB boundary. The other base gives one two-beat burst.
    localparam int WIDTH=8, HEIGHT=2, GROUPS=4;
    localparam [27:0] SPLIT_BASE=28'h2000ff0, ALIGNED_BASE=28'h2000100;
    bit clk=0, rst_n=0;
    always #4 clk=~clk;
    bit start=0, cancel=0, token_ready=1, done_ready=0;
    reg [27:0] frame_base=0;
    reg [63:0] job_id=64'h810000002dca0000;
    wire start_ready, done_valid, done_ok, bus_quiet, fault;
    wire [146:0] token;
    wire token_valid;
    wire dec_start, dec_start_ready, dec_release, dec_cancel, dec_run;
    wire [127:0] dec_data;
    wire [15:0] dec_keep;
    wire dec_valid, dec_last, dec_ready;
    wire [39:0] raw;
    wire raw_valid, raw_ready, raw_sof, raw_eol, dec_done, dec_abort, dec_quiet, dec_active, service_quiet;
    wire [3:0] arid;
    wire [27:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arvalid, rready;
    bit arready=0, rvalid=0, rlast=0;
    reg [127:0] rdata=0;

    stereo_raw_reader #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.EXTERNAL_DECODER(1),.VERIFY_DECODE_ACTIVE(1)) reader (
        .clk(clk),.rst_n(rst_n),.i_start_valid(start),.o_start_ready(start_ready),
        .i_base(frame_base),.i_job_id(job_id),.i_cancel(cancel),
        .m_data(token),.m_valid(token_valid),.m_ready(token_ready),
        .o_done_valid(done_valid),.o_done_ok(done_ok),.i_done_ready(done_ready),
        .o_bus_quiet(bus_quiet),.o_fault(fault),
        .o_decode_start_valid(dec_start),.i_decode_start_ready(dec_start_ready),
        .o_decode_release(dec_release),.o_decode_cancel(dec_cancel),.o_decode_run(dec_run),
        .o_decode_data(dec_data),.o_decode_keep(dec_keep),.o_decode_valid(dec_valid),
        .o_decode_last(dec_last),.i_decode_ready(dec_ready),.i_decode_raw(raw),
        .i_decode_raw_valid(raw_valid),.o_decode_raw_ready(raw_ready),
        .i_decode_sof(raw_sof),.i_decode_eol(raw_eol),.i_decode_done(dec_done),
        .i_decode_aborted(dec_abort),.i_decode_quiet(dec_quiet),.i_decode_active(dec_active),
        .m_axi_arid(arid),.m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),
        .m_axi_arburst(arburst),.m_axi_arvalid(arvalid),.m_axi_arready(arready),
        .m_axi_rid(4'd1),.m_axi_rdata(rdata),.m_axi_rresp(2'b00),.m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid),.m_axi_rready(rready));

    shared_raw10_decode_service #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) service (
        .clk(clk),.rst_n(rst_n),.hdr_start_valid(1'b0),.hdr_start_ready(),
        .hdr_release(1'b0),.hdr_abort(2'b00),.hdr_member(1'b0),.hdr_data(128'd0),
        .hdr_keep(16'd0),.hdr_valid(1'b0),.hdr_last(1'b0),.hdr_ready(),
        .hdr_raw_member(),.hdr_raw(),.hdr_raw_valid(),.hdr_raw_ready(1'b0),.hdr_done(),.hdr_aborted(),
        .stereo_start_valid(dec_start),.stereo_start_ready(dec_start_ready),
        .stereo_release(dec_release),.stereo_cancel(dec_cancel),.stereo_run(dec_run),
        .stereo_data(dec_data),.stereo_keep(dec_keep),.stereo_valid(dec_valid),.stereo_last(dec_last),
        .stereo_ready(dec_ready),.stereo_raw(raw),.stereo_raw_valid(raw_valid),.stereo_raw_ready(raw_ready),
        .stereo_sof(raw_sof),.stereo_eol(raw_eol),.stereo_done(dec_done),.stereo_aborted(dec_abort),
        .stereo_quiet(dec_quiet),.stereo_active(dec_active),.quiet(service_quiet));

    string scenario;
    int ar_offers=0, ar_count=0, r_count=0, promised_beats=0, data_count=0, fence_count=0;
    bit was_ar=0, held_ar=0, held_token=0, saw_active=0, saw_done=0, fence_ok=0;
    reg [44:0] previous_ar;
    reg [146:0] previous_token;
    reg [7:0] fence_error=0;

    function automatic [9:0] sample(input int i);
        sample=10'(901+137*i);
    endfunction

    function automatic [127:0] packed_beat(input int byte_offset);
        reg [159:0] frame;
        for (int i=0;i<16;i++) frame[10*i+:10]=sample(i);
        packed_beat=128'(frame >> (8*byte_offset));
    endfunction

    function automatic [55:0] expanded_group(input int group_index);
        for (int lane=0;lane<4;lane++)
            expanded_group[14*lane+:14]={4'd0,sample(4*group_index+lane)};
    endfunction

    task automatic check(input bit ok, input string message);
        if (!ok) $fatal(1,"%s at %0t AR=%0d R=%0d DATA=%0d: %s",
                        scenario,$time,ar_count,r_count,data_count,message);
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            held_ar=0;
            held_token=0;
            was_ar=0;
        end else begin
            if (held_ar)
                check(arvalid && {arid,araddr,arlen,arsize,arburst}===previous_ar,"stalled AR was revoked or changed");
            if (held_token)
                check(token_valid && token===previous_token,"stalled DATA/FENCE was revoked or changed");
            held_ar=arvalid && !arready;
            held_token=token_valid && !token_ready;
            if (held_ar) previous_ar={arid,araddr,arlen,arsize,arburst};
            if (held_token) previous_token=token;
            if (dec_active) saw_active=1;
            if (dec_done) begin
                saw_done=1;
                check(!dec_active,"core terminal failed to release activity");
            end
            if (arvalid && !was_ar) begin
                ar_offers++;
                check(saw_active && dec_active,"new AR without live shared context");
            end
            was_ar=arvalid;
            if (arvalid && arready) begin
                check(promised_beats==0,"more than one outstanding burst");
                check(arid==1 && arsize==4 && arburst==1,"wrong AXI read shape");
                promised_beats=int'(arlen)+1;
                ar_count++;
            end
            if (rvalid && rready) begin
                check(promised_beats>0 && rlast==(promised_beats==1),"R escaped its promised AR");
                promised_beats--;
                r_count++;
            end
            if (token_valid && token_ready) begin
                check(fence_count==0,"second token after FENCE");
                case (token[146:145])
                    0:begin
                        check(data_count<GROUPS && token[144:135]==0 && token[134:103]==data_count &&
                              token[102]==(data_count==GROUPS-1) && token[101]==(data_count%2==1) &&
                              token[100]==(data_count==0) && token[99:96]==4'hf && token[95:56]==0 &&
                              token[55:0]===expanded_group(data_count),"incorrect RAW DATA, identity or boundary");
                        data_count++;
                    end
                    1:begin
                        check(promised_beats==0 && token[144:105]==0 && token[95:32]==job_id &&
                              token[31:0]==data_count,"FENCE did not follow drained AXI/DATA or lost identity");
                        fence_ok=token[96];
                        fence_error=token[104:97];
                        fence_count++;
                    end
                    default:check(0,"unknown token kind");
                endcase
            end
            if (done_valid) check(fence_count==1,"terminal before real FENCE transfer");
        end
    end

    task automatic start_job(input string label, input [27:0] base);
        @(negedge clk);
        scenario=label;
        check(start_ready && service_quiet && !dec_active && !fault,"previous owner did not release");
        ar_offers=0;
        ar_count=0;
        r_count=0;
        data_count=0;
        fence_count=0;
        saw_active=0;
        saw_done=0;
        frame_base=base;
        job_id++;
        start=1;
        @(negedge clk);
        start=0;
        check(!dec_active && !arvalid && !start_ready,"outer grant was treated as a core START");
    endtask

    task automatic accept_address(input [27:0] addr, input int beats);
        while (!arvalid) @(negedge clk);
        check(araddr==addr && arlen==beats-1,"wrong burst address or size");
        arready=1;
        @(negedge clk);
        arready=0;
        check(!arvalid,"AR remained after acceptance");
    endtask

    task automatic offer_response(input int offset, input bit last);
        check(!rvalid,"response already offered");
        rdata=packed_beat(offset);
        rlast=last;
        rvalid=1;
    endtask

    task automatic finish_response();
        do @(posedge clk); while (!rready);
        @(negedge clk);
        rvalid=0;
    endtask

    task automatic respond(input int offset, input bit last);
        offer_response(offset,last);
        finish_response();
    endtask

    task automatic lose_context();
        check(dec_active && !dec_done && !dec_abort,"fault injection needs live core context");
        // Clear only the selected core cursor and byte ownership. There is no
        // reset, synthetic terminal pulse or change to an AXI/FIFO handshake.
        force service.u_decoder.state_long=2'b00;
        force service.u_decoder.pack_bytes=5'd0;
        #1;
        check(!dec_active && !dec_done && !dec_abort,"lost context must have no positive terminal");
        @(negedge clk);
        release service.u_decoder.state_long;
        release service.u_decoder.pack_bytes;
        #1;
        check(!dec_active,"lost core context unexpectedly reappeared");
    endtask

    task automatic finish_job(input bit expected_ok, input [7:0] error_code,
                              input int addresses, responses, groups);
        while (!done_valid) @(negedge clk);
        check(done_ok===expected_ok && fence_ok===expected_ok && fence_error===error_code,
              "incorrect terminal result");
        check(ar_offers==addresses && ar_count==addresses && r_count==responses &&
              promised_beats==0 && data_count==groups && fence_count==1,
              "wrong total AR/R/DATA/FENCE count");
        check(bus_quiet && !fault && !dec_active && dec_quiet,"not fully drained at result");
        repeat (3) begin
            @(negedge clk);
            check(done_valid && done_ok===expected_ok && !start_ready && !service_quiet,
                  "owner released before terminal handshake");
        end
        done_ready=1;
        @(negedge clk);
        done_ready=0;
        check(start_ready && service_quiet && !done_valid,"terminal handshake did not release owner");
        $display("CASE: %s ar=%0d r=%0d groups=%0d ok=%0d error=%0d",
                 scenario,ar_count,r_count,data_count,expected_ok,error_code);
    endtask

    task automatic good_frame(input string label);
        start_job(label,SPLIT_BASE);
        accept_address(SPLIT_BASE,1);
        respond(0,1);
        accept_address(SPLIT_BASE+16,1);
        respond(16,1);
        finish_job(1,0,2,2,GROUPS);
        check(saw_active && saw_done,"normal frame lacked real decoder activity or terminal");
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n=1;
        good_frame("first healthy read");

        force service.u_decoder.i_start=1'b0;
        start_job("missed inner START",SPLIT_BASE);
        repeat (3) @(negedge clk);
        release service.u_decoder.i_start;
        finish_job(0,6,0,0,0);
        check(!saw_active && !saw_done,"suppressed START produced a core context or terminal");

        start_job("lost context before AR",SPLIT_BASE);
        wait (reader.state==reader.PLAN);
        @(negedge clk);
        check(!arvalid,"fault injection too late for first AR planning");
        lose_context();
        finish_job(0,6,0,0,0);

        start_job("lost context between bursts",SPLIT_BASE);
        accept_address(SPLIT_BASE,1);
        respond(0,1);
        check(!arvalid && ar_count==1 && r_count==1,"fault injection outside the burst boundary");
        lose_context();
        finish_job(0,6,1,1,0);

        start_job("lost context after final R",SPLIT_BASE);
        accept_address(SPLIT_BASE,1);
        respond(0,1);
        accept_address(SPLIT_BASE+16,1);
        respond(16,1);
        check(raw_valid && r_count==2 && !saw_done,"fault injection missed the final buffered group");
        lose_context();
        finish_job(0,6,2,2,3);

        start_job("STOP with offered AR and DATA",SPLIT_BASE);
        token_ready=0;
        accept_address(SPLIT_BASE,1);
        respond(0,1);
        while (!(arvalid && token_valid)) @(negedge clk);
        cancel=1;
        repeat (4) begin
            @(negedge clk);
            check(arvalid && token_valid && !done_valid,"STOP revoked the offered AR or DATA");
        end
        accept_address(SPLIT_BASE+16,1);
        respond(16,1);
        repeat (4) begin
            @(negedge clk);
            check(token_valid && token[146:145]==0 && !done_valid,"FENCE overtook stalled DATA");
        end
        token_ready=1;
        finish_job(0,1,2,2,1);
        cancel=0;

        start_job("STOP with stalled R and DATA",ALIGNED_BASE);
        token_ready=0;
        accept_address(ALIGNED_BASE,2);
        respond(0,0);
        while (!token_valid) @(negedge clk);
        offer_response(16,1);
        repeat (3) begin
            @(negedge clk);
            check(!rready && token_valid && !done_valid,"test did not stall an accepted burst and DATA");
        end
        cancel=1;
        finish_response();
        check(r_count==2 && token_valid && token[146:145]==0 && !done_valid,
              "STOP failed to drain R while holding DATA");
        token_ready=1;
        finish_job(0,1,1,2,1);
        cancel=0;

        good_frame("healthy read after failures");
        $display("RESULT: PASS shared_decode_start");
        $finish;
    end

    initial begin
        #40_000;
        $fatal(1,"shared decoder lifecycle timeout in %s",scenario);
    end
endmodule
