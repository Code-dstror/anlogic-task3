// II1 C1 worker. Parallel width checks register only compact pair results;
// shortest-width selection and bin decoding use the following clock.
// The next row's first ten accepted samples replace already-consumed tail
// positions in the same shift history. Input service remains one sample/clock.
module lane_ridge_candidates1_lutram(
    input wire clk,rst_n,cancel,start,
    input wire [159:0] start_context,
    input wire event_valid,event_bad,
    input wire [8:0] event_x,event_y,
    input wire [31:0] event_sample,
    input wire local_error,frame_complete,frame_error,
    input wire [159:0] terminal_context,
    output reg record_valid,input wire record_ready,
    output wire [176:0] record_data,
    input wire read_enable,input wire [8:0] read_index,
    output wire [39:0] read_data,output wire read_valid,
    output reg [31:0] frames_started,frames_finished,frames_failed,record_drop_count,
    output reg terminal_valid,terminal_error,
    output wire [159:0] terminal_identity
);
    reg active,source_fault,local_fault,finish_seen,eof_seen;
    reg [159:0] frame_context;
    reg [8:0] count,expected_x,expected_y;
    reg [7:0] status;
    assign record_data={frame_context,count,status};
    assign terminal_identity=frame_context;
    reg [34:0] history[0:11];
    reg [7:0] first_y,last_y;
    reg tail_pending;
    reg [3:0] tail_step;
    reg [8:0] tail_y;
    wire take=active&&event_valid;
    // A complete last row flushes itself. Otherwise idle input cycles may
    // defer the tail until the next prefix arrives, without backpressuring it.
    wire tail_fire=tail_pending&&(take||eof_seen||finish_seen||frame_complete||frame_error);
    // Winner payload omits y (common to each row) and the upper reserved bits.
    // Payload26: x10:0, strength21:11, (width-1)24:22, yellow25.
    // Valid is separate bit26. Double bank24 winners use 1296 logical bits.
    function [10:0] abs11;
        input [10:0] v;
        begin abs11=v[10]?(~v+11'd1):v;end
    endfunction
    // Each incoming quarter pixel supplies its gradient magnitude once. The
    // next accepted pixel completes its predecessor's strict/weak peak tests.
    // history[11] is that predecessor; all width probes use positions <=10.
    wire signed [10:0] gx=event_sample[10:0],gy=event_sample[21:11];
    wire [10:0] abs_x=abs11(gx),abs_y=abs11(gy);
    wire oriented={2'b00,abs_y}<={abs_x,2'b00};
    reg signed [10:0] prev_gx,prev2_gx;
    reg prev_oriented;
    always @(posedge clk)if(take)begin
        prev2_gx<=prev_gx;prev_gx<=gx;prev_oriented<=oriented;
    end
    wire pos_prev=prev_oriented && prev_gx>=20 &&
        (event_x==1 || prev_gx>prev2_gx) && prev_gx>=gx;
    wire neg_prev=prev_oriented && prev_gx<=-20 && prev_gx<prev2_gx && prev_gx<=gx;
    // The last column waives the right neighbour for a negative peak. Its
    // flags must be final when the tail is copied on this same edge.
    wire neg_last=event_x==479 && oriented && gx<=-20 && gx<prev_gx;
    wire [34:0] sample={event_sample[31:22],gy[10],neg_last,1'b0,abs_y,abs_x};
    reg [34:0] current[0:12];
    integer h;
    always @*begin
        for(h=0;h<12;h=h+1)current[h]=(event_x==0&&!tail_pending) ? sample : history[h];
        if(event_x!=0)current[11][23:22]={neg_prev,pos_prev};
        // Only the two left-background positions can still hold the prior
        // row when the first next-row ridge (x=0 at event_x=10) is evaluated.
        if(!tail_pending && event_x==10)begin
            current[0][32:25]=first_y;current[1][32:25]=first_y;
        end
        if(!tail_pending && event_x==11)current[0][32:25]=first_y;
        current[12]=sample;
    end
    function better;
        input [26:0] a,b;
        begin better=a[26]&&(!b[26]||a[21:11]>b[21:11]||
            (a[21:11]==b[21:11]&&(a[10:0]<b[10:0]||
            (a[10:0]==b[10:0]&&a[24:22]<b[24:22]))));end
    endfunction
    function separated;
        input [26:0] a,b;
        reg signed [11:0] delta;
        begin
            delta=$signed({1'b0,a[10:0]})-$signed({1'b0,b[10:0]});
            separated=!b[26]||delta>=12'sd24||delta<=-12'sd24;
        end
    endfunction
    function [53:0] insert;
        input [53:0] old;
        input [26:0] p;
        reg [26:0] a,b,c;
        begin
            a=old[26:0];b=old[53:27];c=27'd0;
            if(p[26])begin
                if(better(p,a))begin
                    // The pair invariant is a >= b in the better ordering.
                    // If both survive spacing, a wins without another compare
                    // through the preceding spacing-controlled payload mux.
                    if(separated(a,p))c=a;
                    else if(separated(b,p))c=b;
                    a=p;b=c;
                end else if(separated(p,a)&&better(p,b))b=p;
            end
            insert={b,a};
        end
    endfunction
    reg [26:0] evaluated,candidate;
    reg [3:0] evaluated_bin;
    reg [8:0] evaluated_y,candidate_y;
    reg evaluated_row_end;
    reg [8:0] evaluated_end_y;
    reg [34:0] win[0:12];
    reg [10:0] aly,ary;
    reg [7:0] background,center,right_background;
    reg tail_window;
    reg [1:0] cls;
    reg positive,negative,pair_ok,valid_left;
    reg [7:0] pair_ok_next,pair_yellow_next;
    reg [8:0] pair_left_next,pair_y_next;
    reg [7:0] pair_ok_reg,pair_yellow_reg;
    reg [8:0] pair_left_reg,pair_y_reg,pair_end_y_reg;
    reg pair_pending,pair_row_end_reg;
    integer d,k,left;
    always @*begin
        aly=0;ary=0;right_background=0;tail_window=0;
        background=0;center=0;cls=0;positive=0;negative=0;pair_ok=0;
        left=$signed({1'b0,event_x})-10;
        valid_left=take&&left>=0;
        pair_ok_next=0;pair_yellow_next=0;pair_y_next=event_y;
        if(valid_left)begin
            for(k=0;k<13;k=k+1)win[k]=current[k];
        end else begin
            tail_window=1;pair_y_next=tail_y;left=470+tail_step;
            valid_left=active&&tail_fire;
            for(k=0;k<12;k=k+1)win[k]=history[k];
            win[12]=0;
        end
        pair_left_next=left[8:0];
        aly=win[2][21:11];positive=win[2][22];
        for(d=1;d<=8;d=d+1)begin
            ary=win[2+d][21:11];negative=win[2+d][23];
            center=win[2+d/2][32:25];
            // A valid pair has left+d<=479, so its gradients/center still
            // precede the new prefix. Only its right background can exceed479.
            right_background=tail_window && tail_step+d>=8 ? last_y : win[4+d][32:25];
            background=win[0][32:25]>right_background?win[0][32:25]:right_background;
            cls=win[2+d/2][34]?2'd2:win[2+d/2][33]?2'd1:2'd0;
            pair_ok=valid_left&&left+d<480&&positive&&negative&&
                (aly==0||ary==0||win[2][24]!=win[2+d][24])&&
                {1'b0,center}>={1'b0,background}+9'd6&&cls!=0;
            pair_ok_next[d-1]=pair_ok&&pair_y_next>=169&&pair_y_next<=269;
            pair_yellow_next[d-1]=cls==2;
        end
    end
    // The selected pair borrows the just-shifted magnitude history. Every
    // qualified pair advances history exactly once, even during tail service.
    // Capture immediately on the following edge; no input enable gates this
    // stage, because the preceding pair may be pending during an input gap.
    reg [21:0] right_gradient;
    reg [21:0] selected_left_gradient,selected_right_gradient;
    reg [14:0] selected_head;
    reg selected_valid,selected_row_end;
    reg [8:0] selected_y,selected_end_y;
    wire [10:0] selected_x_min=selected_left_gradient[10:0]<selected_right_gradient[10:0]?
        selected_left_gradient[10:0]:selected_right_gradient[10:0];
    wire [10:0] selected_y_min=selected_left_gradient[21:11]<selected_right_gradient[21:11]?
        selected_left_gradient[21:11]:selected_right_gradient[21:11];
    // Keep the original eleven-bit truncation, including abs11(-1024).
    wire [10:0] selected_strength=selected_x_min+selected_y_min;
    integer width_pick;
    always @*begin
        candidate=0;candidate_y=pair_y_reg;right_gradient=0;
        for(width_pick=0;width_pick<8;width_pick=width_pick+1)begin
            if(pair_ok_reg[width_pick]&&!candidate[26])begin
                candidate[26]=1;candidate[25]=pair_yellow_reg[width_pick];
                candidate[24:22]=width_pick;
                right_gradient=history[2+width_pick][21:0];
                candidate[10:0]={pair_left_reg,2'b00}+(width_pick+1)*2;
            end
        end
    end
    // Replicated asynchronous LUTRAM reads retain the original FF update
    // and selector cycles. One candidate uses one shared unchanged insert.
    reg [1:0] row_pending;
    reg [8:0] row_number[0:1];
    reg selecting,select_bank;
    reg [4:0] scan;
    reg [1:0] pass;
    reg [1:0] scan_phase;
    function [3:0] locate_bin;
        input [10:0] x;
        begin
            if(x<960)begin
                if(x<480)locate_bin=x<160?0:x<320?1:2;
                else locate_bin=x<640?3:x<800?4:5;
            end else begin
                if(x<1440)locate_bin=x<1120?6:x<1280?7:8;
                else locate_bin=x<1600?9:x<1760?10:11;
            end
        end
    endfunction
    wire core_run=rst_n&&!cancel&&!start&&active;
    wire clear_all=cancel||(start&&(!record_valid||record_ready));
    wire finish_selection=core_run&&selecting&&scan_phase==2&&scan==23&&pass==3;
    wire [1:0] clear_row=finish_selection?(select_bank?2'b10:2'b01):2'b00;
    wire [53:0] rmw_pair[0:1],selector_pair[0:1];
    wire [53:0] old_pair=evaluated_y[0]?rmw_pair[1]:rmw_pair[0];
    // Read once, then insert/write on the next clock. Only the immediately
    // preceding write can be absent from the sampled asynchronous RAM word.
    // Forward that registered result for A/A/A and A/B/A at one sample/clock;
    // the feedback contains one insert, never a cascade of pending inserts.
    reg [53:0] rmw_old,previous_pair;
    reg [26:0] rmw_candidate;
    reg [3:0] rmw_bin,previous_bin;
    reg rmw_bank,previous_bank,previous_valid,rmw_row_end;
    reg [8:0] rmw_end_y;
    wire forward_previous=previous_valid&&previous_bin==rmw_bin&&previous_bank==rmw_bank;
    wire [53:0] update_pair=insert(forward_previous?previous_pair:rmw_old,rmw_candidate);
    genvar winner_bank;
    generate for(winner_bank=0;winner_bank<2;winner_bank=winner_bank+1)begin:g_winner_bank
        lane_winner_pair_lutram bank(
            .clk(clk),.rst_n(rst_n),.clear_all(clear_all),.clear_row(clear_row[winner_bank]),
            .write_valid(core_run&&rmw_candidate[26]&&rmw_bank==winner_bank),
            .write_address(rmw_bin),.write_pair(update_pair),
            .rmw_address(evaluated_bin),.selector_address(scan[4:1]),
            .rmw_pair(rmw_pair[winner_bank]),.selector_pair(selector_pair[winner_bank]));
    end endgenerate
    // READ / QUALIFY / REDUCE separate RAM, spacing and rank decisions.
    // Four complete passes cost 288 clocks; sort+emit stay below the 480
    // clocks between serial row ends, including continuous row overlap.
    reg [26:0] best;
    // Row choice and sorting/emission occupy disjoint phases. Reuse these
    // two payload registers instead of copying chosen0/1 into emit0/1.
    reg [26:0] emit0,emit1,emit2;
    wire [26:0] chosen0=emit0,chosen1=emit1;
    wire [53:0] scan_pair=select_bank?selector_pair[1]:selector_pair[0];
    wire [26:0] scanned=scan[0]?scan_pair[53:27]:scan_pair[26:0];
    reg [26:0] scan_sample;
    reg scan_eligible;
    wire [26:0] scan_best=scan_eligible&&better(scan_sample,best)?scan_sample:best;
    reg [1:0] emit_left;
    reg [8:0] emit_y;
    reg write_enable;
    reg [36:0] write_data;
    lane_candidate_store storage(.clk(clk),.rst_n(rst_n),.clear(cancel||(start&&(!record_valid||record_ready))),
        .write_enable(write_enable),.write_index(count),.write_data(write_data),
        .read_enable(read_enable),.read_index(read_index),.point_count(count),
        .published(record_valid),.read_data(read_data),.read_valid(read_valid));
    wire [3:0] emit_width={1'b0,emit0[24:22]}+4'd1;
    reg [2:0] sort_step;
    integer z;
    always @(posedge clk)begin
        if(!rst_n)begin
            active<=0;record_valid<=0;terminal_valid<=0;terminal_error<=0;count<=0;status<=0;
            frames_started<=0;frames_finished<=0;frames_failed<=0;record_drop_count<=0;
            tail_pending<=0;row_pending<=0;selecting<=0;emit_left<=0;write_enable<=0;
            evaluated<=0;pair_ok_reg<=0;pair_pending<=0;pair_row_end_reg<=0;
            evaluated_row_end<=0;selected_valid<=0;selected_row_end<=0;
            rmw_candidate<=0;rmw_row_end<=0;previous_valid<=0;sort_step<=0;
        end else begin
            terminal_valid<=0;write_enable<=0;
            if(record_valid&&record_ready)record_valid<=0;
            if(cancel)begin
                active<=0;record_valid<=0;tail_pending<=0;selecting<=0;row_pending<=0;emit_left<=0;
                evaluated_row_end<=0;selected_valid<=0;selected_row_end<=0;evaluated<=0;pair_ok_reg<=0;pair_pending<=0;pair_row_end_reg<=0;
                rmw_candidate<=0;rmw_row_end<=0;previous_valid<=0;sort_step<=0;
            end else if(start)begin
                if(record_valid&&!record_ready)record_drop_count<=record_drop_count+1'b1;
                else begin
                    active<=1;frame_context<=start_context;count<=0;source_fault<=0;local_fault<=0;
                    finish_seen<=0;eof_seen<=0;expected_x<=0;expected_y<=0;tail_pending<=0;
                    selecting<=0;row_pending<=0;emit_left<=0;evaluated_row_end<=0;selected_valid<=0;selected_row_end<=0;
                    frames_started<=frames_started+1'b1;
                    evaluated<=0;pair_ok_reg<=0;pair_pending<=0;pair_row_end_reg<=0;
                    rmw_candidate<=0;rmw_row_end<=0;previous_valid<=0;sort_step<=0;
                end
            end else if(active)begin
                pair_ok_reg<=pair_ok_next;pair_yellow_reg<=pair_yellow_next;
                pair_left_reg<=pair_left_next;pair_y_reg<=pair_y_next;
                pair_pending<=take||tail_fire;
                pair_row_end_reg<=tail_fire&&tail_step==9;pair_end_y_reg<=tail_y;
                selected_valid<=candidate[26];
                selected_head<={candidate[25:22],candidate[10:0]};
                selected_left_gradient<=history[1][21:0];selected_right_gradient<=right_gradient;
                selected_y<=candidate_y;selected_row_end<=pair_row_end_reg;selected_end_y<=pair_end_y_reg;
                evaluated<={selected_valid,selected_head[14:11],selected_strength,selected_head[10:0]};
                evaluated_y<=selected_y;evaluated_bin<=locate_bin(selected_head[10:0]);
                evaluated_row_end<=selected_row_end;evaluated_end_y<=selected_end_y;
                rmw_old<=old_pair;rmw_candidate<=evaluated;
                rmw_bin<=evaluated_bin;rmw_bank<=evaluated_y[0];
                rmw_row_end<=evaluated_row_end;rmw_end_y<=evaluated_end_y;
                previous_valid<=rmw_candidate[26]&&!clear_row[rmw_bank];
                if(rmw_candidate[26])begin
                    previous_pair<=update_pair;previous_bin<=rmw_bin;previous_bank<=rmw_bank;
                end
                if(tail_fire)begin
                    if(!take)begin
                        for(z=0;z<11;z=z+1)history[z]<=history[z+1];
                        history[11]<=0;
                    end
                    if(tail_step==9)tail_pending<=0;else tail_step<=tail_step+1'b1;
                end
                if(take)begin
                    if(event_bad||eof_seen||event_x!=expected_x||event_y!=expected_y)
                        local_fault<=1;
                    for(z=0;z<12;z=z+1)history[z]<=current[z+1];
                    if(event_x==0)first_y<=event_sample[29:22];
                    if(event_x==479)begin
                        expected_x<=0;expected_y<=expected_y+1'b1;tail_pending<=1;tail_step<=0;tail_y<=event_y;
                        last_y<=event_sample[29:22];
                        if(event_y==269)eof_seen<=1;
                    end else expected_x<=expected_x+1'b1;
                end
                if(rmw_row_end&&rmw_end_y>=169)begin
                    if(row_pending[rmw_end_y[0]])local_fault<=1;
                    row_pending[rmw_end_y[0]]<=1;row_number[rmw_end_y[0]]<=rmw_end_y;
                end
                if(!selecting&&row_pending!=0&&emit_left==0&&sort_step==0)begin
                    selecting<=1;select_bank<=row_pending[0]?0:1;scan<=0;pass<=0;
                    best<=0;emit0<=0;emit1<=0;scan_phase<=0;
                end else if(selecting)begin
                    if(scan_phase==0)begin
                        scan_sample<=scanned;scan_phase<=1;
                    end else if(scan_phase==1)begin
                        scan_eligible<=scan_sample[26]&&separated(scan_sample,chosen0)&&
                            separated(scan_sample,chosen1)&&(pass!=0||scan_sample[25]);
                        scan_phase<=2;
                    end else begin
                      scan_phase<=0;
                      if(scan==23)begin
                        scan<=0;best<=0;
                        if(pass==0)begin emit0<=scan_best;pass<=scan_best[26]?2:1;end
                        else if(pass==1)begin emit0<=scan_best;pass<=2;end
                        else if(pass==2)begin emit1<=scan_best;pass<=3;end
                        else begin
                            emit2<=scan_best;
                            emit_y<=row_number[select_bank];sort_step<=1;
                            selecting<=0;row_pending[select_bank]<=0;
                        end
                      end else begin scan<=scan+1'b1;best<=scan_best;end
                    end
                end
                // Reuse the three emit registers for one compare/swap/clock.
                // No RAM/spacing/rank decision can reach the sorting network.
                if(sort_step==1||sort_step==3)begin
                    if(!emit0[26]||(emit1[26]&&emit1[10:0]<emit0[10:0]))begin
                        emit0<=emit1;emit1<=emit0;
                    end
                    sort_step<=sort_step+1'b1;
                end else if(sort_step==2)begin
                    if(!emit1[26]||(emit2[26]&&emit2[10:0]<emit1[10:0]))begin
                        emit1<=emit2;emit2<=emit1;
                    end
                    sort_step<=3;
                end else if(sort_step==4)begin sort_step<=0;emit_left<=3;end
                if(emit_left!=0)begin
                    if(emit0[26])begin
                        if(count<303)begin
                            write_enable<=1;write_data<={emit0[25]?2'd2:2'd1,emit_width,emit0[21:11],emit_y,emit0[10:0]};
                        end else local_fault<=1;
                    end
                    emit0<=emit1;emit1<=emit2;emit2<=0;emit_left<=emit_left-1'b1;
                end
                // RAM sees the previous registered write; advance its address
                // here so each accepted write uses the current count.
                if(write_enable)count<=count+1'b1;
                if(local_error)local_fault<=1;
                if(frame_error)begin source_fault<=1;finish_seen<=1;end
                if(frame_complete)begin finish_seen<=1;if(terminal_context!=frame_context)local_fault<=1;end
                if(finish_seen&&(!pair_pending&&!pair_row_end_reg&&!selected_valid&&!selected_row_end&&!tail_pending&&!evaluated_row_end&&!evaluated[26]&&
                    !rmw_row_end&&!rmw_candidate[26]&&!selecting&&row_pending==0&&sort_step==0&&emit_left==0&&!write_enable))begin
                    active<=0;record_valid<=1;terminal_valid<=1;terminal_error<=source_fault||frame_error;
                    if(source_fault||frame_error||local_fault||local_error||!eof_seen)begin
                        count<=0;status<=(source_fault||frame_error)?8'h81:8'h80;frames_failed<=frames_failed+1'b1;
                    end else begin status<=count==0?8'd1:8'd0;frames_finished<=frames_finished+1'b1;end
                end
            end
        end
    end
endmodule
