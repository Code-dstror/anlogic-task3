`timescale 1ns/1ps
module tb_parser;
parameter [31:0] INITIAL_SEQUENCE=0;
reg clk=0,rst_n=0,id_rst_n=0,valid=0,ready=1;reg [31:0] din=0;
always #5 clk=~clk;
wire [39:0] data;wire ov,sof,eol,abort,identity_fault,ecc_error,crc_error,length_error,done,wait_sync;
wire [3:0] code;wire [31:0] sequence_count;wire [63:0] diag,trace;
physical_csi_word_core #(.RX_DIAG_ENABLE(1),.SEQUENCE_INITIAL(INITIAL_SEQUENCE)) dut(
.i_clk(clk),.i_reset_n(rst_n),.i_identity_rst_n(id_rst_n),.i_word(din),.i_word_valid(valid),.i_sink_ready(ready),
.o_data(data),.o_valid(ov),.o_sof(sof),.o_eol(eol),.o_abort(abort),.o_error_code(code),
.o_source_sequence_count(sequence_count),.o_identity_fault(identity_fault),.o_identity_diag(diag),.o_trace_parser(trace),.o_trace_trigger(),
.o_header_ecc_error(ecc_error),.o_payload_crc_error(crc_error),.o_length_error(length_error),.o_packet_done(done),.o_wait_for_sync(wait_sync));
integer checks=0,failures=0,case_errors=0,cases=0,detected=0,nwant=0,ngot=0,cycle=0;
integer fd;string label="",category="";reg active=0,held=0;
reg [46:0] held_token;reg [46:0] expected[0:16383],actual[0:16383];
task verify(input bit ok,input string why);begin checks++;if(!ok)begin failures++;case_errors++;if(case_errors<8)$display("MISMATCH|%s|%s",label,why);end end endtask
task idle(input integer n);begin valid=0;din=0;repeat(n)@(negedge clk);end endtask
task put(input [31:0] value);begin din=value;valid=1;@(negedge clk);end endtask
task head(input [31:0] value);begin put(value);idle(4);end endtask
task want(input [3:0] c,input bit a,input bit s,input bit e,input [39:0] d);begin expected[nwant]={c,a,e,s,d};nwant++;end endtask
task start_case(input string name,input string kind);begin
 @(negedge clk);active=0;valid=0;ready=1;rst_n=0;id_rst_n=0;held=0;
 repeat(5)@(negedge clk);rst_n=1;id_rst_n=1;repeat(3)@(negedge clk);
 label=name;category=kind;case_errors=0;nwant=0;ngot=0;active=1;cases++;
end endtask
task finish_case(input [31:0] seq,input bit fault,input [2:0] errors,input integer state);
begin idle(24);verify(ngot==nwant,$sformatf("token_count actual=%0d expected=%0d",ngot,nwant));
 for(integer j=0;j<ngot&&j<nwant;j++)verify(actual[j]===expected[j],$sformatf("token%0d got=%012h expected=%012h",j,actual[j],expected[j]));
 verify(sequence_count==seq,$sformatf("source count got=%0d expected=%0d",sequence_count,seq));
 verify(identity_fault===fault,"identity_fault");verify({length_error,crc_error,ecc_error}===errors,"error flags");
 if(state>=0)verify(trace[33:32]==state,"parser state");
 $display("CASE|%s|%s|category=%s|tokens=%0d|source=%0d|fault=%b|flags=%b|state=%0d",label,case_errors==0?"PASS":"FAIL",category,ngot,sequence_count,identity_fault,{length_error,crc_error,ecc_error},trace[33:32]);active=0;
end endtask
task risk(input string why);begin detected++;$display("DETECTED|%s|%s",label,why);end endtask
always @(posedge clk)begin
cycle++;
if(!rst_n)held=0;else if(active)begin
 if(held)verify(ov&&{code,abort,eol,sof,data}===held_token,"accepted-stall token changed");
 held=ov&&!ready;held_token={code,abort,eol,sof,data};
 if(ov&&ready)begin actual[ngot]={code,abort,eol,sof,data};ngot++;
 $fwrite(fd,"%s,%0d,%0d,%b,%b,%b,%010h\n",label,cycle,code,abort,sof,eol,data);end
end end
initial begin fd=$fopen("tokens.csv","w");$fwrite(fd,"case,cycle,code,abort,sof,eol,data\n");
__CASES__
$display("RESULT|cases=%0d|checks=%0d|failures=%0d|detected=%0d",cases,checks,failures,detected);$fclose(fd);$finish;end
initial begin #10000000;$fatal(1,"bounded timeout");end
endmodule
