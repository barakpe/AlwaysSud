
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include <k5_libs.h>
#include <sud_lib.h>
#include "alwaysud.h"

#ifndef HLCM
#include "alwaysud_enums.svh"
#endif


//-------------------------------------------------------------------------

char xlr_solver() { // Board is already loaded in XLR HW

    // xlr check if legal, also update xlr board copy if legal.

    start_reg_t start_reg ;
    start_reg.full = 0;
    start_reg.part.cmd =  SOLVE ; 
    HOST_REG(XLR_START_RI) = start_reg.full; 
    
    done_reg_t done_reg;
    char done = 0;
    while (!done) {
       done_reg.full = HOST_REG(XLR_DONE_RI) ;
       done = done_reg.part.status;
       //printf("DBG setup is_legal_xlr Polling ...done_reg.full=%08x\n",done_reg.full); // uncomment for debug
    } 
    return  done_reg.part.result;  
}

//-------------------------------------------------------------------------


void xlr_setup(uint8_t* xmem_board_addr) {    

    HOST_REG(XMEM_BOARD_ADDR_RI) = (unsigned int)xmem_board_addr;
     
    start_reg_t start_reg ;
    start_reg.full = 0;  
    start_reg.part.cmd = SETUP ;       
    HOST_REG(XLR_START_RI) = start_reg.full; 
        
    done_reg_t done_reg;
    char done = 0 ;
    while (!done) {
       done_reg.full = HOST_REG(XLR_DONE_RI) ;
       done = done_reg.part.status;
       //printf("DBG setup done Polling ...done_reg.full =%08x\n",done_reg.full); // uncomment for debug
    } 
}

//----------------------------------------------------------------------------------

/// Iterative solver (explicit stack, no recursion) 

int solve(uint8_t* board) {

      // Notice that currently we do not support here a non-accelerated reference option

      xlr_setup(board) ;

      // Split the measurement. report_task_performance() reports the delta since the
      // PREVIOUS call, so this one ends the setup window and starts the solve window -
      // and the "Sudoku solve" report in main() then covers the search alone.
      //
      // Why it matters: setup is a fixed ~340 cycles (board LOAD over three memory
      // bursts, plus two register handshakes and their polling loops). On easy1 that
      // was 94% of the single number we used to print, so an easy-board "improvement"
      // was mostly handshake noise.
      report_task_performance("Board setup+load");

      char solver_success = xlr_solver() ;
      return solver_success ; 

}

//----------------------------------------------------------------------------------

// Main 

int main(void) {
    
    printf("HELLO SUDOKU SOLVER\n"); 
    
    alloc_init();
          
    uint8_t (*board)[SIZE];
    
    board = alloc_get(SIZE*SIZE, "board");

    load_sud_board(board) ;

    printf("=== Input ===\n");
    print_board(board);

    printf("\nSolving in progress...\n");
    
    reset_report_performance(); 

    char solved = solve((uint8_t*)board) ;
    
    report_task_performance("Sudoku solve"); // search only - see the split in solve()
    report_total_performance();              // setup + solve, i.e. the old single number


    if (solved) {
        
      printf("\n=== Application reported Solved ===\n");
      print_board(board);

      char is_solved_board_ok = check_solved_board(board) ;

      printf("\nSolved board %s final checker\n", is_solved_board_ok ? "PASSED" : "FAILED");
   
    } else printf("\nNo solution found by application.\n");
    
      alloc_free((void*)board, "board"); 
   
    bm_quit_app(); 
}