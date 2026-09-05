// Geometry package. The table itself is GENERATED from bench/units.py by
// explore/model/gen_geom.py, so the RTL and the correctness gate cannot
// disagree about which cells constrain which. Swap the include to change
// variant; nothing else in the solver knows any Sudoku geometry.
package sud_geom_pkg;
`ifdef SUD_VARIANT_DIAGONAL
  `include "sud_geom_diagonal.svh"
`else
  `include "sud_geom_classic.svh"
`endif
endpackage
