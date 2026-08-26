//==============================================================================
// sud_pkg.sv
//
// COPIED FROM week-1/hw1/hw/sud_pkg.sv - unmodified.
// ex2.1's accelerator reuses grp_row/grp_col for check_is_legal, and takes
// BOARD_DIM / BOX_DIM / CELL_W from here so the board geometry has one
// definition shared by the hw1 modules and this accelerator.
//
// Shared Sudoku definitions for hw1. Same board representation as ex1.1, plus
// the GROUP abstraction that lets both architectures in this exercise share one
// piece of indexing.
//
// BOARD REPRESENTATION
// --------------------
// One cell is a NIBBLE (4 bits, 0..9, 0 = empty), a whole board is 9*9*4 = 324
// bits. The SW side (xmem) holds one cell per BYTE; converting between the two
// is what the LOAD state of k5x_sud/hw/sudx_basic/sudx_basic.sv does.
//
// THE GROUP ABSTRACTION
// ---------------------
// A Sudoku board is legal iff none of its 27 GROUPS contains the same digit
// twice, where a group is a row, a column, or a 3x3 box:
//
//     g =  0.. 8  -> row g
//     g =  9..17  -> column g-9
//     g = 18..26  -> box g-18   (boxes numbered left-to-right, top-to-bottom)
//
// grp_row(g,i) / grp_col(g,i) give the coordinates of the i-th member (i=0..8)
// of group g. Every cell belongs to exactly 3 groups: its row, its column and
// its box. Write the duplicate check ONCE against this indexing and BOTH
// architectures in this exercise reuse it - they differ only in HOW MANY groups
// they process per cycle:
//
//     part A, comb : 27 groups in 1 cycle    (27 checkers, no state)
//     part B, seq  :  3 groups per cycle     ( 3 checkers, ~10 cycles, 1 board reg)
//
// That is the whole point of the homework: same function, same indexing, same
// golden model - two very different pieces of hardware.
//==============================================================================

package sud_pkg;

  parameter int BOARD_DIM  = 9;
  parameter int BOX_DIM    = 3;
  parameter int NUM_CELLS  = BOARD_DIM * BOARD_DIM;   // 81
  parameter int CELL_W     = 4;                       // nibble per cell
  parameter int IDX_W      = 4;                       // 0..8 needs 4 bits
  parameter int NUM_GROUPS = 3 * BOARD_DIM;           // 27: 9 rows + 9 cols + 9 boxes
  parameter int SEEN_W     = 1 << CELL_W;             // 16 - one bit per possible
                                                      // nibble value, so seen[v]
                                                      // is never out of range

  typedef logic [BOARD_DIM-1:0][BOARD_DIM-1:0][CELL_W-1:0] board_t;

  //----------------------------------------------------------------------------
  // Row coordinate of member i of group g.

  function automatic int grp_row(input int g, input int i);
    if      (g < BOARD_DIM)     grp_row = g;                                    // row group
    else if (g < 2*BOARD_DIM)   grp_row = i;                                    // col group
    else                        grp_row = (((g - 2*BOARD_DIM) / BOX_DIM) * BOX_DIM)
                                          + (i / BOX_DIM);                      // box group
  endfunction

  //----------------------------------------------------------------------------
  // Column coordinate of member i of group g.

  function automatic int grp_col(input int g, input int i);
    if      (g < BOARD_DIM)     grp_col = i;
    else if (g < 2*BOARD_DIM)   grp_col = g - BOARD_DIM;
    else                        grp_col = (((g - 2*BOARD_DIM) % BOX_DIM) * BOX_DIM)
                                          + (i % BOX_DIM);
  endfunction

endpackage
