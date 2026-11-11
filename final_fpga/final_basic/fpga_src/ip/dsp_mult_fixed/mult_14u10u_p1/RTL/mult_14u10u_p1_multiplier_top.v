module mult_14u10u_p1_multiplier_top
#(
    parameter   A_WIDTH           = 69,
    parameter   B_WIDTH           = 69,
    parameter   A_SIGNED          = 1,
    parameter   B_SIGNED          = 1,
    //ce_int&rst_int
    parameter   HAS_CE            = 1,
    parameter   HAS_SCLR          = 1,
    parameter   CE_OVER_SCLR      = 0,
    //constant
    parameter   MODEL_TYPE        = 0,
    parameter   B_VALUE_WIDTH     = 32,
    parameter   B_VALUE_NEGE      = 1,
    parameter [68:0] B_VALUE      = {B_VALUE_WIDTH{1'b1}},//18'b11_1111_1111_1111_1111
    //pipeline
    parameter   MULT_TYPE         = 0,
    parameter   DELAY             = 18,
    //round
    parameter   OUT_HIGH          = 137,
    parameter   OUT_LOW           = 0,
    parameter   P_WIDTH           = OUT_HIGH-OUT_LOW+1,
    parameter   ROUND_OUTPUT      = 0
)(

    input                       ce  ,


    input                       rst ,


    input                       clk ,

    input       [A_WIDTH-1:0]   a   , 
         
    input       [B_WIDTH-1:0]   b   ,
          
    output      [P_WIDTH-1:0]   p
);

mult_14u10u_p1_multiplier #(
    .A_WIDTH       ( A_WIDTH        ),
    .B_WIDTH       ( B_WIDTH        ),
    .A_SIGNED      ( A_SIGNED       ),
    .B_SIGNED      ( B_SIGNED       ),
    .HAS_CE        ( HAS_CE         ),
    .HAS_SCLR      ( HAS_SCLR       ),
    .CE_OVER_SCLR  ( CE_OVER_SCLR   ),
    .MODEL_TYPE    ( MODEL_TYPE     ),
    .B_VALUE_WIDTH ( B_VALUE_WIDTH  ),
    .B_VALUE_NEGE  ( B_VALUE_NEGE   ),
    .B_VALUE       ( B_VALUE        ),
    .MULT_TYPE     ( MULT_TYPE      ),
    .DELAY         ( DELAY          ),
    .OUT_HIGH      ( OUT_HIGH       ),
    .OUT_LOW       ( OUT_LOW        ),
    .P_WIDTH       ( P_WIDTH        ),
    .ROUND_OUTPUT  ( ROUND_OUTPUT   )
)u_multiplier(

    .ce            ( ce             ),



    .rst           ( rst            ),



    .clk           ( clk            ),


    .a             ( a              ),

    .b             ( b              ),


    .p             ( p              )
);



endmodule

