// F22 real Y pyramid: reuse native Gaussian tap; six logical official row banks.
// Observation/record consumers never control pixel ready, RAM CE or reset.
module preprocess_multiscale4 (
    input wire clk,rst_n,cancel,
    input wire start_valid,
    output wire start_ready,
    input wire [12:0] start_width,start_height,
    input wire [10:0] start_threshold,
    input wire [159:0] start_context,
    input wire s_valid,
    output wire s_ready,
    input wire s_window_valid,
    input wire [287:0] s_window,
    input wire [31:0] s_filtered_y,
    input wire [3:0] s_keep,
    input wire s_sof,s_eol,source_error,
    output reg record_valid,
    input wire record_ready,
    output reg [683:0] record_data,
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
    reg [12:0] width,height,native_x,native_y;
    reg [10:0] threshold;
    reg [159:0] frame_context;
    wire [12:0] half_width=(width+1'b1)>>1,half_height=(height+1'b1)>>1;
    wire [12:0] quarter_width=(half_width+1'b1)>>1,quarter_height=(half_height+1'b1)>>1;
    wire run=rst_n&&!cancel&&!clear_pipeline;
    wire pipe_cancel=cancel||clear_pipeline;
    assign start_ready=run&&state==ST_IDLE;
    wire start_fire=start_valid&&start_ready;
    wire bad_start=start_width<4||start_width>3840||start_width[1:0]!=0||
        start_height==0||start_height>2160||start_threshold>2040;
    wire good_start=start_fire&&!bad_start;
    assign frame_event_context=frame_context;
    wire [12:0] starting_half_width=(start_width+1'b1)>>1;
    wire [12:0] starting_half_height=(start_height+1'b1)>>1;

    reg half_group_valid,quarter_group_valid;
    reg [31:0] half_group_data,quarter_group_data;
    reg [3:0] half_group_keep,quarter_group_keep;
    reg half_group_sof,half_group_eol,half_group_eof;
    reg quarter_group_sof,quarter_group_eol,quarter_group_eof;
    reg [15:0] half_carry;
    reg half_carry_valid;
    reg [31:0] quarter_carry;
    reg [2:0] quarter_carry_count;
    reg [12:0] half_input_x,half_input_y,quarter_input_x,quarter_input_y;
    wire half_input_ready,quarter_input_ready;
    wire half_window_valid,quarter_window_valid,half_window_ready,quarter_window_ready;
    wire [287:0] half_window,quarter_window;
    wire [218:0] half_metadata,quarter_metadata;
    wire half_done,quarter_done,half_error,quarter_error;
    preprocess_y_window4 half_service(.clk(clk),.rst_n(rst_n),.cancel(pipe_cancel),
        .start_valid(good_start),.start_ready(),.start_width(starting_half_width),.start_height(starting_half_height),
        .start_context(start_context),.s_valid(half_group_valid),.s_ready(half_input_ready),
        .s_data(half_group_data),.s_keep(half_group_keep),.s_sof(half_group_sof),.s_eol(half_group_eol),
        .s_eof(half_group_eof),.m_valid(half_window_valid),.m_ready(half_window_ready),
        .m_window(half_window),.m_metadata(half_metadata),.done(half_done),.error(half_error));
    preprocess_y_window4 #(.MAX_WIDTH(960),.MAX_HEIGHT(540)) quarter_service(
        .clk(clk),.rst_n(rst_n),.cancel(pipe_cancel),.start_valid(good_start),.start_ready(),
        .start_width((starting_half_width+1'b1)>>1),.start_height((starting_half_height+1'b1)>>1),
        .start_context(start_context),.s_valid(quarter_group_valid),.s_ready(quarter_input_ready),
        .s_data(quarter_group_data),.s_keep(quarter_group_keep),.s_sof(quarter_group_sof),
        .s_eol(quarter_group_eol),.s_eof(quarter_group_eof),.m_valid(quarter_window_valid),
        .m_ready(quarter_window_ready),.m_window(quarter_window),.m_metadata(quarter_metadata),
        .done(quarter_done),.error(quarter_error));
    wire arb_valid,arb_ready;
    wire [287:0] arb_window;
    wire [220:0] arb_metadata;
    wire half_admitted,half_arb_ready;
    wire half_arb_valid=half_window_valid&&half_admitted;
    assign half_window_ready=half_arb_ready&&half_admitted;
    preprocess_scale_arbiter4 arbiter(.clk(clk),.rst_n(rst_n),.cancel(pipe_cancel),
        .s_half_valid(half_arb_valid),.s_half_ready(half_arb_ready),
        .s_half_window(half_window),.s_half_metadata(half_metadata),
        .s_quarter_valid(quarter_window_valid),.s_quarter_ready(quarter_window_ready),
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
    preprocess_sobel4 #(.FILTER_ENABLE(0)) native_math(.clk(clk),.rst_n(rst_n),.cancel(pipe_cancel),
        .s_valid(take_native),.s_ready(full_ready),.s_window(s_window),.s_filtered_y(s_filtered_y),
        .s_keep(4'hf),.s_scale(2'd0),.s_width(width),.s_height(height),.s_x(native_x),.s_y(native_y),
        .s_sof(s_sof),.s_eol(s_eol),.s_eof(native_last),.s_context(frame_context),
        .m_valid(full_valid),.m_ready(1'b1),.m_gx(full_event_gx),.m_gy(full_event_gy),
        .m_magnitude(full_event_magnitude),.m_filtered_y(full_event_filtered_y),
        .m_keep(full_event_metadata[6:3]),.m_scale(full_event_metadata[60:59]),
        .m_width(full_event_metadata[58:46]),.m_height(full_event_metadata[45:33]),
        .m_x(full_event_metadata[32:20]),.m_y(full_event_metadata[19:7]),
        .m_sof(full_event_metadata[2]),.m_eol(full_event_metadata[1]),.m_eof(full_event_metadata[0]),
        .m_context(full_event_metadata[220:61]));
    preprocess_sobel4 lower_math(.clk(clk),.rst_n(rst_n),.cancel(pipe_cancel),
        .s_valid(arb_valid),.s_ready(arb_ready),.s_window(arb_window),.s_filtered_y(32'd0),
        .s_keep(arb_metadata[6:3]),.s_scale(arb_metadata[60:59]),.s_width(arb_metadata[58:46]),
        .s_height(arb_metadata[45:33]),.s_x(arb_metadata[32:20]),.s_y(arb_metadata[19:7]),
        .s_sof(arb_metadata[2]),.s_eol(arb_metadata[1]),.s_eof(arb_metadata[0]),.s_context(arb_metadata[220:61]),
        .m_valid(low_valid),.m_ready(low_ready),.m_gx(low_event_gx),.m_gy(low_event_gy),
        .m_magnitude(low_event_magnitude),.m_filtered_y(low_event_filtered_y),
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
        integer lane;
        reg [2:0] pixels,strong_pixels;
        reg [12:0] sum,peak_x;
        reg [10:0] peak,magnitude;
        begin
            pixels=0;strong_pixels=0;sum=0;peak=0;peak_x=x;
            for(lane=0;lane<4;lane=lane+1) if(keep[lane]) begin
                magnitude=magnitudes[lane*11 +:11];pixels=pixels+1'b1;
                strong_pixels=strong_pixels+(magnitude>=limit);sum=sum+{2'b0,magnitude};
                if(magnitude>peak) begin peak=magnitude;peak_x=x+lane;end
            end
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
    reg [23:0] pixels_seen [0:2],strong_count [0:2];
    reg [33:0] gradient_sum [0:2];
    reg [10:0] peak_gradient [0:2];
    reg [12:0] peak_x [0:2],peak_y [0:2];
    reg [2:0] eof_seen,full_outstanding,low_outstanding;
    reg [1:0] window_done,half_wait,quarter_wait;
    wire [55:0] full_summary=summarize(full_event_metadata[6:3],full_event_magnitude,
        full_event_metadata[32:20],full_event_metadata[19:7],threshold);
    wire [55:0] low_summary=summarize(low_event_metadata[6:3],low_event_magnitude,
        low_event_metadata[32:20],low_event_metadata[19:7],threshold);
    wire [1:0] low_scale=low_event_metadata[60:59];
    wire [23:0] expected_low=low_scale==1 ? area(half_width,half_height) : area(quarter_width,quarter_height);
    wire count_bad=(full_event_valid&&(pixels_seen[0]+full_summary[55:53]>area(width,height)||
        (full_event_metadata[0]&&pixels_seen[0]+full_summary[55:53]!=area(width,height)))) ||
        (low_event_valid&&(low_scale==0||low_scale==3||pixels_seen[low_scale]+low_summary[55:53]>expected_low||
        (low_event_metadata[0]&&pixels_seen[low_scale]+low_summary[55:53]!=expected_low)));
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
    reg [1:0] fused_scale;
    always @* begin
        fused_scale=0;
        if(peak_gradient[1]>peak_gradient[0]) fused_scale=1;
        if(peak_gradient[2]>peak_gradient[fused_scale]) fused_scale=2;
    end
    wire [39:0] fused={fused_scale,peak_gradient[fused_scale],
        (peak_x[fused_scale]<<fused_scale),(peak_y[fused_scale]<<fused_scale),peak_gradient[fused_scale]>=threshold};
    wire [683:0] success_record={frame_context,1'b1,8'd0,width,height,threshold,stat0,stat1,stat2,fused};
    wire [2:0] low_resident=low_outstanding+{2'b0,half_window_valid}+{2'b0,quarter_window_valid};
    task publish;
        input [683:0] value;
        begin
            if(!record_valid||record_ready) begin record_valid<=1;record_data<=value;end
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
            state<=ST_IDLE;clear_pipeline<=0;record_valid<=0;frame_complete<=0;frame_error<=0;
            frame_error_code<=0;debug_poll_count<=0;record_drop_count<=0;completed_count<=0;failed_count<=0;
            native_stall_count<=0;firstfault_code<=0;firstfault_context<=0;first_congestion_context<=0;
            max_low_resident<=0;max_grant_wait<=0;half_wait<=0;quarter_wait<=0;
            half_group_valid<=0;quarter_group_valid<=0;half_carry_valid<=0;quarter_carry_count<=0;quarter_carry<=0;
            full_outstanding<=0;low_outstanding<=0;eof_seen<=0;window_done<=0;
        end else begin
            clear_pipeline<=0;frame_complete<=0;frame_error<=0;
            if(record_valid&&record_ready) record_valid<=0;
            if(debug_poll) debug_poll_count<=increment(debug_poll_count);
            if(debug_clear_firstfault) begin firstfault_code<=0;firstfault_context<=0;end
            if(cancel) begin
                state<=ST_IDLE;record_valid<=0;half_group_valid<=0;quarter_group_valid<=0;
                half_carry_valid<=0;quarter_carry_count<=0;quarter_carry<=0;full_outstanding<=0;low_outstanding<=0;
            end else if(start_fire) begin
                width<=start_width;height<=start_height;threshold<=start_threshold;frame_context<=start_context;
                native_x<=0;native_y<=0;half_input_x<=0;half_input_y<=0;quarter_input_x<=0;quarter_input_y<=0;
                half_group_valid<=0;quarter_group_valid<=0;half_carry_valid<=0;quarter_carry_count<=0;quarter_carry<=0;
                full_outstanding<=0;low_outstanding<=0;eof_seen<=0;window_done<=0;half_wait<=0;quarter_wait<=0;
                for(stats_index=0;stats_index<3;stats_index=stats_index+1) begin
                    pixels_seen[stats_index]<=0;strong_count[stats_index]<=0;gradient_sum[stats_index]<=0;
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
                    if(s_eol) begin native_x<=0;native_y<=native_y+1'b1;end else native_x<=native_x+13'd4;
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
                    pixels_seen[0]<=pixels_seen[0]+full_summary[55:53];strong_count[0]<=strong_count[0]+full_summary[52:50];
                    gradient_sum[0]<=gradient_sum[0]+full_summary[49:37];
                    if(full_summary[36:26]>peak_gradient[0]) begin
                        peak_gradient[0]<=full_summary[36:26];peak_x[0]<=full_summary[25:13];peak_y[0]<=full_summary[12:0];end
                    if(full_event_metadata[0]) eof_seen[0]<=1;
                end
                if(low_event_valid) begin
                    pixels_seen[low_scale]<=pixels_seen[low_scale]+low_summary[55:53];
                    strong_count[low_scale]<=strong_count[low_scale]+low_summary[52:50];
                    gradient_sum[low_scale]<=gradient_sum[low_scale]+low_summary[49:37];
                    if(low_summary[36:26]>peak_gradient[low_scale]) begin
                        peak_gradient[low_scale]<=low_summary[36:26];peak_x[low_scale]<=low_summary[25:13];peak_y[low_scale]<=low_summary[12:0];end
                    if(low_event_metadata[0]) eof_seen[low_scale]<=1;
                end
                if(finish_frame) begin
                    state<=ST_IDLE;frame_complete<=1;completed_count<=increment(completed_count);publish(success_record);
                end
            end
        end
    end
endmodule
