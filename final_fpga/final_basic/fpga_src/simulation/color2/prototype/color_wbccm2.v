`timescale 1ns/1ps
//2PPC prototype with the unchanged five-CE WB/CCM arithmetic. Accepting a
//4PPC group clocks its first two pixels directly into the multipliers and
//holds only the upper two. Low corrected half plus last-stage high half form
//the4PPC output; a high-half stall freezes all arithmetic and token controls.
module color_wbccm2 #(
    parameter signed [10:0] CCM00 = 11'sd256, CCM01 = 0, CCM02 = 0,
    parameter signed [10:0] CCM10 = 0, CCM11 = 11'sd256, CCM12 = 0,
    parameter signed [10:0] CCM20 = 0, CCM21 = 0, CCM22 = 11'sd256

)(
    input wire clk,rst_n,
    input wire s_hdr,input wire [29:0] s_gains,
    input wire [167:0] s_data,input wire s_valid,output wire s_ready,
    input wire s_sof,s_eol,
    output wire [167:0] m_data,output wire m_valid,input wire m_ready,
    output wire m_hdr,m_sof,m_eol,m_clipped
);
    reg pending;
    reg [83:0] upper;
    reg [29:0] held_gains;
    reg held_hdr,held_sof,held_eol;
    reg [4:0] valid,phase,hdr_pipe,sof,eol,clipped;
    reg [83:0] low_rgb;
    reg low_clipped;
    wire advance=!rst_n||!valid[4]||!phase[4]||m_ready;
    wire half_hdr=pending?held_hdr:s_hdr;
    wire [29:0] half_gains=pending?held_gains:s_gains;
    wire [83:0] half_data=pending?upper:s_data[83:0];
    wire [83:0] corrected_rgb;
    wire [5:0] wb_clip,ccm_clip;
    assign s_ready=rst_n&&advance&&!pending;
    wire take=s_valid&&s_ready;
    assign m_valid=rst_n&&valid[4]&&phase[4];
    assign m_data={corrected_rgb,low_rgb};
    assign m_hdr=hdr_pipe[4];assign m_sof=sof[4];assign m_eol=eol[4];
    assign m_clipped=low_clipped||clipped[4];
    always @(posedge clk)begin
        if(!rst_n)begin
            pending<=0;valid<=0;phase<=0;hdr_pipe<=0;sof<=0;eol<=0;clipped<=0;
            low_clipped<=0;
        end else if(advance)begin
            valid<={valid[3:0],pending||s_valid};phase<={phase[3:0],pending};
            hdr_pipe<={hdr_pipe[3:0],half_hdr};
            sof<={sof[3:0],pending?held_sof:s_sof};eol<={eol[3:0],pending?held_eol:s_eol};
            clipped[0]<=0;clipped[1]<=|wb_clip;clipped[2]<=clipped[1];
            clipped[3]<=clipped[2];clipped[4]<=clipped[3]||(|ccm_clip);
            if(pending)pending<=0;
            if(take)begin
                pending<=1;upper<=s_data[167:84];held_gains<=s_gains;
                held_hdr<=s_hdr;held_sof<=s_sof;held_eol<=s_eol;
            end
            if(valid[4]&&!phase[4])begin low_rgb<=corrected_rgb;low_clipped<=clipped[4];end
        end
    end
    genvar pixel, channel, term;
    generate for (pixel=0; pixel<2; pixel=pixel+1) begin : lane
        wire [41:0] wb_rgb;
        for (channel=0; channel<3; channel=channel+1) begin : wb
            wire [9:0] gain = half_gains[(2-channel)*10 +: 10];
            wire [23:0] product;
            reg [13:0] value;
            reg hdr_q;
            wire [24:0] rounded = {1'b0,product} + 25'd128;
            wire [16:0] scaled = rounded[24:8];
            wire [13:0] maximum = hdr_q ? 14'd16383 : 14'd1023;
            td_dsp_mult #(.A_WIDTH(14),.B_WIDTH(10),.INPUT_FORMAT("UNSIGNED")) u_gain (
                .clk(clk),.rst_n(rst_n),.en(advance),
                .a(half_data[pixel*42+channel*14 +: 14]),.b(gain),.p(product));
            always @(posedge clk) if (advance) begin
                hdr_q <= half_hdr;
                value <= scaled > {3'd0,maximum} ? maximum : scaled[13:0];
            end
            assign wb_clip[pixel*3+channel] = scaled > {3'd0,maximum};
            assign wb_rgb[channel*14 +: 14] = value;
        end
        for (channel=0; channel<3; channel=channel+1) begin : ccm
            localparam signed [10:0] C0 = channel==2 ? CCM00 : channel==1 ? CCM10 : CCM20;
            localparam signed [10:0] C1 = channel==2 ? CCM01 : channel==1 ? CCM11 : CCM21;
            localparam signed [10:0] C2 = channel==2 ? CCM02 : channel==1 ? CCM12 : CCM22;
            wire [77:0] products;
            for (term=0; term<3; term=term+1) begin : item
                localparam signed [10:0] COEFF = term==0 ? C0 : term==1 ? C1 : C2;
                if (COEFF == 0) begin : zero
                    assign products[term*26 +: 26] = 26'd0;
                end else if (COEFF == 256) begin : identity
                    reg [25:0] delayed;
                    always @(posedge clk) if (advance)
                        delayed <= {4'd0,wb_rgb[(2-term)*14 +: 14],8'd0};
                    assign products[term*26 +: 26] = delayed;
                end else begin : multiply
                    td_dsp_mult #(.A_WIDTH(15),.B_WIDTH(11)) u_coefficient (
                        .clk(clk),.rst_n(rst_n),.en(advance),
                        .a({1'b0,wb_rgb[(2-term)*14 +: 14]}),.b(COEFF),
                        .p(products[term*26 +: 26]));
                end
            end
            wire signed [25:0] p0 = products[0 +: 26];
            wire signed [25:0] p1 = products[26 +: 26];
            wire signed [25:0] p2 = products[52 +: 26];
            reg signed [27:0] partial;
            reg signed [25:0] third;
            reg [13:0] corrected;
            wire signed [28:0] sum = partial + third + 29'sd128;
            wire signed [28:0] shifted = sum >>> 8;
            wire [13:0] maximum = hdr_pipe[3] ? 14'd16383 : 14'd1023;
            always @(posedge clk) if (advance) begin
                partial <= p0 + p1;
                third <= p2;
                corrected <= shifted < 0 ? 14'd0 :
                    shifted > $signed({1'b0,maximum}) ? maximum : shifted[13:0];
            end
            assign ccm_clip[pixel*3+channel] = shifted < 0 || shifted > $signed({1'b0,maximum});
            assign corrected_rgb[pixel*42+channel*14 +: 14] = corrected;
        end
    end endgenerate
endmodule
