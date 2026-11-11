`timescale 1ns/1ps
`default_nettype none
// Failed-frame local cleanup only. Never reset the JPEG/CDC/DDR/RAW owner.
module hdr_pair_product_abort_drain4 #(
    parameter integer SYNC_CLEAR_ENABLE = 0,
    parameter integer SEPARATE_DATA_RESET = 0,
    parameter integer FALLING_INPUT_RESET = 0
)(
    input wire clk,rst_n,
    input wire i_context_fire,input wire [63:0] i_context_tag,
    input wire i_source_fire,input wire [63:0] i_source_tag,
    input wire i_source_ok,i_source_read_quiescent,
    input wire i_native_job_start,
    input wire i_native_valid,i_isp_valid,i_preprocess_valid,i_admission_valid,
    output wire o_local_rst_n,output wire o_drain_pending,
    output reg o_failed_status_valid,input wire i_failed_status_ready,
    output reg o_protocol_fault,output reg [31:0] o_stale_source_count,
    output reg o_cleanup_pulse,
    // Optional same-value pre-distribution reset, used only for data masks.
    input wire i_data_reset_n,output wire o_local_data_rst_n
);
    localparam [2:0] IDLE=0,DRAIN=1,ARM=2,CLEAR=3,STATUS=4,FAULT=5,RELEASE=6;
    reg [2:0] state;
    reg [1:0] clear_cycles;
    reg [63:0] tag;
    reg previous_presented;
    reg clear_active;
    wire applied_clear;
    reg native_started;
    wire presented=i_native_valid || i_isp_valid || i_preprocess_valid || i_admission_valid;
    wire exact_source=i_source_tag==tag && tag!=0;
    // The opt-in profile commits the complete functional clear at a rising
    // edge. Its contract preserves sampled held transfers, not delta ordering.
    assign o_local_rst_n=rst_n && !applied_clear;
    wire data_reset_n=SEPARATE_DATA_RESET!=0 ? i_data_reset_n : rst_n;
    assign o_local_data_rst_n=data_reset_n && !applied_clear;
    assign o_drain_pending=state!=IDLE;
    generate if (SYNC_CLEAR_ENABLE != 0) begin : g_sync_clear
        reg committed_clear;
        // Only the coordinated reset is asynchronous. The falling-edge request
        // drives a data input and never drives this register's async reset pin.
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) committed_clear <= 1'b0;
            else committed_clear <= clear_active;
        end
        assign applied_clear = committed_clear;
    end else begin : g_legacy_clear
        assign applied_clear = clear_active;
    end endgenerate
    wire clear_reset_n;
    generate if(FALLING_INPUT_RESET!=0)begin:g_clear_reset_release
        // The caller releases rst_n at a falling edge. The local rising
        // release protects the negative-edge clear state while leaving the
        // positive-edge ownership FSM on the caller's original reset.
        (* preserve="true" *) reg release_n;
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)release_n<=1'b0;
            else release_n<=1'b1;
        end
        assign clear_reset_n=release_n;
    end else begin:g_original_clear_reset
        assign clear_reset_n=rst_n;
    end endgenerate
    always @(negedge clk or negedge clear_reset_n)begin
        if(!clear_reset_n)clear_active<=0;
        else if(state==ARM && !presented && !previous_presented)clear_active<=1;
        else if(state==STATUS || state==IDLE ||
                (SYNC_CLEAR_ENABLE != 0 && state==RELEASE))clear_active<=0;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;clear_cycles<=0;tag<=0;previous_presented<=0;native_started<=0;
            o_failed_status_valid<=0;o_protocol_fault<=0;o_stale_source_count<=0;o_cleanup_pulse<=0;
        end else begin
            previous_presented<=presented;o_cleanup_pulse<=0;
            if(i_context_fire)begin
                if(state!=IDLE || i_context_tag==0)o_protocol_fault<=1;
                else begin tag<=i_context_tag;native_started<=0;end
            end
            if(i_native_job_start)native_started<=1;
            if(i_source_fire)begin
                if(!exact_source)begin if(!(&o_stale_source_count))o_stale_source_count<=o_stale_source_count+1'b1;end
                else if(!i_source_read_quiescent)o_protocol_fault<=1;
                else if(!i_source_ok && state==IDLE && (native_started || i_native_job_start))state<=DRAIN;
            end
            case(state)
                DRAIN:if(!presented && !previous_presented)state<=ARM;
                ARM:if(applied_clear)begin state<=CLEAR;clear_cycles<=2;o_cleanup_pulse<=1;end
                    else if(presented || previous_presented)state<=DRAIN;
                CLEAR:if(clear_cycles!=0)clear_cycles<=clear_cycles-1'b1;
                    else if(SYNC_CLEAR_ENABLE != 0)state<=RELEASE;
                    else begin state<=STATUS;o_failed_status_valid<=1;end
                RELEASE:if(SYNC_CLEAR_ENABLE==0)begin state<=FAULT;o_protocol_fault<=1;end
                    else if(!applied_clear && !clear_active)begin
                    state<=STATUS;o_failed_status_valid<=1;
                end
                STATUS:if(o_failed_status_valid && i_failed_status_ready)begin
                    o_failed_status_valid<=0;state<=IDLE;
                end
                IDLE:begin end
                FAULT:begin end
                default:begin state<=FAULT;o_protocol_fault<=1;end
            endcase
        end
    end
endmodule
`default_nettype wire
