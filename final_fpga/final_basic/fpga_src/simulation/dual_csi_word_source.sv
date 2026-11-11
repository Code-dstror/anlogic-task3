`timescale 1ns/1ps
// Electrical/PHY-output fixture only. Production CSI parsing, CRC, event CDC,
// frame identity, crop and all downstream ownership remain in the DUT.
module dual_csi_word_source #(
    parameter integer CAMERA=0, WIDTH=1920, HEIGHT=1080, FIRST_ROW=16, FIRST_GROUP=1,
    parameter integer HIGH_DETAIL=0
)(input wire word_clk, output reg [31:0] word=0, output reg valid=0);
    function automatic [9:0] raw_sample(input integer x,y);
        integer base;
        reg [31:0] hash;
        begin
            if(HIGH_DETAIL!=0)begin
                // Defined unsigned 32-bit hash of each 2x2 Bayer cell. Both
                // eyes carry different high-detail images; values stay RAW10.
                hash=(32'(x/2)*32'h1f123bb5)^(32'(y/2)*32'h5f356495)^(32'(CAMERA+1)*32'h9e3779b9);
                hash=(hash^(hash>>16))*32'h45d9f3b;
                hash=(hash^(hash>>16))*32'h45d9f3b;
                hash=hash^(hash>>16);
                raw_sample=64+(hash[9:0]%896);
            end else if(CAMERA==0)begin
                base=100+((x/16*3+y/8*5)%600);
                raw_sample=base+(!(x%2)&&!(y%2)?180:(x%2)&&(y%2)?20:90);
            end else begin
                base=80+((x/8*7+y/16*11)%580);
                raw_sample=base+(!(x%2)&&!(y%2)?20:(x%2)&&(y%2)?160:110);
            end
        end
    endfunction
    function automatic [5:0] ecc(input [23:0] d);
        begin
            ecc[0]=d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23];
            ecc[1]=d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[23];
            ecc[2]=d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22];
            ecc[3]=d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[23];
            ecc[4]=d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[22]^d[23];
            ecc[5]=d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23];
        end
    endfunction
    function automatic [15:0] crc_byte(input [15:0] c,input [7:0] b);
        reg [15:0] v;
        begin v=c^b;for(integer k=0;k<8;k++)v=v[0]?((v>>1)^16'h8408):(v>>1);crc_byte=v;end
    endfunction
    task automatic send_word(input [31:0] value);
        begin @(negedge word_clk);word=value;valid=1;@(negedge word_clk);valid=0;end
    endtask
    task automatic event_word(input [1:0] kind,input [15:0] frame_number);
        reg [23:0] h;
        begin h={frame_number,6'd0,kind};send_word({2'd0,ecc(h),h});repeat(4)@(negedge word_clk);end
    endtask
    task automatic line(input integer row,input bit bad_crc);
        reg [7:0] bytes[0:(WIDTH/4+FIRST_GROUP+1)*5+7];
        reg [15:0] crc;reg [23:0] h;reg [9:0] samples[0:3];
        integer groups,byte_count;
        begin
            groups=WIDTH/4+FIRST_GROUP+1;byte_count=groups*5;
            for(integer n=0;n<byte_count+8;n++)bytes[n]=0;
            for(integer group_index=0;group_index<groups;group_index++)begin
                for(integer lane=0;lane<4;lane++)begin
                    samples[lane]=(row>=FIRST_ROW&&group_index>=FIRST_GROUP&&group_index<FIRST_GROUP+WIDTH/4)?
                        raw_sample((group_index-FIRST_GROUP)*4+lane,row-FIRST_ROW):10'd123;
                    bytes[group_index*5+lane]=samples[lane][9:2];
                end
                bytes[group_index*5+4]={samples[3][1:0],samples[2][1:0],samples[1][1:0],samples[0][1:0]};
            end
            crc=16'hffff;for(integer n=0;n<byte_count;n++)crc=crc_byte(crc,bytes[n]);
            bytes[byte_count]=crc[7:0]^{7'd0,bad_crc};bytes[byte_count+1]=crc[15:8];
            h={16'(byte_count),8'h2b};send_word({2'd0,ecc(h),h});repeat(2)@(negedge word_clk);
            for(integer n=0;n<byte_count+2;n+=4)send_word({bytes[n+3],bytes[n+2],bytes[n+1],bytes[n]});
            repeat(4)@(negedge word_clk);
        end
    endtask
    task automatic frame(input [15:0] frame_number,input integer bad_crc_row);
        begin
            event_word(0,frame_number);
            for(integer row=0;row<HEIGHT+FIRST_ROW;row++)line(row,row==bad_crc_row);
            event_word(1,frame_number);
        end
    endtask
endmodule
