# Backlog

Ideas found while working on something else. They do not get implemented on the current
branch — one hypothesis per branch, or a "3.2x" turns out to be four changes and we never
learn which one paid.

Promote an item by opening `feat/<name>`. The planned sequence is in `STATE.md`.

---

1. **Units table in the RTL.** `bench/units.py` did this for the checker; the RTL still has
   rows/columns/boxes baked into `is_valid`. Isolate "does digit d conflict at (r,c)" into
   one place so a variant touches only that. **Top of the list** — it is the hackathon
   risk, and propagation is defined over units so v2 needs it anyway.

2. **Placement + backtrack counters** in the spare bits of `done_reg`. Separates *searched
   less* from *searched faster*; without them a v2 result cannot be interpreted. Cheap now,
   impossible to reconstruct later. Changes the `.svh`, so it needs a bitstream rebuild.

3. **Attack the LOAD path.** Setup is a fixed 235 cycles regardless of puzzle. Once the
   solve window is small it dominates the rate — at v3's predicted ~26 cycles it would be
   90% of the score. Nothing to do until v2/v3 land, but it is where the project ends.

4. **Fix the two real synthesis warnings** on the first branch that forks the RTL. Both are
   inherited and both are one edit from being bugs:
   - `10230` ×3, `alwaysud.sv:83` — 32-bit host register truncated to 16-bit
     `XMEM_ADDR_WIDTH`. Safe only because the board sits at xmem offset 0.
   - `10027` ×1, `alwaysud_solver.sv:65` — `grid[br+dr][bc+dc]` index expression too narrow
     for a 9-element array. Safe only because br,bc ∈ {0,3,6} and dr,dc ∈ 0..2.

5. **Two harder puzzles.** `hard1` is hard for *raster-order* DFS specifically. Once the
   algorithm changes it stops being a fair opponent. Same file format; add after a tag so
   history stays comparable.

6. **Register the solver boundary.** `alwaysud.sv` carries the reference's own TODO,
   *"consider sampling solver inputs"*. Worth measuring if F_max ever becomes the binding
   constraint — but note pipelining as a *strategy* is deleted; this is one register, not a
   pipeline.

7. **Print-suppressed mode.** Board wall-clock is dominated by UART. Only interesting if we
   ever want real end-to-end time; the score does not use it.

8. **Delete `reference/ex2.1/`** if it is still unreferenced when the variant lands. Week
   2's `sudx_basic` is a different accelerator and nothing points at it. See
   `reference/PROVENANCE.md`.

---

## Closed

- ~~Integrate `claude_mrv`~~ — deferred to insurance. Its value is better guesses; v3
  predicts zero guesses. See `STATE.md`.
- ~~Pipeline the MRV critical path~~ — deleted. The 5.52 MHz is one badly-written
  reduction, not a pipelining problem, and pipelining loses on a cycles/F_max metric.
- ~~Check packed vs unpacked arrays~~ — answered by v0: **0 memory bits**, everything is in
  flip-flops. Nothing was inferred as block RAM. Re-check if candidate masks are ever
  stored rather than recomputed.
