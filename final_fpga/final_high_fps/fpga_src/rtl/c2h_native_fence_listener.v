// No-backpressure receiver for exactly one PF0 4-byte host fence Completion.
// See CONTRACT.md for field qualifiers and conservative fault semantics.
module c2h_native_fence_listener (
    input wire clk,rst_n,
    input wire fence_start,
    input wire [6:0] fence_lower_address,
    input wire [31:0] fence_cookie,
    input wire [15:0] fence_requester_id,
    input wire [127:0] rx_data,
    input wire [3:0] rx_dwen,
    input wire rx_hv,rx_dv,rx_eot,
    input wire rx_dllp_abort,rx_tlp_abort,rx_ecrc_error,
    input wire [63:0] rx_address,
    input wire [1:0] rx_format,
    input wire [4:0] rx_type,
    input wire [2:0] rx_tc,rx_attributes,
    input wire [15:0] rx_requester_id,rx_completer_id,
    input wire [9:0] rx_tag,rx_dword_length,
    input wire rx_function,rx_vf_active,rx_poisoned,rx_cpl_last,
    input wire [2:0] rx_status,
    input wire [11:0] rx_byte_count,
    input wire [1:0] rx_at,
    input wire rx_th,rx_bcm,requester_timeout,
    output reg [127:0] rc_data,
    output wire [3:0] rc_keep,
    output wire [74:0] rc_user,
    output wire rc_last,
    output reg rc_valid,
    input wire rc_ready,
    output reg fault,
    output wire o_incident_now,
    output wire outstanding
);
    reg pending,header_pending;
    reg [6:0] expected_address;
    reg [31:0] expected_cookie;
    reg [15:0] expected_requester;
    reg [95:0] held_header;
    wire have_owner=pending||fence_start;
    wire [6:0] owner_address=fence_start ? fence_lower_address : expected_address;
    wire [31:0] owner_cookie=fence_start ? fence_cookie : expected_cookie;
    wire [15:0] owner_requester=fence_start ? fence_requester_id : expected_requester;
    wire fields_good=rx_format==2 && rx_type==5'h0a && rx_tc==0 && rx_attributes==0 &&
        rx_requester_id==owner_requester && rx_tag==10'h01a && !rx_function && !rx_vf_active &&
        !rx_poisoned && rx_dword_length==1 && rx_byte_count==4 && rx_cpl_last && rx_status==0 &&
        rx_address[6:0]==owner_address && rx_at==0 && !rx_th && !rx_bcm;
    wire [95:0] current_header={1'b0,rx_attributes,rx_tc,1'b0,rx_completer_id,rx_tag[7:0],
        rx_requester_id,1'b0,rx_poisoned,rx_status,1'b0,rx_dword_length,
        1'b0,rx_cpl_last,1'b0,1'b0,rx_byte_count,4'd0,rx_address[11:0]};
    wire header_valid_for_data=rx_hv ? have_owner&&!header_pending&&fields_good : pending&&header_pending;
    wire end_error=(rx_hv||rx_dv)&&rx_eot&&(rx_dllp_abort||rx_tlp_abort||rx_ecrc_error||!rx_dv);
    wire violation=requester_timeout || (fence_start&&pending) || (rc_valid&&!rc_ready) ||
        (rx_hv&&(!have_owner||header_pending||!fields_good)) ||
        (rx_dv&&(!header_valid_for_data||!rx_eot||rx_dwen!=1||rx_data[31:0]!=owner_cookie||!rc_ready)) || end_error;
    wire success=rx_dv&&rx_eot&&header_valid_for_data&&!violation&&!fault;
    // Report the current qualified native violation before the same edge can
    // accept a host ACK, separately from the unchanged sticky fault output.
    assign o_incident_now=fault || (rst_n && violation);
    assign outstanding=pending;
    assign rc_keep=4'hf;
    assign rc_last=1'b1;
    assign rc_user={16'd0,16'hffff,1'b1,1'b0,4'd0,4'd0,1'b0,32'd0};
    // Pending/header/valid/fault close asynchronously. The expected fields
    // have no owner while pending=0 and are replaced atomically at fence_start.
    // Keep their payload clear on the local D path rather than the ASR tree.
    always @(posedge clk) begin
        if(!rst_n) begin
            expected_address<=0;expected_cookie<=0;expected_requester<=0;
        end else if(fence_start&&!fault) begin
            expected_address<=fence_lower_address;
            expected_cookie<=fence_cookie;expected_requester<=fence_requester_id;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pending<=0;header_pending<=0;fault<=0;rc_valid<=0;
        end else begin
            rc_valid<=0;
            if(fence_start&&!fault) begin
                pending<=1;
            end
            if(violation) fault<=1;
            if(rx_hv&&!fault&&!violation) begin
                held_header<=current_header;header_pending<=1;
            end
            if(success) begin
                rc_data<={rx_data[31:0],rx_hv ? current_header : held_header};
                rc_valid<=1;pending<=0;header_pending<=0;
            end
        end
    end
endmodule
