// Sparse candidate profile: legacy four-ROI analysis requests are unsupported.
`timescale 1ns/1ps
`default_nettype none
`include "pcie_protocol_v1.vh"
// Full invalid tuples are rejected before the214-bit union. A negative ACK
// returns the original1184 bits, never a lossy packed/reconstructed version.
module mono_config_narrow_gate_v2 #(
    parameter integer WIDTH=1920,HEIGHT=1080,LANE_GAUSSIAN_ONLY=1,
    parameter integer TRUSTED_INPUT=0,
    parameter [7:0] LEGACY_SUPPORTED=0,
    parameter [2:0] V2_SUPPORTED_MODES=0,
    parameter [5:0] V2_SUPPORTED_ENABLES=0
)(
    input wire [1183:0] s_frontend_data,
    input wire s_frontend_valid,s_frontend_ok,
    output wire s_frontend_ready,
    output wire [1183:0] m_lease_data,
    output wire m_lease_valid,m_lease_ok,
    input wire m_lease_ready,i_lease_busy,
    input wire [1183:0] s_lease_ack_data,
    input wire s_lease_ack_valid,s_lease_ack_ok,
    output wire s_lease_ack_ready,
    output wire [1183:0] m_ack_data,
    output wire m_ack_valid,m_ack_ok,
    input wire m_ack_ready,
    output wire m_schema2,m_legacy_gaussian,
    output wire [1:0] m_product_mode,
    output wire [5:0] m_processing_enables,
    output wire [1023:0] m_algorithm_parameters
);
    `include "mono_config_transport_v2.vh"
    localparam [7:0] PROFILE_LEGACY_SUPPORTED = LEGACY_SUPPORTED & 8'hcf;
    wire legacy_legal,legacy_unsupported;
    wire [1023:0] extension=s_frontend_data[1183:160];
    wire is_v2=extension[7:0]==`PCIE_CFG_V2_SCHEMA;
    wire representable=s_frontend_data==mono_unpack_tuple(mono_pack_tuple(s_frontend_data));
    wire lane=extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_F22]||
              extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_F23];
    wire legacy_lane_bad=LANE_GAUSSIAN_ONLY!=0&&lane&&
        (s_frontend_data[65:64]!=2'd2||extension[`PCIE_CFG_EXT_OFFSET_PP_ENABLE+:3]!=3);
    // The production frontend returns the immutable BAR-validated or LOCAL
    // BOOT tuple. Standalone callers retain the full negative-ACK boundary.
    wire canonical=TRUSTED_INPUT!=0 || (representable&&(is_v2 ?
        mono_v2_error(extension,{30'd0,s_frontend_data[65:64]},V2_SUPPORTED_MODES,V2_SUPPORTED_ENABLES)==0 :
        legacy_legal&&!legacy_unsupported&&!legacy_lane_bad));
    wire reject=s_frontend_valid&&!canonical&&!i_lease_busy;
    frame_config_extension_validate #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.SUPPORTED(PROFILE_LEGACY_SUPPORTED)) legacy_validator(
        .extension(extension),.valid(legacy_legal),.unsupported(legacy_unsupported));
    assign m_lease_data=s_frontend_data;
    assign m_lease_valid=s_frontend_valid&&canonical;
    assign m_lease_ok=s_frontend_ok;
    assign s_frontend_ready=canonical?m_lease_ready:(!i_lease_busy&&m_ack_ready);
    assign m_ack_data=reject?s_frontend_data:s_lease_ack_data;
    assign m_ack_valid=reject||s_lease_ack_valid;
    assign m_ack_ok=!reject&&s_lease_ack_ok;
    assign s_lease_ack_ready=!reject&&m_ack_ready;
    assign m_schema2=is_v2;
    assign m_legacy_gaussian=!is_v2&&s_frontend_data[65:64]==`PCIE_CFG_MODE_GAUSSIAN;
    assign m_product_mode=is_v2?extension[9:8]:
        (extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_HDR]?2'd2:2'd0);
    assign m_processing_enables=is_v2?extension[15:10]:
        {extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_F23],
         extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_F22],
         s_frontend_data[65:64]==`PCIE_CFG_MODE_HISTOGRAM,1'b0,
         extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_DEHAZE],
         s_frontend_data[65:64]==`PCIE_CFG_MODE_GRAY||m_legacy_gaussian};
    assign m_algorithm_parameters=mono_algorithm_parameters(extension);
endmodule
`default_nettype wire
