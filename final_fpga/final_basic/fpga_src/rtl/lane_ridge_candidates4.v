// Frozen C1 extractor. All arithmetic is integer; dx/dy are signed11,
// abs <=1020, strength <=2040, x_native=4*left+2*width. Four left positions
// are evaluated each clock. A 12-sample history and a separate saved EOL
// tail let the last ten left positions drain during the next row's lookahead.
// No blanking or pixel backpressure is required. Only quarter events enter.
module lane_ridge_candidates4(
    input wire clk,rst_n,cancel,start,
    input wire [159:0] start_context,
    input wire event_valid,event_bad,
    input wire [8:0] event_x,event_y,
    input wire [43:0] event_gx,event_gy,
    input wire [31:0] event_center_y,
    input wire [7:0] event_hint,
    input wire hint_valid,hint_error,
    input wire frame_complete,frame_error,
    input wire [159:0] terminal_context,
    output reg record_valid,
    input wire record_ready,
    output wire [176:0] record_data,
    input wire read_enable,
    input wire [8:0] read_index,
    output wire [39:0] read_data,
    output wire read_valid,
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
    // A sample is {hint2,Y8,dy11,dx11}. Only these 32 bits need history.
    reg [31:0] history[0:11],tail[0:11];
    reg tail_pending;
    reg [3:0] tail_step;
    reg [8:0] tail_y;
    wire take=active&&event_valid;
    wire [31:0] input_sample[0:3];
    genvar s;
    generate for(s=0;s<4;s=s+1)begin:g_sample
        assign input_sample[s]={event_hint[s*2+:2],event_center_y[s*8+:8],
            event_gy[s*11+:11],event_gx[s*11+:11]};
    end endgenerate
    reg [31:0] current[0:15];
    integer h;
    always @*begin
        for(h=0;h<12;h=h+1)current[h]=event_x==0?input_sample[0]:history[h];
        for(h=0;h<4;h=h+1)current[h+12]=input_sample[h];
    end
    // Winner payload omits y (common to each row) and the upper reserved bits.
    // Payload26: x10:0, strength21:11, (width-1)24:22, yellow25.
    // Valid is separate bit26. Double bank24 winners use 1296 logical bits.
    function [10:0] abs11;
        input [10:0] v;
        begin abs11=v[10]?(~v+11'd1):v;end
    endfunction
    function better;
        input [26:0] a,b;
        begin better=a[26]&&(!b[26]||a[21:11]>b[21:11]||
            (a[21:11]==b[21:11]&&(a[10:0]<b[10:0]||
            (a[10:0]==b[10:0]&&a[24:22]<b[24:22]))));end
    endfunction
    function separated;
        input [26:0] a,b;
        begin separated=!b[26]||(a[10:0]>=b[10:0]?
            a[10:0]-b[10:0]>=24:b[10:0]-a[10:0]>=24);end
    endfunction
    function [53:0] insert;
        input [53:0] old;
        input [26:0] p;
        reg [26:0] a,b,c;
        begin
            a=old[26:0];b=old[53:27];c=27'd0;
            if(p[26])begin
                if(better(p,a))begin
                    if(separated(a,p))c=a;
                    if(separated(b,p)&&better(b,c))c=b;
                    a=p;b=c;
                end else if(separated(p,a)&&better(p,b))b=p;
            end
            insert={b,a};
        end
    endfunction
    reg [26:0] evaluated[0:1];
    reg [3:0] evaluated_bin[0:1];
    reg [8:0] evaluated_y[0:1];
    reg evaluated_row_end;
    reg [8:0] evaluated_end_y;
    reg [26:0] candidate[0:3];
    reg [8:0] candidate_y[0:3];
    // Adjacent left positions cannot both satisfy the strict-left positive
    // peak test. Four positions therefore contain at most two candidates;
    // mixed EOL478/479 + next-row0/1 also has at most two (479 cannot pair).
    // Remove invalid identities at the existing register boundary, preserving
    // left/lane order even when variable pair width reverses center-x order.
    wire [3:0] candidate_mask={candidate[3][26],candidate[2][26],candidate[1][26],candidate[0][26]};
    wire [1:0] compact_lane[0:1];
    assign compact_lane[0]=candidate_mask[0]?2'd0:candidate_mask[1]?2'd1:candidate_mask[2]?2'd2:2'd3;
    wire [3:0] remaining_mask=candidate_mask&~(4'b0001<<compact_lane[0]);
    assign compact_lane[1]=remaining_mask[0]?2'd0:remaining_mask[1]?2'd1:remaining_mask[2]?2'd2:2'd3;
    wire [1:0] compact_valid={|remaining_mask,|candidate_mask};
    reg [31:0] win[0:12];
    reg signed [10:0] lx,ly,rx,ry,n0,n1;
    reg [10:0] alx,aly,arx,ary,strength;
    reg [7:0] background,center;
    reg [1:0] cls;
    reg positive,negative,pair_ok,valid_left;
    integer lane,d,k,left,offset;
    always @*begin
        lx=0;ly=0;rx=0;ry=0;n0=0;n1=0;alx=0;aly=0;arx=0;ary=0;
        strength=0;background=0;center=0;cls=0;positive=0;negative=0;pair_ok=0;left=0;offset=0;valid_left=0;
        for(k=0;k<13;k=k+1)win[k]=0;
        for(lane=0;lane<4;lane=lane+1)begin
            candidate[lane]=0;candidate_y[lane]=event_y;
            left=$signed({1'b0,event_x})-10+lane;
            valid_left=take&&left>=0;
            if(valid_left)begin
                for(k=0;k<13;k=k+1)win[k]=current[lane+k];
            end else begin
                candidate_y[lane]=tail_y;left=470+tail_step+lane;
                valid_left=active&&tail_pending&&tail_step+lane<10;
                for(k=0;k<13;k=k+1)begin
                    offset=tail_step+lane+k;
                    win[k]=offset<12?tail[offset]:tail[11];
                end
            end
            lx=win[2][10:0];ly=win[2][21:11];alx=abs11(lx);aly=abs11(ly);
            n0=win[1][10:0];n1=win[3][10:0];
            positive=lx>=20&&{2'd0,aly}<={alx,2'd0}&&
                (left==0||lx>n0)&&lx>=n1;
            for(d=1;d<=8;d=d+1)begin
                rx=win[2+d][10:0];ry=win[2+d][21:11];arx=abs11(rx);ary=abs11(ry);
                n0=win[1+d][10:0];n1=win[3+d][10:0];
                negative=rx<=-20&&{2'd0,ary}<={arx,2'd0}&&rx<n0&&
                    (left+d==479||rx<=n1);
                center=win[2+d/2][29:22];
                background=win[0][29:22]>win[4+d][29:22]?win[0][29:22]:win[4+d][29:22];
                cls=win[2+d/2][31]?2'd2:win[2+d/2][30]?2'd1:2'd0;
                pair_ok=valid_left&&left+d<480&&positive&&negative&&
                    (ly==0||ry==0||ly[10]!=ry[10])&&
                    {1'b0,center}>={1'b0,background}+9'd6&&cls!=0;
                strength=(alx<arx?alx:arx)+(aly<ary?aly:ary);
                if(pair_ok&&!candidate[lane][26])begin
                    candidate[lane][26]=1;
                    candidate[lane][25]=cls==2;candidate[lane][24:22]=d-1;
                    candidate[lane][21:11]=strength;candidate[lane][10:0]=left*4+d*2;
                end
            end
            if(candidate_y[lane]<169||candidate_y[lane]>269)candidate[lane]=0;
        end
    end
    // At most two centers differ by26 native pixels: same-row bins are equal
    // or adjacent. Mixed EOL uses old bin11 and new bin0. Thus each bin-parity
    // group targets one row/bin address per clock, with original left order.
    // Two 12-entry FF banks retain all48 winners; only four shared inserts.
    reg [53:0] winners_even[0:11],winners_odd[0:11];
    reg [1:0] row_pending;
    reg [8:0] row_number[0:1];
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
    wire even0=evaluated[0][26]&&!evaluated_bin[0][0];
    wire even1=evaluated[1][26]&&!evaluated_bin[1][0];
    wire odd0=evaluated[0][26]&&evaluated_bin[0][0];
    wire odd1=evaluated[1][26]&&evaluated_bin[1][0];
    wire [3:0] address0=(evaluated_y[0][0]?4'd6:4'd0)+{1'b0,evaluated_bin[0][3:1]};
    wire [3:0] address1=(evaluated_y[1][0]?4'd6:4'd0)+{1'b0,evaluated_bin[1][3:1]};
    wire [3:0] even_address=even0?address0:address1;
    wire [3:0] odd_address=odd0?address0:address1;
    wire [26:0] even_point0={even0,evaluated[0][25:0]};
    wire [26:0] even_point1={even1,evaluated[1][25:0]};
    wire [26:0] odd_point0={odd0,evaluated[0][25:0]};
    wire [26:0] odd_point1={odd1,evaluated[1][25:0]};
    wire [53:0] even_next=insert(insert(winners_even[even_address],even_point0),even_point1);
    wire [53:0] odd_next=insert(insert(winners_odd[odd_address],odd_point0),odd_point1);
    // Sequential row selection scans 24 winners three times with a yellow
    // winner, four otherwise (72/96 clocks), below 120 continuous row events.
    reg selecting,select_bank;
    reg [4:0] scan;
    reg [1:0] pass;
    reg [26:0] best,chosen0,chosen1;
    wire [3:0] scan_address=(select_bank?4'd6:4'd0)+{1'b0,scan[4:2]};
    wire [53:0] scan_pair=scan[1]?winners_odd[scan_address]:winners_even[scan_address];
    wire [26:0] scanned=scan[0]?scan_pair[53:27]:scan_pair[26:0];
    wire eligible=scanned[26]&&separated(scanned,chosen0)&&separated(scanned,chosen1)&&
        (pass!=0||scanned[25]);
    wire [26:0] scan_best=eligible&&better(scanned,best)?scanned:best;
    reg [1:0] emit_left;
    reg [26:0] emit0,emit1,emit2;
    reg [8:0] emit_y;
    reg write_enable;
    reg [36:0] write_data;
    lane_candidate_store storage(.clk(clk),.rst_n(rst_n),.clear(cancel||start),
        .write_enable(write_enable),.write_index(count),.write_data(write_data),
        .read_enable(read_enable),.read_index(read_index),.point_count(count),
        .published(record_valid),.read_data(read_data),.read_valid(read_valid));
    wire [3:0] emit_width={1'b0,emit0[24:22]}+4'd1;
    reg [26:0] sort_a,sort_b,sort_c,sort_t;
    integer z;
    always @(posedge clk)begin
        if(!rst_n)begin
            active<=0;record_valid<=0;terminal_valid<=0;terminal_error<=0;count<=0;status<=0;
            frames_started<=0;frames_finished<=0;frames_failed<=0;record_drop_count<=0;
            tail_pending<=0;row_pending<=0;selecting<=0;emit_left<=0;write_enable<=0;
            for(z=0;z<2;z=z+1)evaluated[z]<=0;
            evaluated_row_end<=0;
        end else begin
            terminal_valid<=0;write_enable<=0;
            if(record_valid&&record_ready)record_valid<=0;
            if(cancel)begin
                active<=0;record_valid<=0;tail_pending<=0;selecting<=0;row_pending<=0;emit_left<=0;
                evaluated_row_end<=0;for(z=0;z<2;z=z+1)evaluated[z]<=0;
            end else if(start)begin
                if(record_valid&&!record_ready)record_drop_count<=record_drop_count+1'b1;
                else begin
                    active<=1;frame_context<=start_context;count<=0;source_fault<=0;local_fault<=0;
                    finish_seen<=0;eof_seen<=0;expected_x<=0;expected_y<=0;tail_pending<=0;
                    selecting<=0;row_pending<=0;emit_left<=0;evaluated_row_end<=0;
                    frames_started<=frames_started+1'b1;
                    for(z=0;z<12;z=z+1)begin winners_even[z]<=0;winners_odd[z]<=0;end
                    for(z=0;z<2;z=z+1)evaluated[z]<=0;
                end
            end else if(active)begin
                for(z=0;z<2;z=z+1)begin
                    evaluated[z]<=compact_valid[z]?candidate[compact_lane[z]]:27'd0;
                    evaluated_y[z]<=compact_valid[z]?candidate_y[compact_lane[z]]:9'd0;
                    evaluated_bin[z]<=compact_valid[z]?locate_bin(candidate[compact_lane[z]][10:0]):4'd0;
                end
                evaluated_row_end<=tail_pending&&tail_step==8;
                evaluated_end_y<=tail_y;
                if(tail_pending)begin
                    if(tail_step==8)tail_pending<=0;else tail_step<=tail_step+4;
                end
                if(take)begin
                    if(event_bad||!hint_valid||hint_error||eof_seen||event_x!=expected_x||event_y!=expected_y)
                        local_fault<=1;
                    for(z=0;z<12;z=z+1)history[z]<=current[z+4];
                    if(event_x==476)begin
                        expected_x<=0;expected_y<=expected_y+1'b1;tail_pending<=1;tail_step<=0;tail_y<=event_y;
                        for(z=0;z<12;z=z+1)tail[z]<=current[z+4];
                        if(event_y==269)eof_seen<=1;
                    end else expected_x<=expected_x+4;
                end
                if(even0||even1)winners_even[even_address]<=even_next;
                if(odd0||odd1)winners_odd[odd_address]<=odd_next;
                if(evaluated_row_end&&evaluated_end_y>=169)begin
                    if(row_pending[evaluated_end_y[0]])local_fault<=1;
                    row_pending[evaluated_end_y[0]]<=1;row_number[evaluated_end_y[0]]<=evaluated_end_y;
                end
                if(!selecting&&row_pending!=0&&emit_left==0)begin
                    selecting<=1;select_bank<=row_pending[0]?0:1;scan<=0;pass<=0;
                    best<=0;chosen0<=0;chosen1<=0;
                end else if(selecting)begin
                    if(scan==23)begin
                        scan<=0;best<=0;
                        if(pass==0)begin chosen0<=scan_best;pass<=scan_best[26]?2:1;end
                        else if(pass==1)begin chosen0<=scan_best;pass<=2;end
                        else if(pass==2)begin chosen1<=scan_best;pass<=3;end
                        else begin
                            // Sort three selected points by x, invalid last.
                            sort_a=chosen0;sort_b=chosen1;sort_c=scan_best;
                            if(!sort_a[26]||(sort_b[26]&&sort_b[10:0]<sort_a[10:0]))begin sort_t=sort_a;sort_a=sort_b;sort_b=sort_t;end
                            if(!sort_b[26]||(sort_c[26]&&sort_c[10:0]<sort_b[10:0]))begin sort_t=sort_b;sort_b=sort_c;sort_c=sort_t;end
                            if(!sort_a[26]||(sort_b[26]&&sort_b[10:0]<sort_a[10:0]))begin sort_t=sort_a;sort_a=sort_b;sort_b=sort_t;end
                            emit0<=sort_a;emit1<=sort_b;emit2<=sort_c;emit_y<=row_number[select_bank];emit_left<=3;
                            selecting<=0;row_pending[select_bank]<=0;
                            for(z=0;z<6;z=z+1)begin
                                winners_even[(select_bank?6:0)+z]<=0;
                                winners_odd[(select_bank?6:0)+z]<=0;
                            end
                        end
                    end else begin scan<=scan+1'b1;best<=scan_best;end
                end
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
                if(frame_error)begin source_fault<=1;finish_seen<=1;end
                if(frame_complete)begin finish_seen<=1;if(terminal_context!=frame_context)local_fault<=1;end
                if(finish_seen&&(!tail_pending&&!evaluated_row_end&&!selecting&&row_pending==0&&emit_left==0&&!write_enable))begin
                    active<=0;record_valid<=1;terminal_valid<=1;terminal_error<=source_fault;
                    if(source_fault||local_fault||!eof_seen)begin
                        count<=0;status<=source_fault?8'h81:8'h80;frames_failed<=frames_failed+1'b1;
                    end else begin status<=count==0?8'd1:8'd0;frames_finished<=frames_finished+1'b1;end
                end
            end
        end
    end
endmodule
