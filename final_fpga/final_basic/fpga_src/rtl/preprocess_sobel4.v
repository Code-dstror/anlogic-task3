// F22 arithmetic only: four Y8 windows, exact signed Sobel and optional Gaussian.
// Three register stages share CE; history and vendor RAM belong to the caller.
module preprocess_sobel4 #(
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
    input wire [159:0] s_context,
    output wire m_valid,
    input wire m_ready,
    output wire [43:0] m_gx,
    output wire [43:0] m_gy,
    output wire [43:0] m_magnitude,
    output wire [31:0] m_filtered_y,
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
    reg [220:0] metadata1, metadata2, metadata3;
    wire run = rst_n && !cancel;
    wire advance = !valid3 || m_ready;
    assign s_ready = run && advance;
    assign m_valid = run && valid3;
    assign {m_context, m_scale, m_width, m_height, m_x, m_y,
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
                metadata1 <= {s_context, s_scale, s_width, s_height, s_x, s_y,
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
        reg [9:0] x_positive1, x_negative1, y_positive1, y_negative1;
        reg [11:0] filter_sum1;
        reg [7:0] filtered1, filtered2, filtered3;
        reg [10:0] gx2, gy2, gx3, gy3, magnitude3;
        wire [10:0] abs_x2 = gx2[10] ? (~gx2 + 11'd1) : gx2;
        wire [10:0] abs_y2 = gy2[10] ? (~gy2 + 11'd1) : gy2;
        wire [11:0] rounded_filter = filter_sum1 + 12'd8;
        assign m_gx[lane*11 +: 11] = gx3;
        assign m_gy[lane*11 +: 11] = gy3;
        assign m_magnitude[lane*11 +: 11] = magnitude3;
        assign m_filtered_y[lane*8 +: 8] = filtered3;

        always @(posedge clk) begin
            if (run && advance) begin
                if (s_valid) begin
                    if (s_keep[lane]) begin
                        // 1+2+1 weighted column/row terms each fit ten unsigned bits.
                        x_positive1 <= {2'b0,p02} + {1'b0,p12,1'b0} + {2'b0,p22};
                        x_negative1 <= {2'b0,p00} + {1'b0,p10,1'b0} + {2'b0,p20};
                        y_positive1 <= {2'b0,p20} + {1'b0,p21,1'b0} + {2'b0,p22};
                        y_negative1 <= {2'b0,p00} + {1'b0,p01,1'b0} + {2'b0,p02};
                        if (FILTER_ENABLE) begin
                            filter_sum1 <= {4'b0,p00} + {3'b0,p01,1'b0} + {4'b0,p02} +
                                {3'b0,p10,1'b0} + {2'b0,p11,2'b0} + {3'b0,p12,1'b0} +
                                {4'b0,p20} + {3'b0,p21,1'b0} + {4'b0,p22};
                        end else begin
                            filtered1 <= s_filtered_y[lane*8 +: 8];
                        end
                    end else begin
                        x_positive1 <= 10'd0;
                        x_negative1 <= 10'd0;
                        y_positive1 <= 10'd0;
                        y_negative1 <= 10'd0;
                        filter_sum1 <= 12'd0;
                        filtered1 <= 8'd0;
                    end
                end
                if (valid1) begin
                    // Zero extension before subtraction gives exact signed11 two's complement.
                    gx2 <= {1'b0,x_positive1} - {1'b0,x_negative1};
                    gy2 <= {1'b0,y_positive1} - {1'b0,y_negative1};
                    filtered2 <= FILTER_ENABLE ? rounded_filter[11:4] : filtered1;
                end
                if (valid2) begin
                    gx3 <= gx2;
                    gy3 <= gy2;
                    magnitude3 <= {1'b0,abs_x2[9:0]} + {1'b0,abs_y2[9:0]};
                    filtered3 <= filtered2;
                end
            end
        end
    end endgenerate
endmodule
