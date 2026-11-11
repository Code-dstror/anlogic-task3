module td_smoke (
    input wire clk,
    output reg led
);

always @(posedge clk) begin
    led <= ~led;
end

endmodule
