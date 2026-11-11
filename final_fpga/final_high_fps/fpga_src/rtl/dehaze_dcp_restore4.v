`timescale 1ns/1ps
// Previous qualified frame, independently per camera. R,G,B are bytes 2,1,0.
// The emitter and estimator consume the same accepted four-pixel groups.
module dehaze_dcp_restore4 #(
    parameter integer WIDTH=1920,HEIGHT=1080,
    parameter integer EXTERNAL_DARK_ENABLE=0
)(
    input wire clk,rst_n,clear,i_history_reset,
    input wire i_enable,i_camera,
    input wire [31:0] i_session,i_epoch,i_sequence,
    input wire s_valid,s_sof,s_eol,output wire s_ready,
    input wire [95:0] s_rgb,input wire [31:0] s_luma,
    input wire [15:0] s_dark_statistics,
    input wire i_terminal_valid,i_terminal_ok,i_terminal_camera,
    input wire [31:0] i_terminal_session,i_terminal_epoch,i_terminal_sequence,
    output wire m_valid,m_sof,m_eol,input wire m_ready,
    output wire [95:0] m_rgb,output wire [31:0] m_luma,
    output reg o_history_used,output wire o_pending,o_pixel_pending
);
    localparam integer TILE_X=WIDTH/16, TILE_Y=HEIGHT/4;
    localparam integer STEP_X=TILE_X/8, STEP_Y=TILE_Y/8;
    localparam [1:0] IDLE=0,CAPTURE=1,BUILD=2,WAIT_SOURCE=3;
    reg [1:0] state,tile_x,tile_y;
    localparam integer LOCAL_X_BITS=$clog2(TILE_X),LOCAL_Y_BITS=$clog2(TILE_Y);
    localparam integer PHASE_X_BITS=$clog2(STEP_X),PHASE_Y_BITS=$clog2(STEP_Y);
    reg [LOCAL_X_BITS-1:0] local_x;
    reg [LOCAL_Y_BITS-1:0] local_y;
    reg [PHASE_X_BITS-1:0] phase_x;
    reg [PHASE_Y_BITS-1:0] phase_y;
    reg [3:0] patch_x,patch_y;
    reg camera;
    reg [31:0] session,epoch,seq;
    reg terminal_seen,terminal_good,raster_good;
    reg [3:0] build_tile;
    reg [2:0] clear_tiles;
    reg [7:0] bright_samples;
    reg [6:0] chromatic_samples;
    reg [4:0] highlight_samples;
    reg [7:0] best_dark,airlight,group_min;
    reg [7:0] rows_min[0:31];
    reg [13:0] tile_sum[0:3];
    reg [7:0] tile_mean[0:15];
    // Build a complete inactive map for this eye before publishing its page.
    // A failed source can leave arbitrary data in the unpublished map.
    reg [1:0] active_page;
    // Store the four neighbours of a grid cell in one synchronous read.
    // The inactive per-eye page receives a complete 3x3 set of blocks.
    reg [35:0] gain_blocks[0:63];
    reg [44:0] prior_gains;
    reg [7:0] air_history[0:1];
    reg [31:0] hist_session[0:1],hist_epoch[0:1],hist_seq[0:1];
    reg [1:0] history_valid;

    reg [6:0] vp,sp,ep;
    // Cancellation closes the public boundary immediately. Register only the
    // pipeline flush so the upstream fault tree does not drive inferred DSP
    // reset pins. One closed cycle completes the flush before a new owner.
    reg clear_pending;
    wire pixel_discard=clear||clear_pending;
    wire advance=!vp[6]||m_ready;
    assign o_pixel_pending=|vp;
    assign o_pending=o_pixel_pending||state!=IDLE;
    assign s_ready=rst_n&&!pixel_discard&&advance&&(state==IDLE||state==CAPTURE);
    wire fire=s_valid&&s_ready;
    wire fresh=s_sof;
    wire [1:0] tx=fresh?2'd0:tile_x,ty=fresh?2'd0:tile_y;
    wire [LOCAL_X_BITS-1:0] lx=fresh?0:local_x;
    wire [LOCAL_Y_BITS-1:0] ly=fresh?0:local_y;
    wire [PHASE_X_BITS-1:0] px=fresh?0:phase_x;
    wire [PHASE_Y_BITS-1:0] py=fresh?0:phase_y;
    wire [3:0] bx=fresh?4'd0:patch_x,by=fresh?4'd0:patch_y;
    wire x_end=lx==TILE_X-1,y_end=ly==TILE_Y-1;
    wire end_line=x_end&&tx==3,end_frame=end_line&&y_end&&ty==3;
    wire eye=fresh?i_camera:camera;
    wire [31:0] delta_seq=i_sequence-hist_seq[i_camera];
    wire eligible=i_enable&&!i_history_reset&&history_valid[i_camera]&&
        hist_session[i_camera]==i_session&&hist_epoch[i_camera]==i_epoch&&delta_seq!=0&&delta_seq<=32'd4;
    wire use_gain=fresh?eligible:o_history_used;
    wire matches_running=i_terminal_camera==camera&&i_terminal_session==session&&
        i_terminal_epoch==epoch&&i_terminal_sequence==seq;
    wire matches_start=i_terminal_camera==i_camera&&i_terminal_session==i_session&&
        i_terminal_epoch==i_epoch&&i_terminal_sequence==i_sequence;
    wire terminal=i_terminal_valid&&(fresh&&fire?matches_start:matches_running);
    wire accepted_source=(terminal_seen||terminal)&&(terminal_seen?terminal_good:1'b1)&&(!terminal||i_terminal_ok);
    function [7:0] lesser;
        input [7:0] a,b;
        begin lesser=a<b?a:b;end
    endfunction
    genvar p;
    wire [7:0] dark4,dark_last;
    generate if(EXTERNAL_DARK_ENABLE)begin:g_queued_dark
        // The existing gray FIFO owns these minima with the same RGB/Y word.
        assign dark4=s_dark_statistics[7:0];
        assign dark_last=s_dark_statistics[15:8];
    end else begin:g_internal_dark
        wire [7:0] dark_lane[0:3];
        for(p=0;p<4;p=p+1)begin:g_min
            assign dark_lane[p]=lesser(s_rgb[p*24+:8],
                lesser(s_rgb[p*24+8+:8],s_rgb[p*24+16+:8]));
        end
        assign dark4=lesser(lesser(dark_lane[0],dark_lane[1]),lesser(dark_lane[2],dark_lane[3]));
        assign dark_last=dark_lane[3];
    end endgenerate
    wire [4:0] col={tx,bx[2:0]};
    // One comparator handles both halves of the sampled eight-pixel patch.
    // The first group folds in earlier rows. The second folds in that result.
    wire [7:0] prior_min=px==0 ? rows_min[col] : group_min;
    wire [7:0] dark_patch=lesser(prior_min,dark4);
    // One receipt per completed dark-channel patch. The independent
    // accumulation stage shortens RGB -> clear-tile count and airlight paths.
    // The last patch of a parametrized raster may coincide with its last beat.
    wire complete_patch=fire && (fresh ? i_enable : state==CAPTURE) &&
        bx<8 && by<8 && px==1 && py==3;
    reg patch_pending,first_in_tile,last_in_tile;
    reg [3:0] patch_tile;
    reg [7:0] patch_dark_q,patch_air_q;
    reg patch_bright_q,patch_colored_q,patch_highlight_q;
    wire [13:0] patch_sum=(first_in_tile?14'd0:tile_sum[patch_tile[1:0]])+patch_dark_q;
    wire [7:0] candidate_air=s_luma[31:24]<192?8'd192:
        s_luma[31:24]>=248?8'd248:{s_luma[31:27],3'b000};
    // The correction ROM samples eight atmospheric light levels (192..248)
    // and 32 dark-channel levels. Values use Q7; t is bounded below by 0.5.
    function [8:0] optical_gain;
        input [7:0] lookup;
        begin
            case(lookup)
                8'd0: optical_gain=9'd128;
                8'd1: optical_gain=9'd128;
                8'd2: optical_gain=9'd128;
                8'd3: optical_gain=9'd130;
                8'd4: optical_gain=9'd134;
                8'd5: optical_gain=9'd139;
                8'd6: optical_gain=9'd144;
                8'd7: optical_gain=9'd149;
                8'd8: optical_gain=9'd155;
                8'd9: optical_gain=9'd161;
                8'd10: optical_gain=9'd167;
                8'd11: optical_gain=9'd174;
                8'd12: optical_gain=9'd182;
                8'd13: optical_gain=9'd191;
                8'd14: optical_gain=9'd200;
                8'd15: optical_gain=9'd210;
                8'd16: optical_gain=9'd221;
                8'd17: optical_gain=9'd234;
                8'd18: optical_gain=9'd248;
                8'd19: optical_gain=9'd256;
                8'd20: optical_gain=9'd256;
                8'd21: optical_gain=9'd256;
                8'd22: optical_gain=9'd256;
                8'd23: optical_gain=9'd256;
                8'd24: optical_gain=9'd256;
                8'd25: optical_gain=9'd256;
                8'd26: optical_gain=9'd256;
                8'd27: optical_gain=9'd256;
                8'd28: optical_gain=9'd256;
                8'd29: optical_gain=9'd256;
                8'd30: optical_gain=9'd256;
                8'd31: optical_gain=9'd256;
                8'd32: optical_gain=9'd128;
                8'd33: optical_gain=9'd128;
                8'd34: optical_gain=9'd128;
                8'd35: optical_gain=9'd130;
                8'd36: optical_gain=9'd134;
                8'd37: optical_gain=9'd138;
                8'd38: optical_gain=9'd143;
                8'd39: optical_gain=9'd148;
                8'd40: optical_gain=9'd153;
                8'd41: optical_gain=9'd159;
                8'd42: optical_gain=9'd165;
                8'd43: optical_gain=9'd172;
                8'd44: optical_gain=9'd179;
                8'd45: optical_gain=9'd187;
                8'd46: optical_gain=9'd195;
                8'd47: optical_gain=9'd205;
                8'd48: optical_gain=9'd215;
                8'd49: optical_gain=9'd227;
                8'd50: optical_gain=9'd239;
                8'd51: optical_gain=9'd253;
                8'd52: optical_gain=9'd256;
                8'd53: optical_gain=9'd256;
                8'd54: optical_gain=9'd256;
                8'd55: optical_gain=9'd256;
                8'd56: optical_gain=9'd256;
                8'd57: optical_gain=9'd256;
                8'd58: optical_gain=9'd256;
                8'd59: optical_gain=9'd256;
                8'd60: optical_gain=9'd256;
                8'd61: optical_gain=9'd256;
                8'd62: optical_gain=9'd256;
                8'd63: optical_gain=9'd256;
                8'd64: optical_gain=9'd128;
                8'd65: optical_gain=9'd128;
                8'd66: optical_gain=9'd128;
                8'd67: optical_gain=9'd130;
                8'd68: optical_gain=9'd134;
                8'd69: optical_gain=9'd138;
                8'd70: optical_gain=9'd142;
                8'd71: optical_gain=9'd147;
                8'd72: optical_gain=9'd152;
                8'd73: optical_gain=9'd158;
                8'd74: optical_gain=9'd163;
                8'd75: optical_gain=9'd170;
                8'd76: optical_gain=9'd176;
                8'd77: optical_gain=9'd184;
                8'd78: optical_gain=9'd192;
                8'd79: optical_gain=9'd200;
                8'd80: optical_gain=9'd210;
                8'd81: optical_gain=9'd220;
                8'd82: optical_gain=9'd232;
                8'd83: optical_gain=9'd244;
                8'd84: optical_gain=9'd256;
                8'd85: optical_gain=9'd256;
                8'd86: optical_gain=9'd256;
                8'd87: optical_gain=9'd256;
                8'd88: optical_gain=9'd256;
                8'd89: optical_gain=9'd256;
                8'd90: optical_gain=9'd256;
                8'd91: optical_gain=9'd256;
                8'd92: optical_gain=9'd256;
                8'd93: optical_gain=9'd256;
                8'd94: optical_gain=9'd256;
                8'd95: optical_gain=9'd256;
                8'd96: optical_gain=9'd128;
                8'd97: optical_gain=9'd128;
                8'd98: optical_gain=9'd128;
                8'd99: optical_gain=9'd130;
                8'd100: optical_gain=9'd134;
                8'd101: optical_gain=9'd138;
                8'd102: optical_gain=9'd142;
                8'd103: optical_gain=9'd146;
                8'd104: optical_gain=9'd151;
                8'd105: optical_gain=9'd156;
                8'd106: optical_gain=9'd162;
                8'd107: optical_gain=9'd168;
                8'd108: optical_gain=9'd174;
                8'd109: optical_gain=9'd181;
                8'd110: optical_gain=9'd188;
                8'd111: optical_gain=9'd196;
                8'd112: optical_gain=9'd205;
                8'd113: optical_gain=9'd214;
                8'd114: optical_gain=9'd225;
                8'd115: optical_gain=9'd236;
                8'd116: optical_gain=9'd249;
                8'd117: optical_gain=9'd256;
                8'd118: optical_gain=9'd256;
                8'd119: optical_gain=9'd256;
                8'd120: optical_gain=9'd256;
                8'd121: optical_gain=9'd256;
                8'd122: optical_gain=9'd256;
                8'd123: optical_gain=9'd256;
                8'd124: optical_gain=9'd256;
                8'd125: optical_gain=9'd256;
                8'd126: optical_gain=9'd256;
                8'd127: optical_gain=9'd256;
                8'd128: optical_gain=9'd128;
                8'd129: optical_gain=9'd128;
                8'd130: optical_gain=9'd128;
                8'd131: optical_gain=9'd130;
                8'd132: optical_gain=9'd133;
                8'd133: optical_gain=9'd137;
                8'd134: optical_gain=9'd141;
                8'd135: optical_gain=9'd146;
                8'd136: optical_gain=9'd150;
                8'd137: optical_gain=9'd155;
                8'd138: optical_gain=9'd160;
                8'd139: optical_gain=9'd166;
                8'd140: optical_gain=9'd172;
                8'd141: optical_gain=9'd178;
                8'd142: optical_gain=9'd185;
                8'd143: optical_gain=9'd192;
                8'd144: optical_gain=9'd201;
                8'd145: optical_gain=9'd209;
                8'd146: optical_gain=9'd219;
                8'd147: optical_gain=9'd229;
                8'd148: optical_gain=9'd241;
                8'd149: optical_gain=9'd254;
                8'd150: optical_gain=9'd256;
                8'd151: optical_gain=9'd256;
                8'd152: optical_gain=9'd256;
                8'd153: optical_gain=9'd256;
                8'd154: optical_gain=9'd256;
                8'd155: optical_gain=9'd256;
                8'd156: optical_gain=9'd256;
                8'd157: optical_gain=9'd256;
                8'd158: optical_gain=9'd256;
                8'd159: optical_gain=9'd256;
                8'd160: optical_gain=9'd128;
                8'd161: optical_gain=9'd128;
                8'd162: optical_gain=9'd128;
                8'd163: optical_gain=9'd130;
                8'd164: optical_gain=9'd133;
                8'd165: optical_gain=9'd137;
                8'd166: optical_gain=9'd141;
                8'd167: optical_gain=9'd145;
                8'd168: optical_gain=9'd149;
                8'd169: optical_gain=9'd154;
                8'd170: optical_gain=9'd159;
                8'd171: optical_gain=9'd164;
                8'd172: optical_gain=9'd170;
                8'd173: optical_gain=9'd176;
                8'd174: optical_gain=9'd182;
                8'd175: optical_gain=9'd189;
                8'd176: optical_gain=9'd197;
                8'd177: optical_gain=9'd205;
                8'd178: optical_gain=9'd214;
                8'd179: optical_gain=9'd223;
                8'd180: optical_gain=9'd234;
                8'd181: optical_gain=9'd245;
                8'd182: optical_gain=9'd256;
                8'd183: optical_gain=9'd256;
                8'd184: optical_gain=9'd256;
                8'd185: optical_gain=9'd256;
                8'd186: optical_gain=9'd256;
                8'd187: optical_gain=9'd256;
                8'd188: optical_gain=9'd256;
                8'd189: optical_gain=9'd256;
                8'd190: optical_gain=9'd256;
                8'd191: optical_gain=9'd256;
                8'd192: optical_gain=9'd128;
                8'd193: optical_gain=9'd128;
                8'd194: optical_gain=9'd128;
                8'd195: optical_gain=9'd130;
                8'd196: optical_gain=9'd133;
                8'd197: optical_gain=9'd137;
                8'd198: optical_gain=9'd140;
                8'd199: optical_gain=9'd144;
                8'd200: optical_gain=9'd148;
                8'd201: optical_gain=9'd153;
                8'd202: optical_gain=9'd158;
                8'd203: optical_gain=9'd163;
                8'd204: optical_gain=9'd168;
                8'd205: optical_gain=9'd174;
                8'd206: optical_gain=9'd180;
                8'd207: optical_gain=9'd186;
                8'd208: optical_gain=9'd193;
                8'd209: optical_gain=9'd201;
                8'd210: optical_gain=9'd209;
                8'd211: optical_gain=9'd218;
                8'd212: optical_gain=9'd228;
                8'd213: optical_gain=9'd238;
                8'd214: optical_gain=9'd250;
                8'd215: optical_gain=9'd256;
                8'd216: optical_gain=9'd256;
                8'd217: optical_gain=9'd256;
                8'd218: optical_gain=9'd256;
                8'd219: optical_gain=9'd256;
                8'd220: optical_gain=9'd256;
                8'd221: optical_gain=9'd256;
                8'd222: optical_gain=9'd256;
                8'd223: optical_gain=9'd256;
                8'd224: optical_gain=9'd128;
                8'd225: optical_gain=9'd128;
                8'd226: optical_gain=9'd128;
                8'd227: optical_gain=9'd130;
                8'd228: optical_gain=9'd133;
                8'd229: optical_gain=9'd136;
                8'd230: optical_gain=9'd140;
                8'd231: optical_gain=9'd144;
                8'd232: optical_gain=9'd148;
                8'd233: optical_gain=9'd152;
                8'd234: optical_gain=9'd156;
                8'd235: optical_gain=9'd161;
                8'd236: optical_gain=9'd166;
                8'd237: optical_gain=9'd172;
                8'd238: optical_gain=9'd177;
                8'd239: optical_gain=9'd183;
                8'd240: optical_gain=9'd190;
                8'd241: optical_gain=9'd197;
                8'd242: optical_gain=9'd205;
                8'd243: optical_gain=9'd213;
                8'd244: optical_gain=9'd222;
                8'd245: optical_gain=9'd232;
                8'd246: optical_gain=9'd242;
                8'd247: optical_gain=9'd254;
                8'd248: optical_gain=9'd256;
                8'd249: optical_gain=9'd256;
                8'd250: optical_gain=9'd256;
                8'd251: optical_gain=9'd256;
                8'd252: optical_gain=9'd256;
                8'd253: optical_gain=9'd256;
                8'd254: optical_gain=9'd256;
                8'd255: optical_gain=9'd256;
                default: optical_gain=9'd128;
            endcase
        end
    endfunction
    wire [7:0] lookup={airlight[5:3],tile_mean[build_tile][7:3]};
    wire [8:0] chroma_limit={1'b0,dark_last}+9'd8;
    wire patch_colored=s_rgb[95:88]>chroma_limit||s_rgb[87:80]>chroma_limit||s_rgb[79:72]>chroma_limit;
    always @(posedge clk)begin
        if(complete_patch)begin
            patch_tile<={ty,tx};first_in_tile<=bx==0&&by==0;last_in_tile<=bx==7&&by==7;
            patch_dark_q<=dark_patch;patch_air_q<=candidate_air;
            patch_bright_q<=s_luma[31:24]>=96;patch_colored_q<=patch_colored;
            patch_highlight_q<=s_luma[31:24]>=224;
        end
    end
    // Auto-gain can make a night-fog frame bright but almost achromatic with
    // isolated headlights. Use a quarter of the inverse-transmission increment.
    wire low_confidence=bright_samples<128||(chromatic_samples<64&&highlight_samples>=16);
    wire [8:0] base_gain=optical_gain(lookup);
    wire [8:0] safe_gain=9'd128+((base_gain-9'd128+9'd2)>>2);
    wire [5:0] build_address={camera,!active_page[camera],build_tile};
    wire [8:0] next_gain=(best_dark<64||clear_tiles[2])?9'd128:(low_confidence?safe_gain:base_gain);
    always @(posedge clk)begin
        if(state==BUILD && !patch_pending && !clear)begin
            // Consecutive raster-order gains supply (r-1,c-1),(r-1,c),
            // (r,c-1),(r,c). Writes start after one row and one column.
            prior_gains<={prior_gains[35:0],next_gain};
            if(build_tile[3:2]!=0 && build_tile[1:0]!=0)
                gain_blocks[build_address]<={prior_gains[44:36],prior_gains[35:27],prior_gains[8:0],next_gain};
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;history_valid<=0;active_page<=0;o_history_used<=0;patch_pending<=0;
            tile_x<=0;tile_y<=0;local_x<=0;local_y<=0;phase_x<=0;phase_y<=0;patch_x<=0;patch_y<=0;
            camera<=0;session<=0;epoch<=0;seq<=0;terminal_seen<=0;terminal_good<=0;raster_good<=0;
            build_tile<=0;best_dark<=0;airlight<=192;clear_tiles<=0;bright_samples<=0;chromatic_samples<=0;highlight_samples<=0;
        end else begin
            patch_pending<=complete_patch && !clear && !i_history_reset && !(terminal&&!i_terminal_ok);
            if(i_history_reset)history_valid<=0;
            if(clear)begin
                state<=IDLE;terminal_seen<=0;raster_good<=0;o_history_used<=0;
            end else begin
                if(terminal&&state!=IDLE)begin
                    terminal_seen<=1;
                    terminal_good<=i_terminal_ok&&(!terminal_seen||terminal_good);
                end
                if(fire&&(fresh||state==CAPTURE))begin
                    if(fresh)begin
                        camera<=i_camera;session<=i_session;epoch<=i_epoch;seq<=i_sequence;
                        state<=i_enable?CAPTURE:IDLE;o_history_used<=eligible;
                        best_dark<=0;airlight<=192;clear_tiles<=0;bright_samples<=0;chromatic_samples<=0;highlight_samples<=0;raster_good<=s_eol==end_line;
                        terminal_seen<=terminal;terminal_good<=terminal&&i_terminal_ok;
                    end else if(s_eol!=end_line)raster_good<=0;
                    // Coordinates advance from true input transfers, including the SOF beat.
                    tile_x<=x_end?tx+1'b1:tx;local_x<=x_end?0:lx+1'b1;
                    phase_x<=(x_end||px==STEP_X-1)?0:px+1'b1;
                    patch_x<=x_end?0:px==STEP_X-1?bx+1'b1:bx;
                    tile_y<=end_line&&y_end?ty+1'b1:ty;
                    local_y<=end_line?(y_end?0:ly+1'b1):ly;
                    phase_y<=end_line?((y_end||py==STEP_Y-1)?0:py+1'b1):py;
                    patch_y<=end_line?(y_end?0:py==STEP_Y-1?by+1'b1:by):by;
                    if((fresh?i_enable:1'b1)&&bx<8&&by<8&&py<4)begin
                        if(px==0)group_min<=py==0 ? dark4 : dark_patch;
                        if(px==1)begin
                            rows_min[col]<=dark_patch;
                        end
                    end
                    if(end_frame)begin
                        build_tile<=0;
                        state<=raster_good&&s_eol?BUILD:IDLE;
                    end
                end
                if(patch_pending && !(fresh&&fire))begin
                    tile_sum[patch_tile[1:0]]<=patch_sum;
                    if(patch_bright_q&&bright_samples<128)bright_samples<=bright_samples+1'b1;
                    if(patch_colored_q&&chromatic_samples<64)chromatic_samples<=chromatic_samples+1'b1;
                    if(patch_highlight_q&&highlight_samples<16)highlight_samples<=highlight_samples+1'b1;
                    if(last_in_tile)begin
                        tile_mean[patch_tile]<=patch_sum[13:6];
                        if(patch_sum[13:6]<=48&&!clear_tiles[2])clear_tiles<=clear_tiles+1'b1;
                    end
                    if(patch_dark_q>best_dark)begin best_dark<=patch_dark_q;airlight<=patch_air_q;end
                end
                if(state==BUILD&&!patch_pending)begin
                    if(build_tile==15)state<=WAIT_SOURCE;
                    else build_tile<=build_tile+1'b1;
                end
                if(state==WAIT_SOURCE&&(terminal_seen||terminal))begin
                    if(accepted_source&&!i_history_reset)begin
                        history_valid[camera]<=1;hist_session[camera]<=session;
                        hist_epoch[camera]<=epoch;hist_seq[camera]<=seq;air_history[camera]<=airlight;
                        active_page[camera]<=!active_page[camera];
                    end
                    state<=IDLE;terminal_seen<=0;
                end
                // A bad physical terminal may arrive on a truncated raster with no EOF.
                if((terminal&&!i_terminal_ok)||(i_history_reset&&!(fresh&&fire)))begin
                    state<=IDLE;terminal_seen<=0;raster_good<=0;
                end
            end
        end
    end

    // Bilinear interpolation at eight subcells per tile. Outside grid centres
    // clamp to the nearest tile; saturated edge cells never wrap to tile zero.
    wire [2:0] sx=bx>=8?3'd7:bx[2:0],sy=by>=8?3'd7:by[2:0];
    wire [1:0] right=!sx[2]?tx:tx==3?3:tx+1'b1;
    wire [1:0] bottom=!sy[2]?ty:ty==3?3:ty+1'b1;
    // Index by the lower-right corner, 1..3 on each axis. At image
    // borders choose endpoint weight 0 or 8 from the nearest real cell.
    wire [1:0] cell_x=(tx==0 && !sx[2]) ? 2'd1 : right;
    wire [1:0] cell_y=(ty==0 && !sy[2]) ? 2'd1 : bottom;
    wire [3:0] sample_fx=(tx==0 && !sx[2]) ? 4'd0 :
        (tx==3 && sx[2]) ? 4'd8 : {1'b0,~sx[2],sx[1:0]};
    wire [3:0] sample_fy=(ty==0 && !sy[2]) ? 4'd0 :
        (ty==3 && sy[2]) ? 4'd8 : {1'b0,~sy[2],sy[1:0]};
    reg [35:0] neighbours;
    wire [8:0] g00=neighbours[35:27],g01=neighbours[26:18];
    wire [8:0] g10=neighbours[17:9],g11=neighbours[8:0];
    reg [3:0] fx0,fy0,fy1;
    reg [11:0] a1,b1;
    reg [8:0] gain2;
    reg [95:0] rgb0,rgb1,rgb2,rgb3,rgb4,rgb5,rgb6;
    reg [31:0] y0,y1,y2,y3,y4,y5,y6;
    reg [5:0] enabled;
    reg [7:0] air0,air1,air2;
    wire [15:0] weighted=a1*(4'd8-fy1)+b1*fy1+16'd32;
    assign m_valid=vp[6]&&!pixel_discard;assign m_sof=sp[6];assign m_eol=ep[6];assign m_rgb=rgb6;assign m_luma=y6;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin vp<=0;sp<=0;ep<=0;clear_pending<=0;end
        else begin
            clear_pending<=clear;
            if(clear_pending)begin vp<=0;sp<=0;ep<=0;end
            else if(advance)begin vp<={vp[5:0],fire};sp<={sp[5:0],s_sof};ep<={ep[5:0],s_eol};end
        end
    end
    always @(posedge clk)if(advance)begin
        neighbours<=gain_blocks[{eye,active_page[eye],cell_y,cell_x}];
        fx0<=sample_fx;fy0<=sample_fy;fy1<=fy0;
        a1<=g00*(4'd8-fx0)+g01*fx0;b1<=g10*(4'd8-fx0)+g11*fx0;
        // One shared coefficient selects identity for all twelve components.
        // Force known A as well: the first frame has no initialized map.
        gain2<=enabled[1] ? weighted[14:6] : 9'd128;
        rgb0<=s_rgb;rgb1<=rgb0;rgb2<=rgb1;rgb3<=rgb2;rgb5<=rgb4;rgb6<=rgb5;
        y0<=s_luma;y1<=y0;y2<=y1;y3<=y2;y4<=y3;y5<=y4;
        air0<=use_gain ? air_history[eye] : 8'd0;air1<=air0;air2<=air1;
        enabled<={enabled[4:0],use_gain};
    end
    generate for(p=0;p<12;p=p+1)begin:g_restore
        reg signed [16:0] recovered_q7;
        wire signed [8:0] difference=$signed({1'b0,rgb2[p*8+:8]})-$signed({1'b0,air2});
        // Folding the shared A*128+64 bias into the multiply-add is exact
        // before the arithmetic right shift. Its signed result is in [-32576,65344].
        wire signed [16:0] bias=$signed({2'b00,air2,7'd64});
        wire [9:0] restored=recovered_q7[16:7];
        // Limit shadow loss to half of the original component.
        wire [7:0] component=rgb3[p*8+:8];
        // At 96 both expressions equal 48. Testing the top three bits
        // suffices to select the larger of I/2 and I-48.
        wire [7:0] floor_value=(component[7] || (&component[6:5])) ? component-8'd48 : component>>1;
        wire negative=restored[9];
        wire above=!negative && restored[8];
        wire below=negative || (restored[7:0]<floor_value);
        always @(posedge clk)if(advance)begin
            recovered_q7<=difference*$signed({1'b0,gain2})+bias;
            rgb4[p*8+:8]<=above ? 8'hff : below ? floor_value : restored[7:0];
        end
    end endgenerate
    generate for(p=0;p<4;p=p+1)begin:g_y
        reg [15:0] redgreen,blue;
        always @(posedge clk)if(advance)begin
            redgreen<=rgb4[p*24+16+:8]*8'd77+rgb4[p*24+8+:8]*8'd150;
            blue<=rgb4[p*24+:8]*8'd29+16'd128;
            y6[p*8+:8]<=enabled[5]?(redgreen+blue)>>8:y5[p*8+:8];
        end
    end endgenerate
    generate if(WIDTH%128!=0||WIDTH<256||HEIGHT%4!=0||HEIGHT<128||
                TILE_X>2048||TILE_Y>2048||STEP_X>255||STEP_Y>255)begin:g_bad_geometry
        DCP_REQUIRES_4X4_TILES_WITH_8X8_SAMPLED_PATCHES invalid_geometry();
    end endgenerate
endmodule
