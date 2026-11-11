`timescale 1ns/1ps

// The expectation for each transfer comes from the stimulus oracle, in acceptance order.
module stream_checker #(parameter integer WIDTH = 1) (
    input wire clk, flush,
    input wire s_valid, s_ready, m_valid, m_ready,
    input wire [WIDTH-1:0] s_expected, m_payload,
    input integer latency, spacing,
    output integer accepted, received, stalled
);
    typedef logic [WIDTH-1:0] word_t;
    word_t expected[$];
    int accepted_at[$];
    word_t held_word, want;
    bit held = 0;
    int cycle, previous_accept, origin;

    always @(posedge clk) begin
        if (flush) begin
            expected.delete();
            accepted_at.delete();
            held = 0;
            cycle = 0;
            previous_accept = 0;
            accepted = 0;
            received = 0;
            stalled = 0;
        end else begin
            cycle++;
            if ($isunknown({s_ready, m_valid}))
                $fatal(1, "DATAPATH_FAIL %m unknown READY/VALID cycle=%0d", cycle);
            if (held && (!m_valid || m_payload !== held_word))
                $fatal(1, "DATAPATH_FAIL %m output changed under stall cycle=%0d idx=%0d", cycle, received);
            held = m_valid && !m_ready;
            if (held) begin
                held_word = m_payload;
                stalled++;
            end

            if (s_valid && s_ready) begin
                if (spacing > 0 && accepted > 8 && cycle - previous_accept != spacing)
                    $fatal(1, "DATAPATH_FAIL %m expected spacing %0d got %0d at input %0d",
                           spacing, cycle - previous_accept, accepted);
                expected.push_back(s_expected);
                accepted_at.push_back(cycle);
                accepted++;
                previous_accept = cycle;
            end
            if (m_valid) begin
                if (expected.size() == 0)
                    $fatal(1, "DATAPATH_FAIL %m output without input cycle=%0d idx=%0d", cycle, received);
                want = expected[0];
                if (m_payload !== want)
                    $fatal(1, "DATAPATH_FAIL %m cycle=%0d idx=%0d got=%h expected=%h",
                           cycle, received, m_payload, want);
                if (m_ready) begin
                    want = expected.pop_front();
                    origin = accepted_at.pop_front();
                    if (latency > 0 && cycle - origin != latency)
                        $fatal(1, "DATAPATH_FAIL %m expected latency %0d got %0d at output %0d",
                               latency, cycle - origin, received);
                    received++;
                end
            end
        end
    end
endmodule
