//=============================================================================
// alwaysud_solver (s2rr / D6) - same algorithm as MODE 1/2 of the plain solver,
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
// MODE 1 = raster guess cell, MODE 2 = MRV guess cell.
// MODE 3 = MRV and NOTHING ELSE: no naked or hidden singles, so the inference
//          logic optimises away. That is the "add MRV to the reference solver"
//          step measured on its own, which is the only way to compare it fairly
//          against the singles step rather than against v0.
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
    localparam int KMIN = (MODE == 3) ? 1 : 2;

    logic [NC-1:0][8:0] sol;
    logic [NU-1:0][8:0] used;
    logic [6:0] sp;
    logic [6:0] st_cell   [0:80];
    logic [8:0] st_dig    [0:80];
    logic       st_forced [0:80];

    typedef enum logic [2:0] { IDLE, INIT, STEP, BACK, DONE_S, DONE_F } state_t;
    state_t state;

    //-------------------------------------------------------------- primitives
    // Isolate the lowest set bit of 9, as a one-hot 9-bit vector.
    //
    // The obvious way to write this is a running `seen` accumulator:
    //     seen = 1'b0;
    //     for (i) begin r[i] = v[i] & ~seen; seen = seen | v[i]; end
    // which is a NINE-DEEP RIPPLE, and iso81() calls iso9() twice in series, so
    // that costs ~18 logic levels on the critical path. Measured: it was on
    // s2fast's worst path at 24.37 MHz.
    //
    // This is the same function as a logarithmic prefix-OR - Sklansky/Hillis-Steele,
    // shift-and-OR by 1, 2, 4 - which is 4 levels instead of 9. `lower` ends up
    // holding "some bit below me is set", and the lowest set bit is the only one
    // where that is false.
    function automatic logic [8:0] iso9(input logic [8:0] v);
        logic [8:0] p, lower;
        p     = v;
        p     = p | (p << 1);            // level 1: OR in the neighbour below
        p     = p | (p << 2);            // level 2
        p     = p | (p << 4);            // level 3  -> p[i] = |v[i:0]
        lower = {p[7:0], 1'b0};          // shift down: lower[i] = |v[i-1:0]
        return v & ~lower;               // level 4
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

    // ---- hidden singles, ONE UNIT PER CYCLE (this is the whole of D6) --------
    //
    // s2fast tests all NU*9 (unit, digit) pairs every cycle: 243 exactly-one-of-9
    // detectors, each reading nine cells' candidate masks. That is 2,187 wires off
    // the candidate array, and measured, it is what makes the design fail to route
    // - not its size and not its F_max (mrvonly is 22,224 LE and routes in 23 min;
    // s2fast is 25,098 LE and routes in 3h37, after failing once).
    //
    // Here there are NINE detectors. A registered pointer walks the units one per
    // clock. The gather is a 27:1 mux of a fixed 81-bit bundle per unit, which is
    // ordinary muxing rather than all-to-all fan-in. Naked singles and the
    // empty-domain check stay parallel: they are 81 one-hot tests and cost little.
    //
    // Price: a hidden single takes up to NU cycles to find instead of 1.
    // Modelled as arch "s2r" - hard1 295 -> 954, worst case 2.44x.
    logic [6:0] rr_u;                      // which unit we are looking at this cycle
    logic [8:0][8:0] unit_avail;           // that unit's nine candidate masks
    logic [8:0]      unit_used;

    always_comb begin
        unit_avail = '0;
        unit_used  = '0;
        for (int u = 0; u < NU; u++)
            if (rr_u == u[6:0]) begin
                for (int k = 0; k < 9; k++) unit_avail[k] = availc[SUD_UNIT_CELLS[u][k]];
                unit_used = used[u];
            end
    end

    always_comb begin
        logic [NC-1:0][8:0] fh;
        logic nh, hitv;
        logic [3:0] hitk;
        logic [8:0] hitb;
        fh = '0; nh = 1'b0; hitv = 1'b0; hitk = 4'd0; hitb = 9'd0;

        for (int d = 8; d >= 0; d--) begin      // lowest digit wins the priority
            logic [8:0] s9, i9;
            for (int k = 0; k < 9; k++) s9[k] = unit_avail[k][d];
            i9 = iso9(s9);
            if (!unit_used[d]) begin
                if (s9 == 9'd0) nh = 1'b1;                       // no home -> dead
                else if (s9 == i9) begin                          // exactly one home
                    hitv = 1'b1; hitb = 9'd1 << d;
                    for (int k = 0; k < 9; k++) if (i9[k]) hitk = k[3:0];
                end
            end
        end
        nohome = nh;

        // scatter the single hit back onto its cell
        for (int u = 0; u < NU; u++)
            if (rr_u == u[6:0])
                for (int k = 0; k < 9; k++)
                    if (hitv && (hitk == k[3:0])) fh[SUD_UNIT_CELLS[u][k]] = hitb;

        for (int c = 0; c < NC; c++) begin
            logic [8:0] a, nak;
            a   = availc[c];
            nak = ((a == iso9(a)) && (a != 9'd0)) ? a : 9'd0;
            forced[c]    = nak | fh[c];
            forcedany[c] = |(nak | fh[c]);
            deadcell[c]  = emptyc[c] && (a == 9'd0);
        end
    end

    // A guess is only allowed once every unit has been looked at with nothing
    // found, so `miss` counts consecutive fruitless unit examinations.
    logic [6:0] miss;
    logic       may_guess;
    assign may_guess = (miss >= 7'(NU - 1));

    // The round-robin pointer only moves when the UNIT SCAN is what made progress.
    // A naked single is found by the parallel per-cell logic and says nothing about
    // where the unit walk had got to, so it must not consume a unit slot.
    logic nakedany;
    always_comb begin
        nakedany = 1'b0;
        for (int c = 0; c < NC; c++)
            if (emptyc[c] && (availc[c] == iso9(availc[c])) && (availc[c] != 9'd0))
                nakedany = 1'b1;
    end

    //------------------------------------------------------------ MRV (MODE 2)
    // Guessing only happens when nothing is forced, so no empty cell has one
    // candidate then: the lowest reachable count is 2. Build a mask per count
    // and take the lowest non-empty one - all in one-hot, no min-tree of indices.
    logic [NC-1:0] mrv_pick;
    always_comb begin
        logic [80:0] byn [1:9];
        logic [80:0] r;
        // MODE 2 only guesses when nothing is forced, so no cell has one
        // candidate then and k starts at 2. MODE 3 has no inference at all, so
        // a single-candidate cell is still MRV's job and k must start at 1.
        for (int k = 1; k <= 9; k++) byn[k] = '0;
        for (int c = 0; c < NC; c++) begin
            logic [3:0] n;
            n = popc9(availc[c]);
            for (int k = KMIN; k <= 9; k++)
                if (emptyc[c] && (n == 4'(k))) byn[k][c] = 1'b1;
        end
        r = '0;
        for (int k = 9; k >= KMIN; k--) if (|byn[k]) r = byn[k];
        mrv_pick = r;
    end

    //------------------------------------------------------------- the decision
    logic [NC-1:0] selv;
    logic [8:0]    selmask, pick_bit;
    logic          pick_forced, pick_dead, any_empty;

    assign any_empty = |emptyc;
    assign pick_dead   = (|deadcell) | nohome;
    assign pick_forced = |forcedany;

    always_comb begin
        logic [80:0] cand_v;
        if (pick_forced)                        cand_v = forcedany;
        else if (MODE == 2)                     cand_v = mrv_pick;
        else                                    cand_v = emptyc;
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
            sol <= '0; used <= '0; rr_u <= 7'd0; miss <= 7'd0;
        end else begin
            case (state)
                IDLE: if (start) state <= INIT;

                INIT: begin
                    done <= 1'b0; success <= 1'b0; sp <= 7'd0;
                    rr_u <= 7'd0; miss <= 7'd0;
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
                    else if (!pick_forced && !may_guess) begin
                        rr_u <= (rr_u == 7'(NU-1)) ? 7'd0 : rr_u + 7'd1;
                        miss <= miss + 7'd1;      // look at the next unit, 1 cycle
                    end else begin
                        if (pick_forced && !nakedany)      // a hidden single: the
                            rr_u <= (rr_u == 7'(NU-1))     // unit walk made progress
                                    ? 7'd0 : rr_u + 7'd1;
                        miss <= 7'd0;
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
                            miss  <= 7'd0;
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
