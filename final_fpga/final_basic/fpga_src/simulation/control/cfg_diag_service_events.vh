    wire ref_read_response_valid,ref_command_valid,ref_response_ready,ref_initialized;
    wire [31:0] ref_read_data,ref_session_id;
    wire [1:0] ref_write_response,ref_read_response;
    wire [39:0] ref_command_data;
    cfg_diag_e0c4_bar #(.LEGACY_SUPPORTED(8'h0c),.V2_SUPPORTED_MODES(3'b101),.V2_SUPPORTED_ENABLES(6'h3f)) reference_bar(
        .clk(user_clk),.rst_n(rst_n),.stream_ready(dut.command_user_done&&dut.response_user_done),
        .write_valid(write_valid),.write_offset(write_offset),.write_data(write_data),.write_strobes(write_strobes),
        .write_response(ref_write_response),.read_valid(read_valid),.read_offset(read_offset),
        .read_response_valid(ref_read_response_valid),.read_data(ref_read_data),.read_response(ref_read_response),
        .command_data(ref_command_data),.command_valid(ref_command_valid),.command_ready(dut.command_source_ready),
        .response_data(dut.response_sink),.response_valid(dut.response_sink_valid),.response_ready(ref_response_ready),
        .initialized(ref_initialized),.session_id(ref_session_id));
    integer diag_prepares=0,diag_presents=0,diag_copies=0,diag_publications=0,diag_copy_cycles=0,diag_miter_checks=0;
    reg diag_pending_publish=0,diag_old_bank;
    reg [31:0] diag_old_epoch;
    reg diag_event_prepare,diag_event_commit,diag_event_present,diag_event_copy,diag_event_complete,diag_event_publish;
    task diag_compare_bar;
        begin
            check({write_response,read_response,read_response_valid,read_data,dut.command_source,
                dut.command_source_valid,dut.response_sink_ready,user_initialized,user_session}===
                {ref_write_response,ref_read_response,ref_read_response_valid,ref_read_data,ref_command_data,
                 ref_command_valid,ref_response_ready,ref_initialized,ref_session_id},
                "all USER business outputs match fixed e0c4 BAR");
            diag_miter_checks=diag_miter_checks+1;
        end
    endtask
    always @(negedge user_clk)begin #2;diag_compare_bar();end
    always @(posedge user_clk)begin
        diag_event_prepare=dut.u_bar.g_cfg_diag.prepare_start;
        diag_event_commit=dut.u_bar.g_cfg_diag.commit_accepted;
        diag_event_present=dut.u_bar.effective_ready&&dut.response_sink_valid&&dut.u_bar.applied_reply;
        diag_event_copy=dut.u_bar.job==12&&dut.u_bar.publish_ready;
        diag_event_complete=dut.u_bar.job==13&&dut.u_bar.publish_complete;
        diag_event_publish=dut.u_bar.g_cfg_diag.publish_atomic;
        if(rst_n)begin
            if(diag_event_prepare)diag_prepares=diag_prepares+1;
            if(diag_event_present&&!diag_pending_publish)begin
                diag_presents=diag_presents+1;diag_pending_publish=1;
                diag_old_epoch=dut.u_bar.epoch;diag_old_bank=dut.u_bar.u_store.active_bank;
                check(!diag_domains[167]&&!diag_domains[166],"presented APPLIED is not already published/taken");
            end
            if(diag_event_copy)begin
                diag_copies=diag_copies+1;
                check(diag_pending_publish&&!diag_domains[167],"copy begins only after APPLIED presentation");
            end
            if(diag_pending_publish&&!diag_event_publish)begin
                check(dut.u_bar.epoch==diag_old_epoch&&dut.u_bar.u_store.active_bank==diag_old_bank,
                    "copy/presentation retain old epoch and active bank until atomic handshake");
                check(!diag_domains[167]&&!diag_domains[166],"no early USER taken/published milestones");
            end
            if(dut.u_bar.copy_busy)diag_copy_cycles=diag_copy_cycles+1;
            if(diag_event_publish)begin
                check(diag_event_complete&&dut.u_bar.reply_final&&dut.u_bar.reply_match,
                    "USER publication requires complete copy and matching real final handshake");
                diag_publications=diag_publications+1;
            end
        end
        #1;
        diag_compare_bar();
        if(rst_n)begin
            if(diag_event_prepare)check(diag_domains[160]&&diag_domains[167:161]==0&&
                diag_domains[63:32]==request_id&&diag_domains[31:0]==user_session,
                "new PREPARE resets milestones with current USER request identity");
            if(diag_event_commit)check(diag_domains[161],"real USER COMMIT acceptance sets its own milestone");
            if(diag_event_present)check(diag_domains[163],"presented APPLIED independently records before publication");
            if(diag_event_copy)check(diag_domains[164],"copy-start handshake records its own milestone");
            if(diag_event_complete)check(diag_domains[165],"complete copy records its own milestone");
            if(diag_event_publish)begin
                check(diag_domains[167:160]==8'hff&&diag_domains[127:96]==diag_old_epoch+1&&
                    diag_domains[159:128]==32'd1000+request_id&&dut.u_bar.u_store.active_bank!=diag_old_bank,
                    "matching final handshake atomically publishes bank/epoch/exact frame and all USER milestones");
                diag_pending_publish=0;
            end
        end else diag_pending_publish=0;
    end
