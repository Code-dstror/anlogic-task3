`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
module tb_autof21_control;
    reg uc=0,pc=0,ur=0,pr=0;
    always #4 uc=~uc;
    always #5 pc=~pc;
    reg wv=0,rv=0;reg [11:0] wa=0,ra=0;reg [31:0] wd=0;
    wire [1:0] wr,rr;wire rvalid;wire [31:0] rd;
    reg frame_accept=0;reg [31:0] frame_sequence=0;
    wire source_ready,ui,pi,config_fault;
    wire [31:0] us,ps,epoch,stale;
    wire [1183:0] front,active,lease_request,lease_ack;
    wire front_valid,front_ready,front_ack_ready,lease_request_valid,lease_request_ok;
    wire lease_ack_valid,lease_ack_ok,lease_ack_ready;
    reg downstream_ready=0,downstream_ack_valid=0;reg [1183:0] downstream_ack=0;
    wire lease_busy,lease_active,lease_fault,lease_inhibit;wire [31:0] lease_generation;
    wire active_schema2;wire [5:0] active_enables;
    mono_config_service_v2 #(.EXT_SUPPORTED(8'h3c),.V2_SUPPORTED_MODES(3'b101),.V2_SUPPORTED_ENABLES(6'h3f)) cfg(
        .user_clk(uc),.user_rst_n(ur),.pixel_clk(pc),.pixel_rst_n(pr),
        .write_valid(wv),.write_offset(wa),.write_data(wd),.write_strobes(4'hf),.write_response(wr),
        .read_valid(rv),.read_offset(ra),.read_response_valid(rvalid),.read_data(rd),.read_response(rr),
        .pipeline_idle(1'b1),.frame_accept(frame_accept),.frame_sequence(frame_sequence),
        .source_ready(source_ready),.pause_new_jobs(),.active_mode(),.active_quality(),.adaptive_quality(),
        .minimum_quality(),.frame_budget(),.restart_mcus(),.source_session(ps),.mode_epoch(epoch),
        .user_session(us),.user_initialized(ui),.pixel_initialized(pi),
        .m_config_data(front),.m_config_valid(front_valid),.m_config_ready(front_ready),
        .s_config_ack_data(lease_ack),.s_config_ack_valid(lease_ack_valid),.s_config_ack_ok(lease_ack_ok),
        .s_config_ack_ready(front_ack_ready),.config_fault(config_fault),.config_stale_ack_count(stale),
        .active_config(active),.active_schema2(active_schema2),.active_legacy_gaussian(),
        .active_product_mode(),.active_processing_enables(active_enables),
        .diag_observer_rst_n(2'b00),.diag_source_fs(1'b0),.diag_source_gates(16'd0),.diag_domains(),.diag_domain_reset_n());
    wire owned_lut_valid,core_reset;
    wire [31:0] owned_generation;
    wire update_busy=1'b0;
    pixel_lut_config_lease lease(
        .clk(pc),.rst_n(pr),.i_session_valid(pi),.i_session(ps),
        .i_lut_valid(owned_lut_valid),.i_lut_generation(owned_generation),
        .i_update_busy(update_busy),.i_algorithm_quiet(1'b1),
        .s_frontend_data(front),.s_frontend_valid(front_valid),.s_frontend_ok(1'b1),.s_frontend_ready(front_ready),
        .m_request_data(lease_request),.m_request_valid(lease_request_valid),.m_request_ok(lease_request_ok),.m_request_ready(downstream_ready),
        .s_ack_data(downstream_ack),.s_ack_valid(downstream_ack_valid),.s_ack_ok(1'b1),.s_ack_ready(lease_ack_ready),
        .m_ack_data(lease_ack),.m_ack_valid(lease_ack_valid),.m_ack_ok(lease_ack_ok),.m_ack_ready(front_ack_ready),
        .o_update_inhibit(lease_inhibit),.o_busy(lease_busy),.o_active(lease_active),.o_release_pending(),
        .o_active_generation(lease_generation),.o_fault(lease_fault));
    wire lv;wire [31:0] lut_generation;
    reset_release_sync map_reset(.i_clk(pc),.i_async_rst_n(ur&&pr),.o_rst_n(core_reset));
    assign owned_lut_valid=lv&&pi&&ps!=0;
    assign owned_generation=lut_generation;
    // Real qualified map and official map RAM/multiplier; no table loader stub.
    preprocess_dehaze_map_qualified #(.AUTO_FIXED_LUT_ENABLE(1)) map_owner(
        .clk(pc),.rst_n(core_reset),.frame_cancel(1'b0),.history_reset(1'b0),.i_history_eligible(1'b1),
        .main_begin(1'b0),.main_begin_ready(),.main_release(1'b0),.main_fault(1'b0),.main_camera(1'b0),
        .main_cohort(209'd0),.main_frame_id(32'd0),.main_history_valid(),.main_a(),.main_age(),.main_lut_generation(),
        .main_pin_valid(),.main_pin_camera(),.main_pin_a(),.main_pin_capture(),.main_req_valid(1'b0),.main_req_ready(),
        .main_req_tile(8'd0),.main_reply_valid(),.main_reply_data(),
        .obs_valid(1'b0),.obs_ready(),.obs_rgb(24'd0),.obs_y(8'd0),.obs_sof(1'b0),.obs_eol(1'b0),.obs_last(1'b0),
        .obs_camera(1'b0),.obs_cohort(209'd0),.obs_frame_id(32'd0),.obs_context(160'd0),
        .obs_status_valid(1'b0),.obs_status_ready(),.obs_status_ok(1'b0),.obs_status_error(8'd0),
        .obs_status_pixels(16'd0),.obs_status_delivered(16'd0),
        .source_valid(1'b0),.source_ready(),.source_camera(1'b0),.source_ok(1'b0),.source_owner_match(),
        .source_accepted(),.source_decision_valid(),.source_decision_collect(),.source_decision_capture(),.source_cancel_done(),
        .source_session(32'd0),.source_epoch(32'd0),.source_capture(32'd0),
        .cfg_begin_valid(1'b0),.cfg_begin_ready(),.cfg_generation(32'd0),.cfg_valid(1'b0),.cfg_ready(),
        .cfg_index(9'd0),.cfg_value(11'd0),.cfg_commit_valid(1'b0),.cfg_commit_ready(),.cfg_abort(1'b0),
        .cfg_status_valid(),.cfg_status_ready(1'b1),.cfg_status_ok(),.cfg_status_error(),.cfg_status_generation(),
        .lut_valid(lv),.lut_generation(lut_generation),.map_commit(),.map_commit_camera(),.map_commit_frame_id(),.map_commit_context(),
        .candidate_tile_valid(),.candidate_tile_index(),.candidate_tile_data(),.debug_clear_firstfault(1'b0),
        .candidate_drops(),.qualified_maps(),.control_rejects(),.source_rejects(),.firstfault(),.firstfault_context());
    `include "analysis_config_transport.vh"
    integer checks=0,callbacks=0,request_id=10,k,limit;
    reg [1023:0] extension,algorithm;
    reg [1183:0] plan,old_active;
    reg [31:0] status,error,readback,old_session;
    task check(input bit good,input string why);
        begin checks++;if(!good)$fatal(1,"AUTOF21 control %s cfg=%0d/%0d epoch=%0d lease=%0d",why,cfg.u_bar.state,cfg.u_engine.state,epoch,lease.state);end
    endtask
    always @(posedge pc)if(pr)begin
        if(lease_request_valid&&downstream_ready)callbacks++;
    end
    task csr_write(input [11:0] address,input [31:0] data);
        begin @(negedge uc);wa=address;wd=data;wv=1;#1;check(wr==0,"CFG write");@(posedge uc);@(negedge uc);wv=0;end
    endtask
    task csr_read(input [11:0] address,output [31:0] data);
        begin
            @(negedge uc);ra=address;rv=1;@(posedge uc);#1;
            if(!rvalid)begin @(negedge uc);rv=0;limit=0;while(!rvalid)begin @(posedge uc);#1;limit++;check(limit<100,"CFG read bounded");end end
            check(rr==0,"CFG read");data=rd;@(negedge uc);rv=0;
        end
    endtask
    task callback;
        begin
            limit=0;while(!lease_request_valid)begin @(negedge pc);limit++;check(limit<4000,"CFG callback bounded");end
            plan=lease_request;check(lease_request_ok,"real lease authorizes requested LUT");
            repeat(7)begin @(negedge pc);check(lease_request_valid&&lease_request===plan,"borrowed request holds raw1184 bits");end
            downstream_ready=1;@(posedge pc);@(negedge pc);downstream_ready=0;
            downstream_ack=plan;downstream_ack_valid=1;
            do @(posedge pc);while(!lease_ack_ready);
            @(negedge pc);downstream_ack_valid=0;
        end
    endtask
    task boot;
        begin
            callback();limit=0;while(!ui||!pi||!owned_lut_valid)begin @(negedge uc);limit++;check(limit<2000,"session and fixed LUT become ready without ALGO");end
            check(us!=0&&us==ps&&owned_generation==1&&!lease_active&&!config_fault&&!lease_fault,"real BOOT and automatic generation1");
        end
    endtask
    task request(input [5:0] enables,input [31:0] lut_gen);
        begin
            extension=0;extension[7:0]=2;extension[15:10]=enables;extension[383:352]=lut_gen;
            request_id++;csr_write(`PCIE_REG_CFG_REQUEST_SEQUENCE,request_id);csr_write(`PCIE_REG_CFG_REQUEST_SESSION,us);
            csr_write(`PCIE_REG_CFG_REQUEST_MODE,0);csr_write(`PCIE_REG_CFG_REQUEST_QUALITY,75);csr_write(`PCIE_REG_CFG_REQUEST_FLAGS,0);
            csr_write(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);csr_write(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);csr_write(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);
            csr_write(`PCIE_REG_CFG_HOST_CAPABILITIES,1);
            for(k=0;k<32;k++)csr_write(`PCIE_REG_CFG_EXT_SHADOW_BASE+k*4,extension[k*32+:32]);
        end
    endtask
    task apply;
        integer polls;
        begin
            old_active=active;csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);status=0;polls=0;
            while(!status[1])begin csr_read(`PCIE_REG_CFG_STATUS,status);polls++;check(polls<2000&&!status[3],"PREPARE reaches READY");end
            check(active===old_active&&!front_valid,"PREPARE preserves active tuple");
            csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);callback();
            check(plan[1183:160]===extension,"COMMIT callback preserves raw generation0/1");
            limit=0;while(!cfg.u_engine.frame_apply_eligible)begin @(negedge pc);limit++;check(limit<1000,"whole positive ACK arms APPLIED");end
            check(active===old_active,"ACK alone waits frame boundary");
            frame_sequence++;frame_accept=1;@(posedge pc);#1;check(active===plan,"frame boundary applies exact raw tuple");@(negedge pc);frame_accept=0;
            status=1;polls=0;while(status[0]||!status[2])begin csr_read(`PCIE_REG_CFG_STATUS,status);polls++;check(polls<1000,"APPLIED returns to USER");end
            for(k=0;k<32;k++)begin csr_read(`PCIE_REG_CFG_EXT_ACTIVE_BASE+k*4,readback);check(readback===extension[k*32+:32],"all active BAR words preserve raw identity");end
            algorithm=analysis_algorithm_extension(active[1183:160]);
            check(active_schema2&&active_enables==extension[15:10]&&!config_fault&&!lease_fault,"independent mode/enables and no faults");
            check(lease_active==extension[11]&&lease_generation==(extension[11]?1:0),"lease pins effectiveG1 and disable releases");
            check(algorithm[383:352]==(extension[11]?1:0),"algorithm view uses effective generation; disabled stays0");
            if(extension[14])check(algorithm[`PCIE_CFG_EXT_OFFSET_STRIP_COUNT+:4]==4&&
                algorithm[`PCIE_CFG_EXT_OFFSET_STRIP_Y_END+:52]=={13'd270,13'd202,13'd135,13'd67},"four-band F22/F23 preserved");
        end
    endtask
    task reject(input [5:0] enables,input [31:0] lut_gen);
        integer before_callbacks,polls;
        begin
            old_active=active;before_callbacks=callbacks;request(enables,lut_gen);csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);
            status=1;polls=0;while(status[0])begin csr_read(`PCIE_REG_CFG_STATUS,status);polls++;check(polls<2000,"bad generation retires");end
            csr_read(`PCIE_REG_CFG_ERROR,error);check(status[3]&&error==`PCIE_CFG_ERROR_INVALID&&callbacks==before_callbacks&&active===old_active&&!config_fault,"bad generation rejected before callback without FAULT");
        end
    endtask
    initial begin
        #100;ur=1;pr=1;boot();
        request(6'h02,0);apply();request(0,0);apply();request(6'h32,0);apply();
        check(owned_lut_valid,"ordinary ON/OFF/ON plus F22/F23 needs no ALGO transaction");
        reject(6'h02,2);reject(0,1);request(6'h02,1);apply();
        old_session=us;@(negedge pc);pr=0;repeat(20)@(negedge uc);
        check(!owned_lut_valid&&!lease_active&&!pi,"pixel reset invalidates all live ownership");
        @(negedge pc);pr=1;boot();check(us!=old_session,"real FIFO release creates new CFG session");
        request(6'h02,0);apply();check(owned_lut_valid&&stale==0,"new session re-enables with ordinary CFG only");
        $display("RESULT: PASS AUTOF21 control checks=%0d callbacks=%0d algo_commands=0 session=%0d epoch=%0d rawG0=preserved effectiveG=1",checks,callbacks,us,epoch);$finish;
    end
    initial begin #3000000;$fatal(1,"AUTOF21 control watchdog");end
endmodule
