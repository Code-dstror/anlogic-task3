`timescale 1ns/1ps

// Passive implementation diagnosis for the frozen a10 product fixture.
// No drivers, assertions, forced state, or verdict on functional qualification.
module trace_a10;
    `define TB $root.tb_fusion_product
    `define DUT `TB.dut
    `define ARB `DUT.u_ddr_store.g_hdr_shared.u_arbiter

    always @(posedge `TB.i_mem_clk) begin
        if (`ARB.w_timeout || `ARB.r_timeout) begin
            $display("DIAG_WATCHDOG t_ns=%0t cycle=%0d w_timeout=%b r_timeout=%b w_state=%d w_wait=%d w_owner=%b b_valid=%b b_ready=%b r_state=%d r_wait=%d raw_ar=%b/%b recovery=%b",
                     $time, `TB.axi_cycle, `ARB.w_timeout, `ARB.r_timeout,
                     `ARB.w_state, `ARB.w_wait, `ARB.w_owner, `ARB.m_bvalid,
                     `ARB.m_bready, `ARB.r_state, `ARB.r_wait, `ARB.s1_arvalid,
                     `ARB.s1_arready, `ARB.o_recovery_required);
        end
    end

    always @(posedge `ARB.o_recovery_required) begin
        $display("DIAG_ARB_RECOVERY t_ns=%0t w_wait=%d r_wait=%d fault=%b",
                 $time, `ARB.w_wait, `ARB.r_wait, `ARB.fault);
    end

    always @(posedge `TB.o_fault) begin
        $display("DIAG_TOP_FAULT t_ns=%0t raw=%b capture=%b processing_event=%b bridge=%b store=%b transport=%b jpeg_dfi=%b jpeg_user=%b record_source=%b",
                 $time, `DUT.raw_processing_fault, `DUT.capture_frontend_fault,
                 `DUT.processing_event_fault, `DUT.bridge_fault, `DUT.store_recovery,
                 `DUT.transport_recovery, `DUT.jpeg_cdc_source_fault,
                 `DUT.jpeg_cdc_user_fault, `DUT.record_source_fault);
    end

    `undef ARB
    `undef DUT
    `undef TB
endmodule
