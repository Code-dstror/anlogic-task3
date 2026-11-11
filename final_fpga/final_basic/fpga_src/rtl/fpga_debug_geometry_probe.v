`timescale 1ns/1ps
// One source-clock diagnostic bank. Requests are held by the 25 MHz controller
// until the matching acknowledgement returns; no unsynchronized status bus is
// sampled by the controller.
module fpga_debug_geometry_probe (
    input wire i_clk,
    input wire i_debug_rst_n,
    input wire i_request,
    input wire [39:0] i_command,
    output reg o_ack,
    output reg [39:0] o_response,
    input wire [511:0] i_status,
    input wire [511:0] i_geometry_status,
    input wire [95:0] i_sample,
    input wire i_frame_event,
    input wire i_error_event,
    input wire i_clear
);
    localparam [7:0] OK = 0, INVALID = 1, BUSY = 2;
    localparam [1:0] IDLE = 0, READ_WAIT = 1, READ_REPLY = 2;
    reg [1:0] state;
    reg req_meta, req_sync, clear_meta, clear_sync, clear_seen;
    reg [511:0] status_snapshot;
    reg [511:0] geometry_snapshot;
    reg [7:0] wr_addr, rd_addr, first_addr;
    reg [7:0] pre_count, post_left;
    reg [1:0] trigger_mode;
    reg armed, frozen, triggered, pending_trigger, first_error;
    reg [31:0] first_error_cycle, cycle_count;
    reg [1:0] rd_lane;
    wire [7:0] op = i_command[39:32];
    wire [31:0] arg = i_command[31:0];
    wire clear_now = clear_sync != clear_seen;
    wire selected_event = (trigger_mode == 1 && i_frame_event) ||
                          (trigger_mode == 2 && i_error_event);
    wire trigger_now = pre_count >= 8'd128 &&
                       (pending_trigger || selected_event);
    wire write_en = armed && !frozen && !clear_now;
    wire [99:0] ram_data = {4'b0, i_sample};
    wire [99:0] ram_q;
    // Each instance is an Anlogic 20K ERAM IP, sized 20 x 256. Five instances
    // avoid asking one physical 20K block to hold 96 x 256 bits.
    genvar bank;
    generate for (bank = 0; bank < 5; bank = bank + 1) begin: g_trace_ram
        isp_line_ram_20x1024_ip #(
            .DATA_WIDTH_A(20), .ADDR_WIDTH_A(8), .DATA_DEPTH_A(256),
            .DATA_WIDTH_B(20), .ADDR_WIDTH_B(8), .DATA_DEPTH_B(256)
        ) u_ram (
            .doa(), .dia(ram_data[bank*20+:20]), .addra(wr_addr),
            .cea(1'b1), .clka(i_clk), .wea(write_en),
            .dob(ram_q[bank*20+:20]), .dib(20'd0), .addrb(rd_addr),
            .ceb(1'b1), .web(1'b0)
        );
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
            geometry_snapshot <= 0;
            status_snapshot <= 0; wr_addr <= 0; rd_addr <= 0;
            first_addr <= 0; pre_count <= 0; post_left <= 0;
            trigger_mode <= 0; armed <= 0; frozen <= 0;
            triggered <= 0; pending_trigger <= 0; first_error <= 0;
            first_error_cycle <= 0; cycle_count <= 0;
            rd_lane <= 0;
        end else begin
            req_meta <= i_request; req_sync <= req_meta;
            clear_meta <= i_clear; clear_sync <= clear_meta;
            cycle_count <= cycle_count + 1'b1;
            if (i_error_event && !first_error) begin
                first_error <= 1;
                first_error_cycle <= cycle_count;
            end
            if (clear_now) begin
                clear_seen <= clear_sync;
                wr_addr <= 0; first_addr <= 0; pre_count <= 0;
                post_left <= 0; armed <= 0; frozen <= 0;
                triggered <= 0; pending_trigger <= 0; first_error <= 0;
                first_error_cycle <= 0;
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
                        // New geometry page; legacy status/trace commands are unchanged.
                        8'h12: begin
                            geometry_snapshot <= i_geometry_status;
                            o_response <= {OK,32'd0}; o_ack <= req_sync;
                        end
                        8'h13: begin
                            if (arg < 16) o_response <= {OK, geometry_snapshot[arg[3:0]*32+:32]};
                            else o_response <= {INVALID,32'd0};
                            o_ack <= req_sync;
                        end
                        8'h11: begin
                            status_snapshot <= i_status;
                            o_response <= {OK, 32'd0}; o_ack <= req_sync;
                        end
                        8'h10: begin
                            if (arg < 16) o_response <= {OK, status_snapshot[arg[3:0]*32+:32]};
                            else o_response <= {INVALID, 32'd0};
                            o_ack <= req_sync;
                        end
                        8'h20: begin
                            if (arg <= 2) begin
                                armed <= 1; frozen <= 0; triggered <= 0;
                                pre_count <= 0; post_left <= 0; wr_addr <= 0;
                                pending_trigger <= 0; trigger_mode <= arg[1:0];
                                o_response <= {OK, 32'd0};
                            end else o_response <= {INVALID, 32'd0};
                            o_ack <= req_sync;
                        end
                        8'h22: begin
                            if (armed && trigger_mode == 0) begin
                                pending_trigger <= 1;
                                o_response <= {OK, 32'd0};
                            end else o_response <= {BUSY, 32'd0};
                            o_ack <= req_sync;
                        end
                        8'h21: begin
                            if (!frozen) begin
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
                            o_response <= {OK, first_error_cycle[15:0],
                                           first_addr, 3'b0, first_error,
                                           triggered, (pre_count >= 128), frozen, armed};
                            o_ack <= req_sync;
                        end
                        8'h24: begin
                            o_response <= {OK, first_error_cycle}; o_ack <= req_sync;
                        end
                        default: begin
                            o_response <= {INVALID, 32'd0}; o_ack <= req_sync;
                        end
                    endcase
                end
                READ_WAIT: state <= READ_REPLY;
                READ_REPLY: begin
                    o_response <= {OK, read_value};
                    o_ack <= req_sync;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
