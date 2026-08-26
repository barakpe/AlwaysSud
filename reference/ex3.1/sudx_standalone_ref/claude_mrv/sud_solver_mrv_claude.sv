//==============================================================================
// sudoku_solver_mrv.sv
//
// Same interface/behavior as sudoku_solver.sv, but picks which cell to fill
// next using the Minimum Remaining Values (MRV) heuristic instead of fixed
// raster order: at each step it scans all unfilled cells and chooses the one
// with the fewest legal candidate digits, then tries the smallest legal
// digit there. This tends to prune the search tree dramatically vs. a fixed
// cell order, at the cost of needing an explicit decision stack (since the
// "previous cell" during backtracking is no longer just "one earlier in
// raster order" -- it can be any cell) and a bigger per-cycle combinational
// scan (81 candidate-count computations instead of 1).
//
// Ports are identical to sudoku_solver.sv: same start/busy/done/success
// control signals, same puzzle_in/puzzle_solved packed widths.
//==============================================================================

module sud_solver_mrv_claude (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 start,
    input  logic [8:0][8:0][3:0] puzzle_in,      // [row][col], 0 = empty, 1-9 = given
    output logic                 busy,
    output logic                 done,
    output logic                 success,
    output logic [8:0][8:0][3:0] puzzle_solved
);

    // Which "third" (0,1,2) a 0-8 row/col index belongs to (avoids a /3 op)
    function automatic logic [1:0] third(input logic [3:0] x);
        case (x)
            4'd0, 4'd1, 4'd2: third = 2'd0;
            4'd3, 4'd4, 4'd5: third = 2'd1;
            default:          third = 2'd2;
        endcase
    endfunction

    // 3x3 box index (0-8) for a given row/col
    function automatic logic [3:0] box_of(input logic [3:0] r, input logic [3:0] c);
        box_of = ({2'b00, third(r)} * 4'd3) + {2'b00, third(c)};
    endfunction

    // Number of digits 1-9 NOT set in `used`
    function automatic logic [3:0] popcount9(input logic [9:0] used);
        logic [3:0] cnt;
        cnt = 4'd0;
        for (int d = 1; d <= 9; d++) if (!used[d]) cnt = cnt + 4'd1;
        popcount9 = cnt;
    endfunction

    // Smallest digit >= start_d (1-9) not set in mask. Returns {found, digit}.
    function automatic logic [4:0] find_next_digit(input logic [9:0] mask, input logic [3:0] start_d);
        logic       fnd;
        logic [3:0] res;
        fnd = 1'b0;
        res = 4'd0;
        for (int d = 1; d <= 9; d++) begin
            if (!fnd && (d >= int'(start_d)) && !mask[d]) begin
                res = d[3:0];
                fnd = 1'b1;
            end
        end
        find_next_digit = {fnd, res};
    endfunction

    typedef enum logic [2:0] {S_IDLE, S_INIT, S_ADVANCE, S_BACKTRACK, S_DONE} state_t;
    state_t state;

    // Board storage
    logic [3:0] cell_val   [0:8][0:8];   // current value, 0 = empty
    logic       fixed_cell [0:8][0:8];   // 1 = given, never touched by search

    // bit d (1..9) set => digit d already used in this row/col/box. bit0 unused.
    logic [9:0] row_used [0:8];
    logic [9:0] col_used [0:8];
    logic [9:0] box_used [0:8];

    // Decision stack: one entry per cell the search itself has filled in
    // (givens are never pushed). Max depth = 81 cells.
    logic [3:0] stack_row   [0:80];
    logic [3:0] stack_col   [0:80];
    logic [3:0] stack_digit [0:80];
    logic [6:0] sp;   // number of entries currently on the stack (0-81)

    // Internal unpacked mirror of puzzle_in for the same reason as the
    // raster-order version: some tools don't support a variable index
    // reaching directly into a packed multi-dimensional port.
    logic [3:0] puzzle_in_copy [0:8][0:8];
    genvar gr, gc;
    generate
        for (gr = 0; gr < 9; gr = gr + 1) begin : G_ROW
            for (gc = 0; gc < 9; gc = gc + 1) begin : G_COL
                assign puzzle_in_copy[gr][gc] = puzzle_in[gr][gc];
            end
        end
    endgenerate

    // ---------------- INIT scan pointer ----------------
    logic [3:0] row, col;
    logic       at_last_cell;
    assign at_last_cell = (row == 4'd8) && (col == 4'd8);
    logic [3:0] init_val;
    assign init_val = puzzle_in_copy[row][col];
    logic [3:0] init_box;
    assign init_box = box_of(row, col);

    // ---------------- MRV scan (combinational, over all 81 cells) ----------------
    logic [3:0] best_r, best_c, best_cnt;
    logic       any_unassigned;
    always_comb begin
        best_cnt       = 4'd10;   // sentinel, larger than any real count (max 9)
        best_r         = 4'd0;
        best_c         = 4'd0;
        any_unassigned = 1'b0;
        for (int r = 0; r < 9; r++) begin
            for (int c = 0; c < 9; c++) begin
                if (!fixed_cell[r][c] && cell_val[r][c] == 4'd0) begin
                    any_unassigned = 1'b1;
                    if (popcount9(row_used[r] | col_used[c] | box_used[box_of(r[3:0], c[3:0])]) < best_cnt) begin
                        best_cnt = popcount9(row_used[r] | col_used[c] | box_used[box_of(r[3:0], c[3:0])]);
                        best_r   = r[3:0];
                        best_c   = c[3:0];
                    end
                end
            end
        end
    end

    logic [3:0] best_box;
    assign best_box = box_of(best_r, best_c);
    logic [9:0] best_mask;
    assign best_mask = row_used[best_r] | col_used[best_c] | box_used[best_box];
    logic [4:0] best_search;
    assign best_search = find_next_digit(best_mask, 4'd1);
    wire adv_found       = best_search[4];
    wire [3:0] adv_digit = best_search[3:0];

    // ---------------- Top-of-stack lookup (for backtracking) ----------------
    logic [6:0] top_idx;
    assign top_idx = sp - 7'd1;   // only meaningful when sp > 0
    logic [3:0] top_r, top_c, top_d;
    assign top_r = stack_row[top_idx];
    assign top_c = stack_col[top_idx];
    assign top_d = stack_digit[top_idx];
    logic [3:0] top_box;
    assign top_box = box_of(top_r, top_c);
    logic [9:0] top_mask_excl;
    assign top_mask_excl = (row_used[top_r] | col_used[top_c] | box_used[top_box]) & ~(10'b1 << top_d);
    logic [4:0] top_search;
    assign top_search = find_next_digit(top_mask_excl, top_d + 4'd1);
    wire top_found            = top_search[4];
    wire [3:0] top_next_digit = top_search[3:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            busy    <= 1'b0;
            done    <= 1'b0;
            success <= 1'b0;
            row     <= 4'd0;
            col     <= 4'd0;
            sp      <= 7'd0;
            for (int r = 0; r < 9; r++) begin
                row_used[r] <= 10'd0;
                col_used[r] <= 10'd0;
                box_used[r] <= 10'd0;
                for (int c = 0; c < 9; c++) begin
                    cell_val[r][c]   <= 4'd0;
                    fixed_cell[r][c] <= 1'b0;
                end
            end
        end else begin
            case (state)
                //--------------------------------------------------------
                S_IDLE: begin
                    done    <= 1'b0;
                    success <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        row   <= 4'd0;
                        col   <= 4'd0;
                        sp    <= 7'd0;
                        for (int r = 0; r < 9; r++) begin
                            row_used[r] <= 10'd0;
                            col_used[r] <= 10'd0;
                            box_used[r] <= 10'd0;
                        end
                        state <= S_INIT;
                    end
                end

                //--------------------------------------------------------
                // Load one cell per cycle (raster order), build masks
                S_INIT: begin
                    cell_val[row][col]   <= init_val;
                    fixed_cell[row][col] <= (init_val != 4'd0);
                    if (init_val != 4'd0) begin
                        row_used[row]     <= row_used[row]     | (10'b1 << init_val);
                        col_used[col]     <= col_used[col]     | (10'b1 << init_val);
                        box_used[init_box]<= box_used[init_box]| (10'b1 << init_val);
                    end
                    if (at_last_cell) begin
                        state <= S_ADVANCE;
                    end else if (col == 4'd8) begin
                        col <= 4'd0;
                        row <= row + 4'd1;
                    end else begin
                        col <= col + 4'd1;
                    end
                end

                //--------------------------------------------------------
                // Pick the unfilled cell with fewest candidates, try its
                // smallest legal digit.
                S_ADVANCE: begin
                    if (!any_unassigned) begin
                        state   <= S_DONE;
                        success <= 1'b1;
                    end else if (!adv_found) begin
                        // most-constrained cell has zero legal digits: contradiction
                        state <= S_BACKTRACK;
                    end else begin
                        cell_val[best_r][best_c] <= adv_digit;
                        row_used[best_r]         <= row_used[best_r]   | (10'b1 << adv_digit);
                        col_used[best_c]         <= col_used[best_c]   | (10'b1 << adv_digit);
                        box_used[best_box]       <= box_used[best_box] | (10'b1 << adv_digit);
                        stack_row[sp]            <= best_r;
                        stack_col[sp]            <= best_c;
                        stack_digit[sp]          <= adv_digit;
                        sp                       <= sp + 7'd1;
                        // stay in S_ADVANCE; next cycle picks the next cell
                    end
                end

                //--------------------------------------------------------
                // Undo/retry the most recent decision (LIFO order)
                S_BACKTRACK: begin
                    if (sp == 7'd0) begin
                        state   <= S_DONE;
                        success <= 1'b0;
                    end else if (top_found) begin
                        cell_val[top_r][top_c] <= top_next_digit;
                        row_used[top_r]        <= (row_used[top_r]   & ~(10'b1 << top_d)) | (10'b1 << top_next_digit);
                        col_used[top_c]        <= (col_used[top_c]   & ~(10'b1 << top_d)) | (10'b1 << top_next_digit);
                        box_used[top_box]      <= (box_used[top_box] & ~(10'b1 << top_d)) | (10'b1 << top_next_digit);
                        stack_digit[top_idx]   <= top_next_digit;
                        state                  <= S_ADVANCE;   // sp unchanged, pick next cell fresh
                    end else begin
                        cell_val[top_r][top_c] <= 4'd0;
                        row_used[top_r]        <= row_used[top_r]   & ~(10'b1 << top_d);
                        col_used[top_c]        <= col_used[top_c]   & ~(10'b1 << top_d);
                        box_used[top_box]      <= box_used[top_box] & ~(10'b1 << top_d);
                        sp                     <= sp - 7'd1;
                        // stay in S_BACKTRACK; pop further next cycle
                    end
                end

                //--------------------------------------------------------
                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    if (start) begin
                        row   <= 4'd0;
                        col   <= 4'd0;
                        sp    <= 7'd0;
                        busy  <= 1'b1;
                        done  <= 1'b0;
                        success <= 1'b0;
                        for (int r = 0; r < 9; r++) begin
                            row_used[r] <= 10'd0;
                            col_used[r] <= 10'd0;
                            box_used[r] <= 10'd0;
                        end
                        state <= S_INIT;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Output the current grid contents (valid/meaningful once done && success)
    genvar or_, oc_;
    generate
        for (or_ = 0; or_ < 9; or_ = or_ + 1) begin : O_ROW
            for (oc_ = 0; oc_ < 9; oc_ = oc_ + 1) begin : O_COL
                assign puzzle_solved[or_][oc_] = cell_val[or_][oc_];
            end
        end
    endgenerate

endmodule
