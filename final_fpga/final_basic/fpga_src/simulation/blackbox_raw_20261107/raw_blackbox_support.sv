package raw_blackbox_support;
    function automatic logic [15:0] low_keep(input int unsigned count);
        return 16'((32'h1 << count) - 1);
    endfunction

    function automatic logic [7:0] payload_byte(
        input int unsigned stream_key, input int unsigned index
    );
        int unsigned mix;
        mix = stream_key ^ (index * 32'h9e3779b9);
        mix = (mix ^ (mix >> 16)) * 32'h7feb352d;
        mix = mix ^ (mix >> 15);
        return mix[7:0] ^ mix[23:16];
    endfunction

    function automatic logic [127:0] payload_word(
        input int unsigned stream_key, input int unsigned offset
    );
        for (int lane = 0; lane < 16; lane++) begin
            payload_word[8*lane +: 8] = payload_byte(stream_key, offset + lane);
        end
    endfunction

    function automatic logic [511:0] araw_header(
        input logic [31:0] payload_bytes,
        input logic [15:0] width, height,
        input logic [31:0] seq_num, session, epoch,
        input logic camera,
        input logic [1:0] bayer,
        input logic time_valid,
        input logic [63:0] capture_time, job_id
    );
        logic [511:0] result;
        result = '0;
        result[8*0  +: 32] = 32'h57415241;
        result[8*4  +: 16] = 16'd1;
        result[8*6  +: 16] = 16'd64;
        result[8*8  +: 32] = payload_bytes;
        result[8*12 +: 16] = width;
        result[8*14 +: 16] = height;
        result[8*16 +: 32] = seq_num;
        result[8*20 +: 32] = session;
        result[8*24 +: 32] = epoch;
        result[8*28 +:  8] = {7'b0, camera};
        result[8*29 +:  8] = 8'd1;
        result[8*30 +:  8] = {6'b0, bayer};
        result[8*31 +:  8] = {7'b0, time_valid};
        result[8*32 +: 64] = capture_time;
        result[8*40 +: 64] = job_id;
        return result;
    endfunction

    function automatic int unsigned next_random(input int unsigned state);
        state = state ^ (state << 13);
        state = state ^ (state >> 17);
        return state ^ (state << 5);
    endfunction
endpackage
