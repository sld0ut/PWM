//*******************************************************************//
// Project name         :
//
// File name            : pwm_top.v
// Purpose              :
//*******************************************************************//
`timescale 1ns/10ps

module pwm_top (
  input  wire          clk,
  input  wire          clk_cg,
  input  wire          resetb,

  input  wire          psel,
  input  wire  [ 4:0]  paddr,    // <-- PADDR[6:2]  : 5 bit
  input  wire          penable,
  input  wire          pwrite,
  input  wire  [31:0]  pwdata,   // <--
  output wire  [31:0]  prdata,   // -->

  input  wire  [ 3:0]  pstrb,
  input  wire          i_sm,          // scan mode

  input  wire          i_sync_start,
  output wire          o_sync_start,
  input  wire          i_sync_pwm_en,
  output wire          o_sync_pwm_en,

  output wire          o_pwm,
  output wire          o_pwm_iv,
  output wire          o_pwm_int
);


///////////////////////////////////////////////////////////////
// WIRE
///////////////////////////////////////////////////////////////
wire           w_prd_end;
wire           w_prd_end_d;
                          
wire           w_pwm_en; 
wire  [ 2:0]   w_clksel; 
wire  [ 1:0]   w_mask;   
wire           w_int_en; 
                          
wire           w_start;  
wire           w_hold;   
//wire           w_clear;  
                          
wire           w_prs_en; 
wire  [ 7:0]   w_prs;    
                          
wire  [15:0]   w_period; 
wire  [15:0]   w_counter;
wire  [15:0]   w_dncnt;  
wire  [15:0]   w_upcnt;  
                          
wire  [14:0]   w_dtz;    
wire           w_pwm_clk_en;

///////////////////////////////////////////////////////////////
// INSTANCIATION
///////////////////////////////////////////////////////////////
pwm_func u_pwm_func(
  /*input wire          */   .resetb         (resetb      ),
  /*input wire          */   .clk            (clk         ),

  ///*input wire          */   .i_sm           (i_sm        ),     // scan mode

  /*input wire          */   .i_pwm_en       (w_pwm_en    ),     // control reg[0]
  /*input wire   [ 1:0] */   .i_mask         (w_mask      ),     // control reg[5:4]
  /*input wire          */   .i_int_en       (w_int_en    ),     // control reg[6]

  /*input wire          */   .i_start        (w_start     ),     // cmd reg[0]
  /*input wire          */   .i_hold         (w_hold      ),     // cmd reg[1]
  ///*input wire          */   .i_clear      (1'b0          ), //w_clear),       // cmd reg[2]

  /*input wire   [15:0] */   .i_period       (w_period    ),     // period reg[14:0]
  /*input wire   [15:0] */   .i_dncnt        (w_dncnt     ),     // down counter reg[14:0]
  /*input wire   [15:0] */   .i_upcnt        (w_upcnt     ),     // up counter reg[14:0]

  /*input wire   [14:0] */   .i_dtz          (w_dtz       ),     // dead time zone reg[7:0]

  /*input wire          */   .i_pwm_clk_en   (w_pwm_clk_en   ),     // pwm clock

  /*output wire         */   .o_pwm       (o_pwm       ),     // pwm output
  /*output wire         */   .o_pwm_iv    (o_pwm_iv    ),     // pwm inverting output
  /*output wire         */   .o_prd_end   (w_prd_end   ),     // period end signal
  /*output wire         */   .o_prd_end_d (w_prd_end_d ),     // interrupt source
  /*output wire  [15:0] */   .o_counter   (w_counter   )      // current counter
);

pwm_reg u_pwm_reg(
  /* input wire          */  .clk           (clk           ),
  /* input wire          */  .clk_cg     	(clk_cg			),
  /* input wire          */  .resetb        (resetb        ),
  
  /* input wire          */  .psel          (psel          ),
  /* input wire   [ 4:0] */  .paddr         (paddr         ),    // <-- PADDR[7:2]  : 6 bit
  /* input wire          */  .penable       (penable       ),
  /* input wire          */  .pwrite        (pwrite        ),
  /* input wire   [31:0] */  .pwdata        (pwdata        ),    // <--
  /* output wire  [31:0] */  .prdata        (prdata        ),    // -->
  
  /* input  wire         */  .i_prd_end     (w_prd_end     ),    // period end
  /* input  wire         */  .i_prd_end_d   (w_prd_end_d   ),    // interrupt source
  /* input  wire  [ 3:0] */  .pstrb			(pstrb		   ),
  /* output wire         */  .o_pwm_int     (o_pwm_int     ),
  
  /* output wire         */  .o_pwm_en      (w_pwm_en      ),    // control reg[0]
  /* output wire  [ 2:0] */  .o_clksel      (w_clksel      ),    // control reg[3:1]
  /* output wire  [ 1:0] */  .o_mask        (w_mask        ),    // control reg[5:4]
  /* output wire         */  .o_int_en      (w_int_en      ),    // control reg[6]

  /* input  wire         */  .i_sync_start  (i_sync_start  ),    
  /* output wire         */  .o_sync_start  (o_sync_start  ),   
  /* input  wire         */  .i_sync_pwm_en (i_sync_pwm_en ),  
  /* output wire         */  .o_sync_pwm_en (o_sync_pwm_en ), 

  /* output wire         */  .o_start       (w_start       ),    // cmd reg[0]
  /* output wire         */  .o_hold        (w_hold        ),    // cmd reg[1]
  ///* output wire         */  .o_clear      (w_clear),        // cmd reg[2]

  /* output wire         */  .o_prs_en      (w_prs_en      ),    // prescaler reg[?]
  /* output wire  [ 7:0] */  .o_prs         (w_prs         ),    // prescaler reg[7:0]
  
  /* output wire  [15:0] */  .o_period      (w_period      ),    // period reg
  /* input  wire  [15:0] */  .i_counter     (w_counter     ),    // current counter reg 
  /* output wire  [15:0] */  .o_dncnt       (w_dncnt       ),    // down counter reg
  /* output wire  [15:0] */  .o_upcnt       (w_upcnt       ),    // up counter reg

  /* output wire  [14:0] */  .o_dtz         (w_dtz         )     // dead time zone reg[7:0]
);

pwm_clkgen u_pwm_clkgen(
  /* input  wire         */  .resetb       (resetb   ),
  /* input  wire         */  .clk          (clk      ),
              
  /* input  wire         */  .i_prs_en     (w_prs_en ),  // prescaler reg[15]  
  /* input  wire  [ 7:0] */  .i_prs        (w_prs    ),  // prescaler reg[7:0]
  /* input  wire  [ 2:0] */  .i_clksel     (w_clksel ),  // control reg[3:1]
              
  /* output wire         */  .o_pwm_clk_en (w_pwm_clk_en)
);


endmodule
