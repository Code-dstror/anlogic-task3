    // Testbench signals named after the public sink ports shared by both DUTs.
    logic o_start_valid;
    logic i_start_ready = 0;
    logic [31:0] o_capture_id, o_session_id, o_mode_epoch, o_write_tag;
    logic [15:0] o_width, o_height;
    logic [63:0] o_timestamp_ns;
    logic o_camera_id, o_start_mask;
    logic [7:0] o_quality, o_format;
    logic [2:0] o_start_source_type;
    logic [127:0] o_jpeg_tdata;
    logic [15:0] o_jpeg_tkeep;
    logic o_jpeg_tlast, o_jpeg_tvalid;
    logic i_jpeg_tready = 0;
    logic o_result_valid, o_result_ok;
    logic i_result_ready = 0;
    logic [31:0] o_result_id, o_result_epoch;
    logic [24:0] o_result_length;
    logic [7:0] o_result_error, o_result_quality;
    logic [16383:0] o_record_extension;
    logic o_record_extension_valid;
    logic i_record_extension_ready = 0;
    logic o_extension_shape_valid;
    logic i_extension_read_enable = 0;
    logic [8:0] i_extension_read_index = 0;
    logic [39:0] o_extension_read_data;
    logic o_protocol_fault;

    task automatic check_start(input frame_t frame);
        if (o_start_valid !== 1'b1 ||
            {o_capture_id, o_session_id, o_mode_epoch, o_write_tag, o_timestamp_ns,
             o_width, o_height, o_camera_id, o_quality} !== frame ||
            {o_start_mask, o_start_source_type, o_format} !== {1'b0, 3'b0, 8'd1})
            $fatal(1, "START lost or wrong capture=%h expected=%h", o_capture_id,
                   frame.capture_id);
        if ({o_jpeg_tvalid, o_record_extension_valid, o_result_valid} !== 3'b0)
            $fatal(1, "dependent offer before START transfer");
    endtask

    task automatic hold_start(input frame_t frame, input integer cycles);
        do @(posedge sink_clk); while (o_start_valid !== 1'b1);
        repeat (cycles) begin
            check_start(frame);
            @(posedge sink_clk);
        end
        check_start(frame);
    endtask

    task automatic take_start(input frame_t frame);
        @(negedge sink_clk); i_start_ready = 1;
        @(posedge sink_clk); check_start(frame);
        @(negedge sink_clk); i_start_ready = 0;
    endtask

    task automatic check_jpeg(input frame_t frame, input integer beat, input bit last);
        if (o_jpeg_tvalid !== 1'b1 ||
            {o_jpeg_tlast, o_jpeg_tkeep, o_jpeg_tdata} !==
            {last, jpeg_keep(last), jpeg_bytes(frame, beat, last)})
            $fatal(1, "JPEG lost or wrong capture=%h beat=%0d keep=%h last=%b data=%h",
                   frame.capture_id, beat, o_jpeg_tkeep, o_jpeg_tlast, o_jpeg_tdata);
        if ({o_start_valid, o_record_extension_valid, o_result_valid} !== 3'b0)
            $fatal(1, "unexpected concurrent offer during JPEG");
    endtask

    task automatic take_jpeg(input frame_t frame, input integer beats, input bit ends,
                             input integer first_stall, input integer tail_stall,
                             input bit require_full_rate);
        integer gaps, streak, longest, current_stall;
        bit last;
        streak = 0;
        longest = 0;
        @(negedge sink_clk);
        for (integer beat = 0; beat < beats; beat++) begin
            last = ends && beat == beats - 1;
            current_stall = beat == 0 ? first_stall : (last ? tail_stall : 0);
            if (current_stall != 0) begin
                i_jpeg_tready = 0;
                do @(posedge sink_clk); while (o_jpeg_tvalid !== 1'b1);
                repeat (current_stall) begin
                    check_jpeg(frame, beat, last);
                    @(posedge sink_clk);
                end
                check_jpeg(frame, beat, last);
                @(negedge sink_clk);
                streak = 0;
            end
            i_jpeg_tready = 1;
            gaps = 0;
            do begin
                @(posedge sink_clk);
                if (o_jpeg_tvalid !== 1'b1)
                    gaps++;
                if (gaps != 0 && ((require_full_rate && beat != 0) || current_stall != 0))
                    $fatal(1, "JPEG bubble after offered beat or within continuous stream, beat=%0d",
                           beat);
            end while (o_jpeg_tvalid !== 1'b1);
            check_jpeg(frame, beat, last);
            streak = gaps == 0 ? streak + 1 : 1;
            if (streak > longest)
                longest = streak;
            @(negedge sink_clk);
        end
        i_jpeg_tready = 0;
        $display("JPEG capture=%h beats=%0d bytes=%0d longest_ready_streak=%0d",
                 frame.capture_id, beats, jpeg_length(beats, ends), longest);
    endtask

    task automatic check_extension;
        if (o_record_extension_valid !== 1'b1 || o_extension_shape_valid !== 1'b1 ||
            o_record_extension !== '0)
            $fatal(1, "extension offer lost, invalid shape, or nonzero parallel port");
        if ({o_start_valid, o_jpeg_tvalid, o_result_valid} !== 3'b0)
            $fatal(1, "unexpected offer before extension transfer");
    endtask

    task automatic hold_extension(input integer cycles);
        do @(posedge sink_clk); while (o_record_extension_valid !== 1'b1);
        repeat (cycles) begin
            check_extension();
            @(posedge sink_clk);
        end
        check_extension();
    endtask

    task automatic read_words(input extension_t expected, input integer first,
                              input integer last, input bit check_offer);
        logic [16423:0] padded;
        padded = {40'b0, expected};
        for (integer index = first; index <= last; index++) begin
            @(negedge sink_clk);
            i_extension_read_enable = 1;
            i_extension_read_index = 9'(index);
            @(posedge sink_clk);
            if (o_extension_shape_valid !== 1'b1)
                $fatal(1, "extension lease ended before read index=%0d", index);
            if (check_offer)
                check_extension();
            @(negedge sink_clk); i_extension_read_enable = 0;
            @(posedge sink_clk);
            if (o_extension_read_data !== padded[40*index +: 40])
                $fatal(1, "extension RAM index=%0d actual=%h expected=%h",
                       index, o_extension_read_data, padded[40*index +: 40]);
        end
    endtask

    task automatic take_extension;
        @(negedge sink_clk); i_record_extension_ready = 1;
        @(posedge sink_clk); check_extension();
        @(negedge sink_clk); i_record_extension_ready = 0;
    endtask

    function automatic logic [105:0] result_fields();
        return {o_result_ok, o_result_id, o_result_epoch, o_result_length,
                o_result_error, o_result_quality};
    endfunction

    task automatic hold_result(input frame_t frame, input logic [24:0] length,
                               input bit ok, input logic [7:0] error_code,
                               input integer cycles, input bit exact_identity);
        logic [105:0] held_result;
        do @(posedge sink_clk); while (o_result_valid !== 1'b1);
        held_result = result_fields();
        if ({o_result_ok, o_result_error} !== {ok, error_code} ||
            (exact_identity &&
             {o_result_id, o_result_epoch, o_result_length, o_result_quality} !==
             {frame.capture_id, frame.epoch, length, frame.quality}))
            $fatal(1, "wrong RESULT capture=%h length=%0d ok=%b error=%h",
                   o_result_id, o_result_length, o_result_ok, o_result_error);
        repeat (cycles) begin
            if ({o_result_valid, result_fields()} !== {1'b1, held_result})
                $fatal(1, "RESULT changed while stalled");
            if ({o_start_valid, o_jpeg_tvalid, o_record_extension_valid} !== 3'b0)
                $fatal(1, "unexpected offer before RESULT transfer");
            @(posedge sink_clk);
        end
        if ({o_result_valid, result_fields()} !== {1'b1, held_result})
            $fatal(1, "RESULT withdrawn during stall");
    endtask

    task automatic take_result;
        logic [105:0] held_result;
        held_result = result_fields();
        @(negedge sink_clk); i_result_ready = 1;
        @(posedge sink_clk);
        if ({o_result_valid, result_fields()} !== {1'b1, held_result})
            $fatal(1, "RESULT lost or changed on transfer");
        @(negedge sink_clk); i_result_ready = 0;
    endtask

    task automatic check_quiet(input integer cycles);
        repeat (cycles) begin
            @(posedge sink_clk);
            if ({o_start_valid, o_jpeg_tvalid, o_record_extension_valid, o_result_valid} !== 4'b0)
                $fatal(1, "unexpected START/JPEG/extension/RESULT on idle or quarantined interface");
        end
    endtask
