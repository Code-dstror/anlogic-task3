`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"

// Real digital application owner for fixed physical-mono preset configurations.
// The fanout holds an invalid full head through its negative ACK; legal heads
// have an exact compact representation. The trusted same-clock pair owner
// lends its frozen head; other callers keep independent pending storage.
module frame_config_preset_owner #(
    parameter integer TRUSTED_INPUT=0
) (
    input wire i_clk,i_rst_n,
    input wire [1183:0] s_config_data,
    input wire s_config_valid,
    output wire s_config_ready,
    output wire [1183:0] m_applied_data,
    output reg m_applied_valid,m_applied_ok,
    input wire m_applied_ready,
    input wire i_config_reset_done,i_source_idle,i_apply_quiescent,
    output wire [1183:0] o_active_config,
    output reg o_initialized,o_config_fault,
    output wire o_plan_busy
);
    `include "analysis_config_transport.vh"
    wire [MONO_TUPLE_BITS-1:0] pending_storage;
    reg [MONO_TUPLE_BITS-1:0] active_storage;
    reg pending,pending_legal;
    wire [1183:0] frozen_plan=mono_unpack_tuple(pending_storage);
    wire [1183:0] active_plan=mono_unpack_tuple(active_storage);
    wire [1183:0] canonical_boot={32'd0,6'd0,16'd0,25'd0,7'd1,1'b0,7'd75,2'd0,s_config_data[63:32],32'd0};
    wire [STAGE2_EXTENSION_BITS-1:0] input_preset=stage2_pack_extension(s_config_data[1183:160]);
    wire schema2=s_config_data[167:160]==`PCIE_CFG_V2_SCHEMA;
    wire hdr_fields_legal=!input_preset[34] ||
        (s_config_data[160+`PCIE_CFG_EXT_OFFSET_HDR_RATIO+:3]==4 &&
         s_config_data[160+`PCIE_CFG_EXT_OFFSET_HDR_BLACK_LONG+:10]==50 &&
         s_config_data[160+`PCIE_CFG_EXT_OFFSET_HDR_BLACK_SHORT+:10]==50 &&
         s_config_data[160+`PCIE_CFG_EXT_OFFSET_HDR_QUALIFICATION+:4]==`PCIE_CFG_EXT_HDR_QUALIFICATION_REQUIRED);
    wire legacy_extension_legal=stage2_preset_valid(s_config_data[1183:160])&&hdr_fields_legal&&
        (!input_preset[0]||input_preset[33:2]!=0)&&
        (!input_preset[1]||s_config_data[65:64]==2);
    wire extension_legal=schema2 ?
        mono_v2_error(s_config_data[1183:160],{30'd0,s_config_data[65:64]},((3'b001 << `PCIE_CFG_V2_MODES_MONO_SDR) | (3'b001 << `PCIE_CFG_V2_MODES_MONO_HDR)),6'h3d)==0 : legacy_extension_legal;
    wire fields_legal=extension_legal&&
        s_config_data[63:32]!=0&&s_config_data[72:66]>=1&&s_config_data[72:66]<=100&&
        s_config_data[80:74]>=1&&s_config_data[80:74]<=s_config_data[72:66]&&
        s_config_data[105:81]<=25'd16777216&&s_config_data[127:122]==0&&
        (!s_config_data[73]||s_config_data[105:81]!=0);
    wire identity_legal=!o_initialized?s_config_data==canonical_boot:
        s_config_data[31:0]!=0&&s_config_data[63:32]==active_storage[63:32]&&
        s_config_data[159:128]==active_storage[159:128]+32'd1;
    // physical_pair_config_owner cannot overwrite held_tuple until the final
    // application ACK handshake. Borrow it through the pending and ACK stalls.
    generate if(TRUSTED_INPUT!=0)begin:g_borrowed_pending
        assign pending_storage=mono_pack_tuple(s_config_data);
    end else begin:g_owned_pending
        reg [MONO_TUPLE_BITS-1:0] storage;
        assign pending_storage=storage;
        always @(posedge i_clk or negedge i_rst_n)begin
            if(!i_rst_n)storage<=0;
            else if(s_config_valid&&s_config_ready)storage<=mono_pack_tuple(s_config_data);
        end
    end endgenerate
    assign s_config_ready=i_rst_n&&i_config_reset_done&&!o_config_fault&&!pending&&!m_applied_valid;
    assign m_applied_data=pending_legal?frozen_plan:s_config_data;
    assign o_active_config=active_plan;
    assign o_plan_busy=pending||m_applied_valid;
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            active_storage<=0;pending<=0;pending_legal<=0;
            m_applied_valid<=0;m_applied_ok<=0;o_initialized<=0;o_config_fault<=0;
        end else begin
            if(m_applied_valid&&m_applied_ready)begin m_applied_valid<=0;pending<=0;end
            if(s_config_valid&&s_config_ready)begin
                pending_legal<=(TRUSTED_INPUT!=0||fields_legal)&&identity_legal;pending<=1;
            end
            if(pending&&!m_applied_valid)begin
                if(!pending_legal||(TRUSTED_INPUT==0&&s_config_data!=frozen_plan))begin
                    m_applied_valid<=1;m_applied_ok<=0;o_config_fault<=1;
                end else if(i_config_reset_done&&i_source_idle&&i_apply_quiescent)begin
                    active_storage<=pending_storage;o_initialized<=1;
                    m_applied_valid<=1;m_applied_ok<=1;
                end
            end
        end
    end
endmodule
