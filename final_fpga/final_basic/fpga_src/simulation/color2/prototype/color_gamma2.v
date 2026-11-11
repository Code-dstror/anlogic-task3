`timescale 1ns/1ps
// Independent2PPC prototype: accept four pixels, send the lower two directly
// on that handshake, retain only the upper two. The ROM output supplies the
// upper RGB half; low_rgb supplies the lower, without another whole-group reg.
module color_gamma2 #(parameter integer GAMMA_BYPASS=0)(
    input wire clk,rst_n,
    input wire [119:0] s_data,input wire s_valid,output wire s_ready,
    input wire s_sof,s_eol,s_clipped,
    output wire [95:0] m_data,output wire m_valid,input wire m_ready,
    output wire m_sof,m_eol,m_clipped
);
    reg pending;
    reg [59:0] upper;
    reg held_sof,held_eol,held_clipped;
    reg valid,phase,sof,eol,clipped;
    reg [47:0] low_rgb;
    reg low_clipped;
    wire advance=!rst_n||!valid||!phase||m_ready;
    assign s_ready=rst_n&&advance&&!pending;
    wire take=s_valid&&s_ready;
    wire [59:0] half_data=pending?upper:s_data[59:0];
    wire [47:0] gamma_rgb;
    assign m_valid=rst_n&&valid&&phase;
    assign m_data={gamma_rgb,low_rgb};
    assign m_sof=sof;assign m_eol=eol;assign m_clipped=low_clipped||clipped;
    genvar pixel,channel;
    generate for(pixel=0;pixel<2;pixel=pixel+1)begin:g_pixel
        for(channel=0;channel<3;channel=channel+1)begin:g_channel
            gamma_lut_10to8 #(.C_GAMMA_LINEAR_BYPASS(GAMMA_BYPASS),.C_USE_CE(1)) gamma(
                .i_clk(clk),.i_rstn(rst_n),.i_ce(advance),
                .i_index(half_data[pixel*30+channel*10+:10]),
                .o_value(gamma_rgb[pixel*24+channel*8+:8]));
        end
    end endgenerate
    always @(posedge clk)begin
        if(!rst_n)begin
            pending<=0;valid<=0;phase<=0;sof<=0;eol<=0;clipped<=0;
            low_rgb<=0;low_clipped<=0;
        end else if(advance)begin
            valid<=pending||s_valid;phase<=pending;
            sof<=pending?held_sof:s_sof;eol<=pending?held_eol:s_eol;
            clipped<=pending?held_clipped:s_clipped;
            if(pending)pending<=0;
            if(take)begin
                pending<=1;upper<=s_data[119:60];
                held_sof<=s_sof;held_eol<=s_eol;held_clipped<=s_clipped;
            end
            if(valid&&!phase)begin low_rgb<=gamma_rgb;low_clipped<=clipped;end
        end
    end
endmodule
