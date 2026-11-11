`timescale 1ns/1ps
// Atomic same-clock block pipeline; only held successful status qualifies output.
module cfs_block_decoder (
    input wire i_clk,i_rst_n,i_abort,
    input wire i_start_valid,
    output wire o_start_ready,
    input wire [11:0] i_sample_count,i_stored_length,
    input wire [15:0] i_width,i_block_start_x,
    input wire [159:0] i_context,
    input wire i_valid,
    output wire o_ready,
    input wire [31:0] i_data,
    input wire [3:0] i_keep,
    input wire i_last,
    output wire o_valid,
    input wire i_ready,
    output wire [31:0] o_data,
    output wire [3:0] o_keep,
    output wire o_last,
    output wire [159:0] o_context,
    output wire o_status_valid,
    input wire i_status_ready,
    output wire o_status_ok,
    output wire [7:0] o_status_error,
    output wire o_status_overflow,
    output wire [11:0] o_status_input_length,o_status_output_length,
    output wire [159:0] o_status_context
);
    localparam [2:0] S_IDLE=0,S_RELEASE=1,S_ARM=2,S_RUN=3,S_DRAIN=4,S_DONE=5;
    reg [2:0] state,state_next;
    reg [11:0] sample_count,raw_length,stored_length,input_count,output_count;
    reg [12:0] drain_budget;
    reg [15:0] width,block_start_x;
    reg [159:0] block_context;
    reg [7:0] error_code;
    reg overflow,input_complete,outer_final_seen;
    reg unpack_seen,predict_seen,pack_seen,lz_seen;
    reg [11:0] lz_length;
    reg output_valid,output_last;
    reg [31:0] output_data;
    reg [3:0] output_keep;
    wire [15:0] declared_bits=i_sample_count*16'd10;
    wire [15:0] declared_bytes=(declared_bits+16'd7)>>3;
    wire metadata_ok=i_sample_count>=1 && i_sample_count<=2048 &&
        i_width!=0 && i_block_start_x<i_width && i_stored_length>=1 && i_stored_length<=2580;
    // State changes occur only on this clock. Release precedes atomic ARM start.
    wire pipe_rst_n=i_rst_n && (state==S_ARM || state==S_RUN);
    wire unpack_start_ready,predict_start_ready,pack_start_ready,lz_start_ready;
    wire all_start_ready=unpack_start_ready && predict_start_ready && pack_start_ready && lz_start_ready;
    wire pipeline_start=state==S_ARM && all_start_ready && !i_abort;
    wire start_fire=i_start_valid && o_start_ready;
    reg [2:0] input_bytes,output_bytes;
    reg keep_ok;
    wire [12:0] input_end={1'b0,input_count}+input_bytes;
    wire [12:0] budget_end=drain_budget+(input_bytes==0 ? 13'd1 : {10'd0,input_bytes});
    wire [11:0] input_target=stored_length;
    wire transport_bad_keep=!keep_ok;
    wire transport_bad_length=input_end>{1'b0,input_target} ||
        i_last!=(input_end=={1'b0,input_target});
    wire transport_fault=transport_bad_keep || transport_bad_length;
    wire source_ready;
    wire input_fire=i_valid && o_ready;
    wire outer_fire=o_valid && i_ready;
    wire outer_slot=!output_valid || i_ready;
    wire [31:0] final_data;
    wire [3:0] final_keep;
    wire final_last,final_valid,final_ready;
    wire unpack_status_valid,unpack_status_ok,pack_status_valid,pack_status_ok;
    wire [7:0] unpack_error,pack_error,lz_error;
    wire [11:0] unpack_count,pack_count,predict_count,lz_count;
    wire predict_done,predict_error,lz_done,lz_overflow;
    wire [39:0] unpack_data,predict_data,pack_data;
    wire [3:0] unpack_keep,predict_keep,pack_keep;
    wire unpack_last,unpack_valid,unpack_ready,predict_last,predict_valid,predict_ready;
    wire pack_last,pack_valid,pack_ready;
    wire [39:0] unpack_input_data;
    wire [3:0] unpack_input_keep;
    wire unpack_input_last,unpack_input_valid,unpack_input_ready;
    reg [7:0] fault;
    wire all_done=unpack_seen && predict_seen && pack_seen && lz_seen;
    always @(*) begin
        input_bytes=i_keep[0]+{2'd0,i_keep[1]}+{2'd0,i_keep[2]}+{2'd0,i_keep[3]};
        keep_ok=i_keep==4'h1 || i_keep==4'h3 || i_keep==4'h7 || i_keep==4'hf;
        case(output_keep)
            4'h1:output_bytes=1;
            4'h3:output_bytes=2;
            4'h7:output_bytes=3;
            4'hf:output_bytes=4;
            default:output_bytes=0;
        endcase
    end
    // First fault ends every internal owner; external presented data survives.
    always @(*) begin
        fault=0;
        if(state==S_RUN) begin
            if(input_fire && transport_bad_keep) fault=2;
            else if(input_fire && transport_bad_length) fault=3;
            else if(unpack_error!=0 || (unpack_status_valid && !unpack_status_ok)) fault=4;
            else if(predict_error) fault=5;
            else if(pack_error!=0 || (pack_status_valid && !pack_status_ok)) fault=6;
            else if(lz_overflow) fault=8;
            else if(lz_error!=0) fault=7;
            else if((unpack_status_valid && unpack_count!=sample_count) ||
                (predict_done && predict_count!=sample_count) ||
                (pack_status_valid && pack_count!=raw_length) ||
                (lz_done && lz_count!=raw_length)) fault=9;
            else if(all_done && outer_final_seen &&
                (input_count!=input_target || output_count!=raw_length)) fault=9;
        end
    end
    assign o_start_ready=i_rst_n && !i_abort && state==S_IDLE;
    assign o_ready=i_rst_n && !i_abort && !input_complete &&
        ((state==S_RUN && source_ready) || state==S_DRAIN);
    assign o_valid=i_rst_n && !i_abort && output_valid;
    assign o_data=output_data;
    assign o_keep=output_keep;
    assign o_last=output_last;
    assign o_context=block_context;
    assign final_ready=state==S_RUN && !i_abort && outer_slot;
    assign o_status_valid=i_rst_n && state==S_DONE;
    assign o_status_ok=error_code==0;
    assign o_status_error=error_code;
    assign o_status_overflow=overflow;
    assign o_status_input_length=input_count;
    assign o_status_output_length=output_count;
    assign o_status_context=block_context;
    always @(*) begin
        state_next=state;
        case(state)
            S_IDLE:if(start_fire) state_next=metadata_ok ? S_RELEASE : S_DONE;
            S_RELEASE:state_next=S_ARM;
            S_ARM:if(pipeline_start) state_next=S_RUN;
            S_RUN:begin
                if(fault!=0) state_next=S_DRAIN;
                else if(all_done && outer_final_seen && !output_valid) state_next=S_DONE;
            end
            S_DRAIN:if(input_complete && !output_valid) state_next=S_DONE;
            S_DONE:if(i_status_ready) state_next=S_IDLE;
            default:state_next=S_DRAIN;
        endcase
        if(i_abort && state!=S_IDLE && state!=S_DONE) state_next=S_DONE;
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) state<=S_IDLE;
        else state<=state_next;
    end
    // The outer register is deliberately excluded from shared block reset.
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            sample_count<=0;raw_length<=0;stored_length<=0;width<=0;block_start_x<=0;block_context<=0;
            input_count<=0;output_count<=0;drain_budget<=0;error_code<=0;overflow<=0;
            input_complete<=0;outer_final_seen<=0;unpack_seen<=0;predict_seen<=0;pack_seen<=0;lz_seen<=0;lz_length<=0;
            output_valid<=0;output_data<=0;output_keep<=0;output_last<=0;
        end else if(start_fire) begin
            sample_count<=i_sample_count;raw_length<=declared_bytes[11:0];stored_length<=i_stored_length;
            width<=i_width;block_start_x<=i_block_start_x;block_context<=i_context;
            input_count<=0;output_count<=0;drain_budget<=0;error_code<=metadata_ok ? 8'd0 : 8'd1;overflow<=0;
            input_complete<=!metadata_ok;outer_final_seen<=0;unpack_seen<=0;predict_seen<=0;pack_seen<=0;lz_seen<=0;lz_length<=0;
            output_valid<=0;output_data<=0;output_keep<=0;output_last<=0;
        end else begin
            if(input_fire) begin
                input_count<=input_end>4095 ? 12'd4095 : input_end[11:0];
                drain_budget<=budget_end>4095 ? 13'd4095 : budget_end;
                if(i_last || budget_end>={1'b0,input_target}) input_complete<=1;
            end
            if(outer_fire) begin
                output_valid<=0;
                output_count<=output_count+output_bytes;
                if(output_last) outer_final_seen<=1;
            end
            if(final_valid && final_ready && fault==0) begin
                output_valid<=1;output_data<=final_data;output_keep<=final_keep;output_last<=final_last;
            end
            if(state==S_RUN) begin
                if(unpack_status_valid) unpack_seen<=1;
                if(predict_done) predict_seen<=1;
                if(pack_status_valid) pack_seen<=1;
                if(lz_done) begin lz_seen<=1;lz_length<=lz_count;end
                if(fault!=0 && error_code==0) error_code<=fault;
                if(lz_overflow) overflow<=1;
            end
            if(i_abort && state!=S_IDLE && state!=S_DONE) begin
                output_valid<=0;output_data<=0;output_keep<=0;output_last<=0;
                input_complete<=1;
                if(error_code==0) error_code<=10;
            end
        end
    end

    cfs_raw10_gearbox #(.PACK(0)) u_unpack (
        .i_clk(i_clk),.i_rst_n(pipe_rst_n),.i_abort(1'b0),
        .i_start_valid(pipeline_start),.o_start_ready(unpack_start_ready),
        .i_sample_count(sample_count),.i_context(block_context),
        .i_valid(unpack_input_valid),.o_ready(unpack_input_ready),.i_data(unpack_input_data),
        .i_keep(unpack_input_keep),.i_last(unpack_input_last),
        .o_valid(unpack_valid),.i_ready(unpack_ready),.o_data(unpack_data),.o_keep(unpack_keep),.o_last(unpack_last),.o_context(),
        .o_status_valid(unpack_status_valid),.i_status_ready(1'b1),.o_status_ok(unpack_status_ok),
        .o_status_error(unpack_error),.o_status_count(unpack_count),.o_status_context());
    cfs_raw10_predictor u_predict (
        .clk(i_clk),.rst_n(pipe_rst_n),.abort(1'b0),.start_valid(pipeline_start),.start_ready(predict_start_ready),
        .inverse_mode(1'b1),.sample_count(sample_count),.width(width),.block_start_x(block_start_x),.i_context(block_context),
        .input_data(unpack_data),.input_keep(unpack_keep),.input_last(unpack_last),.input_valid(unpack_valid),.input_ready(unpack_ready),
        .output_data(predict_data),.output_keep(predict_keep),.output_last(predict_last),.output_valid(predict_valid),.output_ready(predict_ready),
        .result_context(),.busy(),.done(predict_done),.error(predict_error),.output_count(predict_count),.service_cycles());
    cfs_raw10_gearbox #(.PACK(1)) u_pack (
        .i_clk(i_clk),.i_rst_n(pipe_rst_n),.i_abort(1'b0),
        .i_start_valid(pipeline_start),.o_start_ready(pack_start_ready),
        .i_sample_count(sample_count),.i_context(block_context),
        .i_valid(predict_valid),.o_ready(predict_ready),.i_data(predict_data),.i_keep(predict_keep),.i_last(predict_last),
        .o_valid(pack_valid),.i_ready(pack_ready),.o_data(pack_data),.o_keep(pack_keep),.o_last(pack_last),.o_context(),
        .o_status_valid(pack_status_valid),.i_status_ready(1'b1),.o_status_ok(pack_status_ok),
        .o_status_error(pack_error),.o_status_count(pack_count),.o_status_context());

    wire [31:0] decoded_data;
    wire [3:0] decoded_keep;
    wire decoded_last,decoded_valid,decoded_ready,lz_status_ok;
    assign lz_overflow=1'b0;
    assign final_data=pack_data[31:0];
    assign final_keep=pack_keep;
    assign final_last=pack_last;
    assign final_valid=pack_valid;
    assign pack_ready=final_ready;
    cfs_lz77_decoder u_lz (
        .i_clk(i_clk),.i_rst_n(pipe_rst_n),.i_start_valid(pipeline_start),.o_start_ready(lz_start_ready),
        .i_block_id(32'd0),.i_context(block_context),.i_raw_length(raw_length),.i_stored_length(stored_length),
        .i_input_valid(i_valid && state==S_RUN && !transport_fault && !i_abort),.o_input_ready(source_ready),
        .i_input_data(i_data),.i_input_keep(i_keep),.i_input_last(i_last),
        .o_output_valid(decoded_valid),.i_output_ready(decoded_ready),.o_output_data(decoded_data),
        .o_output_keep(decoded_keep),.o_output_last(decoded_last),.o_output_block_id(),.o_output_context(),
        .o_status_valid(lz_done),.i_status_ready(1'b1),.o_status_ok(lz_status_ok),.o_status_error(lz_error),
        .o_status_count(lz_count),.o_status_block_id(),.o_status_context());
    // Eight-byte sequential carry normalizes short legal decoder beats.
    reg [63:0] byte_carry;
    reg [3:0] carry_count;
    reg carry_final;
    reg [2:0] decoded_bytes;
    reg [31:0] masked_decoded;
    always @(*) begin
        decoded_bytes=0;masked_decoded=0;
        case(decoded_keep)
            4'h1:begin decoded_bytes=1;masked_decoded={24'd0,decoded_data[7:0]};end
            4'h3:begin decoded_bytes=2;masked_decoded={16'd0,decoded_data[15:0]};end
            4'h7:begin decoded_bytes=3;masked_decoded={8'd0,decoded_data[23:0]};end
            4'hf:begin decoded_bytes=4;masked_decoded=decoded_data;end
            default:begin decoded_bytes=0;masked_decoded=0;end
        endcase
    end
    assign unpack_input_data={8'd0,byte_carry[31:0]};
    assign unpack_input_keep=carry_count>=4 ? 4'hf : carry_count==3 ? 4'h7 : carry_count==2 ? 4'h3 : 4'h1;
    assign unpack_input_last=carry_final && carry_count<=4;
    assign unpack_input_valid=state==S_RUN && !i_abort &&
        (carry_count>=4 || (carry_final && carry_count!=0));
    wire carry_take=unpack_input_valid && unpack_input_ready;
    wire [3:0] carry_remove=carry_take ? (carry_count>=4 ? 4'd4 : carry_count) : 4'd0;
    wire [3:0] carry_remaining=carry_count-carry_remove;
    assign decoded_ready=state==S_RUN && !i_abort && !carry_final && carry_remaining<=4;
    wire decoded_fire=decoded_valid && decoded_ready;
    wire [63:0] shifted_carry=byte_carry>>(carry_remove*8);
    wire [63:0] appended_decoded={32'd0,masked_decoded}<<(carry_remaining*8);
    always @(posedge i_clk) begin
        if(!pipe_rst_n) begin byte_carry<=0;carry_count<=0;carry_final<=0;end
        else if(state==S_RUN) begin
            byte_carry<=decoded_fire ? shifted_carry | appended_decoded : shifted_carry;
            carry_count<=carry_remaining+(decoded_fire ? {1'b0,decoded_bytes} : 4'd0);
            if(decoded_fire && decoded_last) carry_final<=1;
        end
    end
endmodule
