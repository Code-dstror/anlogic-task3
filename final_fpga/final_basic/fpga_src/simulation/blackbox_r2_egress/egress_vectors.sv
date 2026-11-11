`timescale 1ns/1ps

package egress_vectors;
    typedef struct packed {
        logic [31:0] capture_id;
        logic [31:0] session;
        logic [31:0] epoch;
        logic [31:0] tag;
        logic [63:0] timestamp_ns;
        logic [15:0] width;
        logic [15:0] height;
        logic camera;
        logic [7:0] quality;
    } frame_t;

    typedef logic [16383:0] extension_t;

    function automatic frame_t fixture(input logic [31:0] capture_id, input integer owner);
        frame_t frame;
        frame.capture_id = capture_id;
        frame.session = 32'hf305_be40 ^ (32'h1023_1a4c * owner);
        frame.epoch = 32'h0298_ac73 ^ (32'h13e1_00cd * owner);
        frame.tag = 32'h2bd8_039a ^ (32'h0123_a5d7 * owner);
        frame.timestamp_ns = 64'hfedc_1012_a678_1b23 + 17 * owner;
        frame.width = 16'd1920;
        frame.height = 16'd1080;
        frame.camera = owner[0];
        frame.quality = 8'(72 + owner);
        return frame;
    endfunction

    function automatic extension_t extension_for(input frame_t frame);
        extension_t value;
        value = '0;
        value[31:0] = 32'h32585443;
        value[47:32] = 16'd1;
        value[48] = 1'b1;
        value[95:64] = frame.session;
        value[127:96] = frame.epoch;
        value[159:128] = frame.capture_id;
        value[167:160] = {7'b0, frame.camera};
        // Record v4 no-points, disabled shape at extension byte offset 128.
        value[1024 +: 128] = 128'h010d_00a9_0000_0000_0000_0501_3456_5053;
        return value;
    endfunction

    function automatic logic [127:0] jpeg_bytes(input frame_t frame, input integer beat,
                                               input bit last);
        logic [127:0] value;
        value = {frame.capture_id ^ 32'hff01_3685, frame.tag ^ (32'h5aac_1e2f * beat),
                 frame.session ^ (32'h9632_0e71 * beat), frame.epoch + 31 * beat};
        if (last)
            value[127:88] = '0;
        return value;
    endfunction

    function automatic logic [15:0] jpeg_keep(input bit last);
        return last ? 16'h07ff : 16'hffff;
    endfunction

    function automatic logic [24:0] jpeg_length(input integer beats, input bit ends);
        return 25'(16 * beats - (ends ? 5 : 0));
    endfunction
endpackage
