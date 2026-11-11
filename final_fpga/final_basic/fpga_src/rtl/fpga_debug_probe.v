`timescale 1ns/1ps
// One source-clock diagnostic bank. Requests are held by the 25 MHz controller
// until the matching acknowledgement returns; no unsynchronized status bus is
// sampled by the controller.
module fpga_debug_probe #(
    parameter integer DEBUG_PROFILE = 0,
    parameter integer DEBUG_EXT_ENABLE = 0,
    parameter integer TRACE_ENABLE = (DEBUG_PROFILE != 1),
    parameter integer GEOMETRY_ENABLE = 0,
    parameter integer JOB_STATUS_ENABLE = 0
) (
    input wire i_clk,
    input wire i_debug_rst_n,
    input wire i_request,
    input wire [39:0] i_command,
    output reg o_ack,
    output reg [39:0] o_response,
    input wire [511:0] i_status,
    input wire [511:0] i_geometry_status,
    input wire [255:0] i_job_status,
    input wire [95:0] i_sample,
    input wire i_frame_event,
    input wire i_error_event,
    input wire i_clear,
    input wire [31:0] i_fault_causes,
    input wire [255:0] i_fault_context,
    output wire o_clear_event
);
    localparam [7:0] OK = 0, INVALID = 1, BUSY = 2, UNSUPPORTED = 5;
    localparam [31:0] PROFILE_WORD = DEBUG_PROFILE;
    localparam [1:0] IDLE = 0, READ_WAIT = 1, READ_REPLY = 2;
    reg [1:0] state;
    reg req_meta, req_sync, clear_meta, clear_sync, clear_seen;
    reg [511:0] status_snapshot;
    reg [511:0] geometry_snapshot;
    reg geometry_valid;
    reg [255:0] job_snapshot;
    reg job_valid;
    reg [7:0] wr_addr, rd_addr, first_addr;
    reg [7:0] pre_count, post_left;
    reg [1:0] trigger_mode;
    reg armed, frozen, triggered, pending_trigger, first_error;
    reg [31:0] first_error_cycle, cycle_count;
    reg [31:0] clear_epoch, snapshot_epoch, fault_epoch, first_causes;
    reg [31:0] later_fault_count, previous_causes;
    reg [255:0] first_context;
    reg snapshot_valid, previous_error;
    reg [1:0] rd_lane;
    wire [7:0] op = i_command[39:32];
    wire [31:0] arg = i_command[31:0];
    wire legacy_clear = clear_sync != clear_seen;
    // The source-domain command is stable throughout request synchronization.
    // Local monitors consume this event on the same edge that completes ACK.
    assign o_clear_event = DEBUG_EXT_ENABLE != 0 && state == IDLE &&
        req_sync != o_ack && op == 8'h32 && arg == clear_epoch;
    wire clear_now = legacy_clear || o_clear_event;
    wire [31:0] new_causes = i_fault_causes & ~previous_causes;
    wire fault_edge = DEBUG_EXT_ENABLE != 0 ?
        ((|new_causes) || (i_error_event && !previous_error && !(|i_fault_causes))) :
        i_error_event;
    wire selected_event = (trigger_mode == 1 && i_frame_event) ||
                          (trigger_mode == 2 && i_error_event);
    wire trigger_now = pre_count >= 8'd128 &&
                       (pending_trigger || selected_event);
    wire write_en = TRACE_ENABLE != 0 && armed && !frozen && !clear_now;
    wire [99:0] ram_data = {4'b0, i_sample};
    wire [99:0] ram_q;
    // Each instance is an Anlogic 20K ERAM IP, sized 20 x 256. Five instances
    // avoid asking one physical 20K block to hold 96 x 256 bits.
    genvar bank;
    generate if (TRACE_ENABLE != 0) begin: g_trace_enabled
    for (bank = 0; bank < 5; bank = bank + 1) begin: g_trace_ram
        isp_line_ram_20x1024_ip #(
            .DATA_WIDTH_A(20), .ADDR_WIDTH_A(8), .DATA_DEPTH_A(256),
            .DATA_WIDTH_B(20), .ADDR_WIDTH_B(8), .DATA_DEPTH_B(256)
        ) u_ram (
            .doa(), .dia(ram_data[bank*20+:20]), .addra(wr_addr),
            .cea(1'b1), .clka(i_clk), .wea(write_en),
            .dob(ram_q[bank*20+:20]), .dib(20'd0), .addrb(rd_addr),
            .ceb(1'b1), .web(1'b0)
        );
    end
    end else begin: g_trace_disabled
        assign ram_q = 100'd0;
    end endgenerate
    wire [95:0] sample_q = ram_q[95:0];
    reg [31:0] read_value;
    always @* begin
        case (rd_lane)
            2'd0: read_value = sample_q[31:0];
            2'd1: read_value = sample_q[63:32];
            default: read_value = sample_q[95:64];
        endcase
    end
    always @(posedge i_clk or negedge i_debug_rst_n) begin
        if (!i_debug_rst_n) begin
            req_meta <= 0; req_sync <= 0; clear_meta <= 0;
            clear_sync <= 0; clear_seen <= 0;
            o_ack <= 0; o_response <= 0; state <= IDLE;
            status_snapshot <= 0; wr_addr <= 0; rd_addr <= 0;
            geometry_snapshot<=0;geometry_valid<=0;
            job_snapshot<=0;job_valid<=0;
            first_addr <= 0; pre_count <= 0; post_left <= 0;
            trigger_mode <= 0; armed <= 0; frozen <= 0;
            triggered <= 0; pending_trigger <= 0; first_error <= 0;
            first_error_cycle <= 0; cycle_count <= 0;
            clear_epoch <= 0; snapshot_epoch <= 0; snapshot_valid <= 0;
            fault_epoch <= 0; first_causes <= 0; first_context <= 0;
            later_fault_count <= 0; previous_causes <= 0; previous_error <= 0;
            rd_lane <= 0;
        end else begin
            req_meta <= i_request; req_sync <= req_meta;
            clear_meta <= i_clear; clear_sync <= clear_meta;
            cycle_count <= cycle_count + 1'b1;
            previous_causes <= i_fault_causes;
            previous_error <= i_error_event;
            if (fault_edge && !first_error) begin
                first_error <= 1;
                first_error_cycle <= cycle_count;
                first_causes <= i_fault_causes;
                first_context <= i_fault_context;
                fault_epoch <= clear_epoch;
            end else if (fault_edge && DEBUG_EXT_ENABLE != 0) begin
                later_fault_count <= later_fault_count + 1'b1;
            end
            if (clear_now) begin
                clear_seen <= clear_sync;
                clear_epoch <= clear_epoch + 1'b1;
                snapshot_valid <= 0;
                geometry_valid<=0;
                job_valid<=0;
                wr_addr <= 0; first_addr <= 0; pre_count <= 0;
                post_left <= 0; armed <= 0; frozen <= 0;
                triggered <= 0; pending_trigger <= 0; first_error <= 0;
                first_error_cycle <= 0;
                first_causes <= 0; first_context <= 0; later_fault_count <= 0;
                // A fault on the clear edge belongs to the new evidence epoch.
                if (fault_edge) begin
                    first_error <= 1; first_error_cycle <= cycle_count;
                    first_causes <= i_fault_causes; first_context <= i_fault_context;
                    fault_epoch <= clear_epoch + 1'b1;
                end
            end else if (write_en) begin
                wr_addr <= wr_addr + 1'b1;
                if (!triggered) begin
                    if (pre_count < 8'd128) pre_count <= pre_count + 1'b1;
                    if (selected_event) pending_trigger <= 1;
                    if (trigger_now) begin
                        triggered <= 1;
                        post_left <= 8'd127;
                        pending_trigger <= 0;
                    end
                end else if (post_left == 8'd1) begin
                    post_left <= 0;
                    frozen <= 1;
                    armed <= 0;
                    first_addr <= wr_addr + 1'b1;
                end else post_left <= post_left - 1'b1;
            end
            case (state)
                IDLE: if (req_sync != o_ack) begin
                    case (op)
                        8'h14: begin
                            if(JOB_STATUS_ENABLE == 0) o_response<={UNSUPPORTED,32'd0};
                            else begin
                                job_snapshot<=i_job_status;job_valid<=!clear_now;
                                o_response<={OK,32'd0};
                            end
                            o_ack<=req_sync;
                        end
                        8'h15: begin
                            if(JOB_STATUS_ENABLE == 0) o_response<={UNSUPPORTED,32'd0};
                            else if(!job_valid || clear_now) o_response<={BUSY,32'd0};
                            else if(arg<8) o_response<={OK,job_snapshot[arg[2:0]*32+:32]};
                            else o_response<={INVALID,32'd0};
                            o_ack<=req_sync;
                        end
                        8'h12: begin
                            if(GEOMETRY_ENABLE == 0) o_response<={UNSUPPORTED,32'd0};
                            else begin
                                geometry_snapshot<=i_geometry_status;geometry_valid<=!clear_now;
                                o_response<={OK,32'd0};
                            end
                            o_ack<=req_sync;
                        end
                        8'h13: begin
                            if(GEOMETRY_ENABLE == 0) o_response<={UNSUPPORTED,32'd0};
                            else if(!geometry_valid || clear_now) o_response<={BUSY,32'd0};
                            else if(arg<16) o_response<={OK,geometry_snapshot[arg[3:0]*32+:32]};
                            else o_response<={INVALID,32'd0};
                            o_ack<=req_sync;
                        end
                        8'h11: begin
                            status_snapshot <= i_status;
                            snapshot_epoch <= clear_epoch;
                            snapshot_valid <= !clear_now;
                            o_response <= {OK, 32'd0}; o_ack <= req_sync;
                        end
                        8'h10: begin
                            if (DEBUG_EXT_ENABLE != 0 && (!snapshot_valid || clear_now))
                                o_response <= {BUSY, 32'd0};
                            else if (arg < 16) o_response <= {OK, status_snapshot[arg[3:0]*32+:32]};
                            else o_response <= {INVALID, 32'd0};
                            o_ack <= req_sync;
                        end
                        8'h20: begin
                            if (TRACE_ENABLE == 0) o_response <= {UNSUPPORTED, 32'd0};
                            else if (arg <= 2) begin
                                armed <= 1; frozen <= 0; triggered <= 0;
                                pre_count <= 0; post_left <= 0; wr_addr <= 0;
                                pending_trigger <= 0; trigger_mode <= arg[1:0];
                                o_response <= {OK, 32'd0};
                            end else o_response <= {INVALID, 32'd0};
                            o_ack <= req_sync;
                        end
                        8'h22: begin
                            if (TRACE_ENABLE == 0) o_response <= {UNSUPPORTED, 32'd0};
                            else if (armed && trigger_mode == 0) begin
                                pending_trigger <= 1;
                                o_response <= {OK, 32'd0};
                            end else o_response <= {BUSY, 32'd0};
                            o_ack <= req_sync;
                        end
                        8'h21: begin
                            if (TRACE_ENABLE == 0) begin
                                o_response <= {UNSUPPORTED, 32'd0}; o_ack <= req_sync;
                            end else if (!frozen || clear_now) begin
                                o_response <= {BUSY, 32'd0}; o_ack <= req_sync;
                            end else if (arg >= 768) begin
                                o_response <= {INVALID, 32'd0}; o_ack <= req_sync;
                            end else begin
                                rd_lane <= arg[9:0] % 10'd3;
                                rd_addr <= first_addr + (arg[9:0] / 10'd3);
                                state <= READ_WAIT;
                            end
                        end
                        8'h23: begin
                            // bits 0..4: armed/frozen/primed/triggered/first_error;
                            // bits 15..8: physical first address; upper half: first
                            // fault's low 16 clock ticks (full tick via op 0x24).
                            if (TRACE_ENABLE == 0) o_response <= {UNSUPPORTED, 32'd0};
                            else o_response <= {OK, first_error_cycle[15:0],
                                           first_addr, 3'b0, first_error,
                                           triggered, (pre_count >= 128), frozen, armed};
                            o_ack <= req_sync;
                        end
                        8'h24: begin
                            o_response <= {OK, first_error_cycle}; o_ack <= req_sync;
                        end
                        8'h30: begin
                            if (DEBUG_EXT_ENABLE == 0) o_response <= {INVALID,32'd0};
                            else case (arg)
                                0: o_response <= {OK,32'h32474244};
                                1: o_response <= {OK,32'd1};
                                2: o_response <= {OK,PROFILE_WORD};
                                3: o_response <= {OK,32'd7 | (TRACE_ENABLE != 0 ? 32'd8 : 32'd0) |
                                                     (JOB_STATUS_ENABLE != 0 ? 32'd32 : 32'd0)};
                                default: o_response <= {INVALID,32'd0};
                            endcase
                            o_ack <= req_sync;
                        end
                        8'h31: begin
                            if (DEBUG_EXT_ENABLE == 0) o_response <= {INVALID,32'd0};
                            else case (arg)
                                0: o_response <= {OK,clear_epoch};
                                1: o_response <= {OK,snapshot_epoch};
                                2: o_response <= {OK,{31'd0,snapshot_valid && !clear_now}};
                                3: o_response <= {OK,frozen && !clear_now ? 32'd256 : 32'd0};
                                default: o_response <= {INVALID,32'd0};
                            endcase
                            o_ack <= req_sync;
                        end
                        8'h32: begin
                            if (DEBUG_EXT_ENABLE == 0 || arg != clear_epoch)
                                o_response <= {INVALID,32'd0};
                            else o_response <= {OK,clear_epoch + 1'b1};
                            o_ack <= req_sync;
                        end
                        8'h33: begin
                            if (DEBUG_EXT_ENABLE == 0) o_response <= {INVALID,32'd0};
                            else if (!first_error || clear_now) o_response <= {BUSY,32'd0};
                            else case (arg)
                                0: o_response <= {OK,first_causes};
                                1: o_response <= {OK,first_error_cycle};
                                2: o_response <= {OK,fault_epoch};
                                3: o_response <= {OK,later_fault_count};
                                4,5,6,7,8,9,10,11:
                                    o_response <= {OK,first_context[(arg[3:0]-4)*32+:32]};
                                default: o_response <= {INVALID,32'd0};
                            endcase
                            o_ack <= req_sync;
                        end
                        default: begin
                            o_response <= {INVALID, 32'd0}; o_ack <= req_sync;
                        end
                    endcase
                end
                READ_WAIT: state <= READ_REPLY;
                READ_REPLY: begin
                    if (DEBUG_EXT_ENABLE != 0 && (clear_now || !frozen))
                        o_response <= {BUSY,32'd0};
                    else o_response <= {OK, read_value};
                    o_ack <= req_sync;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
