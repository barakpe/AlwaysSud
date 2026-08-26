# Backlog

Ideas found while working on something else. **They do not get implemented on the
current branch** - one hypothesis per branch, or a "3.2x" turns out to be four
changes and we never learn which one paid.

Promote an item by opening `feat/<name>` for it.

---

1. **Placement + backtrack counters.** Return them in the spare bits of `done_reg`.
   This separates *searched less* from *searched faster*, and without it the v4/MRV
   result cannot be interpreted. **Do this early** - it is cheap now and impossible
   to reconstruct from old runs later. Changing `done_reg` changes the `.svh`, so it
   needs a bitstream rebuild.

2. **Add two harder puzzles.** `hard1` is hard for *raster-order* DFS specifically.
   MRV deserves an opponent chosen to test it rather than to flatter it. Same file
   format (81 hex bytes). Add *after* v0 is recorded so history stays comparable.

3. **Check packed vs unpacked.** ex3.1 declares `grid` and `stack` as unpacked
   arrays, which Quartus may infer as block RAM. RAM has two ports - fine for a stack
   touched one entry at a time, fatal for anything read 81-at-once. Confirm from the
   v0 resource report before building v2.

4. **Sample the solver inputs.** `alwaysud.sv` carries the reference's own TODO:
   *"consider sampling solver inputs"* and *"Consider sampling solver outputs"*.
   Worth understanding whether that costs a cycle or buys timing.

5. **Suppress printing for a clean timing run.** The board's wall-clock is dominated
   by UART. A print-suppressed mode would let us measure the real end-to-end time
   once the cycle counts get small.
