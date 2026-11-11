// Fixed two-frame convex RGB average; no multiplier, RAM or temporal feedback.
module preprocess_temporal_nr_blend4 (
    input wire [95:0] i_current, i_history,
    input wire [7:0] i_confidence, input wire [3:0] i_lane_valid,
    input wire [7:0] i_guard,
    output wire [95:0] o_rgb, output wire [3:0] o_fused
);
    function [7:0] blend;
        input [7:0] current, history;input [1:0] confidence;
        reg [10:0] sum;
        begin
            case(confidence)
                2'd1:sum={3'd0,current}+({3'd0,current}<<1)+({3'd0,current}<<2)+{3'd0,history}+11'd4;
                2'd2:sum=({3'd0,current}<<2)+({3'd0,current}<<1)+({3'd0,history}<<1)+11'd4;
                2'd3:sum=({3'd0,current}<<2)+({3'd0,history}<<2)+11'd4;
                default:sum={current,3'd0};
            endcase
            blend=sum[10:3];
        end
    endfunction
    genvar lane, channel;
    generate for(lane=0;lane<4;lane=lane+1) begin: lanes
        wire [7:0] delta[0:2];
        for(channel=0;channel<3;channel=channel+1) begin: channels
            wire [7:0] current=i_current[lane*24+channel*8+:8];
            wire [7:0] history=i_history[lane*24+channel*8+:8];
            assign delta[channel]=current>=history ? current-history : history-current;
            assign o_rgb[lane*24+channel*8+:8]=blend(current,history,
                o_fused[lane] ? i_confidence[lane*2+:2] : 2'd0);
        end
        assign o_fused[lane]=i_lane_valid[lane] && i_confidence[lane*2+:2]!=0 &&
            delta[0]<=i_guard && delta[1]<=i_guard && delta[2]<=i_guard;
    end endgenerate
endmodule
