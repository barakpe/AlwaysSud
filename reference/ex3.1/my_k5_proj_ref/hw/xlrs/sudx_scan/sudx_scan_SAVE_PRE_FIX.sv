import xbox_def_pkg::*;
import sudx_def_pkg::*;

module sudx_scan (
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
        SOLVE,
        STORE, // write back board to xmem for SW to read
        DONE
       } next_state, state; //state machine 

  // MUST BE SAME AS SW , notice unlike C the first maos to msb
    
    typedef struct packed {
           logic [23:0] unused ; 
           logic [7:0]  cmd ;                            
    } start_reg_t;
           
    typedef struct packed {
           logic [15:0] unused ; 
           logic  [7:0] result ;            
           logic  [7:0] status ;          
    } done_reg_t;
     
          
  localparam BOARD_DIM = 9 ; 
  localparam BOX_DIM = 3 ;   
  localparam MUM_BOARD_ELEM = BOARD_DIM*BOARD_DIM ; 
   
  logic sudx_start;  
  start_reg_t start_reg;    
  logic clear_done_on_read;
  
  logic [5:0] num_load_bytes_requested ;
  logic [5:0] num_store_bytes_requested ;
  
  sudx_cmd_t sudx_cmd ;
  
    
  logic [XMEM_ADDR_WIDTH-1:0] xmem_board_addr ;
  logic [$clog2(MUM_BOARD_ELEM)-1:0] loaded_start_idx , next_load_start_idx;
  logic [$clog2(MUM_BOARD_ELEM)-1:0] stored_start_idx , next_store_start_idx;
   
  done_reg_t done_reg  ;
  
  //--------------------------------------------------------------------------------------------------------
  
  // Internal board, each bit in element represent a nibble per index 
  // Notice this is different then the SW representation in xmem where each element is held in a byte
  logic [BOARD_DIM-1:0][BOARD_DIM-1:0][3:0] board, board_ps ; // sampled, and pre-sampled

  logic [MUM_BOARD_ELEM-1:0][3:0] board_flat_ps ; // for load convenience

  // Solver sub module control/status signals
  logic solver_start;
  logic solver_done;
  logic solver_success;     
  logic [8:0][8:0][3:0] solver_puzzle_out;
  logic [80:0][3:0] solver_puzzle_out_flat ;

  assign solver_puzzle_out_flat = solver_puzzle_out ;
    
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
   
   next_load_start_idx  = loaded_start_idx + num_load_bytes_requested;
   next_store_start_idx = stored_start_idx + num_store_bytes_requested;

   mem_intf_read.mem_size_bytes  = 32;              // default assuming MUM_BOARD_ELEM>32  
   mem_intf_read.mem_start_addr  = xmem_board_addr; // default board xmem address 
   mem_intf_read.mem_req = 0;


   mem_intf_write.mem_size_bytes = 32;
   mem_intf_write.mem_data       = 0;
   mem_intf_write.mem_start_addr = xmem_board_addr;
   mem_intf_write.mem_req        = 0;   
   
   //  default host regs output 
   host_regs_intrf.host_regs_data_out  = 0 ;
   host_regs_intrf.host_regs_valid_out = 0 ;
  
   board_ps = board;
   board_flat_ps = board;
   
   done_reg = 0 ;
   
   case (state) // State Machine case
    
      IDLE: if (sudx_start) begin
       if      (sudx_cmd==SETUP) next_state = LOAD;     // Setup only, loading board, pending for execution
       else if (sudx_cmd==SOLVE) next_state = SOLVE;    // invoke solver  
       else if (sudx_cmd==STORE) next_state = STORE;    // write board back to xmem       
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
      
      SOLVE : begin 
        if (solver_done) next_state = STORE;
      end
      
      STORE : begin 

        mem_intf_write.mem_req = 1;          
        mem_intf_write.mem_start_addr = xmem_board_addr + next_store_start_idx ;  
      
        if (mem_intf_write.mem_ack) begin
                                         
          if ((next_store_start_idx+32) >= MUM_BOARD_ELEM) // Overwrite default 32
            mem_intf_write.mem_size_bytes = MUM_BOARD_ELEM - next_store_start_idx ;   
          
          if (next_store_start_idx == MUM_BOARD_ELEM)  begin                       
            next_state = DONE;   
            mem_intf_write.mem_req = 0;            
          end
                                     
        end // if (mem_intf_write.mem_ack) 

        if (mem_intf_write.mem_req) begin
          for (int i=0;i<32;i++) begin  
             if ((stored_start_idx+i) < MUM_BOARD_ELEM) 
               mem_intf_write.mem_data[i][3:0] = solver_puzzle_out_flat[stored_start_idx+i] ;               
          end
        end

      end


      DONE: begin
        done_reg.status = 1;   // done
        done_reg.result = solver_success;         
        if (clear_done_on_read) begin
          done_reg = 0;       
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
      board               <= 0;   
      loaded_start_idx    <= 0;  
      stored_start_idx    <= 0;  
      num_load_bytes_requested <= 0;
      num_store_bytes_requested <= 0;     
    end else begin     
      state      <= next_state ;
      board      <= board_ps ;     
      if (mem_intf_read.mem_req) begin
        loaded_start_idx <= next_load_start_idx ;
        num_load_bytes_requested <= mem_intf_read.mem_size_bytes;
      end 
      if (mem_intf_write.mem_req) begin
        stored_start_idx <= next_store_start_idx ;
        num_store_bytes_requested <= mem_intf_write.mem_size_bytes ;
      end 
    end    
  end
   
  //------------------------------------------------------------------------

  // TODO: consider sampling solver inputs
  assign solver_start = sudx_start && (sudx_cmd==SOLVE);

  sudx_scan_solver solver (
        .clk           (clk),
        .rst_n         (rst_n),
        .puzzle_in     (board),
        .start         (solver_start),
        .done          (solver_done),
        .success       (solver_success),        
        .solved_puzzle (solver_puzzle_out)
  );

  // Consider sampling solver outputs


endmodule
