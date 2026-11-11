`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// User-domain JPEG ring controls. Descriptor parts publish atomically at DONE.
module jpeg_frame_bar (
    input wire i_clk, i_rst_n, i_stream_ready, i_session_initialized,
    input wire [31:0] i_session_id,
    input wire i_write_valid, input wire [11:0] i_write_offset,
    input wire [31:0] i_write_data, input wire [3:0] i_write_strobes,
    output wire [1:0] o_write_response,
    input wire i_read_valid, input wire [11:0] i_read_offset,
    output reg o_read_response_valid, output reg [31:0] o_read_data,
    output reg [1:0] o_read_response,
    output reg [146:0] o_command_data, output reg o_command_valid,
    input wire i_command_ready,
    input wire [146:0] i_response_data, input wire i_response_valid,
    output wire o_response_ready
);
    reg [31:0] request_camera, request_slot, request_generation, request_session, request_sequence;
    reg [31:0] active_sequence, active_session, response_sequence;
    reg busy, done;
    reg [3:0] error_code;
    reg [127:0] descriptor0, descriptor1, pending0;
    wire session_ready = i_stream_ready && i_session_initialized;
    wire parameter_write = i_write_offset >= `PCIE_REG_JPEG_REQUEST_CAMERA &&
                           i_write_offset <= `PCIE_REG_JPEG_REQUEST_SEQUENCE;
    wire command_write = i_write_offset == `PCIE_REG_JPEG_COMMAND;
    assign o_write_response = !busy && (parameter_write || command_write) &&
                              i_write_offset[1:0] == 0 ? 2'd0 : 2'd2;
    assign o_response_ready = 1'b1;
    function [31:0] merge_bytes;
        input [31:0] old_value,new_value;input [3:0] strobes;integer lane;
        begin merge_bytes=old_value;for(lane=0;lane<4;lane=lane+1)
            if(strobes[lane]) merge_bytes[lane*8+:8]=new_value[lane*8+:8];end
    endfunction
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            request_camera<=0;request_slot<=0;request_generation<=0;request_session<=0;request_sequence<=0;
            active_sequence<=0;active_session<=0;response_sequence<=0;busy<=0;done<=0;error_code<=0;
            descriptor0<=0;descriptor1<=0;pending0<=0;o_command_data<=0;o_command_valid<=0;
        end else begin
            if(o_command_valid && i_command_ready) o_command_valid<=0;
            if(i_write_valid && o_write_response==0) case(i_write_offset)
                `PCIE_REG_JPEG_REQUEST_CAMERA: request_camera<=merge_bytes(request_camera,i_write_data,i_write_strobes);
                `PCIE_REG_JPEG_REQUEST_SLOT: request_slot<=merge_bytes(request_slot,i_write_data,i_write_strobes);
                `PCIE_REG_JPEG_REQUEST_GENERATION: request_generation<=merge_bytes(request_generation,i_write_data,i_write_strobes);
                `PCIE_REG_JPEG_REQUEST_SESSION: request_session<=merge_bytes(request_session,i_write_data,i_write_strobes);
                `PCIE_REG_JPEG_REQUEST_SEQUENCE: request_sequence<=merge_bytes(request_sequence,i_write_data,i_write_strobes);
                `PCIE_REG_JPEG_COMMAND: begin
                    active_sequence<=request_sequence;active_session<=i_session_id;
                    done<=0;error_code<=0;
                    if(!session_ready) begin done<=1;response_sequence<=request_sequence;error_code<=`PCIE_JPEG_ERROR_RESET;end
                    else if(i_write_strobes!=4'hf || request_sequence==0 || request_sequence==active_sequence ||
                            i_write_data>`PCIE_JPEG_COMMAND_RELEASE || request_camera>=`PCIE_JPEG_CAMERA_COUNT ||
                            (request_slot>=`PCIE_JPEG_SLOT_COUNT && !(i_write_data==0 && request_slot==`PCIE_JPEG_LATEST_SLOT)) ||
                            (i_write_data!=0 && request_generation==0)) begin
                        done<=1;response_sequence<=request_sequence;error_code<=`PCIE_JPEG_ERROR_INVALID;
                    end else if(i_write_data!=0 && request_session!=i_session_id) begin
                        done<=1;response_sequence<=request_sequence;error_code<=`PCIE_JPEG_ERROR_STALE;
                    end else begin
                        busy<=1;o_command_valid<=1;
                        // QUERY latest is always scoped to the current initialized session.
                        o_command_data<={64'd0,(i_write_data==0 ? i_session_id : request_session),
                                         request_generation,request_slot[15:0],request_camera[0],i_write_data[1:0]};
                    end
                end
                default: begin end
            endcase
            if(busy && i_response_valid && o_response_ready) begin
                if(i_response_data[146:145]==0) pending0<=i_response_data[127:0];
                else if(i_response_data[146:145]==1) begin
                    descriptor0<=pending0;descriptor1<=i_response_data[127:0];
                    busy<=0;done<=1;response_sequence<=active_sequence;error_code<=i_response_data[89:86];
                end
            end
            // Retained BAR reset domain detects application/stream recovery explicitly.
            if(busy && (!session_ready || active_session!=i_session_id)) begin
                busy<=0;done<=1;response_sequence<=active_sequence;error_code<=`PCIE_JPEG_ERROR_RESET;o_command_valid<=0;
            end
        end
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin o_read_response_valid<=0;o_read_data<=0;o_read_response<=0;end
        else begin
            o_read_response_valid<=i_read_valid;o_read_data<=0;o_read_response<=0;
            if(i_read_valid) begin
                if(i_read_offset[1:0]!=0) o_read_response<=2;
                else case(i_read_offset)
                    `PCIE_REG_JPEG_MAGIC: o_read_data<=`PCIE_JPEG_MAGIC;
                    `PCIE_REG_JPEG_ABI_VERSION: o_read_data<=`PCIE_JPEG_ABI_VERSION;
                    `PCIE_REG_JPEG_CONFIG: o_read_data<=`PCIE_JPEG_CONFIG;
                    `PCIE_REG_JPEG_MAX_FRAME: o_read_data<=`PCIE_JPEG_MAX_FRAME;
                    `PCIE_REG_JPEG_STATUS: o_read_data<={28'd0,session_ready,(error_code!=0),done,busy};
                    `PCIE_REG_JPEG_RESPONSE_SEQUENCE: o_read_data<=response_sequence;
                    `PCIE_REG_JPEG_ERROR: o_read_data<={28'd0,error_code};
                    `PCIE_REG_JPEG_SESSION: o_read_data<=i_session_id;
                    `PCIE_REG_JPEG_REQUEST_CAMERA: o_read_data<=request_camera;
                    `PCIE_REG_JPEG_REQUEST_SLOT: o_read_data<=request_slot;
                    `PCIE_REG_JPEG_REQUEST_GENERATION: o_read_data<=request_generation;
                    `PCIE_REG_JPEG_REQUEST_SESSION: o_read_data<=request_session;
                    `PCIE_REG_JPEG_REQUEST_SEQUENCE: o_read_data<=request_sequence;
                    `PCIE_REG_JPEG_DESC_CAMERA: o_read_data<={31'd0,descriptor1[81]};
                    `PCIE_REG_JPEG_DESC_SLOT: o_read_data<={16'd0,descriptor1[80:65]};
                    `PCIE_REG_JPEG_DESC_GENERATION: o_read_data<=descriptor0[95:64];
                    `PCIE_REG_JPEG_DESC_SESSION: o_read_data<=descriptor0[127:96];
                    `PCIE_REG_JPEG_DESC_FRAME_SEQUENCE: o_read_data<=descriptor0[31:0];
                    `PCIE_REG_JPEG_DESC_MODE_EPOCH: o_read_data<=descriptor0[63:32];
                    `PCIE_REG_JPEG_DESC_WIDTH: o_read_data<={16'd0,descriptor1[40:25]};
                    `PCIE_REG_JPEG_DESC_HEIGHT: o_read_data<={16'd0,descriptor1[56:41]};
                    `PCIE_REG_JPEG_DESC_LENGTH: o_read_data<={7'd0,descriptor1[24:0]};
                    `PCIE_REG_JPEG_DESC_STATE: o_read_data<={23'd0,descriptor1[82],5'd0,descriptor1[85:83]};
                    `PCIE_REG_JPEG_DESC_QUALITY: o_read_data<={24'd0,descriptor1[64:57]};
                    default: o_read_response<=2;
                endcase
            end
        end
    end
endmodule
