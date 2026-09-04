//=============================================================================
// alwaysud_solver (s2fast) - same algorithm as MODE 1/2 of the plain solver,
// restructured so that no selection is ever encoded to an index on the
// decision path.
//
// WHY. The measured worst path of the plain mask solver was
//   sol -> emptyc -> pri81 (encode) -> 81:1 mux of availc (decode) -> used -> sol
// i.e. the design finds "which cell" as a 7-bit number and then spends another
// five levels of muxing turning that number back into the cell's data. Here the
// selection stays an 81-bit one-hot the whole way: choose with a tree, read the
// chosen cell with an AND-OR tree, and write it by gating with the same vector.
// The 7-bit index is still produced for the stack, but it only ever feeds a
// register, so it sits beside the critical path instead of inside it.
//
// The rule is also unified: a cell is "forced" if it has one candidate (naked
// single) OR it is the only home for some digit in one of its units (hidden
// single). Lowest forced cell wins; if none is forced, guess. That makes the
// contradiction test global - any empty cell with no candidate, or any unit
// digit with no home - which prunes slightly harder than asking in sequence.
// Modelled as arch "s2u" / "s2um".
//
// MODE 1 = raster guess cell, MODE 2 = minimum-remaining-values guess cell.
//=============================================================================
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
    localparam int NC = SUD_NC;
    localparam int NU = SUD_NU;

    logic [NC-1:0][8:0] sol;
    logic [NU-1:0][8:0] used;
    logic [6:0] sp;
    logic [6:0] st_cell   [0:80];
    logic [8:0] st_dig    [0:80];
    logic       st_forced [0:80];

    typedef enum logic [2:0] { IDLE, INIT, STEP, BACK, DONE_S, DONE_F } state_t;
    state_t state;

    //-------------------------------------------------------------- primitives
    // isolate the lowest set bit of 9, as a one-hot 9-bit vector
    function automatic logic [8:0] iso9(input logic [8:0] v);
        logic [8:0] r;
        logic       seen;
        seen = 1'b0;
        for (int i = 0; i < 9; i++) begin
            r[i] = v[i] & ~seen;
            seen = seen | v[i];
        end
        return r;
    endfunction

    function automatic logic [3:0] popc9(input logic [8:0] x);
        logic [3:0] n;
        n = 4'd0;
        for (int i = 0; i < 9; i++) n = n + {3'd0, x[i]};
        return n;
    endfunction

    function automatic logic [8:0] above9(input logic [8:0] b);
        logic [9:0] bb, lo;
        bb = {b, 1'b0};
        lo = bb - 10'd1;
        return ~lo[8:0];
    endfunction

    // isolate the lowest set bit of 81, two levels of 9 - never an index
    function automatic logic [80:0] iso81(input logic [80:0] v);
        logic [8:0]  gany, glow;
        logic [80:0] r;
        for (int g = 0; g < 9; g++) begin
            logic [8:0] s;
            for (int k = 0; k < 9; k++) s[k] = v[g*9 + k];
            gany[g] = |s;
        end
        glow = iso9(gany);
        for (int g = 0; g < 9; g++) begin
            logic [8:0] s, e;
            for (int k = 0; k < 9; k++) s[k] = v[g*9 + k];
            e = glow[g] ? iso9(s) : 9'd0;
            for (int k = 0; k < 9; k++) r[g*9 + k] = e[k];
        end
        return r;
    endfunction

    // one-hot 81 -> 7-bit index. Only ever drives a register.
    function automatic logic [6:0] enc81(input logic [80:0] v);
        logic [6:0] r;
        r = 7'd0;
        for (int b = 0; b < 7; b++) begin
            logic t;
            t = 1'b0;
            for (int c = 0; c < 81; c++) if (c[b]) t = t | v[c];
            r[b] = t;
        end
        return r;
    endfunction

    //------------------------------------------------------- candidate lattice
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

    //--------------------------------------------- forced cells and dead ends
    logic [NC-1:0][8:0] forced;      // digits this cell is forced to
    logic [NC-1:0]      forcedany, deadcell;
    logic               nohome;

    always_comb begin
        logic nh;
        logic [NC-1:0][8:0] fh;      // hidden-single contributions, scattered
        nh = 1'b0;
        fh = '0;
        // Walk (unit, digit) once and scatter onto the cell, rather than asking
        // each of 81 cells about each of NU*9 (unit, digit) pairs.
        for (int u = 0; u < NU; u++) begin
            for (int d = 0; d < 9; d++) begin
                logic [8:0] s9, i9;
                logic       one;
                for (int k = 0; k < 9; k++) s9[k] = availc[SUD_UNIT_CELLS[u][k]][d];
                i9  = iso9(s9);
                one = ~used[u][d] & (s9 == i9) & (s9 != 9'd0);
                if (~used[u][d] & (s9 == 9'd0)) nh = 1'b1;
                for (int k = 0; k < 9; k++)
                    if (one & i9[k]) fh[SUD_UNIT_CELLS[u][k]][d] = 1'b1;
            end
        end
        nohome = nh;

        for (int c = 0; c < NC; c++) begin
            logic [8:0] a, nak;
            a   = availc[c];
            nak = ((a == iso9(a)) && (a != 9'd0)) ? a : 9'd0;   // naked single
            forced[c]    = nak | fh[c];
            forcedany[c] = |(nak | fh[c]);
            deadcell[c]  = emptyc[c] && (a == 9'd0);
        end
    end

    //------------------------------------------------------------ MRV (MODE 2)
    // Guessing only happens when nothing is forced, so no empty cell has one
    // candidate then: the lowest reachable count is 2. Build a mask per count
    // and take the lowest non-empty one - all in one-hot, no min-tree of indices.
    logic [NC-1:0] mrv_pick;
    always_comb begin
        logic [80:0] byn [2:9];
        logic [80:0] r;
        for (int k = 2; k <= 9; k++) byn[k] = '0;
        for (int c = 0; c < NC; c++) begin
            logic [3:0] n;
            n = popc9(availc[c]);
            for (int k = 2; k <= 9; k++)
                if (emptyc[c] && (n == 4'(k))) byn[k][c] = 1'b1;
        end
        r = '0;
        for (int k = 9; k >= 2; k--) if (|byn[k]) r = byn[k];
        mrv_pick = r;
    end

    //------------------------------------------------------------- the decision
    logic [NC-1:0] selv;
    logic [8:0]    selmask, pick_bit;
    logic          pick_forced, pick_dead, any_empty;

    assign any_empty = |emptyc;
    assign pick_dead = (|deadcell) | nohome;
    assign pick_forced = |forcedany;

    always_comb begin
        logic [80:0] cand_v;
        if (pick_forced)       cand_v = forcedany;
        else if (MODE == 2)    cand_v = mrv_pick;
        else                   cand_v = emptyc;
        selv = iso81(cand_v);
    end

    always_comb begin
        logic [8:0] m;
        m = 9'd0;
        for (int c = 0; c < NC; c++)
            m = m | ({9{selv[c]}} & (pick_forced ? forced[c] : availc[c]));
        selmask = m;
    end
    assign pick_bit = iso9(selmask);

    //---------------------------------------------------------- backtrack view
    logic [6:0] top_cell;
    logic [8:0] top_dig;
    logic       top_forced;
    logic [NC-1:0] topv;
    logic [8:0] top_used, top_retry;

    assign top_cell   = st_cell  [sp - 7'd1];
    assign top_dig    = st_dig   [sp - 7'd1];
    assign top_forced = st_forced[sp - 7'd1];

    always_comb begin
        for (int c = 0; c < NC; c++) topv[c] = (top_cell == c[6:0]);
    end
    always_comb begin
        logic [8:0] m;
        m = 9'd0;
        for (int c = 0; c < NC; c++) m = m | ({9{topv[c]}} & cellused[c]);
        top_used = m;
    end
    // the popped digit is certainly in top_used, so removing it is just a mask
    assign top_retry = ~(top_used & ~top_dig) & 9'h1FF & above9(top_dig);

    //-------------------------------------------------------------------- FSM
    logic [80:0][3:0] pz_flat;
    assign pz_flat = puzzle_in;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; sp <= 7'd0; done <= 1'b0; success <= 1'b0;
            sol <= '0; used <= '0;
        end else begin
            case (state)
                IDLE: if (start) state <= INIT;

                INIT: begin
                    done <= 1'b0; success <= 1'b0; sp <= 7'd0;
                    for (int u = 0; u < NU; u++) begin
                        logic [8:0] m;
                        m = 9'd0;
                        for (int c = 0; c < NC; c++)
                            if (SUD_MEMBER[u][c] && pz_flat[c] != 4'd0)
                                m = m | (9'd1 << (pz_flat[c] - 4'd1));
                        used[u] <= m;
                    end
                    for (int c = 0; c < NC; c++)
                        sol[c] <= (pz_flat[c] == 4'd0) ? 9'd0 : (9'd1 << (pz_flat[c] - 4'd1));
                    state <= STEP;
                end

                STEP: begin
                    if (!any_empty)     state <= DONE_S;
                    else if (pick_dead) state <= BACK;
                    else begin
                        for (int c = 0; c < NC; c++) if (selv[c]) sol[c] <= pick_bit;
                        for (int u = 0; u < NU; u++) begin
                            logic hit;
                            hit = 1'b0;
                            for (int c = 0; c < NC; c++)
                                if (SUD_MEMBER[u][c]) hit = hit | selv[c];
                            if (hit) used[u] <= used[u] | pick_bit;
                        end
                        st_cell  [sp] <= enc81(selv);
                        st_dig   [sp] <= pick_bit;
                        st_forced[sp] <= pick_forced;
                        sp <= sp + 7'd1;
                    end
                end

                BACK: begin
                    if (sp == 7'd0) state <= DONE_F;
                    else begin
                        logic [8:0] nb;
                        logic       retry;
                        retry = !top_forced && (top_retry != 9'd0);
                        nb    = iso9(top_retry);
                        for (int c = 0; c < NC; c++)
                            if (topv[c]) sol[c] <= retry ? nb : 9'd0;
                        for (int u = 0; u < NU; u++) begin
                            logic hit;
                            hit = 1'b0;
                            for (int c = 0; c < NC; c++)
                                if (SUD_MEMBER[u][c]) hit = hit | topv[c];
                            if (hit) used[u] <= retry ? ((used[u] & ~top_dig) | nb)
                                                      :  (used[u] & ~top_dig);
                        end
                        if (retry) begin
                            st_dig[sp - 7'd1] <= nb;
                            state <= STEP;
                        end else sp <= sp - 7'd1;
                    end
                end

                DONE_S: begin success <= 1'b1; done <= 1'b1; end
                DONE_F: begin success <= 1'b0; done <= 1'b1; end
                default: state <= IDLE;
            endcase
        end
    end

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
