`timescale 1ns / 1ns

module fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0 
#(
	// config_param

	parameter integer      REGISTER1 = 0, 
    parameter integer      REGISTER2 = 0,
    parameter integer      REGISTER3 = 0,
    parameter integer      REGISTER4 = 0,
    parameter integer      REGISTER5 = 0,
    parameter integer      REGISTER6 = 0,
    parameter integer      REGISTER7 = 0,
    parameter integer      REGISTER8 = 0,
    parameter integer      REGISTER9 = 0,
    parameter integer      REGISTER10 = 0,
    parameter integer      REGISTER11 = 0,
    parameter integer      REGISTER12 = 0,
    parameter integer      REGISTER13 = 0,
    parameter integer      REGISTER14 = 0,
    parameter integer      REGISTER15 = 0,
    parameter integer      REGISTER16 = 0,
    parameter integer      REGISTER17 = 0,
    parameter integer      REGISTER18 = 0,
    parameter integer      REGISTER19 = 0,
    parameter integer      REGISTER20 = 0,
    parameter integer      REGISTER21 = 0,
    parameter integer      REGISTER22 = 0,
    parameter integer      REGISTER23 = 0,
    parameter integer      REGISTER24 = 1,
	parameter			   MUL9_MODE = "NORMAL",						// "NORMAL", "DUAL_9X9"
	parameter			   MUL9_SIGNED = "SIGNED",						// "SIGNED", "UNSIGNED"
    parameter			   A_INPUT_TYPE = "UNSIGNED",
    parameter		       B_INPUT_TYPE = "UNSIGNED",
    parameter		       Y_INPUT_TYPE = "UNSIGNED",
    parameter		       Z_INPUT_TYPE = "UNSIGNED",
    parameter [4:0]        A_INPUT_WIDTH = 26,
    parameter [4:0]        B_INPUT_WIDTH = 26,
    parameter [4:0]        Y_INPUT_WIDTH = 17,
    parameter [5:0]        Z_INPUT_WIDTH = 53,
    parameter [5:0]        P_OUTPUT_WIDTH = 53, 
    parameter [29:0]	   USER_CTRL0 = 30'b0,
    parameter [29:0]	   USER_CTRL1 = 30'b0,
    parameter [29:0]	   USER_CTRL2 = 30'b0,
    parameter [29:0]	   USER_CTRL3 = 30'b0,
    parameter [29:0]	   USER_CTRL4 = 30'b0,
    parameter [29:0]	   USER_CTRL5 = 30'b0,
    parameter [29:0]	   USER_CTRL6 = 30'b0,
    parameter [29:0]	   USER_CTRL7 = 30'b0,

	localparam [3:0] NUM_INSTRUCTION = USER_CTRL0[29] + USER_CTRL1[29] + USER_CTRL2[29] + USER_CTRL3[29] + USER_CTRL4[29] + USER_CTRL5[29] + USER_CTRL6[29] + USER_CTRL7[29] 
)(
    // input ports
    input CLK, 
	
	input CE,
	
	
	input RST,
	
	
	
    input [(A_INPUT_WIDTH - 1):0] A, 
	
	
	
    input [(Y_INPUT_WIDTH - 1):0] Y, 
	
	
    input [(Z_INPUT_WIDTH - 1):0] Z, 
	
    //cascade ports
	
	
	
	
	
	
	
	
	
	
    //output ports
    output [(P_OUTPUT_WIDTH - 1):0] P) ;
    localparam XAREG = (((REGISTER7 + REGISTER8) == 0) ? "0" : (((REGISTER7 + REGISTER8) == 1) ? "1" : (((REGISTER7 + REGISTER8) == 2) ? "2" : "1"))) ; 
    localparam XBREG = (((REGISTER9 + REGISTER10) == 0) ? "0" : (((REGISTER9 + REGISTER10) == 1) ? "1" : (((REGISTER9 + REGISTER10) == 2) ? "2" : "1"))) ; 
    localparam YREG = (((REGISTER13 + REGISTER14) == 0) ? "0" : (((REGISTER13 + REGISTER14) == 1) ? "1" : (((REGISTER13 + REGISTER14) == 2) ? "2" : "1"))) ; 
    localparam ZREG = ((REGISTER19 == 0) ? "0" : "1") ; 
    localparam INCTRLREG = ((REGISTER23 == 0) ? "0" : "1") ; 
    localparam MUXCTRLREG = ((REGISTER23 == 0) ? "0" : "1") ; 
    localparam OPCTRLREG = ((REGISTER23 == 0) ? "0" : "1") ; 
    localparam CINCTRLREG = ((REGISTER23 == 0) ? "0" : "1") ; 
    localparam CXAREG = (((REGISTER1 + REGISTER2) == 0) ? "0" : (((REGISTER1 + REGISTER2) == 1) ? "1" : (((REGISTER1 + REGISTER2) == 2) ? "2" : "1"))) ; 
    localparam CXBREG = (((REGISTER3 + REGISTER4) == 0) ? "0" : (((REGISTER3 + REGISTER4) == 1) ? "1" : (((REGISTER3 + REGISTER4) == 2) ? "2" : "1"))) ; 
    localparam CYREG = (((REGISTER5 + REGISTER6) == 0) ? "0" : (((REGISTER5 + REGISTER6) == 1) ? "1" : (((REGISTER5 + REGISTER6) == 2) ? "2" : "1"))) ; 
    localparam XABREG = ((REGISTER11 == 0) ? "0" : "1") ; 
    localparam MREG = ((REGISTER15 == 0) ? "0" : "1") ; 
    localparam POUWREG = ((REGISTER24 == 0) ? "0" : "1") ; 
    localparam CCOREG = ((REGISTER24 == 0) ? "0" : "1") ; 
    localparam RND_EN = (((((((((USER_CTRL0[15:14] == 2'b01) || (USER_CTRL1[15:14] == 2'b01)) || (USER_CTRL2[15:14] == 2'b01)) || (USER_CTRL3[15:14] == 2'b01)) || (USER_CTRL4[15:14] == 2'b01)) || (USER_CTRL5[15:14] == 2'b01)) || (USER_CTRL6[15:14] == 2'b01)) || (USER_CTRL7[15:14] == 2'b01)) ? 1 : 0) ; 
	
    localparam [53:0] RND = ((P_OUTPUT_WIDTH == 54) ? 54'b0 : ({1'b1,53'b0} >> P_OUTPUT_WIDTH)) ; 
	
    wire ce_in ; 
    wire rst_in ; 
    wire [26:0] a_in ; 
    wire [26:0] b_in ; 
    wire [17:0] y_in ; 
    wire cci_in ; 
    reg [((8 * 30) - 1):0] inst = 0 ; 
    reg [29:0] inst_temp = 0 ; 
    wire [28:0] inst_internal ; 
    reg inctrl5_reg = 0 ; 
    wire inctrl5_in ; 
    wire [6:0] INCTRL ; 
	
	wire [53:0] z_in ; 
    wire [53:0] cpi_in ; 
    wire [10:0] OPCTRL ; 
    reg [10:0] opctrl_reg1 = 0 ; 
    reg [10:0] opctrl_reg2 = 0 ; 
    reg [10:0] opctrl_reg3 = 0 ; 
    wire [10:0] opctrl_in ; 
    wire [6:0] MUXCTRL ; 
    reg [6:0] muxctrl_reg1 = 0 ; 
    reg [6:0] muxctrl_reg2 = 0 ; 
    reg [6:0] muxctrl_reg3 = 0 ; 
    wire [6:0] muxctrl_in ; 
    wire [53:0] tadd_a ; 
    wire [53:0] tadd_b ; 
    wire [53:0] tadd_c ; 
    wire [53:0] tadd_sum ; 
    wire [53:0] p_siou ; 
    wire [53:0] logic_a ; 
    wire [53:0] logic_b ; 
    wire [53:0] logic_c ; 
    wire [53:0] logic_p ; 
	
    wire [2:0] CINCTRL ; 
    reg [2:0] cinctrl_reg1 = 0 ; 
    reg [2:0] cinctrl_reg2 = 0 ; 
    reg [2:0] cinctrl_reg3 = 0 ; 
    wire [2:0] cinctrl_in ; 
    wire [26:0] add_a ; 
    wire [26:0] add_b ; 
    wire [1:0] add_opctrl ; 
    wire [26:0] add_sum ; 
    wire [26:0] mult_x ; 
    wire [17:0] mult_y ; 
	wire mul9_mode;
	wire mul9_signed;
    wire mult_opctrl ; 
    wire [44:0] mult_p ; 
    wire tadd_ci ; 
    wire [6:0] tadd_opctrl ; 
    wire [5:0] tadd_oversel ; 
    wire tadd_co ; 
    wire tadd_overflow ; 
    wire tadd_underflow ; 
    wire [4:0] logic_opctrl ; 
    wire [1:0] logic_wxor ; 


assign ce_in = CE;




assign rst_in = RST;




reg [A_INPUT_WIDTH-1:0] a_reg = 0;



reg [Y_INPUT_WIDTH-1:0] y_reg = 0;



reg [Z_INPUT_WIDTH-1:0] z_reg1 = 0;
reg [Z_INPUT_WIDTH-1:0] z_reg2 = 0;
reg [Z_INPUT_WIDTH-1:0] z_reg3 = 0;








    always @(posedge CLK or posedge rst_in)
        begin
            if (rst_in) 
                inctrl5_reg <=  0 ;
            else if (ce_in) 
                inctrl5_reg <=  inst_internal[24] ;
        end

    assign inctrl5_in = ((((REGISTER20 + REGISTER21) + REGISTER22) == 3) ? inctrl5_reg : inst_internal[24]) ; 
    assign INCTRL[0] = (((REGISTER7 + REGISTER8) == 2) ? 1'b0 : 1'b1); 
    assign INCTRL[1] = (((REGISTER9 + REGISTER10) == 2) ? 1'b0 : 1'b1); 
    assign INCTRL[2] = (((REGISTER13 + REGISTER14) == 2) ? 1'b0 : 1'b1); 
    assign INCTRL[6:3] = {1'b1,inctrl5_in,2'b11} ; 

    integer i,j ; 
    always @(*)
        begin
		 inst[((8 * 30) - 1):0] = {USER_CTRL7[29:0],
                USER_CTRL6[29:0],
                USER_CTRL5[29:0],
                USER_CTRL4[29:0],
                USER_CTRL3[29:0],
                USER_CTRL2[29:0],
                USER_CTRL1[29:0],
                USER_CTRL0[29:0]} ;
        for (i = 0 ; (i < 8) ; i = (i + 1))
            begin
                for (j = (i + 1) ; (j < 8) ; j = (j + 1))
                    begin
                        if ((!inst[(((i + 1) * 30) - 1)])) 
                            begin
                                inst_temp = inst[(j * 30) +: 30] ;
                                inst[(j * 30) +: 30] = inst[(i * 30) +: 30] ;
                                inst[(i * 30) +: 30] = inst_temp ;
                            end
                    end
            end
        end
    generate

	
	always @ ( posedge CLK or posedge rst_in )
	begin
		if ( rst_in )
			a_reg <= 0;
		else if ( ce_in )
			a_reg <= A;
	end

        if ((A_INPUT_TYPE == "UNSIGNED")) 
		assign a_in ={{(27-A_INPUT_WIDTH){1'b0}},A};
        else
		assign a_in = {{(27-A_INPUT_WIDTH){A[A_INPUT_WIDTH-1]}},A};
	

	
	assign b_in = 27'd0;
	

	
        always @ (posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    y_reg <=  0 ;
                else if (ce_in) 
                    y_reg <=  Y ;
            end

        if ((Y_INPUT_TYPE == "UNSIGNED")) 
            assign y_in = ((REGISTER12 == 1) ? {{(18 - Y_INPUT_WIDTH){1'b0}},y_reg} : {{(18 - Y_INPUT_WIDTH){1'b0}},Y}) ; 
        else
            assign y_in = ((REGISTER12 == 1) ? {{(18 - Y_INPUT_WIDTH){y_reg[(Y_INPUT_WIDTH - 1)]}}, y_reg} : {{(18 - Y_INPUT_WIDTH){Y[(Y_INPUT_WIDTH - 1)]}},Y}) ; 
    

	
        always @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    z_reg1 <=  0 ;
                else if (ce_in) 
                    z_reg1 <=  Z ;
            end

        always @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    z_reg2 <=  0 ;
                else if (ce_in) 
                        z_reg2 <=  z_reg1 ;
            end
        always
            @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    z_reg3 <=  0 ;
                else if (ce_in) 
                        z_reg3 <=  z_reg2 ;
            end
		
        if ((Z_INPUT_TYPE == "UNSIGNED")) 
            assign z_in = ((((REGISTER16 + REGISTER17) + REGISTER18) == 0) ? {{(54 - Z_INPUT_WIDTH){1'b0}},Z} : ((((REGISTER16 + REGISTER17) + REGISTER18) == 1) ? {{(54 - Z_INPUT_WIDTH){1'b0}},z_reg1} : ((((REGISTER16 + REGISTER17) + REGISTER18) == 3) ? {{(54 - Z_INPUT_WIDTH){1'b0}},z_reg3} : {{(54 - Z_INPUT_WIDTH){1'b0}}, z_reg2}))) ; 
        else
            assign z_in = ((((REGISTER16 + REGISTER17) + REGISTER18) == 0) ? {{(54 - Z_INPUT_WIDTH){Z[(Z_INPUT_WIDTH - 1)]}},Z} : ((((REGISTER16 + REGISTER17) + REGISTER18) == 1) ? {{(54 - Z_INPUT_WIDTH){z_reg1[(Z_INPUT_WIDTH - 1)]}}, z_reg1} : ((((REGISTER16 + REGISTER17) + REGISTER18) == 3) ? {{(54 - Z_INPUT_WIDTH){z_reg3[(Z_INPUT_WIDTH - 1)]}},z_reg3} : {{(54 - Z_INPUT_WIDTH){z_reg2[(Z_INPUT_WIDTH - 1)]}},z_reg2}))) ; 
		
    

	
    assign inst_internal = inst[28:0] ;
	
	
	
        assign OPCTRL = inst_internal[10:0] ; 
        assign MUXCTRL = inst_internal[18:12] ; 
        assign CINCTRL = inst_internal[23:21] ; 

        assign opctrl_in[0] = ((((REGISTER20 + REGISTER21) + REGISTER22) == 3) ? opctrl_reg1[0] : OPCTRL[0]) ; 
        assign opctrl_in[2:1] = ((((REGISTER20 + REGISTER21) + REGISTER22) == 3) ? opctrl_reg2[2:1] : ((((REGISTER20 + REGISTER21) + REGISTER22) == 2) ? opctrl_reg1[2:1] : OPCTRL[2:1])) ; 
        assign opctrl_in[10:3] = ((((REGISTER20 + REGISTER21) + REGISTER22) == 0) ? OPCTRL[10:3] : ((((REGISTER20 + REGISTER21) + REGISTER22) == 1) ? opctrl_reg1[10:3] : ((((REGISTER20 + REGISTER21) + REGISTER22) == 3) ? opctrl_reg3[10:3] : opctrl_reg2[10:3]))) ;

        assign muxctrl_in = ((((REGISTER20 + REGISTER21) + REGISTER22) == 0) ? MUXCTRL : ((((REGISTER20 + REGISTER21) + REGISTER22) == 1) ? muxctrl_reg1 : ((((REGISTER20 + REGISTER21) + REGISTER22) == 3) ? muxctrl_reg3 : muxctrl_reg2))) ; 

        assign cinctrl_in = ((((REGISTER20 + REGISTER21) + REGISTER22) == 0) ? CINCTRL : ((((REGISTER20 + REGISTER21) + REGISTER22) == 1) ? cinctrl_reg1 : ((((REGISTER20 + REGISTER21) + REGISTER22) == 3) ? cinctrl_reg3 : cinctrl_reg2))) ; 
	

        always @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    opctrl_reg1 <=  0 ;
                else if (ce_in) 
                    opctrl_reg1 <=  OPCTRL ;
            end

        always @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    opctrl_reg2 <=  0 ;
                else if (ce_in) 
                    opctrl_reg2 <=  opctrl_reg1 ;
            end

        always @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    opctrl_reg3 <=  0 ;
                else if (ce_in) 
                    opctrl_reg3 <=  opctrl_reg2 ;
            end

        always @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    muxctrl_reg1 <=  0 ;
                else if (ce_in) 
                    muxctrl_reg1 <=  MUXCTRL ;
            end

        always @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    muxctrl_reg2 <=  0 ;
                else if (ce_in) 
                    muxctrl_reg2 <=  muxctrl_reg1 ;
            end

        always @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    muxctrl_reg3 <=  0 ;
                else if (ce_in) 
                    muxctrl_reg3 <=  muxctrl_reg2 ;
            end

        always @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    cinctrl_reg1 <=  0 ;
                else if (ce_in) 
                    cinctrl_reg1 <=  CINCTRL ;
            end

        always @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    cinctrl_reg2 <=  0 ;
                else if (ce_in) 
                    cinctrl_reg2 <=  cinctrl_reg1 ;
            end

        always  @(posedge CLK or posedge rst_in)
            begin
                if (rst_in) 
                    cinctrl_reg3 <=  0 ;
                else if (ce_in) 
                    cinctrl_reg3 <=  cinctrl_reg2 ;
            end

    endgenerate


		
    PH1_PHY_DSPSIOU #(
			.CLKMUX("SIG"),
			.CE0("SIG"),
			.CE1("SIG"),
			.CE2("SIG"),
			.CE3("SIG"),
			.RST0("SIG"),
			.RST1("SIG"),
			.RST2("SIG"),
			.RST3("SIG"),
            .XAREG(XAREG),
            .XBREG(XBREG),
            .YREG(YREG),
            .ZREG(ZREG),
            .INCTRLREG(INCTRLREG),
            .MUXCTRLREG(MUXCTRLREG),
            .OPCTRLREG(OPCTRLREG),
            .CINCTRLREG(CINCTRLREG),
            .CXAREG(CXAREG),
            .CXBREG(CXBREG),
            .CYREG(CYREG),
            .XABREG(XABREG),
            .MREG(MREG),
            .POUWREG(POUWREG),
            .CCOREG(CCOREG),
            .SR0MODE("ASYNC"),
            .SR1MODE("ASYNC"),
            .SR2MODE("ASYNC"),
            .SR3MODE("ASYNC"),
            .USER_GSRN("ENABLE"),
            .CEXA1("CE0"),
            .CEXA2("CE0"),
            .CEXB1("CE0"),
            .CEXB2("CE0"),
            .CEXAB("CE0"),
            .CEM("CE0"),
            .CEY1("CE0"),
            .CEY2("CE0"),
            .CEPOU("CE0"),
            .CECOUT("CE0"),
            .CEINCTRL("CE0"),
            .CEMUXCTRL("CE0"),
            .CEOPCTRL("CE0"),
            .CECINCTRL("CE0"),
            .CEZ("CE0"),
            .CEW("CE0"),
            .RSTXA1("RST0"),
            .RSTXA2("RST0"),
            .RSTXB1("RST0"),
            .RSTXB2("RST0"),
            .RSTXAB("RST0"),
            .RSTM("RST0"),
            .RSTY1("RST0"),
            .RSTY2("RST0"),
            .RSTPOU("RST0"),
            .RSTCOUT("RST0"),
            .RSTINCTRL("RST0"),
            .RSTMUXCTRL("RST0"),
            .RSTOPCTRL("RST0"),
            .RSTCINCTRL("RST0"),
            .RSTZ("RST0"),
            .RSTW("RST0"),
			
            .XA_INPUT("XA"),
			
			
			.XB_INPUT("XB"),
			
			
            .Y_INPUT("Y"),
			
            .CXABO_OUTPUT("CXAO"),
            .RND(RND),
            .USE_OVERFLOW("P53")) u_siou 
			(	.y(y_in), 
                .xa(a_in), 
                .xb(b_in), 
                .z(z_in), 
                .clk(CLK), 
                .ce({4{ce_in}}), 
                .rst({4{rst_in}}), 
                .muxctrl(muxctrl_in), 
                .inctrl({INCTRL[6:5],1'b1,INCTRL[3:0]}), 
                .cinctrl(cinctrl_in), 
                .opctrl(opctrl_in), 
			    
			    
			    
				
				
			    
			    
			    
			    
			    
				.p(p_siou), 
                .overflow(), 
                .underflow(), 
                .wxor(), 
                .add_a(add_a), 
                .add_b(add_b), 
                .add_opctrl(add_opctrl), 
                .add_sum(add_sum), 
                .mult_x(mult_x), 
                .mult_y(mult_y), 
                .mult_opctrl(mult_opctrl), 
                .mult_p(mult_p), 
                .tadd_a(tadd_a), 
                .tadd_b(tadd_b), 
                .tadd_c(tadd_c), 
                .tadd_ci(tadd_ci), 
                .tadd_opctrl(tadd_opctrl), 
                .tadd_oversel(tadd_oversel), 
                .tadd_sum(tadd_sum), 
                .tadd_co(tadd_co), 
                .tadd_overflow(tadd_overflow), 
                .tadd_underflow(tadd_underflow), 
                .logic_a(logic_a), 
                .logic_b(logic_b), 
                .logic_c(logic_c), 
                .logic_opctrl(logic_opctrl), 
                .logic_p(logic_p), 
                .logic_wxor(logic_wxor)) ; 
    // add
    PH1_PHY_DSPADD_V2 u_add (
				.a(add_a), 
                .b(add_b), 
                .opctrl(add_opctrl), 
                .sum(add_sum)
				) ; 
    // mult
    PH1_PHY_DSPMULT_V2 u_mult (
				.x(mult_x), 
                .y(mult_y), 
                .opctrl(mult_opctrl), 
                .p(mult_p)
				) ; 
    // tadd
    PH1_PHY_DSPTADD_V2 u_tadd (
				.a(tadd_a), 
                .b(tadd_b), 
                .c(tadd_c), 
                .ci(tadd_ci), 
                .opctrl(tadd_opctrl), 
                .oversel(tadd_oversel), 
                .sum(tadd_sum), 
                .co(tadd_co), 
                .overflow(tadd_overflow), 
                .underflow(tadd_underflow)
				) ; 
    // logic
    PH1_PHY_DSPLOGIC_V2 u_logic (
				.a(logic_a), 
                .b(logic_b), 
                .c(logic_c), 
                .opctrl(logic_opctrl), 
                .p(logic_p), 
                .wxor(logic_wxor)
				) ; 
    assign P = (RND_EN ? p_siou[53:(54 - P_OUTPUT_WIDTH)] : p_siou[(P_OUTPUT_WIDTH - 1):0]) ; 
				
			
endmodule
	


