`timescale 1ns/1ps
`include "fixture.vh"
module quant_entropy_path #(parameter SYNC=0)(
    input wire clk,rst_n,cancel,frame_begin,checking,
    input wire [1:0] frame,
    input wire [31:0] frame_cycle,
    output wire done
);
    reg [259:0] columns[0:`COLUMN_TOTAL-1];
    reg [146:0] golden_tokens[0:`TOKEN_TOTAL-1];
    reg [7:0] golden_bytes[0:`BYTE_TOTAL-1];
    reg [31:0] byte_counts[0:3],byte_offsets[0:3];
    initial begin
        $readmemh("columns.hex",columns);$readmemh("tokens.hex",golden_tokens);
        $readmemh("entropy.hex",golden_bytes);$readmemh("byte_counts.hex",byte_counts);$readmemh("byte_offsets.hex",byte_offsets);
    end
    reg valid=0;wire ready,token_valid,quant_error;
    reg [259:0] input_word=0;
    wire [146:0] token;
    wire token_ready;
    wire [63:0] table_q;
    wire private_rst_n=rst_n&&!cancel;
    generate if(SYNC)begin:g_new
        jpeg_quant_stream #(.TINY_DISTRIBUTED_RAM_ENABLE(1)) quant (
            .i_clk(clk),.i_rst_n(private_rst_n),.i_column_valid(valid),.o_column_ready(ready),
            .i_column_data(input_word[127:0]),.i_column_index(input_word[130:128]),
            .i_capture_id(input_word[162:131]),.i_frame_last(input_word[163]),.i_block_index(input_word[165:164]),
            .i_mcu_y(input_word[174:166]),.i_mcu_x(input_word[183:175]),.i_component(input_word[185:184]),
            .i_quality(input_word[192:186]),.i_epoch(input_word[224:193]),.i_session_id(input_word[256:225]),.i_camera_id(input_word[257]),
            .o_token_valid(token_valid),.i_token_ready(token_ready),.o_token_data(token),.o_error(quant_error),
            .i_table_quality(7'd75),.i_table_component(1'b0),.i_table_column(3'd0),.i_table_enable(1'b0),.o_table_quantizers(table_q));
    end else begin:g_old
        jpeg_quant_stream_async_reference #(.TINY_DISTRIBUTED_RAM_ENABLE(1)) quant (
            .i_clk(clk),.i_rst_n(private_rst_n),.i_column_valid(valid),.o_column_ready(ready),
            .i_column_data(input_word[127:0]),.i_column_index(input_word[130:128]),
            .i_capture_id(input_word[162:131]),.i_frame_last(input_word[163]),.i_block_index(input_word[165:164]),
            .i_mcu_y(input_word[174:166]),.i_mcu_x(input_word[183:175]),.i_component(input_word[185:184]),
            .i_quality(input_word[192:186]),.i_epoch(input_word[224:193]),.i_session_id(input_word[256:225]),.i_camera_id(input_word[257]),
            .o_token_valid(token_valid),.i_token_ready(token_ready),.o_token_data(token),.o_error(quant_error),
            .i_table_quality(7'd75),.i_table_component(1'b0),.i_table_column(3'd0),.i_table_enable(1'b0),.o_table_quantizers(table_q));
    end endgenerate
    wire byte_valid,byte_last,entropy_done,entropy_error,idle;
    wire [7:0] entropy_byte,error_code;wire [31:0] error_id;
    reg byte_ready=0;integer last_hold=0;reg last_held=0;
    wire [15:0] restart=(frame==0 ? 0 : frame==1 ? 1 : frame==2 ? 3 : 2);
    jpeg_entropy #(.STREAM_INPUT_ENABLE(1),.RESTART_ENABLE(1),.COEFF_BANKED_STORAGE_ENABLE(1)) entropy (
        .i_clk(clk),.i_rst_n(rst_n),.i_abort(cancel),.i_block_valid(1'b0),.o_block_ready(),.i_coeffs(1024'd0),
        .i_component(2'd0),.i_block_index(2'd0),.i_mcu_x(9'd0),.i_mcu_y(9'd0),.i_frame_last(1'b0),.i_capture_id(32'd0),
        .i_token_valid(token_valid),.o_token_ready(token_ready),.i_token_data(token[127:0]),.i_token_keep(token[143:128]),
        .i_token_last(token[144]),.i_token_user(token[146:145]),.i_restart_mcus(restart),
        .o_byte_valid(byte_valid),.i_byte_ready(cancel ? 1'b1 : byte_ready),.o_byte(entropy_byte),.o_byte_last(byte_last),
        .o_entropy_done(entropy_done),.o_error_valid(entropy_error),.o_error_capture_id(error_id),.o_error_code(error_code),.o_idle(idle));
    integer sent=0,tokens=0,bytes_out=0,stalls=0,peak_resident=0;
    reg held=0;reg [8:0] held_byte;
    reg [31:0] rng=32'h9a3c6e21;
    reg saw_done=0;
    reg input_accepted=0;
    assign done=checking && saw_done;
    always @(negedge clk)begin
        if(!rst_n||cancel||frame_begin)begin valid=0;byte_ready=0;last_hold=0;last_held=0;end
        else begin
            if(!valid||input_accepted)begin
                valid=sent<`COLUMNS_PER_FRAME;
                if(valid)input_word=columns[frame*`COLUMNS_PER_FRAME+sent];
            end
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            if(!checking||frame_cycle<7000)byte_ready=0;
            else if(last_hold>0)begin last_hold=last_hold-1;byte_ready=0;end
            else if(!last_held && bytes_out==byte_counts[frame]-1 && byte_valid)begin last_held=1;last_hold=31;byte_ready=0;end
            else byte_ready=rng[2:0]!=0;
        end
    end
    always @(posedge clk)begin
        input_accepted=valid&&ready;
        if(!rst_n||cancel||frame_begin)begin sent=0;tokens=0;bytes_out=0;held=0;saw_done=0;input_accepted=0;end
        else begin
            if(valid&&ready)sent=sent+1;
            if(quant_error||entropy_error)$fatal(1,"integration error variant%0d quant%0d entropy%0d code%0d sent%0d column%0d",SYNC,quant_error,entropy_error,error_code,sent,input_word[130:128]);
            if(checking)begin
                if(token_valid&&token_ready)begin
                    if(tokens>=`TOKENS_PER_FRAME||token!==golden_tokens[frame*`TOKENS_PER_FRAME+tokens])$fatal(1,"token mismatch variant%0d frame%0d index%0d",SYNC,frame,tokens);
                    tokens=tokens+1;
                end
                if(held&&(!byte_valid||{byte_last,entropy_byte}!==held_byte))$fatal(1,"entropy output changed stalled variant%0d",SYNC);
                held=byte_valid&&!byte_ready;if(held)begin held_byte={byte_last,entropy_byte};stalls=stalls+1;end
                if(byte_valid&&byte_ready)begin
                    if(bytes_out>=byte_counts[frame]||entropy_byte!==golden_bytes[byte_offsets[frame]+bytes_out]||byte_last!==(bytes_out==byte_counts[frame]-1))
                        $fatal(1,"entropy mismatch variant%0d frame%0d byte%0d got%h expected%h last%0d",SYNC,frame,bytes_out,entropy_byte,golden_bytes[byte_offsets[frame]+bytes_out],byte_last);
                    bytes_out=bytes_out+1;
                end
                if(entropy_done && !saw_done)begin
                    if(tokens!=`TOKENS_PER_FRAME||bytes_out!=byte_counts[frame]||!last_held)$fatal(1,"incomplete integration frame");
                    saw_done=1;$display("FRAME_PASS variant=%0d frame=%0d tokens=%0d bytes=%0d entropy_stall_cycles=%0d",SYNC,frame,tokens,bytes_out,stalls);
                end
            end
        end
    end
    if(SYNC)always @(posedge clk)if(g_new.quant.u_token_fifo.o_resident>peak_resident)peak_resident=g_new.quant.u_token_fifo.o_resident;
endmodule

module tb_quant_entropy;
    reg clk=0;always #4 clk=!clk;
    reg rst_n=0,cancel=0,frame_begin=0,checking=0;
    reg [1:0] frame=0;reg [31:0] frame_cycle=0;
    wire [1:0] done;
    quant_entropy_path #(.SYNC(0)) old_path(clk,rst_n,cancel,frame_begin,checking,frame,frame_cycle,done[0]);
    quant_entropy_path #(.SYNC(1)) new_path(clk,rst_n,cancel,frame_begin,checking,frame,frame_cycle,done[1]);
    integer cycles=0,n;
    always @(posedge clk)begin
        cycles=cycles+1;frame_cycle=frame_cycle+1;
        if(cycles>400000)$fatal(1,"integration timeout frame%0d old%0d/%0d new%0d/%0d",frame,old_path.tokens,old_path.bytes_out,new_path.tokens,new_path.bytes_out);
    end
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        // Fill with an unfinished cohort while bytes are held, then use the
        // encoder's real one-clock private_rst_n/entropy-abort cancellation.
        repeat(3500)@(negedge clk);cancel=1;frame_begin=1;@(negedge clk);cancel=0;
        repeat(20)@(negedge clk);checking=1;
        for(n=0;n<4;n=n+1)begin
            @(negedge clk);frame=n;frame_begin=1;frame_cycle=0;
            @(negedge clk);frame_begin=0;
            wait(&done);repeat(12)@(negedge clk);
        end
        if(new_path.peak_resident!=512)$fatal(1,"integration did not fill512 tokens");
        $display("RESULT: PASS quant->entropy A/B four qualities four restart policies; 4608 golden tokens and exact entropy bytes each; cancel/recovery; peak512");$finish;
    end
endmodule
