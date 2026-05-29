//*******************************************************************//
// Project name         :
//
// File name            : pwm_func.v
// Purpose              :
//*******************************************************************//
`timescale 1ns/10ps

module pwm_func(
  input wire         resetb,
  input wire         clk,

  //input wire         i_sm,             // scan mode
                  
  input wire         i_pwm_en,         // control0 reg[0]
  input wire [ 1:0]  i_mask,           // control0 reg[5:4]
  input wire         i_int_en,         // control0 reg[6]

  input wire         i_start,          // control1 reg[0]
  input wire         i_hold,           // control1 reg[1]
  //input wire         i_clear,          // control1 reg[2]

  input wire [15:0]  i_period,         // period reg
  input wire [15:0]  i_dncnt,          // down counter reg
  input wire [15:0]  i_upcnt,          // up counter reg

  //input wire         i_dtz_en,         // dead time zone reg[15]
  //input wire [ 1:0]  i_dcksel,         // dead time zone reg[9:8]
  input wire [14:0]  i_dtz,            // dead time zone reg

  input wire         i_pwm_clk_en,        // pwm clock
  //input wire         i_dck,            // dead time clock

  output wire        o_pwm,            // pwm output
  output wire        o_pwm_iv,         // pwm inverting output
  output wire        o_prd_end,        // period end signal
  output wire        o_prd_end_d,      // intertupt source
  output wire [15:0] o_counter         // current counter
);

///////////////////////////////////////////////////////////////
// PARAMETER
///////////////////////////////////////////////////////////////
parameter IDL = 2'h0;  // IDLE state
parameter CNT = 2'h1;  // Counting state
parameter UPD = 2'h2;  // Update state

///////////////////////////////////////////////////////////////
// SIGNALS
///////////////////////////////////////////////////////////////
reg  [ 2:0] r_nxt_state;
reg  [ 2:0] r_state;

reg  [15:0] r_counter; 
reg         r_start;
reg         r_pwm;   
reg         r_pwm_iv;

reg  [15:0] r_dt_cnt;      // dead time counter
reg  [15:0] r_dt_cnt_iv;
reg         r_dt_mask;     // mask time
reg         r_dt_mask_iv;  // mask time
reg         r_dt_on;       // dead time one

reg         r_pwm_d;
reg         r_pwm_iv_d;
reg         r_prd_end_d;

//wire        w_pwm_clk; // pwm clock
wire        w_prd_end; // period end signal

// Substractor logic
wire [16:0] w_prd_up_m = {1'h0,i_period} - {1'h0,i_upcnt};   // upcnt > period
wire [16:0] w_prd_dn_m = {1'h0,i_period} - {1'h0,i_dncnt};   // dncnt > period
wire [16:0] w_dn_up_m  = {1'h0,i_dncnt } - {1'h0,i_upcnt};   // upcnt > dncnt
wire [16:0] w_dt_du_m  = (w_dn_up_m[16]) ? 17'h10000 :             
                                                       w_dn_up_m - {2'h0,i_dtz};     // dt > down-up

wire [16:0] w_pd_dt_m  = {2'h0,w_prd_dn_m[14:0]} - {2'h0,i_dtz};  // dt > period-down 

// modified up & down counter values
wire [15:0] w_dncnt  = (w_prd_dn_m[16]) ? i_period         : i_dncnt; // down > period
//wire [14:0] w_dtz_iv = (w_pd_dt_m[16] ) ? w_prd_dn_m[14:0] : i_dtz;   // dt > period-down

// up & down counter positions
wire [15:0] w_upcnt_p  = (i_upcnt == 16'h0) ? 16'h0 :  i_upcnt-1;
wire [15:0] w_dncnt_p  = (w_dncnt == 16'h0) ? 16'h0 :  w_dncnt-1;
wire [15:0] w_dtz_p    = (i_dtz   == 15'h0) ? 16'h0 : {1'b0,i_dtz-1};

// OUTPUT stock at 1/0 signal
wire        w_zero = (i_period ==    16'h0) ? 1'b1 : 
                     (i_dncnt  ==    16'h0) ? 1'b1 :
                     (i_dncnt  == i_upcnt ) ? 1'b1 :
                     (i_upcnt  == i_period) ? 1'b1 :         // upcnt = period  
                     (w_prd_up_m[16])       ? 1'b1 :         // upcnt > period
                                                     1'b0 ;

wire        w_one  = (i_upcnt == 16'h0 & 
                        i_dtz == 15'h0 &                     // dtz = 0
                      w_dncnt == i_period ) ? 1'b1 :         // w_dncnt = period
                                                     1'b0 ;

///////////////////////////////////////////////////////////////
// FSM
///////////////////////////////////////////////////////////////
always @ (*) begin
   case(r_state)
      IDL :     r_nxt_state = (~i_pwm_en        ) ? IDL :
                              (i_period == 16'h0) ? IDL :
                              ( r_start         ) ? CNT : IDL ;

      CNT :     r_nxt_state = (~i_pwm_en) ? IDL : 
                              //( i_stop)   ? IDL :
                              (w_prd_end) ? UPD : CNT ;

      UPD :     r_nxt_state = (~i_pwm_en) ? IDL : CNT ;
                              //( i_stop)   ? IDL : CNT ;

      default : r_nxt_state = IDL;
   endcase
end

always @(posedge clk or negedge resetb) begin
   if(~resetb)           r_state <= 2'h0;
   else if(i_pwm_clk_en) r_state <= r_nxt_state;
end


///////////////////////////////////////////////////////////////
// LOGIC
///////////////////////////////////////////////////////////////

always @(posedge clk or negedge resetb) begin
   if(~resetb)             r_start <= 1'h0;
   else if(r_state != IDL) r_start <= 1'h0;
   else if(i_start)        r_start <= 1'h1;
end

// PWM Counter Period End signal
//  should consider after starting!!
//assign w_pwm_clk = i_sm ? clk : i_pwm_clk;
assign w_prd_end = (  r_state == CNT &
                    r_counter == i_period-1) ? 1'b1 :1'b0 ;

always @(posedge clk or negedge resetb) begin
   if(~resetb)                    r_counter <= 16'hffff;
   else if(i_pwm_clk_en) begin
      if(~i_pwm_en)               r_counter <= 16'hffff;
      else if(r_nxt_state == IDL) r_counter <= 16'hffff;
      else if(i_hold)             r_counter <= r_counter;
      else if(w_prd_end)          r_counter <= 16'h0;
      else if(r_nxt_state == CNT) r_counter <= r_counter + 1'b1;
   end
end

// Dead Time Counters
always @(posedge clk or negedge resetb) begin
   if(~resetb)                      r_dt_cnt <= 16'h0;
   else if(i_pwm_clk_en) begin
      if(~i_pwm_en)                 r_dt_cnt <= 16'h0;
      else if(r_nxt_state == IDL)   r_dt_cnt <= 16'h0; // state = IDL
      else if(    i_upcnt == 0 
                & r_state == IDL & 
              r_nxt_state == CNT  ) r_dt_cnt <= 16'h0; 
         else if(i_upcnt == 0 
                 & w_prd_end  )     r_dt_cnt <= 16'h0; // r_nxt_state = UPD & i_upcnt = 0
      else if(~r_dt_mask)           r_dt_cnt <= 16'h0;
      else if(r_dt_cnt == w_dtz_p)  r_dt_cnt <= 16'h0;
      else if(//r_nxt_state == CNT &
              r_dt_mask)            r_dt_cnt <= r_dt_cnt + 1;
   end
end

always @(posedge clk or negedge resetb) begin
   if(~resetb)                        r_dt_cnt_iv <= 16'h0;
   else if(i_pwm_clk_en) begin
      if(~i_pwm_en)                   r_dt_cnt_iv <= 16'h0;
      else if(~r_nxt_state[0])        r_dt_cnt_iv <= 16'h0; // state = IDL | UPB
      else if(~r_dt_mask_iv)          r_dt_cnt_iv <= 16'h0;
      else if(r_dt_cnt_iv == w_dtz_p) r_dt_cnt_iv <= 16'h0;
      else if(r_nxt_state == CNT &
              r_dt_mask_iv)           r_dt_cnt_iv <= r_dt_cnt_iv + 1;
   end
end

// Dead Time Mask signals
always @(posedge clk or negedge resetb) begin
   if(~resetb)                                     r_dt_mask <= 1'b0;
   else if(i_pwm_clk_en) begin
      if(~i_pwm_en)                                r_dt_mask <= 1'b0;
      else if(i_dtz == 15'h0)                      r_dt_mask <= 1'b0;
      else if(w_one | w_zero)                      r_dt_mask <= 1'b0;
      else if(r_nxt_state == IDL)                  r_dt_mask <= 1'b0;
      else if(i_upcnt == 0   &       i_dtz != 0 & 
              r_state == IDL & r_nxt_state == CNT) r_dt_mask <= 1'b1; // r_nxt_state = CNT & deadtime > 0
      else if(i_upcnt == 0   & w_prd_end)          r_dt_mask <= 1'b1; // r_nxt_state = UPD & i_upcnt = 0
      else if(w_prd_end)                           r_dt_mask <= 1'b0;
      else if( r_dt_cnt == w_dtz_p & r_dt_mask)    r_dt_mask <= 1'b0;
      else if(r_counter == w_upcnt_p)              r_dt_mask <= 1'b1;
   end
end
      
always @(posedge clk or negedge resetb) begin
   if(~resetb)                    r_dt_mask_iv <= 1'b0;
   else if(i_pwm_clk_en) begin
      if(~i_pwm_en)               r_dt_mask_iv <= 1'b0;
      else if(i_dtz == 15'h0)     r_dt_mask_iv <= 1'b0;
      else if(w_one | w_zero)     r_dt_mask_iv <= 1'b0;
      else if(r_nxt_state == IDL) r_dt_mask_iv <= 1'b0;
      else if(w_prd_end)          r_dt_mask_iv <= 1'b0;
      else if(r_dt_mask_iv &   r_counter != w_dncnt_p & w_dtz_p == 0) r_dt_mask_iv <= 1'b0;
      else if(                 r_counter == w_dncnt_p & w_dtz_p == 0) r_dt_mask_iv <= 1'b1;  // i_dtz == 1 & r_count == 0 ??
      else if(r_dt_mask_iv & r_dt_cnt_iv == w_dtz_p                 ) r_dt_mask_iv <= 1'b0;
      else if(                 r_counter == w_dncnt_p               ) r_dt_mask_iv <= 1'b1;
   end
end
   
always @(posedge clk or negedge resetb) begin
   if(~resetb)                                   r_dt_on <= 1'b0;
   else if(i_pwm_clk_en) begin
      if(i_dtz == 0)                             r_dt_on <= 1'b0;
      else if(r_nxt_state == IDL | w_prd_end)    r_dt_on <= 1'b0;
      else if( r_dt_on & r_counter == w_dncnt_p) r_dt_on <= 1'b0;
      else if(~r_dt_on & r_counter == w_upcnt_p) r_dt_on <= 1'b1;
   end
end

// PWM signals generator
always @(posedge clk or negedge resetb) begin
   if(~resetb)                         r_pwm <= 1'b0;
   else if(i_pwm_clk_en) begin
      if(~i_pwm_en)                    r_pwm <= 1'b0;
      else if(i_mask[0])               r_pwm <= 1'b0;
      else if(w_zero)                  r_pwm <= 1'b0;
      else if(w_one)                   r_pwm <= 1'b1;
      else if(~r_nxt_state[0]) begin                   // state = UPD | IDL
         if(i_upcnt == 0)              r_pwm <= 1'b1;  // corner case
         else                          r_pwm <= 1'b0;
      end
      else if(i_upcnt == 0 &
              i_dncnt == 1 & 
                i_dtz == 1  )          r_pwm <= 1'b0; // start with 0 but dtz is 1 & dncnt is 1
      else if(r_counter == w_dncnt_p)  r_pwm <= 1'b0;
      else if(r_counter == w_upcnt_p)  r_pwm <= 1'b1;
   end
end

always @(posedge clk or negedge resetb) begin
   if(~resetb)                        r_pwm_iv <= 1'b1;
   else if(i_pwm_clk_en) begin
      if(~i_pwm_en)                   r_pwm_iv <= 1'b1;
      else if(i_mask[1])              r_pwm_iv <= 1'b0;  // 1'b1 ??
      else if(w_zero)                 r_pwm_iv <= 1'b1;
      else if(w_one)                  r_pwm_iv <= 1'b0;
      else if(~r_nxt_state[0]) begin                     // state = UPD | IDL
         if(i_upcnt == 0)             r_pwm_iv <= 1'b0;  // corner case
         else                         r_pwm_iv <= 1'b1;
      end
      else if(  i_upcnt == 0 & 
                i_dncnt == 1 & 
                i_dtz   == 1 & 
              r_counter == 0        ) r_pwm_iv <= 1'b1; // start with 0 but dtz is 1 & dncnt is 1
      else if(r_counter == w_dncnt_p) r_pwm_iv <= 1'b1;
      else if(r_counter == w_upcnt_p) r_pwm_iv <= 1'b0;
   end
end

// registers for OUTPUT
always @(posedge clk or negedge resetb) begin
   if(~resetb)           r_pwm_d <= 1'b0;
   else if(i_pwm_clk_en) r_pwm_d <= ~r_dt_mask & r_pwm;
end

always @(posedge clk or negedge resetb) begin
   if(~resetb)           r_pwm_iv_d <= 1'b0;
   else if(i_pwm_clk_en) r_pwm_iv_d <= ~r_dt_mask_iv & r_pwm_iv;
end

always @(posedge clk or negedge resetb) begin
   if(~resetb)           r_prd_end_d <= 1'b0;
   else if(i_pwm_clk_en) r_prd_end_d <= w_prd_end;
end

reg [15:0] r_counter_d;
always @(posedge clk or negedge resetb) begin
   if(~resetb)           r_counter_d <= 16'h0;
   else if(i_pwm_clk_en) r_counter_d <= r_counter;
end

///////////////////////////////////////////////////////////////
// OUTPUT
///////////////////////////////////////////////////////////////
assign o_pwm       = r_pwm_d;
assign o_pwm_iv    = r_pwm_iv_d;
assign o_counter   = r_counter;
assign o_prd_end   = w_prd_end;
assign o_prd_end_d = r_prd_end_d;

// for test
wire w_pwm    = ~r_dt_mask    & r_pwm;
wire w_pwm_iv = ~r_dt_mask_iv & r_pwm_iv;



endmodule
