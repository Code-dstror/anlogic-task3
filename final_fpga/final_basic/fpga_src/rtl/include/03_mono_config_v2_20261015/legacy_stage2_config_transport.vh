// Preset-only private FULL codec. Full validation must precede compression.
`ifndef PCIE_CFG_EXT_OFFSET_ENABLE
`include "pcie_protocol_v1.vh"
`endif
// Preserve the complete legal HDR policy (45 numeric/qualification bits and
// 128 timer bits) alongside the existing FULL preset. No HDR bit is inferred
// from source selection or discarded during a CFG crossing.
localparam integer STAGE2_EXTENSION_BITS=208;
localparam integer STAGE2_TUPLE_BITS=368;
function [207:0] stage2_pack_extension;
    input [1023:0] extension;
    reg dehaze,lane,hdr;
    begin
        dehaze=extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_DEHAZE];
        lane=extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_F22] ||
             extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_F23];
        hdr=extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_HDR];
        stage2_pack_extension={hdr ? extension[255:128] : 128'd0,
            hdr ? extension[108:64] : 45'd0,hdr,
            dehaze ? extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_LUT_GENERATION+:32] : 32'd0,lane,dehaze};
    end
endfunction
function [1023:0] stage2_unpack_extension;
    input [207:0] packed_extension;
    begin
        stage2_unpack_extension=1024'd0;
        if(packed_extension[1:0]!=0||packed_extension[34])stage2_unpack_extension[7:0]=1;
        if(packed_extension[34])begin
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_HDR]=1;
            stage2_unpack_extension[108:64]=packed_extension[79:35];
            stage2_unpack_extension[255:128]=packed_extension[207:80];
        end
        if(packed_extension[0])begin
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_DEHAZE]=1;
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_CONFIG+:67]=
                {1'b1,8'd192,9'd128,8'd8,9'd16,8'd32,8'd16,8'd200,8'd24};
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_LUT_GENERATION+:32]=packed_extension[33:2];
        end
        if(packed_extension[1])begin
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_ENABLE+4+:2]=3;
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_PP_ENABLE+:3]=3;
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_STRIP_COUNT+:4]=4;
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_THRESHOLD+:11]=40;
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_GX_MIN+:11]=1;
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_RATIO_SHIFT+:2]=3;
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_MIN_COUNT+:20]=1;
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_MIN_PAIRED_STRIPS+:4]=1;
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_STRIP_Y_BEGIN+:52]={13'd202,13'd135,13'd67,13'd0};
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_STRIP_Y_END+:52]={13'd270,13'd202,13'd135,13'd67};
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_ROI_SPLIT+:52]={4{13'd240}};
            stage2_unpack_extension[`PCIE_CFG_EXT_OFFSET_ROI_RIGHT+:52]={4{13'd480}};
        end
    end
endfunction
function stage2_preset_valid;
    input [1023:0] extension;
    begin
        stage2_preset_valid=extension==stage2_unpack_extension(stage2_pack_extension(extension));
    end
endfunction
function [367:0] stage2_pack_tuple;
    input [1183:0] tuple;
    begin stage2_pack_tuple={stage2_pack_extension(tuple[1183:160]),tuple[159:0]};end
endfunction
function [1183:0] stage2_unpack_tuple;
    input [367:0] packed_tuple;
    begin stage2_unpack_tuple={stage2_unpack_extension(packed_tuple[367:160]),packed_tuple[159:0]};end
endfunction
