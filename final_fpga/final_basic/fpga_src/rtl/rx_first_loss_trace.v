`timescale 1ns/1ps
`default_nettype none

// Read-only WORD-domain first-loss recorder. The RAM has one clock, a
// synchronous read port and no reset. Only held mailbox data crosses to SYS.
module rx_first_loss_trace (
    input wire i_word_clk,
    input wire i_observer_rst_n,
    input wire i_cohort_rst_n,
    input wire i_enable,
    input wire i_trigger,
    input wire [255:0] i_sample,
    input wire i_sys_clk,
    input wire i_sys_rst_n,
    input wire i_request,
    input wire [5:0] i_index,
    output wire o_ack,
    output reg [319:0] o_data
);
    localparam [2:0] R_IDLE=3'd0, R_INDEX=3'd1, R_WAIT=3'd2,
        R_CAPTURE=3'd3, R_HOLD=3'd4;

    // This marker also remembers a cohort reset pulse during a stopped WORD
    // clock. Generation itself belongs to the independent observer lifetime.
    wire marker_rst_n=i_observer_rst_n && i_cohort_rst_n;
    reg cohort_marker,cohort_seen;
    always @(posedge i_word_clk or negedge marker_rst_n)begin
        if(!marker_rst_n)cohort_marker<=0;
        else cohort_marker<=1;
    end

    reg [15:0] generation;
    reg generation_exhausted;
    reg [31:0] cycle_count,trigger_cycle;
    reg [4:0] pre_write,pre_base;
    reg [5:0] pre_count,post_write;
    reg trigger_seen,capture_ready,capturing_post;
    wire cohort_active=cohort_marker && cohort_seen && i_cohort_rst_n &&
        !generation_exhausted;
    wire enabled=cohort_active && i_enable;
    // Once triggered, the seven following WORD clocks are consecutive even
    // if SDR enable changes. A business cohort reset still cancels capture.
    wire ram_write_enable=cohort_active && !capture_ready &&
        (capturing_post || (i_enable && !trigger_seen));
    wire [5:0] ram_write_address=capturing_post ? post_write :
        i_trigger ? 6'd32 : {1'b0,pre_write};

    reg [255:0] sample_ram [0:63];
    reg ram_read_enable;
    reg [5:0] ram_read_address;
    reg [255:0] ram_read_data;
    always @(posedge i_word_clk)begin
        if(ram_write_enable)sample_ram[ram_write_address]<=i_sample;
        if(ram_read_enable)ram_read_data<=sample_ram[ram_read_address];
    end

    always @(posedge i_word_clk or negedge i_observer_rst_n)begin
        if(!i_observer_rst_n)begin
            cohort_seen<=0;generation<=0;generation_exhausted<=0;
            cycle_count<=0;trigger_cycle<=0;
            pre_write<=0;pre_base<=0;pre_count<=0;post_write<=33;
            trigger_seen<=0;capture_ready<=0;capturing_post<=0;
        end else begin
            cycle_count<=cycle_count+1'b1;
            cohort_seen<=cohort_marker;
            if(!cohort_marker || !cohort_seen || generation_exhausted)begin
                pre_write<=0;pre_base<=0;pre_count<=0;post_write<=33;
                trigger_cycle<=0;trigger_seen<=0;capture_ready<=0;capturing_post<=0;
                if(cohort_marker && !cohort_seen)begin
                    if(generation==16'hffff)generation_exhausted<=1;
                    else generation<=generation+1'b1;
                end
            end else if(capturing_post)begin
                if(post_write==6'd39)begin
                    capturing_post<=0;capture_ready<=1;
                end else post_write<=post_write+1'b1;
            end else if(!trigger_seen)begin
                if(!i_enable)begin
                    // The prehistory is a contiguous enabled interval.
                    pre_write<=0;pre_count<=0;
                end else if(i_trigger)begin
                    pre_base<=pre_write;trigger_cycle<=cycle_count;
                    trigger_seen<=1;capturing_post<=1;post_write<=33;
                end else begin
                    pre_write<=pre_write+1'b1;
                    if(pre_count<6'd32)pre_count<=pre_count+1'b1;
                end
            end
        end
    end

    (* preserve="true", ASYNC_REG="TRUE" *) reg request_meta,request_sync;
    always @(posedge i_word_clk or negedge i_observer_rst_n)begin
        if(!i_observer_rst_n)begin request_meta<=0;request_sync<=0;end
        else begin request_meta<=i_request;request_sync<=request_meta;end
    end

    reg [5:0] request_index;
    wire [5:0] first_valid_pre=6'd32-pre_count;
    wire requested_valid=cohort_active && capture_ready && request_index<6'd40 &&
        (request_index>=6'd32 || request_index>=first_valid_pre);
    wire [4:0] requested_pre_address=pre_base+request_index[4:0];
    wire [5:0] requested_address=request_index<6'd32 ?
        {1'b0,requested_pre_address} : request_index;
    wire current_ready=cohort_active && capture_ready;
    wire current_post=cohort_active && capturing_post;
    wire [5:0] current_pre=cohort_active ? pre_count : 6'd0;
    wire [31:0] current_trigger=cohort_active ? trigger_cycle : 32'd0;

    reg [2:0] read_state;
    reg [15:0] request_generation;
    reg [63:0] request_metadata;
    reg ack_word;
    reg [319:0] mailbox_word;
    always @(posedge i_word_clk or negedge i_observer_rst_n)begin
        if(!i_observer_rst_n)begin
            read_state<=R_IDLE;request_index<=0;request_generation<=0;
            request_metadata<=0;ram_read_enable<=0;ram_read_address<=0;
            ack_word<=0;mailbox_word<=0;
        end else begin
            ram_read_enable<=0;
            case(read_state)
                R_IDLE:begin
                    ack_word<=0;
                    if(request_sync)begin
                        request_index<=i_index;
                        read_state<=R_INDEX;
                    end
                end
                R_INDEX:begin
                    // Held index has one CDC landing register. All address,
                    // validity and metadata decoding is WORD-local afterwards.
                    if(!request_sync)read_state<=R_IDLE;
                    else begin
                        request_generation<=generation;
                        request_metadata<={enabled,requested_valid,current_post,current_ready,
                            current_pre,request_index,current_trigger,generation};
                        if(requested_valid)begin
                            ram_read_address<=requested_address;
                            ram_read_enable<=1;read_state<=R_WAIT;
                        end else begin
                            mailbox_word<={{enabled,1'b0,current_post,current_ready,
                                current_pre,request_index,current_trigger,generation},
                                request_index==6'd63 ? i_sample : 256'd0};
                            ack_word<=1;read_state<=R_HOLD;
                        end
                    end
                end
                R_WAIT:begin
                    // The RAM consumes the registered read enable/address
                    // on this edge. Its data is available to R_CAPTURE next.
                    if(!request_sync)read_state<=R_IDLE;
                    else read_state<=R_CAPTURE;
                end
                R_CAPTURE:begin
                    if(!request_sync)read_state<=R_IDLE;
                    else begin
                        if(cohort_active && capture_ready &&
                            generation==request_generation)
                            mailbox_word<={request_metadata,ram_read_data};
                        else begin
                            // A reset before mailbox ownership is granted
                            // invalidates the pending read, including its RAM.
                            mailbox_word<={{enabled,1'b0,current_post,current_ready,
                                current_pre,request_index,current_trigger,generation},256'd0};
                        end
                        ack_word<=1;read_state<=R_HOLD;
                    end
                end
                default:begin
                    // Cohort reset never edits an already held response.
                    if(!request_sync)begin ack_word<=0;read_state<=R_IDLE;end
                end
            endcase
        end
    end

    (* preserve="true", ASYNC_REG="TRUE" *) reg ack_meta,ack_sync;
    assign o_ack=ack_sync;
    always @(posedge i_sys_clk or negedge i_sys_rst_n)begin
        if(!i_sys_rst_n)begin ack_meta<=0;ack_sync<=0;o_data<=0;end
        else begin
            ack_meta<=ack_word;ack_sync<=ack_meta;
            // Bundled data has been held throughout ACK synchronization.
            // Capture with the second ACK stage, then hold until the next ACK.
            if(ack_meta && !ack_sync)o_data<=mailbox_word;
        end
    end
endmodule
`default_nettype wire
