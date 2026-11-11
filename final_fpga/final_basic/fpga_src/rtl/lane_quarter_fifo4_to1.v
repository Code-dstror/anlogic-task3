// Single PIX-clock 4PPC->1PPC queue.147 useful bits/group, padded to160:
// {bad1,y9,x9,{hint2,p11Y8,Gy11,Gx11}*4}. Four existing official40bit
// ERAMs, depth256. resident counts RAM, prefetched RAM output and live head.
// Every scalar sample is launched from the registered head. Loading a new
// head beside final-lane retirement retains II1 and isolates ERAM clock-to-Q
// and the word/head metadata mux from the ridge arithmetic. Startup <=3 clocks.
module lane_quarter_fifo4_to1 #(
    // Generic users retain combinational cancellation. The lane owner alone
    // may observe the held old sample on clear: its worker discards that frame.
    parameter integer CLEAR_SUPPRESS_VALID=1
)(
    input wire clk,rst_n,clear,
    input wire s_valid,output wire s_ready,
    input wire [146:0] s_data,
    output wire m_valid,input wire m_ready,
    output wire [31:0] m_sample,
    output wire [8:0] m_x,m_y,
    output wire m_bad,
    output wire empty,output wire [8:0] resident,
    output wire overflow
);
    reg [8:0] resident_count,unread_count;
    reg [7:0] write_pointer,read_pointer;
    reg ram_valid,head_valid;
    reg [1:0] phase;
    reg [127:0] head_samples;
    reg [18:0] head_metadata;
    wire run=rst_n&&!clear;
    wire [159:0] read_word;
    wire [159:0] write_word={13'd0,s_data};
    assign resident=resident_count;
    assign empty=resident_count==0;
    assign m_valid=rst_n&&head_valid&&(CLEAR_SUPPRESS_VALID!=0 ? !clear : 1'b1);
    wire take=m_valid&&m_ready;
    wire pop=take&&head_valid&&phase==3;
    wire adopt=run&&ram_valid&&(!head_valid||pop);
    assign s_ready=run&&(resident_count<256||pop);
    wire push=s_valid&&s_ready;
    assign overflow=run&&s_valid&&!s_ready;
    wire read_enable=run&&unread_count!=0&&(!ram_valid||adopt);
    wire [18:0] metadata=head_metadata;
    assign m_sample=head_samples[31:0];
    assign m_x=metadata[8:0]+{7'd0,phase};
    assign m_y=metadata[17:9];
    assign m_bad=metadata[18];
    genvar bank;
    generate for(bank=0;bank<4;bank=bank+1)begin:g_bank
        td_sdp_ram40 #(.WIDTH(40),.DEPTH(256),.ADDR_WIDTH(8)) storage(
            .clk(clk),.wr_en(push),.wr_addr(write_pointer),
            .wr_data(write_word[bank*40+:40]),.rd_en(read_enable),
            .rd_addr(read_pointer),.rd_data(read_word[bank*40+:40]));
    end endgenerate
    always @(posedge clk)begin
        if(!rst_n||clear)begin
            resident_count<=0;unread_count<=0;write_pointer<=0;read_pointer<=0;
            ram_valid<=0;head_valid<=0;phase<=0;
        end else begin
            case({push,pop})
                2'b10:resident_count<=resident_count+1'b1;
                2'b01:resident_count<=resident_count-1'b1;
                default:begin end
            endcase
            case({push,read_enable})
                2'b10:unread_count<=unread_count+1'b1;
                2'b01:unread_count<=unread_count-1'b1;
                default:begin end
            endcase
            if(push)write_pointer<=write_pointer+1'b1;
            if(read_enable)begin read_pointer<=read_pointer+1'b1;ram_valid<=1;end
            else if(adopt)ram_valid<=0;
            if(adopt)begin
                head_samples<=read_word[127:0];head_metadata<=read_word[146:128];
                head_valid<=1;phase<=0;
            end else if(take&&head_valid)begin
                head_samples<={32'd0,head_samples[127:32]};
                if(phase==3)begin head_valid<=0;phase<=0;end
                else phase<=phase+1'b1;
            end
        end
    end
endmodule
