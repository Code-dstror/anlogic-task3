`timescale 1ns / 1ps
// Simulation-only finite-memory AXI model; never registered in a TD source set.
module axi128_stall_memory #(
    parameter integer MEMORY_BYTES=65536,
    // Focused frame bench: map camera0/1 slot0 to disjoint 4 MiB banks.
    parameter integer FRAME_BANK_MAP=0
) (
    input wire clk,rst_n,
    input wire [3:0] awid,arid,
    input wire [27:0] awaddr,araddr,
    input wire [7:0] awlen,arlen,
    input wire [2:0] awsize,arsize,
    input wire [1:0] awburst,arburst,
    input wire awvalid,wvalid,wlast,bready,arvalid,rready,
    input wire [127:0] wdata,
    input wire [15:0] wstrb,
    output wire awready,wready,arready,
    output reg [3:0] bid,rid,
    output reg [1:0] bresp,rresp,
    output reg bvalid,rvalid,rlast,
    output reg [127:0] rdata,
    input wire inject_b_error,inject_r_error,inject_data_error,
    output reg [31:0] aw_count,b_count,ar_count,r_count,w_count
);
    reg [7:0] memory [0:MEMORY_BYTES-1];
    function integer memory_index;
        input [27:0] address;
        begin memory_index=FRAME_BANK_MAP!=0 ? {address[26],address[21:0]} :
            address & (MEMORY_BYTES-1);end
    endfunction
    reg [31:0] lfsr;
    reg wa_active,ra_active;
    reg [27:0] wa,ra;
    reg [7:0] wn,rn;
    reg [3:0] aid;
    integer wi,ri,bd,rd,lane;
    assign awready=rst_n && !wa_active && !bvalid && bd==0 && lfsr[2:0]!=0;
    assign wready=rst_n && wa_active && lfsr[5:3]!=0;
    assign arready=rst_n && !ra_active && !rvalid && lfsr[8:6]!=0;
    always @(posedge clk) begin
        if(!rst_n) begin
            lfsr<=32'h32ba9341;wa_active<=0;ra_active<=0;bvalid<=0;rvalid<=0;
            bd<=0;rd<=0;wi<=0;ri<=0;wa<=0;ra<=0;wn<=0;rn<=0;aid<=0;
            bid<=0;rid<=0;bresp<=0;rresp<=0;rlast<=0;rdata<=0;
            aw_count<=0;b_count<=0;ar_count<=0;r_count<=0;w_count<=0;
        end else begin
            lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
            if(awvalid && awready) begin
                if(awsize!=4 || awburst!=1 || awaddr[3:0]!=0 || awlen>15 ||
                   ({1'b0,awaddr[11:0]}+(awlen+1)*16)>4096) $fatal(1,"AXI AW contract");
                wa<=awaddr;wn<=awlen;wi<=0;bid<=awid;wa_active<=1;aw_count<=aw_count+1;
            end
            if(wvalid && wready) begin
                if(wlast!=(wi==wn)) $fatal(1,"AXI WLAST");
                for(lane=0;lane<16;lane=lane+1)
                    if(wstrb[lane]) memory[memory_index(wa+wi*16+lane)]<=wdata[lane*8+:8];
                wi<=wi+1;w_count<=w_count+1;
                if(wlast) begin wa_active<=0;bd<=12;bresp<=inject_b_error ? 2 : 0;end
            end
            if(bd>0) begin bd<=bd-1;if(bd==1)bvalid<=1;end
            if(bvalid && bready) begin bvalid<=0;b_count<=b_count+1;end
            if(arvalid && arready) begin
                if(arsize!=4 || arburst!=1 || araddr[3:0]!=0 || arlen>15 ||
                   ({1'b0,araddr[11:0]}+(arlen+1)*16)>4096) $fatal(1,"AXI AR contract");
                ra<=araddr;rn<=arlen;ri<=0;aid<=arid;ra_active<=1;rd<=4;ar_count<=ar_count+1;
            end
            if(rd>0) rd<=rd-1;
            if(ra_active && !rvalid && rd==0 && lfsr[11:9]!=0) begin
                for(lane=0;lane<16;lane=lane+1)
                    rdata[lane*8+:8]<=memory[memory_index(ra+ri*16+lane)] ^ ((inject_data_error && ri==0 && lane==0) ? 8'h01 : 8'h00);
                rvalid<=1;rid<=aid;rlast<=ri==rn;
                rresp<=(inject_r_error && ri==1) ? 2 : 0;
            end
            if(rvalid && rready) begin
                rvalid<=0;r_count<=r_count+1;ri<=ri+1;rd<=lfsr[1:0];
                if(rlast) ra_active<=0;
            end
        end
    end
endmodule
