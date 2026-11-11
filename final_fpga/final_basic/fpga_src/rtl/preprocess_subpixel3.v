// Sparse F25 Q8 refinement. Arithmetic division is the unchanged official IP.
module preprocess_subpixel3 (
    input wire clk,rst_n,cancel,debug_clear,
    input wire s_valid,
    output wire s_ready,
    input wire [10:0] s_left,s_center,s_right,
    input wire [12:0] s_peak_x,s_y,s_native_width,
    input wire [2:0] s_spacing,
    input wire [1:0] s_neighbors,
    input wire [12:0] s_min_curvature,
    input wire [159:0] s_context,
    input wire [31:0] s_tag,
    output wire m_valid,
    input wire m_ready,
    output reg m_ok,
    output reg [7:0] m_error_code,
    output reg signed [21:0] m_x_q8,
    output reg signed [11:0] m_delta_q8,
    output reg [12:0] m_y,
    output reg [2:0] m_spacing,
    output reg signed [13:0] m_curvature,
    output reg [159:0] m_context,
    output reg [31:0] m_tag,
    output reg [31:0] requests_accepted,results_completed,requests_rejected,
    output reg first_fault_valid,
    output reg [7:0] first_fault_code,
    output reg [159:0] first_fault_context,
    output reg [31:0] first_fault_tag
);
    localparam [1:0] ST_IDLE=0,ST_SEND=1,ST_WAIT=2,ST_HOLD=3;
    reg [1:0] state;
    reg [5:0] reset_hold,drain_hold;
    reg dividend_pending,divisor_pending;
    reg signed [18:0] numerator;
    reg signed [13:0] denominator;
    reg signed [21:0] peak_q8;
    wire run=rst_n&&!cancel;
    // The official model retains a pipelined result after a short, output-
    // stalled reset. Qualification proves32 reset-low clocks plus32 released
    // drain clocks with ready asserted flush this fixed one-request package.
    // No operand/admission or old metadata is live throughout that quarantine.
    wire divider_reset_n=run&&reset_hold==0;
    wire dividend_ready,divisor_ready,quotient_valid;
    wire [39:0] quotient_data;
    wire signed [23:0] quotient=$signed(quotient_data[39:16]);
    wire quotient_bad=quotient < -24'sd128 || quotient > 24'sd128;
    wire signed [11:0] quotient_narrow=$signed(quotient[11:0]);
    wire signed [11:0] native_delta=m_spacing==4 ? quotient_narrow<<<2 :
        m_spacing==2 ? quotient_narrow<<<1 : quotient_narrow;
    wire signed [21:0] native_delta_extended={{10{native_delta[11]}},native_delta};
    wire divider_output_ready=run&&(drain_hold!=0||state==ST_WAIT);
    assign s_ready=divider_reset_n&&drain_hold==0&&state==ST_IDLE&&dividend_ready&&divisor_ready;
    assign m_valid=run&&state==ST_HOLD;
    wire take_request=s_valid&&s_ready;
    wire take_result=m_valid&&m_ready;
    wire take_quotient=quotient_valid&&divider_output_ready&&state==ST_WAIT;

    wire signed [13:0] left_extended=$signed({3'b0,s_left});
    wire signed [13:0] center_extended=$signed({3'b0,s_center});
    wire signed [13:0] right_extended=$signed({3'b0,s_right});
    wire signed [13:0] input_curvature=(center_extended<<<1)-left_extended-right_extended;
    wire signed [18:0] input_difference=$signed({8'b0,s_right})-$signed({8'b0,s_left});
    wire signed [18:0] input_numerator=input_difference<<<7;
    wire signed [21:0] input_peak_q8=$signed({1'b0,s_peak_x,8'b0});
    wire [13:0] right_neighbor={1'b0,s_peak_x}+{11'b0,s_spacing};
    reg [7:0] reject_code;
    always @* begin
        reject_code=0;
        if(s_left>2040||s_center>2040||s_right>2040) reject_code=1;
        else if(s_native_width==0||s_peak_x>=s_native_width||
            (s_spacing!=1&&s_spacing!=2&&s_spacing!=4)||
            s_min_curvature==0||s_min_curvature>4080) reject_code=2;
        else if(s_neighbors!=3||s_peak_x<s_spacing||right_neighbor>={1'b0,s_native_width}) reject_code=3;
        else if(s_center<s_left||s_center<s_right||
            (s_center==s_left&&s_center==s_right)) reject_code=4;
        else if(input_curvature<$signed({1'b0,s_min_curvature})) reject_code=5;
    end
    wire reject_request=take_request&&reject_code!=0;
    wire reject_quotient=take_quotient&&quotient_bad;

    // Only sign extension and AXIS adaptation surround the official configured
    // wrapper. No parameter override or replacement arithmetic core is used.
    div_19s14s_q8 divider (
        .aclk(clk),.aresetn(divider_reset_n),
        .s_axis_dividend_tdata({{5{numerator[18]}},numerator}),
        .s_axis_dividend_tvalid(divider_reset_n&&state==ST_SEND&&dividend_pending),
        .s_axis_dividend_tready(dividend_ready),
        .s_axis_divisor_tdata({{2{denominator[13]}},denominator}),
        .s_axis_divisor_tvalid(divider_reset_n&&state==ST_SEND&&divisor_pending),
        .s_axis_divisor_tready(divisor_ready),
        .m_axis_dout_tdata(quotient_data),.m_axis_dout_tvalid(quotient_valid),
        .m_axis_dout_tready(divider_output_ready));

    always @(posedge clk) begin
        if(!rst_n||cancel) begin
            state<=ST_IDLE;reset_hold<=32;drain_hold<=32;dividend_pending<=0;divisor_pending<=0;
            numerator<=0;denominator<=0;peak_q8<=0;
            m_ok<=0;m_error_code<=0;m_x_q8<=0;m_delta_q8<=0;m_y<=0;
            m_spacing<=0;m_curvature<=0;m_context<=0;m_tag<=0;
        end else begin
            if(reset_hold!=0) reset_hold<=reset_hold-1'b1;
            else if(drain_hold!=0) drain_hold<=drain_hold-1'b1;
            case(state)
                ST_IDLE: if(take_request) begin
                    peak_q8<=input_peak_q8;m_x_q8<=input_peak_q8;m_delta_q8<=0;
                    m_y<=s_y;m_spacing<=s_spacing;m_context<=s_context;m_tag<=s_tag;
                    m_curvature<=reject_code==1 ? 14'sd0 : input_curvature;
                    m_ok<=reject_code==0;m_error_code<=reject_code;
                    if(reject_code!=0) state<=ST_HOLD;
                    else begin
                        numerator<=input_numerator;denominator<=input_curvature;
                        dividend_pending<=1;divisor_pending<=1;state<=ST_SEND;
                    end
                end
                ST_SEND: begin
                    if(dividend_pending&&dividend_ready) dividend_pending<=0;
                    if(divisor_pending&&divisor_ready) divisor_pending<=0;
                    if((!dividend_pending||dividend_ready)&&(!divisor_pending||divisor_ready)) state<=ST_WAIT;
                end
                ST_WAIT: if(take_quotient) begin
                    if(quotient_bad) begin
                        m_ok<=0;m_error_code<=6;m_delta_q8<=0;m_x_q8<=peak_q8;
                    end else begin
                        m_delta_q8<=native_delta;m_x_q8<=peak_q8+native_delta_extended;
                    end
                    state<=ST_HOLD;
                end
                ST_HOLD: if(take_result) state<=ST_IDLE;
                default: state<=ST_IDLE;
            endcase
        end
    end

    // This independent diagnostic state has no fan-in to any functional signal.
    always @(posedge clk) begin
        if(!rst_n||cancel||debug_clear) begin
            requests_accepted<=0;results_completed<=0;requests_rejected<=0;
            first_fault_valid<=0;first_fault_code<=0;first_fault_context<=0;first_fault_tag<=0;
        end else begin
            if(take_request) requests_accepted<=requests_accepted+1'b1;
            if(take_result) results_completed<=results_completed+1'b1;
            if(reject_request||reject_quotient) begin
                requests_rejected<=requests_rejected+1'b1;
                if(!first_fault_valid) begin
                    first_fault_valid<=1;
                    first_fault_code<=reject_request ? reject_code : 8'd6;
                    first_fault_context<=reject_request ? s_context : m_context;
                    first_fault_tag<=reject_request ? s_tag : m_tag;
                end
            end
        end
    end
endmodule
