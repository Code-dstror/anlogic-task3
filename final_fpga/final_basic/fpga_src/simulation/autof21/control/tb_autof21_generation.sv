`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
module tb_autof21_generation;
    `include "analysis_config_transport.vh"
    reg clk=0,rst_n=0,start=0,valid=0;
    always #5 clk=~clk;
    reg [31:0] word=0;
    wire start_ready,word_ready,result_valid;wire [2:0] result_error;
    mono_config_scan_v2 #(.LEGACY_SUPPORTED(8'h3c),.V2_SUPPORTED_MODES(3'b101),.V2_SUPPORTED_ENABLES(6'h3f)) scan(
        .clk(clk),.rst_n(rst_n),.cancel(1'b0),.start_valid(start),.start_ready(start_ready),.start_mode(32'd0),
        .word_valid(valid),.word_ready(word_ready),.word_data(word),.result_valid(result_valid),.result_ready(1'b1),.result_error(result_error));
    reg [1023:0] extension=0,algorithm;
    wire legacy_legal,legacy_unsupported;
    frame_config_extension_validate #(.SUPPORTED(8'h3c)) legacy(
        .extension(extension),.valid(legacy_legal),.unsupported(legacy_unsupported));
    integer checks=0,n;
    task check(input bit good,input string why);
        begin checks++;if(!good)$fatal(1,"AUTOF21 generation profile=%0d %s",`F21_AUTO_FIXED_LUT_PROFILE,why);end
    endtask
    task qualify(input integer expected);
        begin
            if(extension[7:0]==2)check(mono_v2_error(extension,0,3'b101,6'h3f)==expected,"combinational narrow/DFI validator agrees");
            @(negedge clk);start=1;do @(posedge clk);while(!start_ready);@(negedge clk);start=0;
            for(n=0;n<32;n++)begin word=extension[n*32+:32];valid=1;do @(posedge clk);while(!word_ready);@(negedge clk);end
            valid=0;wait(result_valid);#1;check(result_error==expected,"sequential scanner generation decision");
            @(negedge clk);
        end
    endtask
    initial begin
        #40;rst_n=1;
        extension=0;extension[15:0]=16'h0802;
        qualify(`F21_AUTO_FIXED_LUT_PROFILE?0:`PCIE_CFG_ERROR_INVALID);
        algorithm=analysis_algorithm_extension(extension);
        check(algorithm[383:352]==(`F21_AUTO_FIXED_LUT_PROFILE?1:0),"enabled algorithm generation0 profile interpretation");
        check(mono_unpack_extension(mono_pack_extension(extension))===extension,"generation0 raw compact roundtrip");
        extension[383:352]=1;qualify(0);algorithm=analysis_algorithm_extension(extension);check(algorithm[383:352]==1,"generation1 unchanged");
        extension[383:352]=2;qualify(`F21_AUTO_FIXED_LUT_PROFILE?`PCIE_CFG_ERROR_INVALID:0);
        extension[383:352]=32'hffffffff;qualify(`F21_AUTO_FIXED_LUT_PROFILE?`PCIE_CFG_ERROR_INVALID:0);
        extension=0;extension[7:0]=2;qualify(0);algorithm=analysis_algorithm_extension(extension);
        check(algorithm[383:352]==0&&analysis_dehaze_lut_generation(extension)==0,"disabled generation remains canonical0");
        extension[383:352]=1;qualify(`PCIE_CFG_ERROR_INVALID);
        extension=stage2_unpack_extension(208'd5);#1;check(legacy_legal&&!legacy_unsupported,"legacy canonical generation1 remains valid");qualify(0);
        extension[383:352]=0;#1;check(!legacy_legal,"legacy generation0 remains rejected");qualify(`PCIE_CFG_ERROR_UNSUPPORTED);
        extension[383:352]=2;#1;check(legacy_legal==!`F21_AUTO_FIXED_LUT_PROFILE,"legacy wrong generation profile policy");
        qualify(`F21_AUTO_FIXED_LUT_PROFILE?`PCIE_CFG_ERROR_UNSUPPORTED:0);
        $display("RESULT: PASS AUTOF21 generation profile=%0d checks=%0d old_default_preserved=1",`F21_AUTO_FIXED_LUT_PROFILE,checks);$finish;
    end
    initial begin #100000;$fatal(1,"AUTOF21 generation watchdog");end
endmodule
