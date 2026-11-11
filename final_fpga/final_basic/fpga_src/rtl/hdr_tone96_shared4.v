`timescale 1ns/1ps

// Two HDR pixels per advance, with one shared four-pixel input and output.
// SDR bypass and all HDR flags use the same ordered output boundary.
module hdr_tone96_shared4 (
    input wire clk, rst_n, clear,
    input wire [167:0] s_data,
    input wire s_hdr, s_valid, s_sof, s_eol, s_clipped,
    output wire s_ready,
    output reg [119:0] m_data,
    output wire m_valid,
    input wire m_ready,
    output reg m_sof, m_eol, m_clipped
);
    wire run=rst_n && !clear;
    reg output_valid;
    wire advance=run && (!output_valid || m_ready);
    reg [167:0] group_data;
    reg group_valid,group_sof,group_eol,group_clipped,group_second;
    reg [8:0] valid_pipe,sof_pipe,eol_pipe,clipped_pipe,second_pipe;
    reg [59:0] first_pair;
    wire [59:0] mapped_pair;
    wire hdr_empty=!group_valid && valid_pipe==0;
    assign s_ready=advance && (s_hdr ? (!group_valid || group_second) : hdr_empty);
    wire take=s_valid && s_ready;
    assign m_valid=run && output_valid;

    // A constant slice and its rounding bit implement each of the five exact
    // power-of-two divisions. Both lanes use the same interpolation contract.
    function [11:0] rounded_gain_delta;
        input [20:0] product;
        input [3:0] shift;
        begin
            case(shift)
                5:rounded_gain_delta=product[16:5]+product[4];
                6:rounded_gain_delta=product[17:6]+product[5];
                7:rounded_gain_delta=product[18:7]+product[6];
                8:rounded_gain_delta=product[19:8]+product[7];
                default:rounded_gain_delta=product[20:9]+product[8];
            endcase
        end
    endfunction
    function [5:0] rounded_tone_delta;
        input [14:0] product;
        input [3:0] shift;
        begin
            case(shift)
                5:rounded_tone_delta=product[10:5]+product[4];
                6:rounded_tone_delta=product[11:6]+product[5];
                7:rounded_tone_delta=product[12:7]+product[6];
                8:rounded_tone_delta=product[13:8]+product[7];
                default:rounded_tone_delta=product[14:9]+product[8];
            endcase
        end
    endfunction

    integer pixel,channel;
    always @(posedge clk)begin
        if(!run)begin
            group_valid<=0;group_second<=0;output_valid<=0;
            valid_pipe<=0;sof_pipe<=0;eol_pipe<=0;clipped_pipe<=0;
        end else if(advance)begin
            output_valid<=0;
            valid_pipe<={valid_pipe[7:0],group_valid};
            sof_pipe<={sof_pipe[7:0],group_sof};
            eol_pipe<={eol_pipe[7:0],group_eol};
            clipped_pipe<={clipped_pipe[7:0],group_clipped};
            second_pipe<={second_pipe[7:0],group_second};
            if(group_valid)begin
                group_data<={84'd0,group_data[167:84]};
                group_second<=!group_second;
                if(group_second)group_valid<=0;
            end
            if(take && s_hdr)begin
                group_data<=s_data;group_second<=0;group_valid<=1;
                group_sof<=s_sof;group_eol<=s_eol;group_clipped<=s_clipped;
            end
            if(take && !s_hdr)begin
                // Post-CCM SDR samples are normally already 0..1023.
                for(pixel=0;pixel<4;pixel=pixel+1)
                    for(channel=0;channel<3;channel=channel+1)
                        m_data[pixel*30+channel*10+:10]<=
                            |s_data[pixel*42+channel*14+10+:4] ?
                            10'd1023 : s_data[pixel*42+channel*14+:10];
                output_valid<=1;m_sof<=s_sof;m_eol<=s_eol;m_clipped<=s_clipped;
            end
            if(valid_pipe[8])begin
                if(second_pipe[8])begin
                    m_data<={mapped_pair,first_pair};output_valid<=1;
                    m_sof<=sof_pipe[8];m_eol<=eol_pipe[8];m_clipped<=clipped_pipe[8];
                end else first_pair<=mapped_pair;
            end
        end
    end

    genvar lane,component;
    generate for(lane=0;lane<2;lane=lane+1)begin:g_pixel_lane
        wire [41:0] rgb_input=group_data[lane*42+:42];
        reg [41:0] rgb0,rgb1,rgb2,rgb3,rgb4,rgb5;
        reg [13:0] max_rg0,maximum1,maximum2,maximum3,maximum4,maximum5;
        wire [13:0] maximum0=max_rg0>rgb0[13:0] ? max_rg0 : rgb0[13:0];
        reg [6:0] index2;
        reg [8:0] remainder2,remainder3;
        reg [3:0] shift2,shift3,shift4;
        wire [39:0] coeff_low3,coeff_high3;
        wire [44:0] coefficients3={coeff_high3[4:0],coeff_low3};
        reg [16:0] gain_base4,gain5;
        reg [9:0] tone_base4,tone5,tone6,tone7;
        wire [35:0] gain_product4,tone_product4;

        // Each lane has an independent read of the original 45-bit knots.
        tone96_rom0 u_rom_low(
            .dia(40'd0),.addra(9'd0),.cea(1'b0),.clka(clk),
            .dob(coeff_low3),.addrb({2'd0,index2}),.ceb(advance && valid_pipe[2]));
        tone96_rom1 u_rom_high(
            .dia(40'd0),.addra(9'd0),.cea(1'b0),.clka(clk),
            .dob(coeff_high3),.addrb({2'd0,index2}),.ceb(advance && valid_pipe[2]));
        mult_18s18s_p1 u_gain_delta(
            .clk(clk),.rst(!run),.ce(advance),
            .a({6'd0,coefficients3[28:17]}),.b({9'd0,remainder3}),.p(gain_product4));
        mult_18s18s_p1 u_tone_delta(
            .clk(clk),.rst(!run),.ce(advance),
            .a({12'd0,coefficients3[44:39]}),.b({9'd0,remainder3}),.p(tone_product4));

        always @(posedge clk)if(advance)begin
            rgb0<=rgb_input;
            max_rg0<=rgb_input[41:28]>rgb_input[27:14] ? rgb_input[41:28] : rgb_input[27:14];
            rgb1<=rgb0;maximum1<=maximum0;
            rgb2<=rgb1;maximum2<=maximum1;
            if(maximum1<1024)begin
                index2<={2'd0,maximum1[9:5]};remainder2<={4'd0,maximum1[4:0]};shift2<=5;
            end else if(maximum1<2048)begin
                index2<=7'd32+{3'd0,maximum1[9:6]};remainder2<={3'd0,maximum1[5:0]};shift2<=6;
            end else if(maximum1<4096)begin
                index2<=7'd48+{3'd0,maximum1[10:7]};remainder2<={2'd0,maximum1[6:0]};shift2<=7;
            end else if(maximum1<8192)begin
                index2<=7'd64+{3'd0,maximum1[11:8]};remainder2<={1'd0,maximum1[7:0]};shift2<=8;
            end else begin
                index2<=7'd80+{3'd0,maximum1[12:9]};remainder2<=maximum1[8:0];shift2<=9;
            end
            rgb3<=rgb2;maximum3<=maximum2;remainder3<=remainder2;shift3<=shift2;
            rgb4<=rgb3;maximum4<=maximum3;shift4<=shift3;
            gain_base4<=coefficients3[16:0];tone_base4<=coefficients3[38:29];
            rgb5<=rgb4;maximum5<=maximum4;
            gain5<=gain_base4-{5'd0,rounded_gain_delta(gain_product4[20:0],shift4)};
            tone5<=tone_base4+{4'd0,rounded_tone_delta(tone_product4[14:0],shift4)};
            tone6<=tone5;tone7<=tone6;
        end

        for(component=0;component<3;component=component+1)begin:g_component
            wire [35:0] product6;
            reg [30:0] rounded7;
            reg maximum6,maximum7;
            reg [9:0] result8;
            mult_18s18s_p1 u_color_gain(
                .clk(clk),.rst(!run),.ce(advance),
                .a({4'd0,rgb5[component*14+:14]}),.b({1'b0,gain5}),.p(product6));
            always @(posedge clk)if(advance)begin
                maximum6<=rgb5[component*14+:14]==maximum5;
                rounded7<=product6[30:0]+31'd32768;maximum7<=maximum6;
                result8<=(maximum7 || rounded7[30:16]>{5'd0,tone7}) ? tone7 : rounded7[25:16];
            end
            assign mapped_pair[lane*30+component*10+:10]=result8;
        end
    end endgenerate
endmodule
