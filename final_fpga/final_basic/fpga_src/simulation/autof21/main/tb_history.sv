`timescale 1ns/1ps
module tb_autof21_history;
    parameter integer ROWS=1080;
    localparam integer GROUPS=ROWS*480;
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,frame_valid=0,s_valid=0,m_ready=0;
    reg [31:0] frame_capture=0,s_tag=0;
    wire frame_ready,s_ready,m_valid,busy,fault;
    wire map_begin,map_begin_ready,map_release,map_cancel,map_camera;
    wire [208:0] map_cohort;wire [31:0] map_capture;
    wire history_valid,pin_valid,pin_camera;
    wire [7:0] history_age,pin_a;wire [31:0] history_generation,pin_capture;
    wire map_req_valid,map_req_ready,map_reply_valid;wire [7:0] map_req_tile;
    wire [63:0] map_frame_id;wire [19:0] map_reply_data;
    wire [95:0] m_rgb;wire [31:0] m_y,m_tag;wire [63:0] m_owner;
    wire [3:0] m_keep,m_clipped,m_protected;
    wire m_sof,m_eol,m_last,m_history_used;wire [7:0] m_history_age;
    wire [31:0] m_lut_generation;wire [5:0] map_outstanding;
    reg obs_valid=0,obs_sof=0,obs_eol=0,obs_last=0,obs_status_valid=0,source_valid=0;
    reg [31:0] obs_word=0,obs_capture=0,source_capture=0;
    wire obs_ready,obs_status_ready,source_ready,lut_valid,map_commit,candidate_valid;
    wire [31:0] lut_generation,commit_capture;wire [7:0] candidate_index;
    wire [19:0] candidate_data;
    reg [127:0] source_words[0:GROUPS-1];
    reg [135:0] golden[0:GROUPS-1];
    reg [31:0] observations[0:57599];
    reg [19:0] map_words[0:431];
    reg [208:0] cohort;
    integer cycle=0,current_frame=0,commits=0,candidates=0,outputs=0;
    integer frame_outputs=0,reads=0,releases=0,held_checks=0,last_hold=0;
    integer changed_groups=0,changed_frame=0,total_inputs=0;
    reg [31:0] random_state=32'h35a1f210;
    reg held=0;reg [279:0] held_bundle;
    wire [127:0] source_bundle=source_words[s_tag];
    wire [279:0] output_bundle={m_lut_generation,m_history_age,m_owner,m_tag,m_history_used,m_sof,m_eol,m_last,m_keep,m_protected,m_clipped,m_y,m_rgb};
    preprocess_dehaze_qualified_rgb4 rgb(
        .clk(clk),.rst_n(rst_n),.clear(1'b0),.frame_valid(frame_valid),.frame_ready(frame_ready),
        .frame_owner({32'h10203040,frame_capture}),.frame_capture(frame_capture),.frame_camera(1'b0),
        .frame_cohort(cohort),.frame_rows(12'(ROWS)),
        .map_begin(map_begin),.map_begin_ready(map_begin_ready),.map_release(map_release),.map_cancel(map_cancel),
        .map_cohort(map_cohort),.map_capture(map_capture),.map_camera(map_camera),
        .map_history_valid(history_valid),.map_pin_valid(pin_valid),.map_pin_camera(pin_camera),
        .map_history_age(history_age),.map_lut_generation(history_generation),.map_pin_capture(pin_capture),.map_pin_a(pin_a),
        .map_req_valid(map_req_valid),.map_req_ready(map_req_ready),.map_req_tile(map_req_tile),.map_frame_id(map_frame_id),
        .map_reply_valid(map_reply_valid),.map_reply_data(map_reply_data),
        .s_valid(s_valid),.s_ready(s_ready),.s_rgb(source_bundle[95:0]),.s_y(source_bundle[127:96]),
        .s_keep(4'hf),.s_sof(s_tag==0),.s_eol(s_tag%480==479),.s_last(s_tag==GROUPS-1),.s_tag(s_tag),
        .m_valid(m_valid),.m_ready(m_ready),.m_rgb(m_rgb),.m_y(m_y),.m_keep(m_keep),.m_clipped(m_clipped),.m_protected(m_protected),
        .m_sof(m_sof),.m_eol(m_eol),.m_last(m_last),.m_tag(m_tag),.m_owner(m_owner),
        .m_history_used(m_history_used),.m_history_age(m_history_age),.m_lut_generation(m_lut_generation),
        .busy(busy),.fault(fault),.map_outstanding(map_outstanding));
    preprocess_dehaze_map_qualified #(.FIXED_CONFIG_SESSION_ENABLE(1),.AUTO_FIXED_LUT_ENABLE(1)) map_core(
        .clk(clk),.rst_n(rst_n),.frame_cancel(map_cancel),.history_reset(1'b0),.i_history_eligible(1'b1),
        .main_begin(map_begin),.main_begin_ready(map_begin_ready),.main_release(map_release),.main_fault(fault),
        .main_camera(map_camera),.main_cohort(map_cohort),.main_frame_id(map_capture),
        .main_history_valid(history_valid),.main_a(),.main_age(history_age),.main_lut_generation(history_generation),
        .main_pin_valid(pin_valid),.main_pin_camera(pin_camera),.main_pin_a(pin_a),.main_pin_capture(pin_capture),
        .main_req_valid(map_req_valid),.main_req_ready(map_req_ready),.main_req_tile(map_req_tile),
        .main_reply_valid(map_reply_valid),.main_reply_data(map_reply_data),
        .obs_valid(obs_valid),.obs_ready(obs_ready),.obs_rgb(obs_word[31:8]),.obs_y(obs_word[7:0]),
        .obs_sof(obs_sof),.obs_eol(obs_eol),.obs_last(obs_last),.obs_camera(1'b0),.obs_cohort(cohort),
        .obs_frame_id(obs_capture),.obs_context({128'd0,obs_capture}),
        .obs_status_valid(obs_status_valid),.obs_status_ready(obs_status_ready),.obs_status_ok(1'b1),
        .obs_status_error(8'd0),.obs_status_pixels(16'd57600),.obs_status_delivered(16'd57600),
        .source_valid(source_valid),.source_ready(source_ready),.source_camera(1'b0),.source_ok(1'b1),
        .source_owner_match(),.source_accepted(),.source_decision_valid(),.source_decision_collect(),
        .source_decision_capture(),.source_cancel_done(),
        .source_session(32'h10203040),.source_epoch(32'd1),.source_capture(source_capture),
        .cfg_begin_valid(1'b0),.cfg_begin_ready(),.cfg_generation(32'd0),.cfg_valid(1'b0),.cfg_ready(),
        .cfg_index(9'd0),.cfg_value(11'd0),.cfg_commit_valid(1'b0),.cfg_commit_ready(),.cfg_abort(1'b0),
        .cfg_status_valid(),.cfg_status_ready(1'b1),.cfg_status_ok(),.cfg_status_error(),.cfg_status_generation(),
        .lut_valid(lut_valid),.lut_generation(lut_generation),.map_commit(map_commit),.map_commit_camera(),
        .map_commit_frame_id(commit_capture),.map_commit_context(),.candidate_tile_valid(candidate_valid),
        .candidate_tile_index(candidate_index),.candidate_tile_data(candidate_data),
        .debug_clear_firstfault(1'b0),.candidate_drops(),.qualified_maps(),.control_rejects(),.source_rejects(),.firstfault(),.firstfault_context());
    always @(negedge clk)begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        m_ready=random_state[0]||random_state[3];
        if(m_valid&&m_last&&last_hold>0)begin m_ready=0;last_hold--;end
    end
    always @(posedge clk)begin
        cycle++;
        if(cycle>10000000)$fatal(1,"history long watchdog");
        if(rst_n)begin
            if(current_frame>0&&(fault||!lut_valid||lut_generation!=1||map_core.load_busy))$fatal(1,"fixed ROM readiness/stream fault");
            if(map_begin&&map_begin_ready&&history_valid!==(current_frame>1))$fatal(1,"history admission frame%0d",current_frame);
            if(map_req_valid&&map_req_ready)reads++;
            if(map_release)begin
                if(map_outstanding!=0||m_valid)$fatal(1,"premature pinned-map release");
                releases++;
            end
            if(candidate_valid)begin
                if(candidate_data!==map_words[(current_frame-1)*144+candidate_index])$fatal(1,"independent map mismatch frame%0d tile%0d got%h",current_frame,candidate_index,candidate_data);
                candidates++;
            end
            if(map_commit)begin
                if(commit_capture!=current_frame)$fatal(1,"map SOURCE identity mismatch");
                commits++;
            end
            if(held)begin
                if(!m_valid||output_bundle!==held_bundle)$fatal(1,"stalled output tuple changed");
                held_checks++;
            end
            if(s_valid&&s_ready)total_inputs++;
            if(m_valid&&m_ready)begin
                if(m_tag!=frame_outputs||m_owner!=={32'h10203040,32'(current_frame)}||m_keep!=15||
                   m_sof!=(frame_outputs==0)||m_eol!=(frame_outputs%480==479)||m_last!=(frame_outputs==GROUPS-1)||
                   m_history_used!==(current_frame>1)||m_history_age!=(current_frame>1?1:0)||m_lut_generation!=(current_frame>1?1:0))
                    $fatal(1,"output identity/geometry/history mismatch frame%0d tag%0d",current_frame,m_tag);
                if({m_protected,m_clipped,m_y,m_rgb}!==golden[frame_outputs])
                    $fatal(1,"independent interpolated RGB/Y mismatch frame%0d group%0d got%h expected%h",current_frame,frame_outputs,{m_protected,m_clipped,m_y,m_rgb},golden[frame_outputs]);
                if(m_rgb!==source_words[frame_outputs][95:0])begin changed_groups++;changed_frame++;end
                frame_outputs++;outputs++;
            end
            held=m_valid&&!m_ready;held_bundle=output_bundle;
        end
    end
    task observe(input integer capture);
        begin
            for(integer i=0;i<57600;i++)begin
                @(negedge clk);obs_valid=1;obs_word=observations[i];obs_capture=capture;
                obs_sof=i==0;obs_eol=i%320==319;obs_last=i==57599;
                do @(posedge clk);while(!obs_ready);
            end
            @(negedge clk);obs_valid=0;obs_status_valid=1;
            do @(posedge clk);while(!obs_status_ready);
            @(negedge clk);obs_status_valid=0;source_valid=1;source_capture=capture;
            do @(posedge clk);while(!source_ready);
            @(negedge clk);source_valid=0;
        end
    endtask
    task foreground;
        begin
            for(integer i=0;i<GROUPS;i++)begin
                @(negedge clk);s_valid=1;s_tag=i;
                do @(posedge clk);while(!s_ready);
            end
            @(negedge clk);s_valid=0;
            wait(!busy);@(negedge clk);
        end
    endtask
    initial begin
        cohort={32'h10203040,32'd1,32'd1000,16'd256,13'd1920,13'd1080,3'd1,1'b0,
                1'b1,8'd224,9'd128,8'd8,9'd16,8'd64,8'd48,8'd208,8'd24};
        $readmemh("fixtures/source.hex",source_words);$readmemh("fixtures/maps.hex",map_words);
        repeat(8)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
        for(integer f=1;f<=4;f++)begin
            current_frame=f;frame_outputs=0;changed_frame=0;last_hold=13;
            $readmemh($sformatf("fixtures/expected_%0d.hex",f),golden);
            if(f<4)$readmemh($sformatf("fixtures/observation_%0d.hex",f),observations);
            frame_capture=f;frame_valid=1;
            do @(posedge clk);while(!frame_ready);
            @(negedge clk);frame_valid=0;
            fork
                foreground();
                begin if(f<4)begin repeat(3)@(negedge clk);observe(f);wait(commits==f);end end
            join
            if(frame_outputs!=GROUPS||pin_valid||map_outstanding!=0||last_hold!=0||
               (f==1&&changed_frame!=0)||(f>1&&changed_frame==0))$fatal(1,"incomplete numerical frame%0d",f);
            $display("AUTOF21_HISTORY_FRAME PASS frame=%0d groups=%0d changed=%0d commits=%0d",f,frame_outputs,changed_frame,commits);
        end
        if(commits!=3||candidates!=432||releases!=3||held_checks<52||total_inputs!=4*GROUPS)$fatal(1,"history coverage totals");
        $display("RESULT: PASS AUTO_F21_HISTORY rows=%0d frames=4 groups=%0d maps=3 tiles=432 changed_groups=%0d reads=%0d releases=3 held_checks=%0d algo_writes=0",ROWS,outputs,changed_groups,reads,held_checks);
        $finish;
    end
endmodule
