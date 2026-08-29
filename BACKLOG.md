# Backlog

Ideas found while working on something else. **They do not get implemented on the
current branch** - one hypothesis per branch, or a "3.2x" turns out to be four changes
and we never learn which one paid.

Promote an item by opening `feat/<name>` for it.

---

1. **Build `sudx_mrv` / `alwaysud_mrv`.** Integrate `reference/ex3.1/sudx_standalone_ref/
   claude_mrv/sud_solver_mrv_claude.sv` into our wrapper, replacing `alwaysud_solver`.
   The wrapper already does LOAD / SOLVE / STORE and the solver interface is nearly the
   same shape (`clk, rst_n, start, puzzle_in, done, success, puzzle_solved` - the MRV
   one adds `busy`). **This is the single highest-value item on the list**: ~5,000x on
   the scoring formula.

2. **Pipeline the MRV critical path.** `claude_mrv` synthesises to ~5 MHz because
   choosing the minimum-candidate cell is one enormous combinational path: 81 popcounts
   feeding a min-reduction tree. Splitting that across 2-3 cycles could plausibly get
   10x the frequency for a small cycle cost - and on `solve_time = cycles / f_max` that
   is close to a straight 10x. **The differentiator: everyone will integrate MRV, few
   will fix its timing.**

3. **Placement + backtrack counters.** Return them in the spare bits of `done_reg`.
   Separates *searched less* from *searched faster*; without it an MRV result cannot be
   interpreted. Cheap now, impossible to reconstruct later. Changes the `.svh`, so it
   needs a bitstream rebuild.

4. **Modular constraint check, for the hackathon variant.** Isolate "does digit d
   conflict at (r,c)" into one place so a variant only touches that. See the hackathon
   note in `STATE.md`. Worth doing *before* the design ossifies.

5. **Add two harder puzzles.** `hard1` is hard for *raster-order* DFS specifically. MRV
   deserves an opponent chosen to test it rather than to flatter it. Same file format.
   Add after v0 is recorded so history stays comparable.

6. **Check packed vs unpacked.** ex3.1 declares `grid` and `stack` as unpacked arrays,
   which Quartus may infer as block RAM. RAM has two ports - fine for a stack touched one
   entry at a time, fatal for anything read 81-at-once. MRV reads all 81 cells every
   cycle, so this matters a great deal for item 1. Confirm from the v0 resource report.

7. **Sample the solver inputs.** `alwaysud.sv` carries the reference's own TODO:
   *"consider sampling solver inputs"* / *"Consider sampling solver outputs"*. Likely
   relevant to item 2 - registering the solver boundary is often the cheapest first
   pipeline cut.

8. **Suppress printing for a clean timing run.** The board's wall-clock is dominated by
   UART. Once cycle counts get small, a print-suppressed mode would let us measure real
   end-to-end time.
