`timescale 1ns / 1ps

module tb_axis_frame_fifo_ip;

    reg source_clk;
    reg sink_clk;
    reg source_rst_n;
    reg sink_rst_n;
    wire [146:0] source_data;
    wire source_valid;
    wire source_ready;
    wire [146:0] sink_data;
    wire sink_valid;
    reg sink_ready;

    integer write_index;
    integer read_index;
    integer error_count;
    integer timeout_count;
    reg [15:0] ready_lfsr;

    assign source_valid = source_rst_n && (write_index < 128);
    assign source_data = {115'b0, write_index[31:0]};

    axis_frame_fifo_ip u_dut (
        .i_source_clk(source_clk),
        .i_source_rst_n(source_rst_n),
        .i_source_data(source_data),
        .i_source_valid(source_valid),
        .o_source_ready(source_ready),
        .i_sink_clk(sink_clk),
        .i_sink_rst_n(sink_rst_n),
        .o_sink_data(sink_data),
        .o_sink_valid(sink_valid),
        .i_sink_ready(sink_ready)
    );

    initial begin
        source_clk = 1'b0;
        forever #5 source_clk = !source_clk;
    end

    initial begin
        sink_clk = 1'b0;
        forever #7 sink_clk = !sink_clk;
    end

    always @(posedge source_clk) begin
        if (!source_rst_n) begin
            write_index <= 0;
        end else if (source_valid && source_ready)
            write_index <= write_index + 1;
    end

    always @(posedge sink_clk) begin
        if (!sink_rst_n) begin
            sink_ready <= 1'b0;
            ready_lfsr <= 16'h1ACE;
            read_index <= 0;
            error_count <= 0;
        end else begin
            ready_lfsr <= {ready_lfsr[14:0],
                           ready_lfsr[15] ^ ready_lfsr[13] ^
                           ready_lfsr[12] ^ ready_lfsr[10]};
            sink_ready <= ready_lfsr[0] | ready_lfsr[3];
            if (sink_valid && sink_ready) begin
                if (sink_data[31:0] !== read_index[31:0] ||
                    sink_data[146:32] !== 115'b0) begin
                    $display("FIFO DATA ERROR index=%0d data=%h", read_index,
                             sink_data);
                    error_count <= error_count + 1;
                end
                read_index <= read_index + 1;
            end
        end
    end

    initial begin
        source_rst_n = 1'b0;
        sink_rst_n = 1'b0;
        timeout_count = 0;
        #100;
        source_rst_n = 1'b1;
        sink_rst_n = 1'b1;

        while (read_index < 128 && timeout_count < 20000) begin
            @(posedge sink_clk);
            timeout_count = timeout_count + 1;
        end

        if (read_index == 128 && error_count == 0) begin
            $display("[TB] RESULT: PASS");
            $finish;
        end

        $display("[TB] RESULT: FAIL read=%0d errors=%0d",
                 read_index, error_count);
        $fatal(1);
    end

endmodule
