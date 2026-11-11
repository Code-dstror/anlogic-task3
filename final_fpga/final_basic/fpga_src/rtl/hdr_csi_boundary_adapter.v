`timescale 1ns/1ps
`default_nettype none

// Restricted IMX415 packet-boundary contract; see HDR_PACKET_BOUNDARY_R2.md.
// This is a WORD-domain pipeline, not an LP/EoT detector. The existing header
// ECC is decoded once here and registered before either VC parser uses it.
module hdr_csi_boundary_adapter #(
    parameter integer EXPECTED_RAW_BYTES=2916,
    parameter [5:0] RAW_DT=6'h2c,
    parameter [1:0] LONG_VC=0, SHORT_VC=1
) (
    input wire i_clk,i_reset_n,
    input wire [31:0] i_word,
    input wire i_word_valid,
    input wire i_boundary_open,
    output wire [31:0] o_word,
    output wire o_word_valid,
    output wire [23:0] o_header_corrected,
    output wire [5:0] o_header_syndrome,
    output wire o_header_good,
    output wire o_boundary_reject
);
    function [5:0] header_ecc;
        input [23:0] d;
        begin
            header_ecc[0]=d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23];
            header_ecc[1]=d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[22]^d[23];
            header_ecc[2]=d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22];
            header_ecc[3]=d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[23];
            header_ecc[4]=d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[22]^d[23];
            header_ecc[5]=d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23];
        end
    endfunction
    function supported_header;
        input [23:0] h;
        reg member;
        begin
            member=(h[7:6]==LONG_VC)||(h[7:6]==SHORT_VC);
            supported_header=member &&
                ((h[5:0]<=6'h03) || (h[5:0]==6'h12) || (h[5:0]==6'h37) ||
                 ((h[5:0]==RAW_DT)&&(h[23:8]==EXPECTED_RAW_BYTES)));
        end
    endfunction

    reg [23:0] corrected;
    reg [5:0] syndrome,column;
    reg found;
    integer bit_index;
    always @* begin
        syndrome=header_ecc(i_word[23:0])^i_word[29:24];
        corrected=i_word[23:0];
        found=(syndrome==0);
        if((syndrome!=0)&&((syndrome&(syndrome-1'b1))==0))found=1;
        column=0;
        for(bit_index=0;bit_index<24;bit_index=bit_index+1)begin
            column=header_ecc(24'b1<<bit_index);
            if((syndrome!=0)&&(syndrome==column))begin
                corrected[bit_index]=~i_word[bit_index];found=1;
            end
        end
    end

    // 65 + 64 + 1 = 130 declared FF. No frame storage and no CDC.
    reg [31:0] decode_word,candidate_word;
    reg [23:0] decode_header,candidate_header;
    reg [5:0] decode_syndrome,candidate_syndrome;
    reg decode_good,decode_supported,decode_valid;
    reg candidate_good,candidate_valid;
    reg draining;
    wire candidate_supported=supported_header(candidate_header);
    wire zero_confirmed=decode_valid && decode_good && decode_supported &&
        decode_header!=24'd0;
    wire boundary_accept=candidate_good && candidate_supported &&
        ((candidate_header!=24'd0)||zero_confirmed);
    assign o_word=candidate_word;
    assign o_header_corrected=candidate_header;
    assign o_header_syndrome=candidate_syndrome;
    assign o_header_good=candidate_good;
    assign o_word_valid=candidate_valid && !draining &&
        (!i_boundary_open || boundary_accept);
    assign o_boundary_reject=candidate_valid && !draining &&
        i_boundary_open && !boundary_accept;

    always @(posedge i_clk)begin
        if(!i_reset_n)begin
            decode_word<=0;decode_header<=0;decode_syndrome<=0;
            decode_good<=0;decode_supported<=0;decode_valid<=0;
            candidate_word<=0;candidate_header<=0;candidate_syndrome<=0;
            candidate_good<=0;candidate_valid<=0;draining<=0;
        end else begin
            decode_word<=i_word;decode_header<=corrected;decode_syndrome<=syndrome;
            decode_good<=found && (i_word[31:30]==0);
            decode_supported<=supported_header(corrected);decode_valid<=i_word_valid;
            candidate_word<=decode_word;candidate_header<=decode_header;
            candidate_syndrome<=decode_syndrome;candidate_good<=decode_good;
            candidate_valid<=decode_valid;
            if(o_boundary_reject)begin
                draining<=1;decode_valid<=0;candidate_valid<=0;
            end else if(draining)begin
                // Discard the feedback pipeline already in flight. A new
                // acquisition is allowed only after its actual valid gap.
                decode_valid<=0;candidate_valid<=0;
                if(!i_word_valid)draining<=0;
            end
        end
    end
endmodule
`default_nettype wire
