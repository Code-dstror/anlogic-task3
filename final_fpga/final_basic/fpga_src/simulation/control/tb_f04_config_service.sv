`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
module tb_f04_config_service;
    reg user_clk=0,pixel_clk=0,rst_n=0;
    always #4 user_clk=~user_clk;
    always #5 pixel_clk=~pixel_clk;
    reg write_valid=0,read_valid=0;
    reg [11:0] write_offset=0,read_offset=0;
    reg [31:0] write_data=0;
    reg [3:0] write_strobes=15;
    wire [1:0] write_response,read_response;
    wire read_response_valid;
    wire [31:0] read_data;
    reg pipeline_idle=1,frame_accept=0;
    reg [31:0] frame_sequence=0;
    wire source_ready,pause_new_jobs,user_initialized,pixel_initialized,config_fault;
    wire [31:0] source_session,mode_epoch,user_session,stale_acks;
    wire [1183:0] m_config_data,active_config;
    wire m_config_valid,s_config_ack_ready;
    reg m_config_ready=0,s_config_ack_valid=0,s_config_ack_ok=1;
    reg [1183:0] s_config_ack_data=0;
    mono_config_service_v2 #(.EXT_SUPPORTED(8'h3c),.V2_SUPPORTED_MODES(3'b101),.V2_SUPPORTED_ENABLES(6'h3f)) dut(
        .user_clk(user_clk),.user_rst_n(rst_n),.pixel_clk(pixel_clk),.pixel_rst_n(rst_n),
        .write_valid(write_valid),.write_offset(write_offset),.write_data(write_data),.write_strobes(write_strobes),.write_response(write_response),
        .read_valid(read_valid),.read_offset(read_offset),.read_response_valid(read_response_valid),.read_data(read_data),.read_response(read_response),
        .pipeline_idle(pipeline_idle),.frame_accept(frame_accept),.frame_sequence(frame_sequence),
        .source_ready(source_ready),.pause_new_jobs(pause_new_jobs),.active_mode(),.active_quality(),.adaptive_quality(),
        .minimum_quality(),.frame_budget(),.restart_mcus(),.source_session(source_session),.mode_epoch(mode_epoch),
        .user_session(user_session),.user_initialized(user_initialized),.pixel_initialized(pixel_initialized),
        .m_config_data(m_config_data),.m_config_valid(m_config_valid),.m_config_ready(m_config_ready),
        .s_config_ack_data(s_config_ack_data),.s_config_ack_valid(s_config_ack_valid),.s_config_ack_ok(s_config_ack_ok),
        .s_config_ack_ready(s_config_ack_ready),.config_fault(config_fault),.config_stale_ack_count(stale_acks),
        .active_config(active_config),.active_schema2(),.active_legacy_gaussian(),.active_product_mode(),.active_processing_enables());
    reg [1023:0] extension;
    reg [1183:0] plan,active_before;
    reg [31:0] status_word,error_word,session_before,epoch_before,value;
    reg [63:0] requested_delta;
    reg [31:0] requested_wait,requested_age;
    integer checks=0,callback_count=0,forwarded=0,rejected=0,recovered=0,request_id=10;
    integer schema_id,bad_case,k,limit,before_callbacks,before_forwarded;
    reg guard_invalid=0;
    task check(input bit okay,input string why);
        begin checks=checks+1;if(!okay)$fatal(1,"F04 service schema=%0d bad=%0d %s bar=%0d/%0d engine=%0d epoch=%0d",schema_id,bad_case,why,dut.u_bar.state,dut.u_bar.job,dut.u_engine.state,mode_epoch);end
    endtask
    always @(posedge pixel_clk)if(rst_n)begin
        if(m_config_valid&&m_config_ready)callback_count=callback_count+1;
        if(guard_invalid)begin check(!m_config_valid,"invalid PREPARE never creates callback offer");check(!config_fault,"invalid PREPARE never sticky FAULT");end
    end
    always @(posedge user_clk)if(rst_n&&dut.command_source_valid&&dut.command_source_ready)forwarded=forwarded+1;
    task csr_write(input [11:0] address,input [31:0] data_value);
        begin
            @(negedge user_clk);write_valid=1;write_offset=address;write_data=data_value;
            #1;check(write_response==0,"BAR write accepted");
            @(posedge user_clk);@(negedge user_clk);write_valid=0;
        end
    endtask
    task csr_read(input [11:0] address,output [31:0] data_value);
        begin
            @(negedge user_clk);read_valid=1;read_offset=address;
            @(posedge user_clk);#1;
            if(!read_response_valid)begin
                @(negedge user_clk);read_valid=0;limit=0;
                while(!read_response_valid)begin @(posedge user_clk);#1;limit=limit+1;check(limit<100,"BAR read bounded");end
            end
            check(read_response==0,"BAR read response okay");data_value=read_data;
            @(negedge user_clk);read_valid=0;
        end
    endtask
    task take_callback;
        begin
            limit=0;while(!m_config_valid)begin @(negedge pixel_clk);limit=limit+1;check(limit<3000,"callback bounded");end
            plan=m_config_data;repeat(3)begin @(negedge pixel_clk);check(m_config_valid&&m_config_data===plan,"callback held while not ready");end
            m_config_ready=1;@(posedge pixel_clk);@(negedge pixel_clk);m_config_ready=0;
        end
    endtask
    task ack_callback;
        begin
            @(negedge pixel_clk);s_config_ack_data=plan;s_config_ack_valid=1;
            do @(posedge pixel_clk);while(!s_config_ack_ready);
            @(negedge pixel_clk);s_config_ack_valid=0;
        end
    endtask
    task load_request(input integer schema_value,input [63:0] delta_value,input [31:0] wait_value,age_value);
        begin
            requested_delta=delta_value;requested_wait=wait_value;requested_age=age_value;
            extension=0;extension[31:0]=schema_value==2 ? 32'h202 : 32'h401;
            extension[66:64]=4;extension[76:67]=50;extension[86:77]=50;
            extension[100:87]=64;extension[104:101]=3;extension[108:105]=15;
            extension[191:128]=delta_value;extension[223:192]=wait_value;extension[255:224]=age_value;
            request_id=request_id+1;
            csr_write(`PCIE_REG_CFG_REQUEST_SEQUENCE,request_id);
            csr_write(`PCIE_REG_CFG_REQUEST_SESSION,user_session);
            csr_write(`PCIE_REG_CFG_REQUEST_MODE,0);csr_write(`PCIE_REG_CFG_REQUEST_QUALITY,75);
            csr_write(`PCIE_REG_CFG_REQUEST_FLAGS,0);csr_write(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);
            csr_write(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);csr_write(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);
            csr_write(`PCIE_REG_CFG_HOST_CAPABILITIES,1);
            for(k=0;k<32;k=k+1)csr_write(`PCIE_REG_CFG_EXT_SHADOW_BASE+k*4,extension[k*32+:32]);
        end
    endtask
    task check_old_authority;
        begin
            check(active_config===active_before,"entire1184-bit active tuple unchanged");
            check(source_session==session_before&&user_session==session_before&&mode_epoch==epoch_before,
                "session and active epoch unchanged");
            check(user_initialized&&pixel_initialized&&source_ready&&!config_fault,"initialized authority stays usable");
            check(callback_count==before_callbacks&&forwarded==before_forwarded,"invalid PREPARE is not forwarded and has no callback");
            for(k=4;k<=7;k=k+1)begin
                csr_read(`PCIE_REG_CFG_EXT_ACTIVE_BASE+k*4,value);
                check(value===active_before[160+k*32+:32],"BAR active timer bank unchanged");
            end
        end
    endtask
    task reject_bad;
        integer polls;
        begin
            active_before=active_config;session_before=source_session;epoch_before=mode_epoch;
            before_callbacks=callback_count;before_forwarded=forwarded;guard_invalid=1;
            case(bad_case)
                0:load_request(schema_id,1000000,0,100000000);
                1:load_request(schema_id,1000000,50000000,0);
                2:load_request(schema_id,64'h100000000,50000000,100000000);
            endcase
            csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);
            polls=0;status_word=1;
            while(status_word[0])begin csr_read(`PCIE_REG_CFG_STATUS,status_word);polls=polls+1;check(polls<1000,"invalid PREPARE retires");end
            csr_read(`PCIE_REG_CFG_ERROR,error_word);
            check(status_word[4]&&status_word[3]&&!status_word[1]&&error_word==`PCIE_CFG_ERROR_INVALID,
                "pure timer error returns INVALID before COMMIT");
            repeat(25)@(negedge pixel_clk);check_old_authority();guard_invalid=0;rejected=rejected+1;
        end
    endtask
    task legal_recovery;
        integer polls;
        begin
            case(bad_case)
                0:load_request(schema_id,0,1,1);
                1:load_request(schema_id,64'hffffffff,1,1);
                2:load_request(schema_id,1000000,50000000,100000000);
            endcase
            csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);
            polls=0;status_word=0;
            while(!status_word[1])begin csr_read(`PCIE_REG_CFG_STATUS,status_word);polls=polls+1;check(polls<1500,"legal PREPARE reaches READY");check(!status_word[3],"legal PREPARE has no error");end
            check(!m_config_valid&&mode_epoch==epoch_before&&active_config===active_before,"PREPARE does not apply");
            csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);take_callback();
            check(plan[351:288]==requested_delta&&plan[383:352]==requested_wait&&plan[415:384]==requested_age,
                "callback preserves full requested timers including delta0 and max32");
            check(plan[63:32]==session_before&&plan[159:128]==epoch_before+1,"callback exact identity");
            ack_callback();limit=0;
            while(!dut.u_engine.frame_apply_eligible)begin @(negedge pixel_clk);limit=limit+1;check(limit<100,"positive ACK arms existing frame boundary");end
            check(active_config===active_before&&mode_epoch==epoch_before,"ACK alone does not apply");
            @(negedge pixel_clk);frame_sequence=32'd1000+request_id;frame_accept=1;
            @(posedge pixel_clk);#1;check(active_config===plan&&mode_epoch==epoch_before+1,"exact frame applies accepted tuple");
            @(negedge pixel_clk);frame_accept=0;
            polls=0;status_word=1;
            while(status_word[0]||!status_word[2])begin csr_read(`PCIE_REG_CFG_STATUS,status_word);polls=polls+1;check(polls<1000,"APPLIED BAR copy/response completes");end
            csr_read(`PCIE_REG_CFG_ERROR,error_word);check(error_word==0&&!status_word[3]&&!config_fault,"legal recovery clears error without reset");
            check(source_session==session_before&&user_session==session_before&&pixel_initialized&&user_initialized,"same session survives rejection and recovery");
            check(callback_count==before_callbacks+1,"one real COMMIT callback per recovery");
            for(k=4;k<=7;k=k+1)begin csr_read(`PCIE_REG_CFG_EXT_ACTIVE_BASE+k*4,value);check(value===extension[k*32+:32],"atomic active timer readback");end
            recovered=recovered+1;
        end
    endtask
    initial begin
        #100;repeat(4)@(negedge user_clk);rst_n=1;
        take_callback();ack_callback();limit=0;
        while(!user_initialized||!pixel_initialized)begin @(negedge user_clk);limit=limit+1;check(limit<1000,"BOOT completes actual service");end
        repeat(8)@(negedge user_clk);check(callback_count==1&&!config_fault,"one clean boot callback");
        for(schema_id=1;schema_id<=2;schema_id=schema_id+1)for(bad_case=0;bad_case<3;bad_case=bad_case+1)begin
            reject_bad();legal_recovery();
        end
        check(rejected==6&&recovered==6&&callback_count==7&&mode_epoch==6&&stale_acks==0,"complete recovery coverage");
        $display("RESULT: PASS F04 service checks=%0d rejected=%0d recovered=%0d callbacks=%0d forwarded_flits=%0d epoch=%0d",checks,rejected,recovered,callback_count,forwarded,mode_epoch);$finish;
    end
    initial begin #2000000;$fatal(1,"F04 service watchdog");end
endmodule
