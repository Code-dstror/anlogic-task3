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
        // Exact BT.601 identities; RGB8 differences fit signed9.
        wire signed [8:0] delta_bg=$signed({1'b0,blue})-$signed({1'b0,green});
        wire signed [8:0] delta_rg=$signed({1'b0,red})-$signed({1'b0,green});
        reg signed [8:0] bg1,rg1;
        wire signed [25:0] cb_rg,cr_bg;
        // Existing one-edge signed 17x9 multiplier IP, no MAC or new IP.
        td_dsp_mult #(.A_WIDTH(17),.B_WIDTH(9)) u_cb_rg(
            .clk(clk),.rst_n(rst_n),.en(advance),.a(-17'sd11059),.b(delta_rg),.p(cb_rg));
        td_dsp_mult #(.A_WIDTH(17),.B_WIDTH(9)) u_cr_bg(
            .clk(clk),.rst_n(rst_n),.en(advance),.a(-17'sd5329),.b(delta_bg),.p(cr_bg));
        wire signed [23:0] shifted_bg={bg1,15'd0};
        wire signed [23:0] shifted_rg={rg1,15'd0};
        wire signed [25:0] combine_cb={{2{shifted_bg[23]}},shifted_bg}+cb_rg;
        wire signed [25:0] combine_cr={{2{shifted_rg[23]}},shifted_rg}+cr_bg;
        // Correlated RGB inputs bound each unbiased sum to +/-8355840;
        // signed24 is exact, despite a looser independent-operand bound.
        reg signed [23:0] cb_partial,cr_partial;
        wire signed [27:0] cb_sum={{4{cb_partial[23]}},cb_partial}+28'sd8421376;
        wire signed [27:0] cr_sum={{4{cr_partial[23]}},cr_partial}+28'sd8421376;
        reg [7:0] cb,cr;
        always @(posedge clk) if(advance) begin
            bg1<=delta_bg;rg1<=delta_rg;
            cb_partial<=combine_cb[23:0];cr_partial<=combine_cr[23:0];
            // Preserve aa3e611's pixel clamp, then its original pair average.
            cb<=cb_sum[24] ? 8'd255 : cb_sum[23:16];
            cr<=cr_sum[24] ? 8'd255 : cr_sum[23:16];
        end
        assign cb_pixels[pixel*8 +: 8]=cb;assign cr_pixels[pixel*8 +: 8]=cr;
    end endgenerate
endmodule
