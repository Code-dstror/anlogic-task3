// Exact unsigned division for the single-outstanding HE background owner.
// Sixteen pairs of radix-2 steps include acceptance: result latency is 15 edges.
// Requests must have both valid bits and nonzero divisor while idle.
module stage3_he_div_32u24u_iter16 (
    input wire aclk, aresetn,
    input wire [31:0] s_axis_dividend_tdata,
    input wire s_axis_dividend_tvalid,
    input wire [23:0] s_axis_divisor_tdata,
    input wire s_axis_divisor_tvalid,
    output wire [55:0] m_axis_dout_tdata,
    output reg m_axis_dout_tvalid
);
    reg busy;
    reg [3:0] steps_left;
    reg [31:0] shift_quotient;
    reg [23:0] remainder, divisor;
    wire request = s_axis_dividend_tvalid && s_axis_divisor_tvalid;
    wire accept = !busy && request && s_axis_divisor_tdata != 0;
    wire [31:0] shifted_input = busy ? shift_quotient : s_axis_dividend_tdata;
    wire [23:0] current_divisor = busy ? divisor : s_axis_divisor_tdata;
    // Each restoring substep preserves 0 <= remainder < divisor.
    // The two selected quotient bits are exactly one original radix-4 digit.
    // A borrow needs one extra bit beyond the 25-bit trial, including D=max.
    wire [24:0] first_trial = {busy ? remainder : 24'd0, shifted_input[31]};
    wire [25:0] first_subtract = {1'b0,first_trial} - {2'b0,current_divisor};
    wire first_digit = !first_subtract[25];
    wire [23:0] first_remainder = first_digit ? first_subtract[23:0] : first_trial[23:0];
    wire [24:0] second_trial = {first_remainder,shifted_input[30]};
    wire [25:0] second_subtract = {1'b0,second_trial} - {2'b0,current_divisor};
    wire second_digit = !second_subtract[25];
    wire [1:0] digit = {first_digit,second_digit};
    wire [23:0] next_remainder = second_digit ? second_subtract[23:0] : second_trial[23:0];
    assign m_axis_dout_tdata = {shift_quotient,remainder};
    always @(posedge aclk) begin
        if (!aresetn) begin
            busy<=0; steps_left<=0; m_axis_dout_tvalid<=0;
            shift_quotient<=0; remainder<=0; divisor<=0;
        end else begin
            m_axis_dout_tvalid<=0;
            if (accept || busy) begin
                shift_quotient<={shifted_input[29:0],digit};
                remainder<=next_remainder;
                if (accept) begin
                    divisor<=s_axis_divisor_tdata; busy<=1; steps_left<=14;
                end else if (steps_left==0) begin
                    busy<=0; m_axis_dout_tvalid<=1;
                end else steps_left<=steps_left-1'b1;
            end
        end
    end
endmodule
