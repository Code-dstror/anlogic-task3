`timescale 1ns/1ps
`default_nettype none
// Read-only local-domain counters. These pages feed only the UART snapshot;
// there is no output to a business reset, READY, owner or admission decision.
module camera_field_diagnostics (
    input wire dfi_clk,dfi_rst_n,dfi_run,
    input wire [31:0] dfi_session,dfi_epoch,
    input wire job_fire,job_camera,input wire [31:0] job_sequence,
    input wire [1:0] begin_reject,pair_expire,bad_finish,
    input wire [7:0] bank_states,dfi_flags,
    input wire pixel_clk,pixel_rst_n,pixel_run,
    input wire [31:0] pixel_epoch,
    input wire [31:0] cfg_applied_epoch,
    input wire [15:0] cfg_flags,
    input wire [3:0] capture_admit,
    input wire [15:0] pixel_flags,
    output wire [223:0] dfi_page,pixel_page
);
    reg dfi_run_q,pixel_run_q;
    reg [31:0] last_sequence0,last_sequence1;
    reg [15:0] jobs0,jobs1,admit0,admit1,admit2,admit3;
    reg [7:0] reject0,reject1,expire0,expire1,bad0,bad1;
    // Modulo counters are reset on application RUN, not on a mode switch.
    // The separately sampled active epoch identifies windows spanning a CFG.
    always @(posedge dfi_clk or negedge dfi_rst_n)begin
        if(!dfi_rst_n)begin
            dfi_run_q<=0;last_sequence0<=0;last_sequence1<=0;jobs0<=0;jobs1<=0;
            reject0<=0;reject1<=0;expire0<=0;expire1<=0;bad0<=0;bad1<=0;
        end else begin
            dfi_run_q<=dfi_run;
            if(dfi_run)begin
                if(!dfi_run_q)begin
                    last_sequence0<=job_fire&&!job_camera?job_sequence:0;
                    last_sequence1<=job_fire&&job_camera?job_sequence:0;
                    jobs0<=job_fire&&!job_camera;jobs1<=job_fire&&job_camera;
                    reject0<=begin_reject[0];reject1<=begin_reject[1];
                    expire0<=pair_expire[0];expire1<=pair_expire[1];
                    bad0<=bad_finish[0];bad1<=bad_finish[1];
                end else begin
                    if(job_fire&&!job_camera)begin jobs0<=jobs0+1'b1;last_sequence0<=job_sequence;end
                    if(job_fire&&job_camera)begin jobs1<=jobs1+1'b1;last_sequence1<=job_sequence;end
                    if(begin_reject[0])reject0<=reject0+1'b1;
                    if(begin_reject[1])reject1<=reject1+1'b1;
                    if(pair_expire[0])expire0<=expire0+1'b1;
                    if(pair_expire[1])expire1<=expire1+1'b1;
                    if(bad_finish[0])bad0<=bad0+1'b1;
                    if(bad_finish[1])bad1<=bad1+1'b1;
                end
            end
        end
    end
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)begin pixel_run_q<=0;admit0<=0;admit1<=0;admit2<=0;admit3<=0;end
        else begin
            pixel_run_q<=pixel_run;
            if(pixel_run)begin
                if(!pixel_run_q)begin
                    admit0<=capture_admit[0];admit1<=capture_admit[1];
                    admit2<=capture_admit[2];admit3<=capture_admit[3];
                end else begin
                    if(capture_admit[0])admit0<=admit0+1'b1;
                    if(capture_admit[1])admit1<=admit1+1'b1;
                    if(capture_admit[2])admit2<=admit2+1'b1;
                    if(capture_admit[3])admit3<=admit3+1'b1;
                end
            end
        end
    end
    assign dfi_page={dfi_flags,bank_states,bad1,bad0,expire1,expire0,reject1,reject0,
        jobs1,jobs0,dfi_session,dfi_epoch,last_sequence1,last_sequence0};
    // [159:96] are reserved for the two SYS-domain sensor diagnostics. The
    // UART's SYS FREEZE edge overlays them without creating another CDC bus.
    assign pixel_page={cfg_flags,pixel_epoch,pixel_flags,64'd0,admit3,admit2,admit1,admit0,cfg_applied_epoch};
endmodule
`default_nettype wire
