// Two already-registered Y-window producers share one II=1 arithmetic input.
// Metadata219 = {context160,width13,height13,x13,y13,keep4,sof,eol,eof}.
module preprocess_scale_arbiter4 (
    input wire clk,
    input wire rst_n,
    input wire cancel,
    input wire s_half_valid,
    output wire s_half_ready,
    input wire [287:0] s_half_window,
    input wire [218:0] s_half_metadata,
    input wire s_quarter_valid,
    output wire s_quarter_ready,
    input wire [287:0] s_quarter_window,
    input wire [218:0] s_quarter_metadata,
    output wire m_valid,
    input wire m_ready,
    output wire [287:0] m_window,
    output wire [220:0] m_metadata
);
    reg prefer_quarter;
    // Lock the selected producer while the shared input is stalled. A producer
    // arriving on the other port must not replace an already presented beat.
    reg grant_locked;
    reg locked_quarter;
    wire run = rst_n && !cancel;
    wire select_quarter = grant_locked ? locked_quarter :
        (s_quarter_valid && (!s_half_valid || prefer_quarter));
    assign m_valid = run && (select_quarter ? s_quarter_valid : s_half_valid);
    assign m_window = select_quarter ? s_quarter_window : s_half_window;
    wire [218:0] selected_metadata = select_quarter ?
        s_quarter_metadata : s_half_metadata;
    assign m_metadata = {selected_metadata[218:59],
                         select_quarter ? 2'd2 : 2'd1, selected_metadata[58:0]};
    assign s_half_ready = run && m_ready && !select_quarter;
    assign s_quarter_ready = run && m_ready && select_quarter;

    always @(posedge clk) begin
        if (!rst_n || cancel) begin
            prefer_quarter <= 1'b0;
            grant_locked <= 1'b0;
            locked_quarter <= 1'b0;
        end else if (m_valid) begin
            if (m_ready) begin
                prefer_quarter <= !select_quarter;
                grant_locked <= 1'b0;
            end else if (!grant_locked) begin
                grant_locked <= 1'b1;
                locked_quarter <= select_quarter;
            end
        end
    end
endmodule
