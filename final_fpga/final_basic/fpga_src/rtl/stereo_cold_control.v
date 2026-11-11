`timescale 1ns/1ps
`default_nettype none
`include "pcie_protocol_v1.vh"
`include "stereo_control_v1.vh"
`include "raw_video_v1.vh"
// Cold, pre-stream mode mailbox. No mode change is permitted after APP/DMA starts.
module stereo_cold_control #(
    parameter integer FRAME_DIVISOR=2, RAW_EXPORT_ENABLE=0
)(
    input wire user_clk,user_rst_n,pixel_clk,pixel_rst_n,dfi_clk,dfi_rst_n,
    input wire write_valid,input wire [11:0] write_offset,
    input wire [31:0] write_data,input wire [3:0] write_strobes,
    output wire [1:0] write_response,
    input wire read_valid,input wire [11:0] read_offset,
    output reg read_response_valid,output reg [31:0] read_data,
    output reg [1:0] read_response,
    input wire i_app_enable,i_c2h_running,i_user_config_idle,
    input wire i_pixel_quiet,i_dfi_quiet,
    output wire o_user_busy,o_user_locked,o_user_mode,o_user_start_inhibit,
    output wire o_pixel_mode,o_dfi_mode,
    output wire o_user_raw,o_pixel_raw,o_dfi_raw,
    output wire [7:0] o_user_frame_divisor,
    output reg [7:0] o_pixel_frame_divisor,o_dfi_frame_divisor,
    output wire o_pixel_pause,o_dfi_pause
);
    wire cohort=user_rst_n&&pixel_rst_n&&dfi_rst_n;
    wire urst,prst,drst;
    reset_release_sync u_user_release(.i_clk(user_clk),.i_async_rst_n(cohort),.o_rst_n(urst));
    reset_release_sync u_pixel_release(.i_clk(pixel_clk),.i_async_rst_n(cohort),.o_rst_n(prst));
    reset_release_sync u_dfi_release(.i_clk(dfi_clk),.i_async_rst_n(cohort),.o_rst_n(drst));
    reg [1:0] requested_mode,active_mode,pixel_mode,dfi_mode;
    reg [7:0] requested_divisor,active_divisor;
    reg requested_raw,active_raw,pixel_raw,dfi_raw;
    // One held mailbox bundle: {divisor[7:0], mode[1:0]}.
    // Stable from request publication until both recipients have acknowledged.
    (* preserve *) reg [10:0] held_profile;
    reg request_toggle,release_toggle;
    reg busy,done,locked,quarantined;
    reg [2:0] error;
    reg pixel_ack,dfi_ack;
    reg [1:0] pixel_ack_sync,dfi_ack_sync;
    reg [1:0] pixel_request_sync,dfi_request_sync;
    reg [1:0] pixel_release_sync,dfi_release_sync;
    reg [1:0] pixel_quarantine_sync,dfi_quarantine_sync;
    wire started=i_app_enable||i_c2h_running;
    wire mode_write=write_offset==`PCIE_REG_STEREO_REQUEST_MODE;
    wire divisor_write=write_offset==`PCIE_REG_STEREO_REQUEST_DIVISOR;
    wire apply_write=write_offset==`PCIE_REG_STEREO_COMMAND;
    wire product_write=RAW_EXPORT_ENABLE!=0&&write_offset==`PCIE_RAW_VIDEO_REQUEST_PRODUCT;
    wire legal_shape=write_strobes==4'hf &&
        ((mode_write&&write_data<=`STEREO_MODES_DUAL_JPEG)||
         (divisor_write&&write_data>=1&&write_data<=`STEREO_MAXIMUM_FRAME_DIVISOR)||
         (product_write&&write_data<=1)||
         (apply_write&&write_data==`STEREO_COMMANDS_APPLY));
    wire allowed=urst&&!busy&&!locked&&!started&&!quarantined&&i_user_config_idle;
    wire accepted=write_valid&&allowed&&legal_shape;
    assign write_response=allowed&&legal_shape?2'b00:2'b10;
    assign o_user_busy=busy;
    assign o_user_locked=locked;
    assign o_user_mode=active_mode!=`STEREO_MODES_MONO;
    assign o_pixel_mode=pixel_mode!=`STEREO_MODES_MONO;
    assign o_dfi_mode=dfi_mode!=`STEREO_MODES_MONO;
    assign o_user_raw=RAW_EXPORT_ENABLE!=0&&active_raw;
    assign o_pixel_raw=RAW_EXPORT_ENABLE!=0&&pixel_raw;
    assign o_dfi_raw=RAW_EXPORT_ENABLE!=0&&dfi_raw;
    assign o_user_frame_divisor=active_divisor;
    assign o_user_start_inhibit=!urst||busy||quarantined;
    // Both recipients block admission until USER releases the jointly applied request.
    assign o_pixel_pause=!prst||pixel_request_sync[1]!=pixel_ack||
        pixel_release_sync[1]!=pixel_ack||pixel_quarantine_sync[1];
    assign o_dfi_pause=!drst||dfi_request_sync[1]!=dfi_ack||
        dfi_release_sync[1]!=dfi_ack||dfi_quarantine_sync[1];
    always @(posedge user_clk or negedge urst)begin
        if(!urst)begin
            requested_mode<=0;active_mode<=0;request_toggle<=0;release_toggle<=0;
            requested_divisor<=FRAME_DIVISOR;active_divisor<=FRAME_DIVISOR;
            requested_raw<=0;active_raw<=0;
            held_profile<={1'b0,FRAME_DIVISOR[7:0],2'd0};
            busy<=0;done<=0;locked<=0;quarantined<=0;error<=0;
            pixel_ack_sync<=0;dfi_ack_sync<=0;
        end else begin
            pixel_ack_sync<={pixel_ack_sync[0],pixel_ack};
            dfi_ack_sync<={dfi_ack_sync[0],dfi_ack};
            if(started)locked<=1;
            if(busy&&started)begin
                // An out-of-contract DMA start cannot publish a partially applied mode.
                quarantined<=1;error<=`STEREO_ERRORS_LOCKED;
            end
            if(busy&&!quarantined&&!started&&pixel_ack_sync[1]==request_toggle&&
                dfi_ack_sync[1]==request_toggle)begin
                release_toggle<=request_toggle;active_mode<=held_profile[1:0];
                active_divisor<=held_profile[9:2];active_raw<=held_profile[10];busy<=0;done<=1;
            end
            if(write_valid)begin
                if(!legal_shape)error<=`STEREO_ERRORS_INVALID;
                else if(locked||started||quarantined)error<=`STEREO_ERRORS_LOCKED;
                else if(busy||!i_user_config_idle)error<=`STEREO_ERRORS_BUSY;
                else if(accepted)begin
                    error<=0;
                    done<=0;
                    if(mode_write)begin
                        requested_mode<=write_data[1:0];
                        requested_divisor<=FRAME_DIVISOR;
                    end else if(divisor_write)requested_divisor<=write_data[7:0];
                    else if(product_write)requested_raw<=write_data[0];
                    else begin held_profile<={requested_raw,requested_divisor,requested_mode};
                        request_toggle<=!request_toggle;busy<=1;end
                end
            end
        end
    end
    // The complete held bundle is sampled only after two request stages and
    // real local quiet. No field is separately synchronized or applied early.
    always @(posedge pixel_clk or negedge prst)begin
        if(!prst)begin
            pixel_request_sync<=0;pixel_release_sync<=0;pixel_quarantine_sync<=0;
            pixel_ack<=0;pixel_mode<=0;pixel_raw<=0;o_pixel_frame_divisor<=FRAME_DIVISOR;
        end else begin
            pixel_request_sync<={pixel_request_sync[0],request_toggle};
            pixel_release_sync<={pixel_release_sync[0],release_toggle};
            pixel_quarantine_sync<={pixel_quarantine_sync[0],quarantined};
            if(pixel_request_sync[1]!=pixel_ack&&i_pixel_quiet)begin
                pixel_mode<=held_profile[1:0];o_pixel_frame_divisor<=held_profile[9:2];
                pixel_raw<=held_profile[10];
                pixel_ack<=pixel_request_sync[1];
            end
        end
    end
    always @(posedge dfi_clk or negedge drst)begin
        if(!drst)begin
            dfi_request_sync<=0;dfi_release_sync<=0;dfi_quarantine_sync<=0;
            dfi_ack<=0;dfi_mode<=0;dfi_raw<=0;o_dfi_frame_divisor<=FRAME_DIVISOR;
        end else begin
            dfi_request_sync<={dfi_request_sync[0],request_toggle};
            dfi_release_sync<={dfi_release_sync[0],release_toggle};
            dfi_quarantine_sync<={dfi_quarantine_sync[0],quarantined};
            if(dfi_request_sync[1]!=dfi_ack&&i_dfi_quiet)begin
                dfi_mode<=held_profile[1:0];o_dfi_frame_divisor<=held_profile[9:2];
                dfi_raw<=held_profile[10];
                dfi_ack<=dfi_request_sync[1];
            end
        end
    end
    always @(posedge user_clk)begin
        if(!urst)begin read_response_valid<=0;read_data<=0;read_response<=0;end
        else begin
            read_response_valid<=read_valid;read_response<=0;read_data<=0;
            if(read_valid)case(read_offset)
                `PCIE_REG_STEREO_MAGIC:read_data<=`STEREO_MAGIC;
                `PCIE_REG_STEREO_ABI_VERSION:read_data<=`STEREO_ABI_VERSION;
                `PCIE_REG_STEREO_CAPABILITIES:read_data<={8'd255,8'd0,FRAME_DIVISOR[7:0],8'h03};
                `PCIE_REG_STEREO_REQUEST_MODE:read_data<={30'd0,requested_mode};
                `PCIE_REG_STEREO_REQUEST_DIVISOR:read_data<={24'd0,requested_divisor};
                `PCIE_REG_STEREO_STATUS:read_data<={27'd0,active_mode,locked,done,busy};
                `PCIE_REG_STEREO_ERROR:read_data<={29'd0,error};
                `PCIE_REG_STEREO_ACTIVE_MODE:read_data<={30'd0,active_mode};
                `PCIE_REG_STEREO_ACTIVE_DIVISOR:read_data<={24'd0,active_divisor};
                `PCIE_RAW_VIDEO_REQUEST_PRODUCT:begin
                    read_data<={31'd0,requested_raw};if(RAW_EXPORT_ENABLE==0)read_response<=2'b10;
                end
                `PCIE_RAW_VIDEO_ACTIVE_PRODUCT:begin
                    read_data<={31'd0,active_raw};if(RAW_EXPORT_ENABLE==0)read_response<=2'b10;
                end
                default:read_response<=2'b10;
            endcase
        end
    end
    generate if(FRAME_DIVISOR<1||FRAME_DIVISOR>255)begin:g_bad_divisor
        STEREO_CADENCE_REQUIRES_DIVISOR_1_TO_255 invalid_parameter();
    end endgenerate
endmodule
`default_nettype wire
