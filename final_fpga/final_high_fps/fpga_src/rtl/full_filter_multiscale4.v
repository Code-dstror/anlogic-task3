// Private single-frame context owner; borrowed helpers cannot outlive this owner.
// F22 reuses the native Gaussian tap; each lower scale retains two prior Y rows.
// Observation/record consumers never control pixel ready, RAM CE or reset.
module full_filter_multiscale4 #(parameter integer WINDOW_STRIP_ENABLE=0, FIXED1080P_ENABLE=0) (
    input wire clk,rst_n,cancel,
    input wire start_valid,
    output wire start_ready,
    input wire [12:0] start_width,start_height,
    input wire [10:0] start_threshold,
    input wire [159:0] start_context,
    input wire s_valid,
    output wire s_ready,
    input wire s_window_valid,
    input wire [(WINDOW_STRIP_ENABLE ? 144 : 288)-1:0] s_window,
    input wire [31:0] s_filtered_y,
    input wire [3:0] s_keep,
    input wire s_sof,s_eol,source_error,
    output wire record_valid,record_pending,
    input wire record_ready,
    output wire [683:0] record_data,
    output reg frame_complete,frame_error,
    output reg [7:0] frame_error_code,
    output wire [159:0] frame_event_context,
    output wire full_event_valid,
    output wire [220:0] full_event_metadata,
    output wire [31:0] full_event_filtered_y,
    output wire [43:0] full_event_gx,full_event_gy,full_event_magnitude,
    output wire [12:0] full_event_native_x,full_event_native_y,
    output wire low_event_valid,
    output wire [220:0] low_event_metadata,
    output wire [31:0] low_event_filtered_y,
    output wire [31:0] low_event_center_y,
    output wire [43:0] low_event_gx,low_event_gy,low_event_magnitude,
    output wire [12:0] low_event_native_x,low_event_native_y,
    input wire debug_poll,debug_clear_firstfault,
    output reg [31:0] debug_poll_count,record_drop_count,completed_count,failed_count,native_stall_count,
    output reg [7:0] firstfault_code,
    output reg [159:0] firstfault_context,first_congestion_context,
    output reg [2:0] max_low_resident,
    output reg [1:0] max_grant_wait
);
    localparam [1:0] ST_IDLE=0,ST_RUN=1,ST_TAIL=2;
    reg [1:0] state;
    reg clear_pipeline;
    // This service already rejects every other geometry when fixed mode
    // is enabled. The rejected-START record still reports its original inputs.
    localparam integer NATIVE_BITS=FIXED1080P_ENABLE ? 11 : 13;
    reg [12:0] width,height;
    reg [NATIVE_BITS-1:0] native_x_n,native_y_n;
    wire [12:0] native_x=native_x_n,native_y=native_y_n;
    reg [10:0] threshold;
    reg [159:0] frame_context;
    wire [12:0] half_width=(width+1'b1)>>1,half_height=(height+1'b1)>>1;
    wire [12:0] quarter_width=(half_width+1'b1)>>1,quarter_height=(half_height+1'b1)>>1;
    wire run=rst_n&&!cancel&&!clear_pipeline;
    wire pipe_cancel=cancel||clear_pipeline;
    assign start_ready=run&&state==ST_IDLE;
    wire start_fire=start_valid&&start_ready;
    wire bad_start=start_width<4||start_width>3840||start_width[1:0]!=0||
        start_height==0||start_height>2160||start_threshold>2040||
        (FIXED1080P_ENABLE&&(start_width!=13'd1920||start_height!=13'd1080));
    wire good_start=start_fire&&!bad_start;
    assign frame_event_context=frame_context;
    wire [12:0] starting_half_width=FIXED1080P_ENABLE ? 13'd960 : (start_width+1'b1)>>1;
    wire [12:0] starting_half_height=FIXED1080P_ENABLE ? 13'd540 : (start_height+1'b1)>>1;

    reg half_group_valid,quarter_group_valid;
    reg [31:0] half_group_data,quarter_group_data;
    reg [3:0] half_group_keep,quarter_group_keep;
    reg half_group_sof,half_group_eol,half_group_eof;
    reg quarter_group_sof,quarter_group_eol,quarter_group_eof;
    reg [15:0] half_carry;
    reg half_carry_valid;
    reg [31:0] quarter_carry;
    reg [2:0] quarter_carry_count;
    localparam integer HALF_BITS=FIXED1080P_ENABLE ? 10 : 13;
    localparam integer QUARTER_BITS=FIXED1080P_ENABLE ? 9 : 13;
    reg [HALF_BITS-1:0] half_input_x,half_input_y;
    reg [QUARTER_BITS-1:0] quarter_input_x,quarter_input_y;
    wire half_input_ready,quarter_input_ready;
    wire half_window_valid,quarter_window_valid,half_window_ready,quarter_window_ready;
    wire half_window_pending,quarter_window_pending;
    wire [287:0] half_window,quarter_window;
    wire [218:0] half_metadata,quarter_metadata;
    wire half_done,quarter_done,half_error,quarter_error;
    full_filter_y_window4 #(.FIXED_WIDTH(FIXED1080P_ENABLE ? 960 : 0),
        .FIXED_HEIGHT(FIXED1080P_ENABLE ? 540 : 0)) half_service(.clk(clk),.rst_n(rst_n),.cancel(pipe_cancel),
        .start_valid(good_start),.start_ready(),.start_width(starting_half_width),.start_height(starting_half_height),
        .i_frame_context(frame_context),.s_valid(half_group_valid),.s_ready(half_input_ready),
        .s_data(half_group_data),.s_keep(half_group_keep),.s_sof(half_group_sof),.s_eol(half_group_eol),
        .s_eof(half_group_eof),.m_valid(half_window_valid),.window_pending(half_window_pending),.m_ready(half_window_ready),
        .m_window(half_window),.m_metadata(half_metadata),.done(half_done),.error(half_error));
    full_filter_y_window4 #(.MAX_WIDTH(960),.MAX_HEIGHT(540),
        .FIXED_WIDTH(FIXED1080P_ENABLE ? 480 : 0),
        .FIXED_HEIGHT(FIXED1080P_ENABLE ? 270 : 0)) quarter_service(
        .clk(clk),.rst_n(rst_n),.cancel(pipe_cancel),.start_valid(good_start),.start_ready(),
        .start_width((starting_half_width+1'b1)>>1),.start_height((starting_half_height+1'b1)>>1),
        .i_frame_context(frame_context),.s_valid(quarter_group_valid),.s_ready(quarter_input_ready),
        .s_data(quarter_group_data),.s_keep(quarter_group_keep),.s_sof(quarter_group_sof),
        .s_eol(quarter_group_eol),.s_eof(quarter_group_eof),.m_valid(quarter_window_valid),
        .window_pending(quarter_window_pending),.m_ready(quarter_window_ready),.m_window(quarter_window),.m_metadata(quarter_metadata),
        .done(quarter_done),.error(quarter_error));
    wire arb_valid,arb_ready;
    wire [287:0] arb_window;
    wire [220:0] arb_metadata;
    wire half_admitted,half_arb_ready;
    // The arbiter masks VALID/READY with pipe_cancel itself. Its choice must
    // depend only on held producer ownership, not on the combinational fault
    // cone that suppresses both public VALIDs during cancel.
    wire half_arb_valid=half_window_pending&&half_admitted;
    assign half_window_ready=half_arb_ready&&half_admitted;
    preprocess_scale_arbiter4 arbiter(.clk(clk),.rst_n(rst_n),.cancel(pipe_cancel),
        .s_half_valid(half_arb_valid),.s_half_ready(half_arb_ready),
        .s_half_window(half_window),.s_half_metadata(half_metadata),
        .s_quarter_valid(quarter_window_pending),.s_quarter_ready(quarter_window_ready),
        .s_quarter_window(quarter_window),.s_quarter_metadata(quarter_metadata),
        .m_valid(arb_valid),.m_ready(arb_ready),.m_window(arb_window),.m_metadata(arb_metadata));
    wire full_ready,full_valid,low_valid,low_ready;
    wire native_last=native_x==width-4&&native_y==height-1'b1;
    wire emit_half=!native_y[0]&&(half_carry_valid||s_eol);
    assign s_ready=run&&state==ST_RUN&&full_ready&&(!emit_half||!half_group_valid||half_input_ready);
    wire input_fire=s_valid&&s_ready;
    wire [7:0] input_error=s_keep!=4'hf ? 8'd2 :
        (s_sof!=(native_x==0&&native_y==0)||s_eol!=(native_x==width-4)) ? 8'd3 :
        !s_window_valid ? 8'd4 : 8'd0;
    wire take_native=input_fire&&input_error==0&&!source_error;
    // Expand only beside the native consumer; lower-scale windows are intact.
    wire [287:0] native_window;
    generate if(WINDOW_STRIP_ENABLE)begin:g_native_strip
        genvar native_lane,native_row,native_column;
        for(native_lane=0;native_lane<4;native_lane=native_lane+1)begin:g_lane
            for(native_row=0;native_row<3;native_row=native_row+1)begin:g_row
                for(native_column=0;native_column<3;native_column=native_column+1)begin:g_column
                    assign native_window[native_lane*72+native_row*24+native_column*8 +:8] =
                        s_window[(native_row*6+native_lane+native_column)*8 +:8];
                end
            end
        end
    end else begin:g_native_legacy
        assign native_window=s_window;
    end endgenerate
    full_filter_sobel4 #(.FILTER_ENABLE(0)) native_math(.clk(clk),.rst_n(rst_n),.cancel(pipe_cancel),
        .s_valid(take_native),.s_ready(full_ready),.s_window(native_window),.s_filtered_y(s_filtered_y),
        .s_keep(4'hf),.s_scale(2'd0),.s_width(width),.s_height(height),.s_x(native_x),.s_y(native_y),
        .s_sof(s_sof),.s_eol(s_eol),.s_eof(native_last),.i_frame_context(frame_context),
        .m_valid(full_valid),.m_ready(1'b1),.m_gx(full_event_gx),.m_gy(full_event_gy),
        .m_magnitude(full_event_magnitude),.m_filtered_y(full_event_filtered_y),.m_center_y(),
        .m_keep(full_event_metadata[6:3]),.m_scale(full_event_metadata[60:59]),
        .m_width(full_event_metadata[58:46]),.m_height(full_event_metadata[45:33]),
        .m_x(full_event_metadata[32:20]),.m_y(full_event_metadata[19:7]),
        .m_sof(full_event_metadata[2]),.m_eol(full_event_metadata[1]),.m_eof(full_event_metadata[0]),
        .m_context(full_event_metadata[220:61]));
    full_filter_sobel4 lower_math(.clk(clk),.rst_n(rst_n),.cancel(pipe_cancel),
        .s_valid(arb_valid),.s_ready(arb_ready),.s_window(arb_window),.s_filtered_y(32'd0),
        .s_keep(arb_metadata[6:3]),.s_scale(arb_metadata[60:59]),.s_width(arb_metadata[58:46]),
        .s_height(arb_metadata[45:33]),.s_x(arb_metadata[32:20]),.s_y(arb_metadata[19:7]),
        .s_sof(arb_metadata[2]),.s_eol(arb_metadata[1]),.s_eof(arb_metadata[0]),.i_frame_context(frame_context),
        .m_valid(low_valid),.m_ready(low_ready),.m_gx(low_event_gx),.m_gy(low_event_gy),
        .m_magnitude(low_event_magnitude),.m_filtered_y(low_event_filtered_y),.m_center_y(low_event_center_y),
        .m_keep(low_event_metadata[6:3]),.m_scale(low_event_metadata[60:59]),
        .m_width(low_event_metadata[58:46]),.m_height(low_event_metadata[45:33]),
        .m_x(low_event_metadata[32:20]),.m_y(low_event_metadata[19:7]),
        .m_sof(low_event_metadata[2]),.m_eol(low_event_metadata[1]),.m_eof(low_event_metadata[0]),
        .m_context(low_event_metadata[220:61]));
    // Fork the two decimated Gaussian samples directly from the held half window.
    // The shared arithmetic output has no feedback into its own input ready.
    wire select_half_row=!half_metadata[7];
    wire [2:0] quarter_added=half_metadata[5] ? 3'd2 : 3'd1;
    wire [2:0] quarter_next_count=quarter_carry_count+quarter_added;
    wire emit_quarter=select_half_row&&(quarter_next_count>=4||half_metadata[1]);
    // Admission uses registered capacity only. Do not use same-cycle downstream
    // quarter ready here: it can depend on this arbiter's selected producer.
    assign half_admitted=!emit_quarter||!quarter_group_valid;
    wire take_half=half_window_valid&&half_window_ready;
    assign low_ready=1'b1;
    assign full_event_valid=run&&state!=ST_IDLE&&full_valid;
    assign low_event_valid=run&&state!=ST_IDLE&&low_valid&&low_ready;
    assign full_event_native_x=full_event_metadata[32:20];
    assign full_event_native_y=full_event_metadata[19:7];
    assign low_event_native_x=low_event_metadata[32:20]<<low_event_metadata[60:59];
    assign low_event_native_y=low_event_metadata[19:7]<<low_event_metadata[60:59];

    function [23:0] area;
        input [12:0] w,h;
        integer bit_index;
        begin area=0;for(bit_index=0;bit_index<13;bit_index=bit_index+1)
            if(h[bit_index]) area=area+({11'd0,w}<<bit_index);end
    endfunction
    function [55:0] summarize;
        input [3:0] keep;
        input [43:0] magnitudes;
        input [12:0] x,y;
        input [10:0] limit;
        reg [2:0] pixels,strong_pixels;
        reg [12:0] sum,peak_x;
        reg [10:0] peak,mag0,mag1,mag2,mag3,peak01,peak23;
        reg [11:0] sum01,sum23;
        reg lane01,lane23;
        reg [1:0] peak_lane;
        begin
            mag0=keep[0] ? magnitudes[0+:11] : 11'd0;
            mag1=keep[1] ? magnitudes[11+:11] : 11'd0;
            mag2=keep[2] ? magnitudes[22+:11] : 11'd0;
            mag3=keep[3] ? magnitudes[33+:11] : 11'd0;
            pixels={2'd0,keep[0]}+{2'd0,keep[1]}+{2'd0,keep[2]}+{2'd0,keep[3]};
            strong_pixels={2'd0,(keep[0]&&mag0>=limit)}+{2'd0,(keep[1]&&mag1>=limit)}+
                {2'd0,(keep[2]&&mag2>=limit)}+{2'd0,(keep[3]&&mag3>=limit)};
            sum01={1'b0,mag0}+{1'b0,mag1};sum23={1'b0,mag2}+{1'b0,mag3};
            sum={1'b0,sum01}+{1'b0,sum23};
            // Balanced strict-greater tree keeps the first lane on a tie,
            // including the original x result when every magnitude is zero.
            lane01=mag1>mag0;lane23=mag3>mag2;
            peak01=lane01 ? mag1 : mag0;peak23=lane23 ? mag3 : mag2;
            peak_lane=peak23>peak01 ? {1'b1,lane23} : {1'b0,lane01};
            peak=peak23>peak01 ? peak23 : peak01;
            peak_x=x+{11'd0,peak_lane};
            summarize={pixels,strong_pixels,sum,peak,peak_x,y};
        end
    endfunction
    function [31:0] increment;
        input [31:0] value;
        begin increment=value==32'hffffffff ? value : value+1'b1;end
    endfunction
    function [7:0] gaussian_sample;
        input [71:0] window;
        reg [11:0] total;
        begin
            total={4'b0,window[7:0]}+{3'b0,window[15:8],1'b0}+{4'b0,window[23:16]}+
                {3'b0,window[31:24],1'b0}+{2'b0,window[39:32],2'b0}+{3'b0,window[47:40],1'b0}+
                {4'b0,window[55:48]}+{3'b0,window[63:56],1'b0}+{4'b0,window[71:64]}+12'd8;
            gaussian_sample=total[11:4];
        end
    endfunction
    // Counts cannot exceed the already-checked scale area. Sobel magnitude
    // is at most 2040; the largest valid sum is 4,230,144,000 (<2^32).
    localparam integer C0=FIXED1080P_ENABLE ? 21 : 24;
    localparam integer C1=FIXED1080P_ENABLE ? 19 : 24;
    localparam integer C2=FIXED1080P_ENABLE ? 17 : 24;
    localparam integer G0=FIXED1080P_ENABLE ? 32 : 34;
    localparam integer G1=FIXED1080P_ENABLE ? 30 : 34;
    localparam integer G2=FIXED1080P_ENABLE ? 28 : 34;
    reg [C0-1:0] pixels0,strong_total0;
    reg [C1-1:0] pixels1,strong_total1;
    reg [C2-1:0] pixels2,strong_total2;
    reg [G0-1:0] gradient0;
    reg [G1-1:0] gradient1;
    reg [G2-1:0] gradient2;
    wire [23:0] pixels_seen [0:2],strong_count [0:2];
    wire [33:0] gradient_sum [0:2];
    assign pixels_seen[0]=pixels0;assign pixels_seen[1]=pixels1;assign pixels_seen[2]=pixels2;
    assign strong_count[0]=strong_total0;assign strong_count[1]=strong_total1;assign strong_count[2]=strong_total2;
    assign gradient_sum[0]=gradient0;assign gradient_sum[1]=gradient1;assign gradient_sum[2]=gradient2;
    reg [10:0] peak_gradient [0:2];
    reg [12:0] peak_x [0:2],peak_y [0:2];
    reg [2:0] eof_seen,full_outstanding,low_outstanding;
    reg [1:0] window_done,half_wait,quarter_wait;
    wire [1:0] low_scale=low_event_metadata[60:59];
    // Scale 0/3 raises count_bad before any update. The shared low-scale
    // accumulator therefore reads only the half or quarter context.
    wire [23:0] low_pixels=low_scale[1] ? pixels_seen[2] : pixels_seen[1];
    wire [23:0] low_strong=low_scale[1] ? strong_count[2] : strong_count[1];
    wire [33:0] low_gradient=low_scale[1] ? gradient_sum[2] : gradient_sum[1];
    wire [10:0] low_peak=low_scale[1] ? peak_gradient[2] : peak_gradient[1];
    // The winning magnitude/coordinate tree remains unchanged. Strictly
    // exceeding the historical maximum is equivalent to any kept lane doing
    // so; evaluate that one-bit write predicate in parallel with the tree.
    wire [3:0] full_peak_exceeds,low_peak_exceeds;
    genvar peak_lane;
    generate for(peak_lane=0;peak_lane<4;peak_lane=peak_lane+1)begin:g_peak_write
        assign full_peak_exceeds[peak_lane]=full_event_metadata[3+peak_lane] &&
            full_event_magnitude[peak_lane*11+:11]>peak_gradient[0];
        assign low_peak_exceeds[peak_lane]=low_event_metadata[3+peak_lane] &&
            low_event_magnitude[peak_lane*11+:11]>low_peak;
    end endgenerate
    wire [55:0] full_summary=summarize(full_event_metadata[6:3],full_event_magnitude,
        full_event_metadata[32:20],full_event_metadata[19:7],threshold);
    wire [55:0] low_summary=summarize(low_event_metadata[6:3],low_event_magnitude,
        low_event_metadata[32:20],low_event_metadata[19:7],threshold);
    wire [23:0] native_area,half_area,quarter_area;
    // The HD service explicitly owns this profile. General callers retain the
    // original area function and acceptance set; no pixel preparation cycle.
    generate if(FIXED1080P_ENABLE)begin:g_fixed1080p_area
        assign native_area=24'd2073600; // 1920 x 1080
        assign half_area=24'd518400;   // 960 x 540
        assign quarter_area=24'd129600;// 480 x 270
    end else begin:g_generic_area
        assign native_area=area(width,height);
        assign half_area=area(half_width,half_height);
        assign quarter_area=area(quarter_width,quarter_height);
    end endgenerate
    wire [23:0] expected_low=low_scale==1 ? half_area : quarter_area;
    wire count_bad=(full_event_valid&&(pixels_seen[0]+full_summary[55:53]>native_area||
        (full_event_metadata[0]&&pixels_seen[0]+full_summary[55:53]!=native_area))) ||
        (low_event_valid&&(low_scale==0||low_scale==3||low_pixels+low_summary[55:53]>expected_low||
        (low_event_metadata[0]&&low_pixels+low_summary[55:53]!=expected_low)));
    wire [7:0] fault_code=source_error ? 8'd5 : input_fire&&input_error!=0 ? input_error :
        (half_error||quarter_error||count_bad) ? 8'd6 : 8'd0;
    wire finish_frame=state==ST_TAIL&&eof_seen==7&&window_done==3&&
        full_outstanding==0&&low_outstanding==0&&!half_group_valid&&!quarter_group_valid&&
        !half_carry_valid&&quarter_carry_count==0;
    wire [145:0] stat0={width,height,pixels_seen[0],strong_count[0],gradient_sum[0],
        peak_gradient[0],peak_x[0],peak_y[0],peak_gradient[0]>=threshold};
    wire [145:0] stat1={half_width,half_height,pixels_seen[1],strong_count[1],gradient_sum[1],
        peak_gradient[1],peak_x[1],peak_y[1],peak_gradient[1]>=threshold};
    wire [145:0] stat2={quarter_width,quarter_height,pixels_seen[2],strong_count[2],gradient_sum[2],
        peak_gradient[2],peak_x[2],peak_y[2],peak_gradient[2]>=threshold};
    wire half_wins=peak_gradient[1]>peak_gradient[0];
    wire [10:0] first_peak=half_wins ? peak_gradient[1] : peak_gradient[0];
    wire quarter_wins=peak_gradient[2]>first_peak;
    wire [1:0] fused_scale=quarter_wins ? 2'd2 : half_wins ? 2'd1 : 2'd0;
    wire [10:0] fused_peak=quarter_wins ? peak_gradient[2] : first_peak;
    // Constant shifts preserve the original thirteen-bit truncation.
    wire [12:0] fused_x=quarter_wins ? {peak_x[2][10:0],2'b0} :
        half_wins ? {peak_x[1][11:0],1'b0} : peak_x[0];
    wire [12:0] fused_y=quarter_wins ? {peak_y[2][10:0],2'b0} :
        half_wins ? {peak_y[1][11:0],1'b0} : peak_y[0];
    wire [39:0] fused={fused_scale,fused_peak,fused_x,fused_y,fused_peak>=threshold};
    wire [683:0] success_record={frame_context,1'b1,8'd0,width,height,threshold,stat0,stat1,stat2,fused};
    wire [2:0] low_resident=low_outstanding+{2'b0,half_window_valid}+{2'b0,quarter_window_valid};
    // One complete result owns all eighteen ERAM words. This is deliberately
    // parallel storage: no wide FF reconstruction and no pixel-rate RAM port.
    // Write and read occur on distinct clocks, so no same-address collision.
    wire record_slot_free;
    wire publish_bad_start = start_fire && bad_start;
    wire publish_fault = !start_fire && state != ST_IDLE && fault_code != 0;
    wire publish_success = !start_fire && !publish_fault && run &&
        state != ST_IDLE && finish_frame;
    wire record_write = rst_n && !cancel && record_slot_free &&
        (publish_bad_start || publish_fault || publish_success);
    wire [683:0] record_write_data = publish_bad_start ?
        {start_context,1'b0,8'd1,start_width,start_height,start_threshold,438'd0,40'd0} :
        publish_fault ? {frame_context,1'b0,fault_code,width,height,threshold,438'd0,40'd0} :
        success_record;
    parallel_result_eram #(.WIDTH(684)) result_store(
        .clk(clk),.rst_n(rst_n),.cancel(cancel),
        .s_valid(record_write),.s_ready(record_slot_free),.s_data(record_write_data),
        .m_valid(record_valid),.o_pending(record_pending),.m_ready(record_ready),.m_data(record_data));
    task publish;
        input [683:0] value;
        begin
            if(record_slot_free) begin end
            else begin
                record_drop_count<=increment(record_drop_count);
                if(record_drop_count==0) first_congestion_context<=value[683:524];
                if(firstfault_code==0) begin firstfault_code<=8'h80;firstfault_context<=value[683:524];end
            end
        end
    endtask
    integer stats_index;
    wire [31:0] picked_quarter={16'd0,gaussian_sample(half_window[215:144]),gaussian_sample(half_window[71:0])};
    wire [31:0] combined_quarter=quarter_carry|(picked_quarter<<(quarter_carry_count*8));
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=ST_IDLE;clear_pipeline<=0;frame_complete<=0;frame_error<=0;
            frame_error_code<=0;debug_poll_count<=0;record_drop_count<=0;completed_count<=0;failed_count<=0;
            native_stall_count<=0;firstfault_code<=0;firstfault_context<=0;first_congestion_context<=0;
            max_low_resident<=0;max_grant_wait<=0;half_wait<=0;quarter_wait<=0;
            half_group_valid<=0;quarter_group_valid<=0;half_carry_valid<=0;quarter_carry_count<=0;quarter_carry<=0;
            full_outstanding<=0;low_outstanding<=0;eof_seen<=0;window_done<=0;
        end else begin
            clear_pipeline<=0;frame_complete<=0;frame_error<=0;
            
            if(debug_poll) debug_poll_count<=increment(debug_poll_count);
            if(debug_clear_firstfault) begin firstfault_code<=0;firstfault_context<=0;end
            if(cancel) begin
                state<=ST_IDLE;half_group_valid<=0;quarter_group_valid<=0;
                half_carry_valid<=0;quarter_carry_count<=0;quarter_carry<=0;full_outstanding<=0;low_outstanding<=0;
            end else if(start_fire) begin
                width<=FIXED1080P_ENABLE ? 13'd1920 : start_width;
                height<=FIXED1080P_ENABLE ? 13'd1080 : start_height;
                threshold<=start_threshold;frame_context<=start_context;
                native_x_n<=0;native_y_n<=0;half_input_x<=0;half_input_y<=0;quarter_input_x<=0;quarter_input_y<=0;
                half_group_valid<=0;quarter_group_valid<=0;half_carry_valid<=0;quarter_carry_count<=0;quarter_carry<=0;
                full_outstanding<=0;low_outstanding<=0;eof_seen<=0;window_done<=0;half_wait<=0;quarter_wait<=0;
                pixels0<=0;pixels1<=0;pixels2<=0;strong_total0<=0;strong_total1<=0;strong_total2<=0;
                gradient0<=0;gradient1<=0;gradient2<=0;
                for(stats_index=0;stats_index<3;stats_index=stats_index+1) begin
                    peak_gradient[stats_index]<=0;peak_x[stats_index]<=0;peak_y[stats_index]<=0;
                end
                if(bad_start) begin
                    state<=ST_IDLE;frame_error<=1;frame_error_code<=1;failed_count<=increment(failed_count);
                    publish({start_context,1'b0,8'd1,start_width,start_height,start_threshold,438'd0,40'd0});
                    if(firstfault_code==0) begin firstfault_code<=1;firstfault_context<=start_context;end
                end else state<=ST_RUN;
            end else if(state!=ST_IDLE&&fault_code!=0) begin
                state<=ST_IDLE;clear_pipeline<=1;frame_error<=1;frame_error_code<=fault_code;
                failed_count<=increment(failed_count);half_group_valid<=0;quarter_group_valid<=0;
                half_carry_valid<=0;quarter_carry_count<=0;quarter_carry<=0;full_outstanding<=0;low_outstanding<=0;
                publish({frame_context,1'b0,fault_code,width,height,threshold,438'd0,40'd0});
                if(firstfault_code==0) begin firstfault_code<=fault_code;firstfault_context<=frame_context;end
            end else if(run&&state!=ST_IDLE) begin
                if(s_valid&&!s_ready&&state==ST_RUN) native_stall_count<=increment(native_stall_count);
                if(low_resident>max_low_resident) max_low_resident<=low_resident;
                if(half_done) window_done[0]<=1;
                if(quarter_done) window_done[1]<=1;
                case({take_native,full_event_valid})
                    2'b10:full_outstanding<=full_outstanding+1'b1;
                    2'b01:full_outstanding<=full_outstanding-1'b1;
                endcase
                case({arb_valid&&arb_ready,low_event_valid})
                    2'b10:low_outstanding<=low_outstanding+1'b1;
                    2'b01:low_outstanding<=low_outstanding-1'b1;
                endcase
                if(arb_valid&&arb_ready) begin
                    if(half_arb_valid&&!half_arb_ready) begin
                        half_wait<=half_wait+1'b1;if(half_wait+1'b1>max_grant_wait) max_grant_wait<=half_wait+1'b1;
                    end else half_wait<=0;
                    if(quarter_window_valid&&!quarter_window_ready) begin
                        quarter_wait<=quarter_wait+1'b1;if(quarter_wait+1'b1>max_grant_wait) max_grant_wait<=quarter_wait+1'b1;
                    end else quarter_wait<=0;
                end
                if(half_group_valid&&half_input_ready) half_group_valid<=0;
                if(quarter_group_valid&&quarter_input_ready) quarter_group_valid<=0;
                if(take_native) begin
                    if(!native_y[0]) begin
                        if(emit_half) begin
                            half_group_valid<=1;
                            half_group_data<=half_carry_valid ?
                                {s_filtered_y[23:16],s_filtered_y[7:0],half_carry} :
                                {16'd0,s_filtered_y[23:16],s_filtered_y[7:0]};
                            half_group_keep<=half_carry_valid ? 4'hf : 4'h3;
                            half_group_sof<=half_input_x==0&&half_input_y==0;
                            half_group_eol<=s_eol;
                            half_group_eof<=s_eol&&native_y==((height-1'b1)&13'h1ffe);
                            half_carry_valid<=0;
                            if(s_eol) begin half_input_x<=0;half_input_y<=half_input_y+1'b1;end
                            else half_input_x<=half_input_x+13'd4;
                        end else begin half_carry<={s_filtered_y[23:16],s_filtered_y[7:0]};half_carry_valid<=1;end
                    end
                    if(s_eol) begin native_x_n<=0;native_y_n<=native_y+1'b1;end else native_x_n<=native_x+13'd4;
                    if(native_last) state<=ST_TAIL;
                end
                if(take_half&&select_half_row) begin
                    if(emit_quarter) begin
                        quarter_group_valid<=1;quarter_group_data<=combined_quarter;
                        quarter_group_keep<=(4'h1<<quarter_next_count)-4'd1;
                        quarter_group_sof<=quarter_input_x==0&&quarter_input_y==0;
                        quarter_group_eol<=half_metadata[1];
                        quarter_group_eof<=half_metadata[1]&&half_metadata[19:7]==((half_height-1'b1)&13'h1ffe);
                        quarter_carry<=0;quarter_carry_count<=0;
                        if(half_metadata[1]) begin quarter_input_x<=0;quarter_input_y<=quarter_input_y+1'b1;end
                        else quarter_input_x<=quarter_input_x+13'd4;
                    end else begin quarter_carry<=combined_quarter;quarter_carry_count<=quarter_next_count;end
                end
                if(full_event_valid) begin
                    pixels0<=pixels0+full_summary[55:53];strong_total0<=strong_total0+full_summary[52:50];
                    gradient0<=gradient0+full_summary[49:37];
                    if(|full_peak_exceeds) begin
                        peak_gradient[0]<=full_summary[36:26];peak_x[0]<=full_summary[25:13];peak_y[0]<=full_summary[12:0];end
                    if(full_event_metadata[0]) eof_seen[0]<=1;
                end
                if(low_event_valid) begin
                    if(low_scale[1]) begin
                        pixels2<=low_pixels+low_summary[55:53];
                        strong_total2<=low_strong+low_summary[52:50];
                        gradient2<=low_gradient+low_summary[49:37];
                        if(|low_peak_exceeds) begin
                            peak_gradient[2]<=low_summary[36:26];peak_x[2]<=low_summary[25:13];peak_y[2]<=low_summary[12:0];end
                        if(low_event_metadata[0]) eof_seen[2]<=1;
                    end else begin
                        pixels1<=low_pixels+low_summary[55:53];
                        strong_total1<=low_strong+low_summary[52:50];
                        gradient1<=low_gradient+low_summary[49:37];
                        if(|low_peak_exceeds) begin
                            peak_gradient[1]<=low_summary[36:26];peak_x[1]<=low_summary[25:13];peak_y[1]<=low_summary[12:0];end
                        if(low_event_metadata[0]) eof_seen[1]<=1;
                    end
                end
                if(finish_frame) begin
                    state<=ST_IDLE;frame_complete<=1;completed_count<=increment(completed_count);publish(success_record);
                end
            end
        end
    end
endmodule
