// Per-camera PHY, CSI parser and sensor mode controller. Included within each physical
// frontend so native clock/CDC paths and qualified receiver instance names are retained.
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] pixel_reset, ref_reset;
    reg [1:0] done_sync, error_sync, enable_sync;
    reg receive_fault;
    wire sensor_done,sensor_error,sensor_xclr,sensor_stable,config_start_ready;
    wire hdr_written,hdr_stable_cfg;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] cfg_release;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] request_cfg,quiet_cfg,mode_pixel,hold_pixel,stable_pixel;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] slow_request_cfg,slow_mode_pixel;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] fault_cfg;
    reg mode_cfg,slow_mode_cfg,mode_hold,config_started,config_start;
    assign hdr_written=mode_cfg&&sensor_done;
    assign hdr_stable_cfg=mode_cfg&&sensor_stable;
    reg [4:0] mode_timer;
    wire source_reset_n=i_reset_n&&!mode_hold;
    wire requested_slow=SDR_RATE_CONTROL_ENABLE!=0&&MODE_4K==0&&i_sdr_30_request;
    wire pair_event_cfg,pair_ok_cfg,pair_overflow;
    reg source_fault_sticky,hdr_source_seen;
    wire good_hdr_pair=i_hdr_pair_event&&i_hdr_pair_ok;
    assign cam_xclr=!mode_hold&&sensor_xclr;
    assign o_hdr_mode=mode_pixel[1];
    assign o_sdr_30_mode=slow_mode_pixel[1]&&!mode_pixel[1];
    assign o_mode_running=!hold_pixel[1];
    assign o_hdr_stable=stable_pixel[1]&&mode_pixel[1]&&!hold_pixel[1];
    real_hdr_sensor_clock_mux u_mclk(.i_sdr_clk(i_sensor_clk),.i_hdr_clk(i_hdr_mclk),
        .i_reset_n(i_reset_n&&i_clock_locked),.i_select_hdr(mode_cfg),.o_clk(cam_mclk));
    always @(posedge i_cfg_clk or negedge i_reset_n)begin
        if(!i_reset_n)cfg_release<=0;else cfg_release<={cfg_release[0],1'b1};
    end
    always @(posedge i_cfg_clk or negedge cfg_release[1])begin
        if(!cfg_release[1])begin
            request_cfg<=0;slow_request_cfg<=0;quiet_cfg<=0;mode_cfg<=0;slow_mode_cfg<=0;
            mode_hold<=1;mode_timer<=0;config_started<=0;config_start<=0;fault_cfg<=0;
        end else begin
            request_cfg<={request_cfg[0],i_hdr_request};slow_request_cfg<={slow_request_cfg[0],requested_slow};
            quiet_cfg<={quiet_cfg[0],i_mode_quiet};
            fault_cfg<={fault_cfg[0],source_fault_sticky};config_start<=0;
            if(mode_hold)begin
                if(mode_timer==4)begin mode_cfg<=request_cfg[1];slow_mode_cfg<=!request_cfg[1]&&slow_request_cfg[1];end
                if(mode_timer==15)begin mode_hold<=0;mode_timer<=0;end
                else mode_timer<=mode_timer+1'b1;
                config_started<=0;
            end else if(quiet_cfg[1]&&(request_cfg[1]!=mode_cfg||
                (!mode_cfg&&slow_request_cfg[1]!=slow_mode_cfg)))begin
                mode_hold<=1;mode_timer<=0;config_started<=0;
            end else if(!config_started&&config_start_ready&&i_clock_locked)begin
                config_start<=1;config_started<=1;
            end
        end
    end
    always @(posedge i_pixel_clk or negedge i_reset_n)begin
        if(!i_reset_n)begin mode_pixel<=0;slow_mode_pixel<=0;hold_pixel<=3;stable_pixel<=0;end
        else begin
            mode_pixel<={mode_pixel[0],mode_cfg};hold_pixel<={hold_pixel[0],mode_hold};
            slow_mode_pixel<={slow_mode_pixel[0],slow_mode_cfg};
            stable_pixel<={stable_pixel[0],hdr_stable_cfg};
        end
    end
    always @(posedge i_pixel_clk or negedge pixel_reset[1])begin
        if(!pixel_reset[1])begin source_fault_sticky<=0;hdr_source_seen<=0;end
        else if(o_hdr_mode)begin
            if(good_hdr_pair)hdr_source_seen<=1;
            // PHY clock reacquisition before the first qualified pair is
            // training. Identity loss and pair-event loss are always fatal.
            if(o_source_identity_fault||pair_overflow||
                (receive_fault&&(hdr_source_seen||good_hdr_pair)))source_fault_sticky<=1;
        end
    end
    real_hdr_event_cdc u_pair_cdc(.s_clk(i_pixel_clk),.s_reset_n(pixel_reset[1]),
        .s_event(i_hdr_pair_event),.s_ok(i_hdr_pair_ok),.s_overflow(pair_overflow),
        .m_clk(i_cfg_clk),.m_reset_n(cfg_release[1]&&!mode_hold),.m_event(pair_event_cfg),.m_ok(pair_ok_cfg));
    // SDR waits were expressed at 24 MHz. Round upwards when moving them to
    // SYS25; do not shorten the qualified reset or STANDBY wake intervals.
    localparam integer CONFIG_SDR_WAIT=(CONFIG_WAIT_CYCLES*25+23)/24;
    localparam integer CONFIG_SDR_WAKE=(SDR_WAKE_CYCLES*25+23)/24;
    localparam integer CONFIG_SDR_I2C=(I2C_HALF_PERIOD*25+23)/24;
    localparam integer CONFIG_I2C_HALF=CONFIG_SDR_I2C>HDR_I2C_HALF_PERIOD?CONFIG_SDR_I2C:HDR_I2C_HALF_PERIOD;
    imx415_sensor_config #(.MODE_4K(MODE_4K),.RUNTIME_GAIN_ENABLE(COLOR_CONFIG_ENABLE),
        .WARMUP_PAIRS(HDR_WARMUP_PAIRS),.I2C_HALF_PERIOD(CONFIG_I2C_HALF),
        .SDR_RESET_HOLD_CYCLES(CONFIG_SDR_WAIT),.SDR_RELEASE_WAIT_CYCLES(CONFIG_SDR_WAIT),
        .SDR_WAKE_CYCLES(CONFIG_SDR_WAKE),.HDR_RESET_HOLD_CYCLES(HDR_RESET_HOLD_CYCLES),
        .HDR_RELEASE_WAIT_CYCLES(HDR_RELEASE_WAIT_CYCLES),.HDR_REGULATOR_WAIT_CYCLES(HDR_REGULATOR_WAIT_CYCLES))
        u_config(.i_clk(i_cfg_clk),.i_rst_n(cfg_release[1]&&!mode_hold),
        .i_start(config_start),.i_clock_locked(i_clock_locked),.i_abort(mode_hold),
        .i_hdr(mode_cfg),.i_sdr_30(slow_mode_cfg),.i_gain_code(i_gain_code),
        .i_source_fault(fault_cfg[1]),.i_pair_event(pair_event_cfg),.i_pair_ok(pair_ok_cfg),
        .o_start_ready(config_start_ready),.o_xclr(sensor_xclr),.o_scl(cam_scl),.io_sda(cam_sda),
        .o_config_written(sensor_done),.o_stable(sensor_stable),.o_error(sensor_error),.o_register_index(),.o_rx_diag_cfg(o_rx_diag_cfg));
    wire [39:0] raw_data;
    wire [31:0] raw_sequence;wire raw_identity_valid;
    wire raw_valid, raw_ready, raw_sof, raw_eol, raw_abort;
    wire pipeline_raw_ready;
    wire phy_ready;
    reg phy_previous;
    reg [31:0] silence_count;
    reg silence_reported;
    reg identity_fault_seen;
    wire [3:0] error_code;
    wire hs_word_clk, delay_ready;
    assign o_rx_diag_word_clk=hs_word_clk;
    wire [7:0] delay_debug;
    wire [5:0] delay_window;
    reg [1:0] delay_sync;
    reg [1:0] delay_capture_wait;

    assign o_config_done = done_sync[1];
    assign o_config_error = error_sync[1];
    assign o_delay_ready = delay_sync[1];
    assign o_phy_ready = phy_ready;
    // 每次停钟或输入静默只发出一次中止，受反压停住的有效数据不属于静默
    // 有限深度 FIFO 的接收溢出由接收器单独处理
    // 检测 CSI 时钟停止或数据静默并上报一次帧中止
    always @(posedge i_pixel_clk) begin
        if (!pixel_reset[1]) begin
            phy_previous <= 0;
            silence_count <= 0;
            silence_reported <= 0;
            receive_fault <= 0;
            identity_fault_seen <= 0;
        end else begin
            phy_previous <= phy_ready;
            receive_fault <= 0;
            // Ordinary frame resynchronization can clear parser loss without
            // a cohort reset. Rearm its edge detector for the next failure.
            identity_fault_seen<=o_source_identity_fault;
            if(o_source_identity_fault&&!identity_fault_seen)receive_fault<=1;
            if (!done_sync[1] || !delay_sync[1] || raw_valid || sdr_event_activity || m_hdr0_valid || m_hdr1_valid) begin
                silence_count <= 0;
                silence_reported <= 0;
            end else if (!silence_reported) begin
                if (silence_count == SILENCE_CYCLES-1) begin
                    receive_fault <= 1;
                    silence_reported <= 1;
                end else silence_count <= silence_count + 1'b1;
            end
            if (phy_previous && !phy_ready) receive_fault <= 1;
        end
    end
    // 公共复位可能在参考时钟停顿时释放，因此先生成异步断言、本地同步释放的复位
    // 在参考时钟域同步释放本地复位
    always @(posedge i_ref_clk or negedge source_reset_n) begin
        if (!source_reset_n) ref_reset <= 0;
        else ref_reset <= {ref_reset[0],1'b1};
    end
    // 配置完成是传感器时钟域的稳定电平，仅在参考域复位释放后进入两级同步器
    // 将传感器配置完成状态同步到参考时钟域
    always @(posedge i_ref_clk or negedge ref_reset[1]) begin
        if (!ref_reset[1]) enable_sync <= 0;
        else enable_sync <= {enable_sync[0],sensor_done};
    end
    // 将配置和延迟校准状态同步到像素时钟域
    always @(posedge i_pixel_clk or negedge source_reset_n) begin
        if (!source_reset_n) begin
            pixel_reset <= 0;
        end else begin
            pixel_reset <= {pixel_reset[0],1'b1};

        end
    end

    // The three status chains use PIX local reset release; their
    // asynchronous data enters only the first synchronizer stage.
    always @(posedge i_pixel_clk or negedge pixel_reset[1]) begin
        if (!pixel_reset[1]) begin done_sync<=0; error_sync<=0; delay_sync<=0; end
        else begin
            done_sync<={done_sync[0],sensor_done};
            error_sync<={error_sync[0],sensor_error};
            delay_sync<={delay_sync[0],delay_ready};
        end
    end

    // The eye-scan fields stop changing before done rises. Capture them once
    // after the synchronized done level has remained high for two pixel clocks.
    always @(posedge i_pixel_clk or negedge pixel_reset[1]) begin
        if (!pixel_reset[1]) begin
            delay_capture_wait <= 0;
            o_delay_debug <= 0;
            o_delay_window <= 0;
            o_delay_status_valid <= 0;
        end else if (!delay_sync[1]) begin
            delay_capture_wait <= 0;
            o_delay_debug <= 0;
            o_delay_window <= 0;
            o_delay_status_valid <= 0;
        end else if (!o_delay_status_valid) begin
            if (delay_capture_wait == 2'd2) begin
                o_delay_debug <= delay_debug;
                o_delay_window <= delay_window;
                o_delay_status_valid <= 1;
            end else delay_capture_wait <= delay_capture_wait + 1'b1;
        end
    end
    real_hdr_physical_csi_rx #(
        .RX_DIAG_ENABLE(RX_DIAG_ENABLE), .EVENT_FIFO_DEPTH(EVENT_FIFO_DEPTH),
        .FRAME_EVENTS_ENABLE(FRAME_EVENTS_ENABLE),.MIPI_LAN(4),.DEVICE("PH1A")) u_receiver (
        .i_ref_clk(i_ref_clk),.i_mipi_clk_p(mipi_clk_hs_rx_p),
        .i_mipi_data_p(mipi_data_hs_p),.i_pixel_clk(i_pixel_clk),
        .i_reset_n(ref_reset[1]),.i_enable(enable_sync[1]),.i_debug_button(1'b1),
        .i_hdr_mode(mode_cfg),.i_hdr_cycle_enable(hdr_written),
        .m_hdr0_data(m_hdr0_data),.m_hdr1_data(m_hdr1_data),.m_hdr0_valid(m_hdr0_valid),.m_hdr1_valid(m_hdr1_valid),
        .m_hdr0_ready(m_hdr0_ready),.m_hdr1_ready(m_hdr1_ready),
        .o_raw_data(raw_data),.o_raw_valid(raw_valid),.i_raw_ready(raw_ready),
        .o_raw_sof(raw_sof),.o_raw_eol(raw_eol), .m_frame_event_valid(m_frame_event_valid), .m_frame_event_ready(m_frame_event_ready),
        .m_frame_event_kind(m_frame_event_kind), .m_frame_event_ok(m_frame_event_ok),
        .m_frame_event_error(m_frame_event_error),
        .m_frame_event_sequence(m_frame_event_sequence),.m_frame_event_identity_valid(m_frame_event_identity_valid),
        .o_source_identity_fault(o_source_identity_fault),.o_rx_diag_word(o_rx_diag_word),
        .o_rx_trace_sample(o_rx_trace_sample),.o_rx_trace_trigger(o_rx_trace_trigger),
        .o_rx_trace_cohort_n(o_rx_trace_cohort_n),.o_rx_trace_enable(o_rx_trace_enable),
        .o_raw_sequence(raw_sequence),.o_raw_identity_valid(raw_identity_valid),
        .o_frame_abort(raw_abort),
        .o_error_code(error_code),.o_header_ecc_error_count(o_ecc_errors),
        .o_payload_crc_error_count(o_crc_errors),.o_overflow_error_count(o_overflows),
        .o_length_error_count(o_format_errors),.o_hs_word_clk(hs_word_clk),
        .o_auto_delay_done(delay_ready),.o_delay_debug(delay_debug),
        .o_delay_window(delay_window),.o_phy_ready(phy_ready),
        .o_diag_lane_bytes(),.o_diag_lane_valid(),.o_diag_aligned_word(),.o_diag_aligned_valid(),
        .o_diag_geared_word(),.o_diag_geared_valid(),.o_diag_wait_sync(),.o_diag_packet_done(),
        .o_diag_publish_enable(),.o_diag_word_reset_n()
    );
