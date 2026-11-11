// Module-local combinational encoding for the frozen F21-only capability.
// Pack only after full1024 validation. This function is not a validator.
function [100:0] f21_pack_extension;
    input [1023:0] extension;
    begin
        f21_pack_extension={extension[383:352],extension[322:256],extension[11],extension[0]};
    end
endfunction
function [1023:0] f21_unpack_extension;
    input [100:0] packed_extension;
    begin
        f21_unpack_extension=1024'd0;
        f21_unpack_extension[0]=packed_extension[0];
        f21_unpack_extension[11]=packed_extension[1];
        f21_unpack_extension[322:256]=packed_extension[68:2];
        f21_unpack_extension[383:352]=packed_extension[100:69];
    end
endfunction
function [260:0] f21_pack_tuple;
    input [1183:0] tuple;
    begin
        f21_pack_tuple={f21_pack_extension(tuple[1183:160]),tuple[159:0]};
    end
endfunction
function [1183:0] f21_unpack_tuple;
    input [260:0] packed_tuple;
    begin
        f21_unpack_tuple={f21_unpack_extension(packed_tuple[260:160]),packed_tuple[159:0]};
    end
endfunction
