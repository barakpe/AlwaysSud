+define+HOST_REGS_INTRF
+incdir+$K5_SW_APPS/sudx_basic
# sud_pkg comes from week-1/hw1 - it holds the board type and the 27-group
# indexing (grp_row/grp_col) that check_is_legal now reuses.
# Packages must be compiled BEFORE the modules that import them, so it goes first.
$MY_K5_XLRS/sudx_basic/sud_pkg.sv
$MY_K5_XLRS/sudx_basic/sudx_basic_def_pkg.sv
$MY_K5_XLRS/sudx_basic/sudx_basic.sv