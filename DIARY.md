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

## A units table, and a gate that can finally fail - 2026-08-31

**Result:** `bench/units.py` is now the only place in the project that knows which cells
constrain which. `solve_ref.py` and `diagnose.py` both derive peers, hidden singles and
legality from it. Goldens byte-identical before and after, and all four hardware runs
still PASS - so the refactor changed structure, not behaviour.

**The test that matters** is not that classic still passes. It is that something now
fails. Judging the real v0 hard1 grid:

| variant | units | verdict |
|---|---|---|
| classic | 27 | LEGAL |
| diagonal | 29 | **ILLEGAL** - duplicates on both main diagonals |
| windoku | 31 | **ILLEGAL** - duplicates in three hyper boxes |

An hour ago the gate would have passed all three, because it only knew rows, columns and
boxes. A gate that cannot fail is not a gate, and this one could not fail on the exact
scenario it exists for - the 9 September variant.

**Surprise:** none of the four course boards has a solution under `diagonal`. Their givens
already contradict the extra constraint. So a variant does not just mean new rules, it
means **new board files**, and any plan that assumed we would re-run easy1/hard1 under new
rules was wrong. Worth knowing now rather than on the day.

**Second thing found:** the geometry was written out four separate times - three inside
`solve_ref.py` (peers, hidden singles, and implicitly the search) and a fourth in
`diagnose.py`. Four copies of a definition that a variant changes is four chances to
update three of them. That is the same shape as the register layout living in both
`alwaysud.h` and `alwaysud.sv`, and the same shape as the handoff enumerating files
instead of comparing a commit. It keeps being the same bug.

**Also:** the oracle now validates its own output - illegal grid, or a changed given, and
it raises rather than returning. That is a direct consequence of the naked-singles model
that produced an illegal board, returned it, and drove a roadmap. The oracle should be
held to the standard it holds the hardware to.

**What is still open, and it is the half that is graded:** the RTL has the geometry baked
into `alwaysud_solver.sv`. On hackathon day the checker adapts by editing one file; the
hardware does not. That is now the whole of risk 2.

---

## The 155 cycles ARE the timer split - and I refuted a true claim - 2026-08-31

**Result:** measured on the board. One bitstream, one flag, four puzzles.

| board | `SPLIT=0` one window | `SPLIT=1` setup + solve | delta |
|---|---|---|---|
| easy1 | 363 | 235 + 283 = 518 | +155 |
| 20blanks | 483 | 235 + 403 = 638 | +155 |
| 51blanks | 56,883 | 235 + 56,803 = 57,038 | +155 |
| hard1 | **128,760,819** | 235 + 128,760,739 | +155 |

`SPLIT=0` reproduces the historical 363 / 483 / 56,883 exactly. **The claim we had
recorded was right all along.**

**What I did wrong, and it is worth being precise about.** Earlier today I set out to
*test* that claim, read `k5_utils_lib.h:96-109` on the way, and found the cycle counter is
reset *after* `bm_printf`. I concluded the split had to be free, went looking for another
culprit, eliminated three, found none, and wrote the claim up as unattributed - editing
STATE.md, DIARY.md and MEASUREMENT.md to say so.

The reading was correct. The print really is excluded. **The inference was wrong**, because
the print is not the only thing an extra call costs. The direct probe - two report calls
back to back with no work between - says the seam is **35 cycles**. The other ~120 is code
generation.

I replaced a true claim that had weak evidence with a false claim that had *better-looking*
evidence, because source code feels more authoritative than arithmetic. It was still one
step short of the experiment, and the experiment took four minutes once the board was up.

**The finding that outlives the 155.** In the probe run, `setup+load` moved 235 -> 275 and
`solve` 283 -> 331. Nothing was added before either window and the RTL was untouched. The
RISC-V waits for the accelerator by polling a done register *in software*, so changing the
code changes register allocation and loop layout, and the poll notices completion at a
different point. The measured cycles include that quantisation.

So: **small-board cycle counts are not a pure hardware property.** A 40-cycle easy1
"improvement" can be produced by recompiling. From now on, an easy1 movement under ~50
cycles is noise unless the binary is identical - and that is a rule about the measurement,
not about the design. hard1 is immune: 155 in 128,760,819 is 0.0001%, and the score is
1.4797 s under either window.

**Third time.** The naked-singles model, the reference directory, and now this. Every one
was a case of trusting a derived artifact - a model, a vendored copy, a source reading -
over the thing itself. The pattern is not carelessness; each felt like the rigorous move at
the time. Measure the thing.

---

## v0 on hardware - 2026-08-31 - the first real number, and a model that held

**Result:** all four boards run on the DE10-Lite and PASS both gates - our golden
comparison and the app's own final checker. easy1 283 / 20blanks 403 / 51blanks 56,803 /
**hard1 128,760,739** solve cycles, with a flat 235 setup+load on every one.

**The score: 128,760,739 / 87.02 MHz = 1,479,668 us = 1.4797 s.**

The three simulatable boards matched simulation *to the digit*. That is the fourth time
this course that sim and fabric have agreed exactly, and it is worth saying out loud why
it is not luck: the same RTL was compiled by both, and nothing in this design depends on
timing, only on cycles.

**Surprise:** the hard1 FSM model was right. It predicted 128,760,553 and the board did
128,760,739 - **+186 cycles in 128.7 million, 0.00014% low**. I had been treating that
model as a rough planning aid because hard1 needs ~30 h of RTL simulation and nobody was
ever going to run it. It is better than that. Every future rung's hard1 estimate comes
from the same model, so the whole ladder is now planned on something that has been checked
against reality once rather than on nothing.

Worth being precise about what was validated: the model reproduces the *search*, and hard1
is 99.99% search. It has not been validated on a board where propagation dominates, which
is exactly what v2 and v3 are meant to create. Expect it to drift there, and re-check.

**Second thing the run settled:** setup+load is 235 cycles on hard1 too - identical to
easy1, which has three blanks. The 32+32+17 burst cost is genuinely independent of the
puzzle, so all future improvement has to come out of the solve window. That also means the
235 is a floor: at v3's predicted ~26 solve cycles, *load would be 90% of the runtime*.

**Process note.** The cloud-to-laptop handoff ran end to end for the first time - release
downloaded, commit gate, both md5s, stage, program, run - and the commit gate is the part
that earned its place. The release was built from `74e1b12`; the working tree was already
a commit ahead at `7253138`. A file-list check would have had to know that the newer commit
touched only `.claude/skills` and `logs/`. `git diff <sha> -- sw/apps hw/xlrs` just said
clean, and it would equally have caught a change to `alwaysud.h`, which no file list we
had ever written mentioned.

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
