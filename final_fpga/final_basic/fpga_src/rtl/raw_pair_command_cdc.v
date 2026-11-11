// Atomic metadata commands; official control FIFO owns all queued storage/CDC.
module raw_pair_command_cdc (
    input wire i_source_clk, i_source_rst_n,
    input wire [577:0] s_command,
    input wire s_command_valid, output wire s_command_ready,
    output wire o_source_reset_done,
    input wire i_sink_clk, i_sink_rst_n,
    output wire [577:0] m_command,
    output wire m_command_valid, input wire m_command_ready,
    output wire o_sink_reset_done,
    output reg o_protocol_fault, output wire o_source_protocol_fault
);
    wire cohort_reset_n=i_source_rst_n && i_sink_rst_n;
    reg [639:0] source_packet, sink_packet;
    reg source_active, sink_valid;
    reg [2:0] source_part, sink_part;
    reg fault_meta, fault_sync;
    reg [127:0] source_payload;
    wire [146:0] fifo_source_data={source_part,16'd0,source_payload};
    wire fifo_source_ready, fifo_sink_valid;
    wire [146:0] fifo_sink_data;
    wire fifo_source_valid=o_source_reset_done && source_active && !fault_sync;
    wire fifo_sink_ready=o_sink_reset_done && !sink_valid && !o_protocol_fault;
    wire bad_part=fifo_sink_data[146:144]!=sink_part || fifo_sink_data[143:128]!=0 ||
        (sink_part==3'd4 && fifo_sink_data[127:66]!=0);
    assign o_source_protocol_fault=fault_sync;
    assign s_command_ready=o_source_reset_done && !source_active && !fault_sync;
    assign m_command=sink_packet[577:0];
    assign m_command_valid=o_sink_reset_done && sink_valid && !o_protocol_fault;

    always @* begin
        case(source_part)
            3'd0:source_payload=source_packet[127:0];
            3'd1:source_payload=source_packet[255:128];
            3'd2:source_payload=source_packet[383:256];
            3'd3:source_payload=source_packet[511:384];
            default:source_payload=source_packet[639:512];
        endcase
    end
    // Only this sticky fault level crosses outside the official FIFO.
    always @(posedge i_source_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) begin fault_meta<=0;fault_sync<=0;end
        else begin fault_meta<=o_protocol_fault;fault_sync<=fault_meta;end
    end
    always @(posedge i_source_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) begin source_packet<=0;source_active<=0;source_part<=0;end
        else if(!o_source_reset_done) begin source_packet<=0;source_active<=0;source_part<=0;end
        else if(s_command_valid && s_command_ready) begin
            source_packet<={62'd0,s_command};source_active<=1;source_part<=0;
        end else if(fifo_source_valid && fifo_source_ready) begin
            if(source_part==3'd4) begin source_active<=0;source_part<=0;end
            else source_part<=source_part+1'b1;
        end
    end
    always @(posedge i_sink_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) begin sink_packet<=0;sink_valid<=0;sink_part<=0;o_protocol_fault<=0;end
        else if(!o_sink_reset_done) begin sink_packet<=0;sink_valid<=0;sink_part<=0;o_protocol_fault<=0;end
        else if(m_command_valid && m_command_ready) sink_valid<=0;
        else if(fifo_sink_valid && fifo_sink_ready) begin
            if(bad_part) begin o_protocol_fault<=1;sink_valid<=0;end
            else begin
                case(sink_part)
                    3'd0:sink_packet[127:0]<=fifo_sink_data[127:0];
                    3'd1:sink_packet[255:128]<=fifo_sink_data[127:0];
                    3'd2:sink_packet[383:256]<=fifo_sink_data[127:0];
                    3'd3:sink_packet[511:384]<=fifo_sink_data[127:0];
                    3'd4:sink_packet[639:512]<=fifo_sink_data[127:0];
                endcase
                if(sink_part==3'd4) begin sink_valid<=1;sink_part<=0;end
                else sink_part<=sink_part+1'b1;
            end
        end
    end
    control_message_fifo_ip u_fifo (
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_source_clk),.i_source_rst_n(cohort_reset_n),.i_source_data(fifo_source_data),
        .i_source_valid(fifo_source_valid),.o_source_ready(fifo_source_ready),.o_source_reset_done(o_source_reset_done),
        .i_sink_clk(i_sink_clk),.i_sink_rst_n(cohort_reset_n),.o_sink_data(fifo_sink_data),
        .o_sink_valid(fifo_sink_valid),.i_sink_ready(fifo_sink_ready),.o_sink_reset_done(o_sink_reset_done)
    );
endmodule
