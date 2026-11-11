`timescale 1ns/1ps
// The camera register bank emits a single-beat Cpl or CplD. Its reply register is stable
// until CC is accepted. Borrow it through the actual client1 EOT handshake.
module camera_pcie_bar_tx (
    input wire core_clk, core_rst_n,
    input wire [9:0] i_read_lookup, i_read_tag,
    input wire i_read_pending,
    output wire o_reply_done,
    input wire [127:0] s_axis_cc_tdata,
    input wire s_axis_cc_tvalid,
    output wire s_axis_cc_tready,
    input wire xadm_client1_halt,
    output wire [127:0] client1_tlp_data,
    output wire [63:0] client1_tlp_addr,
    output wire [15:0] client1_remote_req_id,
    output wire [11:0] client1_cpl_byte_cnt,
    output wire [2:0] client1_tlp_tc, client1_tlp_attr, client1_cpl_status,
    output wire client1_tlp_dv, client1_tlp_eot, client1_tlp_hv,
    output wire [1:0] client1_tlp_fmt,
    output wire [12:0] client1_tlp_byte_len,
    output wire [9:0] client1_tlp_tid, client1_cpl_lookup_id
);
    wire with_data=s_axis_cc_tdata[42:32]!=0;
    assign client1_tlp_hv=core_rst_n && i_read_pending && s_axis_cc_tvalid;
    assign client1_tlp_dv=client1_tlp_hv && with_data;
    assign client1_tlp_eot=client1_tlp_hv;
    assign client1_tlp_fmt={with_data,1'b0};
    assign client1_tlp_byte_len=with_data ? 13'd4 : 13'd0;
    assign client1_tlp_data={96'd0,s_axis_cc_tdata[127:96]};
    assign client1_tlp_addr={57'd0,s_axis_cc_tdata[6:0]};
    assign client1_tlp_tid=i_read_tag;
    assign client1_cpl_lookup_id=i_read_lookup;
    assign client1_remote_req_id=s_axis_cc_tdata[63:48];
    assign client1_cpl_byte_cnt=s_axis_cc_tdata[27:16];
    assign client1_tlp_tc=s_axis_cc_tdata[91:89];
    assign client1_tlp_attr=s_axis_cc_tdata[94:92];
    assign client1_cpl_status=s_axis_cc_tdata[45:43];
    // Drain a stale local response after a core-only reset without sending it.
    assign s_axis_cc_tready=core_rst_n && (!i_read_pending || !xadm_client1_halt);
    assign o_reply_done=client1_tlp_hv && !xadm_client1_halt;
endmodule
