`timescale 1ns/1ps
`default_nettype none
// One held event bit and a toggle/acknowledge crossing. Payload stays fixed
// until the acknowledgement returns. Overflow revokes source qualification.
module real_hdr_event_cdc (
    input wire s_clk,s_reset_n,s_event,s_ok,
    output reg s_overflow,
    input wire m_clk,m_reset_n,
    output reg m_event,m_ok
);
    reg request,payload,acknowledge;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] ack_sync,request_sync;
    always @(posedge s_clk or negedge s_reset_n)begin
        if(!s_reset_n)begin request<=0;payload<=0;ack_sync<=0;s_overflow<=0;end
        else begin
            ack_sync<={ack_sync[0],acknowledge};
            if(s_event)begin
                if(request!=ack_sync[1])s_overflow<=1;
                else begin payload<=s_ok;request<=!request;end
            end
        end
    end
    always @(posedge m_clk or negedge m_reset_n)begin
        if(!m_reset_n)begin request_sync<=0;acknowledge<=0;m_event<=0;m_ok<=0;end
        else begin
            request_sync<={request_sync[0],request};m_event<=0;
            if(request_sync[1]!=acknowledge)begin
                m_ok<=payload;m_event<=1;acknowledge<=request_sync[1];
            end
        end
    end
endmodule
`default_nettype wire
