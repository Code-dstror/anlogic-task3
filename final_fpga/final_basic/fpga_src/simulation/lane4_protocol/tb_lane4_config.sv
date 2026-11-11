`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
module tb_lane4_config;
    reg user_clk=0,pixel_clk=0,rst_n=0;
    always #4 user_clk=~user_clk;
    always #5 pixel_clk=~pixel_clk;
    reg write_valid=0,read_valid=0;
    reg [11:0] write_offset=0,read_offset=0;
    reg [31:0] write_data=0;
    wire [1:0] write_response,read_response;
    wire read_response_valid;
    wire [31:0] read_data;
    reg pipeline_idle=1,frame_accept=0;
    reg [31:0] frame_sequence=0;
    wire source_ready,pause_new_jobs,user_initialized,pixel_initialized,config_fault;
    wire [31:0] source_session,mode_epoch,user_session,stale_acks;
    wire [1183:0] m_config_data,active_config;
    wire m_config_valid,s_config_ack_ready;
    wire active_schema2,active_legacy_gaussian;
    wire [1:0] active_product_mode;
    wire [5:0] active_processing_enables;
    reg m_config_ready=0,s_config_ack_valid=0;
    reg [1183:0] s_config_ack_data=0;
    // Same masks as MAIN: 0x3c legacy and 0x3f independent schema2 enables.
    mono_config_service_v2 #(.EXT_SUPPORTED(8'h3c),.V2_SUPPORTED_MODES(3'b101),.V2_SUPPORTED_ENABLES(6'h3f)) dut(
        .user_clk(user_clk),.user_rst_n(rst_n),.pixel_clk(pixel_clk),.pixel_rst_n(rst_n),
        .write_valid(write_valid),.write_offset(write_offset),.write_data(write_data),.write_strobes(4'hf),.write_response(write_response),
        .read_valid(read_valid),.read_offset(read_offset),.read_response_valid(read_response_valid),.read_data(read_data),.read_response(read_response),
        .pipeline_idle(pipeline_idle),.frame_accept(frame_accept),.frame_sequence(frame_sequence),
        .source_ready(source_ready),.pause_new_jobs(pause_new_jobs),.active_mode(),.active_quality(),.adaptive_quality(),
        .minimum_quality(),.frame_budget(),.restart_mcus(),.source_session(source_session),.mode_epoch(mode_epoch),
        .user_session(user_session),.user_initialized(user_initialized),.pixel_initialized(pixel_initialized),
        .m_config_data(m_config_data),.m_config_valid(m_config_valid),.m_config_ready(m_config_ready),
        .s_config_ack_data(s_config_ack_data),.s_config_ack_valid(s_config_ack_valid),.s_config_ack_ok(1'b1),
        .s_config_ack_ready(s_config_ack_ready),.config_fault(config_fault),.config_stale_ack_count(stale_acks),
        .active_config(active_config),.active_schema2(active_schema2),.active_legacy_gaussian(active_legacy_gaussian),
        .active_product_mode(active_product_mode),.active_processing_enables(active_processing_enables),
        .diag_observer_rst_n(2'b00),.diag_source_fs(1'b0),.diag_source_gates(16'd0),.diag_domains(),.diag_domain_reset_n());
    `include "mono_config_transport_v2.vh"
    reg [1023:0] extension,algorithm;
    reg [1183:0] gate_tuple=0;
    wire [1183:0] gate_ack;
    wire gate_lease_valid,gate_ack_valid,gate_ack_ok;
    wire [1023:0] gate_algorithm;
    wire [5:0] gate_enables;
    mono_config_narrow_gate_v2 #(.LEGACY_SUPPORTED(8'h3c),.V2_SUPPORTED_MODES(3'b101),.V2_SUPPORTED_ENABLES(6'h3f)) gate(
        .s_frontend_data(gate_tuple),.s_frontend_valid(1'b1),.s_frontend_ok(1'b1),.s_frontend_ready(),
        .m_lease_data(),.m_lease_valid(gate_lease_valid),.m_lease_ok(),.m_lease_ready(1'b0),.i_lease_busy(1'b0),
        .s_lease_ack_data(1184'd0),.s_lease_ack_valid(1'b0),.s_lease_ack_ok(1'b0),.s_lease_ack_ready(),
        .m_ack_data(gate_ack),.m_ack_valid(gate_ack_valid),.m_ack_ok(gate_ack_ok),.m_ack_ready(1'b1),
        .m_schema2(),.m_legacy_gaussian(),.m_product_mode(),.m_processing_enables(gate_enables),.m_algorithm_parameters(gate_algorithm));
    reg [1183:0] plan,active_before;
    reg [31:0] value,status_word,error_word;
    integer checks=0,callbacks=0,request_id=10,k,limit,schema_id,before_callbacks;
    always @(posedge pixel_clk)if(rst_n && m_config_valid && m_config_ready)callbacks=callbacks+1;
    task check(input bit okay,input string why);
        begin checks=checks+1;if(!okay)$fatal(1,"LANE4 config %s epoch=%0d bar=%0d/%0d engine=%0d",why,mode_epoch,dut.u_bar.state,dut.u_bar.job,dut.u_engine.state);end
    endtask
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
            check(read_response==0,"BAR read okay");data_value=read_data;
            @(negedge user_clk);read_valid=0;
        end
    endtask
    task callback;
        begin
            limit=0;while(!m_config_valid)begin @(negedge pixel_clk);limit=limit+1;check(limit<3000,"callback bounded");end
            plan=m_config_data;
            repeat(7)begin @(negedge pixel_clk);check(m_config_valid&&m_config_data===plan,"callback stable under stall");end
            m_config_ready=1;@(posedge pixel_clk);@(negedge pixel_clk);m_config_ready=0;
            s_config_ack_data=plan;s_config_ack_valid=1;
            do @(posedge pixel_clk);while(!s_config_ack_ready);
            @(negedge pixel_clk);s_config_ack_valid=0;
        end
    endtask
    task load_request(input integer schema_value);
        begin
            if(schema_value==1)extension=stage2_unpack_extension(208'd2);
            else begin extension=0;extension[15:0]=16'hc002;end
            request_id=request_id+1;
            csr_write(`PCIE_REG_CFG_REQUEST_SEQUENCE,request_id);
            csr_write(`PCIE_REG_CFG_REQUEST_SESSION,user_session);
            csr_write(`PCIE_REG_CFG_REQUEST_MODE,schema_value==1?2:0);
            csr_write(`PCIE_REG_CFG_REQUEST_QUALITY,75);csr_write(`PCIE_REG_CFG_REQUEST_FLAGS,0);
            csr_write(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);csr_write(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);
            csr_write(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);csr_write(`PCIE_REG_CFG_HOST_CAPABILITIES,1);
            for(k=0;k<32;k=k+1)csr_write(`PCIE_REG_CFG_EXT_SHADOW_BASE+k*4,extension[k*32+:32]);
        end
    endtask
    task apply_request;
        integer polls;
        begin
            active_before=active_config;
            csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);
            polls=0;status_word=0;
            while(!status_word[1])begin
                csr_read(`PCIE_REG_CFG_STATUS,status_word);polls=polls+1;
                check(polls<1500&&!status_word[3],"canonical four-band PREPARE succeeds");
            end
            check(active_config===active_before&&!m_config_valid,"PREPARE keeps active configuration");
            csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);callback();
            check(plan[1183:160]===extension,"callback exact canonical raw extension");
            while(!dut.u_engine.frame_apply_eligible)@(negedge pixel_clk);
            check(active_config===active_before,"ACK waits frame boundary");
            frame_sequence=1000+request_id;frame_accept=1;
            @(posedge pixel_clk);#1;check(active_config===plan,"atomic frame-boundary apply");
            @(negedge pixel_clk);frame_accept=0;
            polls=0;status_word=1;
            while(status_word[0]||!status_word[2])begin csr_read(`PCIE_REG_CFG_STATUS,status_word);polls=polls+1;check(polls<1000,"APPLIED readback completes");end
            for(k=0;k<32;k=k+1)begin
                csr_read(`PCIE_REG_CFG_EXT_ACTIVE_BASE+k*4,value);
                check(value===extension[k*32+:32],"all raw active BAR words match requested schema");
            end
            algorithm=mono_algorithm_parameters(active_config[1183:160]);
            gate_tuple=active_config;#1;
            check(gate_lease_valid&&!gate_ack_valid&&gate_algorithm===algorithm&&gate_enables==active_processing_enables,"actual narrow gate forwards exact applied preset and independent enables");
            check(algorithm[`PCIE_CFG_EXT_OFFSET_STRIP_COUNT+:4]==4,"four applied algorithm strips");
            check(algorithm[`PCIE_CFG_EXT_OFFSET_STRIP_Y_BEGIN+:52]=={13'd202,13'd135,13'd67,13'd0},"all four quarter Y begins");
            check(algorithm[`PCIE_CFG_EXT_OFFSET_STRIP_Y_END+:52]=={13'd270,13'd202,13'd135,13'd67},"all four quarter Y ends");
            check(algorithm[`PCIE_CFG_EXT_OFFSET_ROI_LEFT+:52]==0&&
                algorithm[`PCIE_CFG_EXT_OFFSET_ROI_SPLIT+:52]=={4{13'd240}}&&
                algorithm[`PCIE_CFG_EXT_OFFSET_ROI_RIGHT+:52]=={4{13'd480}},"four left/right ROI boundaries");
            check(algorithm[383:256]==0&&algorithm[255:64]==0,"lane request does not enable dehaze or HDR parameters");
            check(active_product_mode==0&&!config_fault&&stale_acks==0,"no unrelated product owner enabled");
            check(active_processing_enables==(schema_id==1?6'h31:6'h30),"independent enables; only legacy Gaussian adds gray");
            check(active_schema2==(schema_id==2)&&active_legacy_gaussian==(schema_id==1),"schema/legacy Gaussian provenance");
        end
    endtask
    initial begin
        #100;repeat(4)@(negedge user_clk);rst_n=1;
        callback();limit=0;
        while(!user_initialized||!pixel_initialized)begin @(negedge user_clk);limit=limit+1;check(limit<1000,"BOOT complete");end
        csr_read(`PCIE_REG_CFG_EXT_STRIPS,value);check(value==4,"CFG_EXT_STRIPS readback=4");
        csr_read(`PCIE_REG_CFG_EXT_SUPPORTED,value);check(value==32'h3c,"legacy only F22/F23 restored; HDR/F21 unchanged");
        csr_read(`PCIE_REG_CFG_EXT_V2_ENABLES,value);check(value==32'h3f,"schema2 enable mask unchanged");
        csr_read(`PCIE_REG_CFG_EXT_V2_MODES,value);check(value==5,"MONO/HDR modes unchanged; NR unsupported");
        csr_read(`PCIE_REG_CFG_EXT_COMBINATIONS,value);check(value==0,"no new combination enabled");
        for(schema_id=2;schema_id>=1;schema_id=schema_id-1)begin load_request(schema_id);apply_request();end
        // Reserved schema2 mode stays rejected by the same BAR scanner.
        active_before=active_config;before_callbacks=callbacks;load_request(2);
        extension[9:8]=1;csr_write(`PCIE_REG_CFG_EXT_SHADOW_BASE,extension[31:0]);
        csr_write(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);
        status_word=1;limit=0;
        while(status_word[0])begin csr_read(`PCIE_REG_CFG_STATUS,status_word);limit=limit+1;check(limit<1500,"unsupported PREPARE retires");end
        csr_read(`PCIE_REG_CFG_ERROR,error_word);
        check(error_word==`PCIE_CFG_ERROR_UNSUPPORTED&&active_config===active_before&&callbacks==before_callbacks,"unsupported mode remains rejected without new authority");
        check(callbacks==3&&mode_epoch==2&&!config_fault,"one BOOT and two applied callbacks");
        gate_tuple=active_config;gate_tuple[660]=~gate_tuple[660];#1;
        check(!gate_lease_valid&&gate_ack_valid&&!gate_ack_ok&&gate_ack===gate_tuple,"noncanonical lane geometry receives full original negative ACK");
        $display("RESULT: PASS LANE4 config checks=%0d callbacks=%0d epoch=%0d strips=4 legacy=3c v2=3f",checks,callbacks,mode_epoch);$finish;
    end
    initial begin #2000000;$fatal(1,"LANE4 config watchdog");end
endmodule
