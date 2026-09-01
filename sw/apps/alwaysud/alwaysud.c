
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
// Measurement switches
//
// ALWAYSUD_SPLIT_TIMERS
//   1 = report "Board setup+load" and "Sudoku solve" separately (development).
//   0 = one window spanning setup+solve, exactly like the course's sudx_scan,
//       so the number is directly comparable to the baseline and to other students.
//
//   Turn it OFF for a scoring run. Not because the split is expensive - see below -
//   but because a number that is not comparable to the baseline invites the question
//   "why is your easy1 smaller?", and the answer should not be "different window".
//
//   The endgame makes this sharper. v3 predicts hard1 at ~26 solve cycles against a
//   fixed 235-cycle load, so near the end of the ladder the load - not the search -
//   is most of the score, and the window definition stops being a detail.
//
// ALWAYSUD_PROBE_TIMER_COST
//   Adds a second report_task_performance() immediately after the first, with no work
//   between them, so its delta is the cost of one report call. Diagnostic only.
//-------------------------------------------------------------------------

#ifndef ALWAYSUD_SPLIT_TIMERS
#define ALWAYSUD_SPLIT_TIMERS 1
#endif

#ifndef ALWAYSUD_PROBE_TIMER_COST
#define ALWAYSUD_PROBE_TIMER_COST 0
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

#if ALWAYSUD_SPLIT_TIMERS
      // Split the measurement. report_task_performance() reports the delta since the
      // PREVIOUS call, so this one ends the setup window and starts the solve window -
      // and the "Sudoku solve" report in main() then covers the search alone.
      //
      // Why it matters: setup is a fixed 235 cycles (board LOAD over three memory
      // bursts, plus two register handshakes and their polling loops). On easy1 that
      // is 45% of the total, so an easy-board "improvement" would be mostly handshake
      // noise. It is also puzzle-independent - hard1 pays exactly the same 235.
      report_task_performance("Board setup+load");

#if ALWAYSUD_PROBE_TIMER_COST
      // Back-to-back call: this second report's delta IS the cost of one report call,
      // because no work happens between them. Settles how much of a window is
      // instrument rather than design. See docs/MEASUREMENT.md.
      report_task_performance("probe: cost of one report call");
#endif
#endif

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
    
    // With the split ON this is the search alone; with it OFF this single call spans
    // setup+solve and is directly comparable to the course's sudx_scan number.
    report_task_performance("Sudoku solve");
#if ALWAYSUD_SPLIT_TIMERS
    report_total_performance();              // setup + solve, i.e. the unsplit number
#endif


    if (solved) {
        
      printf("\n=== Application reported Solved ===\n");
      print_board(board);

      char is_solved_board_ok = check_solved_board(board) ;

      printf("\nSolved board %s final checker\n", is_solved_board_ok ? "PASSED" : "FAILED");
   
    } else printf("\nNo solution found by application.\n");
    
      alloc_free((void*)board, "board"); 
   
    bm_quit_app(); 
}