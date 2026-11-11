`timescale 1ns / 1ps
`default_nettype none

// One metadata FIFO; early original stats wait for their real record BEGIN.
module nr_original_stats_cdc4 (
    input wire i_dfi_clk,i_dfi_rst_n,i_pixel_clk,i_pixel_rst_n,
    input wire s_valid,output wire s_ready,input wire [63:0] s_tag,
    input wire [159:0] s_context,input wire [183:0] s_statistics,
    output wire o_dfi_reset_done,o_pixel_reset_done,
    input wire i_context_fire,input wire [63:0] i_context_tag,
    input wire [159:0] i_context,input wire i_request,
    input wire i_product_begin,input wire [159:0] i_product_context,
    input wire i_frame_released,input wire [159:0] i_release_context,
    output wire o_context_available,
    output wire m_valid,input wire m_ready,output wire [159:0] m_context,
    output wire [183:0] m_statistics,output reg [31:0] o_stale_count
);
    wire cohort_reset_n=i_dfi_rst_n && i_pixel_rst_n;
    reg [1:0] pixel_release;
    always @(posedge i_pixel_clk or negedge cohort_reset_n)begin
        if(!cohort_reset_n)pixel_release<=0;
        else pixel_release<={pixel_release[0],1'b1};
    end
    wire pixel_reset_n=pixel_release[1];
    wire sink_reset_done;
    assign o_pixel_reset_done=pixel_reset_n && sink_reset_done;
    wire [407:0] sink_data;
    wire sink_valid,sink_ready;
    wire [63:0] incoming_tag=sink_data[407:344];
    wire [159:0] incoming_context=sink_data[343:184];
    reg active,requested,product_owned,received,delivered,pending,released;
    reg [63:0] tag_locked;
    reg [159:0] context_locked;
    reg [183:0] statistics_locked;
    wire exact=active && incoming_tag==tag_locked && incoming_context==context_locked;
    wire begin_exact=active && requested && !delivered && !product_owned && i_product_context==context_locked;
    wire release_exact=active && i_release_context==context_locked;
    wire new_product=i_product_begin && begin_exact;
    wire cancel_unbound=i_frame_released && release_exact && !product_owned && !new_product;
    wire receive=sink_valid && sink_ready;
    wire stats_fire=m_valid && m_ready;
    wire stale=(receive && (!exact || received)) || (i_product_begin && !begin_exact) ||
        (i_frame_released && !release_exact);
    assign sink_ready=o_pixel_reset_done && (!exact || !requested || received || !pending);
    assign o_context_available=o_pixel_reset_done && !active && !product_owned && !pending;
    assign m_valid=o_pixel_reset_done && product_owned && pending;
    assign m_context=context_locked;assign m_statistics=statistics_locked;
    control_message_fifo_ip #(.MESSAGE_WIDTH(408)) u_metadata(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_dfi_clk),.i_source_rst_n(cohort_reset_n),.i_source_data({s_tag,s_context,s_statistics}),
        .i_source_valid(s_valid),.o_source_ready(s_ready),.o_source_reset_done(o_dfi_reset_done),
        .i_sink_clk(i_pixel_clk),.i_sink_rst_n(cohort_reset_n),.o_sink_data(sink_data),
        .o_sink_valid(sink_valid),.i_sink_ready(sink_ready),.o_sink_reset_done(sink_reset_done));
    always @(posedge i_pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin
            active<=0;requested<=0;product_owned<=0;received<=0;delivered<=0;pending<=0;released<=0;
            tag_locked<=0;context_locked<=0;statistics_locked<=0;o_stale_count<=0;
        end else begin
            if(stale && !(&o_stale_count))o_stale_count<=o_stale_count+1'b1;
            if(receive && exact && requested && !received && !cancel_unbound)begin
                received<=1;pending<=1;statistics_locked<=sink_data[183:0];
            end
            if(new_product)product_owned<=1;
            if(stats_fire)begin
                pending<=0;product_owned<=0;delivered<=1;
                if(released)begin active<=0;requested<=0;end
            end
            // A released failed frame has no record owner. Late metadata is stale.
            // A presented record-owned result remains held through READY.
            if(i_frame_released && release_exact)begin
                released<=1;
                if((!product_owned && !new_product) || stats_fire)begin
                    active<=0;requested<=0;pending<=0;received<=0;delivered<=0;
                end
            end
            if(i_context_fire && o_context_available)begin
                active<=1;requested<=i_request;product_owned<=0;received<=0;delivered<=0;pending<=0;released<=0;
                tag_locked<=i_context_tag;context_locked<=i_context;statistics_locked<=0;
            end
        end
    end
endmodule
`default_nettype wire
