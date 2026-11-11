`timescale 1ns / 1ps
`include "c2h_transport_limits.vh"
// Single-grant dedicated DMA transport. The read fence shares the data RQ
// stream; no result is safe until its checked Completion (or known zero DMA).
module c2h_native_rx_transport (
    input wire i_clk, input wire i_rst_n, input wire i_link_up, input wire i_bme,
    input wire i_external_fault,
    input wire i_source_abort,
    output wire [31:0] o_fence_cookie,
    input wire [127:0] i_cq_data, input wire [3:0] i_cq_keep,
    input wire [87:0] i_cq_user, input wire i_cq_last, input wire i_cq_valid,
    output wire o_cq_ready,
    output wire [127:0] o_cc_data, output wire [3:0] o_cc_keep,
    output wire [32:0] o_cc_user, output wire o_cc_last, output wire o_cc_valid,
    input wire i_cc_ready,
    output wire [127:0] o_tlp_data,
    output wire [63:0] o_tlp_address,
    output wire [7:0] o_tlp_byte_enable,
    output wire [12:0] o_tlp_byte_length,
    output wire [1:0] o_tlp_format,
    output wire [9:0] o_tlp_tag,
    output wire o_tlp_header_valid, o_tlp_data_valid, o_tlp_end,
    input wire i_tlp_halt,
    input wire [127:0] i_rc_data, input wire [3:0] i_rc_keep,
    input wire [74:0] i_rc_user, input wire i_rc_last, input wire i_rc_valid,
    output wire o_rc_ready,
    input wire i_record_valid, output wire o_record_ready,
    input wire [31:0] i_record_length, input wire [127:0] i_record_identity,
    input wire [127:0] i_axis_data, input wire [15:0] i_axis_keep,
    input wire i_axis_last, input wire i_axis_valid, output wire o_axis_ready,
    // Internal product lifecycle; not a BAR/host ABI change.
    output wire o_record_retire_valid,
    output wire [127:0] o_record_retire_identity,
    output wire [31:0] o_record_retire_status,
    output wire o_record_cancel,
    output wire o_result_pending, output wire o_quarantine, output wire o_buffer_armed,
    // Observation only; these signals never qualify transport operations.
    output wire [2:0] o_observe_state,
    output wire o_observe_submit,
    output wire [31:0] o_axil_awaddr, output wire [2:0] o_axil_awprot,
    output wire o_axil_awvalid, input wire i_axil_awready,
    output wire [31:0] o_axil_wdata, output wire [3:0] o_axil_wstrb,
    output wire o_axil_wvalid, input wire i_axil_wready,
    input wire [1:0] i_axil_bresp, input wire i_axil_bvalid, output wire o_axil_bready,
    output wire [31:0] o_axil_araddr, output wire [2:0] o_axil_arprot,
    output wire o_axil_arvalid, input wire i_axil_arready,
    input wire [31:0] i_axil_rdata, input wire [1:0] i_axil_rresp,
    input wire i_axil_rvalid, output wire o_axil_rready, output wire o_axil_fault
);
    localparam [3:0] S_IDLE=0, S_WAIT=1, S_LAUNCH=2, S_RUN=3,
        S_FENCE=4, S_COMPLETION=5, S_RESULT=6, S_FAULT=7;
    reg [3:0] state, next_state;
    reg stopped, fault, bound, cancel_pending, session_valid, source_abort_seen;
    reg [31:0] command_error, result_code, local_bytes, record_length;
    reg [31:0] last_generation;
    reg [63:0] session;
    reg [63:0] shadow_address, shadow_fence, dma_address, fence_address;
    reg [31:0] shadow_capacity, shadow_cookie, capacity, fence_cookie;
    reg [127:0] shadow_identity, identity, record_identity;
    assign o_fence_cookie=fence_cookie;
    wire [11:0] reg_address;
    wire reg_write;
    wire [31:0] reg_wdata;
    wire [3:0] reg_wstrb;
    reg [31:0] reg_rdata;
    wire control = reg_write && reg_address == 12'h008 && reg_wstrb == 4'hf;
    wire submit = control && reg_wdata == 1;
    wire cancel = control && reg_wdata == 2 && shadow_identity == identity;
    wire stop = control && reg_wdata == 4;
    wire resume = control && reg_wdata == 8;
    wire ack = control && reg_wdata == 16 && shadow_identity == identity;
    wire permitted = i_link_up && i_bme && !fault && !i_external_fault;
    wire abort_job = cancel_pending || cancel || stop;
    wire [64:0] shadow_end = {1'b0,shadow_address} + {33'd0,shadow_capacity};
    wire descriptor_bad = shadow_address[3:0] != 0 || shadow_capacity == 0 ||
        shadow_capacity > `C2H_MAX_RECORD_BYTES || shadow_end[64] || shadow_fence[1:0] != 0 ||
        shadow_fence > 64'hfffffffffffffffb ||
        (shadow_fence >= shadow_address && shadow_fence < shadow_end[63:0]);
    wire stale_identity = shadow_identity[63:32] == 0 || shadow_identity[127:64] == 0 ||
        (session_valid && (shadow_identity[127:64] != session || shadow_identity[63:32] <= last_generation));
    wire accept_submit = submit && state == S_IDLE && !stopped && permitted && !descriptor_bad && !stale_identity;
    assign o_observe_state=state[2:0];
    assign o_observe_submit=accept_submit;
    wire record_bad = i_record_length == 0 || i_record_length > capacity || i_record_length > `C2H_MAX_RECORD_BYTES;
    wire record_fire = o_record_ready && i_record_valid;
    wire packet_cmd_ready, packet_result_valid;
    wire [2:0] packet_status;
    wire [31:0] packet_bytes;
    wire [127:0] packet_data;
    wire [63:0] packet_address;
    wire [7:0] packet_be;
    wire [12:0] packet_length;
    wire [1:0] packet_format;
    wire packet_hv,packet_dv,packet_eot;
    // The actual bridge packs a one-DWORD RC Completion into one 128-bit beat.
    wire completion_good = i_rc_last && i_rc_keep == 4'hf &&
        i_rc_data[71:64] == 8'h1a && i_rc_data[45:43] == 0 && !i_rc_data[46] &&
        i_rc_data[42:32] == 1 && i_rc_data[28:16] == 4 &&
        i_rc_data[15:12] == 0 && i_rc_data[6:0] == fence_address[6:0] &&
        i_rc_data[127:96] == fence_cookie && i_rc_data[30] &&
        i_rc_user[42] && !i_rc_user[32];

    c2h_bar_cq bar (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_cq_data(i_cq_data), .i_cq_keep(i_cq_keep),
        .i_cq_user(i_cq_user), .i_cq_last(i_cq_last), .i_cq_valid(i_cq_valid), .o_cq_ready(o_cq_ready),
        .o_cc_data(o_cc_data), .o_cc_keep(o_cc_keep), .o_cc_user(o_cc_user),
        .o_cc_last(o_cc_last), .o_cc_valid(o_cc_valid), .i_cc_ready(i_cc_ready),
        .o_reg_address(reg_address), .o_reg_write(reg_write), .o_reg_wdata(reg_wdata),
        .o_reg_wstrb(reg_wstrb), .i_reg_rdata(reg_rdata),
        .o_axil_awaddr(o_axil_awaddr),.o_axil_awprot(o_axil_awprot),.o_axil_awvalid(o_axil_awvalid),.i_axil_awready(i_axil_awready),
        .o_axil_wdata(o_axil_wdata),.o_axil_wstrb(o_axil_wstrb),.o_axil_wvalid(o_axil_wvalid),.i_axil_wready(i_axil_wready),
        .i_axil_bresp(i_axil_bresp),.i_axil_bvalid(i_axil_bvalid),.o_axil_bready(o_axil_bready),
        .o_axil_araddr(o_axil_araddr),.o_axil_arprot(o_axil_arprot),.o_axil_arvalid(o_axil_arvalid),.i_axil_arready(i_axil_arready),
        .i_axil_rdata(i_axil_rdata),.i_axil_rresp(i_axil_rresp),.i_axil_rvalid(i_axil_rvalid),.o_axil_rready(o_axil_rready),.o_axil_fault(o_axil_fault)
    );
    c2h_native_packetizer #(.MAX_RECORD_BYTES(`C2H_MAX_RECORD_BYTES)) packetizer (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_dma_enable(permitted),.i_source_abort(source_abort_seen||(bound&&i_source_abort)),
        .i_cmd_valid(state == S_LAUNCH), .o_cmd_ready(packet_cmd_ready),
        .i_cmd_address(dma_address), .i_cmd_length(record_length), .i_cmd_capacity(capacity),
        .i_cmd_identity(identity), .i_cancel_valid(abort_job), .i_cancel_identity(identity),
        .i_axis_tdata(i_axis_data), .i_axis_tkeep(i_axis_keep), .i_axis_tlast(i_axis_last),
        .i_axis_tvalid(i_axis_valid), .o_axis_tready(o_axis_ready),
        .o_tlp_data(packet_data),.o_tlp_address(packet_address),.o_tlp_byte_enable(packet_be),
        .o_tlp_byte_length(packet_length),.o_tlp_format(packet_format),
        .o_tlp_header_valid(packet_hv),.o_tlp_data_valid(packet_dv),.o_tlp_end(packet_eot),
        .i_tlp_halt(i_tlp_halt || state==S_FENCE),
        .o_result_valid(packet_result_valid), .i_result_ready(state == S_RUN),
        .o_result_identity(), .o_result_status(packet_status), .o_local_emitted_bytes(packet_bytes)
    );
    // A checked result is retired by the matching host ACK only. S_RESULT's
    // existing fault bit alone misses a coincident incident, so guard the event
    // and the state transition using the current inputs as well.
    wire current_incident = i_external_fault ||
        (i_rc_valid && (state != S_COMPLETION || !completion_good)) ||
        (bound && (!i_link_up || !i_bme));
    assign o_record_retire_valid = i_rst_n && state == S_RESULT && ack && bound &&
        !fault && !current_incident;
    assign o_record_retire_identity = record_identity;
    assign o_record_retire_status = result_code;
    assign o_record_cancel = bound && (abort_job || source_abort_seen || !permitted);
    assign o_buffer_armed = state == S_WAIT && permitted && !abort_job && !stopped;
    assign o_record_ready = o_buffer_armed && !record_bad && !i_source_abort;
    assign o_rc_ready = 1;
    assign o_result_pending = state == S_RESULT || fault;
    assign o_quarantine = fault;
    assign o_tlp_data = state==S_FENCE ? 128'd0 : packet_data;
    assign o_tlp_address = state==S_FENCE ? fence_address : packet_address;
    assign o_tlp_byte_enable = state==S_FENCE ? 8'h0f : packet_be;
    assign o_tlp_byte_length = state==S_FENCE ? 13'd4 : packet_length;
    assign o_tlp_format = state==S_FENCE ? (fence_address[63:32]!=0 ? 2'b01 : 2'b00) : packet_format;
    assign o_tlp_tag = state==S_FENCE ? 10'h01a : 10'd0;
    assign o_tlp_header_valid = i_rst_n && (state==S_FENCE || packet_hv);
    assign o_tlp_data_valid = i_rst_n && state!=S_FENCE && packet_dv;
    assign o_tlp_end = state==S_FENCE ? 1'b1 : packet_eot;
    always @(*) begin
        reg_rdata = 0;
        case (reg_address)
            12'h000: reg_rdata = 32'h43324844;
            12'h004: reg_rdata = 1;
            12'h00c: reg_rdata = {24'd0,i_bme,i_link_up,bound,stopped,fault,
                (state == S_RESULT && !fault),(state == S_WAIT),(state != S_IDLE)};
            12'h010: reg_rdata = command_error;
            12'h014: reg_rdata = `C2H_MAX_RECORD_BYTES;
            12'h020: reg_rdata = shadow_address[31:0];
            12'h024: reg_rdata = shadow_address[63:32];
            12'h028: reg_rdata = shadow_capacity;
            12'h030: reg_rdata = shadow_identity[31:0];
            12'h034: reg_rdata = shadow_identity[63:32];
            12'h038: reg_rdata = shadow_identity[95:64];
            12'h03c: reg_rdata = shadow_identity[127:96];
            12'h040: reg_rdata = shadow_fence[31:0];
            12'h044: reg_rdata = shadow_fence[63:32];
            12'h048: reg_rdata = shadow_cookie;
            12'h080: reg_rdata = result_code;
            12'h084: reg_rdata = local_bytes;
            12'h088: reg_rdata = record_length;
            12'h090: reg_rdata = identity[31:0];
            12'h094: reg_rdata = identity[63:32];
            12'h098: reg_rdata = identity[95:64];
            12'h09c: reg_rdata = identity[127:96];
            12'h0a0: reg_rdata = record_identity[31:0];
            12'h0a4: reg_rdata = record_identity[63:32];
            12'h0a8: reg_rdata = record_identity[95:64];
            12'h0ac: reg_rdata = record_identity[127:96];
            default: reg_rdata = 0;
        endcase
    end
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: if (fault) next_state = S_FAULT; else if (accept_submit) next_state = S_WAIT;
            S_WAIT: begin
                if (fault) next_state = S_FAULT;
                else if (abort_job || !permitted || (i_record_valid && record_bad)) next_state = S_RESULT;
                else if (record_fire) next_state = S_LAUNCH;
            end
            S_LAUNCH: if (packet_cmd_ready) next_state = S_RUN;
            S_RUN: if (packet_result_valid) begin
                if (fault || !i_link_up || !i_bme) next_state = S_FAULT;
                else if (packet_bytes == 0) next_state = S_RESULT;
                else next_state = S_FENCE;
            end
            S_FENCE: if (!i_tlp_halt) begin
                if (fault || !i_link_up || !i_bme) next_state = S_FAULT;
                else next_state = S_COMPLETION;
            end
            S_COMPLETION: begin
                if (fault || !i_link_up || !i_bme) next_state = S_FAULT;
                else if (i_rc_valid) begin
                    if (completion_good) next_state = S_RESULT;
                    else next_state = S_FAULT;
                end
            end
            S_RESULT: begin
                if (fault || current_incident) next_state = S_FAULT;
                else if (ack) next_state = S_IDLE;
            end
            S_FAULT: next_state = S_FAULT;
            default: next_state = S_FAULT;
        endcase
    end
    // Ownership reset still asserts without a USER edge. Release the FSM's
    // small ASR tree on USER's falling edge, away from its rising capture edge.
    // The real USER waveform is rise@0/fall@2/period8: ownership Q -> this ASR
    // has 2ns recovery; this Q -> rising FSM ASR has 6ns. Both remain timed.
    (* preserve="true" *) reg state_reset_n=1'b0;
    always @(negedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) state_reset_n <= 1'b0;
        else state_reset_n <= 1'b1;
    end
    always @(posedge i_clk or negedge state_reset_n) begin
        if (!state_reset_n) state <= S_IDLE;
        else state <= next_state;
    end
    // These internal grant fields are used only after accept_submit, which
    // overwrites the entire bundle. TLP header/data valid and fence_start
    // close asynchronously through the unchanged control/packetizer paths.
    // BAR-readable shadow, result and identity registers keep async reset.
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            dma_address<=0;fence_address<=0;capacity<=0;fence_cookie<=0;
        end else if (accept_submit) begin
            dma_address<=shadow_address;fence_address<=shadow_fence;
            capacity<=shadow_capacity;fence_cookie<=shadow_cookie;
        end
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            stopped<=1; fault<=0; bound<=0; cancel_pending<=0; session_valid<=0;source_abort_seen<=0;
            command_error<=0; result_code<=0; local_bytes<=0; record_length<=0;
            last_generation<=0; session<=0; shadow_address<=0; shadow_fence<=0;
            shadow_capacity<=0; shadow_cookie<=0;
            shadow_identity<=0; identity<=0; record_identity<=0;
        end else begin
            if (reg_write && reg_wstrb == 4'hf) begin
                case (reg_address)
                    12'h020: shadow_address[31:0]<=reg_wdata;
                    12'h024: shadow_address[63:32]<=reg_wdata;
                    12'h028: shadow_capacity<=reg_wdata;
                    12'h030: shadow_identity[31:0]<=reg_wdata;
                    12'h034: shadow_identity[63:32]<=reg_wdata;
                    12'h038: shadow_identity[95:64]<=reg_wdata;
                    12'h03c: shadow_identity[127:96]<=reg_wdata;
                    12'h040: shadow_fence[31:0]<=reg_wdata;
                    12'h044: shadow_fence[63:32]<=reg_wdata;
                    12'h048: shadow_cookie<=reg_wdata;
                    default: begin end
                endcase
            end
            if (control) begin
                command_error <= 0;
                if (submit && !accept_submit) begin
                    if (state != S_IDLE || stopped || !permitted) command_error<=1;
                    else if (descriptor_bad) command_error<=2;
                    else if (stale_identity) command_error<=3;
                end else if ((reg_wdata == 2 || reg_wdata == 16) && shadow_identity != identity)
                    command_error <= 3;
                else if (reg_wdata != 1 && reg_wdata != 2 && reg_wdata != 4 && reg_wdata != 8 && reg_wdata != 16)
                    command_error <= 4;
                else if ((resume && (state != S_IDLE || fault)) || (ack && state != S_RESULT)) command_error <= 1;
            end
            if (stop) stopped <= 1;
            if (resume && state == S_IDLE && !fault) stopped <= 0;
            if (cancel || stop) cancel_pending <= 1;
            if (accept_submit) begin
                identity<=shadow_identity; result_code<=0; local_bytes<=0;
                record_length<=0; record_identity<=0; bound<=0; cancel_pending<=0;source_abort_seen<=0;
                session<=shadow_identity[127:64]; last_generation<=shadow_identity[63:32]; session_valid<=1;
            end
            if (record_fire) begin
                record_length<=i_record_length; record_identity<=i_record_identity; bound<=1;
            end
            if (state == S_WAIT) begin
                if (abort_job || !permitted) result_code<=1;
                else if (i_record_valid && record_bad) result_code<=3;
            end
            if (state == S_RUN && packet_result_valid) begin
                local_bytes<=packet_bytes;
                if (packet_status == 0) result_code<=0;
                else if (packet_status == 2) result_code<=1;
                else if (packet_status == 6) result_code<=6;
                else result_code<=2;
            end
            if (o_record_retire_valid) bound<=0;
            if ((state == S_FENCE || state == S_COMPLETION) && abort_job && result_code == 0)result_code<=1;
            if(bound&&i_source_abort&&state!=S_RESULT&&state!=S_FAULT)begin source_abort_seen<=1;result_code<=6;end
            if (bound && (!i_link_up || !i_bme)) begin fault<=1; result_code<=4; end
            if (i_rc_valid && (state != S_COMPLETION || !completion_good)) begin fault<=1; result_code<=5; end
            if (state > S_FAULT) begin fault<=1; result_code<=5; end
            if (i_external_fault) begin fault<=1; result_code<=4; end
            // Keep the first latched failure. Same-edge priority above stays
            // unchanged; later incidents cannot erase a fence/protocol cause.
            if (fault) result_code<=result_code;
        end
    end
endmodule
