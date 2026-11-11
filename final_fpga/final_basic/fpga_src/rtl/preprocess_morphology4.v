// Threshold plus one/two real packed-bit3x3 window stages. No F22-ready output.
module preprocess_morphology4 (
    input wire clk,rst_n,cancel,source_error,debug_clear,
    input wire start_valid,
    output wire start_ready,
    input wire [12:0] start_width,start_height,
    input wire [159:0] start_context,
    input wire [10:0] start_threshold,
    input wire [2:0] start_mode,
    input wire s_valid,
    output wire s_ready,
    input wire [43:0] s_magnitude,
    input wire [3:0] s_keep,
    input wire s_sof,s_eol,s_eof,
    output wire m_valid,
    input wire m_ready,
    output wire [3:0] m_mask,m_keep,
    output wire m_sof,m_eol,m_eof,
    output wire [12:0] m_x,m_y,m_width,m_height,
    output wire [159:0] m_context,
    output reg done,error,
    output reg [7:0] error_code,
    output reg [159:0] status_context,
    output reg [31:0] frames_started,frames_completed,frames_failed,
    output reg first_fault_valid,
    output reg [7:0] first_fault_code,
    output reg [159:0] first_fault_context
);
    reg active,poisoned,first_finished,second_finished;
    reg [2:0] mode;
    reg [10:0] threshold;
    reg [7:0] first_error;
    wire run=rst_n&&!cancel;
    wire two_stages=mode==3||mode==4;
    wire bad_config=start_mode>4||start_threshold>2040||start_width==0||start_width>3840
        ||start_height==0||start_height>2160;
    wire first_start_ready,second_start_ready,first_input_ready;
    assign start_ready=run&&!active&&first_start_ready&&second_start_ready;
    wire take_start=start_valid&&start_ready;
    reg numeric_bad;
    integer lane_check;
    always @* begin
        numeric_bad=0;
        for(lane_check=0;lane_check<4;lane_check=lane_check+1)
            if(s_keep[lane_check]&&s_magnitude[lane_check*11 +:11]>2040) numeric_bad=1;
    end
    // A malformed numeric vector is consumed as a fault, not written to RAM.
    // This bypass avoids a source_error -> ready -> source_error combinational loop.
    assign s_ready=run&&active&&!poisoned&&(numeric_bad ? 1'b1 : first_input_ready);
    wire numeric_fault=s_valid&&s_ready&&numeric_bad;
    wire first_valid,second_valid,second_input_ready;
    wire [35:0] first_window,second_window;
    wire [218:0] first_metadata,second_metadata;
    wire first_done,second_done,first_window_error,second_window_error;
    wire [7:0] first_window_code,second_window_code;
    wire window_fault=first_window_error||second_window_error;
    wire new_fault=active&&!poisoned&&(source_error||numeric_fault||window_fault);
    wire ordinary_error=source_error||numeric_fault||poisoned||window_fault;
    wire [7:0] new_code=source_error ? 8'd3 : numeric_fault ? 8'd4 :
        first_window_error ? first_window_code : second_window_code;
    wire all_finished=(first_finished||first_done)&&(second_finished||second_done);
    wire finish_frame=active&&all_finished;
    wire selected_done=two_stages ? second_done : first_done;
    wire [3:0] threshold_mask;
    wire [3:0] first_mask,second_mask;
    wire [218:0] selected_metadata=two_stages ? second_metadata : first_metadata;
    // During a whole-frame fault the internal first-stage beat is consumed
    // into discard. The external selected beat remains held by stage2.
    wire first_output_ready=two_stages ? (ordinary_error||second_input_ready) : m_ready;
    genvar pixel;
    generate for(pixel=0;pixel<4;pixel=pixel+1) begin:g_pixel
        assign threshold_mask[pixel]=s_keep[pixel]&&s_magnitude[pixel*11 +:11]!=0
            &&s_magnitude[pixel*11 +:11]>=threshold;
        assign first_mask[pixel]=mode==0 ? first_window[pixel*9+4] :
            (mode==1||mode==3) ? &first_window[pixel*9 +:9] : |first_window[pixel*9 +:9];
        assign second_mask[pixel]=mode==4 ? &second_window[pixel*9 +:9] : |second_window[pixel*9 +:9];
    end endgenerate
    preprocess_binary_window4 first_window_engine (
        .clk(clk),.rst_n(rst_n),.cancel(cancel),.source_error(ordinary_error),
        .start_valid(take_start&&!bad_config),.start_ready(first_start_ready),
        .start_width(start_width),.start_height(start_height),.start_context(start_context),
        .s_valid(s_valid&&active&&!poisoned&&!numeric_bad),.s_ready(first_input_ready),
        .s_mask(threshold_mask),.s_keep(s_keep),.s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),
        .m_valid(first_valid),.m_ready(first_output_ready),.m_window(first_window),.m_metadata(first_metadata),
        .done(first_done),.error(first_window_error),.error_code(first_window_code),.status_context());
    preprocess_binary_window4 second_window_engine (
        .clk(clk),.rst_n(rst_n),.cancel(cancel),.source_error(ordinary_error),
        .start_valid(take_start&&!bad_config&&(start_mode==3||start_mode==4)),.start_ready(second_start_ready),
        .start_width(start_width),.start_height(start_height),.start_context(start_context),
        .s_valid(first_valid&&two_stages&&!ordinary_error),.s_ready(second_input_ready),
        .s_mask(first_mask),.s_keep(first_metadata[6:3]),.s_sof(first_metadata[2]),
        .s_eol(first_metadata[1]),.s_eof(first_metadata[0]),
        .m_valid(second_valid),.m_ready(m_ready),.m_window(second_window),.m_metadata(second_metadata),
        .done(second_done),.error(second_window_error),.error_code(second_window_code),.status_context());
    assign m_valid=run&&active&&(two_stages ? second_valid : first_valid);
    assign m_mask=two_stages ? second_mask : first_mask;
    assign {m_context,m_width,m_height,m_x,m_y,m_keep,m_sof,m_eol,m_eof}=selected_metadata;

    always @(posedge clk) begin
        if(!rst_n||cancel) begin
            active<=0;poisoned<=0;first_finished<=0;second_finished<=0;
            mode<=0;threshold<=0;first_error<=0;done<=0;error<=0;error_code<=0;status_context<=0;
        end else begin
            done<=0;error<=0;
            if(take_start) begin
                mode<=start_mode;threshold<=start_threshold;status_context<=start_context;
                poisoned<=0;first_error<=0;first_finished<=0;
                second_finished<=!(start_mode==3||start_mode==4);error_code<=0;
                if(bad_config) begin active<=0;done<=1;error<=1;error_code<=1;end
                else active<=1;
            end else if(active) begin
                if(first_done) first_finished<=1;
                if(second_done) second_finished<=1;
                if(new_fault) begin poisoned<=1;first_error<=new_code;end
                if(finish_frame) begin
                    active<=0;done<=1;
                    if(poisoned||new_fault) begin
                        error<=1;error_code<=poisoned ? first_error : new_code;
                    end else if(selected_done) begin error_code<=0;end
                    else begin error<=1;error_code<=2;end
                end
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n||cancel||debug_clear) begin
            frames_started<=0;frames_completed<=0;frames_failed<=0;
            first_fault_valid<=0;first_fault_code<=0;first_fault_context<=0;
        end else begin
            if(take_start) begin
                frames_started<=frames_started+32'd1;
                if(bad_config) frames_failed<=frames_failed+32'd1;
            end
            if(finish_frame) begin
                if(poisoned||new_fault||!selected_done) frames_failed<=frames_failed+32'd1;
                else frames_completed<=frames_completed+32'd1;
            end
            if(!first_fault_valid&&((take_start&&bad_config)||new_fault)) begin
                first_fault_valid<=1;first_fault_code<=take_start&&bad_config ? 8'd1 : new_code;
                first_fault_context<=take_start ? start_context : status_context;
            end
        end
    end
endmodule
