`timescale 1ns / 1ps
// Adapted from the repository's tb_jpeg_frame_ring control and independent
// AXI memory fixture. The source and all test inputs are local to this project.
module tb_jpeg_tail_retire;
    reg  i_clk=0;
    reg  i_rst_n=0;
    reg  i_ddr_ready=0;
    reg  i_start_valid=0;
    wire  o_start_ready;
    reg [31:0] i_capture_id=0;
    reg [15:0] i_width=0;
    reg [15:0] i_height=0;
    reg [63:0] i_timestamp_ns=0;
    reg [127:0] i_jpeg_tdata=0;
    reg [15:0] i_jpeg_tkeep=0;
    reg  i_jpeg_tvalid=0;
    wire  o_jpeg_tready;
    reg  i_jpeg_tlast=0;
    reg  i_result_valid=0;
    wire  o_result_ready;
    reg [31:0] i_result_id=0;
    reg  i_result_ok=0;
    reg [24:0] i_result_length=0;
    wire  o_ready_valid;
    reg  i_ready_claim=0;
    wire [31:0] o_capture_id;
    wire [24:0] o_payload_length;
    wire [15:0] o_width;
    wire [15:0] o_height;
    wire [63:0] o_timestamp_ns;
    wire [127:0] o_payload_tdata;
    wire [15:0] o_payload_tkeep;
    wire  o_payload_tvalid;
    reg  i_payload_tready=0;
    wire  o_payload_tlast;
    wire  o_drop_pulse;
    wire  o_read_done_pulse;
    wire [7:0] o_error_code;
    wire  o_stream_recovery_required;
    wire [3:0] o_state;
    wire [15:0] o_wr_burst_count;
    wire [15:0] o_rd_burst_count;
    wire [15:0] o_berr_count;
    wire [15:0] o_rerr_count;
    wire [15:0] o_drop_count;
    wire [27:0] o_last_error_addr;
    wire [3:0] o_axi_awid;
    wire [27:0] o_axi_awaddr;
    wire [7:0] o_axi_awlen;
    wire [2:0] o_axi_awsize;
    wire [1:0] o_axi_awburst;
    wire  o_axi_awvalid;
    wire  i_axi_awready;
    wire [127:0] o_axi_wdata;
    wire [15:0] o_axi_wstrb;
    wire  o_axi_wlast;
    wire  o_axi_wvalid;
    wire  i_axi_wready;
    wire [3:0] i_axi_bid;
    wire [1:0] i_axi_bresp;
    wire  i_axi_bvalid;
    wire  o_axi_bready;
    wire [3:0] o_axi_arid;
    wire [27:0] o_axi_araddr;
    wire [7:0] o_axi_arlen;
    wire [2:0] o_axi_arsize;
    wire [1:0] o_axi_arburst;
    wire  o_axi_arvalid;
    wire  i_axi_arready;
    wire [3:0] i_axi_rid;
    wire [127:0] i_axi_rdata;
    wire [1:0] i_axi_rresp;
    wire  i_axi_rlast;
    wire  i_axi_rvalid;
    wire  o_axi_rready;
    reg [31:0] i_session_id=0;
    reg [31:0] i_mode_epoch=0;
    reg  i_camera_id=0;
    reg [7:0] i_quality=0;
    reg [7:0] i_result_quality=0;
    reg [31:0] i_result_epoch=0;
    wire [15:0] o_slot_id;
    wire [31:0] o_generation;
    wire [31:0] o_session_id;
    wire [31:0] o_mode_epoch;
    wire  o_camera_id;
    wire [7:0] o_quality;
    reg  i_retire_valid=0;
    wire  o_retire_ready;
    reg [31:0] i_retire_session=0;
    reg [31:0] i_retire_generation=0;
    reg [15:0] i_retire_slot=0;
    reg  i_retire_error=0;
    wire  o_retire_rsp_valid;
    reg  i_retire_rsp_ready=0;
    wire [3:0] o_retire_rsp_code;
    wire  o_read_complete;
    wire  o_read_error;
    reg  i_req_valid=0;
    wire  o_req_ready;
    reg [1:0] i_req_op=0;
    reg  i_req_camera=0;
    reg [15:0] i_req_slot=0;
    reg [31:0] i_req_generation=0;
    reg [31:0] i_req_session=0;
    wire  o_rsp_valid;
    reg  i_rsp_ready=0;
    wire [3:0] o_rsp_code;
    wire [15:0] o_rsp_slot;
    wire [31:0] o_rsp_generation;
    wire [31:0] o_rsp_session;
    wire [31:0] o_rsp_epoch;
    wire [31:0] o_rsp_capture_id;
    wire  o_rsp_camera;
    wire [7:0] o_rsp_quality;
    wire [15:0] o_rsp_width;
    wire [15:0] o_rsp_height;
    wire [24:0] o_rsp_payload_length;
    wire  o_rsp_pinned;
    wire [2:0] o_rsp_state;
    always #3.75 i_clk=~i_clk;
    reg b_error=0,r_error=0;
    wire [31:0] aw_count,b_count,ar_count,r_count,w_count;
    reg [7:0] oracle [0:8191];
    integer n,j,seen=0,last_stall=0,expected_id=0,expected_length=0;
    reg audit_hold=0,check_read=0,stall_last=0;
    reg [144:0] held_payload; reg held=0;
    reg [15:0] saved_slot; reg [31:0] saved_generation;
    reg [31:0] retire_session=32'h12345678;
    jpeg_frame_ring #(.SLOT_BYTES(512),.SLOT0_BASE(28'hff0),
        .SLOT1_BASE(28'h2000),.SLOT2_BASE(28'h3000),.SLOT3_BASE(28'h4000),
        .SLOT4_BASE(28'h5000),.SLOT5_BASE(28'h6000)) dut (
        .i_write_tag(32'd0),.i_write_result_ready(1'b1),.o_write_result_valid(),
        .o_write_result_ok(),.o_write_result_error(),.o_write_result_capture_id(),
        .o_write_result_session(),.o_write_result_epoch(),.o_write_result_camera(),
        .o_write_result_slot(),.o_write_result_generation(),.o_write_result_payload_length(),
        .o_write_result_tag(),.o_record_quiescent(),.i_start_mask(1'b0),
        .i_mask_allocation_ready(1'b0),.i_start_source_type(3'd0),.o_mask_allocation_valid(),
        .o_mask_allocation_slot(),.o_mask_allocation_generation(),.o_mask_allocation_base(),
        .o_mask_allocation_bytes(),.i_mask_result_valid(1'b0),.o_mask_result_ready(),
        .i_mask_result_context(160'd0),.i_mask_result_tag(32'd0),.i_mask_result_generation(32'd0),
        .i_mask_result_slot(16'd0),.i_mask_result_ok(1'b0),.i_mask_result_error(8'd0),
        .i_mask_result_width(13'd0),.i_mask_result_height(13'd0),.i_mask_result_written_bytes(17'd0),
        .i_mask_result_terminal_body(48'd0),.i_req_mask(1'b0),.i_req_read_lock(1'b0),
        .i_mask_read_lease_release(1'b0),.o_mask_read_lease_active(),.o_rsp_read_authorized(),
        .o_rsp_mask_present(),.o_rsp_mask_pinned(),.o_rsp_mask_tail_base(),
        .o_write_quiescent(), .*
    );
    axi128_stall_memory mem(
        .clk(i_clk),
        .rst_n(i_rst_n),
        .awid(o_axi_awid),
        .awaddr(o_axi_awaddr),
        .awlen(o_axi_awlen),
        .awsize(o_axi_awsize),
        .awburst(o_axi_awburst),
        .awvalid(o_axi_awvalid),
        .awready(i_axi_awready),
        .wdata(o_axi_wdata),
        .wstrb(o_axi_wstrb),
        .wlast(o_axi_wlast),
        .wvalid(o_axi_wvalid),
        .wready(i_axi_wready),
        .bid(i_axi_bid),
        .bresp(i_axi_bresp),
        .bvalid(i_axi_bvalid),
        .bready(o_axi_bready),
        .arid(o_axi_arid),
        .araddr(o_axi_araddr),
        .arlen(o_axi_arlen),
        .arsize(o_axi_arsize),
        .arburst(o_axi_arburst),
        .arvalid(o_axi_arvalid),
        .arready(i_axi_arready),
        .rid(i_axi_rid),
        .rdata(i_axi_rdata),
        .rresp(i_axi_rresp),
        .rlast(i_axi_rlast),
        .rvalid(i_axi_rvalid),
        .rready(o_axi_rready),
        .inject_b_error(b_error),
        .inject_r_error(r_error),
        .inject_data_error(1'b0),
        .aw_count(aw_count),
        .b_count(b_count),
        .ar_count(ar_count),
        .r_count(r_count),
        .w_count(w_count)
    );

    always @(negedge i_clk) begin
        if(!i_rst_n || audit_hold) i_payload_tready=0;
        else if(stall_last && o_payload_tvalid && o_payload_tlast && last_stall<12) begin
            i_payload_tready=0;last_stall=last_stall+1;
        end else i_payload_tready=($random & 7)!=0;
    end
    always @(posedge i_clk) begin
        if(!i_rst_n) held<=0;
        else begin
            if(held && (!o_payload_tvalid || {o_payload_tdata,o_payload_tkeep,o_payload_tlast}!==held_payload)) $fatal(1,"payload stall stability");
            held<=o_payload_tvalid && !i_payload_tready;
            held_payload<={o_payload_tdata,o_payload_tkeep,o_payload_tlast};
            if(check_read && o_payload_tvalid && i_payload_tready) begin
                for(j=0;j<16;j=j+1) if(o_payload_tkeep[j]) begin
                    if(seen>=expected_length || o_payload_tdata[j*8+:8]!==oracle[(expected_id-1)*512+seen]) $fatal(1,"payload byte id=%0d offset=%0d",expected_id,seen);
                    seen=seen+1;
                end
                if(o_payload_tlast && seen!=expected_length) $fatal(1,"tail length");
            end
        end
    end
    task capture;
        input integer id,cam,length,bad;
        integer offset,lane;
        begin
            @(negedge i_clk);i_camera_id=cam;i_capture_id=id;i_start_valid=1;
            i_session_id=32'h12345678;i_mode_epoch=32'h1234;i_quality=10+id;
            i_width=1920;i_height=1080;i_timestamp_ns=id*100;
            @(posedge i_clk);while(!o_start_ready) @(posedge i_clk);
            @(negedge i_clk);i_start_valid=0;
            for(offset=0;offset<length;offset=offset+16) begin
                i_jpeg_tdata=0;
                for(lane=0;lane<16;lane=lane+1) if(offset+lane<length)
                    i_jpeg_tdata[lane*8+:8]=oracle[(id-1)*512+offset+lane];
                i_jpeg_tkeep=(length-offset)>=16 ? 16'hffff : 16'hffff>>(16-(length-offset));
                if(bad==3 && offset==0) i_jpeg_tkeep=16'hfff5;
                i_jpeg_tlast=offset+16>=length;i_jpeg_tvalid=1;
                @(posedge i_clk);while(!o_jpeg_tready) @(posedge i_clk);
                @(negedge i_clk);i_jpeg_tvalid=0;
            end
            i_result_valid=1;i_result_id=id;i_result_ok=bad!=1;
            i_result_length=length;i_result_epoch=bad==2 ? 32'h1235 : 32'h1234;
            i_result_quality=bad==4 ? 11+id : 10+id;
            @(posedge i_clk);while(!o_result_ready) @(posedge i_clk);
            @(negedge i_clk);i_result_valid=0;
            while(o_state!=0) @(negedge i_clk);
            repeat(3) @(negedge i_clk);
        end
    endtask
    task request;
        input integer op,cam,slot;
        input [31:0] gen;
        input integer code;
        reg [217:0] held_response;
        begin
            @(negedge i_clk);i_req_valid=1;i_req_op=op;i_req_camera=cam;
            i_req_slot=slot;i_req_generation=gen;i_req_session=32'h12345678;i_rsp_ready=0;
            @(posedge i_clk);while(!o_req_ready) @(posedge i_clk);
            @(negedge i_clk);i_req_valid=0;
            // Public inputs may change immediately after the accepted tuple.
            i_req_op=3;i_req_camera=!cam;i_req_slot=16'hffff;
            i_req_generation=32'hdeadbeef;i_req_session=32'hdeadbeef;
            while(!o_rsp_valid) @(negedge i_clk);
            if(o_rsp_code!=code) $fatal(1,"request op%0d code got%0d expected%0d",op,o_rsp_code,code);
            held_response={o_rsp_code,o_rsp_slot,o_rsp_generation,o_rsp_session,o_rsp_epoch,
                o_rsp_capture_id,o_rsp_camera,o_rsp_quality,o_rsp_width,o_rsp_height,
                o_rsp_payload_length,o_rsp_pinned,o_rsp_state};
            repeat(3) begin
                @(negedge i_clk);
                if(!o_rsp_valid || {o_rsp_code,o_rsp_slot,o_rsp_generation,o_rsp_session,o_rsp_epoch,
                    o_rsp_capture_id,o_rsp_camera,o_rsp_quality,o_rsp_width,o_rsp_height,
                    o_rsp_payload_length,o_rsp_pinned,o_rsp_state}!==held_response)
                    $fatal(1,"response changed under stall");
            end
            i_rsp_ready=1;@(negedge i_clk);
        end
    endtask
    task read_claim;
        input integer id,length;
        begin
            while(!o_ready_valid) @(negedge i_clk);
            if(o_capture_id!=id || o_payload_length!=length || o_quality!=10+id || o_mode_epoch!=32'h1234 || o_session_id!=32'h12345678) $fatal(1,"READY metadata");
            saved_slot=o_slot_id;saved_generation=o_generation;
            expected_id=id;expected_length=length;seen=0;check_read=1;
            i_ready_claim=1;@(negedge i_clk);i_ready_claim=0;
            while(!o_read_complete) @(negedge i_clk);
            if(!r_error && seen!=length) $fatal(1,"read final length");
            if(o_slot_id!=saved_slot || o_generation!=saved_generation || o_ready_valid) $fatal(1,"SENDING ownership");
            repeat(15) @(negedge i_clk);
            if(!o_read_complete) $fatal(1,"completion not sticky");
            check_read=0;
        end
    endtask
    task retire;
        input integer error,code;
        begin
            i_retire_valid=1;i_retire_slot=saved_slot;i_retire_generation=saved_generation;
            i_retire_session=retire_session;i_retire_error=error;i_retire_rsp_ready=0;
            @(posedge i_clk);while(!o_retire_ready) @(posedge i_clk);
            @(negedge i_clk);i_retire_valid=0;
            while(!o_retire_rsp_valid) @(negedge i_clk);
            if(o_retire_rsp_code!=code) $fatal(1,"retire code %0d expected %0d",o_retire_rsp_code,code);
            i_retire_rsp_ready=1;@(negedge i_clk);
        end
    endtask

    initial begin
        for(n=0;n<16;n=n+1)
            for(j=0;j<512;j=j+1) oracle[n*512+j]=(n+1)*17+j*29+j/7;
        i_ddr_ready=1;i_rsp_ready=1;i_retire_rsp_ready=1;
        repeat(8) @(negedge i_clk);i_rst_n=1;repeat(20) @(negedge i_clk);

        // Fill all three CAM0 slots. An early RETIRE has the exact identity.
        capture(1,0,17,0);capture(2,0,17,0);capture(3,0,17,0);capture(4,1,17,0);
        fork
            read_claim(1,17);
            begin
                wait(o_payload_tvalid && !o_payload_tlast);
                @(posedge i_clk);while(!(o_payload_tvalid&&i_payload_tready))@(posedge i_clk);
                audit_hold=1;wait(o_payload_tvalid&&o_payload_tlast);
                @(negedge i_clk);retire(0,3);
                repeat(32)begin @(negedge i_clk);if(o_read_complete||dut.slot_state[0]!=4||!o_payload_tvalid||!o_payload_tlast)
                    $fatal(1,"tail stall was retired");end
                audit_hold=0;
            end
        join
        request(0,0,0,0,0);if(o_rsp_state!=4)$fatal(1,"SENDING was reusable before exact RETIRE");
        saved_slot=3;retire(0,2);saved_slot=0;
        saved_generation=saved_generation+1;retire(0,2);saved_generation=saved_generation-1;
        retire(0,0);read_claim(2,17);retire(0,0);read_claim(3,17);retire(0,0);
        read_claim(4,17);retire(0,0);
        if(aw_count!=b_count)$fatal(1,"write debt left");
        $display("RESULT: PASS JPEG_EARLY_RETIRE stalled final beat, exact early RETIRE BUSY, wrong-eye/stale-generation rejected");$finish;
    end
    initial begin #2000000;$fatal(1,"watchdog JPEG ring");end
endmodule
