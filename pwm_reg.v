//*******************************************************************//
// Project name         :
//
// File name            : pwm_reg.v
// Purpose              :
//*******************************************************************//
`timescale 1ns/10ps

module pwm_reg(
  input wire           clk          ,
  input wire           clk_cg		,
  input wire           resetb       ,
  
  input wire           psel         ,
  input wire   [ 4:0]  paddr        ,    // <-- PADDR[7:2]  : 6 bit
  input wire           penable      ,
  input wire           pwrite       ,
  input wire   [31:0]  pwdata       ,    // <--
  input wire   [ 3:0]  pstrb		,
  output wire  [31:0]  prdata       ,    // -->
  
  input  wire          i_prd_end    ,
  input  wire          i_prd_end_d  ,
  output wire          o_pwm_int    ,
  
  output wire          o_pwm_en     ,    // control reg[0]
  output wire  [ 2:0]  o_clksel     ,    // control reg[3:1]
  output wire  [ 1:0]  o_mask       ,    // control reg[5:4]
  output wire          o_int_en     ,    // control reg[6]

  input  wire          i_sync_start ,
  output wire          o_sync_start , 
  input wire           i_sync_pwm_en, 
  output wire          o_sync_pwm_en, 

  output wire          o_start      ,    // cmd reg[0]
  output wire          o_hold       ,    // cmd reg[1]

  output wire          o_prs_en     ,    // prescaler reg[?]
  output wire  [ 7:0]  o_prs        ,    // prescaler reg[7:0]
  
  output wire  [15:0]  o_period     ,    // period reg
  input  wire  [15:0]  i_counter    ,    // current counter reg 
  output wire  [15:0]  o_dncnt      ,    // down counter reg
  output wire  [15:0]  o_upcnt      ,    // up counter reg

  output wire  [14:0]  o_dtz             // dead time zone reg[15:0]
);

/////////////////////////////////////////////////////////////////////////////////////////
// PARAMETERS
/////////////////////////////////////////////////////////////////////////////////////////
// PWM Timer output
parameter PWM_CTRL  = 5'h00;  //0x00
parameter PWM_CMD   = 5'h01;  //0x04
parameter PWM_STS   = 5'h02;  //0x08
parameter PWM_PRS   = 5'h03;  //0x0c
parameter PWM_PRD   = 5'h04;  //0x10
parameter PWM_CNT   = 5'h05;  //0x14
parameter PWM_DCNT  = 5'h06;  //0x18
parameter PWM_DTZ   = 5'h07;  //0x1c
parameter PWM_UCNT  = 5'h08;  //0x20
parameter PWM_SUP	= 5'h09;  //0x24

/////////////////////////////////////////////////////////////////////////////////////////
//						REG / WIRE
/////////////////////////////////////////////////////////////////////////////////////////

reg           r_pwm_en  ;  // control0 reg[0]
reg   [ 2:0]  r_clksel  ;  // control0 reg[3:1]
reg   [ 1:0]  r_mask    ;  // control0 reg[5:4]
reg           r_int_en  ;  // control0 reg[6]
reg           r_sync    ;  // control0 reg[7]
reg           r_sync_md	;  // control0 reg[8]

reg           r_start   ;  // cmd reg[0]
reg           r_hold    ;  // cmd reg[1]

reg           r_int_flg ;  // status reg[0

reg   [ 7:0]  r_prs     ;  // prescaler reg[7:0]

reg   [15:0]  r_period  ;  // period reg
reg   [15:0]  r_dncnt   ;  // down counter reg
reg   [15:0]  r_upcnt   ;  // up counter reg

reg   [14:0]  r_dtz     ;  // dead time zone reg[15:0]

reg			  r_sup		;	// Sync Update Reg

// double buffered register bits
reg   [ 2:0]  r_clksel_d;  // control0 reg[3:1]
reg   [ 1:0]  r_mask_d  ;  // control0 reg[5:4]
reg           r_int_en_d;  // control0 reg[6]
reg           r_start_d1;  // cmd reg[0]

reg   [ 7:0]  r_prs_d   ;  // prescaler reg[7:0]

reg   [15:0]  r_period_d;  // period reg
reg   [15:0]  r_dncnt_d ;  // down counter reg
reg   [15:0]  r_upcnt_d ;  // up counter reg

reg   [14:0]  r_dtz_d   ;  // dead time zone reg[15:0]

reg   [15:0]  r_read_data;

wire          w_wren;
wire          w_rden;

wire          pwm_ctrl_wen;
wire          pwm_cmd_wen ;
wire          pwm_sts_wen ;
wire          pwm_prs_wen ;
wire          pwm_prd_wen ;
wire          pwm_dcnt_wen;
wire          pwm_dtz_wen ;
wire          pwm_ucnt_wen;
wire          pwm_sup_wen;

reg [1:0]		prd_end_lat;
wire			w_prd_end_r;
wire			w_prd_end_f;
reg	[1:0]	sync_update;
reg			r_prs_en;

/////////////////////////////////////////////////////////////////////////////////////////
//  OUTPUT ASSIGN
/////////////////////////////////////////////////////////////////////////////////////////

assign prdata        = {16'h0, r_read_data};

assign o_pwm_en      = (r_sync) ? i_sync_pwm_en : r_pwm_en;    // control reg[0]
assign o_clksel      = r_clksel_d;                             // control reg[3:1]
assign o_mask        = r_mask_d  ;                             // control reg[5:4]
assign o_int_en      = r_int_en_d;                             // control reg[6]

assign o_start       = r_start_d1;  // cmd reg[0]
assign o_hold        = r_hold    ;  // cmd reg[1]

assign o_pwm_int     = r_int_flg ;  // interrupt

assign o_prs         = r_prs_d   ;  // prescaler reg[7:0]

assign o_period      = r_period_d;  // period reg
assign o_dncnt       = r_dncnt_d ;  // down counter reg
assign o_dtz         = r_dtz_d   ;  // dead time zone reg[15:0]
assign o_upcnt       = r_upcnt_d ;  // up counter reg

assign o_sync_start  = r_start & r_sync;
assign o_sync_pwm_en = r_pwm_en & r_sync;

assign o_prs_en      = (r_sync) ? r_prs_en : 1'b1;

/////////////////////////////////////////////////////////////////////////////////////////
//	APB SIGNAL
/////////////////////////////////////////////////////////////////////////////////////////

assign w_wren        = psel &  penable &  pwrite;
assign w_rden        = psel & ~penable & ~pwrite;

assign pwm_ctrl_wen  = w_wren & (paddr == PWM_CTRL );  //0x00
assign pwm_cmd_wen   = w_wren & (paddr == PWM_CMD  );  //0x04
assign pwm_sts_wen   = w_wren & (paddr == PWM_STS  );  //0x08
assign pwm_prs_wen   = w_wren & (paddr == PWM_PRS  );  //0x0c
assign pwm_prd_wen   = w_wren & (paddr == PWM_PRD  );  //0x10

assign pwm_dcnt_wen  = w_wren & (paddr == PWM_DCNT );  //0x18
assign pwm_dtz_wen   = w_wren & (paddr == PWM_DTZ  );  //0x1c
assign pwm_ucnt_wen  = w_wren & (paddr == PWM_UCNT );  //0x20
assign pwm_sup_wen   = w_wren & (paddr == PWM_SUP );   //0x24

/////////////////////////////////////////////////////////////////////////////////////////
//	REGISTER WRITE
/////////////////////////////////////////////////////////////////////////////////////////
always @(posedge clk or negedge resetb) begin
   if(~resetb)     r_start_d1 <= 1'b0;
   else if(r_sync) r_start_d1 <= i_sync_start;
   else            r_start_d1 <= r_start;
end

always @(posedge clk or negedge resetb)
   if(~resetb) begin
	  prd_end_lat <= 'd0;
   end else if (o_pwm_en) begin
	  prd_end_lat <= {prd_end_lat[0],i_prd_end};
   end
assign w_prd_end_r = (prd_end_lat[1]==1'b0 & prd_end_lat[0]==1'b1);
assign w_prd_end_f = (prd_end_lat[1]==1'b1 & prd_end_lat[0]==1'b0);

// double buffers for update
always @(posedge clk or negedge resetb) begin
   if(~resetb) begin
      r_clksel_d <= 3'h0; 
      r_mask_d   <= 2'h0; 
      r_int_en_d <= 1'h0;
                
      r_prs_d    <= 8'h00;

      r_period_d <= 16'h0000;
      r_dncnt_d  <= 16'h0000;
                
      r_dtz_d    <= 15'h0000;  

	  r_prs_en	<= 'd0;
   end
//   else if((i_sync_start & r_sync) | r_start | i_prd_end)begin
   else if( (r_sync==1'b1 && i_sync_start && r_sync_md==1'b1 && sync_update==2'd2) ||
   			(r_sync==1'b1 && i_sync_start && r_sync_md==1'b0) ||
			(r_sync==1'b0 && i_prd_end) || 
			(r_sync==1'b0 && r_start)) begin
      r_clksel_d <= r_clksel;
      r_mask_d   <= r_mask  ;
      r_int_en_d <= r_int_en;
                          
      r_prs_d    <= r_prs;

      r_period_d <= r_period;
      r_dncnt_d  <= r_dncnt ;
                          
      r_dtz_d    <= r_dtz   ;
	  r_prs_en	<= 'd1;
   end else if (o_pwm_en==1'b0) begin
	  r_prs_en	<= 'd0;
   end
end

`ifdef UPCNT_ZERO
always @ (*) begin
   if(o_pwm_en) r_upcnt_d = {16{~o_pwm_en}};
   else         r_upcnt_d = 16'h0;
end
`else
always @(posedge clk or negedge resetb) begin
  if(!resetb)    r_upcnt_d  <= 16'h0 ;
//else if((i_sync_start & r_sync) | r_start | i_prd_end)
   else if( (r_sync==1'b1 && i_sync_start && r_sync_md==1'b1 && sync_update==2'd2) ||
   			(r_sync==1'b1 && i_sync_start && r_sync_md==1'b0) ||
			(r_sync==1'b0 && i_prd_end) || 
			(r_sync==1'b0 && r_start))
                 r_upcnt_d  <= r_upcnt ;
end
`endif

// control register
always @(posedge clk_cg or negedge resetb) begin
	if(!resetb) begin
		r_sync_md<= 1'h0;  
		r_sync   <= 1'h0;  
		r_int_en <= 1'h0;
		r_mask   <= 2'h0;
		r_clksel <= 3'h0;
		r_pwm_en <= 1'h0;
	end
	else if(pwm_ctrl_wen) begin
		if(pstrb[3]) begin
		end
		if(pstrb[2]) begin
		end
		if(pstrb[1]) begin
			r_sync_md<= pwdata[8];    // control0 reg[8]
		end
		if(pstrb[0]) begin
			r_sync   <= pwdata[7];    // control0 reg[7]
			r_int_en <= pwdata[6];    // control0 reg[6]
			r_mask   <= pwdata[5:4];  // control0 reg[5:4]
			r_clksel <= pwdata[3:1];  // control0 reg[3:1]
			r_pwm_en <= pwdata[0];    // control0 reg[0]
		end
	end
end

reg			r_start_p;
reg			r_hold_p;
// command register
always @(posedge clk_cg or negedge resetb) begin
	if(!resetb) begin
		r_start_p <= 1'h0;   
		r_hold_p  <= 1'h0;   
	end else if(pwm_cmd_wen) begin
		if(pstrb[3]) begin
		end
		if(pstrb[2]) begin
		end
		if(pstrb[1]) begin
		end
		if(pstrb[0]) begin
			r_start_p <= pwdata[0];    // cmd reg[0]
			r_hold_p  <= pwdata[1];    // cmd reg[1]
		end
	end else begin	
		r_start_p <= 1'b0;
	end
end

always @(posedge clk or negedge resetb) begin
	if(!resetb) begin
		r_start <= 1'h0;   
		r_hold  <= 1'h0;   
	end else if(r_sync && r_sync_md) begin
		r_start <= w_prd_end_r;	// re-start condition
	end else begin
		//r_start <= 1'h0;		// write_only
		r_start <= r_start_p;
		r_hold  <= r_hold_p;       
	end
end

// status register
always @(posedge clk or negedge resetb) begin
  if(!resetb)                     r_int_flg <= 1'b0;  // status reg[0]
  else if(pwm_sts_wen)            r_int_flg <= 1'b0;  // status reg[0]
  else if(o_int_en & i_prd_end_d) r_int_flg <= 1'b1;  // status reg[0]
end

// prescale register
always @(posedge clk_cg or negedge resetb) begin
  if(!resetb)          r_prs <= 8'h00;    
  else if(pwm_prs_wen) begin
  		if(pstrb[3]) begin
		end
		if(pstrb[2]) begin
		end
		if(pstrb[1]) begin
		end
		if(pstrb[0]) begin
			r_prs <=  pwdata[7:0]; // prescaler reg[7:0]
		end
	end
end

// period register
always @(posedge clk_cg or negedge resetb) begin
  if(!resetb)          r_period <= 16'h0000;      
  else if(pwm_prd_wen) begin
  	  	if(pstrb[3]) begin
		end
		if(pstrb[2]) begin
		end
		if(pstrb[1]) begin
			r_period[15:8] <= pwdata[15:8];  // period reg[15:0]
		end
		if(pstrb[0]) begin
			r_period[7:0]  <= pwdata[7:0];  // period reg[15:0]
		end
	end
end

// down counter register
always @(posedge clk_cg or negedge resetb) begin
  if(!resetb)           r_dncnt <= 16'h0000;
  else if(pwm_dcnt_wen) begin
    	if(pstrb[3]) begin
		end
		if(pstrb[2]) begin
		end
		if(pstrb[1]) begin
			r_dncnt[15:8] <= pwdata[15:8];  // period reg[15:0]
		end
		if(pstrb[0]) begin
			r_dncnt[7:0]  <= pwdata[7:0];  // period reg[15:0]
		end
	end
end

// dead time zone register
always @(posedge clk_cg or negedge resetb) begin
  if(!resetb)          r_dtz <= 15'h0000;     
  else if(pwm_dtz_wen) begin     	
  		if(pstrb[3]) begin
		end
		if(pstrb[2]) begin
		end
		if(pstrb[1]) begin
			r_dtz[14:8] <= pwdata[14:8];  // period reg[15:0]
		end
		if(pstrb[0]) begin
			r_dtz[7:0]  <= pwdata[7:0];  // period reg[15:0]
		end
	end
end

// up dounter register
`ifdef UPCNT_ZERO
always @ (*) begin
   if(r_pwm_en) r_upcnt = {16{~r_pwm_en}};
   else         r_upcnt = 16'h0;
end
`else
always @(posedge clk_cg or negedge resetb) begin
  if(!resetb)           r_upcnt <= 16'h0000;
  else if(pwm_ucnt_wen) begin
      	if(pstrb[3]) begin
		end
		if(pstrb[2]) begin
		end
		if(pstrb[1]) begin
			r_upcnt[15:8] <= pwdata[15:8];  // period reg[15:0]
		end
		if(pstrb[0]) begin
			r_upcnt[7:0]  <= pwdata[7:0];  // period reg[15:0]
		end
	end
end
`endif

// sync update register
always @(posedge clk_cg or negedge resetb)
  if(!resetb)          r_sup <= 1'b0;     
  else if(pwm_sup_wen) begin
  	    if(pstrb[3]) begin
		end
		if(pstrb[2]) begin
		end
		if(pstrb[1]) begin
		end
		if(pstrb[0]) begin
			r_sup <= pwdata[0];    // sync update reg[0]
		end
  end else	r_sup <= 1'b0;

always @(posedge clk or negedge resetb)
  if(!resetb)          sync_update <= 'd0;
  else if (r_sync && r_sync_md) begin
  	if (sync_update==2'd0 && r_sup) begin
		if (i_prd_end) begin
			sync_update <= 2'd1;
		end else begin
			sync_update <= 2'd2;
		end
	end
	else if (sync_update==2'd1 && i_prd_end==1'b0)	sync_update <= 2'd2;
	else if (sync_update==2'd2 && i_sync_start)		sync_update <= 2'd0;
  end

/////////////////////////////////////////////////////////////////////////////////////////
//	REGISTER READ
/////////////////////////////////////////////////////////////////////////////////////////
always @(posedge clk or negedge resetb) begin
  if(!resetb)       r_read_data <= 16'h0;
  else begin
    if( w_rden ) begin
      case(paddr)
        PWM_CTRL  : r_read_data <= {7'h00, r_sync_md, r_sync, r_int_en, r_mask, r_clksel, r_pwm_en}; // control reg
        PWM_CMD   : r_read_data <= {8'h00,    6'h0,   r_hold,   r_start};                            // cmd reg
        PWM_STS   : r_read_data <= {15'h0000,         r_int_flg};                                    // status reg
        PWM_PRS   : r_read_data <= {8'h00,    r_prs};                                                // prescaler reg
        PWM_PRD   : r_read_data <=  r_period;                                                        // period reg
        PWM_CNT   : r_read_data <=  i_counter;                                                       // current counter reg
        PWM_DCNT  : r_read_data <=  r_dncnt;                                                         // down conter reg
        PWM_DTZ   : r_read_data <= {1'h0,     r_dtz};                                                // dead time zone reg
        PWM_UCNT  : r_read_data <=  r_upcnt;                                                         // up counter reg
        default   : r_read_data <=  16'h0;
      endcase
    end
  end
end

endmodule
