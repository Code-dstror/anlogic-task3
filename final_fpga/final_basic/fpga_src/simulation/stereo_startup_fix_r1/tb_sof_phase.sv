`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
// COMPONENT HARNESS, not the complete TOP. Exact TOP qualifier/quiet CDC and
// actual record service + FIFO + owner-only source4. Other drained TOP owners
// are tied quiet; no quiet/ACK/owner internal force. Only raw/event input ports
// are driven. Small geometry is irrelevant because APP admission stays closed.
module tb_sof_phase #(parameter COMBO=0);
    reg pixel_clk=0,user_clk=0,dfi_clk=0,rst=0;
    always #4 pixel_clk=~pixel_clk;
    always #5 user_clk=~user_clk;
    always #7 dfi_clk=~dfi_clk;
    reg raw_valid=0,raw_sof=0,event_valid=0;
    wire source_idle,source_fault,capture_valid,source_valid;
    stereo_capture_source4 #(.WIDTH(8),.HEIGHT(2)) source(
        .clk(pixel_clk),.rst_n(rst),.i_data_reset_n(rst),.i_enable(1'b0),
        .i_session(32'd2),.i_epoch(32'd0),.i_time_ns(64'd100),.i_time_valid(1'b1),
        .i_data(40'd0),.i_valid(raw_valid),.i_accept(1'b1),.i_sof(raw_sof),.i_eol(1'b0),.i_abort(1'b0),
        .i_sequence(32'd1),.i_identity_valid(1'b1),.i_event_valid(event_valid),.o_event_ready(),
        .i_event_kind(2'd0),.i_event_ok(1'b1),.i_event_error(4'd0),.i_event_sequence(32'd1),
        .i_event_identity_valid(1'b1),.i_receive_fault(1'b0),.i_identity_quarantine(1'b0),
        .o_capture_valid(capture_valid),.o_raw_source_valid(source_valid),.i_raw_source_ready(1'b1),
        .o_capture_data(),.o_capture_accept(),.o_capture_sof(),.o_capture_eol(),
        .o_capture_abort(),.o_capture_geometry_done(),.o_capture_session(),
        .o_capture_epoch(),.o_capture_sequence(),.o_capture_metadata(),
        .o_raw_source_session(),.o_raw_source_epoch(),.o_raw_source_sequence(),
        .o_raw_source_camera(),.o_raw_source_ok(),.o_raw_source_error(),
        .o_idle(source_idle),.o_fault(source_fault));
    wire native_identity_event=raw_valid&&raw_sof;
    wire cfg_idle;
    frame_admission_qualification cfg_qualifier(.i_clk(pixel_clk),.i_rst_n(rst),
        .i_available(source_idle),.i_take(!COMBO&&native_identity_event),.i_inhibit(1'b0),.o_available(cfg_idle));
    reg old_meta=0,old_sync=0;
    reg [1:0] record_idle_user=0;
    always @(posedge dfi_clk or negedge rst)
        if(!rst)begin old_meta<=0;old_sync<=0;end
        else begin old_meta<=cfg_idle;old_sync<=old_meta;end
    always @(posedge user_clk or negedge rst)
        if(!rst)record_idle_user<=0;
        else record_idle_user<={record_idle_user[0],old_sync};
    reg write_valid=0,read_valid=0;
    reg [11:0] write_offset=0,read_offset=0;
    reg [31:0] write_data=0;
    wire [31:0] read_data;
    wire user_done,dfi_done,user_busy;
    wire [15:0] user_version,dfi_version;
    record_format_service #(.RECORD_V3_ENABLE(1)) service(
        .i_user_clk(user_clk),.i_user_rst_n(rst),.write_valid(write_valid),.write_offset(write_offset),
        .write_data(write_data),.write_strobes(4'hf),.write_response(),.read_valid(read_valid),.read_offset(read_offset),
        .read_response_valid(),.read_data(read_data),.read_response(),.i_user_source_session(32'd2),
        .i_user_source_session_ready(1'b1),.i_app_enable(1'b0),.i_c2h_running(1'b0),.i_tx_busy(1'b0),
        .i_source_functional_quiescent(record_idle_user[1]),.i_session_armed(1'b0),.i_rearm_ready(1'b1),
        .o_user_busy(user_busy),.o_user_selected_version(user_version),.o_user_selected_header_length(),
        .o_user_selection_epoch(),.o_user_reset_done(user_done),.o_stale_ack_count(),
        .i_dfi_clk(dfi_clk),.i_dfi_rst_n(rst),.i_dfi_source_session(32'd2),.i_dfi_quiescent(old_sync),
        .o_dfi_selected_version(dfi_version),.o_dfi_selection_epoch(),.o_dfi_reset_done(dfi_done));
    integer checks=0,takes=0,raw_ack_error=-1;
    integer user_reject=0,dfi_reject=0,ack_reject=0,ok=0;
    integer phase,status,error,guard;
    task check(input bit condition,input string why);
        begin checks++;if(!condition)$fatal(1,"SOF_PHASE %s phase=%0d",why,phase);end
    endtask
    task wr(input [11:0] offset,input [31:0] value);
        begin @(negedge user_clk);write_valid=1;write_offset=offset;write_data=value;
            @(negedge user_clk);write_valid=0;end
    endtask
    task rd(input [11:0] offset,output [31:0] value);
        begin @(negedge user_clk);read_valid=1;read_offset=offset;
            @(posedge user_clk);#1;value=read_data;@(negedge user_clk);read_valid=0;end
    endtask
    always @(posedge pixel_clk)if(rst)begin
        check(source_idle&&!source_fault&&!capture_valid&&!source_valid,"closed APP unowned source remains idle");
    end
    always @(posedge dfi_clk)if(service.command_sink_valid&&service.command_sink_ready)takes++;
    always @(posedge user_clk)if(service.ack_sink_valid&&service.ack_sink_ready)raw_ack_error=service.ack_sink_data[66:64];
    initial begin
        for(phase=-20;phase<=210;phase++)begin
            rst=0;raw_valid=0;raw_sof=0;event_valid=0;#100;rst=1;
            wait(user_done&&dfi_done&&record_idle_user[1]);repeat(10)@(negedge user_clk);
            // Actual FS input, consumed while i_enable=0; no owner is admitted.
            @(negedge pixel_clk);event_valid=1;@(negedge pixel_clk);event_valid=0;
            wr(`PCIE_REG_RECORD_REQUEST_VERSION,4);wr(`PCIE_REG_RECORD_REQUEST_SEQUENCE,phase+21);
            wr(`PCIE_REG_RECORD_REQUEST_SESSION,2);
            takes=0;raw_ack_error=-1;
            fork
                begin #100;wr(`PCIE_REG_RECORD_COMMAND,1);end
                begin
                    #(100+phase*4);@(negedge pixel_clk);raw_valid=1;raw_sof=1;
                    @(negedge pixel_clk);raw_valid=0;raw_sof=0;
                end
            join
            guard=0;do begin rd(`PCIE_REG_RECORD_STATUS,status);guard++;end while(!status[1]&&guard<1000);
            rd(`PCIE_REG_RECORD_ERROR,error);
            check(guard<1000,"terminal response bounded");check(error==0||error==2,"only expected OK/BUSY");
            if(error==0)ok++;
            else if(takes==0)begin user_reject++;$display("SOF_PHASE BUSY USER phase_ns=%0d",phase*4);end
            else if(raw_ack_error==2)begin dfi_reject++;$display("SOF_PHASE BUSY DFI phase_ns=%0d",phase*4);end
            else begin check(raw_ack_error==0,"ACK recheck receives positive DFI ACK");ack_reject++;$display("SOF_PHASE BUSY ACK_RECHECK phase_ns=%0d dfi_version=%0d user_version=%0d",phase*4,dfi_version,user_version);end
        end
        if(COMBO)check(user_reject==0&&dfi_reject==0&&ack_reject==0&&ok==231,"combo preserves all real owner terms and removes only unowned take");
        else check(user_reject>0&&dfi_reject>0&&ack_reject>0,"unowned SOF can hit all three service BUSY points");
        $display("RESULT: PASS SOF_PHASE combo=%0d total=231 ok=%0d user_busy=%0d dfi_busy=%0d ack_busy=%0d checks=%0d",COMBO,ok,user_reject,dfi_reject,ack_reject,checks);$finish;
    end
    initial begin #2000000;$fatal(1,"SOF phase watchdog");end
endmodule
