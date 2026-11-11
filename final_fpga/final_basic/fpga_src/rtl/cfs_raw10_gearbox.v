`timescale 1ns/1ps
// Align continuous LE10 sample bits with32-bit byte beats, in either direction.
module cfs_raw10_gearbox #(
    parameter integer PACK=1,
    parameter integer CONTEXT_WIDTH=160
) (
    input wire i_clk,i_rst_n,i_abort,
    input wire i_start_valid,
    output wire o_start_ready,
    input wire [11:0] i_sample_count,
    input wire [CONTEXT_WIDTH-1:0] i_context,
    input wire i_valid,
    output wire o_ready,
    input wire [39:0] i_data,
    input wire [3:0] i_keep,
    input wire i_last,
    output wire o_valid,
    input wire i_ready,
    output wire [39:0] o_data,
    output wire [3:0] o_keep,
    output wire o_last,
    output wire [CONTEXT_WIDTH-1:0] o_context,
    output wire o_status_valid,
    input wire i_status_ready,
    output wire o_status_ok,
    output wire [7:0] o_status_error,
    output wire [11:0] o_status_count,
    output wire [CONTEXT_WIDTH-1:0] o_status_context
);
    localparam [1:0] S_IDLE=0,S_RUN=1,S_DRAIN=2,S_DONE=3;
    localparam integer INPUT_BITS_PER_UNIT=PACK ? 10 : 8;
    localparam integer OUTPUT_BITS_PER_UNIT=PACK ? 8 : 10;
    localparam integer MAX_INPUT_BITS=4*INPUT_BITS_PER_UNIT;
    reg [1:0] state,state_next;
    reg [11:0] sample_count,byte_count,received_count,produced_count,committed_count;
    reg [CONTEXT_WIDTH-1:0] block_context;
    reg [71:0] assembly;
    reg [6:0] assembly_bits;
    reg input_complete;
    reg [7:0] error_code;
    reg output_valid,output_last;
    reg [39:0] output_data;
    reg [3:0] output_keep;
    reg [2:0] output_units;
    wire [15:0] declared_bits=i_sample_count*16'd10;
    wire [15:0] declared_bytes=(declared_bits+16'd7)>>3;
    wire start_fire=i_start_valid && o_start_ready;
    wire parameter_ok=i_sample_count>=1 && i_sample_count<=2048;
    wire [11:0] input_total=PACK ? sample_count : byte_count;
    wire [11:0] output_total=PACK ? byte_count : sample_count;
    wire [11:0] output_remaining=output_total-produced_count;
    wire output_slot=!output_valid || i_ready;
    wire output_fire=o_valid && i_ready;
    reg [2:0] input_units;
    reg input_keep_ok;
    reg [39:0] masked_input;
    reg [7:0] last_input_byte,padding_mask;
    always @(*) begin
        input_units=0;input_keep_ok=1;masked_input=0;last_input_byte=0;
        case(i_keep)
            4'b0001:begin
                input_units=1;masked_input=PACK ? {30'd0,i_data[9:0]} : {32'd0,i_data[7:0]};
                last_input_byte=i_data[7:0];
            end
            4'b0011:begin
                input_units=2;masked_input=PACK ? {20'd0,i_data[19:0]} : {24'd0,i_data[15:0]};
                last_input_byte=i_data[15:8];
            end
            4'b0111:begin
                input_units=3;masked_input=PACK ? {10'd0,i_data[29:0]} : {16'd0,i_data[23:0]};
                last_input_byte=i_data[23:16];
            end
            4'b1111:begin
                input_units=4;masked_input=PACK ? i_data : {8'd0,i_data[31:0]};
                last_input_byte=i_data[31:24];
            end
            default:input_keep_ok=0;
        endcase
        case(sample_count[1:0])
            2'd1:padding_mask=8'hfc;
            2'd2:padding_mask=8'hf0;
            2'd3:padding_mask=8'hc0;
            default:padding_mask=0;
        endcase
    end
    wire [6:0] accepted_bits=input_units*INPUT_BITS_PER_UNIT;
    wire [12:0] received_end={1'b0,received_count}+input_units;
    reg issue_output;
    reg [2:0] issue_units;
    reg [6:0] consume_bits,reserved_bits,wanted_bits;
    reg [7:0] failure_code;
    wire [6:0] ready_remaining_bits=assembly_bits-reserved_bits;
    wire [6:0] remaining_bits=assembly_bits-consume_bits;
    assign o_start_ready=i_rst_n && !i_abort && state==S_IDLE;
    assign o_ready=i_rst_n && !i_abort && !input_complete &&
        ((state==S_RUN && ready_remaining_bits<=72-MAX_INPUT_BITS) || state==S_DRAIN);
    wire input_fire=i_valid && o_ready;
    wire abort_active=i_abort && (state==S_RUN || state==S_DRAIN);
    always @(*) begin
        state_next=state;issue_output=0;issue_units=0;consume_bits=0;reserved_bits=0;
        wanted_bits=0;failure_code=0;
        case(state)
            S_IDLE:if(start_fire) state_next=parameter_ok ? S_RUN : S_DONE;
            S_RUN:begin
                if(output_slot && output_remaining!=0) begin
                    issue_units=output_remaining>=4 ? 3'd4 : output_remaining[2:0];
                    wanted_bits=issue_units*OUTPUT_BITS_PER_UNIT;
                    if(assembly_bits>=wanted_bits) begin issue_output=1;consume_bits=wanted_bits;end
                    else if(PACK && input_complete && assembly_bits!=0 && output_remaining<=4) begin
                        issue_output=1;consume_bits=assembly_bits;
                    end
                end
                if(input_complete && produced_count==output_total && output_slot) state_next=S_DONE;
            end
            S_DRAIN:if(input_complete && output_slot) state_next=S_DONE;
            S_DONE:if(i_status_ready) state_next=S_IDLE;
            default:state_next=S_IDLE;
        endcase
        // Reserve capacity independently of current input validation.
        reserved_bits=consume_bits;
        if(state==S_RUN && input_fire) begin
            if(!input_keep_ok || (!i_last && i_keep!=4'hf)) failure_code=2;
            else if(received_end>{1'b0,input_total} || i_last!=(received_end=={1'b0,input_total})) failure_code=3;
            else if(!PACK && i_last && (last_input_byte & padding_mask)!=0) failure_code=4;
        end
        if(failure_code!=0) begin state_next=S_DRAIN;issue_output=0;consume_bits=0;end
        if(abort_active) begin state_next=S_DONE;issue_output=0;consume_bits=0;end
    end
    always @(posedge i_clk) begin
        if(!i_rst_n) state<=S_IDLE;
        else state<=state_next;
    end
    // Every nonfinal accepted input contains four units. Before a new
    // input its reservoir offset is therefore a byte multiple in either
    // direction (40-bit groups versus 32-bit words). A partial final input
    // closes the source. Malformed inputs take the existing failure branch.
    wire [71:0] appended_input={32'd0,masked_input}<<{remaining_bits[5:3],3'b000};
    reg [71:0] shifted_assembly;
    always @(*) begin
        if(PACK)begin
            case(consume_bits)
                0:shifted_assembly=assembly;
                8:shifted_assembly={8'd0,assembly[71:8]};
                16:shifted_assembly={16'd0,assembly[71:16]};
                24:shifted_assembly={24'd0,assembly[71:24]};
                32:shifted_assembly={32'd0,assembly[71:32]};
                // A final sub-byte tail consumes the entire reservoir.
                default:shifted_assembly=0;
            endcase
        end else begin
            case(consume_bits)
                0:shifted_assembly=assembly;
                10:shifted_assembly={10'd0,assembly[71:10]};
                20:shifted_assembly={20'd0,assembly[71:20]};
                30:shifted_assembly={30'd0,assembly[71:30]};
                40:shifted_assembly={40'd0,assembly[71:40]};
                default:shifted_assembly=0;
            endcase
        end
    end
    always @(posedge i_clk) begin
        if(!i_rst_n) begin
            sample_count<=0;byte_count<=0;received_count<=0;produced_count<=0;committed_count<=0;
            block_context<=0;assembly<=0;assembly_bits<=0;input_complete<=0;error_code<=0;
            output_valid<=0;output_last<=0;output_data<=0;output_keep<=0;output_units<=0;
        end else if(start_fire) begin
            sample_count<=i_sample_count;byte_count<=declared_bytes[11:0];block_context<=i_context;
            received_count<=0;produced_count<=0;committed_count<=0;assembly<=0;assembly_bits<=0;
            input_complete<=0;error_code<=parameter_ok ? 8'd0 : 8'd1;
            output_valid<=0;output_last<=0;output_keep<=0;output_units<=0;
        end else if(abort_active) begin
            assembly<=0;assembly_bits<=0;input_complete<=1;output_valid<=0;
            if(error_code==0) error_code<=5;
        end else begin
            if(output_fire) committed_count<=committed_count+output_units;
            if(output_slot) begin
                output_valid<=issue_output;
                if(issue_output) begin
                    output_units<=issue_units;produced_count<=produced_count+issue_units;
                    output_last<=produced_count+issue_units==output_total;
                    output_data<=PACK ? {8'd0,assembly[31:0]} : assembly[39:0];
                    case(issue_units)
                        3'd1:output_keep<=4'b0001;
                        3'd2:output_keep<=4'b0011;
                        3'd3:output_keep<=4'b0111;
                        default:output_keep<=4'b1111;
                    endcase
                end
            end
            if(input_fire) begin
                received_count<=received_end[11:0];
                if(i_last || received_end>={1'b0,input_total}) input_complete<=1;
            end
            if(failure_code!=0) begin
                if(error_code==0) error_code<=failure_code;
                assembly<=0;assembly_bits<=0;
            end else if(state==S_RUN) begin
                assembly<=shifted_assembly | (input_fire ? appended_input : 72'd0);
                assembly_bits<=remaining_bits+(input_fire ? accepted_bits : 7'd0);
            end
        end
    end
    assign o_valid=i_rst_n && !i_abort && output_valid;
    assign o_data=output_data;
    assign o_keep=output_keep;
    assign o_last=output_last;
    assign o_context=block_context;
    assign o_status_valid=i_rst_n && state==S_DONE;
    assign o_status_ok=error_code==0;
    assign o_status_error=error_code;
    assign o_status_count=committed_count;
    assign o_status_context=block_context;
endmodule
