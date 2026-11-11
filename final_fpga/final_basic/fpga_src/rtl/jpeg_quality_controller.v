`timescale 1ns/1ps

// Host opt-in quality feedback uses completed JPEG lengths, never FIFO fullness.
module jpeg_quality_controller (
    input wire clk, input wire rst_n,
    input wire adaptive_enable, input wire [7:0] requested_quality, minimum_quality,
    input wire [24:0] frame_budget, input wire [31:0] mode_epoch,
    input wire frame_begin, input wire frame_complete, input wire frame_ok,
    input wire [24:0] completed_length,
    output wire [7:0] selected_quality,
    output reg [31:0] over_budget_count,
    output reg [7:0] degradation_reason
);
    reg history_valid;
    reg [31:0] history_epoch;
    reg [7:0] recommendation,frame_quality,frame_minimum,frame_maximum;
    reg [24:0] budget;
    reg frame_adaptive;
    reg [1:0] below_count;
    wire matching_history=history_valid && history_epoch==mode_epoch;
    wire [7:0] bounded=recommendation<minimum_quality ? minimum_quality :
        recommendation>requested_quality ? requested_quality : recommendation;
    assign selected_quality = adaptive_enable && frame_budget!=0 && matching_history ?
        bounded : requested_quality;
    always @(posedge clk) begin
        if(!rst_n) begin
            history_valid<=0;history_epoch<=0;recommendation<=75;
            frame_quality<=75;frame_minimum<=1;frame_maximum<=75;budget<=0;
            frame_adaptive<=0;below_count<=0;over_budget_count<=0;degradation_reason<=0;
        end else begin
            if(frame_begin) begin
                frame_quality<=selected_quality;frame_minimum<=minimum_quality;
                frame_maximum<=requested_quality;budget<=frame_budget;
                frame_adaptive<=adaptive_enable && frame_budget!=0;
                if(!matching_history) below_count<=0;
                history_epoch<=mode_epoch;
            end
            if(frame_complete) begin
                if(frame_ok) begin
                    history_valid<=1;recommendation<=frame_quality;
                    if(budget!=0 && completed_length>budget) begin
                        over_budget_count<=over_budget_count+1'b1;
                        degradation_reason<=frame_quality==frame_minimum ? 8'd2 : 8'd1;
                        below_count<=0;
                        if(frame_adaptive)
                            recommendation<=frame_quality>frame_minimum+8'd5 ?
                                frame_quality-8'd5 : frame_minimum;
                    end else begin
                        degradation_reason<=0;
                        if(frame_adaptive && completed_length<budget-(budget>>2)) begin
                            if(below_count==2) begin
                                recommendation<=frame_quality<frame_maximum ? frame_quality+1'b1 : frame_maximum;
                                below_count<=0;
                            end else below_count<=below_count+1'b1;
                        end else below_count<=0;
                    end
                end else begin
                    history_valid<=0;below_count<=0;degradation_reason<=3;
                end
            end
        end
    end
endmodule
