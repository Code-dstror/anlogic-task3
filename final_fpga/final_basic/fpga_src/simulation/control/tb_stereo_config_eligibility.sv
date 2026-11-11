`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
module tb_stereo_config_eligibility;
    `include "legacy_stage2_config_transport.vh"
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
    reg dual_mode=0;
    reg [31:0] algorithm_generation=0;
    wire stereo_compatible,transaction_idle;
    mono_config_service_v2 #(.EXT_SUPPORTED(8'h34),.V2_SUPPORTED_MODES(3'b101),.V2_SUPPORTED_ENABLES(6'h3f),.STEREO_CAPABLE(1)) dut(
        .i_stereo_mode(dual_mode),.o_user_transaction_idle(transaction_idle),.o_user_stereo_compatible(stereo_compatible),
        .diag_observer_rst_n(2'b11),.diag_source_fs(1'b0),.diag_source_gates(16'd0),.diag_domains(),.diag_domain_reset_n(),
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
    task load_profile(input integer product,input integer enables,input bit bad);
        begin
            extension=0;extension[7:0]=2;extension[9:8]=product;extension[15:10]=enables;
            if(enables & 2) extension[383:352]=algorithm_generation;
            if(product==2)begin
                extension[66:64]=4;extension[76:67]=50;extension[86:77]=50;
                extension[100:87]=64;extension[104:101]=3;extension[108:105]=15;
                extension[191:128]=50000000;extension[223:192]=100000000;extension[255:224]=1000000000;
            end
            if(bad)extension[511]=1;
            request_id++;
            csr_write(`PCIE_REG_CFG_REQUEST_SEQUENCE,request_id);csr_write(`PCIE_REG_CFG_REQUEST_SESSION,user_session);
            csr_write(`PCIE_REG_CFG_REQUEST_MODE,`PCIE_CFG_MODE_COLOR);csr_write(`PCIE_REG_CFG_REQUEST_QUALITY,75);
            csr_write(`PCIE_REG_CFG_REQUEST_FLAGS,0);csr_write(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);
            csr_write(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);csr_write(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);
            csr_write(`PCIE_REG_CFG_HOST_CAPABILITIES,1);
            for(k=0;k<32;k++)csr_write(`PCIE_REG_CFG_EXT_SHADOW_BASE+k*4,extension[k*32+:32]);
        end
    endtask
    task prepare_profile(input integer product,input integer enables);
        integer polls;reg old_compatible;
        begin
            old_compatible=stereo_compatible;load_profile(product,enables,0);
            check(stereo_compatible==old_compatible,"shadow writes do not change active stereo eligibility");
            csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);
            polls=0;status_word=0;
            while(!status_word[1])begin
                csr_read(`PCIE_REG_CFG_STATUS,status_word);polls++;check(polls<1500&&!status_word[3],"valid profile PREPARE reaches READY");
                check(stereo_compatible==old_compatible,"PREPARE cannot publish active eligibility");
            end
            check(!transaction_idle,"READY owner prevents cold switch even if old basic is compatible");
        end
    endtask
    task cancel_profile;
        integer polls;reg old_compatible;
        begin
            old_compatible=stereo_compatible;csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_CANCEL);
            polls=0;while(!transaction_idle)begin @(negedge user_clk);polls++;check(polls<2000,"cancel bounded");end
            check(stereo_compatible==old_compatible,"cancelled PREPARE retains active qualification");
        end
    endtask
    task apply_profile(input integer product,input integer enables,input bit expected_compatible);
        integer polls;reg old_compatible;
        begin
            old_compatible=stereo_compatible;prepare_profile(product,enables);
            csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);take_callback();
            check(stereo_compatible==old_compatible,"COMMIT callback cannot change active eligibility");
            ack_callback();polls=0;
            while(!dut.u_engine.frame_apply_eligible)begin @(negedge pixel_clk);polls++;check(polls<100,"positive ACK arms SOF");end
            check(stereo_compatible==old_compatible,"positive ACK alone cannot publish qualification");
            @(negedge pixel_clk);frame_sequence=1000+request_id;frame_accept=1;
            @(posedge pixel_clk);@(negedge pixel_clk);frame_accept=0;
            polls=0;while(!transaction_idle)begin @(negedge user_clk);polls++;check(polls<2000,"real APPLIED transaction retires");end
            check(stereo_compatible==expected_compatible,"USER real APPLIED atomically publishes correct basic eligibility");
            check(active_config[175:170]==enables&&active_config[169:168]==product&&
                active_config[543:512]==((enables&2)?algorithm_generation:0),"actual algorithm and generation retained at APPLIED");
            $display("STEREO_CFG_APPLIED PASS product=%0d enables=%0h compatible=%0d",product,enables,stereo_compatible);
        end
    endtask
    task reject_dehaze(input integer schema);
        integer polls,callbacks_before,flits_before;
        reg [1183:0] tuple_before;reg [31:0] epoch_saved,session_saved;
        begin
            tuple_before=active_config;epoch_saved=mode_epoch;session_saved=source_session;
            callbacks_before=callback_count;flits_before=forwarded;
            load_profile(0,0,0);
            if(schema==1)extension=stage2_unpack_extension(208'd5); // exact old dehaze preset, generation1
            else begin extension=0;extension[7:0]=2;extension[11]=1;extension[383:352]=2;end
            for(k=0;k<32;k++)csr_write(`PCIE_REG_CFG_EXT_SHADOW_BASE+k*4,extension[k*32+:32]);
            csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);
            polls=0;status_word=1;
            while(status_word[`PCIE_CFG_STATUS_BUSY])begin
                csr_read(`PCIE_REG_CFG_STATUS,status_word);polls++;check(polls<1500,"unsupported dehaze PREPARE retires");
            end
            csr_read(`PCIE_REG_CFG_ERROR,error_word);
            check(status_word[`PCIE_CFG_STATUS_ERROR]&&!status_word[`PCIE_CFG_STATUS_READY]&&
                !status_word[`PCIE_CFG_STATUS_APPLIED]&&error_word==(schema==1?`PCIE_CFG_ERROR_UNSUPPORTED:`PCIE_CFG_ERROR_INVALID),
                "legacy table loader or non-built-in generation rejected");
            check(callback_count==callbacks_before&&forwarded==flits_before&&!m_config_valid,
                "unsupported dehaze does not forward COMMIT or create callback");
            check(active_config===tuple_before&&mode_epoch==epoch_saved&&source_session==session_saved&&stereo_compatible,
                "unsupported dehaze preserves exact old active tuple, epoch, session and cold eligibility");
            $display("DEHAZE_INVALID_CONFIG PASS schema=%0d error=%0d applied=0 active_unchanged=1",schema,error_word);
        end
    endtask
    task reject_dual_features(input [5:0] bits);
        integer before_tx, polls;
        reg [1183:0] old_tuple;
        begin
            old_tuple=active_config;before_tx=forwarded;
            load_profile(0,bits,0);
            csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);
            polls=0;status_word=1;
            while(status_word[0])begin csr_read(`PCIE_REG_CFG_STATUS,status_word);polls++;check(polls<1500,"dual rejection retires");end
            csr_read(`PCIE_REG_CFG_ERROR,error_word);
            check(status_word[3]&&error_word==`PCIE_CFG_ERROR_UNSUPPORTED,"dual unsupported profile refused");
            check(forwarded==before_tx && active_config===old_tuple,"rejection cannot mutate active tuple or cross CDC");
        end
    endtask
    initial begin
        #100;repeat(4)@(negedge user_clk);rst_n=1;
        take_callback();ack_callback();limit=0;
        while(!user_initialized||!pixel_initialized||!transaction_idle)begin @(negedge user_clk);limit++;check(limit<1000,"real BOOT completes");end
        check(stereo_compatible,"BOOT default is basic SDR");
        reject_dehaze(1);reject_dehaze(2);
        prepare_profile(2,0);cancel_profile();check(stereo_compatible,"cancel HDR keeps active basic");
        apply_profile(2,0,0); // applied HDR blocks cold dual selection
        prepare_profile(0,0);cancel_profile();check(!stereo_compatible,"cancel basic cannot clear active HDR exclusion");
        load_profile(0,0,1);csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);
        limit=0;status_word=1;
        while(status_word[0])begin csr_read(`PCIE_REG_CFG_STATUS,status_word);limit++;check(limit<1000,"invalid PREPARE retires");end
        check(status_word[3]&&!stereo_compatible,"invalid PREPARE cannot publish basic eligibility");
        apply_profile(0,48,0); // F22/F23 lane enables exclude dual basic
        apply_profile(0,1,0);  // independent nonzero processing enable excludes dual basic
        apply_profile(0,0,1);  // only true basic APPLIED restores eligibility
        apply_profile(0,2,0);algorithm_generation=1;apply_profile(0,10,0);apply_profile(0,0,1);
        @(negedge user_clk);dual_mode=1;
        csr_read(`PCIE_REG_CFG_EXT_V2_ENABLES,status_word);check(status_word==15,"dual supports shared filters and internal DCP");
        reject_dual_features(48);reject_dual_features(16);reject_dehaze(2);
        apply_profile(0,1,0);apply_profile(0,4,0);apply_profile(0,8,0);apply_profile(0,13,0);
        apply_profile(2,0,0);apply_profile(2,13,0);
        algorithm_generation=0;apply_profile(0,2,0);apply_profile(0,10,0);
        algorithm_generation=1;apply_profile(2,15,0);apply_profile(0,0,1);
        @(negedge user_clk);rst_n=0;repeat(4)@(negedge user_clk);check(!stereo_compatible,"reset clears old active qualification");
        $display("RESULT: PASS STEREO_CONFIG_ELIGIBILITY checks=%0d callbacks=%0d",checks,callback_count);$finish;
    end
    initial begin #3000000;$fatal(1,"stereo eligibility watchdog");end
endmodule
