`timescale 1ns/1ps
// One time-multiplexed FDCT; rows enter only an already writable bank.
module jpeg_dct8x8_pipeline #(
    parameter integer OUTPUT_STREAM_MODE = 0,
    parameter integer TINY_DISTRIBUTED_RAM_ENABLE = 0,
    parameter integer INPUT_ROW_STREAM_ENABLE = 0
) (
    input wire i_clk,i_rst_n,
    input wire i_block_valid,
    output wire o_block_ready,
    input wire [511:0] i_samples,
    input wire [1:0] i_component,
    input wire [8:0] i_mcu_x,i_mcu_y,
    input wire [1:0] i_block_index,
    input wire i_frame_last,
    input wire [31:0] i_capture_id,
    output wire o_block_valid,
    input wire i_block_ready,
    output wire [1023:0] o_coeffs,
    output wire [1:0] o_component,
    output wire [8:0] o_mcu_x,o_mcu_y,
    output wire [1:0] o_block_index,
    output wire o_frame_last,
    output wire [31:0] o_capture_id,
    output wire o_column_valid,
    input wire i_column_ready,
    output wire [127:0] o_column_data,
    output wire [2:0] o_column_index,
    output wire [1:0] o_column_component,
    output wire [8:0] o_column_mcu_x,o_column_mcu_y,
    output wire [1:0] o_column_block_index,
    output wire o_column_frame_last,
    output wire [31:0] o_column_capture_id,
    input wire i_row_valid,
    output wire o_row_ready,
    input wire [63:0] i_row_data,
    input wire [2:0] i_row_index
);
    localparam integer META_WIDTH=55;
    reg [511:0] samples;
    reg row_active,row_bank,next_row_bank;
    reg [2:0] row_index;
    reg [1:0] bank_writable,bank_full;
    reg [META_WIDTH-1:0] metadata0,metadata1;
    wire [META_WIDTH-1:0] input_metadata={i_component,i_mcu_x,i_mcu_y,i_block_index,i_frame_last,i_capture_id};
    wire row_input_ready,row_output_valid,row_output_ready;
    wire bank_reservable;
    wire [127:0] row_output;
    wire [3:0] row_output_tag;
    wire row_issue=INPUT_ROW_STREAM_ENABLE ? i_row_valid && o_row_ready :
        row_active && row_input_ready;
    wire row_write=row_output_valid && row_output_ready;
    assign row_output_ready=bank_writable[row_output_tag[3]] && i_rst_n;
    reg [127:0] row_input;
    integer pixel;
    always @* begin
        for(pixel=0;pixel<8;pixel=pixel+1)
            row_input[pixel*16 +:16]=$signed({1'b0,INPUT_ROW_STREAM_ENABLE ?
                i_row_data[pixel*8 +:8] : samples[(row_index*8+pixel)*8 +:8]})-16'sd128;
    end
    wire row_target=INPUT_ROW_STREAM_ENABLE && !row_active ? next_row_bank : row_bank;
    wire row_admit=row_active || bank_reservable;
    wire row_valid=(INPUT_ROW_STREAM_ENABLE ? i_row_valid && row_admit : row_active) && bank_writable[row_target];
    wire [3:0] row_tag=INPUT_ROW_STREAM_ENABLE ?
        {row_active ? row_bank : next_row_bank,i_row_index} : {row_bank,row_index};

    reg column_active,column_bank,next_column_bank;
    reg [2:0] column_index;
    reg read_pending;
    reg [2:0] pending_column;
    wire column_input_ready,column_output_valid,column_output_ready;
    wire [127:0] column_input,column_output;
    wire [META_WIDTH+2:0] column_output_tag;
    wire read_available=!read_pending || column_input_ready;
    wire start_column=!column_active && bank_full[next_column_bank] && read_available;
    wire read_request=i_rst_n && read_available && (column_active || start_column);
    wire read_bank=column_active ? column_bank : next_column_bank;
    wire [2:0] read_column=column_active ? column_index : 3'd0;
    // Columns enter and leave in order. Snapshot once before the first RAM
    // read, because transpose storage may be reused before its FDCT tail exits.
    reg [META_WIDTH-1:0] column_context[0:1];
    reg context_write,context_read;
    wire context_push=read_request && start_column;
    wire context_pop=column_output_valid && column_output_ready && column_output_tag[2:0]==7;
    // One RAM-return slot, one elastic input slot and six FDCT stages contain
    // at most eight column vectors. Each block owns eight ordered vectors, so
    // at most two distinct block descriptors can still be live.
    always @(posedge i_clk)begin
        if(!i_rst_n)begin context_write<=0;context_read<=0;end
        else begin
            if(context_push)context_write<=!context_write;
            if(context_pop)context_read<=!context_read;
        end
        if(context_push)column_context[context_write]<=read_bank ? metadata1 : metadata0;
    end
    // Do not pre-reserve a bank whose old columns are still being read. A
    // blocked row result would otherwise stop the single shared core and
    // prevent those columns from draining: a circular wait. Every issued row
    // has unconditional transpose write capacity until its final result.
    assign bank_reservable=bank_writable[next_row_bank];
    assign o_block_ready=!INPUT_ROW_STREAM_ENABLE && i_rst_n && bank_reservable &&
        (!row_active || (row_index==7 && row_input_ready));
    assign o_row_ready=INPUT_ROW_STREAM_ENABLE && row_admit && row_input_ready;
    wire input_fire=INPUT_ROW_STREAM_ENABLE ? row_issue && i_row_index==0 :
        i_block_valid && o_block_ready;
    wire [127:0] ram_data;
    // Three fixed rotation stages share the selection network across all lanes.
    // Bank b stores frequency (b-row) mod 8; column reads undo that permutation.
    wire [127:0] write_rotate_one=row_output_tag[0] ?
        {row_output[111:0],row_output[127:112]} : row_output;
    wire [127:0] write_rotate_two=row_output_tag[1] ?
        {write_rotate_one[95:0],write_rotate_one[127:96]} : write_rotate_one;
    wire [127:0] write_rotate_four=row_output_tag[2] ?
        {write_rotate_two[63:0],write_rotate_two[127:64]} : write_rotate_two;
    wire [127:0] read_rotate_one=pending_column[0] ?
        {ram_data[15:0],ram_data[127:16]} : ram_data;
    wire [127:0] read_rotate_two=pending_column[1] ?
        {read_rotate_one[31:0],read_rotate_one[127:32]} : read_rotate_one;
    assign column_input=pending_column[2] ?
        {read_rotate_two[63:0],read_rotate_two[127:64]} : read_rotate_two;
    genvar bank;
    generate for(bank=0;bank<8;bank=bank+1) begin:g_transpose
        wire [2:0] read_row=bank-read_column;
        td_sdp_ram #(.WIDTH(16),.DEPTH(16),.ADDR_WIDTH(4),
            .DISTRIBUTED_ENABLE(TINY_DISTRIBUTED_RAM_ENABLE)) u_ram (
            .clk(i_clk),.wr_en(row_write),.wr_addr({row_output_tag[3],row_output_tag[2:0]}),
            .wr_data(write_rotate_four[bank*16 +:16]),
            .rd_en(read_request),.rd_addr({read_bank,read_row}),.rd_data(ram_data[bank*16 +:16]));
    end endgenerate
    wire shared_input_ready,shared_output_valid,shared_output_ready;
    wire [127:0] shared_output;
    wire [4:0] shared_tag;
    // A pending registered RAM column always wins. Rows retain their signed
    // eight-bit values, sign-extended into the unchanged ten-bit Q14 core.
    wire shared_input_valid=read_pending || row_valid;
    wire [127:0] shared_input=read_pending ? column_input : row_input;
    wire [4:0] shared_input_tag=read_pending ?
        {1'b1,1'b0,pending_column} : {1'b0,row_tag};
    // Hold the selected row/column before the FDCT butterfly. This cuts the
    // MCU RAM/component/alignment path from the DSP pre-add input path. The
    // single elastic slot accepts one item per clock and carries its full tag;
    // stalled items cannot change and reset discards any unfinished item.
    reg fdct_input_valid;
    wire [127:0] fdct_input_data;
    reg [4:0] fdct_input_tag;
    wire fdct_input_ready;
    assign shared_input_ready=i_rst_n && (!fdct_input_valid || fdct_input_ready);
    // The core consumes only ten bits per sample. Keep this existing capture
    // boundary in fabric: packing it into the DSP XA/XB registers otherwise
    // carries the MCU RAM/alignment mux across the long route to the DSP.
    // No stage is added; unused upper bits are just sign extension.
    genvar input_lane;
    generate for(input_lane=0;input_lane<8;input_lane=input_lane+1) begin:g_input_capture
        (* dont_touch="true" *) reg [9:0] sample_q;
        always @(posedge i_clk)
            if(shared_input_ready && shared_input_valid)
                sample_q<=shared_input[input_lane*16+:10];
        assign fdct_input_data[input_lane*16+:16]={{6{sample_q[9]}},sample_q};
    end endgenerate
    always @(posedge i_clk) begin
        if(!i_rst_n) fdct_input_valid<=0;
        else if(shared_input_ready) fdct_input_valid<=shared_input_valid;
        // Payload has no reset or validity fanout; ownership is the valid bit.
        if(shared_input_ready && shared_input_valid) begin
            fdct_input_tag<=shared_input_tag;
        end
    end
    assign column_input_ready=shared_input_ready;
    assign row_input_ready=shared_input_ready && !read_pending && bank_writable[row_target];
    assign row_output_valid=shared_output_valid && !shared_tag[4];
    assign column_output_valid=shared_output_valid && shared_tag[4];
    assign row_output=shared_output;
    assign column_output=shared_output;
    assign row_output_tag={shared_tag[3],shared_tag[2:0]};
    assign column_output_tag={column_context[context_read],shared_tag[2:0]};
    assign shared_output_ready=shared_tag[4] ? column_output_ready : row_output_ready;
    jpeg_fdct1d #(.TAG_WIDTH(5),.INPUT_SAMPLE_WIDTH(10)) u_shared (
        .i_clk(i_clk),.i_rst_n(i_rst_n),.i_valid(fdct_input_valid),.o_ready(fdct_input_ready),
        .i_data(fdct_input_data),.i_tag(fdct_input_tag),.o_valid(shared_output_valid),
        .i_ready(shared_output_ready),.o_data(shared_output),.o_tag(shared_tag));
    assign o_column_valid=OUTPUT_STREAM_MODE && column_output_valid;
    assign o_column_data=column_output;
    assign o_column_index=column_output_tag[2:0];
    assign {o_column_component,o_column_mcu_x,o_column_mcu_y,o_column_block_index,
        o_column_frame_last,o_column_capture_id}=column_output_tag[META_WIDTH+2:3];

    generate if(OUTPUT_STREAM_MODE) begin:g_columns
        assign column_output_ready=i_column_ready;
        assign o_block_valid=1'b0;assign o_coeffs=1024'd0;
        assign o_component=0;assign o_mcu_x=0;assign o_mcu_y=0;
        assign o_block_index=0;assign o_frame_last=0;assign o_capture_id=0;
    end else begin:g_block
        reg valid;
        reg [1023:0] coefficients;
        reg [META_WIDTH-1:0] metadata;
        integer v;
        assign column_output_ready=!valid || i_block_ready;
        assign o_block_valid=i_rst_n && valid;
        assign o_coeffs=coefficients;
        assign {o_component,o_mcu_x,o_mcu_y,o_block_index,o_frame_last,o_capture_id}=metadata;
        always @(posedge i_clk) begin
            if(!i_rst_n) valid<=0;
            else begin
                if(valid && i_block_ready) valid<=0;
                if(column_output_valid && column_output_ready) begin
                    for(v=0;v<8;v=v+1)
                        coefficients[(v*8+column_output_tag[2:0])*16 +:16]<=column_output[v*16 +:16];
                    if(column_output_tag[2:0]==7) begin
                        valid<=1;metadata<=column_output_tag[META_WIDTH+2:3];
                    end
                end
            end
        end
    end endgenerate
    always @(posedge i_clk) begin
        if(!i_rst_n) begin
            row_active<=0;row_bank<=0;next_row_bank<=0;row_index<=0;
            bank_writable<=2'b11;bank_full<=0;metadata0<=0;metadata1<=0;
            column_active<=0;column_bank<=0;next_column_bank<=0;column_index<=0;
            read_pending<=0;pending_column<=0;
        end else begin
            if(row_issue) begin
                if(INPUT_ROW_STREAM_ENABLE) begin
                    if(i_row_index==7) row_active<=0;
                end else begin
                    if(row_index==7) row_active<=0;
                    else row_index<=row_index+1'b1;
                end
            end
            if(input_fire) begin
                if(!INPUT_ROW_STREAM_ENABLE) samples<=i_samples;
                row_active<=1;row_bank<=next_row_bank;
                row_index<=0;next_row_bank<=!next_row_bank;
                if(next_row_bank) metadata1<=input_metadata;else metadata0<=input_metadata;
            end
            if(read_available) read_pending<=read_request;
            if(read_request) begin
                pending_column<=read_column;
                if(start_column) begin
                    column_bank<=next_column_bank;
                    next_column_bank<=!next_column_bank;bank_full[read_bank]<=0;
                end
                if(read_column==7) begin
                    column_active<=0;bank_writable[read_bank]<=1;
                end else begin
                    column_active<=1;column_index<=read_column+1'b1;
                end
            end
            if(row_write && row_output_tag[2:0]==7) begin
                bank_full[row_output_tag[3]]<=1;
                bank_writable[row_output_tag[3]]<=0;
            end
        end
    end
endmodule
