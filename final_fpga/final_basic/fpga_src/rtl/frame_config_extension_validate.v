`include "pcie_protocol_v1.vh"
`ifndef F21_AUTO_FIXED_LUT_PROFILE
`define F21_AUTO_FIXED_LUT_PROFILE 0
`endif
// Stateless schema validation. Capability masks describe actual production wiring.
module frame_config_extension_validate #(
    parameter integer WIDTH=1920,HEIGHT=1080,STRIPS=4,
    parameter [7:0] SUPPORTED=0,
    parameter [31:0] COMBINATIONS=0,
    parameter [1:0] CAMERA_PRESENT=1
)(
    input wire [1023:0] extension,
    output reg valid,
    output wire unsupported
);
    wire [7:0] enabled=extension[`PCIE_CFG_EXT_OFFSET_ENABLE+:8];
    wire nr=enabled[`PCIE_CFG_EXT_FEATURE_NR];
    wire hdr=enabled[`PCIE_CFG_EXT_FEATURE_HDR];
    wire dehaze=enabled[`PCIE_CFG_EXT_FEATURE_DEHAZE];
    wire pyramid=enabled[`PCIE_CFG_EXT_FEATURE_F22];
    wire candidates=enabled[`PCIE_CFG_EXT_FEATURE_F23];
    wire morphology=enabled[`PCIE_CFG_EXT_FEATURE_F24];
    wire refinement=enabled[`PCIE_CFG_EXT_FEATURE_F25];
    wire [66:0] recovery=extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_CONFIG+:67];
    wire [2:0] pp=extension[`PCIE_CFG_EXT_OFFSET_PP_ENABLE+:3];
    wire camera=extension[`PCIE_CFG_EXT_OFFSET_PP_CAMERA];
    wire [3:0] strips=extension[`PCIE_CFG_EXT_OFFSET_STRIP_COUNT+:4];
    wire [103:0] y_begin=extension[`PCIE_CFG_EXT_OFFSET_STRIP_Y_BEGIN+:104];
    wire [103:0] y_end=extension[`PCIE_CFG_EXT_OFFSET_STRIP_Y_END+:104];
    wire [103:0] left=extension[`PCIE_CFG_EXT_OFFSET_ROI_LEFT+:104];
    wire [103:0] split=extension[`PCIE_CFG_EXT_OFFSET_ROI_SPLIT+:104];
    wire [103:0] right=extension[`PCIE_CFG_EXT_OFFSET_ROI_RIGHT+:104];
    assign unsupported=(enabled&~SUPPORTED)!=0 ||
        (nr&&hdr&&!COMBINATIONS[`PCIE_CFG_EXT_COMBINATION_HDR_THEN_NR]);
    function [31:0] allowed_word;
        input integer index;
        begin
            case(index)
            0:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_00;
            1:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_01;
            2:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_02;
            3:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_03;
            4:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_04;
            5:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_05;
            6:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_06;
            7:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_07;
            8:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_08;
            9:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_09;
            10:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_10;
            11:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_11;
            12:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_12;
            13:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_13;
            14:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_14;
            15:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_15;
            16:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_16;
            17:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_17;
            18:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_18;
            19:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_19;
            20:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_20;
            21:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_21;
            22:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_22;
            23:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_23;
            24:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_24;
            25:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_25;
            26:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_26;
            27:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_27;
            28:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_28;
            29:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_29;
            30:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_30;
            31:allowed_word=`PCIE_CFG_EXT_ALLOWED_WORD_31;
                default:allowed_word=0;
            endcase
        end
    endfunction
    integer word_index,strip_index;
    always @* begin
        valid=1;
        if(extension!=0) begin
            if(extension[`PCIE_CFG_EXT_OFFSET_SCHEMA+:8]!=1||unsupported) valid=0;
            for(word_index=0;word_index<32;word_index=word_index+1)
                if((extension[word_index*32+:32]&~allowed_word(word_index))!=0) valid=0;
            if(nr) begin
                if(WIDTH<6||WIDTH>1920||HEIGHT<6||HEIGHT>1080||WIDTH%6!=0||HEIGHT%6!=0) valid=0;
            end else if(extension[63:32]!=0||extension[`PCIE_CFG_EXT_OFFSET_NR_HISTORY_RESET]) valid=0;
            if(hdr) begin
                if(WIDTH<8||WIDTH%4!=0||HEIGHT<3||
                    extension[`PCIE_CFG_EXT_OFFSET_HDR_RATIO+:3]<1||
                    extension[`PCIE_CFG_EXT_OFFSET_HDR_RATIO+:3]>4||
                    extension[`PCIE_CFG_EXT_OFFSET_HDR_QUALIFICATION+:4]!=`PCIE_CFG_EXT_HDR_QUALIFICATION_REQUIRED)
                    valid=0;
            end else if(extension[108:64]!=0||extension[255:128]!=0) valid=0;
            if(dehaze) begin
                if(WIDTH<6||WIDTH>1920||HEIGHT<6||HEIGHT>1080||WIDTH%6!=0||HEIGHT%6!=0||
                    !recovery[66]||recovery[57:49]<128||recovery[57:49]>256||
                    recovery[48:41]>32||recovery[40:32]>64||recovery[31:24]>128||
                    recovery[23:16]>128||recovery[15:8]<128||recovery[7:0]>64||
                    (`F21_AUTO_FIXED_LUT_PROFILE ?
                     extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_LUT_GENERATION+:32]!=1 :
                     extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_LUT_GENERATION+:32]==0)) valid=0;
            end else if(recovery!=0||extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_LUT_GENERATION+:32]!=0) valid=0;
            if((candidates||morphology||refinement)&&!pyramid) valid=0;
            if(pyramid) begin
                if(!pp[1]||WIDTH<4||WIDTH>3840||WIDTH%4!=0||HEIGHT<1||HEIGHT>2160||
                    extension[`PCIE_CFG_EXT_OFFSET_THRESHOLD+:11]>2040||
                    STRIPS<1||STRIPS>8||strips!=STRIPS||!CAMERA_PRESENT[camera]) valid=0;
                if(candidates) begin
                    if(extension[`PCIE_CFG_EXT_OFFSET_GX_MIN+:11]>1020||
                        extension[`PCIE_CFG_EXT_OFFSET_DIRECTION_SIGN+:2]==3||
                        extension[`PCIE_CFG_EXT_OFFSET_MIN_COUNT+:20]==0||
                        extension[`PCIE_CFG_EXT_OFFSET_MIN_PAIRED_STRIPS+:4]==0||
                        extension[`PCIE_CFG_EXT_OFFSET_MIN_PAIRED_STRIPS+:4]>STRIPS) valid=0;
                end else if(extension[449:411]!=0||y_begin!=0||y_end!=0||left!=0||split!=0||right!=0) valid=0;
                for(strip_index=0;strip_index<8;strip_index=strip_index+1) begin
                    if(strip_index<STRIPS&&candidates) begin
                        if(y_begin[strip_index*13+:13]>=y_end[strip_index*13+:13]||
                            y_end[strip_index*13+:13]>(HEIGHT+3)/4||
                            left[strip_index*13+:13]>=split[strip_index*13+:13]||
                            split[strip_index*13+:13]>=right[strip_index*13+:13]||
                            right[strip_index*13+:13]>(WIDTH+3)/4) valid=0;
                        if(strip_index>0)
                            if(y_begin[strip_index*13+:13]!=y_end[(strip_index-1)*13+:13]||
                                left[strip_index*13+:13]>left[(strip_index-1)*13+:13]||
                                right[strip_index*13+:13]<right[(strip_index-1)*13+:13]) valid=0;
                    end else if(y_begin[strip_index*13+:13]!=0||y_end[strip_index*13+:13]!=0||
                        left[strip_index*13+:13]!=0||split[strip_index*13+:13]!=0||right[strip_index*13+:13]!=0) valid=0;
                end
                if(morphology) begin
                    if(extension[`PCIE_CFG_EXT_OFFSET_MORPH_MODE+:3]>4) valid=0;
                end else if(extension[`PCIE_CFG_EXT_OFFSET_MORPH_MODE+:3]!=0) valid=0;
                if(refinement) begin
                    if(extension[`PCIE_CFG_EXT_OFFSET_MIN_CURVATURE+:13]==0||
                        extension[`PCIE_CFG_EXT_OFFSET_MIN_CURVATURE+:13]>4080) valid=0;
                end else if(extension[`PCIE_CFG_EXT_OFFSET_MIN_CURVATURE+:13]!=0) valid=0;
            end else if(extension[999:384]!=0) valid=0;
        end
    end
endmodule
