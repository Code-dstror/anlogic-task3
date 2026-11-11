// Two-entry shared storage, independent consumer cursors. Full-rate when ready.
// No combinational path from consumer ready to source ready.
module stage3_stream_fork2 #(parameter integer WIDTH = 130) (
    input clk, rst_n, clear,
    input [1:0] destinations,
    input s_valid, output s_ready, input [WIDTH-1:0] s_payload,
    output [1:0] m_valid, input [1:0] m_ready,
    output [WIDTH-1:0] m_payload0, m_payload1
);
    reg [WIDTH-1:0] storage0, storage1;
    reg [2:0] reset_release;
    reg run;
    reg write_index, read_index0, read_index1;
    reg [1:0] count0, count1;
    wire push = s_valid && s_ready;
    wire pop0 = m_valid[0] && m_ready[0];
    wire pop1 = m_valid[1] && m_ready[1];
    assign s_ready = rst_n && reset_release[2] && run && !clear && count0 < 2 && count1 < 2;
    assign m_valid = {2{rst_n && reset_release[2] && run && !clear}} & {count1 != 0,count0 != 0};
    assign m_payload0 = read_index0 ? storage1 : storage0;
    assign m_payload1 = read_index1 ? storage1 : storage0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) reset_release <= 3'b000;
        else reset_release <= {reset_release[1:0],1'b1};
    end
    // Both cursors have capacity, so the next write slot has no owner.
    // Pre-sample only that slot; the actual push edge captures the same tuple.
    // Occupied/stalled slots retain their payload without the upstream clear
    // or VALID cone on these wide enables.
    always @(posedge clk) begin
        if (count0 < 2 && count1 < 2) begin
            if (write_index) storage1 <= s_payload;
            else storage0 <= s_payload;
        end
    end
    always @(posedge clk) begin
        run <= reset_release[2];
        if (!reset_release[2] || !run || clear) begin
            count0 <= 0; count1 <= 0; write_index <= 0;
            read_index0 <= 0; read_index1 <= 0;
        end else begin
            if (push) begin
                write_index <= ~write_index;
            end
            case ({push && destinations[0],pop0})
                2'b10: count0 <= count0+1'b1;
                2'b01: count0 <= count0-1'b1;
                default: count0 <= count0;
            endcase
            case ({push && destinations[1],pop1})
                2'b10: count1 <= count1+1'b1;
                2'b01: count1 <= count1-1'b1;
                default: count1 <= count1;
            endcase
            if (pop0 || (push && !destinations[0])) read_index0 <= ~read_index0;
            if (pop1 || (push && !destinations[1])) read_index1 <= ~read_index1;
        end
    end
endmodule
