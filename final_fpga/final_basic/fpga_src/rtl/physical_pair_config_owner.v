`timescale 1ns/1ps
`default_nettype none
// One immutable configuration for two same-clock members of one camera.
// Each payload FIFO keeps an independent ledger/lease; only CDC packet plumbing is shared.
module physical_pair_config_owner #(
    parameter integer TRUSTED_INPUT=0
)(
    input wire clk,owner_rst_n,cohort_rst_n,dfi_clk,
    input wire [1183:0] s_config_data,input wire s_config_valid,output wire s_config_ready,
    output wire [1183:0] m_config_ack_data,output wire m_config_ack_valid,m_config_ack_ok,
    input wire m_config_ack_ready,
    input wire source0_idle,source1_idle,enqueue0,enqueue1,consume0,consume1,write_quiet,
    output wire [1183:0] active_config,output wire initialized,busy,config_fault,
    output wire [1:0] drain_fault,dfi_fault,local_reset_done,
    output wire config_reset_done,
    output wire [63:0] enqueued0,enqueued1,consumed0,consumed1
);
    reg [1183:0] held_tuple;
    reg owned,plan_sent;
    reg [1:0] drain_sent;
    wire owner_ready,owner_busy,owner_ack_valid,owner_ack_ok;
    wire [1183:0] owner_ack_data;
    wire [1:0] drain_ready,proof_valid,proof_quiet,dfi_done;
    wire [31:0] proof_session0,proof_session1,proof_epoch0,proof_epoch1;
    wire proof0_exact=proof_valid[0]&&proof_quiet[0]&&
        proof_session0==held_tuple[63:32]&&proof_epoch0==held_tuple[159:128];
    wire proof1_exact=proof_valid[1]&&proof_quiet[1]&&
        proof_session1==held_tuple[63:32]&&proof_epoch1==held_tuple[159:128];
    // proof_quiet/source fault already contain each drain's two-flop
    // DFI-to-source fault synchronization. Raw dfi_fault is diagnostic only.
    wire joint_proof=owned&&proof0_exact&&proof1_exact&&!(|drain_fault);
    wire ack_fire=m_config_ack_valid&&m_config_ack_ready;
    wire proof_release=ack_fire&&m_config_ack_ok&&joint_proof;
    assign config_reset_done=owner_rst_n&&(&local_reset_done);
    assign s_config_ready=config_reset_done&&!owned&&!owner_busy&&!config_fault&&
        !(|drain_fault);
    // The owner registers a positive application only under joint_proof.
    // Once visible, retain its complete ACK through backpressure. A later
    // lease violation is sticky/fatal in the original drains; it must not
    // retract an already presented control beat or release a failed proof.
    assign m_config_ack_valid=owner_rst_n&&owned&&owner_ack_valid;
    assign m_config_ack_data=owner_ack_data;
    assign m_config_ack_ok=owner_ack_ok;
    assign busy=owned||owner_busy;
    always @(posedge clk or negedge owner_rst_n)begin
        if(!owner_rst_n)begin held_tuple<=0;owned<=0;plan_sent<=0;drain_sent<=0;end
        else begin
            if(s_config_valid&&s_config_ready)begin
                held_tuple<=s_config_data;owned<=1;plan_sent<=0;drain_sent<=0;
            end
            if(owned&&!plan_sent&&owner_ready)plan_sent<=1;
            if(owned&&!drain_sent[0]&&drain_ready[0])drain_sent[0]<=1;
            if(owned&&!drain_sent[1]&&drain_ready[1])drain_sent[1]<=1;
            if(ack_fire)begin owned<=0;plan_sent<=0;drain_sent<=0;end
        end
    end
    frame_config_preset_owner #(.TRUSTED_INPUT(TRUSTED_INPUT)) u_owner(
        .i_clk(clk),.i_rst_n(owner_rst_n),.s_config_data(held_tuple),
        .s_config_valid(owned&&!plan_sent),.s_config_ready(owner_ready),
        .m_applied_data(owner_ack_data),.m_applied_valid(owner_ack_valid),.m_applied_ok(owner_ack_ok),
        .m_applied_ready(m_config_ack_ready&&m_config_ack_valid),.i_config_reset_done(config_reset_done),
        .i_source_idle(source0_idle&&source1_idle),.i_apply_quiescent(joint_proof),
        .o_active_config(active_config),.o_initialized(initialized),.o_config_fault(config_fault),.o_plan_busy(owner_busy));
    wire [31:0] paired_session,paired_epoch;
    wire paired_source_done,paired_dfi_done;
    assign proof_session0=paired_session;assign proof_session1=paired_session;
    assign proof_epoch0=paired_epoch;assign proof_epoch1=paired_epoch;
    assign local_reset_done={2{paired_source_done}};
    assign dfi_done={2{paired_dfi_done}};
    paired_raw_capture_drain_cdc u_pair_drain(
        .i_source_clk(clk),.i_source_rst_n(cohort_rst_n),.i_dfi_clk(dfi_clk),.i_dfi_rst_n(cohort_rst_n),
        .i_enqueue_fire({enqueue1,enqueue0}),.i_source_idle({source1_idle,source0_idle}),
        .i_consume_fire({consume1,consume0}),.i_write_quiescent(write_quiet),
        .s_drain_valid({owned&&!drain_sent[1],owned&&!drain_sent[0]}),.s_drain_ready(drain_ready),
        .s_drain_session(held_tuple[63:32]),.s_drain_epoch(held_tuple[159:128]),
        .m_drain_valid(proof_valid),.m_drain_ready(proof_release),.m_drain_session(paired_session),.m_drain_epoch(paired_epoch),
        .m_drain_target0(),.m_drain_target1(),.m_drain_id(),.o_apply_quiescent(proof_quiet),
        .o_enqueued_count0(enqueued0),.o_enqueued_count1(enqueued1),.o_consumed_count0(consumed0),.o_consumed_count1(consumed1),
        .o_source_fault(drain_fault),.o_dfi_fault(dfi_fault),.o_stale_ack_count(),
        .o_source_reset_done(paired_source_done),.o_dfi_reset_done(paired_dfi_done));
endmodule
`default_nettype wire
