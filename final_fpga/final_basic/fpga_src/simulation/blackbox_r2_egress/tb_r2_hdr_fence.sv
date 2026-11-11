`timescale 1ns/1ps

module tb_r2_hdr_fence;
    logic source_clk = 0, sink_clk = 0;
    logic source_rst_n = 1, sink_rst_n = 1;
    bit sink_running = 1;
    always #5 source_clk = ~source_clk;
    always #4 if (sink_running) sink_clk = ~sink_clk;

    logic i_sink_phase_owned = 0, i_owner_prepared = 0;
    logic i_fifo_sink_reset_done = 0;
    logic [575:0] i_prepared_context = 0, m_context;
    logic m_context_valid, m_context_ready = 0;
    logic o_source_reset_done, o_sink_reset_done;
    logic [146:0] s_fifo_data = 0;
    logic s_fifo_valid = 0, s_fifo_ready;
    logic [95:0] m_raw_capsule;
    logic [3:0] m_keep;
    logic m_sof, m_eol, m_last, m_valid, m_bad, m_ready = 0;
    logic [63:0] m_tag, m_status_tag;
    logic [31:0] m_index, m_status_groups;
    logic m_status_valid, m_status_ready = 0, m_status_ok;
    logic [7:0] m_status_error;
    logic o_sink_read_quiescent, o_sink_protocol_fault;

    hdr_raw14_shared_transport4 #(.MAX_WIDTH(1920), .MAX_HEIGHT(1080)) dut (
        .i_source_clk(source_clk), .i_source_rst_n(source_rst_n),
        .i_sink_clk(sink_clk), .i_sink_rst_n(sink_rst_n),
        .i_source_phase_owned(1'b0), .s_context(576'b0), .s_context_valid(1'b0),
        .s_context_ready(), .s_raw(56'b0), .s_keep(4'b0), .s_sof(1'b0),
        .s_eol(1'b0), .s_last(1'b0), .s_valid(1'b0), .s_ready(),
        .s_tag(64'b0), .s_index(32'b0), .s_status_valid(1'b0), .s_status_ready(),
        .s_status_tag(64'b0), .s_status_ok(1'b0), .s_status_error(8'b0),
        .i_source_read_quiescent(1'b1), .m_fifo_data(), .m_fifo_valid(),
        .m_fifo_ready(1'b1), .i_fifo_source_reset_done(1'b1), .o_source_protocol_fault(),
        .*
    );

    function automatic logic [55:0] lanes(input integer group_no);
        return {14'(14'h3fff - group_no), 14'(14'h2a32 + group_no),
                14'(14'h2100 ^ group_no), 14'(14'h3c16 + 11 * group_no)};
    endfunction

    function automatic logic [146:0] fence_word(input logic [63:0] tag,
                                               input integer groups, input bit ok,
                                               input logic [7:0] error_code);
        return {2'b01, 40'b0, error_code, ok, tag, 32'(groups)};
    endfunction

    task automatic wait_release;
        do @(posedge sink_clk); while ({o_source_reset_done, o_sink_reset_done} !== 2'b11);
        if (o_sink_protocol_fault !== 1'b0)
            $fatal(1, "reset did not clear HDR sink fault");
    endtask

    task automatic reset;
        @(negedge sink_clk);
        source_rst_n = 0;
        sink_rst_n = 0;
        i_fifo_sink_reset_done = 0;
        i_sink_phase_owned = 0;
        i_owner_prepared = 0;
        s_fifo_valid = 0;
        m_status_ready = 0;
        repeat (4) @(negedge sink_clk);
        source_rst_n = 1;
        sink_rst_n = 1;
        i_fifo_sink_reset_done = 1;
        wait_release();
    endtask

    task automatic begin_owner(input logic [63:0] tag);
        @(negedge sink_clk);
        i_prepared_context = '0;
        i_prepared_context[447:384] = tag;
        i_prepared_context[220:205] = 16'd8;
        i_prepared_context[236:221] = 16'd2;
        i_sink_phase_owned = 1;
        i_owner_prepared = 1;
        do @(posedge sink_clk); while (m_context_valid !== 1'b1);
        repeat (3) begin
            if (m_context_valid !== 1'b1 || m_context !== i_prepared_context ||
                {m_valid, m_status_valid, o_sink_read_quiescent} !== 3'b0)
                $fatal(1, "HDR context offer changed or exposed a dependent output");
            @(posedge sink_clk);
        end
        @(negedge sink_clk); m_context_ready = 1;
        @(posedge sink_clk);
        if (m_context_valid !== 1'b1 || m_context !== i_prepared_context)
            $fatal(1, "HDR context transfer did not match owner");
        @(negedge sink_clk); m_context_ready = 0;
    endtask

    task automatic check_data(input logic [63:0] tag, input integer group_no);
        if (m_valid !== 1'b1 || m_raw_capsule !== {40'b0, lanes(group_no)} ||
            m_tag !== tag || m_index !== 32'(group_no) ||
            {m_keep, m_sof, m_eol, m_last, m_bad} !==
            {4'hf, (group_no == 0), (group_no[0]), (group_no == 3), 1'b0})
            $fatal(1, "HDR DATA mismatch tag=%h group=%0d data=%h",
                   m_tag, group_no, m_raw_capsule);
        if ({m_context_valid, m_status_valid, o_sink_read_quiescent, o_sink_protocol_fault}
            !== 4'b0)
            $fatal(1, "HDR terminal or fault exposed during legal DATA");
        if (s_fifo_ready !== m_ready)
            $fatal(1, "DATA FIFO pop diverged from downstream acceptance");
    endtask

    task automatic send_data(input logic [63:0] tag, input integer groups);
        for (integer group_no = 0; group_no < groups; group_no++) begin
            @(negedge sink_clk);
            s_fifo_data = {2'b00, 9'b0, 1'b0, 32'(group_no), (group_no == 3),
                           group_no[0], (group_no == 0), 4'hf, 40'b0, lanes(group_no)};
            s_fifo_valid = 1;
            m_ready = 0;
            do begin
                @(posedge sink_clk);
                if (s_fifo_ready !== 1'b0)
                    $fatal(1, "HDR DATA popped while stalled");
            end while (m_valid !== 1'b1);
            repeat (group_no == 1 ? 5 : 1) begin
                check_data(tag, group_no);
                @(posedge sink_clk);
            end
            check_data(tag, group_no);
            @(negedge sink_clk); m_ready = 1;
            @(posedge sink_clk); check_data(tag, group_no);
            @(negedge sink_clk);
            s_fifo_valid = 0;
            m_ready = 0;
        end
    endtask

    task automatic check_terminal(input logic [63:0] tag, input integer groups, input bit ok,
                                  input logic [7:0] error_code);
        if ({m_status_valid, o_sink_read_quiescent, o_sink_protocol_fault} !== 3'b110 ||
            {m_status_tag, m_status_groups, m_status_ok, m_status_error} !==
            {tag, 32'(groups), ok, error_code})
            $fatal(1, "wrong HDR SOURCE tag=%h count=%0d ok=%b error=%h",
                   m_status_tag, m_status_groups, m_status_ok, m_status_error);
        if (s_fifo_ready !== m_status_ready || m_valid !== 1'b0)
            $fatal(1, "FENCE popped without SOURCE or offered DATA");
    endtask

    task automatic hold_terminal(input logic [63:0] tag, input integer groups, input bit ok,
                                  input logic [7:0] error_code);
        @(negedge sink_clk);
        s_fifo_data = fence_word(tag, groups, ok, error_code);
        s_fifo_valid = 1;
        do begin
            @(posedge sink_clk);
            if (s_fifo_ready !== 1'b0 || m_valid !== 1'b0 ||
                o_sink_protocol_fault !== 1'b0)
                $fatal(1, "exact FENCE popped, emitted DATA, or faulted before SOURCE");
        end while (m_status_valid !== 1'b1);
        repeat (7) begin
            check_terminal(tag, groups, ok, error_code);
            @(posedge sink_clk);
        end
        check_terminal(tag, groups, ok, error_code);
    endtask

    task automatic take_terminal(input logic [63:0] tag, input integer groups, input bit ok,
                                  input logic [7:0] error_code);
        @(negedge sink_clk); m_status_ready = 1;
        @(posedge sink_clk); check_terminal(tag, groups, ok, error_code);
        @(negedge sink_clk); s_fifo_valid = 0;
        repeat (4) begin
            @(posedge sink_clk);
            if (m_status_valid !== 1'b0)
                $fatal(1, "HDR SOURCE transferred more than once");
        end
        @(negedge sink_clk);
        m_status_ready = 0;
        i_sink_phase_owned = 0;
        i_owner_prepared = 0;
        repeat (4) @(posedge sink_clk);
        $display("HDR SOURCE tag=%h count=%0d ok=%b error=%h", tag, groups, ok, error_code);
    endtask

    task automatic reject_fence(input logic [63:0] tag, input integer bit_no);
        logic [146:0] damaged;
        $display("CASE invalid HDR FENCE bit=%0d", bit_no);
        begin_owner(tag);
        send_data(tag, 4);
        damaged = fence_word(tag, 4, 1, 0);
        damaged[bit_no] = ~damaged[bit_no];
        @(negedge sink_clk);
        m_status_ready = 1;
        s_fifo_valid = 1;
        s_fifo_data = damaged;
        repeat (40) begin
            @(posedge sink_clk);
            if ({s_fifo_ready, m_status_valid, m_valid, o_sink_read_quiescent} !== 4'b0)
                $fatal(1, "malformed FENCE escaped quarantine bit=%0d", bit_no);
        end
        if (o_sink_protocol_fault !== 1'b1)
            $fatal(1, "malformed FENCE failed to raise fault bit=%0d", bit_no);
        reset();
    endtask

    task automatic cancel_while_stopped(input logic [63:0] tag);
        begin_owner(tag);
        send_data(tag, 4);
        hold_terminal(tag, 4, 1, 0);
        @(negedge sink_clk);
        sink_running = 0;
        #2 sink_rst_n = 0;
        #2;
        if ({o_sink_reset_done, m_status_valid, s_fifo_ready} !== 3'b0)
            $fatal(1, "stopped PIX reset did not cancel the held FENCE");
        s_fifo_valid = 0;
        i_sink_phase_owned = 0;
        i_owner_prepared = 0;
        i_fifo_sink_reset_done = 0;
        repeat (3) @(negedge source_clk);
        sink_rst_n = 1;
        i_fifo_sink_reset_done = 1;
        repeat (3) @(negedge source_clk);
        if ({o_sink_reset_done, m_status_valid} !== 2'b0)
            $fatal(1, "stopped PIX released reset or replayed a terminal");
        sink_running = 1;
        wait_release();
        repeat (4) begin
            @(posedge sink_clk);
            if ({m_context_valid, m_valid, m_status_valid} !== 3'b0)
                $fatal(1, "cancelled owner replayed after restart");
        end
        $display("HDR stopped PIX reset cancelled unaccepted SOURCE");
    endtask

    initial begin
        reset();
        begin_owner(64'hb953_00dd_1190_3721);
        send_data(64'hb953_00dd_1190_3721, 4);
        hold_terminal(64'hb953_00dd_1190_3721, 4, 1, 0);
        take_terminal(64'hb953_00dd_1190_3721, 4, 1, 0);

        // An exact terminal for an aborted owner carries the accepted count.
        begin_owner(64'h8c94_a4ff_1403_7841);
        send_data(64'h8c94_a4ff_1403_7841, 3);
        hold_terminal(64'h8c94_a4ff_1403_7841, 3, 0, 8'h55);
        take_terminal(64'h8c94_a4ff_1403_7841, 3, 0, 8'h55);

        reject_fence(64'hb82f_00de_0090_1122, 71);  // native tag
        reject_fence(64'h7ad0_008b_1951_0023, 0);   // group count
        reject_fence(64'h813d_9cb4_5692_1023, 105); // reserved field

        cancel_while_stopped(64'h1bb4_1c4b_9972_2356);
        begin_owner(64'h148c_a4cd_1b03_7542);
        send_data(64'h148c_a4cd_1b03_7542, 4);
        hold_terminal(64'h148c_a4cd_1b03_7542, 4, 1, 0);
        take_terminal(64'h148c_a4cd_1b03_7542, 4, 1, 0);
        $display("R2_HDR_FENCE PASS");
        $finish;
    end

    initial #80000 $fatal(1, "HDR fence suite simulation watchdog");
endmodule
