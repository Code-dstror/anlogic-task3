`timescale 1ns/1ps
`default_nettype none

// PF0 vector zero alerts RK about the level-held result register. Polling and
// MSI use the same RESULT/ACK ownership; the interrupt never retires a buffer.
module camera_pcie_result_msi (
    input wire clk, rst_n, link_up, result_pending, enabled, masked, grant,
    output reg request,
    output wire masked_pending
);
    reg notified;
    assign masked_pending = rst_n && link_up && enabled && masked && result_pending && !notified;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            request <= 1'b0;
            notified <= 1'b0;
        end else if (!link_up) begin
            request <= 1'b0;
            notified <= 1'b0;
        end else begin
            if (!result_pending)
                notified <= 1'b0;
            if (request) begin
                if (grant)
                    request <= 1'b0;
            end else if (result_pending && enabled && !masked && !notified) begin
                request <= 1'b1;
                notified <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
