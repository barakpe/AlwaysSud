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

## v0 - pending

Baseline measurement not yet taken. See `STATE.md`.
