// One frozen metadata job; payload storage/CDC and processing live elsewhere.
module raw_pair_replay_scheduler #(
    // The caller must retain every descriptor/lease/ID through the successful
    // OWNER_RESPONSE edge. Default capture preserves the standalone contract.
    parameter integer BORROW_CONTEXT=0
) (
    input wire clk, input wire rst_n,
    input wire i_job_valid, output wire o_job_ready,
    input wire [1:0] i_job_kind,
    input wire [63:0] i_job_id,i_pair_id,i_job_lease0,i_job_lease1,
    input wire [383:0] i_job_frame0,i_job_frame1,
    output wire m_member_valid, input wire m_member_ready,
    output wire [383:0] m_member_frame,
    output wire [63:0] m_member_lease,m_member_job_id,m_member_pair_id,
    output wire m_member_index,
    output wire o_req_valid, input wire i_req_ready,
    output wire o_req_private, output wire [2:0] o_req_op,
    output wire o_req_camera, output wire [1:0] o_req_slot,
    output wire [31:0] o_req_generation,o_req_session,o_req_offset,o_req_length,
    output wire [63:0] o_req_lease,o_req_job_id,
    input wire i_rsp_valid, output wire o_rsp_ready,
    input wire [3:0] i_rsp_code, input wire i_rsp_camera,
    input wire [1:0] i_rsp_slot,
    input wire [31:0] i_rsp_generation,i_rsp_session,i_rsp_sequence,i_rsp_epoch,
    input wire i_native_done,i_native_error,
    input wire [63:0] i_native_job_id, input wire i_native_member_index,
    input wire i_processing_done,i_processing_error,
    input wire [63:0] i_processing_job_id, input wire i_processing_member_index,
    input wire i_cancel,
    output wire o_processing_cancel_valid, input wire i_processing_cancel_ready,
    output wire [383:0] o_processing_cancel_frame,
    output wire [63:0] o_processing_cancel_lease,o_processing_cancel_job_id,o_processing_cancel_pair_id,
    output wire o_processing_cancel_member_index,
    output wire o_retire_valid, input wire i_retire_ready,
    output wire [31:0] o_retire_session, output wire [63:0] o_retire_job_id,
    output reg o_retire_cancelled, output wire o_retire_read_quiescent,
    input wire i_retire_done,i_retire_error,
    output wire o_busy, output reg o_fault, output reg [3:0] o_error_code,
    output reg o_stale_completion,
    output wire [3:0] o_diag_state
);
    localparam [3:0] IDLE=0,MEMBER=1,REPLAY_REQUEST=2,REPLAY_RESPONSE=3,
        ACTIVE=4,RETIRE_REQUEST=5,RETIRE_RESPONSE=6,WAIT_PROCESS=7,
        CANCEL_CONTEXT=8,WAIT_CANCEL=9,OWNER_REQUEST=10,OWNER_RESPONSE=11,FAULT=12;
    reg [3:0] state;
    // Read-only local-domain state for the first-job flight recorder.
    assign o_diag_state=state;
    wire [1:0] kind;
    wire [63:0] job_id,pair_id,lease0,lease1;
    wire [383:0] frame0,frame1;
    generate if(BORROW_CONTEXT!=0)begin:g_borrow_context
        assign kind=i_job_kind;
        assign job_id=i_job_id;assign pair_id=i_pair_id;
        assign lease0=i_job_lease0;assign lease1=i_job_lease1;
        assign frame0=i_job_frame0;assign frame1=i_job_frame1;
    end else begin:g_capture_context
        reg [1:0] held_kind;
        reg [63:0] held_job,held_pair,held_lease0,held_lease1;
        reg [383:0] held_frame0,held_frame1;
        assign kind=held_kind;
        assign job_id=held_job;assign pair_id=held_pair;
        assign lease0=held_lease0;assign lease1=held_lease1;
        assign frame0=held_frame0;assign frame1=held_frame1;
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)begin
                held_kind<=0;held_job<=0;held_pair<=0;held_lease0<=0;held_lease1<=0;
                held_frame0<=0;held_frame1<=0;
            end else if(i_job_valid&&o_job_ready)begin
                held_kind<=i_job_kind;held_job<=i_job_id;held_pair<=i_pair_id;
                held_lease0<=i_job_lease0;held_lease1<=i_job_lease1;
                held_frame0<=i_job_frame0;held_frame1<=i_job_frame1;
            end
        end
    end endgenerate
    reg member_index,context_accepted,read_admitted,native_seen,processing_seen;
    reg failed,cancel_requested;
    wire [383:0] current_frame=member_index ? frame1 : frame0;
    wire [63:0] current_lease=member_index ? lease1 : lease0;
    wire native_match=i_native_job_id==job_id && i_native_member_index==member_index && context_accepted;
    wire processing_match=i_processing_job_id==job_id && i_processing_member_index==member_index && context_accepted;
    wire failure_now=(i_native_error && native_match) || (i_processing_error && processing_match);
    wire cancel_now=cancel_requested || i_cancel;
    wire sealed=state==OWNER_REQUEST || state==OWNER_RESPONSE || state==FAULT;
    wire response_matches=i_rsp_camera==current_frame[4] && i_rsp_slot==current_frame[6:5] &&
        i_rsp_generation==current_frame[44:13] && i_rsp_session==current_frame[76:45] &&
        i_rsp_sequence==current_frame[108:77] && i_rsp_epoch==current_frame[140:109];
    function descriptor_valid;
        input [383:0] frame;
        begin descriptor_valid=frame[383:367]==0 && frame[12:5]<4 && frame[44:13]!=0 &&
            frame[76:45]!=0 && frame[238:237]==1 && frame[220:205]!=0 && frame[206:205]==0 && frame[236:221]!=0; end
    endfunction
    assign o_job_ready=state==IDLE && !o_fault;
    assign o_busy=state!=IDLE;
    assign m_member_valid=state==MEMBER;
    assign m_member_frame=current_frame;
    assign m_member_lease=current_lease;
    assign m_member_job_id=job_id;assign m_member_pair_id=pair_id;assign m_member_index=member_index;
    assign o_req_valid=state==REPLAY_REQUEST || state==RETIRE_REQUEST;
    assign o_req_private=1'b1;assign o_req_op=state==RETIRE_REQUEST ? 3'd5 : 3'd4;
    assign o_req_camera=current_frame[4];assign o_req_slot=current_frame[6:5];
    assign o_req_generation=current_frame[44:13];assign o_req_session=current_frame[76:45];
    assign o_req_offset=32'd0;assign o_req_length=32'd0;
    assign o_req_lease=current_lease;assign o_req_job_id=job_id;
    assign o_rsp_ready=state==REPLAY_RESPONSE || state==RETIRE_RESPONSE;
    assign o_processing_cancel_valid=state==CANCEL_CONTEXT;
    assign o_processing_cancel_frame=current_frame;assign o_processing_cancel_lease=current_lease;
    assign o_processing_cancel_job_id=job_id;assign o_processing_cancel_pair_id=pair_id;
    assign o_processing_cancel_member_index=member_index;
    assign o_retire_valid=state==OWNER_REQUEST;
    assign o_retire_session=frame0[76:45];assign o_retire_job_id=job_id;
    assign o_retire_read_quiescent=(state==OWNER_REQUEST || state==OWNER_RESPONSE) && !read_admitted;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;
            member_index<=0;context_accepted<=0;read_admitted<=0;native_seen<=0;processing_seen<=0;
            failed<=0;cancel_requested<=0;o_retire_cancelled<=0;o_fault<=0;o_error_code<=0;o_stale_completion<=0;
        end else begin
            o_stale_completion<=0;
            if(state!=IDLE && !sealed) begin
                if(i_cancel) cancel_requested<=1;
                if(failure_now) failed<=1;
                if((i_native_done || i_native_error) && !native_match) o_stale_completion<=1;
                if((i_processing_done || i_processing_error) && !processing_match) o_stale_completion<=1;
                if(i_native_done && native_match && read_admitted) native_seen<=1;
                if(i_processing_done && processing_match) processing_seen<=1;
            end
            case(state)
                IDLE: if(i_job_valid && o_job_ready) begin
                    member_index<=0;context_accepted<=0;read_admitted<=0;native_seen<=0;processing_seen<=0;
                    failed<=0;cancel_requested<=i_cancel;o_error_code<=0;o_retire_cancelled<=i_cancel;
                    if(i_job_kind>1 || i_job_id==0 || i_job_lease0==0 || !descriptor_valid(i_job_frame0) ||
                        (i_job_kind==0 && (i_job_lease1==0 || i_job_lease0==i_job_lease1 || !descriptor_valid(i_job_frame1)))) begin
                        o_fault<=1;o_error_code<=15;state<=FAULT;
                    end else state<=i_cancel ? OWNER_REQUEST : MEMBER;
                end
                MEMBER: if(m_member_ready) begin
                    context_accepted<=1;
                    state<=cancel_now ? CANCEL_CONTEXT : REPLAY_REQUEST;
                end
                REPLAY_REQUEST: if(i_req_ready) state<=REPLAY_RESPONSE;
                REPLAY_RESPONSE: if(i_rsp_valid) begin
                    if(i_rsp_code!=0) begin
                        failed<=1;cancel_requested<=1;o_error_code<=i_rsp_code;state<=CANCEL_CONTEXT;
                    end else if(!response_matches) begin o_fault<=1;o_error_code<=15;state<=FAULT;end
                    else begin
                        read_admitted<=1;state<=ACTIVE;
                        if(i_native_done && native_match) native_seen<=1;
                    end
                end
                ACTIVE: if(native_seen || (i_native_done && native_match)) state<=RETIRE_REQUEST;
                RETIRE_REQUEST: if(i_req_ready) state<=RETIRE_RESPONSE;
                RETIRE_RESPONSE: if(i_rsp_valid) begin
                    if(i_rsp_code!=0 || !response_matches) begin
                        o_fault<=1;o_error_code<=i_rsp_code!=0 ? i_rsp_code : 4'd15;state<=FAULT;
                    end else begin read_admitted<=0;state<=WAIT_PROCESS;end
                end
                WAIT_PROCESS: if(processing_seen || (i_processing_done && processing_match)) begin
                    if(kind==0 && !member_index && !cancel_now) begin
                        member_index<=1;context_accepted<=0;native_seen<=0;processing_seen<=0;state<=MEMBER;
                    end else begin
                        o_retire_cancelled<=failed || failure_now || cancel_now;state<=OWNER_REQUEST;
                    end
                end
                CANCEL_CONTEXT: if(i_processing_cancel_ready) state<=WAIT_CANCEL;
                WAIT_CANCEL: if(processing_seen || (i_processing_done && processing_match)) begin
                    o_retire_cancelled<=1;state<=OWNER_REQUEST;
                end
                OWNER_REQUEST: if(i_retire_ready) state<=OWNER_RESPONSE;
                OWNER_RESPONSE: if(i_retire_done) begin
                    if(i_retire_error) begin o_fault<=1;o_error_code<=15;state<=FAULT;end
                    else begin state<=IDLE;context_accepted<=0;end
                end
                FAULT: state<=FAULT;
                default: begin o_fault<=1;o_error_code<=15;state<=FAULT;end
            endcase
        end
    end
endmodule
