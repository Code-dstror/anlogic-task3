// Private arithmetic: parent frame identity is stable until every pipeline token drains.
// Only per-token geometry/scale travels through the three CE stages.
// F22 arithmetic only: four Y8 windows, exact signed Sobel and optional Gaussian.
// Three register stages share CE; history and vendor RAM belong to the caller.
// Synchronous clear/cancel flushes only the original valid/control pipeline.
// It must not reach the MAC asynchronous RST: parent fault may pulse between
// clock edges while a source advances a legally accepted beat. Invalid DSP
// data drains before the first subsequent valid output; global rst_n alone
// resets DSP storage asynchronously.
module full_filter_sobel4 #(
    parameter integer FILTER_ENABLE = 1
) (
    input wire clk,
    input wire rst_n,
    input wire cancel,
    input wire s_valid,
    output wire s_ready,
    input wire [287:0] s_window,
    input wire [31:0] s_filtered_y,
    input wire [3:0] s_keep,
    input wire [1:0] s_scale,
    input wire [12:0] s_width,
    input wire [12:0] s_height,
    input wire [12:0] s_x,
    input wire [12:0] s_y,
    input wire s_sof,
    input wire s_eol,
    input wire s_eof,
    input wire [159:0] i_frame_context,
    output wire m_valid,
    input wire m_ready,
    output wire [43:0] m_gx,
    output wire [43:0] m_gy,
    output wire [43:0] m_magnitude,
    output wire [31:0] m_filtered_y,
    output wire [31:0] m_center_y,
    output wire [3:0] m_keep,
    output wire [1:0] m_scale,
    output wire [12:0] m_width,
    output wire [12:0] m_height,
    output wire [12:0] m_x,
    output wire [12:0] m_y,
    output wire m_sof,
    output wire m_eol,
    output wire m_eof,
    output wire [159:0] m_context
);
    reg valid1, valid2, valid3;
    reg [60:0] metadata1, metadata2, metadata3;
    wire run = rst_n && !cancel;
    wire advance = !valid3 || m_ready;
    assign s_ready = run && advance;
    assign m_valid = run && valid3;
    assign m_context=i_frame_context;
    assign {m_scale, m_width, m_height, m_x, m_y,
            m_keep, m_sof, m_eol, m_eof} = metadata3;

    always @(posedge clk) begin
        if (!rst_n || cancel) begin
            valid1 <= 1'b0;
            valid2 <= 1'b0;
            valid3 <= 1'b0;
        end else if (advance) begin
            valid1 <= s_valid;
            valid2 <= valid1;
            valid3 <= valid2;
            if (s_valid)
                metadata1 <= {s_scale, s_width, s_height, s_x, s_y,
                              s_keep, s_sof, s_eol, s_eof};
            if (valid1) metadata2 <= metadata1;
            if (valid2) metadata3 <= metadata2;
        end
    end

    genvar lane;
    generate for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
        wire [7:0] p00 = s_window[lane*72 +: 8];
        wire [7:0] p01 = s_window[lane*72+8 +: 8];
        wire [7:0] p02 = s_window[lane*72+16 +: 8];
        wire [7:0] p10 = s_window[lane*72+24 +: 8];
        wire [7:0] p11 = s_window[lane*72+32 +: 8];
        wire [7:0] p12 = s_window[lane*72+40 +: 8];
        wire [7:0] p20 = s_window[lane*72+48 +: 8];
        wire [7:0] p21 = s_window[lane*72+56 +: 8];
        wire [7:0] p22 = s_window[lane*72+64 +: 8];
        // The ridge extractor uses the Sobel input center, never the extra
        // Gaussian output. These narrow registers share the exact token CE.
        reg [7:0] center1,center2,center3;
        always @(posedge clk) if(run && advance) begin
            if(s_valid) center1 <= s_keep[lane] ? p11 : 8'd0;
            if(valid1) center2 <= center1;
            if(valid2) center3 <= center2;
        end
        assign m_center_y[lane*8+:8]=center3;
        // Shared diagonal differences use signed9 (-255..255).
        // Both corner combinations fit signed10 (-510..510).
        wire signed [8:0] diagonal_a = $signed({1'b0,p22}) - $signed({1'b0,p00});
        wire signed [8:0] diagonal_b = $signed({1'b0,p20}) - $signed({1'b0,p02});
        wire signed [8:0] middle_x = s_keep[lane] ?
            $signed({1'b0,p12}) - $signed({1'b0,p10}) : 9'sd0;
        wire signed [8:0] middle_y = s_keep[lane] ?
            $signed({1'b0,p21}) - $signed({1'b0,p01}) : 9'sd0;
        reg signed [9:0] corner_x1, corner_y1;
        wire [33:0] gx2, gy2;
        reg [10:0] gx3, gy3, magnitude3;
        wire [10:0] abs_x2 = gx2[10] ? (~gx2[10:0] + 11'd1) : gx2[10:0];
        wire [10:0] abs_y2 = gy2[10] ? (~gy2[10:0] + 11'd1) : gy2[10:0];
        // MREG captures 2*middle at stage1; PREG adds corner at stage2.
        // Exact signed11 results are -1020..1020. Global CE freezes both.
        fdct_mac19s14s_z33s_p34_m1p1 u_gx (
            .CLK(clk),.CE(advance),.RST(!rst_n),
            .A({{10{middle_x[8]}},middle_x}),.Y(14'd2),
            .Z({{23{corner_x1[9]}},corner_x1}),.P(gx2));
        fdct_mac19s14s_z33s_p34_m1p1 u_gy (
            .CLK(clk),.CE(advance),.RST(!rst_n),
            .A({{10{middle_y[8]}},middle_y}),.Y(14'd2),
            .Z({{23{corner_y1[9]}},corner_y1}),.P(gy2));
        assign m_gx[lane*11 +:11] = gx3;
        assign m_gy[lane*11 +:11] = gy3;
        assign m_magnitude[lane*11 +:11] = magnitude3;
        always @(posedge clk) if (run && advance) begin
            corner_x1 <= s_keep[lane] ?
                $signed({diagonal_a[8],diagonal_a}) - $signed({diagonal_b[8],diagonal_b}) : 10'sd0;
            corner_y1 <= s_keep[lane] ?
                $signed({diagonal_a[8],diagonal_a}) + $signed({diagonal_b[8],diagonal_b}) : 10'sd0;
            if (valid2) begin
                gx3 <= gx2[10:0];
                gy3 <= gy2[10:0];
                magnitude3 <= {1'b0,abs_x2[9:0]} + {1'b0,abs_y2[9:0]};
            end
        end
        if (FILTER_ENABLE) begin : g_filter
            reg [9:0] corners1,edges1;
            wire [10:0] rounded_corners = {1'b0,corners1}+11'd8;
            wire [33:0] center_corners, gaussian;
            // Separating the four corners, four edges and center is exact:
            // (corners + 2*edges + 4*center + 8)>>4, at most4088.
            always @(posedge clk) if (run && advance) begin
                corners1 <= s_keep[lane] ?
                    {2'd0,p00}+{2'd0,p02}+{2'd0,p20}+{2'd0,p22} : 10'd0;
                edges1 <= s_keep[lane] ?
                    {2'd0,p01}+{2'd0,p10}+{2'd0,p12}+{2'd0,p21} : 10'd0;
            end
            fdct_mac19s14s_z33s_p34_m1p1 u_center (
                .CLK(clk),.CE(advance),.RST(!rst_n),
                .A({11'd0,(s_keep[lane] ? p11 : 8'd0)}),.Y(14'd4),
                .Z({22'd0,rounded_corners}),.P(center_corners));
            // MREG at stage2, PREG at stage3; no extra register/latency.
            fdct_mac19s14s_z33s_p34_m1p1 u_edges (
                .CLK(clk),.CE(advance),.RST(!rst_n),
                .A({9'd0,edges1}),.Y(14'd2),
                .Z(center_corners[32:0]),.P(gaussian));
            assign m_filtered_y[lane*8 +:8] = gaussian[11:4];
        end else begin : g_filter_bypass
            reg [7:0] filtered1,filtered2,filtered3;
            always @(posedge clk) if (run && advance) begin
                if (s_valid) filtered1 <= s_keep[lane] ? s_filtered_y[lane*8 +:8] : 8'd0;
                if (valid1) filtered2 <= filtered1;
                if (valid2) filtered3 <= filtered2;
            end
            assign m_filtered_y[lane*8 +:8] = filtered3;
        end
    end endgenerate
endmodule
