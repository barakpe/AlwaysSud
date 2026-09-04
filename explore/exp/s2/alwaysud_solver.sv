//=============================================================================
// alwaysud_solver - candidate-mask solver, one placement per cycle.
//
// Same ports as v0, so it drops into alwaysud.sv unchanged.
//
// WHAT CHANGED FROM v0, and why each piece is here:
//
//   v0 keeps the board as 4-bit digits and asks "is digit v legal at (r,c)?"
//   with 27 comparators, one digit per cycle, and finds the next empty cell one
//   cell per cycle. Both of those are sequential because the C it was
//   transliterated from had one ALU.
//
//   Here the board is one-hot and every unit keeps a 9-bit `used` mask, so the
//   set of legal digits for a cell is ~(OR of its units' masks) - available for
//   all 81 cells at once, for free. That turns "try 9 digits" into "take the
//   lowest set bit" and "walk to the next empty cell" into a priority encoder.
//
// MODE selects which inference runs. Each step adds exactly one mechanism:
//   0  M1   raster order, no inference          - same search tree as v0
//   1  S2   + forward check, naked and hidden singles as forced moves
//   2  S2M  + minimum-remaining-values choice of the cell to guess at
//
// GEOMETRY is a parameter, not arithmetic: sud_geom_pkg is generated from
// bench/units.py. X-Sudoku is +2 units in that table and no change here.
//=============================================================================
// MODE comes from the .f as +define+SUD_MODE=<n>. The parameter default is what
// carries it, because the wrapper instantiates the solver without parameters.
`ifndef SUD_MODE
  `define SUD_MODE 1
`endif

import sud_geom_pkg::*;

module alwaysud_solver #(
    parameter int MODE = `SUD_MODE
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [8:0][8:0][3:0] puzzle_in,
    input  logic        start,
    output logic        done,
    output logic        success,
    output logic [8:0][8:0][3:0] solved_puzzle
);

    localparam int NC  = SUD_NC;
    localparam int NU  = SUD_NU;

    //---------------------------------------------------------------- state
    logic [NC-1:0][8:0] sol;      // one-hot digit per cell, 0 = empty
    logic [NU-1:0][8:0] used;     // digits already placed in each unit

    logic [6:0] sp;
    logic [6:0] st_cell   [0:80];
    logic [8:0] st_dig    [0:80];
    logic       st_forced [0:80];

    typedef enum logic [2:0] { IDLE, INIT, STEP, BACK, DONE_S, DONE_F } state_t;
    state_t state;

    //---------------------------------------------------------------- helpers
    function automatic logic [8:0] lowbit9(input logic [8:0] x);
        return x & (~x + 9'd1);
    endfunction

    function automatic logic onehot9(input logic [8:0] x);
        return (x != 9'd0) && ((x & (x - 9'd1)) == 9'd0);
    endfunction

    // index of the lowest set bit, or 9 when none
    function automatic logic [3:0] pri9(input logic [8:0] v);
        logic [3:0] r;
        r = 4'd9;
        for (int i = 8; i >= 0; i--) if (v[i]) r = i[3:0];
        return r;
    endfunction

    function automatic logic [3:0] popc9(input logic [8:0] x);
        logic [3:0] n;
        n = 4'd0;
        for (int i = 0; i < 9; i++) n = n + {3'd0, x[i]};
        return n;
    endfunction

    // digits strictly above one-hot b
    function automatic logic [8:0] above9(input logic [8:0] b);
        logic [9:0] bb, lo;
        bb = {b, 1'b0};
        lo = bb - 10'd1;          // every bit at or below b
        return ~lo[8:0];
    endfunction

    //------------------------------------------------- per-cell candidate sets
    logic [NC-1:0]      emptyc;
    logic [NC-1:0][8:0] cellused, availc;

    always_comb begin
        for (int c = 0; c < NC; c++) begin
            logic [8:0] m;
            m = 9'd0;
            for (int u = 0; u < NU; u++)
                m = m | (SUD_MEMBER[u][c] ? used[u] : 9'd0);
            cellused[c] = m;
            emptyc[c]   = (sol[c] == 9'd0);
            availc[c]   = (sol[c] == 9'd0) ? (~m & 9'h1FF) : 9'd0;
        end
    end

    // the flat 81-cell view of the packed 9x9 ports
    logic [80:0][3:0] pz_flat;
    assign pz_flat = puzzle_in;

    //--------------------------------------------------- 81-way priority encode
    // Two-level: 9 groups of 9. A flat 81-deep chain is a much longer path.
    function automatic logic [6:0] pri81(input logic [80:0] v);
        logic [8:0] anyg;
        logic [3:0] posg [0:8];
        logic [3:0] g;
        for (int i = 0; i < 9; i++) begin
            logic [8:0] slice;
            for (int j = 0; j < 9; j++) slice[j] = v[i*9 + j];
            anyg[i] = |slice;
            posg[i] = pri9(slice);
        end
        g = pri9(anyg);
        return (g == 4'd9) ? 7'd81 : (7'(g) * 7'd9 + 7'(posg[g]));
    endfunction

    //---------------------------------------------------------- naked singles
    logic [NC-1:0] nakedv, deadv;
    always_comb begin
        for (int c = 0; c < NC; c++) begin
            nakedv[c] = emptyc[c] && onehot9(availc[c]);
            deadv[c]  = emptyc[c] && (availc[c] == 9'd0);
        end
    end

    logic       any_naked, any_dead, any_empty;
    logic [6:0] naked_idx, first_empty;
    assign any_naked   = |nakedv;
    assign any_dead    = |deadv;
    assign any_empty   = |emptyc;
    assign naked_idx   = pri81(nakedv);
    assign first_empty = pri81(emptyc);

    //--------------------------------------------------------- hidden singles
    // For every (unit, digit) not already placed in that unit, gather the 9 bits
    // "can this slot still take that digit". No home at all is a contradiction;
    // exactly one home is a forced placement. Priority is unit-major then digit,
    // and that order is what the cycle model reproduces.
    logic [NU*9-1:0] hs_event;      // this (u,d) decides: no home, or exactly one
    logic [NU*9-1:0] hs_none;       // ... and it was "no home"
    logic [NU-1:0][8:0][8:0] hs_spots;

    always_comb begin
        for (int u = 0; u < NU; u++) begin
            for (int d = 0; d < 9; d++) begin
                logic [8:0] sp9;
                for (int k = 0; k < 9; k++)
                    sp9[k] = availc[SUD_UNIT_CELLS[u][k]][d];
                hs_spots[u][d]      = sp9;
                hs_none [u*9 + d]   = !used[u][d] && (sp9 == 9'd0);
                hs_event[u*9 + d]   = !used[u][d] && ((sp9 == 9'd0) || onehot9(sp9));
            end
        end
    end

    // first set (u,d), unit-major then digit
    logic [8:0] hs_uany;
    logic [3:0] hs_dpos [0:NU-1];
    logic [6:0] hs_u;
    logic [3:0] hs_d;
    logic       any_hs, hs_is_none;
    logic [6:0] hs_cell;
    logic [8:0] hs_bit;

    always_comb begin
        logic [NU-1:0] uany;
        logic [7:0]    ui;
        logic [3:0]    dsel;
        logic [8:0]    slice;
        uany = '0;
        for (int u = 0; u < NU; u++) begin
            for (int d = 0; d < 9; d++) slice[d] = hs_event[u*9 + d];
            uany[u] = |slice;
        end
        ui = 8'd255;
        for (int u = NU-1; u >= 0; u--) if (uany[u]) ui = u[7:0];
        any_hs = (ui != 8'd255);
        hs_u   = ui[6:0];
        for (int d = 0; d < 9; d++) slice[d] = any_hs ? hs_event[hs_u*9 + d] : 1'b0;
        dsel   = pri9(slice);
        hs_d   = dsel;
        hs_is_none = any_hs && hs_none[hs_u*9 + hs_d];
        hs_cell    = any_hs ? SUD_UNIT_CELLS[hs_u][pri9(hs_spots[hs_u][hs_d])] : 7'd0;
        hs_bit     = 9'd1 << hs_d;
    end

    //-------------------------------------------------------------- MRV (MODE 2)
    logic [6:0] mrv_idx;
    always_comb begin
        logic [3:0] bestn;
        logic [6:0] besti;
        bestn = 4'd15;
        besti = 7'd81;
        for (int c = NC-1; c >= 0; c--) begin
            logic [3:0] n;
            n = emptyc[c] ? popc9(availc[c]) : 4'd15;
            if (emptyc[c] && (n <= bestn)) begin
                bestn = n;
                besti = c[6:0];
            end
        end
        mrv_idx = besti;
    end

    //------------------------------------------------------------ the decision
    logic [6:0] pick_cell;
    logic [8:0] pick_bit;
    logic       pick_forced, pick_dead;

    always_comb begin
        logic [6:0] gcell;
        gcell       = (MODE == 2) ? mrv_idx : first_empty;
        pick_cell   = gcell;
        pick_bit    = lowbit9(availc[gcell]);
        pick_forced = 1'b0;
        pick_dead   = (availc[gcell] == 9'd0);

        if (MODE >= 1) begin
            if (any_dead) begin
                pick_dead = 1'b1;
            end else if (any_naked) begin
                pick_cell   = naked_idx;
                pick_bit    = availc[naked_idx];
                pick_forced = 1'b1;
                pick_dead   = 1'b0;
            end else if (any_hs && hs_is_none) begin
                pick_dead = 1'b1;
            end else if (any_hs) begin
                pick_cell   = hs_cell;
                pick_bit    = hs_bit;
                pick_forced = 1'b1;
                pick_dead   = 1'b0;
            end
        end
    end

    //--------------------------------------------------------- backtrack view
    logic [6:0] top_cell;
    logic [8:0] top_dig;
    logic       top_forced;
    logic [8:0] top_retry;

    assign top_cell   = st_cell  [sp - 7'd1];
    assign top_dig    = st_dig   [sp - 7'd1];
    assign top_forced = st_forced[sp - 7'd1];

    always_comb begin
        logic [8:0] m;
        m = 9'h1FF;
        for (int u = 0; u < NU; u++)
            m = m & ~(SUD_MEMBER[u][top_cell]
                      ? (used[u] & ~top_dig)
                      : 9'd0);
        top_retry = m & above9(top_dig);
    end

    //-------------------------------------------------------------------- FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            sp      <= 7'd0;
            done    <= 1'b0;
            success <= 1'b0;
            sol     <= '0;
            used    <= '0;
        end else begin
            case (state)

                IDLE: if (start) state <= INIT;

                INIT: begin
                    done    <= 1'b0;
                    success <= 1'b0;
                    sp      <= 7'd0;
                    for (int u = 0; u < NU; u++) begin
                        logic [8:0] m;
                        m = 9'd0;
                        for (int c = 0; c < NC; c++)
                            if (SUD_MEMBER[u][c] && pz_flat[c] != 4'd0)
                                m = m | (9'd1 << (pz_flat[c] - 4'd1));
                        used[u] <= m;
                    end
                    for (int c = 0; c < NC; c++)
                        sol[c] <= (pz_flat[c] == 4'd0) ? 9'd0
                                                       : (9'd1 << (pz_flat[c] - 4'd1));
                    state <= STEP;
                end

                STEP: begin
                    if (!any_empty) state <= DONE_S;
                    else if (pick_dead) state <= BACK;
                    else begin
                        sol[pick_cell] <= pick_bit;
                        for (int u = 0; u < NU; u++)
                            if (SUD_MEMBER[u][pick_cell]) used[u] <= used[u] | pick_bit;
                        st_cell  [sp] <= pick_cell;
                        st_dig   [sp] <= pick_bit;
                        st_forced[sp] <= pick_forced;
                        sp <= sp + 7'd1;
                    end
                end

                BACK: begin
                    if (sp == 7'd0) state <= DONE_F;
                    else begin
                        sol[top_cell] <= 9'd0;
                        for (int u = 0; u < NU; u++)
                            if (SUD_MEMBER[u][top_cell]) used[u] <= used[u] & ~top_dig;

                        if (!top_forced && (top_retry != 9'd0)) begin
                            logic [8:0] nb;
                            nb = lowbit9(top_retry);
                            sol[top_cell] <= nb;
                            for (int u = 0; u < NU; u++)
                                if (SUD_MEMBER[u][top_cell]) used[u] <= (used[u] & ~top_dig) | nb;
                            st_dig[sp - 7'd1] <= nb;
                            state <= STEP;
                        end else begin
                            sp <= sp - 7'd1;
                        end
                    end
                end

                DONE_S: begin success <= 1'b1; done <= 1'b1; end
                DONE_F: begin success <= 1'b0; done <= 1'b1; end

                default: state <= IDLE;
            endcase
        end
    end

    //---------------------------------------------------------------- output
    logic [80:0][3:0] out_flat;
    always_comb begin
        for (int c = 0; c < NC; c++) begin
            logic [3:0] d;
            d = 4'd0;
            for (int i = 0; i < 9; i++) if (sol[c][i]) d = 4'(i + 1);
            out_flat[c] = d;
        end
    end
    assign solved_puzzle = out_flat;

endmodule
