// Port shim so the COURSE'S OWN MRV solver can be measured on exactly the same
// testbench, puzzles and cycle convention as everything else on this branch.
//
// reference/ex3.1/sudx_standalone_ref/claude_mrv/sud_solver_mrv_claude.sv is
// unmodified; this only renames the module and drops the extra `busy` output,
// which docs/SOLVER.md already flags as "the only plumbing difference if we ever
// swap it in".
module alwaysud_solver (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [8:0][8:0][3:0] puzzle_in,
    input  logic        start,
    output logic        done,
    output logic        success,
    output logic [8:0][8:0][3:0] solved_puzzle
);
    logic busy_unused;
    sud_solver_mrv_claude u_ref (
        .clk(clk), .rst_n(rst_n), .start(start), .puzzle_in(puzzle_in),
        .busy(busy_unused), .done(done), .success(success),
        .puzzle_solved(solved_puzzle)
    );
endmodule
