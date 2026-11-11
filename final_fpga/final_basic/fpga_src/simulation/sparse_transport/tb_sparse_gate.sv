`timescale 1ns/1ps
module tb_sparse_gate #(parameter integer BITS=16384, parameter [15:0] VERSION=4);
    localparam integer INPUT_FLITS=BITS/128, OUTPUT_FLITS=VERSION==2 ? 8 : (VERSION==3 ? 24 : 128);
    reg clk=0,rst_n=0;always #5 clk=~clk;
    reg [16383:0] fixtures[0:5],expected[0:5];
    integer checks=0,k,limit,beats=0,cycles=0;
    reg start_valid=0,ring_ready=0,ext_valid=0,proof_valid=0;
    wire start_ready,ring_valid,reserved,ext_ready,proof_ready;
    reg stage_begin=0,stage_valid=0,stage_last=0;reg [127:0] stage_data=0;
    wire stage_ready,stage_complete,stage_good,read_enable;wire [8:0] read_index;wire [39:0] read_data;
    reg ready_valid=0,header_fire=0,header_release=0,stream_ready=0;
    reg [31:0] ready_generation=23;
    wire header_ready,stream_valid,stream_last,quiet,fault;wire [127:0] stream_data;
    ddr_extension_staging_ram #(.RECORD_EXTENSION_WIDTH(BITS)) staging(
        .i_clk(clk),.i_rst_n(rst_n),.i_begin(stage_begin),.i_session(32'h12345678),.i_epoch(32'd300),
        .i_sequence(32'd103),.i_camera(1'b1),.s_data(stage_data),.s_valid(stage_valid),.s_last(stage_last),
        .s_ready(stage_ready),.o_complete(stage_complete),.o_shape_valid(stage_good),
        .i_read_enable(read_enable),.i_read_index(read_index),.o_read_data(read_data));
    jpeg_record_metadata_gate #(.RECORD_EXTENSION_WIDTH(BITS),.BORROW_PENDING_EXTENSION(1),
        .STAGING_EXTENSION_ENABLE(1),.BORROW_HEADER(1),.STREAM_READ(1)) gate(
        .i_clk(clk),.i_rst_n(rst_n),.s_start_valid(start_valid),.o_start_ready(start_ready),
        .s_start_writer_tag(32'd1103),.s_start_sequence(32'd103),.s_start_session(32'h12345678),
        .s_start_epoch(32'd300),.s_start_camera(1'b1),.i_ring_start_ready(ring_ready),
        .o_ring_start_valid(ring_valid),.o_start_reserved(reserved),
        .s_extension({BITS{1'b0}}),.s_extension_valid(ext_valid),.o_extension_ready(ext_ready),
        .s_extension_shape_valid(stage_good),.o_extension_read_enable(read_enable),.o_extension_read_index(read_index),
        .i_extension_read_data(read_data),.s_write_result_valid(proof_valid),.o_write_result_ready(proof_ready),
        .s_write_result_tag(32'd1103),.s_write_result_sequence(32'd103),.s_write_result_session(32'h12345678),
        .s_write_result_epoch(32'd300),.s_write_result_camera(1'b1),.s_write_result_slot(16'd3),
        .s_write_result_generation(32'd23),.s_write_result_ok(1'b1),.s_write_result_error(8'd0),
        .i_ready_valid(ready_valid),.i_ready_slot(16'd3),.i_ready_generation(ready_generation),
        .i_ready_session(32'h12345678),.i_ready_sequence(32'd103),.i_ready_epoch(32'd300),.i_ready_camera(1'b1),
        .i_selected_version(VERSION),.o_header_ready(header_ready),.o_header_extension(),
        .i_header_fire(header_fire),.i_header_release(header_release),.o_header_stream_data(stream_data),
        .o_header_stream_valid(stream_valid),.o_header_stream_last(stream_last),.i_header_stream_ready(stream_ready),
        .s_mask_req_valid(1'b0),.o_mask_req_ready(),.s_mask_req_slot(16'd0),.s_mask_req_generation(32'd0),
        .s_mask_req_session(32'd0),.s_mask_req_sequence(32'd0),.s_mask_req_epoch(32'd0),.s_mask_req_camera(1'b0),
        .o_mask_rsp_valid(),.o_mask_rsp_ok(),.i_mask_rsp_ready(1'b0),.o_mask_rsp_error(),.o_mask_rsp_slot(),
        .o_mask_rsp_generation(),.o_mask_rsp_session(),.o_mask_rsp_sequence(),.o_mask_rsp_epoch(),
        .o_mask_rsp_camera(),.o_mask_rsp_qualified(),.o_mask_rsp_pixels(),.o_mask_rsp_source_type(),
        .o_quiescent(quiet),.o_fault(fault),.o_stale_write_count(),.o_bad_extension_count());
    task check(input bit condition,input string why);
        begin checks++;if(!condition)$fatal(1,"SPARSE gate %s time=%0t",why,$time);end
    endtask
    task admission;
        begin
            start_valid=1;ring_ready=0;
            repeat(5)begin @(negedge clk);check(!ring_valid && !start_ready,"no reservation without real ring readiness");end
            ring_ready=1;limit=0;
            while(!start_ready)begin @(negedge clk);limit++;check(limit<10,"bounded actual START reservation");end
            @(posedge clk);@(negedge clk);start_valid=0;
        end
    endtask
    task stage;
        begin
            stage_begin=1;@(posedge clk);@(negedge clk);stage_begin=0;
            for(k=0;k<INPUT_FLITS;k++)begin
                stage_valid=1;stage_data=fixtures[3][k*128+:128];stage_last=k==INPUT_FLITS-1;
                do @(posedge clk);while(!stage_ready);
                @(negedge clk);stage_valid=0;
            end
            stage_last=0;while(!stage_complete)@(negedge clk);check(stage_good,"staged record shape");
        end
    endtask
    task publish;
        begin
            ext_valid=1;do @(posedge clk);while(!ext_ready);@(negedge clk);ext_valid=0;
            proof_valid=1;do @(posedge clk);while(!proof_ready);@(negedge clk);proof_valid=0;
            limit=0;while(!quiet)begin @(negedge clk);limit++;check(limit<450,"bounded metadata publication");end
        end
    endtask
    initial begin
        if(BITS==3072)begin
            $readmemh("source3.hex",fixtures);$readmemh("expected3.hex",expected);
        end else begin
            $readmemh("source.hex",fixtures);$readmemh("expected.hex",expected);
        end
        repeat(12)@(negedge clk);rst_n=1;repeat(12)@(negedge clk);
        admission;stage;publish;
        ready_valid=1;ready_generation=22;
        repeat(450)begin @(negedge clk);check(!header_ready && !stream_valid,"wrong generation cannot publish header");end
        ready_generation=23;limit=0;
        while(!header_ready)begin @(negedge clk);limit++;check(limit<460,"metadata query closes");end
        header_fire=1;@(posedge clk);@(negedge clk);header_fire=0;
        // Real final-header release owns lifetime even after all stream flits enter a buffer.
        while(beats<OUTPUT_FLITS)begin
            stream_ready=cycles%5!=0;cycles++;
            @(posedge clk);
            if(stream_valid && stream_ready)begin
                check(stream_data===expected[3][beats*128+:128],"borrowed extension exact");
                check(stream_last==(beats==OUTPUT_FLITS-1),"extension final flit");beats++;
            end
            @(negedge clk);check(!start_ready,"stream borrow fences next START");
        end
        stream_ready=0;start_valid=1;
        repeat(12)begin @(negedge clk);check(!ring_valid && !start_ready,"last input admission is not header output release");end
        start_valid=0;header_release=1;ready_valid=0;@(posedge clk);@(negedge clk);header_release=0;
        limit=0;while(!quiet)begin @(negedge clk);limit++;check(limit<10,"header release drains outstanding RAM return");end
        // Reset while a 410-word copy is underway: old catalog cannot reappear.
        admission;stage;
        ext_valid=1;do @(posedge clk);while(!ext_ready);@(negedge clk);ext_valid=0;
        proof_valid=1;do @(posedge clk);while(!proof_ready);@(negedge clk);proof_valid=0;
        repeat(INPUT_FLITS<40 ? INPUT_FLITS : 40)@(negedge clk);rst_n=0;repeat(5)@(negedge clk);rst_n=1;
        ready_valid=1;
        repeat(450)begin @(negedge clk);check(!header_ready && !stream_valid,"reset canceled incomplete copy and catalog");end
        ready_valid=0;admission;stage;publish;
        ready_valid=1;limit=0;while(!header_ready)begin @(negedge clk);limit++;check(limit<460,"first good frame after reset recovers");end
        check(!fault,"no sticky gate error after legal reset recovery");
        $display("RESULT: PASS SPARSE_GATE checks=%0d flits=%0d",checks,beats);$finish;
    end
    initial begin #2000000;$fatal(1,"SPARSE gate watchdog");end
endmodule
