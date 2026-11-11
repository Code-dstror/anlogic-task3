// F42 metadata-only pair service. Pixel capture and pin ownership are external.
module frame_pair_manager #(
    parameter integer SLOTS_PER_CAMERA = 3,
    parameter integer ALLOW_POLICY_UPDATE = 0
) (
    input wire clk, input wire rst_n,
    input wire i_valid, output wire o_ready,
    input wire [1:0] i_command, input wire [63:0] i_now,
    input wire [383:0] i_descriptor,
    input wire [31:0] i_session, input wire [31:0] i_epoch,
    input wire [1:0] i_mode,
    input wire [63:0] i_max_delta,
    input wire [31:0] i_max_wait, input wire [31:0] i_max_age,
    output reg o_done, output reg o_error,
    output reg o_event_valid, input wire i_event_ready,
    output reg [1:0] o_event_kind, output reg [3:0] o_event_reason,
    output reg [383:0] o_frame0, output reg [383:0] o_frame1,
    output reg [63:0] o_pair_id
);
    localparam [3:0] IDLE=0, START=1, EXP_CALC=2, EXP_CHECK=3,
        EXP_NEXT=4, VALID_CALC=5, VALID_CHECK=6, ADMIT=7, INSERT=8,
        PAIR_CALC=9, PAIR_CHECK=10, CONFIG_COMMIT=11, EVENT=12, FINISH=13;
    reg [3:0] state, return_state;
    reg configured, real_command, command_failed;
    reg [1:0] command, mode, pending_mode;
    reg [31:0] session, epoch, pending_session, pending_epoch;
    reg [63:0] max_delta, pending_delta, command_now, last_now, pair_counter;
    reg [31:0] max_wait, max_age, pending_wait, pending_age;
    reg [383:0] offer, resident0, resident1;
    reg valid0, valid1, scan_lane, config_changed;
    reg [63:0] arrival0, arrival1, wait_age, frame_age, offer_age, pair_delta;
    reg [31:0] sequence_delta, generation_delta;
    reg pair_compatible, right_older;
    // These are bounded identity ledgers, not queue storage or payload RAM.
    reg [1:0] sequence_seen;
    reg [63:0] sequence_ledger;
    reg [127:0] timestamp_ledger;
    reg [2*SLOTS_PER_CAMERA-1:0] generation_seen;
    reg [64*SLOTS_PER_CAMERA-1:0] generation_ledger;
    reg [1:0] event_remove; // bit0/bit1 retire resident only at event handshake
    wire camera = offer[4];
    wire [7:0] slot = offer[12:5];
    wire offer_lane = (mode == 2) ? (offer[2:1] == 2) : camera;
    wire [383:0] scan_frame = scan_lane ? resident1 : resident0;
    wire scan_valid = scan_lane ? valid1 : valid0;
    wire [63:0] scan_arrival = scan_lane ? arrival1 : arrival0;
    wire slot_busy = (valid0 && resident0[12:4] == offer[12:4]) ||
                     (valid1 && resident1[12:4] == offer[12:4]);
    wire bad_offer = offer[383:367] != 0 || slot >= SLOTS_PER_CAMERA ||
        offer[44:13] == 0 || offer[76:45] == 0 || offer[220:205] == 0 ||
        offer[236:221] == 0 || offer[302:271] == 0 ||
        (offer[238:237] != 1 && offer[238:237] != 2) || offer[2:1] == 3;
    integer ledger_index;
    reg [3:0] rejection;
    reg rejected;
    assign o_ready = state == IDLE;

    always @* begin
        ledger_index = camera * SLOTS_PER_CAMERA + slot;
        rejected = 1'b1;
        rejection = 7;
        if (offer[76:45] != session || offer[140:109] != epoch) rejection = 7;
        else if (!offer[0]) rejection = 8;
        else if (sequence_seen[camera] &&
                 (sequence_delta == 0 || sequence_delta[31])) rejection = 9;
        else if (generation_seen[ledger_index] &&
                 (generation_delta == 0 || generation_delta[31])) rejection = 10;
        else if (sequence_seen[camera] &&
                 offer[204:141] < timestamp_ledger[camera*64 +: 64]) rejection = 11;
        else if ((mode == 2 && (camera || offer[2:1] == 0)) ||
                 (mode != 2 && offer[2:1] != 0)) rejection = 12;
        else if (mode == 0 && camera) rejection = 13;
        else if (slot_busy) rejection = 14;
        else if (offer[204:141] > command_now || offer_age >= max_age) rejection = 15;
        else begin rejected = 1'b0; rejection = 0; end
    end

    // Called only when no event is pending; all fields then hold in EVENT.
    task publish;
        input [1:0] kind;
        input [3:0] reason;
        input [383:0] frame0, frame1;
        input [63:0] id;
        input [1:0] remove_mask;
        input [3:0] next_state;
        begin
            o_event_valid <= 1'b1;
            o_event_kind <= kind;
            o_event_reason <= reason;
            o_frame0 <= frame0;
            o_frame1 <= frame1;
            o_pair_id <= id;
            event_remove <= remove_mask;
            return_state <= next_state;
            state <= EVENT;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; return_state <= IDLE;
            configured <= 0; real_command <= 0; command_failed <= 0;
            command <= 0; mode <= 0; pending_mode <= 0;
            session <= 0; epoch <= 0; pending_session <= 0; pending_epoch <= 0;
            max_delta <= 0; max_wait <= 0; max_age <= 0;
            pending_delta <= 0; pending_wait <= 0; pending_age <= 0;
            command_now <= 0; last_now <= 0; pair_counter <= 0;
            offer <= 0; resident0 <= 0; resident1 <= 0;
            valid0 <= 0; valid1 <= 0; arrival0 <= 0; arrival1 <= 0;
            scan_lane <= 0; config_changed <= 0;
            wait_age <= 0; frame_age <= 0; offer_age <= 0; pair_delta <= 0;
            sequence_delta <= 0; generation_delta <= 0;
            pair_compatible <= 0; right_older <= 0;
            sequence_seen <= 0; sequence_ledger <= 0; timestamp_ledger <= 0;
            generation_seen <= 0; generation_ledger <= 0;
            event_remove <= 0; o_done <= 0; o_error <= 0;
            o_event_valid <= 0; o_event_kind <= 0; o_event_reason <= 0;
            o_frame0 <= 0; o_frame1 <= 0; o_pair_id <= 0;
        end else begin
            o_done <= 0; o_error <= 0;
            case (state)
                IDLE: begin
                    if (i_valid || configured) begin
                        real_command <= i_valid;
                        command <= i_valid ? i_command : 2'd1;
                        command_now <= i_now;
                        offer <= i_descriptor;
                        pending_session <= i_session; pending_epoch <= i_epoch;
                        pending_mode <= i_mode; pending_delta <= i_max_delta;
                        pending_wait <= i_max_wait; pending_age <= i_max_age;
                        command_failed <= 0;
                        state <= START;
                    end
                end
                START: begin
                    if (command_now < last_now || command == 3 ||
                        (!configured && command != 2) ||
                        (command == 0 && bad_offer) ||
                        (command == 2 && (pending_session == 0 || pending_mode == 3 || pending_delta[63:32] != 0 ||
                            pending_wait == 0 || pending_age == 0 ||
                            (configured && (pending_delta != max_delta ||
                             pending_wait != max_wait || pending_age != max_age) &&
                             (ALLOW_POLICY_UPDATE==0 ||
                              (pending_session==session && pending_epoch==epoch)))))) begin
                        command_failed <= 1;
                        state <= FINISH;
                    end else begin
                        last_now <= command_now;
                        config_changed <= command == 2 && (!configured ||
                            pending_session != session || pending_epoch != epoch || pending_mode != mode);
                        scan_lane <= 0;
                        state <= EXP_CALC;
                    end
                end
                EXP_CALC: begin
                    wait_age <= command_now - scan_arrival;
                    frame_age <= command_now - scan_frame[204:141];
                    state <= EXP_CHECK;
                end
                EXP_CHECK: begin
                    if (scan_valid && (config_changed || wait_age >= max_wait || frame_age >= max_age))
                        publish(2, config_changed ? 4'd3 : 4'd2, scan_frame, 384'd0,
                            64'd0, scan_lane ? 2'b10 : 2'b01, EXP_NEXT);
                    else state <= EXP_NEXT;
                end
                EXP_NEXT: begin
                    if (!scan_lane) begin scan_lane <= 1; state <= EXP_CALC; end
                    else if (command == 2 && config_changed) state <= CONFIG_COMMIT;
                    else if (command == 0) state <= VALID_CALC;
                    else state <= FINISH;
                end
                CONFIG_COMMIT: begin
                    if (!configured || pending_session != session) begin
                        sequence_seen <= 0; generation_seen <= 0;
                        sequence_ledger <= 0; generation_ledger <= 0; timestamp_ledger <= 0;
                    end
                    session <= pending_session; epoch <= pending_epoch; mode <= pending_mode;
                    max_delta <= pending_delta; max_wait <= pending_wait; max_age <= pending_age;
                    configured <= 1;
                    state <= FINISH;
                end
                VALID_CALC: begin
                    sequence_delta <= offer[108:77] - sequence_ledger[camera*32 +: 32];
                    generation_delta <= offer[44:13] - generation_ledger[ledger_index*32 +: 32];
                    offer_age <= command_now - offer[204:141];
                    state <= VALID_CHECK;
                end
                VALID_CHECK: begin
                    if (rejected) publish(3, rejection, offer, 384'd0, 64'd0, 0, FINISH);
                    else state <= ADMIT;
                end
                ADMIT: begin
                    sequence_seen[camera] <= 1;
                    sequence_ledger[camera*32 +: 32] <= offer[108:77];
                    timestamp_ledger[camera*64 +: 64] <= offer[204:141];
                    generation_seen[ledger_index] <= 1;
                    generation_ledger[ledger_index*32 +: 32] <= offer[44:13];
                    if (mode == 0) publish(1, 1, offer, 384'd0, 64'd0, 0, FINISH);
                    else if (offer_lane ? valid1 : valid0)
                        publish(2, 4, offer_lane ? resident1 : resident0, 384'd0,
                            64'd0, offer_lane ? 2'b10 : 2'b01, INSERT);
                    else state <= INSERT;
                end
                INSERT: begin
                    if (offer_lane) begin resident1 <= offer; arrival1 <= command_now; valid1 <= 1; end
                    else begin resident0 <= offer; arrival0 <= command_now; valid0 <= 1; end
                    state <= PAIR_CALC;
                end
                PAIR_CALC: begin
                    if (valid0 && valid1) begin
                        right_older <= resident1[204:141] < resident0[204:141];
                        pair_delta <= resident0[204:141] >= resident1[204:141] ?
                            resident0[204:141] - resident1[204:141] :
                            resident1[204:141] - resident0[204:141];
                        pair_compatible <= resident0[76:45] == resident1[76:45] &&
                            resident0[140:109] == resident1[140:109] &&
                            resident0[270:205] == resident1[270:205] &&
                            resident0[334:303] == resident1[334:303] &&
                            resident0[3] == resident1[3] &&
                            (mode == 2 ? (resident0[366:335] == resident1[366:335] &&
                                resident0[366:335] != 0 && resident0[302:271] > resident1[302:271] &&
                                resident0[204:141] <= resident1[204:141]) :
                                resident0[302:271] == resident1[302:271]);
                        state <= PAIR_CHECK;
                    end else state <= FINISH;
                end
                PAIR_CHECK: begin
                    if (pair_compatible && pair_delta <= max_delta) begin
                        pair_counter <= pair_counter + 1'b1;
                        publish(0, 0, resident0, resident1, pair_counter + 1'b1, 2'b11, FINISH);
                    end else publish(2, pair_delta > max_delta ? 4'd5 : 4'd6,
                        right_older ? resident1 : resident0, 384'd0, 64'd0,
                        right_older ? 2'b10 : 2'b01, FINISH);
                end
                EVENT: begin
                    if (i_event_ready) begin
                        o_event_valid <= 0;
                        if (event_remove[0]) valid0 <= 0;
                        if (event_remove[1]) valid1 <= 0;
                        state <= return_state;
                    end
                end
                FINISH: begin
                    o_done <= real_command;
                    o_error <= real_command && command_failed;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
