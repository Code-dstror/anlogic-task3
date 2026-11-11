`timescale 1ns / 1ps

module tb_raw_video_record;
    bit clk=0, rst_n=0, start=0, abort_record=0, m_ready=0, s_valid=0, s_last=0;
    always #4 clk=~clk;

    int case_id=0;
    reg [31:0] payload_bytes=0, sequence_id=0, session_id=0, epoch=0;
    reg [15:0] width=0, height=0, s_keep=0;
    bit camera=0, time_valid=0;
    reg [1:0] bayer=0;
    reg [63:0] time_ns=0, job_id=0;
    reg [127:0] s_data=0;
    wire start_ready, drained, done, s_ready, m_valid, m_last;
    wire [127:0] m_data;
    wire [15:0] m_keep;
    raw_video_record_formatter dut (
        .i_clk(clk), .i_rst_n(rst_n), .i_start_valid(start), .o_start_ready(start_ready),
        .i_abort(abort_record), .o_drained(drained), .i_payload_bytes(payload_bytes),
        .i_width(width), .i_height(height), .i_sequence(sequence_id), .i_session(session_id),
        .i_epoch(epoch), .i_camera(camera), .i_bayer_phase(bayer), .i_time_valid(time_valid),
        .i_capture_time_ns(time_ns), .i_job_id(job_id), .s_data(s_data), .s_keep(s_keep),
        .s_valid(s_valid), .s_last(s_last), .s_ready(s_ready), .m_data(m_data),
        .m_keep(m_keep), .m_valid(m_valid), .m_last(m_last), .m_ready(m_ready), .o_done(done));

    bit capture=0, trace_small=0, continuous=0, held=0;
    reg [144:0] held_beat;
    int header_beats=0, body_bytes=0, done_count=0, last_stalls=0;
    int trace_file;
    reg [31:0] random_state=32'h2367af65;

    function automatic [127:0] test_beat(input int tag, input int index);
        reg [31:0] word;
        word=(tag<<20)^index;
        test_beat={~word,word+32'h13579bdf,word^32'h89abcdef,word};
    endfunction

    function automatic [15:0] low_keep(input int bytes_this_beat);
        low_keep=16'hffff >> (16-bytes_this_beat);
    endfunction

    task automatic check(input bit good, input string message);
        if (!good) $fatal(1,"case=%0d header=%0d body=%0d %s",case_id,header_beats,body_bytes,message);
    endtask

    always @(posedge clk) begin : monitor
        int bytes_this_beat;
        if (!rst_n) held=0;
        else begin
            if (held)
                check(m_valid && {m_data,m_keep,m_last}===held_beat,"output changed under stall");
            held=m_valid && !m_ready;
            if (held) held_beat={m_data,m_keep,m_last};
            check(done===(m_valid && m_ready && m_last && !abort_record),"wrong success handshake");
            if (done) done_count++;
            if (capture) begin
                if (continuous && header_beats==4 && body_bytes<payload_bytes)
                    check(m_valid && m_ready && s_ready,"body stalled with both sides ready");
                if (m_valid && !m_ready && m_last) last_stalls++;
                if (m_valid && m_ready) begin
                    check(!start_ready && !drained,"offered beat has no active owner");
                    if (trace_small)
                        $fdisplay(trace_file,"%0d %032h %04h %0d",case_id,m_data,m_keep,m_last);
                    if (header_beats<4) begin
                        check(m_keep===16'hffff && !m_last && !s_ready,"header or premature body consume");
                        header_beats++;
                    end else begin
                        check(body_bytes<payload_bytes,"body overrun");
                        bytes_this_beat=payload_bytes-body_bytes;
                        if (bytes_this_beat>16) bytes_this_beat=16;
                        check(s_valid && s_ready && m_keep===low_keep(bytes_this_beat) &&
                            m_last===(body_bytes+bytes_this_beat==payload_bytes) &&
                            m_data===test_beat(case_id,body_bytes>>4),"body byte, KEEP or LAST mismatch");
                        body_bytes+=bytes_this_beat;
                    end
                end
            end
        end
    end

    task automatic offer_start();
        check(start_ready && drained,"new START without idle formatter");
        start=1;
        @(negedge clk);
        start=0;
        check(!start_ready && !drained && m_valid,"START did not offer the first header");
    endtask

    task automatic send_record(input int tag, length, cols, rows, input bit stress, trace);
        int head_wait, tail_wait, left;
        case_id=tag;
        payload_bytes=length;
        width=16'(cols);
        height=16'(rows);
        sequence_id=32'h91a20000 | tag;
        session_id=32'h78563412;
        epoch=32'hfedc0000 | tag;
        camera=1'(tag);
        bayer=2'(tag-1);
        time_valid=(tag&2)!=0;
        time_ns=64'h8877665544332200 | 64'(tag);
        job_id=64'h80000000dceb0000 | 64'(tag);
        header_beats=0;
        body_bytes=0;
        done_count=0;
        last_stalls=0;
        head_wait=0;
        tail_wait=0;
        capture=1;
        trace_small=trace;
        continuous=!stress;
        offer_start();
        while (!drained) begin
            left=length-body_bytes;
            s_data=test_beat(tag,body_bytes>>4);
            s_keep=low_keep(left>16 ? 16 : left);
            s_last=left<=16;
            s_valid=1;
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            if (stress && header_beats==0 && head_wait<4) begin
                m_ready=0;
                head_wait++;
            end else if (stress && header_beats==4 && s_last && tail_wait<4) begin
                m_ready=0;
                tail_wait++;
            end else m_ready=!stress || random_state[1:0]!=0;
            @(negedge clk);
        end
        s_valid=0;
        m_ready=0;
        capture=0;
        check(header_beats==4 && body_bytes==length && done_count==1,"incomplete record");
        check(!stress || last_stalls>=4,"last beat stall was not exercised");
        $display("CASE: payload=%0d bytes tail_keep=%04h last_stalls=%0d",length,s_keep,last_stalls);
    endtask

    task automatic abort_stalled_header();
        done_count=0;
        offer_start();
        repeat (3) @(negedge clk);
        abort_record=1;
        repeat (4) begin
            @(negedge clk);
            check(m_valid && !m_last && !drained,"abort retracted the offered header");
        end
        m_ready=1;
        @(negedge clk);
        check(!m_valid && drained && !start_ready && done_count==0,"header abort was not a drained failure");
        abort_record=0;
        m_ready=0;
        #1;
    endtask

    task automatic abort_waiting_for_body();
        done_count=0;
        m_ready=1;
        offer_start();
        repeat (4) @(negedge clk);
        check(!m_valid && s_ready && !drained,"body was not waiting for its input");
        abort_record=1;
        @(negedge clk);
        check(!m_valid && drained && !s_ready && done_count==0,"body abort did not drain");
        abort_record=0;
        m_ready=0;
        #1;
    endtask

    initial begin
        trace_file=$fopen("records.hex","w");
        check(trace_file!=0,"cannot open byte oracle trace");
        repeat (3) @(negedge clk);
        rst_n=1;
        #1;
        // Synthetic boundary lengths and real RAW10 geometry share this leaf.
        send_record(1,1,4,1,1,1);
        send_record(2,15,4,3,1,1);
        send_record(3,16,8,2,1,1);
        send_record(4,17,8,2,1,1);
        send_record(5,65,4,13,1,1);
        send_record(6,80,16,4,1,1);
        $fclose(trace_file);

        abort_stalled_header();
        abort_waiting_for_body();
        offer_start();
        repeat (2) @(negedge clk);
        rst_n=0;
        @(negedge clk);
        check(!m_valid && !s_ready && !done && !start_ready,"common reset left an offered beat");
        rst_n=1;
        #1;
        check(drained && !m_valid,"reset did not return to idle");
        $display("CASE: stalled_header_abort=PASS body_abort=PASS common_reset=PASS");

        send_record(7,2592000,1920,1080,0,0);
        send_record(8,16777215,1920,1080,0,0);
        send_record(9,16777216,1920,1080,0,0);
        $display("RESULT: PASS raw_video_record");
        $finish;
    end

    initial begin
        #25_000_000;
        $fatal(1,"RAW record formatter timeout");
    end
endmodule
