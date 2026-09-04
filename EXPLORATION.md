# EXPLORATION — where the rate actually is

Branch `explore/opus5`, from `94df39f` ("strip prior conclusions").
Everything below is either **measured** on this cloud or **modelled** by a cycle model
that was validated against RTL simulation on 3,491 puzzles — every number says which.

The one-line answer:

> **The baseline's problem is not that it searches slowly. It is that it searches at
> all.** Adding constraint propagation — naked and hidden singles placed as forced,
> non-branching moves — takes `hard1` from 128,760,553 solver cycles to **335**, and
> the worst case over 4,341 held-out puzzles from 21.2 billion to **98,276**. That is
> worth ~63,000x on `hard1` and ~55,000x on the worst case **even after paying a
> measured 3.9x in F_max** (87.02 → 22.34 MHz). Frequency is now the only thing left
> worth optimising, and it is the thing I have least evidence about.
>
> The number with no modelling anywhere in it: on `51blanks` — the board
> `docs/MEASUREMENT.md` designates as *the* correctness gate — the full K5 run goes
> from **56,803 to 235 measured solve cycles**, gate passed, app checker agreeing
> (§6a).

### At a glance

| # | direction | `hard1` cycles | worst of 4,341 | F_max | LE | rate on `hard1` | vs v0 | state |
|---|---|---|---|---|---|---|---|---|
| — | **v0** baseline | 128,760,553 | 21,174,957,605 | 87.02 MHz | 9,286 | 1.4797 s | 1x | measured on HW |
| **D1** | masks + naked/hidden singles | **335** | **98,276** | **22.34 MHz** | **25,774** | **23.32 µs** | **63,447x** | RTL, synthesised |
| **D2** | + one-hot selection | **295** | **50,166** | `PENDING` | **25,098** | `PENDING` | | RTL, **K5 gate PASSED**, fitting |
| **D3** | + MRV guess cell | 193 | 17,116 | `PENDING` | `PENDING` | | | RTL, queued |
| **D4** | parallel commit | 102 | 21,149 | — | — | | | modelled only |
| **D5** | cut the window overhead | −186 flat | −186 flat | — | — | | ≤1.5x | measured cost only |
| **D6** | time-multiplex the detectors | 954 | 239,403 | — | — | | | modelled only |
| ✗ | masks alone, no inference | 19,454,731 | 3,253,371,343 | 47.61 MHz | 17,132 | 408.6 ms | 3.6x | **dead end** |
| ✗ | masks + MRV, no singles | 901 | 672,313 | `PENDING` | `PENDING` | | | **dead end** |

Cycles are solver-FSM cycles; rate = (cycles + 186) / F_max. "Worst of 4,341" is the
maximum over every held-out set and all three geometries — the number I would bet on,
not the `hard1` column.

---

## 0. What I did, and why you can believe the numbers

`hard1` cannot be simulated, so everything hangs off a cycle model. Here is the chain.

| step | what | evidence |
|---|---|---|
| 1 | Reproduced the v0 baseline synthesis | **9,286 LE / 1,867 reg / 0 mem bits / 87.02 MHz** — identical to `RESULTS.md`, so my flow is the same flow |
| 2 | Rebuilt the v0 FSM in a geometry-generic model | reproduces `logs/v0/models/v0hard.c` exactly: 21,759,570 finds / 97,273,649 tries / 9,727,332 backtracks on `hard1` |
| 3 | Wrote the candidate architectures as models in the same file | `explore/model/arch.c`, one function per architecture, events counted separately from cycles |
| 4 | Wrote real RTL for the promising ones | `explore/rtl/alwaysud_solver.sv`, `alwaysud_solver_fast.sv` — same ports as v0, drop-in |
| 5 | **Validated model against RTL on 3,491 puzzles, not 3 boards** | `xrun` on the solver module directly: **0 cycle mismatches, 0 wrong grids** |
| 6 | Synthesised each with `qsyn_xlr -all` | F_max / LE / registers / memory bits, `check_synth.sh` clean |

Step 5 is the load-bearing one. A standalone testbench (`explore/rtl/tb_solver.sv`)
drives the solver module directly, so a run over thousands of puzzles costs minutes
instead of the K5 flow's ~40 s per board. Results:

```
rf_s2u_published.txt  vs model s2u/classic    n=3191  cycle-mismatches=0  non-ok=0
rf_s2u_diag.txt       vs model s2u/diagonal   n=300   cycle-mismatches=0  non-ok=0
rtl_s2_published.txt  vs model s2 /classic    n=3191  cycle-mismatches=0  non-ok=0
```

plus the four repo boards under every mode, exact:

| mode | easy1 | 20blanks | 51blanks | hard1 | model says |
|---|---|---|---|---|---|
| M1 (masks only) | 8 | 23 | 8,368 | *(19.5M, not simulated)* | 8 / 23 / 8,368 ✓ |
| MRV only | 6 | 23 | 54 | 901 | 901 ✓ |
| S2 (singles) | 6 | 23 | 54 | 335 | 335 ✓ |
| S2U (unified) | 6 | 23 | 54 | 295 | 295 ✓ |
| S2M (singles+MRV) | 6 | 23 | 54 | 193 | 193 ✓ |

So the model is not "trustworthy if you validate it" — it is exact, on 3,491 puzzles
across two different geometries, for every architecture I quote.

**These are solver-FSM cycles.** The `report_task_performance("Sudoku solve")` window
is larger by a fixed amount. The chain for a `hard1` prediction is therefore:

```
   solver cycles          exact, my model == my RTL on 3,491 puzzles      (measured)
 + window overhead        186 on v0, model vs hardware, puzzle-independent (measured)
 = measured window
```

The second term is the weaker link, and I say so: it was measured with **v0's binary**,
and `docs/MEASUREMENT.md` warns that small-board counts are not a pure hardware property
because recompiling moves the RISC-V poll loop. It is puzzle-independent (186 on `hard1`
against 180/189/200 on the small boards) and it is wrapper-plus-software, not solver, so
it should carry — but "should" is doing work there. The K5 end-to-end run in §6 measures
it directly for the new design; that is what turns the prediction into a number.

### The held-out set

The repo has four puzzles and I did not tune against anything outside them, but four
is not a sample. My held-out set is **4,341 puzzles I did not design against**:

| set | n | what | source |
|---|---|---|---|
| `ho_published` | 3,191 | union of Norvig top95 + hardest, magictour top1465 + top2365, `hard1` **removed** | fetched, `explore/puzzles/` |
| `gen_classic_min` | 400 | minimal puzzles (no given removable), 21–26 clues | generated, seed 101 |
| `gen_classic_easy` | 150 | 40-clue puzzles, the easy end | generated, seed 102 |
| `gen_diagonal_min` | 300 | **X-Sudoku** minimal | generated, seed 201 |
| `gen_diagonal_easy` | 150 | X-Sudoku, 40 clues | generated, seed 202 |
| `gen_windoku_min` | 150 | Windoku minimal (a third geometry, as a control) | generated, seed 301 |

`hard1` turns out to be **line 1 of Norvig's top95** — the puzzle he cites as defeating
naive left-to-right brute force. It is a hard case *for raster DFS*, exactly as your
brief warned, and it is not the worst case (§5).

The generator (`explore/model/gen.py`) builds a random full grid for the variant, then
digs while checking uniqueness — so the X-Sudoku puzzles satisfy the diagonals by
construction, which the four course boards cannot (they have no diagonal solution).

---

## 1. RANKED DIRECTIONS

Ranked by measured rate on `hard1`, with the held-out worst case beside it because
that is the number that survives a hackathon puzzle you have not seen.

### D1 — Candidate masks + naked/hidden singles as forced moves ★ the whole win

**What.** Two changes that only make sense together.

*Masks.* Stop storing the board as 4-bit digits and stop asking "is `v` legal at
`(r,c)`?" with 27 comparators. Store one 9-bit `used` mask per **unit** (row, column,
box — or diagonal), and the board one-hot. The legal set for a cell is then
`~(used[u1] | used[u2] | used[u3])`: three register reads and an OR, available for all
81 cells simultaneously and for free. "Try nine digits" becomes "take the lowest set
bit". "Walk to the next empty cell" becomes a priority encoder.

*Singles.* On top of that, every cycle:
- if any empty cell has **no** candidate → contradiction, backtrack;
- else if any empty cell has **exactly one** candidate (naked single) → place it as a
  **forced** move, marked on the stack as never-to-be-retried;
- else if any digit has **exactly one** home left in some unit (hidden single) → same;
- else guess.

Forced moves cost one cycle each and are never branched on, so the search tree
collapses. The undo stays one cycle per placement because the entire state is still
just "which cells are assigned" — nothing is eliminated that is not also assigned.

**Measured.**

| | v0 | D1 (`s2`) |
|---|---|---|
| `hard1` solver cycles | 128,760,553 | **335** |
| standalone F_max | 87.02 MHz | **22.34 MHz** |
| logic elements (map / fit) | 9,286 / 8,864 | **25,774 / 25,030** |
| registers | 1,867 | 2,907 |
| memory bits | 0 | **0** |
| **rate on `hard1`** | **1.4797 s** | **23.32 µs** → **63,447x** |
| **rate, worst of 4,341 held-out** | 243.33 s | **4.41 ms** → **55,210x** |

*(cycles and F_max measured; rate = (cycles + 186) / F_max, see D5)*

**Depends on.** Nothing. Same module ports as v0, drops into `alwaysud.sv` unchanged.

**Effort.** The RTL exists and is validated: `explore/rtl/alwaysud_solver.sv`
(MODE=1, 356 lines) and `alwaysud_solver_fast.sv` (329 lines). The K5 end-to-end run is
done and passes the gate on all three simulatable boards (§6a). The remaining work is
hardware.

**Risk.** Area and frequency, not correctness. 25,774 LE is over the 20,000 in
`docs/MEASUREMENT.md` (though well under the ~50k device), and the fitter takes
**hours** instead of ~4.5 minutes: measured **2 h 37 m** for D1 and **over 3.5 h** for
D2, on a two-core machine where the router is the whole cost. That is a real charge
against your iteration loop, not just a number in a table.

### D2 — Keep the selection one-hot (the F_max fix)

**What.** The measured worst path of the mask design is an *encode-then-decode round
trip*: a priority encoder turns "which cell" into a 7-bit index, and then an 81:1 mux
turns that index back into the cell's candidate mask. From the m1 timing report:

```
sol[0][2] → Equal0 (is it empty) → Mux3 (priority encode) → first_empty
          → Mux8~76..114 (81:1 mux back to data) → used → sol[3][8]     24 cells
```

So: never form the index on the decision path. Choose with a tree that yields an
81-bit **one-hot**, read the chosen cell with an AND-OR tree, write it by gating with
the same vector. The 7-bit index is still produced — but only to be written into the
stack register, which is beside the critical path, not inside it.

While restructuring, the rule also unifies: a cell is *forced* if it is a naked single
**or** the unique home for a digit in any of its units; lowest forced cell wins. The
contradiction test becomes global (any empty cell with no candidate, or any unit-digit
with no home) instead of being asked only when no naked single exists.

**Measured (cycles).** `hard1` 335 → **295**. Worst held-out 98,276 → **50,166**;
median on `ho_published` 414 → 375.

Be careful how you read that: it is **not** a per-puzzle improvement. Measured across
the 3,191 published held-out puzzles, `s2u` is faster on 2,319, **slower on 500**, and
equal on 372. Only the contradiction test is strictly stronger; the selection order also
changes (lowest forced *cell* rather than naked-then-unit-major), and a different
tie-break is a different search tree, which can go either way. The aggregate wins and
the worst case improves — but "prunes strictly harder" would be false, and if you see an
individual board get slower after this change, that is expected, not a bug.

Zero mismatches against the model on 3,491 puzzles, two geometries.

**Measured (area).** **25,098 LE / 2,907 registers / 0 memory bits** from Analysis &
Synthesis — versus 25,774 for D1. So the one-hot restructuring is **not** an area win;
it is roughly the same logic arranged differently, which is what I expected: it removes
an 81:1 mux and a 7-to-81 decoder, and adds an 81-wide AND-OR tree and gating.

**Measured (frequency).** `PENDING-S2FAST` — the fit has been in the router for over
3.5 hours (v0's whole build is 4.5 minutes), and I put a deadline on it so the runs
that add a *new* axis could have the machine. If it is missing below, that is why, and
it is the single number I would re-run first.

Note **0 memory bits**, which is not a given at this size: the 81-entry decision stack
and the one-hot board stay in flip-flops rather than inferring block RAM. That matters
because `docs/MEASUREMENT.md` records system memory already at 79%.

**Depends on.** D1. It is a restructuring of the same algorithm, so do it *with* D1,
not after — it changes the datapath everywhere.

### D3 — MRV for the cell to guess at

**What.** When nothing is forced, guess at the cell with the fewest candidates instead
of the first empty one. Implemented one-hot as "build a mask per candidate-count, take
the lowest non-empty one" rather than as a min-tree of indices.

**Measured (cycles).** Pure worst-case insurance; it barely moves the median.

| set | without MRV (`s2u`) | with MRV (`s2um`) | gain |
|---|---|---|---|
| `ho_published` worst | 34,347 | 17,116 | 2.0x |
| `gen_classic_min` worst | 1,205 | 663 | 1.8x |
| `gen_diagonal_min` worst | 25,418 | 5,967 | 4.3x |
| `gen_windoku_min` worst | 50,166 | 7,282 | 6.9x |
| `hard1` | 295 | 193 | 1.5x |
| median, `ho_published` | 375 | 351 | 1.07x |

**Measured (frequency/area).** `PENDING-S2FASTMRV`

**Verdict rule, decided in advance.** Compare like with like: the worst case *across
all six sets* is 50,166 without MRV and 17,116 with it, so **MRV is worth it iff it
costs less than 2.9x F_max**. (The 6.9x in the Windoku row is one set's gain, not the
figure to bet on — MRV moves which puzzle is the worst one, so per-set ratios overstate
it.) If MRV costs less than 2.0x it also pays for itself on classic alone.

### D4 — Parallel commit: place every forced cell in one cycle

**What.** D1 places one forced cell per cycle. Everything needed to place *all* of them
is already computed combinationally, so commit them together, with a check that no two
cells in a unit are forced to the same digit and no cell is forced to two digits
(either is a contradiction, and backtracking on it is correct). Undo then needs a
decision-level tag per cell — 7 bits × 81 — and clearing every cell with level ≥ L is
one parallel compare.

**Modelled only — no RTL, no F_max.** `hard1` 335 → **102**; worst `ho_published`
36,841 → 10,377; worst X-Sudoku 34,910 → 6,746.

**Why it is ranked below D3 despite bigger numbers.** Three reasons, in order.

1. Against D2 rather than D1, the gain shrinks to **2.4x** on the worst case across all
   sets (50,166 → 21,149), on a term already around 2 ms.
2. **Its cycles are mostly propagation rounds, so it is the direction that a pipelined
   round would hurt most.** Measured on the worst held-out puzzle: p3 spends 4,888 of
   its 7,330 cycles — 67% — in propagation. If the round has to be split over two
   clocks to make timing, p3 goes to ~12,200 and most of the advantage is gone. D2's
   cycles are placements, which split much better.
3. The multi-commit conflict detection (two cells in a unit forced to the same digit,
   one cell forced to two digits) is the one piece of this whole design that can be
   subtly wrong, and it is wrong in the direction that produces an answer rather than a
   hang.

Its real attraction is different from the cycle count: it deletes the priority encoders
from the forced path entirely, so it may be a *shorter* critical path than D1, not just
fewer cycles. That is worth one synthesis run — and if it clocks well it jumps the
ranking.

### D6 — Time-multiplex the hidden-single detectors (the area answer)

**What.** D1 tests all `NU x 9` (unit, digit) pairs every cycle: 243 "exactly one of
nine" detectors, and that is most of the 25k LE. The same questions can be asked with
**one unit's worth of logic, round-robin, one unit per cycle**. Naked singles and the
empty-domain check stay parallel — they are 81 one-hot detects and cheap.

**Modelled only (`s2r` / `s2rm` in `arch.c`).** Cycles, one unit examination per cycle:

| | `s2` (parallel) | `s2r` (round-robin) | ratio |
|---|---|---|---|
| `hard1` | 335 | 954 | 2.85x |
| worst `ho_published` | 36,841 | 81,322 | 2.21x |
| worst X-Sudoku | 34,910 | 68,363 | 1.96x |
| worst Windoku | 98,276 | 239,403 | 2.44x |
| **worst of all six sets** | **98,276** | **239,403** | **2.44x** |

**The whole direction is one division.** D6 is worth building iff it clocks above
**2.44 x 22.34 = 54.5 MHz**. That is between the measured 47.61 MHz of the mask design
and v0's 87.02, so it is genuinely uncertain — and it is the one direction here that
makes the design *smaller*, which is what fixes both the 20,000-LE limit in
`docs/MEASUREMENT.md` and the multi-hour fit. I did not have synthesis budget to settle
it; it is the first run I would spend after D1 lands.

### D5 — Attack the fixed ~186-cycle window overhead

**What.** Once the solver is at ~300 cycles, the part of the measured window that is
*not* the solver becomes a first-class term: register write, the wrapper's `STORE`
(three memory bursts), `DONE`, and the RISC-V's software poll loop noticing.

**Measured, from v0** (model vs. hardware, `logs/v0/hw/HW_RESULT.txt`):

| board | solver FSM (model) | measured window | overhead |
|---|---|---|---|
| easy1 | 103 | 283 | 180 |
| 20blanks | 214 | 403 | 189 |
| 51blanks | 56,603 | 56,803 | 200 |
| **hard1** | 128,760,553 | 128,760,739 | **186** |

At v0 that overhead is 0.00014% of the score. At D1's 335 cycles it is 36% of the
measured window, and at D4's 102 it would be 65%. **Confirmed end-to-end in §6a**: with
the new solver the measured windows are 187 / 211 / 235 on easy1 / 20blanks / 51blanks,
of which 181 / 188 / 181 is overhead — 77% to 97% of what is being measured. Nothing
else on this list changes by that factor once D1 lands.

The ±10 spread is the poll loop's phase, exactly as `docs/MEASUREMENT.md` predicts.
I have not measured where inside the 186 the time goes — see §4.

---

## 2. DEAD ENDS, with the number that killed each

### ✗ Masks and priority encoders **alone** — 3.6x, not 6.6x

The obvious first step: keep raster DFS and v0's exact search tree, just stop spending
9 cycles per cell trying digits and 81 cycles finding empty cells.

**Measured:** `hard1` 128,760,553 → 19,454,731 cycles (6.6x) — but F_max **87.02 →
47.61 MHz** and LE 9,286 → 17,132. Net rate 1.4797 s → **408.6 ms, 3.6x**.

A 3.6x rung that costs 85% more area and 45% of your frequency is not worth a phase on
its own. It is only worth building as the substrate for D1, where a frequency loss of
the same kind — 74%, measured — buys 384,000x instead of 6.6x. **Do not ship this as a
milestone.**

### ✗ Forward checking alone — real, but two orders short

Adding "backtrack as soon as *any* empty cell has no candidate" on top of masks:
`hard1` 19,454,731 → 3,430,905 (5.7x), worst held-out 553,930,745 → 96,102,817. Cheap
logic, genuinely useful — but it is the small half of the inference story and is
strictly dominated by taking one more step to naked singles (a further 128x).

### ✗ MRV as the **first** algorithmic step — 18x worse than singles, for more logic

This one matters, because the reference solver you were shipped
(`reference/ex3.1/sudx_standalone_ref/claude_mrv/`) is an MRV solver, which makes MRV
the natural first move.

| step on top of masks | `hard1` | worst `ho_published` | worst, any geometry |
|---|---|---|---|
| nothing | 19,454,731 | 553,930,745 | 3,253,371,343 |
| **MRV** | 901 | 672,313 | 672,313 |
| **naked + hidden singles** | **335** | **36,841** | **98,276** |
| both | 193 | 19,584 | 19,584 |

MRV alone is a big step — 824x on the worst case. Singles alone is **18x better than
that**, and needs cheaper logic: a one-hot detect (`x != 0 && (x & (x-1)) == 0`) per
cell versus 81 nine-bit popcounts feeding a min-tree. And once you have singles, MRV
adds only 1.9x on the classic worst case.

`PENDING-MRVONLY` — I am synthesising MRV-only as its own build so this is a measured
comparison of both axes and not just a cycle argument.

One more thing about that reference solver, since you asked me to read it critically:
its MRV scan is written as a sequential `if (... < best_cnt) best = ...` inside a
`for` loop over all 81 cells. That elaborates to an **81-deep chain** of compare-and-
mux, not a balanced tree. Whatever MRV costs in principle, that implementation will
cost considerably more.

### ✗ Multiple parallel search engines — no room, and nothing to divide

The Cornell project explicitly suggests this ("ample room for further implementation of
parallel solvers"). Two measured reasons it is wrong here:

1. There is no room. D1 already occupies 25,774 of ~49,760 LE. A second engine does
   not fit, let alone the four or eight that would matter.
2. There is nothing to divide. Speculation divides *node count*. After D1 the median
   `hard1`-class puzzle is ~300 cycles and the worst in 4,341 is ~10^5. Dividing
   10^5 by 4 while spending the area that could have bought frequency is a loss on
   the quotient, and the quotient is the grade.

### ✗ Deeper inference — naked pairs, box-line reduction, X-wing

The natural "next rung" after hidden singles, and it breaks the architecture.

Everything in D1 works because **the entire solver state is the set of assignments**:
candidate sets are *derived* from `used` masks, so undoing a decision is clearing
assignments, which is one cycle. Pairs, box-line and X-wing **eliminate candidates
without assigning anything**. That elimination is not recoverable from the assignments,
so undo needs a snapshot of the candidate lattice per decision level:
9 bits × 81 cells × depth 64 ≈ **47 kbit**. That infers block RAM, and
`docs/MEASUREMENT.md` records system memory bits already at 79%.

For that you would be buying at most ~10x on a worst case already under 5 ms, while
the median does not move at all. Measured evidence for "the headroom is small": on the
worst held-out puzzle for `s2`, MRV alone already recovers 12.3x (36,841 → 2,993).

### ✗ Tuning anything to `hard1`

`hard1` is Norvig top95 #1. Measured: for v0 it sits at the **98.6th percentile** of my
3,191-puzzle published held-out set, not at the top. The true v0 worst there is
**3,670,993,359** cycles — **28.5x worse than `hard1`** — and under X-Sudoku geometry
**21,174,957,605**, i.e. 164x worse.

A design ranked on `hard1` alone will pick the wrong thing. Concretely: on `hard1`
alone, MRV-only (901) looks within 3x of singles (335). On the held-out worst case the
gap is 18x. Same two designs, opposite conclusions.

### ✗ Chasing the `comp_fpga` 50 MHz system clock

Not graded. I did not spend a run on it. Flagging one consequence in §4 anyway.

---

## 3. THE ORDER I WOULD BUILD THEM IN

**1. D1 + D2 together, as one step, as `v1`.**
Masks, singles, one-hot selection. They are not three independent rungs: masks without
singles is a measured 3.6x dead end, and retrofitting one-hot selection afterwards
rewrites the same datapath twice. The RTL exists on this branch and is validated
cycle-exact. Everything else on this list is a refinement of it or is dead.

Gate it the way `docs/MEASUREMENT.md` says: 51blanks in the K5 sim, then hardware.
`hard1` is predicted at **295 solver cycles** (`s2u`), so **~481 in the measured
window** — and unlike v0's 128.7M, this prediction can be checked against my
standalone-RTL number the moment the board runs.

**2. Then measure, and only then choose between D3 and D4.**
Both are worst-case insurance, both cost frequency, and after step 1 frequency is the
entire remaining budget. The decision rule is a division you can do in an afternoon
once you have step 1's F_max: on the worst case across all six sets, D3 must cost
< 2.9x F_max and D4 < 2.4x. Do not build both before measuring either.

**3. D5 last, and only if the hackathon variant turns out easy.**
Attacking the 186-cycle overhead is worth up to 1.5x. It is the largest remaining term
by proportion but the smallest in absolute risk-adjusted value, and it is the only item
here that touches the wrapper and the driver rather than the solver — i.e. the only one
that can break the platform contract rather than just be slow.

**What enables what.** Masks enable everything: singles, forward checking, MRV and
parallel commit all need "the candidate set of every cell, this cycle, for free", and
that is what the `used`-per-unit representation buys. v0's `is_valid` cannot provide
it at any price — it answers one question about one cell per cycle by construction.

---

## 4. WHAT I COULD NOT DETERMINE

1. **Anything on hardware.** No board. Every cycle number is simulation or a model
   validated against simulation; every frequency is `qsyn_xlr`'s unconstrained F_max
   panel (there is no `basic.sdc`, so the slack numbers are fiction, as documented).

2. **Whether D1 closes the *system* build.** I did not run `comp_fpga`. v0's system was
   20,560 LE with a 9,286-LE accelerator, so platform overhead is ~11,274 LE; D1 at
   25,098–25,774 extrapolates to **~36,400 LE of ~49,760, about 73%**. That is an
   arithmetic estimate, not a measurement, and it says nothing about routability. The
   system clock is not graded but the bitstream still has to exist.

3. **Where the 186 cycles of window overhead actually go.** I know it is
   puzzle-independent and 186 ± 10. I did not decompose it into STORE bursts versus
   poll-loop latency, which is what would say whether D5 is worth 1.2x or 1.5x. It
   needs one `ALWAYSUD_PROBE_TIMER_COST` run and a waveform, both cheap.

4. **D4's frequency.** Modelled only. It could plausibly be *faster* than D1 as well as
   fewer cycles, since it deletes the priority encoders; or the conflict-detection
   network could dominate. One synthesis run settles it, and I would spend it.

5. **Whether multi-hour fits are acceptable to you.** They changed how I worked — I ran
   fewer synthesis points than I wanted and had to choose between them. If your
   iteration budget cannot absorb that, D1 needs an area pass before it needs anything
   else, and D6 is that pass, costed: 2.44x cycles, break-even at 54.5 MHz. **D6's
   frequency is the single measurement I most wish I had.**

6. **The actual hackathon variant.** I tested three geometries (classic, X-Sudoku,
   Windoku) and all three are one line of `bench/units.py`. `bench/units.py` itself
   says what is *not* expressible: anti-knight, thermo, killer cages, inequalities.
   If the variant is one of those, none of this transfers and the gate needs extending
   too — that is worth knowing now rather than on the day.

---

## 5. THE HELD-OUT NUMBERS IN FULL

Worst case (the number to judge on), across every set. Solver-FSM cycles.

Worst case (the number to judge on), across every set. **Solver-FSM cycles**, from
`explore/model/arch.c`; the model is cycle-exact against RTL simulation everywhere it
was checkable (3,491 puzzles, two geometries, zero mismatches).

| arch | what it adds | ho_published | classic_min | classic_easy | diagonal_min | diagonal_easy | windoku_min | **worst of all** |
|---|---|---|---|---|---|---|---|---|
| `v0` | the baseline | 3,670,993,359 | 55,220,173 | 37,666 | 21,174,957,605 | 9,234 | 2,693,355,559 | **21,174,957,605** |
| `m1` | + masks, priority encoders | 553,930,745 | 8,355,730 | 5,512 | 3,253,371,343 | 1,354 | 412,412,241 | **3,253,371,343** |
| `s0` | + forward check | 96,102,817 | 918,486 | 562 | 190,718,964 | 346 | 130,749,261 | **190,718,964** |
| `s1` | + naked singles | 7,038,541 | 59,131 | 94 | 6,354,770 | 70 | 7,361,345 | **7,361,345** |
| `s2` | + hidden singles | 36,841 | 1,439 | 44 | 34,910 | 66 | 98,276 | **98,276** |
| `s2u` | + unified one-hot rule | 34,347 | 1,205 | 44 | 25,418 | 66 | 50,166 | **50,166** |
| `s2m` | `s2` + MRV | 19,584 | 819 | 44 | 7,831 | 66 | 10,160 | **19,584** |
| `s2um` | `s2u` + MRV | 17,116 | 663 | 44 | 5,967 | 66 | 7,282 | **17,116** |
| `m2` | masks + MRV, **no singles** | 672,313 | 10,050 | 96 | 229,816 | 70 | 500,583 | **672,313** |
| `p3` | parallel commit (modelled) | 10,377 | 244 | 11 | 6,746 | 14 | 21,149 | **21,149** |
| `p4` | parallel commit + MRV | 7,168 | 174 | 11 | 2,030 | 14 | 2,976 | **7,168** |

n = 3,191 / 400 / 150 / 300 / 150 / 150 = **4,341 puzzles**, none of which I tuned
against. `hard1` excluded from `ho_published`.

Three things to read off it:

- **Every rung from `m1` to `s2` is worth more than the one before**, and the two
  biggest are naked singles (79x) and hidden singles (191x) — not masks (6.6x) and not
  MRV.
- **`m2` sits between `s1` and `s0`.** MRV without singles is worth roughly one
  inference rung, at the price of the most expensive selection network in the design.
- **The worst case is not the same puzzle for every architecture.** Measured: within
  `ho_published`, `s2u`'s worst is line 513 and `s2um`'s is line 701; within
  `gen_diagonal_min` they are lines 171 and 94; adding parallel commit moves it again.
  Across sets, `s2`'s overall worst is a Windoku puzzle, `v0`'s is X-Sudoku, `s2m`'s is
  a published classic. Ranking on one puzzle — any one puzzle — ranks the wrong thing,
  and it is also why a per-set improvement ratio overstates the real gain.

The same table on the four repo boards, for comparison, so you can see how little they
separate the top of the ladder:

| arch | easy1 | 20blanks | 51blanks | hard1 |
|---|---|---|---|---|
| `v0` | 103 | 214 | 56,603 | 128,760,553 |
| `m1` | 8 | 23 | 8,368 | 19,454,731 |
| `s0` | 8 | 23 | 984 | 3,430,905 |
| `s1` | 6 | 23 | 54 | 26,725 |
| `s2` | 6 | 23 | 54 | 335 |
| `s2u` | 6 | 23 | 54 | 295 |
| `m2` | 6 | 23 | 54 | 901 |
| `s2m` / `s2um` | 6 | 23 | 54 | 193 |
| `p3` / `p4` | 4 | 4 | 8 | 102 / 101 |

Below `s1`, the three simulatable boards are **identical for every architecture** —
6/23/54. They cannot rank anything at the top of the ladder, which is exactly why the
held-out set had to exist.

---

## 6. THE VARIANT TEST

`bench/units.py` says the geometry should live in one table. v0's does not — it is
hardcoded in `is_valid`, and `docs/MEASUREMENT.md` notes "the RTL does not yet share
this table". I closed that: `explore/model/gen_geom.py` **generates the RTL geometry
from `bench/units.py`**, so the gate and the hardware cannot disagree about which cells
constrain which.

The result: X-Sudoku is `+define+SUD_VARIANT_DIAGONAL` and **no RTL change at all**.
Same file, 29 units instead of 27, `SUD_UPC` 5 instead of 3. Measured on 300 generated
X-Sudoku puzzles through `xrun`: **0 cycle mismatches against the model, 0 wrong
grids**. Windoku (31 units) is modelled the same way and also clean.

For v0 the same test is a double failure. Its `is_valid` would have to be rewritten —
and then, with the diagonals correctly enforced, it is measured at a worst case of
**21,174,957,605 cycles = 243 s at 87.02 MHz** on my X-Sudoku set, against
**98,276 cycles = 4.4 ms** for D1. A variant does not just cost v0 a rewrite; it costs
it another 164x.

`PENDING-DIAG-SYNTH`

---

## 6a. THE END-TO-END RUN — measured, gate passed

The `s2fast` tree (MODE 1) run through the full K5 simulation, behind the real wrapper
and the real driver, `logs/explore-s2fast/sim/`:

```
PASS easy1      md5=c07abbf235a9  app-checker=PASSED
PASS 20blanks   md5=afee4b1403b0  app-checker=PASSED
PASS 51blanks   md5=afee4b1403b0  app-checker=PASSED
```

| board | v0 solve window | **s2fast solve window** | solver FSM | window overhead |
|---|---|---|---|---|
| easy1 | 283 | **187** | 6 | 181 |
| 20blanks | 403 | **211** | 23 | 188 |
| 51blanks | 56,803 | **235** | 54 | 181 |
| `hard1` | 128,760,739 | **~478 (predicted)** | 295 | ~183 |

`setup+load` is 235 on all three, identical to v0 — same wrapper, same burst cost.

Two things this settles.

**It works.** Not just in a standalone testbench: behind the real wrapper, through the
real memory bursts, with the driver's own checker agreeing. `51blanks` is the board
`docs/MEASUREMENT.md` designates as the gate because it is the only simulatable one
that exercises the unwind path hard — 4,157 backtracks in v0.

**The window overhead transfers, which is what makes the `hard1` number a prediction
and not a guess.** Measured 181 / 188 / 181 here against 180 / 189 / 200 / 186 for v0's
binary. It is the same wrapper and the same poll loop, and it did not move when the
solver underneath it changed by five orders of magnitude. So `hard1` = 295 + ~183 =
**~478 cycles in the measured window**, and the only unmeasured term left in the rate
is F_max.

And one number with no modelling in it at all: **`51blanks` goes from 56,803 to 235
measured solve cycles, gate-passed — 242x, on the board the protocol calls the gate.**

Note what that also says about D5. On every simulatable board the overhead is now
**77–97% of the measured window**. The search is no longer the thing being measured.

---

## 7. WHERE I THINK YOU ARE LIKELY TO BE WRONG

I have not seen your plan. Two things leaked from the brief itself — the `sed` you gave
me rewrites `` `v0`, `v1-mrv`, `v2-prop` `` to `` `v0`, `v1`, `v2` ``, and
`sw/apps/alwaysud/alwaysud.c` (which you told me to keep) carries a comment saying "v3
predicts hard1 at ~26 solve cycles against a fixed 235-cycle load". So I know your tags
are MRV then propagation, and that your ladder ends somewhere near 26 cycles. I did not
go looking in git history for anything else. Given that much:

**1. MRV first is the wrong order, and it is wrong on both axes.**
Measured above: masks+MRV is 901 cycles on `hard1` and 672,313 on the held-out worst;
masks+singles is 335 and 36,841. Singles win by 18x on the number that matters, and
they are the cheaper circuit — a one-hot detect per cell against 81 popcounts and a
min-tree. If `v1` is MRV you will spend a phase, and a large slice of your frequency
budget, on the weaker half of the idea, and then `v2` will have to pay for the
selection network a second time. **Ship singles as `v1` and treat MRV as an optional
`v3` that has to earn its F_max.**

**2. `hard1` will tell you the wrong thing, and it will do it quietly.**
On `hard1` alone, MRV-only (901) is within 2.7x of singles (335) — close enough to look
like a matter of taste. On my held-out worst case the same two designs are 18x apart.
`hard1` is Norvig top95 #1: hard for raster DFS specifically, and once you have any
inference at all it stops being hard. Measured, it is the **98.6th percentile** of my
published set for v0, not the maximum, and the maximum is **28.5x worse**. If you keep
ranking on `hard1` you will pick MRV, and on hackathon day you will get a puzzle that
is not `hard1`.

**3. You are probably budgeting frequency as a slow drain. It is a cliff.**
`docs/MEASUREMENT.md` frames F_max as "a budget you are spending… record it every step
and watch it drain". Measured, it does not drain — it falls off: 87.02 → 47.61 (masks
alone) → 22.34 MHz (masks + singles). The first parallel structure took 45% of it. If
you plan four rungs each expecting to give up 10–15%, the second rung will surprise
you. Two consequences: (a) the rate still improves by ~63,000x, so **do it anyway** —
but (b) budget the F_max loss up front as roughly 4x, and spend your optimisation
effort there rather than on further cycle reduction, because after `v1` there are
almost no cycles left to remove.

**4. The thing you will optimise next is probably already too small to matter.**
If `v3` lands near 26 solve cycles, then against a measured 186-cycle window overhead
the solver is 12% of the score and the wrapper is 88%. Every cycle you take out of the
search below ~200 is worth less than one percent on the fixed cost — and the fixed cost
is a memory burst and a RISC-V poll loop, neither of which is in
`alwaysud_solver.sv`. **The last rung of an algorithm ladder is not where your last
factor is.** It is in the window, and in F_max.

**5. You may be about to underestimate the build-time cost.**
Measured: v0's whole build is 4.5 minutes; the 25.7k-LE design took **2 h 37 m**, and
the 25.1k-LE one was still routing at **3.5 h** when I had to put a deadline on it. All
of it is the router, on a two-core machine. That number appears in no report and it
changes what "one hypothesis per branch" costs you per day. **Plan the area pass (D6)
before you plan the fourth rung**, or you will spend the hackathon waiting on
`quartus_fit`.

Where I would bet *against* myself: if `comp_fpga` cannot route a 36k-LE system, or if
the one-hot restructuring does not recover meaningful frequency, then D1's 25k LE is a
problem and the right answer shifts toward a smaller design that keeps naked singles
and forward checking but drops the 243 hidden-single detectors — measured at 26,725
cycles on `hard1` and 7,361,345 on the worst case across all six sets, i.e. still
**2,877x fewer cycles than v0's worst**, for a fraction of the logic. That is the
fallback, and it is a good one.

---

## 8. HOW TO REPRODUCE

```bash
# cycle models, all architectures, all sets
explore/table.sh

# one architecture on one board
explore/model/arch s2u sw/apps/sud_shared/sudoku_input_hard1.txt

# RTL vs model, any puzzle file, any variant
explore/sim/runtb2.sh alwaysud_solver_fast.sv 1 SUD_VARIANT_DIAGONAL \
    explore/puzzles/gen_diagonal_min.txt out.txt

# one synthesis data point (needs the cloud toolchain)
explore/measure.sh s2fast          # -> logs/explore-s2fast/sim/RESULT.txt
explore/simonly.sh s2fast          # K5 simulation + correctness gate, no fitter

# regenerate the RTL geometry from bench/units.py
explore/model/gen_geom.py --variant diagonal > explore/rtl/sud_geom_diagonal.svh
```

Layout of what I added, all under `explore/`:

```
explore/model/arch.c        every architecture as an event-counting model
explore/model/gen.py        held-out puzzle generator (any variant)
explore/model/gen_geom.py   bench/units.py -> RTL geometry table
explore/rtl/                the two solvers, the geometry package, the testbench
explore/exp/<name>/         one synthesis data point each (differs only by a +define+)
explore/puzzles/            the held-out sets
explore/sim/                RTL-vs-model comparison outputs
logs/explore-<name>/        qsyn logs, RESULT.txt, warning review
```

### Which commit each number came from

| number | source | commit |
|---|---|---|
| v0 87.02 MHz / 9,286 LE | `logs/explore-v0base/` | `94df39f` — `hw/xlrs/alwaysud/` untouched by me |
| m1 47.61 MHz / 17,132 LE | `logs/explore-m1/` | `8e738d6` — `explore/exp/m1/` |
| s2 22.34 MHz / 25,774 LE | `logs/explore-s2/` | `8e738d6` — `explore/exp/s2/` |
| s2fast | `logs/explore-s2fast/` | `8e738d6` — `explore/exp/s2fast/` |
| mrvonly, s2fastdiag | `logs/explore-mrvonly/`, `logs/explore-s2fastdiag/` | `569a61c` — those `explore/exp/` dirs |
| every cycle number | `explore/model/arch.c` + `explore/sim/` | `e034f7d` (the model has only gained architectures, never changed an existing one) |

`explore/exp/<name>/` is the **record of what was actually staged and built**, so those
directories are deliberately not re-synced when the shared RTL later changes. One
consequence to know about: `explore/exp/s2fast/alwaysud_solver.sv` predates the MODE-3
branches added for the `mrvonly` build. I diffed them — every added line is guarded by
`MODE == 3` or by `KMIN`, which is 2 for MODE 1 either way, so the MODE-1 logic that was
synthesised is identical to the MODE-1 logic in `explore/rtl/`.

**On branches.** You asked for one branch per experiment. I kept one, because the
experiments differ only by a `+define+` on a shared file — `explore/exp/*/alwaysud.f`
is the whole difference between `s2fast`, `s2fastmrv`, `s2fastdiag` and `mrvonly`, and
a branch per `+define+` would have duplicated identical RTL four times. Everything is
on `explore/opus5`; nothing was pushed, tagged, or merged, and `main` is untouched.
