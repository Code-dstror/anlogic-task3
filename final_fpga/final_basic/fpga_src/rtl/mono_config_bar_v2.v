`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
// Retained USER BAR owner. Arbitrary request/shadow bytes live in official RAM;
// exact PREPARE qualification and transport use one bounded word sequencer.
module mono_config_bar_v2 #(
    parameter integer PROFILE=1,WIDTH=1920,HEIGHT=1080,LANE_GAUSSIAN_ONLY=1,CFG_DIAG_ENABLE=0,STEREO_CAPABLE=0,
    parameter [7:0] LEGACY_SUPPORTED=0,
    parameter [2:0] V2_SUPPORTED_MODES=0,
    parameter [5:0] V2_SUPPORTED_ENABLES=0
) (
    input wire clk,rst_n,stream_ready,
    input wire i_stereo_mode,output wire o_transaction_idle,output wire o_stereo_compatible,
    input wire write_valid,input wire [11:0] write_offset,input wire [31:0] write_data,input wire [3:0] write_strobes,
    output wire [1:0] write_response,
    input wire read_valid,input wire [11:0] read_offset,
    output reg read_response_valid,output reg [31:0] read_data,output wire [1:0] read_response,
    output wire [39:0] command_data,output wire command_valid,input wire command_ready,
    input wire [39:0] response_data,input wire response_valid,output wire response_ready,
    output wire initialized,output wire [31:0] session_id,
    input wire diag_observer_rst_n,
    output wire [223:0] diag_data
);
    localparam [2:0] IDLE=0,BOOT=1,PREPARING=2,READY=3,COMMITTING=4,CANCELLING=5;
    localparam [3:0] J_IDLE=0,J_LOCK=1,J_HEADER_REQ=2,J_HEADER_WORD=3,J_EXT_START=4,J_EXT_REQ=5,J_EXT_WORD=6,J_EXT_RESULT=7,
        J_TX_HEADER=8,J_TX_REQ=9,J_TX_WORD=10,J_ERROR_UNLOCK=11,J_PUBLISH=12,J_COPY_WAIT=13;
    reg [2:0] state;
    reg [3:0] job;
    reg previous_ready,session_initialized,boot_pending;
    reg [31:0] session,response_sequence,last_sequence,raw_sequence,epoch,first_sequence;
    reg [2:0] error_code;
    reg failed,applied;
    reg extended;
    reg [1:0] operation;
    reg [5:0] cursor;
    reg session_bad,sequence_bad,tuple_bad;
    reg [6:0] check_quality;
    reg check_adaptive;
    reg [1:0] check_mode;
    // These USER-only summary bits follow the same prepared/active ownership
    // as the RAM tuple. Shadow edits and failed/cancelled PREPARE never change
    // the published cold-mode qualification.
    reg prepared_basic_sdr,active_basic_sdr;
    // The existing schema2 settings describe the shared per-frame filter.
    // A dual session accepts color/gray/Gaussian/HE/internal dehaze and two-exposure HDR.
    localparam [5:0] STEREO_ENABLES = V2_SUPPORTED_ENABLES &
        (`PCIE_CFG_V2_ENABLES_GRAY | `PCIE_CFG_V2_ENABLES_DEHAZE | `PCIE_CFG_V2_ENABLES_GAUSSIAN_IMAGE | `PCIE_CFG_V2_ENABLES_HISTOGRAM);
    localparam [2:0] STEREO_MODES = V2_SUPPORTED_MODES &
        (`PCIE_CFG_V2_MODE_CAPABILITIES_MONO_SDR | `PCIE_CFG_V2_MODE_CAPABILITIES_MONO_HDR);
    reg stereo_unsupported;
    wire memory_done,memory_locked,lock_ready,unlock_ready;
    wire memory_write_ready,memory_read_ready,memory_read_valid;
    wire [31:0] memory_read_data,scan_data;
    wire scan_ready,scan_valid;
    wire publish_ready,publish_complete,publish_done,copy_busy;
    reg memory_read_pending,memory_read_active;
    reg [5:0] memory_read_word;
    wire effective_ready=stream_ready&&memory_done;
    wire stereo_active=STEREO_CAPABLE!=0&&i_stereo_mode;
    // Cold selection requires completed BOOT and no in-flight CFG owner.
    assign o_transaction_idle=effective_ready&&session_initialized&&!boot_pending&&state==IDLE&&job==J_IDLE;
    assign o_stereo_compatible=STEREO_CAPABLE!=0&&effective_ready&&session_initialized&&active_basic_sdr;
    wire owned=state!=IDLE;
    wire command_busy=job!=J_IDLE&&job!=J_PUBLISH&&job!=J_COPY_WAIT;
    wire request_field=write_offset>=`PCIE_REG_CFG_REQUEST_SEQUENCE&&write_offset<=`PCIE_REG_CFG_REQUEST_RESTART_MCUS;
    wire extension_write=write_offset>=`PCIE_REG_CFG_EXT_SHADOW_BASE&&write_offset<`PCIE_REG_CFG_EXT_SHADOW_BASE+128&&write_offset[1:0]==0;
    wire field_write=request_field||write_offset==`PCIE_REG_CFG_HOST_CAPABILITIES||extension_write;
    wire known_command=write_data==`PCIE_CFG_COMMAND_PREPARE||write_data==`PCIE_CFG_COMMAND_PREPARE_EXT||
        write_data==`PCIE_CFG_COMMAND_COMMIT||write_data==`PCIE_CFG_COMMAND_CANCEL;
    wire write_allowed=field_write ? !owned&&!command_busy :
        write_offset==`PCIE_REG_CFG_COMMAND&&write_strobes==15&&known_command;
    assign write_response=write_allowed?2'd0:2'd2;
    assign read_response=0;
    assign initialized=session_initialized&&effective_ready;assign session_id=session;
    reg [5:0] write_address;
    reg write_address_known;
    always @*begin
        write_address=0;write_address_known=1;
        case(write_offset)
            `PCIE_REG_CFG_REQUEST_SEQUENCE:write_address=0;
            `PCIE_REG_CFG_REQUEST_SESSION:write_address=1;
            `PCIE_REG_CFG_REQUEST_MODE:write_address=2;
            `PCIE_REG_CFG_REQUEST_QUALITY:write_address=3;
            `PCIE_REG_CFG_REQUEST_FLAGS:write_address=4;
            `PCIE_REG_CFG_REQUEST_MIN_QUALITY:write_address=5;
            `PCIE_REG_CFG_REQUEST_FRAME_BUDGET:write_address=6;
            `PCIE_REG_CFG_REQUEST_RESTART_MCUS:write_address=7;
            `PCIE_REG_CFG_HOST_CAPABILITIES:write_address=8;
            default:begin write_address_known=extension_write;write_address=6'd9+((write_offset-`PCIE_REG_CFG_EXT_SHADOW_BASE)>>2);end
        endcase
    end
    wire memory_write=effective_ready&&write_valid&&write_allowed&&field_write&&write_address_known;
    reg read_is_memory,read_bank;
    reg [5:0] read_address;
    reg [31:0] scalar;
    always @*begin
        scalar=0;read_is_memory=0;read_bank=0;read_address=0;
        case(read_offset)
            `PCIE_REG_CFG_MAGIC:scalar=`PCIE_CFG_MAGIC;
            `PCIE_REG_CFG_ABI_VERSION:scalar=`PCIE_CFG_ABI_VERSION;
            `PCIE_REG_CFG_FEATURES:scalar=63;
            `PCIE_REG_CFG_COMPILED_PROFILE:scalar=stereo_active?2:PROFILE;
            `PCIE_REG_CFG_CAMERA_PRESENT:scalar=stereo_active?3:1;
            `PCIE_REG_CFG_MAX_WIDTH:scalar=WIDTH;
            `PCIE_REG_CFG_MAX_HEIGHT:scalar=HEIGHT;
            `PCIE_REG_CFG_SESSION:scalar=session;
            `PCIE_REG_CFG_STATUS:scalar={27'd0,initialized,failed,applied,state==READY,owned};
            `PCIE_REG_CFG_RESPONSE_SEQUENCE:scalar=response_sequence;
            `PCIE_REG_CFG_ERROR:scalar={29'd0,error_code};
            `PCIE_REG_CFG_MODE_EPOCH:scalar=epoch;
            `PCIE_REG_CFG_APPLIED_FIRST_SEQUENCE:scalar=first_sequence;
            `PCIE_REG_CFG_APPLIED_CAMERA:scalar=0;
            `PCIE_REG_CFG_ACTIVE_SESSION:scalar=session_initialized?session:0;
            `PCIE_REG_CFG_REQUEST_SEQUENCE:begin read_is_memory=1;read_address=0;end
            `PCIE_REG_CFG_REQUEST_SESSION:begin read_is_memory=1;read_address=1;end
            `PCIE_REG_CFG_REQUEST_MODE:begin read_is_memory=1;read_address=2;end
            `PCIE_REG_CFG_REQUEST_QUALITY:begin read_is_memory=1;read_address=3;end
            `PCIE_REG_CFG_REQUEST_FLAGS:begin read_is_memory=1;read_address=4;end
            `PCIE_REG_CFG_REQUEST_MIN_QUALITY:begin read_is_memory=1;read_address=5;end
            `PCIE_REG_CFG_REQUEST_FRAME_BUDGET:begin read_is_memory=1;read_address=6;end
            `PCIE_REG_CFG_REQUEST_RESTART_MCUS:begin read_is_memory=1;read_address=7;end
            `PCIE_REG_CFG_HOST_CAPABILITIES:begin read_is_memory=1;read_address=8;end
            `PCIE_REG_CFG_ACTIVE_MODE:begin read_is_memory=1;read_bank=1;read_address=2;end
            `PCIE_REG_CFG_ACTIVE_QUALITY:begin read_is_memory=1;read_bank=1;read_address=3;end
            `PCIE_REG_CFG_ACTIVE_FLAGS:begin read_is_memory=1;read_bank=1;read_address=4;end
            `PCIE_REG_CFG_ACTIVE_MIN_QUALITY:begin read_is_memory=1;read_bank=1;read_address=5;end
            `PCIE_REG_CFG_ACTIVE_FRAME_BUDGET:begin read_is_memory=1;read_bank=1;read_address=6;end
            `PCIE_REG_CFG_ACTIVE_RESTART_MCUS:begin read_is_memory=1;read_bank=1;read_address=7;end
            `PCIE_REG_CFG_EXT_MAGIC:scalar=`PCIE_CFG_EXT_MAGIC;
            `PCIE_REG_CFG_EXT_ABI_VERSION:scalar=`PCIE_CFG_EXT_ABI_VERSION;
            `PCIE_REG_CFG_EXT_WIDTH:scalar=1024;
            `PCIE_REG_CFG_EXT_SUPPORTED:scalar={24'd0,stereo_active ? 8'd0 : LEGACY_SUPPORTED};
            `PCIE_REG_CFG_EXT_SCHEMAS:scalar=`PCIE_CFG_V2_SUPPORTED_SCHEMAS;
            `PCIE_REG_CFG_EXT_V2_MODES:scalar={29'd0,stereo_active ? STEREO_MODES : V2_SUPPORTED_MODES};
            `PCIE_REG_CFG_EXT_V2_ENABLES:scalar={26'd0,stereo_active ? STEREO_ENABLES : V2_SUPPORTED_ENABLES};
            `PCIE_REG_CFG_EXT_STRIPS:scalar=0;
            `PCIE_REG_CFG_EXT_COMBINATIONS:scalar=0;
            `PCIE_REG_CFG_EXT_APPLIED_LUT_GENERATION:begin read_is_memory=1;read_bank=1;read_address=20;end
            default:begin end
        endcase
        if(read_offset>=`PCIE_REG_CFG_EXT_SHADOW_BASE&&read_offset<`PCIE_REG_CFG_EXT_SHADOW_BASE+128)begin
            read_is_memory=1;read_bank=0;read_address=6'd9+((read_offset-`PCIE_REG_CFG_EXT_SHADOW_BASE)>>2);
        end
        if(read_offset>=`PCIE_REG_CFG_EXT_ACTIVE_BASE&&read_offset<`PCIE_REG_CFG_EXT_ACTIVE_BASE+128)begin
            read_is_memory=1;read_bank=1;read_address=6'd9+((read_offset-`PCIE_REG_CFG_EXT_ACTIVE_BASE)>>2);
        end
    end
    wire scanner_start_ready,scanner_word_ready,scanner_result_valid;
    wire [2:0] scanner_error;
    mono_config_scan_v2 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.LANE_GAUSSIAN_ONLY(LANE_GAUSSIAN_ONLY),
        .LEGACY_SUPPORTED(LEGACY_SUPPORTED),.V2_SUPPORTED_MODES(V2_SUPPORTED_MODES),.V2_SUPPORTED_ENABLES(V2_SUPPORTED_ENABLES)) u_validator(
        .clk(clk),.rst_n(rst_n),.cancel(!effective_ready),.start_valid(job==J_EXT_START),.start_ready(scanner_start_ready),
        .start_mode({30'd0,check_mode}),.word_valid(job==J_EXT_WORD&&scan_valid),.word_ready(scanner_word_ready),.word_data(scan_data),
        .result_valid(scanner_result_valid),.result_ready(job==J_EXT_RESULT),.result_error(scanner_error));
    wire scan_request=job==J_HEADER_REQ||job==J_EXT_REQ||job==J_TX_REQ;
    wire scan_response_ready=job==J_HEADER_WORD||(job==J_EXT_WORD&&scanner_word_ready)||(job==J_TX_WORD&&command_ready);
    reg [1:0] reply_index,reply_kind;
    reg reply_header_bad,reply_session_bad,reply_sequence_bad;
    reg [31:0] pending_epoch;
    wire reply_final=reply_index==3;
    wire reply_shape_ok=!response_data[39]&&response_data[38]&&response_data[37:32]==2;
    wire reply_match=!reply_header_bad&&!reply_session_bad&&!reply_sequence_bad&&reply_shape_ok&&!command_busy;
    wire applied_reply=reply_final&&reply_kind==2&&state==COMMITTING&&reply_match;
    assign response_ready=effective_ready&&(!applied_reply||job==J_COPY_WAIT&&publish_complete);
    wire reply_fire=response_valid&&response_ready;
    wire reply_terminal=reply_fire&&reply_final&&reply_match&&
        ((reply_kind==2&&state==COMMITTING)||(reply_kind==0&&state==CANCELLING)||reply_kind==3);
    wire boot_ack=reply_fire&&reply_final&&reply_match&&reply_kind==0&&state==BOOT;
    wire memory_unlock=job==J_ERROR_UNLOCK||reply_terminal;
    wire memory_commit=effective_ready&&response_valid&&applied_reply&&job==J_COPY_WAIT;
    // One extra sink per observed fact; diagnostic outputs never drive the BAR,
    // storage, FIFO, READY, response or publish equations above/below.
    generate if(CFG_DIAG_ENABLE!=0)begin:g_cfg_diag
        wire prepare_start=effective_ready&&write_valid&&write_allowed&&!field_write&&
            (write_data==`PCIE_CFG_COMMAND_PREPARE||write_data==`PCIE_CFG_COMMAND_PREPARE_EXT)&&
            !owned&&session_initialized;
        wire commit_accepted=effective_ready&&write_valid&&write_allowed&&!field_write&&
            write_data==`PCIE_CFG_COMMAND_COMMIT&&state==READY&&raw_sequence==last_sequence;
        wire publish_atomic=reply_fire&&reply_final&&reply_match&&reply_kind==2&&state==COMMITTING;
        wire [31:0] live_flags={1'b0,rst_n,copy_busy,publish_complete,
            command_ready,command_valid,response_ready,response_valid,error_code,job,state,
            1'b0,failed,stream_ready,owned,session_initialized,effective_ready,8'd0};
        cfg_diag_user u_capture(
            .i_clk(clk),.i_observer_rst_n(diag_observer_rst_n),.i_app_rst_n(rst_n),
            .i_prepare_start(prepare_start),.i_commit_accepted(commit_accepted),
            .i_commit_last_sent(job==J_TX_WORD&&scan_valid&&command_ready&&operation==1&&cursor==(extended?40:8)),
            .i_applied_present(effective_ready&&response_valid&&applied_reply),
            .i_copy_started(job==J_PUBLISH&&publish_ready),
            .i_copy_complete(job==J_COPY_WAIT&&publish_complete),
            .i_applied_taken(reply_fire&&applied_reply),.i_published(publish_atomic),
            .i_reply_mismatch(reply_fire&&reply_final&&!reply_match&&state==COMMITTING),
            .i_session(session),.i_request_sequence(raw_sequence),.i_target_epoch(epoch+32'd1),
            .i_published_epoch(epoch),.i_published_first_sequence(first_sequence),.i_live_flags(live_flags),.o_data(diag_data));
    end else begin:g_no_cfg_diag
        assign diag_data=224'd0;
    end endgenerate
    mono_config_byte_store_v2 u_store(
        .clk(clk),.rst_n(rst_n),.init_done(memory_done),
        .write_valid(memory_write),.write_ready(memory_write_ready),.write_word(write_address),.write_data(write_data),.write_strobes(write_strobes),
        .lock_valid(job==J_LOCK),.lock_ready(lock_ready),.locked(memory_locked),.unlock_valid(memory_unlock),.unlock_ready(unlock_ready),
        .cancel(previous_ready&&!effective_ready),.clear_active(boot_ack),
        .publish_valid(job==J_PUBLISH),.publish_extension(extended),.publish_ready(publish_ready),.publish_done(publish_done),
        .publish_complete(publish_complete),.publish_commit_ready(memory_commit),.copy_busy(copy_busy),
        .read_valid(memory_read_pending),.read_ready(memory_read_ready),.read_active(memory_read_active),.read_word(memory_read_word),
        .read_response_valid(memory_read_valid),.read_response_ready(1'b1),.read_response_data(memory_read_data),
        .scan_valid(scan_request),.scan_ready(scan_ready),.scan_word(cursor),
        .scan_response_valid(scan_valid),.scan_response_ready(scan_response_ready),.scan_response_data(scan_data));
    assign command_valid=effective_ready&&(job==J_TX_HEADER||(job==J_TX_WORD&&scan_valid));
    assign command_data=job==J_TX_HEADER ? {1'b1,operation==3,operation,extended,3'd0,session} :
        {1'b0,cursor==(extended?40:8),cursor,scan_data};
    function [31:0] merged;
        input [31:0] old_value,value;input [3:0] enables;integer b;
        begin merged=old_value;for(b=0;b<4;b=b+1)if(enables[b])merged[b*8+:8]=value[b*8+:8];end
    endfunction
    task reject_prepare;
        input [2:0] reason;
        begin failed<=1;error_code<=reason;applied<=0;job<=J_ERROR_UNLOCK;end
    endtask
    // The parent releases rst_n on USER's rising edge. Shift only this
    // register owner's ASR to the falling edge: 2 ns into this stage and
    // 6 ns to the next USER rising edge at the production 25% duty cycle.
    // Child RAM/scanner/diagnostic resets and all data qualification stay
    // on rst_n, so this local phase never shortens their data-path budget.
    (* preserve="true" *) reg state_reset_n=1'b0;
    always @(negedge clk or negedge rst_n) begin
        if(!rst_n) state_reset_n<=1'b0;
        else state_reset_n<=1'b1;
    end
    always @(posedge clk or negedge state_reset_n)begin
        if(!state_reset_n)begin
            state<=IDLE;job<=J_IDLE;previous_ready<=0;session_initialized<=0;boot_pending<=0;
            session<=0;response_sequence<=0;last_sequence<=0;raw_sequence<=0;epoch<=0;first_sequence<=0;
            error_code<=0;failed<=0;applied<=0;extended<=0;operation<=0;cursor<=0;
            session_bad<=0;sequence_bad<=0;tuple_bad<=0;check_quality<=0;check_adaptive<=0;check_mode<=0;
            prepared_basic_sdr<=0;active_basic_sdr<=0;stereo_unsupported<=0;
            memory_read_pending<=0;memory_read_active<=0;memory_read_word<=0;read_response_valid<=0;read_data<=0;
            reply_index<=0;reply_kind<=0;reply_header_bad<=0;reply_session_bad<=0;reply_sequence_bad<=0;pending_epoch<=0;
        end else begin
            previous_ready<=effective_ready;
            read_response_valid<=0;
            if(memory_read_pending&&memory_read_ready)memory_read_pending<=0;
            if(memory_read_valid)begin read_response_valid<=1;read_data<=memory_read_data;end
            // Actual BAR owner permits only one outstanding read; its request
            // is retained across local arbitration and application cancel.
            if(read_valid)begin
                if(read_is_memory&&memory_done)begin memory_read_pending<=1;memory_read_active<=read_bank;memory_read_word<=read_address;end
                else begin read_response_valid<=1;read_data<=read_is_memory?(read_address==3?32'd75:read_address==5?32'd1:32'd0):scalar;end
            end
            if(!effective_ready)begin
                active_basic_sdr<=0;
                if(owned)begin failed<=1;applied<=0;error_code<=`PCIE_CFG_ERROR_RESET;end
                state<=IDLE;job<=J_IDLE;session_initialized<=0;boot_pending<=0;reply_index<=0;
            end else begin
                if(!previous_ready)begin
                    session<=session==32'hffffffff ? 32'd1 : session+1'b1;boot_pending<=1;session_initialized<=0;state<=BOOT;
                end
                if(boot_pending&&job==J_IDLE)begin operation<=3;extended<=0;job<=J_TX_HEADER;boot_pending<=0;end
                case(job)
                    J_LOCK:if(lock_ready)begin cursor<=0;session_bad<=0;sequence_bad<=0;tuple_bad<=0;prepared_basic_sdr<=1;stereo_unsupported<=0;job<=J_HEADER_REQ;end
                    J_HEADER_REQ:if(scan_ready)job<=J_HEADER_WORD;
                    J_HEADER_WORD:if(scan_valid)begin
                        case(cursor)
                            0:if(scan_data==0||scan_data==last_sequence)sequence_bad<=1;
                            1:if(scan_data!=session)session_bad<=1;
                            2:begin check_mode<=scan_data[1:0];prepared_basic_sdr<=scan_data==`PCIE_CFG_MODE_COLOR;if(scan_data>3)tuple_bad<=1;end
                            3:begin check_quality<=scan_data[6:0];if(scan_data<1||scan_data>100)tuple_bad<=1;end
                            4:begin check_adaptive<=scan_data[0];if(scan_data>1)tuple_bad<=1;end
                            5:if(scan_data<1||scan_data>check_quality)tuple_bad<=1;
                            6:if(scan_data>16777216||(check_adaptive&&scan_data==0))tuple_bad<=1;
                            7:if(scan_data>65535)tuple_bad<=1;
                            default:begin end
                        endcase
                        if(cursor==8)begin
                            if(session_bad)reject_prepare(`PCIE_CFG_ERROR_SESSION);
                            else if(sequence_bad)reject_prepare(`PCIE_CFG_ERROR_STALE);
                            else if(tuple_bad||!scan_data[0])reject_prepare(`PCIE_CFG_ERROR_INVALID);
                            else if(extended)job<=J_EXT_START;
                            else begin last_sequence<=raw_sequence;job<=J_TX_HEADER;end
                        end else begin cursor<=cursor+1'b1;job<=J_HEADER_REQ;end
                    end
                    J_EXT_START:if(scanner_start_ready)begin cursor<=9;job<=J_EXT_REQ;end
                    J_EXT_REQ:if(scan_ready)job<=J_EXT_WORD;
                    J_EXT_WORD:if(scan_valid&&scanner_word_ready)begin
                        // Schema1: all feature bits clear. Schema2: MONO_SDR
                        // and all six processing enables clear. Other fields
                        // remain governed by the unchanged full validator.
                        if(cursor==9)begin
                            if(scan_data[15:8]!=0)prepared_basic_sdr<=0;
                            if(stereo_active)begin
                                if(scan_data[7:0]==`PCIE_CFG_V2_SCHEMA)
                                    stereo_unsupported<=|(scan_data[15:10]&~STEREO_ENABLES) || !STEREO_MODES[scan_data[9:8]];
                                else stereo_unsupported<=scan_data[15:8]!=0;
                            end
                        end
                        if(cursor==40)job<=J_EXT_RESULT;else begin cursor<=cursor+1'b1;job<=J_EXT_REQ;end
                    end
                    J_EXT_RESULT:if(scanner_result_valid)begin
                        if(scanner_error!=0)reject_prepare(scanner_error);
                        else if(stereo_unsupported)reject_prepare(`PCIE_CFG_ERROR_UNSUPPORTED);
                        else begin last_sequence<=raw_sequence;job<=J_TX_HEADER;end
                    end
                    J_TX_HEADER:if(command_ready)begin
                        if(operation==3)job<=J_IDLE;else begin cursor<=0;job<=J_TX_REQ;end
                    end
                    J_TX_REQ:if(scan_ready)job<=J_TX_WORD;
                    J_TX_WORD:if(scan_valid&&command_ready)begin
                        if(cursor==(extended?40:8))job<=J_IDLE;else begin cursor<=cursor+1'b1;job<=J_TX_REQ;end
                    end
                    J_ERROR_UNLOCK:if(unlock_ready)begin job<=J_IDLE;state<=IDLE;end
                    J_PUBLISH:if(publish_ready)job<=J_COPY_WAIT;
                    default:begin end
                endcase
                if(response_valid&&applied_reply&&job==J_IDLE)job<=J_PUBLISH;
                if(reply_fire)begin
                    if(reply_index==0)begin
                        reply_kind<=response_data[37:36];reply_session_bad<=response_data[31:0]!=session;
                        reply_header_bad<=response_data[39:38]!=2'b10||response_data[35:32]!=0;reply_sequence_bad<=0;reply_index<=1;
                    end else begin
                        if(response_data[39]||response_data[37:32]!=(reply_index-1'b1)||response_data[38]!=(reply_index==3))reply_header_bad<=1;
                        if(reply_index==1)reply_sequence_bad<=response_data[31:0]!=(state==BOOT?32'd0:last_sequence);
                        if(reply_index==2)pending_epoch<=response_data[31:0];
                        if(reply_final)begin
                            reply_index<=0;
                            if(reply_session_bad)begin failed<=1;error_code<=`PCIE_CFG_ERROR_SESSION;end
                            else if(!reply_match)begin failed<=1;error_code<=`PCIE_CFG_ERROR_STALE;end
                            else if(reply_kind==0&&state==BOOT)begin
                                active_basic_sdr<=1;
                                session_initialized<=1;state<=IDLE;epoch<=0;first_sequence<=0;
                            end else begin
                                response_sequence<=last_sequence;
                                if(reply_kind==1&&state==PREPARING)begin state<=READY;failed<=0;error_code<=0;end
                                else if(reply_kind==2&&state==COMMITTING)begin
                                    active_basic_sdr<=prepared_basic_sdr;
                                    state<=IDLE;job<=J_IDLE;applied<=1;failed<=0;error_code<=0;epoch<=pending_epoch;first_sequence<=response_data[31:0];
                                end else if(reply_kind==0&&state==CANCELLING)begin state<=IDLE;applied<=0;failed<=0;error_code<=0;end
                                else if(reply_kind==3)begin state<=IDLE;job<=J_IDLE;applied<=0;failed<=1;error_code<=pending_epoch[2:0];end
                                else begin failed<=1;error_code<=`PCIE_CFG_ERROR_STALE;end
                            end
                        end else reply_index<=reply_index+1'b1;
                    end
                end
                if(write_valid&&write_allowed)begin
                    if(memory_write&&write_address==0)raw_sequence<=merged(raw_sequence,write_data,write_strobes);
                    if(!field_write)begin
                        if(write_data==`PCIE_CFG_COMMAND_PREPARE||write_data==`PCIE_CFG_COMMAND_PREPARE_EXT)begin
                            response_sequence<=raw_sequence;applied<=0;
                            if(owned||!session_initialized)begin failed<=1;error_code<=`PCIE_CFG_ERROR_BUSY;end
                            else begin
                                state<=PREPARING;job<=J_LOCK;operation<=0;extended<=write_data==`PCIE_CFG_COMMAND_PREPARE_EXT;
                                failed<=0;error_code<=0;
                            end
                        end else if(state!=READY||raw_sequence!=last_sequence)begin failed<=1;error_code<=`PCIE_CFG_ERROR_STALE;end
                        else begin
                            operation<=write_data==`PCIE_CFG_COMMAND_COMMIT?2'd1:2'd2;
                            state<=write_data==`PCIE_CFG_COMMAND_COMMIT?COMMITTING:CANCELLING;
                            job<=J_TX_HEADER;failed<=0;error_code<=0;
                        end
                    end
                end
            end
        end
    end
endmodule
