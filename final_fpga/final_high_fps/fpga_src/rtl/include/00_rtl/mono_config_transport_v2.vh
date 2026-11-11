// The DCP profile owns the atmospheric estimator and recovery gains internally.
`ifndef F21_AUTO_FIXED_LUT_PROFILE
`define F21_AUTO_FIXED_LUT_PROFILE 0
`endif
// Private lossless union. Old schema1 remains exactly the original208 bits.
// Schema2: tag1 + mode2 + enables6 + generation32 + HDR policy45 + timers128.
`include "legacy_stage2_config_transport.vh"
`include "quality_control_v1.vh"
localparam integer MONO_EXTENSION_BITS=214;
localparam integer MONO_TUPLE_BITS=374;
// Schema2's legal dehaze generation occupies one bit. Its top bit marks
// quality v1, whose physical policy requires the high delta word to be zero.
// The unmarked branch retains the complete older compact layout.
localparam integer MONO_QUALITY_TAG_BIT=39;
localparam integer MONO_QUALITY_PRESET_LSB=9;
localparam integer MONO_QUALITY_WB_LSB=117;
// Schema2 generation zero selects this image's internal generation one.
// Use only at algorithm consumers; compact/raw CFG identity stays unchanged.
function [31:0] mono_effective_dehaze_lut_generation;
    input [31:0] generation;
    begin mono_effective_dehaze_lut_generation=
        generation==0 ? 32'd1 : generation;end
endfunction
function mono_v2_dehaze_generation_valid;
    input enabled;
    input [31:0] generation;
    begin mono_v2_dehaze_generation_valid=enabled ?
        generation<=1 : generation==0;end
endfunction
function mono_v2_quality_wb_valid;
    input [30:0] word;
    begin
        mono_v2_quality_wb_valid=word[`PCIE_CFG_V2_OFFSET_ISP_WB_ENABLE%32] ?
            word[`PCIE_CFG_V2_OFFSET_ISP_WB_R%32+:10]!=0 &&
            word[`PCIE_CFG_V2_OFFSET_ISP_WB_G%32+:10]!=0 &&
            word[`PCIE_CFG_V2_OFFSET_ISP_WB_B%32+:10]!=0 : word[29:0]==0;
    end
endfunction
function mono_v2_quality_policy_valid;
    input [7:0] word;
    input wb_present,is_hdr;
    begin
        mono_v2_quality_policy_valid=word[`PCIE_CFG_V2_OFFSET_QUALITY_VERSION%32+:4]==0 ?
            !wb_present&&word==0 :
            word[`PCIE_CFG_V2_OFFSET_QUALITY_VERSION%32+:4]==`PCIE_CFG_V2_QUALITY_VERSION_V1 &&
            word[`PCIE_CFG_V2_OFFSET_HDR_FUSION_PRESET%32+:2]<=`PCIE_CFG_V2_QUALITY_FUSION_LEGACY &&
            (is_hdr||word[3:0]==0);
    end
endfunction
function [213:0] mono_pack_extension;
    input [1023:0] extension;
    reg [31:0] generation,delta_high;
    begin
        generation=extension[383:352];
        delta_high=extension[191:160];
        if(extension[`PCIE_CFG_V2_OFFSET_QUALITY_VERSION+:4]==`PCIE_CFG_V2_QUALITY_VERSION_V1)begin
            generation={1'b1,26'd0,extension[`PCIE_CFG_V2_OFFSET_HDR_TONE_PRESET+:4],generation[0]};
            delta_high={1'b0,extension[`PCIE_CFG_V2_OFFSET_ISP_WB_R+:31]};
        end
        if(extension[7:0]==`PCIE_CFG_V2_SCHEMA)
            mono_pack_extension={1'b1,extension[255:192],delta_high,extension[159:128],
                                 extension[108:64],generation,extension[15:10],extension[9:8]};
        else mono_pack_extension={6'd0,stage2_pack_extension(extension)};
    end
endfunction
function [1023:0] mono_unpack_extension;
    input [213:0] packed_extension;
    begin
        if(packed_extension[213])begin
            mono_unpack_extension=0;
            mono_unpack_extension[7:0]=`PCIE_CFG_V2_SCHEMA;
            mono_unpack_extension[9:8]=packed_extension[1:0];
            mono_unpack_extension[15:10]=packed_extension[7:2];
            mono_unpack_extension[383:352]=packed_extension[39:8];
            mono_unpack_extension[108:64]=packed_extension[84:40];
            mono_unpack_extension[255:128]=packed_extension[212:85];
            if(packed_extension[MONO_QUALITY_TAG_BIT])begin
                mono_unpack_extension[383:353]=0;
                mono_unpack_extension[191:160]=0;
                mono_unpack_extension[`PCIE_CFG_V2_OFFSET_ISP_WB_R+:31]=packed_extension[MONO_QUALITY_WB_LSB+:31];
                mono_unpack_extension[`PCIE_CFG_V2_OFFSET_HDR_TONE_PRESET+:4]=packed_extension[MONO_QUALITY_PRESET_LSB+:4];
                mono_unpack_extension[`PCIE_CFG_V2_OFFSET_QUALITY_VERSION+:4]=`PCIE_CFG_V2_QUALITY_VERSION_V1;
            end
        end else mono_unpack_extension=stage2_unpack_extension(packed_extension[207:0]);
    end
endfunction
function [373:0] mono_pack_tuple;
    input [1183:0] tuple;
    begin mono_pack_tuple={mono_pack_extension(tuple[1183:160]),tuple[159:0]};end
endfunction
function [1183:0] mono_unpack_tuple;
    input [373:0] tuple;
    begin mono_unpack_tuple={mono_unpack_extension(tuple[373:160]),tuple[159:0]};end
endfunction
function [2:0] mono_v2_error;
    input [1023:0] extension;
    input [31:0] base_mode;
    input [2:0] supported_modes;
    input [5:0] supported_enables;
    reg [1:0] product_mode;
    reg [5:0] enables;
    reg [1023:0] allowed;
    begin
        product_mode=extension[9:8];enables=extension[15:10];
        allowed=0;allowed[15:0]=16'hffff;allowed[108:64]={45{1'b1}};
        allowed[255:128]={128{1'b1}};allowed[383:352]=32'hffffffff;
        allowed[63:32]=`PCIE_CFG_V2_QUALITY_ALLOWED_WORD_01;
        allowed[415:384]=`PCIE_CFG_V2_QUALITY_ALLOWED_WORD_12;
        if(extension[7:0]!=`PCIE_CFG_V2_SCHEMA || base_mode!=`PCIE_CFG_MODE_COLOR ||
           (extension&~allowed)!=0 || product_mode==`PCIE_CFG_V2_MODES_HDR_LZ_CONFLICT ||
           (enables[5]&&!enables[4]))mono_v2_error=`PCIE_CFG_ERROR_INVALID;
        else if(!((supported_modes>>product_mode)&1'b1) || (enables&~supported_enables)!=0)
            mono_v2_error=`PCIE_CFG_ERROR_UNSUPPORTED;
        else if((product_mode==`PCIE_CFG_V2_MODES_MONO_HDR &&
                 (extension[66:64]<1||extension[66:64]>4||extension[108:105]!=`PCIE_CFG_EXT_HDR_QUALIFICATION_REQUIRED)) ||
                (product_mode!=`PCIE_CFG_V2_MODES_MONO_HDR && (extension[108:64]!=0||extension[255:128]!=0)) ||
                !mono_v2_dehaze_generation_valid(enables[1],extension[383:352]) ||
                !mono_v2_quality_wb_valid(extension[62:32]) ||
                !mono_v2_quality_policy_valid(extension[391:384],extension[62:32]!=0,
                    product_mode==`PCIE_CFG_V2_MODES_MONO_HDR) ||
                (extension[391:388]!=0&&extension[191:160]!=0))
            mono_v2_error=`PCIE_CFG_ERROR_INVALID;
        else mono_v2_error=`PCIE_CFG_ERROR_OK;
    end
endfunction
// Fixed algorithm parameters only. Image/analysis enable decisions MUST use
// schema2's separate six bits, never this legacy preset's PP=3 or lane collapse.
function [1023:0] mono_algorithm_parameters;
    input [1023:0] extension;
    reg [1023:0] fixed;
    begin
        if(extension[7:0]!=`PCIE_CFG_V2_SCHEMA)mono_algorithm_parameters=extension;
        else begin
            fixed=stage2_unpack_extension(208'd3);
            mono_algorithm_parameters=0;
            if(extension[11])begin
                mono_algorithm_parameters[322:256]=fixed[322:256];
                mono_algorithm_parameters[383:352]=mono_effective_dehaze_lut_generation(extension[383:352]);
            end
            if(extension[14])
                mono_algorithm_parameters[`PCIE_CFG_EXT_OFFSET_THRESHOLD+:11]=11'd40;
            if(extension[9:8]==`PCIE_CFG_V2_MODES_MONO_HDR)begin
                mono_algorithm_parameters[108:64]=extension[108:64];
                mono_algorithm_parameters[255:128]=extension[255:128];
            end
        end
    end
endfunction
