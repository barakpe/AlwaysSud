# Development diary

One entry per experiment, newest first. Fixed shape so entries stay comparable.

The **Surprise** line is the point of the whole document: it is where the learning
goes, and it is what turns a table of numbers into something you can talk about.

---

## Template

```
## <tag> - <date>
Hypothesis:  what we expected to happen, and why
Change:      what was actually modified
Result:      cycles per board, before -> after; LEs; F_max; correctness
Verdict:     merged / reverted / kept-as-enabler
Surprise:    what we did not expect. If nothing surprised you, say so - that is
             information too, and usually means the change was well understood.
```

---

## upstream fixes pulled in - 2026-08-29

Not our change, but it lands in our tree, so it belongs in the record.

The instructor published `docs/bug_and_checker_fixing.md` in `ex3.1` with two updates.
We had already ported the **pre-fix** files, so we carried the bug.

**The bug** (`sudx_scan.sv`, STORE state, fixed by Bar Ivry 27/8): the write-back loop
indexed `solver_puzzle_out_flat[stored_start_idx+i]` where it should have been
`next_store_start_idx+i`. Same two-pointer confusion as LOAD - `stored_start_idx` is
where the *previous* burst went, `next_store_start_idx` is where the burst being
assembled now belongs. Effect: the solved board was written back to xmem at the wrong
offset, so the grid the software printed was wrong even when the solver was right.

**The checker**: `check_solved_board()` added to `sud_lib`, called by the app after it
prints. The banner also changed from `=== Solved ===` to
`=== Application reported Solved ===`.

**That banner change silently broke our correctness gate.** `bench/solve_ref.py` split
on the literal `"=== Solved ==="`, which is *not* a substring of the new message, so
`extract()` returned None and every check would have reported "no solved grid found".
Now matched by regex, anchored on the *last* banner in the log, and the app's own
checker verdict is reported alongside ours.

**Surprise:** the instructor's own `cp` command in that doc has a bug of its own - the
destination path for the `.sv` is missing the `sudx_scan/` subdirectory, so it drops a
stray file into `hw/xlrs/` and the fix silently does not apply. Filed as a bonus
candidate. Notable that our independent oracle would have caught the underlying store
bug immediately, which is exactly why it does not share code with the hardware.

---

## v0 - 2026-08-31 - measured, passing, and a correction to my own analysis

**Result:** all three simulatable boards PASS, golden gate and the app's own checker.
363 / 483 / 56,883 cycles. Standalone 9,286 LEs, 1,867 registers, 0 memory bits,
87.02 MHz. Full system 20,560 LEs, 55.29 MHz, 79% memory bits, 1.9 ns of slack against
the 50 MHz requirement. Bitstream built.

**hard1 is 128,760,553 cycles**, not the ~50M the assignment estimates - so v0 is 1.48 s
and every ratio previously recorded was understated by 2.6x.

**Verdict:** this is the baseline. Tag it.

**Surprise, and it is mine.** The propagation floor I used to justify rebuilding the whole
ladder had a bug in exactly the place the roadmap's own risk list warns about. The model
placed all naked singles in a round at once without checking whether two cells in the same
unit were being forced to the *same digit* - a contradiction. It built illegal grids, never
validated the final board, and returned one. hard1 naked-only was reported as 91 rounds /
14 guesses; corrected it is **279 / 68**, which is what the cloud agent got independently.

What should have caught it was not arithmetic but logic: naked-only cannot need fewer
guesses than the strictly stronger naked+hidden. The number was internally inconsistent and
I did not check it against itself.

The conclusion survives - three of four boards still need zero search, and with pairs and
box-line even hard1 does - but it survives on the agent's numbers, not mine. Lesson
recorded: a model that produces a plan needs the same correctness gate as the hardware.

**Also corrected:** `claude_mrv`'s 5.52 MHz is not the popcounts. It is a minimum
reduction written as a serial accumulator - 303 of 334 cells on the critical path - where a
tree would be depth 7. The fix is a rewrite, not pipelining, and costs zero cycles. The
`v3-pipe` rung was deleted; so was `v5-clock`, since `-mhz` cannot move the standalone
F_max the score is computed from.
