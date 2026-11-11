`timescale 1ns/1ps
// A soft reset is a drain request, never a product ownership reset. All clocks
// may stop independently. No timeout proves quiet or discards an old owner.
module production_soft_reset_fence (
    input wire user_clk,pixel_clk,dfi_clk,
    input wire cold_reset_n,
    input wire soft_reset_request,
    input wire pixel_quiet,dfi_quiet,user_quiet,
    input wire token_drain_proven_pixel,
    input wire pixel_data_reset_n,
    input wire user_initialized,input wire [31:0] user_session,
    input wire rearm_ready_async,
    output wire pause_pixel,
    output wire marker_request_pixel,
    output reg pending_user,
    output reg execute_reset_user
);
    // Cold ownership reset asserts asynchronously in every domain. Its
    // release must cross only the local three-stage release synchronizer;
    // ordinary fence state never receives an asynchronous SYS release.
    // A stopped clock cannot release its fence state or acknowledge a drain.
    wire cold_user_reset_n,cold_pixel_reset_n,cold_dfi_reset_n;
    reset_release_sync #(.FALLING_RELEASE(1)) u_user_cold_reset(
        .i_clk(user_clk),.i_async_rst_n(cold_reset_n),.o_rst_n(cold_user_reset_n));
    reset_release_sync u_pixel_cold_reset(
        .i_clk(pixel_clk),.i_async_rst_n(cold_reset_n),.o_rst_n(cold_pixel_reset_n));
    reset_release_sync u_dfi_cold_reset(
        .i_clk(dfi_clk),.i_async_rst_n(cold_reset_n),.o_rst_n(cold_dfi_reset_n));
    localparam [1:0] IDLE=0,DRAIN=1,EXECUTE=2,WAIT_BOOT=3;
    reg [1:0] state,state_next;
    reg drain_request_user;
    reg [31:0] old_session;
    reg quiet_seen;
    (* ASYNC_REG="TRUE" *) reg [1:0] pending_pixel,pending_dfi;
    (* ASYNC_REG="TRUE" *) reg [1:0] drain_pixel;
    (* ASYNC_REG="TRUE" *) reg [1:0] pause_ack_user,dfi_ack_user;
    (* ASYNC_REG="TRUE" *) reg [1:0] pixel_quiet_user,dfi_quiet_user;
    (* ASYNC_REG="TRUE" *) reg [1:0] data_reset_user,rearm_user;
    (* ASYNC_REG="TRUE" *) reg [1:0] token_proof_user;
    assign pause_pixel=pending_pixel[1];
    assign marker_request_pixel=drain_pixel[1];
    always @(posedge pixel_clk or negedge cold_pixel_reset_n)begin
        if(!cold_pixel_reset_n)begin pending_pixel<=0;drain_pixel<=0;end
        else begin pending_pixel<={pending_pixel[0],pending_user};drain_pixel<={drain_pixel[0],drain_request_user};end
    end
    always @(posedge dfi_clk or negedge cold_dfi_reset_n)begin
        if(!cold_dfi_reset_n)pending_dfi<=0;
        else pending_dfi<={pending_dfi[0],pending_user};
    end
    wire all_quiet=pause_ack_user[1]&&dfi_ack_user[1]&&
        pixel_quiet_user[1]&&dfi_quiet_user[1]&&user_quiet&&token_proof_user[1];
    // All three exported USER policies are registered from the same state
    // transition. Binary DRAIN->EXECUTE or WAIT_BOOT->IDLE cannot decode a pulse.
    always @*begin
        state_next=state;
        case(state)
            IDLE:if(soft_reset_request)state_next=DRAIN;
            DRAIN:if(all_quiet&&quiet_seen&&data_reset_user[1]&&user_initialized)state_next=EXECUTE;
            EXECUTE:if(!data_reset_user[1])state_next=WAIT_BOOT;
            WAIT_BOOT:if(data_reset_user[1]&&user_initialized&&user_session!=0&&
                user_session!=old_session&&rearm_user[1])state_next=IDLE;
        endcase
    end
    always @(posedge user_clk or negedge cold_user_reset_n)begin
        if(!cold_user_reset_n)begin
            state<=IDLE;pending_user<=0;execute_reset_user<=0;drain_request_user<=0;old_session<=0;quiet_seen<=0;
            pause_ack_user<=0;dfi_ack_user<=0;pixel_quiet_user<=0;dfi_quiet_user<=0;
            data_reset_user<=0;rearm_user<=0;token_proof_user<=0;
        end else begin
            state<=state_next;pending_user<=state_next!=IDLE;
            execute_reset_user<=state_next==EXECUTE;drain_request_user<=state_next==DRAIN;
            pause_ack_user<={pause_ack_user[0],pending_pixel[1]&&pixel_quiet};
            dfi_ack_user<={dfi_ack_user[0],pending_dfi[1]&&dfi_quiet};
            pixel_quiet_user<={pixel_quiet_user[0],pixel_quiet};
            dfi_quiet_user<={dfi_quiet_user[0],dfi_quiet};
            data_reset_user<={data_reset_user[0],pixel_data_reset_n};
            rearm_user<={rearm_user[0],rearm_ready_async};
            token_proof_user<={token_proof_user[0],token_drain_proven_pixel};
            case(state)
                IDLE:begin
                    quiet_seen<=0;
                    if(soft_reset_request)old_session<=user_session;
                end
                DRAIN:begin
                    quiet_seen<=all_quiet;
                end
                EXECUTE:begin
                    // Hold the request through stopped SYS/PIX clocks until
                    // the actual session data reset is observed asserted.
                end
                WAIT_BOOT:begin
                end
            endcase
        end
    end
endmodule
