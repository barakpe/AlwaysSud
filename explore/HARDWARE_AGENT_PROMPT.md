# Prompt for the hardware-validation agent

Copy everything between the rules into a fresh Claude Code session on the laptop
with the DE10-Lite attached.

---

You are validating an exploration branch on real hardware. Someone else did the
cloud work; your job is to find out whether their numbers survive contact with a
board. **Assume nothing they wrote is true until you have measured it.**

## What exists

```
repo    github.com/barakpe/AlwaysSud
branch  explore/opus5-phases     16 commits, one per phase, from 94df39f
report  EXPLORATION.md           the claims you are testing
```

The claim under test, in one line: replacing the solver's search with constraint
propagation takes `hard1` from **128,760,739 measured cycles at 87.02 MHz** to a
**predicted ~478 cycles at 24.37 MHz** — from 1.4797 s to about 19.6 µs.

Read `EXPLORATION.md` first, then `docs/MEASUREMENT.md`, then
`.claude/skills/board-validate/SKILL.md`. The measurement protocol in
`docs/MEASUREMENT.md` is binding: it is not advice.

## The rules you inherit, and must not relax

1. **The correctness gate runs before any timing number is recorded.** Both
   checkers — `bench/solve_ref.py --check` against `bench/golden/`, and the app's
   own final checker. A faster wrong answer is not a result.
2. **`51blanks` is the gate, not `easy1`.** `20blanks` never backtracks at all, so
   it cannot catch an unwind bug. Only `51blanks` exercises the unwind path hard.
3. **Cycles, never wall-clock.** Wall time on this setup measures UART and host
   startup; run-to-run jitter is ~4 s against a ~0.3 s compute signal.
4. **Quote the window.** All expected numbers are solve-window numbers with
   `ALWAYSUD_SPLIT_TIMERS=1`. Never compare a split number to an unsplit one.
5. **Report the quotient.** `rate = cycles / standalone F_max`. Fewer cycles and
   higher frequency are worth exactly the same. The full-system clock is not graded.
6. **Refuse to program if the tree does not match the release.** Verify the commit
   and both md5s first — `board-validate/SKILL.md` explains why the commit and not
   just the contract file.

## What to run

### Step 1 — the baseline, again

Re-measure **v0** on the board, all four boards. `logs/v0/hw/HW_RESULT.txt` says
283 / 403 / 56,803 / 128,760,739 at 87.02 MHz. If you cannot reproduce that, stop
and say so — everything downstream is a comparison against it, and a baseline that
does not reproduce invalidates the comparison, not just the baseline.

### Step 2 — the recommended design

Program the `explore-s2fast` release and run **all four boards**.

| board | expected solve cycles | source |
|---|---|---|
| `easy1` | **187** | measured in K5 simulation |
| `20blanks` | **211** | measured in K5 simulation |
| `51blanks` | **235** | measured in K5 simulation |
| `hard1` | **~478** | **predicted** — never yet run anywhere |

The first three must match **exactly**. An inexact match is a failure, not a
rounding difference — cycles are exact and have matched between simulation and
silicon to the digit before.

`hard1` is the one number nobody has. Report what the board says, and the delta
from 478. The prediction decomposes as 295 solver cycles + ~183 of wrapper and
software-poll overhead; if it is off, say which term you think moved and why.

Also record `setup+load`, expected 235 on every board.

### Step 3 — the comparison that is the actual deliverable

Build the table. This is what you are for:

| design | easy1 | 20blanks | 51blanks | hard1 | F_max | rate on hard1 |
|---|---|---|---|---|---|---|
| v0 (baseline) | | | | | 87.02 MHz | |
| s2fast (recommended) | | | | | 24.37 MHz | |

Compute the rate as `cycles / F_max` for both, and the ratio. Use the **standalone**
F_max from `qsyn_xlr`, not `comp_fpga`'s system figure.

### Step 4 — the rest of the ladder, ONLY if there is time

Each of these needs its own bitstream, and a full `comp_fpga` for this design took
**hours** on the cloud, not the ~5 minutes v0 takes. Do not start five builds and
run out of time with none finished. In priority order:

| build | why it is worth a slot | expected hard1 solver cycles |
|---|---|---|
| `s2fasttree` | the `iso9` fix — same cycles, possibly better F_max. **Pure upside if it works.** | 295 |
| `s2fastmrv` | MRV on top of singles; should be the fastest of all | 193 |
| `mrvonly` | the "obvious" design, to show on hardware that it loses | 901 |
| `courseref` | the course's own MRV solver, for an honest "vs what we were given" | 981 |

If you only get one, make it `s2fasttree`.

## Traps that have already bitten someone

- **Every `k5` command is an alias or a shell function.** A plain
  `#!/usr/bin/env bash` script sees none of them; `timeout` and `setsid` cannot
  wrap them.
- **Sourcing the project setup clobbers `"$@"` and changes the working directory.**
  Capture your arguments and make paths absolute on the *first lines*, before
  sourcing. This bit the cloud agent even though it was written down.
- **`qsyn_xlr` exits 0 even when it fails.** Parse stdout for `^ERROR ` and for
  three `was successful` lines. Never trust `$?`.
- **Only one Quartus run at a time.** Every `measure.sh` stages into
  `$MY_K5_PROJ/hw/xlrs/alwaysud`, a path derived from the project, not the tag.
  Two drivers there silently destroy each other's sources — `EXPLORATION.md` §8.
- **Only one simulator at a time**, for the same class of reason.
- **`.f` files: only `//` comments are skipped.** A `#` comment kills the build.

## What to report back

1. The comparison table from step 3, filled in, with the rate ratio.
2. **`hard1` measured vs the 478 prediction** — the single most valuable number
   you can produce, because it is the one thing no amount of cloud work could
   settle.
3. Every gate result, per board, both checkers.
4. Anything that did **not** reproduce, stated plainly. A number that failed to
   reproduce is more useful than one that did.
5. Your own read on whether the recommendation holds up.

## What would make you disbelieve the whole thing

State these up front and watch for them:

- `51blanks` not exactly 235 → the design does not behave in silicon as it does in
  simulation, and nothing else in the report can be trusted.
- `hard1` wildly off 478 → either the window overhead does not transfer, or the
  cycle model has a blind spot that 3,491 puzzles did not reach.
- A gate failure on any board → stop. Do not report timing.

If any of those happens, the correct output is a clear description of what broke,
not a repaired number.

---

## ADDENDUM — read this before programming anything

**1. Make the tree match the bitstream, or the guard lies to you.**
`hw/xlrs/alwaysud/` can only hold one design at a time. `validate_board.sh` checks
the tree against the release's **commit**, not against the `.sof` — so it can
report `PASS sources match the bitstream's commit` while you program a different
design entirely. This actually happened during the cloud work.

Every release names the experiment it was built from. Before validating:

```bash
./explore/use_design.sh s2fast      # or s2rr, or s2fasttree
git diff --stat                     # expect changes only under hw/xlrs/alwaysud
```

For `explore-s2fast` the tree is already correct at the release's commit; for the
others you must run that first.

**2. The design may not meet the platform clock, and that is expected.**
`s2fast` closes at **28.42 MHz** system F_max against a 50 MHz platform clock
(v0 closed at 55.29). The score is unaffected — the assignment takes `max_freq`
from standalone `qsyn_xlr`, "rather than from the full-design comp_fpga result" —
but on the board this means **setup violations at the system clock**.

So: if the board returns wrong grids, hangs, or gives cycle counts that vary
between identical runs, **suspect the clock before suspecting the algorithm.**
Simulation is clean, and the cycle counts are deterministic in simulation. Report
it as a timing symptom and say so plainly; do not "fix" the solver.

There is a PLL in the system (`hw/gen_fpga/db/k5x_pll_altpll.v`), so lowering the
accelerator clock is likely possible — but that is a question for Udi, not a
change to make unilaterally mid-validation.

**3. If everything passes, the single number that matters** is `hard1`: predicted
~478 cycles for `s2fast`, against v0's measured 128,760,739. Nothing anywhere has
ever run it.
