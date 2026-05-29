//*******************************************************************//
// Project name         :
//
// File name            : pwm_clkgen.v
// Purpose              :
//*******************************************************************//
`timescale 1ns/10ps

module pwm_clkgen(
  input  wire       resetb,
  input  wire       clk,
              
  input  wire       i_prs_en,
  input  wire [7:0] i_prs,
  input  wire [2:0] i_clksel,
              
 // input  wire       i_dtz_en,
 // input  wire [1:0] i_dcksel,

 // output wire       o_dck,
  output wire       o_pwm_clk_en
);

//////////////////////////////////////////////////////////////////////
// SIGNALS
/////////////////////////////////////////////////////////////////////

wire w_pwm_clk_en;

// prescaler signals
wire div2_en,  div4_en,  div8_en,  div16_en,  div32_en,  div64_en;
wire div_cnt1, div_cnt3, div_cnt7, div_cnt15, div_cnt31, div_cnt63;

reg [7:0] pre_cnt;
reg [5:0] div_cnt;


//////////////////////////////////////////////////////////////////////
// LOGIC
/////////////////////////////////////////////////////////////////////

// prescaler logic
wire pre_cnt_end = &(~i_prs) ? 1'b1 : (pre_cnt == i_prs);
always @(posedge clk or negedge resetb) begin
  if(!resetb)       pre_cnt <= 8'h0;
  else if(i_prs_en) begin
    if(pre_cnt_end) pre_cnt <= 8'h0;
    else            pre_cnt <= pre_cnt + 1'b1;
  end
  else              pre_cnt <= 8'h0;
end

always @(posedge clk or negedge resetb) begin
  if(!resetb)       div_cnt <= 6'h0;
  else if(i_prs_en) begin
    if(pre_cnt_end) div_cnt <= div_cnt + 1'b1;
    else            div_cnt <= div_cnt;
  end
  else              div_cnt <= 6'h0;
end

assign div_cnt1  =   div_cnt[0];
assign div_cnt3  = &(div_cnt[1:0]);
assign div_cnt7  = &(div_cnt[2:0]);
assign div_cnt15 = &(div_cnt[3:0]);
assign div_cnt31 = &(div_cnt[4:0]);
assign div_cnt63 = &(div_cnt[5:0]);

assign div2_en   = pre_cnt_end & div_cnt1 ;  //div_cnt[0];
assign div4_en   = pre_cnt_end & div_cnt3 ;  //div_cnt[1];
assign div8_en   = pre_cnt_end & div_cnt7 ;  //div_cnt[2];
assign div16_en  = pre_cnt_end & div_cnt15;  //div_cnt[3];
assign div32_en  = pre_cnt_end & div_cnt31;  //div_cnt[4];
assign div64_en  = pre_cnt_end & div_cnt63;  //div_cnt[5];


// OUTPUT
wire w_clksel_zero = (i_clksel == 3'h0) ? 1 : 0 ;
assign o_pwm_clk_en = w_clksel_zero ? 1'b1 : w_pwm_clk_en ;

/*
//  `ifdef FPGA
//  //assign o_pwm_clk_en = w_clksel_zero ? clk : w_pwm_clk_en ;
//  `else
//  `ifdef LF13H
//  mx2d4_hd u_dont_pwm_clk (.D0(w_pwm_clk), .D1(clk), .S(w_clksel_zero), .Y(o_pwm_clk));
//  `else
//  `ifdef MX7T
//  MX2D4 u_dont_pwm_clk (.A(w_pwm_clk), .B(clk), .S0(w_clksel_zero), .Y(o_pwm_clk));
//  `else
//  MX2X4 u_dont_pwm_clk (.A(w_pwm_clk), .B(clk), .S0(w_clksel_zero), .Y(o_pwm_clk));
//  `endif
//  `endif
//  `endif
*/

assign w_pwm_clk_en = (i_clksel == 3'h6) ? div64_en :
                      (i_clksel == 3'h5) ? div32_en :
                      (i_clksel == 3'h4) ? div16_en :
                      (i_clksel == 3'h3) ? div8_en  :
                      (i_clksel == 3'h2) ? div4_en  :
                      (i_clksel == 3'h1) ? div2_en  : div64_en ; //clk ;

endmodule
