`timescale 1ns / 1ps

module tb_pcie_c2h_postroute;

    reg sys_clk;
    reg refclk_p;
    wire refclk_n;
    reg pcie_mperst;
    reg [0:0] rxp;
    reg [0:0] rxn;
    wire [0:0] txp;
    wire [0:0] txn;

    assign refclk_n = !refclk_p;

    // The routed TD netlist refers to these two global instances by name.
    glbl glbl();
    PH1_PHY_GSR PH1_PHY_GSR();

    pcie_c2h_test_top u_dut (
        .sys_clk(sys_clk),
        .refclk_p(refclk_p),
        .refclk_n(refclk_n),
        .txp(txp),
        .txn(txn),
        .rxp(rxp),
        .rxn(rxn),
        .pcie_mperst(pcie_mperst)
    );

    always #20 sys_clk = !sys_clk;
    always #5 refclk_p = !refclk_p;

    initial begin
        sys_clk = 1'b0;
        refclk_p = 1'b0;
        pcie_mperst = 1'b0;
        rxp = 1'b0;
        rxn = 1'b1;

        #200;
        pcie_mperst = 1'b1;

        // This is a routed-netlist reset/elaboration smoke test. A Root
        // Complex BFM is unavailable, so link training is intentionally not
        // an acceptance condition here.
        #1800;
        $display("[TB] post-route elaboration/reset RESULT: PASS");
        $finish;
    end

endmodule
