# Public interface declarations

Production implementations must remain opaque to the black-box test author.

```verilog
module stereo_raw_reader #(
    parameter integer WIDTH=1920,HEIGHT=1080,
    parameter integer EXTERNAL_DECODER=0,
    parameter [3:0] AXI_ID=4'd1,
    parameter integer VERIFY_DECODE_ACTIVE=0
)(
    input wire clk,rst_n,
    input wire i_start_valid,output wire o_start_ready,
    input wire [27:0] i_base,input wire [63:0] i_job_id,input wire i_cancel,
    output reg [146:0] m_data,output reg m_valid,input wire m_ready,
    output wire o_done_valid,o_done_ok,input wire i_done_ready,
    output wire o_bus_quiet,output reg o_fault,
    output wire o_decode_start_valid,input wire i_decode_start_ready,
    output wire o_decode_release,o_decode_cancel,o_decode_run,
    output wire [127:0] o_decode_data,output wire [15:0] o_decode_keep,
    output wire o_decode_valid,o_decode_last,input wire i_decode_ready,
    input wire [39:0] i_decode_raw,input wire i_decode_raw_valid,
    output wire o_decode_raw_ready,input wire i_decode_sof,i_decode_eol,
    input wire i_decode_done,i_decode_aborted,i_decode_quiet,i_decode_active,
    output wire [3:0] m_axi_arid,output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,output wire m_axi_arvalid,input wire m_axi_arready,
    input wire [3:0] m_axi_rid,input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,input wire m_axi_rlast,m_axi_rvalid,
    output wire m_axi_rready
);

```

```verilog
module shared_raw10_decode_service #(
    parameter integer WIDTH=1920, HEIGHT=1080
)(
    input wire clk, rst_n,
    input wire hdr_start_valid, output wire hdr_start_ready,
    input wire hdr_release, input wire [1:0] hdr_abort,
    input wire hdr_member, input wire [127:0] hdr_data,
    input wire [15:0] hdr_keep, input wire hdr_valid, hdr_last,
    output wire hdr_ready,
    output wire hdr_raw_member, output wire [39:0] hdr_raw,
    output wire hdr_raw_valid, input wire hdr_raw_ready,
    output wire [1:0] hdr_done, hdr_aborted,
    input wire stereo_start_valid, output wire stereo_start_ready,
    input wire stereo_release, stereo_cancel, stereo_run,
    input wire [127:0] stereo_data, input wire [15:0] stereo_keep,
    input wire stereo_valid, stereo_last, output wire stereo_ready,
    output wire [39:0] stereo_raw, output wire stereo_raw_valid,
    input wire stereo_raw_ready, output wire stereo_sof, stereo_eol,
    output wire stereo_done, stereo_aborted, stereo_quiet, stereo_active,
    output wire quiet
);

```
