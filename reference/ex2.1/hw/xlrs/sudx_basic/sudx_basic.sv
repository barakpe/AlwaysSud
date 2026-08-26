import xbox_def_pkg::*;
import sudx_def_pkg::*;
import sud_pkg::*;      // from week-1/hw1: BOARD_DIM, BOX_DIM, CELL_W,
                        // board_t, and the grp_row/grp_col group indexing

module sudx_basic (
  input   clk,
  input   rst_n,  
 
  // Command Status Register Interface
  host_regs_intrf.xlr host_regs_intrf, 

  // muxed interfaces
  mem_intf_read.client_read   mem_intf_read,
  mem_intf_write.client_write mem_intf_write
);

  enum {IDLE, 
        LOAD,
        CHECK,       // Check Validity
        CLEAR,       // clear cell
        DONE
       } next_state, state; //state machine 

  // MUST BE SAME AS SW , notice unlike C the first maos to msb
    
    typedef struct packed {
           logic [7:0] num ; 
           logic [7:0] row ;           
           logic [7:0] col ; 
           logic [7:0] cmd ;                            
    } start_reg_t;
           
    typedef struct packed {
           logic [15:0] unused ; 
           logic  [7:0] result ;            
           logic  [7:0] status ;          
    } done_reg_t;
     
          
  // BOARD_DIM (9) and BOX_DIM (3) now come from sud_pkg - one source of truth
  // for the board geometry, shared with the hw1 modules.
  localparam MUM_BOARD_ELEM = BOARD_DIM*BOARD_DIM ; 
   
  logic sudx_start;  
  start_reg_t start_reg;    
  logic clear_done_on_read;
  
  logic [5:0] num_bytes_requested ;
  
  sudx_cmd_t sudx_cmd ;
  
    
  logic [XMEM_ADDR_WIDTH-1:0] xmem_board_addr ;
  logic [$clog2(MUM_BOARD_ELEM)-1:0] loaded_start_idx , next_load_start_idx;
  
  logic [$clog2(BOARD_DIM)-1:0]  cmd_col, cmd_row, cmd_num ;
  
  logic is_legal, is_legal_ps ;
  
  done_reg_t done_reg  ;
  
  //--------------------------------------------------------------------------------------------------------
  

  // Internal board, each bit in element represent a nibble per index 
  // Notice this is different then the SW representation in xmem where each element is held in a byte
  logic [BOARD_DIM-1:0][BOARD_DIM-1:0][3:0] board, board_ps ; // sampled, and pre-sampled

  logic [MUM_BOARD_ELEM-1:0][3:0] board_flat_ps ; // for load convenience
    
  //--------------------------------------------------------------------------------------------------------
  
  // Host Regs Interface 
   
  assign sudx_start          = host_regs_intrf.host_regs_valid_pulse[XLR_START_RI] ; 
  assign start_reg           = start_reg_t'(host_regs_intrf.host_regs[XLR_START_RI]);
  assign sudx_cmd            = sudx_cmd_t'(start_reg.cmd[$clog2(NUM_SUDX_CMDS)-1:0])  ;  
  assign clear_done_on_read  = host_regs_intrf.host_regs_read_pulse[XLR_DONE_RI] ; 

  assign xmem_board_addr     = host_regs_intrf.host_regs[XMEM_BOARD_ADDR_RI]; 
 
  //======================================================================================================== 
 
  //State Machine Comb (most simple non-piped implementation)  
  always_comb begin
  
   // State-Machine Comb logic outputs defaults 

   next_state = state;
   
   next_load_start_idx = loaded_start_idx + num_bytes_requested;

   mem_intf_read.mem_size_bytes  = 32;              // default assuming MUM_BOARD_ELEM>32  
   mem_intf_read.mem_start_addr  = xmem_board_addr; // default board xmem address 
   mem_intf_read.mem_req = 0;
    
   // Initially accelerator does not write back to xmem
   mem_intf_write.mem_size_bytes = 0;
   mem_intf_write.mem_data       = 0;
   mem_intf_write.mem_start_addr = 0;
   mem_intf_write.mem_req        = 0;   
   
   //  default host regs output 
   host_regs_intrf.host_regs_data_out  = 0 ;
   host_regs_intrf.host_regs_valid_out = 0 ;
  
   board_ps = board;
   board_flat_ps = board;
   
   done_reg = 0 ;
   
   is_legal_ps = is_legal;
   
   case (state) // State Machine case
    
      IDLE: if (sudx_start) begin
       if      (sudx_cmd==SETUP) next_state = LOAD;           // Setup only, loading board, pending for execution
       else if (sudx_cmd==CHECK_LEGAL) next_state = CHECK;    // Check Validity  
       else if (sudx_cmd==CLEAR_CELL)  next_state = CLEAR;    // Clear cell  
      end
      
      LOAD: begin // Loading board from XMEM , in case of 9X9=81 elements it is 3 transactions: 32+32+17

        mem_intf_read.mem_req = 1;          
        mem_intf_read.mem_start_addr = xmem_board_addr + next_load_start_idx ;  
      
        if (mem_intf_read.mem_valid) begin
          integer i;
          for (i=0;i<32;i++) begin  
             if ((loaded_start_idx+i) < MUM_BOARD_ELEM) 
               board_flat_ps[loaded_start_idx+i] = mem_intf_read.mem_data[i][3:0] ;               
          end
          
          board_ps = board_flat_ps;
                                        
          if ((next_load_start_idx+32) >= MUM_BOARD_ELEM) // Overwrite default 32
            mem_intf_read.mem_size_bytes = MUM_BOARD_ELEM - next_load_start_idx ;   
          
          if (next_load_start_idx == MUM_BOARD_ELEM)  begin                       
            next_state = DONE;   
            mem_intf_read.mem_req = 0;            
          end
                                     
        end // if (mem_intf_read.mem_valid) 
        
      end // LOAD
      
      CHECK : begin 
        is_legal_ps = check_is_legal(cmd_row, cmd_col, cmd_num);
        next_state = DONE;
      end
      
      CLEAR : begin 
        next_state = DONE;
        board_ps[cmd_row][cmd_col] = 0 ;
      end
      

      DONE: begin
        done_reg.status = 1;   
        done_reg.result = is_legal ; 
        if (is_legal) begin
          board_ps[cmd_row][cmd_col] = cmd_num ; 
        end          
        if (clear_done_on_read) begin
          done_reg = 0; 
          is_legal_ps = 0 ;          
          next_state = IDLE;            
        end       
        done_reg.status = 1 ;    
        host_regs_intrf.host_regs_data_out[XLR_DONE_RI] = done_reg ; 
        host_regs_intrf.host_regs_valid_out[XLR_DONE_RI] = 1 ;
      end 
 
   endcase
   
  end // always

  //------------------------------------------------------------------------

 // Sequential
  always @(posedge clk or negedge rst_n) begin
  
    if(!rst_n) begin  
      state               <= IDLE;  
      board               <= 0 ;   
      loaded_start_idx    <= 0;  
      num_bytes_requested <= 0 ;
      is_legal            <= 0;
    end else begin     
      state      <= next_state ;
      board      <= board_ps ;     
      if (mem_intf_read.mem_req) begin
        loaded_start_idx <= next_load_start_idx ;
        num_bytes_requested <= mem_intf_read.mem_size_bytes;
      end
      is_legal <= is_legal_ps ;      
    end    
  end
   
  //------------------------------------------------------------------------
  
  // located at upper part of start register exactly agreed with SW
  assign cmd_col = start_reg.col ;
  assign cmd_row = start_reg.row ;
  assign cmd_num = start_reg.num ;
  
  //------------------------------------------------------------------------  

  // Comb Function to check_validity
  //
  // "May I place digit `num` into the empty cell (row,col)?"
  // Returns 1 if num is NOT already present in that cell's row, column or 3x3 box.
  // This is the RTL twin of is_legal_nox() in sw/apps/sudx_basic/sudx_basic.c,
  // and it is the hot inner loop of the backtracking solver.
  //
  // Reuses the group indexing from sud_pkg.sv (written for week-1/hw1):
  // every cell belongs to exactly 3 of the 27 groups - its row, its column and
  // its box - and grp_row(g,i)/grp_col(g,i) give the coordinates of member i of
  // group g. So the check is just "is num a member of any of my 3 groups?".
  //
  // 3 groups x 9 members = 27 comparisons. The previous version searched for the
  // box origin in a loop and then scanned all 81 cells with in-box predicates;
  // same answer, ~3x the source and a lot more to read.
  //
  // NOTE: this is a MEMBERSHIP test, not hw1's duplicate test - hw1 asked "does
  // any group contain the same digit twice?" and needed the `seen` mask. Here we
  // only compare against one digit, so no mask is needed.
  //
  // Precondition: num is 1..9 (the C solver only ever tries d = 1..9) and
  // board[row][col] is empty, so the cell can never match itself.

  function automatic logic check_is_legal (
    input logic [CELL_W-1:0] row, col, num
  );

    logic conflict;   // scratch wire, not storage - `automatic` gives every call
    int   g;          // its own copy, so two call sites can never stomp on each other

    conflict = 1'b0;  // default first, then override (the ex0 habit)

    // NOT a loop in time: this unrolls at elaboration into 3 parallel checkers,
    // all evaluated in the same instant, inside the CHECK state's single cycle.
    for (int k = 0; k < 3; k++) begin

      if      (k == 0) g = int'(row);                          // its row      -> group  0..8
      else if (k == 1) g = BOARD_DIM + int'(col);              // its column   -> group  9..17
      else             g = 2*BOARD_DIM                         // its 3x3 box  -> group 18..26
                           + (int'(row)/BOX_DIM)*BOX_DIM
                           + (int'(col)/BOX_DIM);

      // likewise unrolled: 9 comparators per checker, 27 in total
      for (int i = 0; i < BOARD_DIM; i++)
        if (board[grp_row(g,i)][grp_col(g,i)] == num) conflict = 1'b1;
    end

    // `board` is not an argument - the function reads the module-level register
    // directly. That is the committed board (a flop), NOT board_ps, which is
    // what we want in CHECK. always_comb looks inside function bodies when it
    // builds its sensitivity list, so `board` is correctly included.
    check_is_legal = ~conflict;   // return by assigning to the function's own name

  endfunction  

 //--------------------------------------------------------------

endmodule
