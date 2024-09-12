`timescale 1ns / 1ps


module top(
            input clk,input [15:0]x,y,
            output [31:0] Q_p
            );
 wire  [15:0]Q_x,Q_y;
 wire [31:0] p;
   
   //Adding a flip-flop to input and output 
  RisingEdge_DFlipFlop_16 d_ff_x(x,clk,Q_x); 
  RisingEdge_DFlipFlop_16 d_ff_y(y,clk,Q_y);
  RisingEdge_DFlipFlop_32 d_ff_p(p,clk,Q_p);
   
  
 ROBA S_roba( Q_x,Q_y,p);
 
endmodule




module RisingEdge_DFlipFlop_16(D,clk,Q);
input [15:0]D; // Data input 
input clk; // clock input 
output reg [15:0]Q; // output Q 
initial Q = 0;
always @(posedge clk) 
begin
 Q <= D; 
end 
endmodule 


module RisingEdge_DFlipFlop_32(D,clk,Q);
input [31:0]D; // Data input 
input clk; // clock input 
output reg [31:0]Q; // output Q 
initial Q = 0;
always @(posedge clk) 
begin
 Q <= D; 
end 
endmodule






//AS-ROBA Logic
module ROBA(
    input [15:0] x,
    input [15:0] y,
    output [31:0] p
    );
    
// Generate abs values
wire [15:0] x_abs;
wire [15:0] y_abs;

wire x_sign;
wire y_sign;

assign x_sign = x[15];
assign y_sign = y[15];

sec_complement_w16 abs_X
        (
         .data_in(x),
         .sign(x[15]),
         .data_out(x_abs)
         );

sec_complement_w16 abs_Y
        (
         .data_in(y),
         .sign(y[15]),
         .data_out(y_abs)
         ); 

// Rounding X
wire [15:0] x_round;
rounding_mod RoundX(x_abs,x_round);

// Rounding Y 
wire [15:0] y_round;
rounding_mod RoundY(y_abs,y_round);

// encode the round value x_abs
wire [3:0] x_enc;
PriorityEncoder_16 EncX(x_round,x_enc);

// encode the round value y_abs
wire [3:0] y_enc;
PriorityEncoder_16 EncY(y_round,y_enc);

// Shift Xr * Y_abs
wire [31:0] xr_Y;
Barrel32L XRtimesY( y_abs, x_enc, xr_Y);

// Shift Yr * x_abs
wire [31:0] yr_X;
Barrel32L YRtimesX( x_abs, y_enc, yr_X);

// Shift Yr * Xr
wire [31:0] yr_yx;
Barrel32L YRtimesXR( x_round, y_enc, yr_yx);

// sum xr_Y yr_X

wire [31:0] P;

//assign P = xr_Y + yr_X;
wire carry_out;
cpu_wb_cla_adder CLA(xr_Y, yr_X, 1'b0, P, carry_out);

// difference to get absolute value of product
wire [31:0] prod_abs;
wire [31:0] Z;

assign Z = yr_yx;
wire [31:0] tmp;
wire [31:0] tmp1;
wire [31:0] tmp2;

assign tmp = (P ^ Z);
assign tmp1 = (Z << 1);
assign tmp2 = (P & Z) << 1;
//assign prod_abs = (P ^ Z) & (((P << 1) ^ (P ^ Z)) | (( P & Z) << 1));
assign prod_abs = tmp & ((tmp1 ^ tmp) | tmp2);
// Revert to the signed value

wire prod_sign;

assign prod_sign = x_sign ^ y_sign;

assign p =  (prod_sign ==1) ?  (~prod_abs) : prod_abs ;

endmodule





module rounding_mod(
    input [15:0] data_in,
    output [15:0] data_out
);
    wire [15:0] tmp;
    genvar i;
    generate
    for (i=3; i<14; i=i+1) 
      begin
        assign tmp[i] = &(~data_in[15:i+1]);
        assign data_out[i] = ((~(data_in[i]) & data_in[i-1] & data_in[i-2]) | (data_in[i] & ~data_in[i-1])) & tmp[i];
      end
    endgenerate
    
    assign data_out[15] = (~data_in[15] & data_in[14] & data_in[13]) | (data_in[15] & ~data_in[14]);
    assign data_out[14] = ((~data_in[14] & data_in[13] & data_in[12]) | (data_in[14] & ~data_in[13])) & ~data_in[15];
    assign data_out[2] = data_in[2] & ~data_in[1] & (&(~data_in[15:3]));
    assign data_out[1] = data_in[1] & (&(~data_in[15:2]));
    assign data_out[0] = data_in[0] & (&(~data_in[15:1]));

endmodule



module PriorityEncoder_16(
    input [15:0] data_i,
    output reg [3:0] code_o
    );

	always @*
		case (data_i)
	 16'b0000000000000001 : code_o = 4'b0000;
         16'b0000000000000010 : code_o = 4'b0001;
         16'b0000000000000100 : code_o = 4'b0010;
         16'b0000000000001000 : code_o = 4'b0011;
         16'b0000000000010000 : code_o = 4'b0100;
         16'b0000000000100000 : code_o = 4'b0101;
         16'b0000000001000000 : code_o = 4'b0110;
         16'b0000000010000000 : code_o = 4'b0111;
         16'b0000000100000000 : code_o = 4'b1000;
         16'b0000001000000000 : code_o = 4'b1001;
         16'b0000010000000000 : code_o = 4'b1010;
         16'b0000100000000000 : code_o = 4'b1011;
         16'b0001000000000000 : code_o = 4'b1100;
         16'b0010000000000000 : code_o = 4'b1101;
         16'b0100000000000000 : code_o = 4'b1110;
         16'b1000000000000000 : code_o = 4'b1111;
			
	 default     : code_o = 4'b0000;
	        endcase
	
endmodule




module Barrel32L(
    input [15:0] data_i,
    input [3:0] shift_i,
    output reg [31:0] data_o
    );
	 
   always @*
      case (shift_i)
         4'b0000: data_o = data_i;
         4'b0001: data_o = data_i << 1;
         4'b0010: data_o = data_i << 2;
         4'b0011: data_o = data_i << 3;
         4'b0100: data_o = data_i << 4;
         4'b0101: data_o = data_i << 5;
         4'b0110: data_o = data_i << 6;
         4'b0111: data_o = data_i << 7;
         4'b1000: data_o = data_i << 8;
         4'b1001: data_o = data_i << 9;
         4'b1010: data_o = data_i << 10;
         4'b1011: data_o = data_i << 11;
         4'b1100: data_o = data_i << 12;
         4'b1101: data_o = data_i << 13;
         4'b1110: data_o = data_i << 14;
         default: data_o = data_i << 15;
      endcase

endmodule



module sec_complement_w16 (         //2's complement calculation
    input [15:0] data_in,
    input sign,
    output [15:0] data_out
);
    
    wire [15:0] inverted_data;
    wire [15:0] sum;
    wire carry_out;

    // Invert data if sign is 1, otherwise pass data unchanged
    assign inverted_data = sign ? ~data_in : data_in;

    // Add 1 to the inverted data if sign is 1
    assign {carry_out, sum} = inverted_data + sign;

    // Assign the result to the output
    assign data_out = sum;

endmodule




module cpu_wb_cla_adder (in1, in2, carry_in, sum, carry_out); // carry_lookahead_adder
parameter DATA_WID = 32;

input [DATA_WID - 1:0] in1;
input [DATA_WID - 1:0] in2;
input carry_in;
output [DATA_WID - 1:0] sum;
output carry_out;

//assign {carry_out, sum} = in1 + in2 + carry_in;

wire [DATA_WID - 1:0] gen;
wire [DATA_WID - 1:0] pro;
wire [DATA_WID:0] carry_tmp;

genvar j, i;
generate
 //assume carry_tmp in is zero
 assign carry_tmp[0] = carry_in;
 
 //carry generator
 for(j = 0; j < DATA_WID; j = j + 1) begin: carry_generator
 assign gen[j] = in1[j] & in2[j];
 assign pro[j] = in1[j] | in2[j];
 assign carry_tmp[j+1] = gen[j] | pro[j] & carry_tmp[j];
 
 end
 
 //carry out 
 assign carry_out = carry_tmp[DATA_WID];
 
 //calculate sum 
 //assign sum[0] = in1[0] ^ in2 ^ carry_in;
 for(i = 0; i < DATA_WID; i = i+1) begin: sum_without_carry
 assign sum[i] = in1[i] ^ in2[i] ^ carry_tmp[i];
 end 
endgenerate 
endmodule

