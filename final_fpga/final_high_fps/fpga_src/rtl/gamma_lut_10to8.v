// 将十位颜色码值映射为八位伽马输出
module gamma_lut_10to8 #(
    // 伽马配置
    parameter C_GAMMA_LINEAR_BYPASS = 1'b0,
    parameter C_INIT_FILE = "gamma22_10to8.dath",
    // Default preserves existing instantiations that omit i_ce.
    parameter C_USE_CE = 1'b0
) (
    // 时钟与复位
    input        i_clk,
    input        i_rstn,

    // 伽马查表索引与码值
    input  [9:0] i_index,
    output [7:0] o_value,
    input        i_ce
);
    wire [7:0] gamma_value;
    wire [7:0] reset_gamma_value;
    reg  [7:0] linear_value;
    reg  [1:0] reset_release;
    reg        gamma_hold_valid;
    reg  [7:0] gamma_hold_value;
    wire       advance = C_USE_CE ? i_ce : 1'b1;
    wire [7:0] held_gamma_value = (C_USE_CE && gamma_hold_valid)
                                ? gamma_hold_value : gamma_value;

    generate
        if (C_INIT_FILE == "gamma22_10to8.dath") begin : g_generated_rom
            // 标准伽马表由 TD IP 配置管理
            gamma_rom_8x1024_ip u_gamma_memory (
                .doa(gamma_value), .addra(i_index), .clka(i_clk)
            );
        end else begin : g_custom_rom
            // 非默认初始化文件沿用公开参数接口
            reg [7:0] custom_table [0:1023];
            reg [7:0] custom_value;
            initial begin
                if (C_INIT_FILE[31:0] == ".dat")
                    $readmemb(C_INIT_FILE, custom_table);
                else
                    $readmemh(C_INIT_FILE, custom_table);
            end
            always @(posedge i_clk)
                custom_value <= custom_table[i_index];
            assign gamma_value = custom_value;
        end
    endgenerate

    // 旧 PH1 输出锁存器异步清零，释放后经过两个时钟沿才输出；生成的 ROM 无复位端口
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn)
            reset_release <= 2'b00;
        else
            reset_release <= {reset_release[0], 1'b1};
    end
    assign reset_gamma_value = reset_release[1] ? held_gamma_value : 8'd0;

    // The generated ROM has no CE port. Preserve its pending output at the
    // first frozen edge, before the free-running ROM samples the next address.
    // The consumer takes this saved value on the first resumed edge; clearing
    // hold_valid afterwards exposes the correctly sampled next ROM value.
    // This adds no latency to enabled transfers and leaves vendor IP untouched.
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            gamma_hold_valid <= 1'b0;
            gamma_hold_value <= 8'd0;
        end else if (C_USE_CE) begin
            if (!advance && !gamma_hold_valid) begin
                gamma_hold_valid <= 1'b1;
                gamma_hold_value <= reset_release[1] ? gamma_value : 8'd0;
            end else if (advance) begin
                gamma_hold_valid <= 1'b0;
            end
        end
    end

    // 锁存查表或线性旁路的颜色输出
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn)
            linear_value <= 8'd0;
        else if (advance)
            linear_value <= i_index[9:2];
    end

    assign o_value = C_GAMMA_LINEAR_BYPASS ? linear_value : reset_gamma_value;
endmodule
