// Preserve raw schema1/schema2 identities. Algorithm views are wiring only;
// never return a translated view as the1184-bit application ACK.
`include "mono_config_transport_v2.vh"
function [1023:0] analysis_algorithm_extension;
    input [1023:0] extension;
    begin
        if(extension[7:0]==`PCIE_CFG_V2_SCHEMA)begin
            analysis_algorithm_extension=mono_algorithm_parameters(extension);
            analysis_algorithm_extension[7:0]=1;
            analysis_algorithm_extension[15:8]={2'd0,extension[15],extension[14],extension[11],
                extension[9:8]==`PCIE_CFG_V2_MODES_MONO_HDR,2'd0};
        end else analysis_algorithm_extension=extension;
    end
endfunction
function analysis_hdr_enabled;
    input [1023:0] extension;
    begin analysis_hdr_enabled=extension[7:0]==`PCIE_CFG_V2_SCHEMA ?
        extension[9:8]==`PCIE_CFG_V2_MODES_MONO_HDR :
        extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_HDR];end
endfunction
function analysis_dehaze_enabled;
    input [1023:0] extension;
    begin analysis_dehaze_enabled=extension[7:0]==`PCIE_CFG_V2_SCHEMA ? extension[11] :
        extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_DEHAZE];end
endfunction
function [31:0] analysis_dehaze_lut_generation;
    input [1023:0] extension;
    begin analysis_dehaze_lut_generation=extension[7:0]==`PCIE_CFG_V2_SCHEMA && extension[11] ?
        mono_effective_dehaze_lut_generation(extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_LUT_GENERATION+:32]) :
        extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_LUT_GENERATION+:32];end
endfunction
function [1:0] analysis_record_features;
    input [1023:0] extension;
    begin analysis_record_features=extension[7:0]==`PCIE_CFG_V2_SCHEMA ? extension[15:14] :
        extension[`PCIE_CFG_EXT_OFFSET_ENABLE+4+:2];end
endfunction
