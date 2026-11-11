// 将四路RGB像素转换为JPEG四二二亮色分量
module jpeg_rgb_to_ycbcr_422_legacy (
    // 时钟与复位
    input  wire i_clk,
    input  wire i_rst_n,

    // 输入RGB像素
    input  wire i_valid,
    output wire o_ready,
    input  wire [95:0] i_rgb,
    input  wire i_sof,
    input  wire i_eol,
    input  wire [31:0] i_capture_id,

    // 输出亮色分量
    output reg o_valid,
    input  wire i_ready,
    output reg  [31:0] o_y,
    output reg  [15:0] o_cb,
    output reg  [15:0] o_cr,
    output reg o_sof,
    output reg o_eol,
    output reg  [31:0] o_capture_id
);

    reg [31:0] y_next;
    reg [15:0] cb_next;
    reg [15:0] cr_next;
    reg [23:0] rgb_pixel;
    reg [7:0]  cb_even;
    reg [7:0]  cr_even;
    reg [7:0]  cb_pixel;
    reg [7:0]  cr_pixel;
    integer lane;

    // 色度的 Q16 累加值可能为负
    // 先做有符号算术右移，再限幅并平均相邻两个样本
    function [7:0] clip8;
        input signed [31:0] value;
        begin
            if (value < 32'sd0)
                clip8 = 8'd0;
            else if (value > 32'sd255)
                clip8 = 8'd255;
            else
                clip8 = value[7:0];
        end
    endfunction

    function [7:0] rgb_y;
        input [7:0] red;
        input [7:0] green;
        input [7:0] blue;
        reg signed [31:0] r_ext;
        reg signed [31:0] g_ext;
        reg signed [31:0] b_ext;
        reg signed [31:0] sum;
        begin
            r_ext = {24'd0, red};
            g_ext = {24'd0, green};
            b_ext = {24'd0, blue};
            sum = 32'sd19595 * r_ext + 32'sd38470 * g_ext
                + 32'sd7471 * b_ext + 32'sd32768;
            rgb_y = clip8(sum >>> 16);
        end
    endfunction

    function [7:0] rgb_cb;
        input [7:0] red;
        input [7:0] green;
        input [7:0] blue;
        reg signed [31:0] r_ext;
        reg signed [31:0] g_ext;
        reg signed [31:0] b_ext;
        reg signed [31:0] sum;
        begin
            r_ext = {24'd0, red};
            g_ext = {24'd0, green};
            b_ext = {24'd0, blue};
            sum = -32'sd11059 * r_ext - 32'sd21709 * g_ext
                + 32'sd32768 * b_ext + 32'sd8388608 + 32'sd32768;
            rgb_cb = clip8(sum >>> 16);
        end
    endfunction

    function [7:0] rgb_cr;
        input [7:0] red;
        input [7:0] green;
        input [7:0] blue;
        reg signed [31:0] r_ext;
        reg signed [31:0] g_ext;
        reg signed [31:0] b_ext;
        reg signed [31:0] sum;
        begin
            r_ext = {24'd0, red};
            g_ext = {24'd0, green};
            b_ext = {24'd0, blue};
            sum = 32'sd32768 * r_ext - 32'sd27439 * g_ext
                - 32'sd5329 * b_ext + 32'sd8388608 + 32'sd32768;
            rgb_cr = clip8(sum >>> 16);
        end
    endfunction

    // 九位加法保留两个八位样本相加产生的进位
    function [7:0] average_pair;
        input [7:0] first;
        input [7:0] second;
        reg [8:0] sum;
        begin
            sum = {1'b0, first} + {1'b0, second} + 9'd1;
            average_pair = sum[8:1];
        end
    endfunction

    // 组合计算四个像素的亮度与抽样色度
    always @(*) begin
        y_next = 32'd0;
        cb_next = 16'd0;
        cr_next = 16'd0;
        rgb_pixel = 24'd0;
        cb_even = 8'd0;
        cr_even = 8'd0;
        cb_pixel = 8'd0;
        cr_pixel = 8'd0;
        for (lane = 0; lane < 4; lane = lane + 1) begin
            rgb_pixel = i_rgb[24*lane +: 24];
            y_next[8*lane +: 8] = rgb_y(rgb_pixel[23:16], rgb_pixel[15:8], rgb_pixel[7:0]);
            cb_pixel = rgb_cb(rgb_pixel[23:16], rgb_pixel[15:8], rgb_pixel[7:0]);
            cr_pixel = rgb_cr(rgb_pixel[23:16], rgb_pixel[15:8], rgb_pixel[7:0]);
            if ((lane & 1) == 0) begin
                cb_even = cb_pixel;
                cr_even = cr_pixel;
            end else begin
                cb_next[8*(lane/2) +: 8] = average_pair(cb_even, cb_pixel);
                cr_next[8*(lane/2) +: 8] = average_pair(cr_even, cr_pixel);
            end
        end
    end

    // 复位有效期间包括复位沿都禁止握手
    // 输出空闲或被接收时开放输入
    assign o_ready = i_rst_n && (!o_valid || i_ready);

    // 保持转换结果直到输出端完成握手
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_valid <= 1'b0;
            o_y <= 32'd0;
            o_cb <= 16'd0;
            o_cr <= 16'd0;
            o_sof <= 1'b0;
            o_eol <= 1'b0;
            o_capture_id <= 32'd0;
        end else if (o_ready) begin
            o_valid <= i_valid;
            if (i_valid) begin
                o_y <= y_next;
                o_cb <= cb_next;
                o_cr <= cr_next;
                o_sof <= i_sof;
                o_eol <= i_eol;
                o_capture_id <= i_capture_id;
            end
        end
    end
endmodule

// The production path consumes the single shared Y result from preprocessing.
// Only chroma is calculated here; both paths preserve accepted-beat ordering.
module jpeg_rgb_to_ycbcr_422 #(
    parameter integer SHARED_LUMA_ENABLE = 0
) (
    input wire i_clk, input wire i_rst_n,
    input wire i_valid, output wire o_ready,
    input wire [95:0] i_rgb, input wire [31:0] i_luma,
    input wire i_sof, input wire i_eol, input wire [31:0] i_capture_id,
    output wire o_valid, input wire i_ready,
    output wire [31:0] o_y, output wire [15:0] o_cb, o_cr,
    output wire o_sof, o_eol, output wire [31:0] o_capture_id
);
    generate if (SHARED_LUMA_ENABLE == 0) begin : legacy
        jpeg_rgb_to_ycbcr_422_legacy u_color (
            .i_clk(i_clk),.i_rst_n(i_rst_n),.i_valid(i_valid),.o_ready(o_ready),
            .i_rgb(i_rgb),.i_sof(i_sof),.i_eol(i_eol),.i_capture_id(i_capture_id),
            .o_valid(o_valid),.i_ready(i_ready),.o_y(o_y),.o_cb(o_cb),.o_cr(o_cr),
            .o_sof(o_sof),.o_eol(o_eol),.o_capture_id(o_capture_id));
    end else begin : shared_y
        jpeg_chroma_422_pipeline u_color (
            .clk(i_clk),.rst_n(i_rst_n),.s_valid(i_valid),.s_ready(o_ready),
            .s_rgb(i_rgb),.s_y(i_luma),.s_sof(i_sof),.s_eol(i_eol),.s_id(i_capture_id),
            .m_valid(o_valid),.m_ready(i_ready),.m_y(o_y),.m_cb(o_cb),.m_cr(o_cr),
            .m_sof(o_sof),.m_eol(o_eol),.m_id(o_capture_id));
    end endgenerate
endmodule

// Q16 Cb/Cr uses 16 registered vendor multipliers; powers of two are wiring.
module jpeg_chroma_422_pipeline (
    input wire clk, input wire rst_n,
    input wire s_valid, output wire s_ready,
    input wire [95:0] s_rgb, input wire [31:0] s_y,
    input wire s_sof, s_eol, input wire [31:0] s_id,
    output wire m_valid, input wire m_ready,
    output reg [31:0] m_y, output reg [15:0] m_cb, m_cr,
    output wire m_sof, m_eol, output wire [31:0] m_id
);
    reg [3:0] valid_pipe,sof_pipe,eol_pipe;
    reg [31:0] id_pipe[0:3],y_pipe[0:2];
    wire advance = !valid_pipe[3] || m_ready;
    wire [31:0] cb_pixels,cr_pixels;
    assign s_ready = rst_n && advance;
    assign m_valid = rst_n && valid_pipe[3];
    assign m_sof=sof_pipe[3]; assign m_eol=eol_pipe[3]; assign m_id=id_pipe[3];
    function [7:0] clip8;
        input signed [27:0] x;
        begin clip8=x<0 ? 8'd0 : x>255 ? 8'd255 : x[7:0]; end
    endfunction
    function [7:0] average;
        input [7:0] a,b; reg [8:0] sum;
        begin sum={1'b0,a}+{1'b0,b}+9'd1; average=sum[8:1]; end
    endfunction
    integer n;
    always @(posedge clk) begin
        if(!rst_n) begin
            valid_pipe<=0;sof_pipe<=0;eol_pipe<=0;m_y<=0;m_cb<=0;m_cr<=0;
            for(n=0;n<4;n=n+1) id_pipe[n]<=0;
            for(n=0;n<3;n=n+1) y_pipe[n]<=0;
        end else if(advance) begin
            valid_pipe<={valid_pipe[2:0],s_valid};
            sof_pipe<={sof_pipe[2:0],s_sof}; eol_pipe<={eol_pipe[2:0],s_eol};
            id_pipe[0]<=s_id; for(n=1;n<4;n=n+1) id_pipe[n]<=id_pipe[n-1];
            y_pipe[0]<=s_y;y_pipe[1]<=y_pipe[0];y_pipe[2]<=y_pipe[1];m_y<=y_pipe[2];
            m_cb<={average(cb_pixels[31:24],cb_pixels[23:16]),average(cb_pixels[15:8],cb_pixels[7:0])};
            m_cr<={average(cr_pixels[31:24],cr_pixels[23:16]),average(cr_pixels[15:8],cr_pixels[7:0])};
        end
    end
    genvar pixel;
    generate for(pixel=0;pixel<4;pixel=pixel+1) begin : lane
        wire [7:0] red=s_rgb[pixel*24+16 +: 8];
        wire [7:0] green=s_rgb[pixel*24+8 +: 8];
        wire [7:0] blue=s_rgb[pixel*24 +: 8];
        wire signed [25:0] cb_r,cb_g,cr_g,cr_b;
        reg signed [25:0] cb_b,cr_r;
        td_dsp_mult #(.A_WIDTH(17),.B_WIDTH(9)) u_cb_r(.clk(clk),.rst_n(rst_n),.en(advance),.a(-17'sd11059),.b({1'b0,red}),.p(cb_r));
        td_dsp_mult #(.A_WIDTH(17),.B_WIDTH(9)) u_cb_g(.clk(clk),.rst_n(rst_n),.en(advance),.a(-17'sd21709),.b({1'b0,green}),.p(cb_g));
        td_dsp_mult #(.A_WIDTH(17),.B_WIDTH(9)) u_cr_g(.clk(clk),.rst_n(rst_n),.en(advance),.a(-17'sd27439),.b({1'b0,green}),.p(cr_g));
        td_dsp_mult #(.A_WIDTH(17),.B_WIDTH(9)) u_cr_b(.clk(clk),.rst_n(rst_n),.en(advance),.a(-17'sd5329),.b({1'b0,blue}),.p(cr_b));
        reg signed [26:0] cb_partial,cr_partial;
        reg signed [25:0] cb_third,cr_third;
        reg [7:0] cb,cr;
        wire signed [27:0] cb_sum=cb_partial+cb_third+28'sd8421376;
        wire signed [27:0] cr_sum=cr_partial+cr_third+28'sd8421376;
        always @(posedge clk) if(advance) begin
            cb_b<={3'd0,blue,15'd0}; cr_r<={3'd0,red,15'd0};
            cb_partial<=cb_r+cb_g;cr_partial<=cr_g+cr_b;
            cb_third<=cb_b;cr_third<=cr_r;
            cb<=clip8(cb_sum>>>16);cr<=clip8(cr_sum>>>16);
        end
        assign cb_pixels[pixel*8 +: 8]=cb;assign cr_pixels[pixel*8 +: 8]=cr;
    end endgenerate
endmodule
