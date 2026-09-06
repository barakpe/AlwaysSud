# Prompt for the hardware-validation agent

Copy everything below the rule into a fresh Claude Code session on the laptop with
the DE10-Lite attached. **All cloud synthesis is now complete**, so the numbers
below are final measurements, not placeholders.

---

You are validating an exploration branch on real hardware. Someone else did the
cloud work; your job is to find out whether their numbers survive contact with a
board. **Assume nothing they wrote is true until you have measured it.**

## What exists

```
repo    github.com/barakpe/AlwaysSud
branch  explore/opus5-phases        one commit per phase, from 94df39f
report  EXPLORATION.md              the claims you are testing
```

The claim under test: replacing the solver's *search* with constraint propagation
takes `hard1` from **128,760,739 measured cycles at 87.02 MHz** — 1.4797 s — to a
few hundred cycles at ~25 MHz, i.e. tens of microseconds.

Read `EXPLORATION.md`, then `docs/MEASUREMENT.md`, then
`.claude/skills/board-validate/SKILL.md`. The protocol in `docs/MEASUREMENT.md` is
binding: it is not advice.

## Everything measured on the cloud, final

Cycles are solver-FSM cycles; the measured solve window is those **+ ~183** of
fixed wrapper and software-poll overhead. F_max is standalone `qsyn_xlr`.

| design | hard1 cycles | F_max | LE | rate on hard1 | bitstream? |
|---|---|---|---|---|---|
| **s2fastmrv** | **193** | **26.36 MHz** | 28,396 | **14.26 µs** | building, may not fit |
| **s2fast** | 295 | 24.37 MHz | 25,098 | 19.61 µs | **YES — `explore-s2fast`** |
| s2 | 335 | 22.34 MHz | 25,774 | 23.19 µs | no |
| s2fasttree | 295 | 16.90 MHz | 25,280 | 28.28 µs | no — **dead end** |
| mrvonly | 901 | 32.23 MHz | 22,224 | 33.63 µs | no |
| s2rr (D6) | 940 | 21.89 MHz | 24,558 | 51.30 µs | no — **dead end** |
| courseref | 981 | 4.98 MHz | 13,026 | 233.73 µs | no |
| **v0 baseline** | 128,760,553 | 87.02 MHz | 9,286 | **1.4797 s** | **YES — `v0`** |

## The rules you inherit, and must not relax

1. **The correctness gate runs before any timing number is recorded.** Both
   checkers — `bench/solve_ref.py --check` against `bench/golden/`, and the app's
   own final checker. A faster wrong answer is not a result.
2. **`51blanks` is the gate, not `easy1`.** `20blanks` never backtracks at all, so
   it cannot catch an unwind bug. Only `51blanks` exercises the unwind path hard.
3. **Cycles, never wall-clock.** Wall time here measures UART and host startup;
   jitter is ~4 s against a ~0.3 s compute signal.
4. **Quote the window.** All expected numbers are solve-window numbers with
   `ALWAYSUD_SPLIT_TIMERS=1`. Never compare a split number to an unsplit one.
5. **Report the quotient.** `rate = cycles / standalone F_max`, which is the
   assignment's own formula. The full-system clock is not graded.

## Before you program anything — two things that will bite you

**1. Make the tree match the bitstream, or the guard lies to you.**
`hw/xlrs/alwaysud/` holds one design at a time. `validate_board.sh` checks the tree
against the release's **commit**, not against the `.sof`, so it can print
`PASS sources match the bitstream's commit` while you program something else. This
already happened once during the cloud work. Every release names its experiment:

```bash
./explore/use_design.sh s2fast      # or s2fastmrv
git diff --stat                     # expect changes only under hw/xlrs/alwaysud
```

For `explore-s2fast` the tree is already correct at that release's commit.

**2. The design does not meet the platform clock, and that is expected.**
`s2fast` closes at **28.42 MHz** system F_max against a 50 MHz platform clock
(v0 closed at 55.29). The score is unaffected — the assignment takes `max_freq`
from standalone `qsyn_xlr`, *"rather than from the full-design comp_fpga result"* —
but on the board this means **setup violations at the system clock**.

So if the board returns wrong grids, hangs, or gives cycle counts that differ
between identical runs: **suspect the clock, not the algorithm.** Simulation is
clean and deterministic. Report it as a timing symptom; do not "fix" the solver.
There is a PLL (`hw/gen_fpga/db/k5x_pll_altpll.v`), so lowering the accelerator
clock is probably possible — but that is a question for Udi, not a change to make
mid-validation.

## What to run

### Step 1 — the baseline, again. Do this first, it needs nothing else.

Re-measure **v0** on all four boards from the existing `v0` release.
`logs/v0/hw/HW_RESULT.txt` says **283 / 403 / 56,803 / 128,760,739** at 87.02 MHz.

If you cannot reproduce that, **stop and say so**. Everything downstream is a
comparison against it, and a baseline that does not reproduce invalidates the
comparison, not just the baseline.

### Step 2 — the design that has a bitstream today

Program `explore-s2fast` and run all four boards.

| board | expected solve cycles | source |
|---|---|---|
| `easy1` | **187** | measured in K5 simulation |
| `20blanks` | **211** | measured in K5 simulation |
| `51blanks` | **235** | measured in K5 simulation |
| `hard1` | **~478** | **predicted** — never run anywhere |

The first three must match **exactly**; cycles have matched simulation to silicon
to the digit before. `hard1` is the number nobody has — report it and the delta
from 478. The prediction is 295 solver cycles + ~183 overhead; if it is off, say
which term you think moved.

Also record `setup+load`, expected 235 on every board.

### Step 3 — the deliverable

| design | easy1 | 20blanks | 51blanks | hard1 | F_max | rate |
|---|---|---|---|---|---|---|
| v0 | | | | | 87.02 MHz | |
| s2fast | | | | | 24.37 MHz | |

Compute `cycles / F_max` for both and the ratio, using **standalone** F_max.

### Step 4 — `s2fastmrv`, if its release has appeared

`explore-s2fastmrv` is the fastest measured design — **193 cycles at 26.36 MHz,
14.26 µs, 1.37x better than `s2fast`**. Its `comp_fpga` was still running when this
was written and **may fail to fit**: 39,507 system LE (79% of the device) where
`s2fast` needed three placement attempts at 36,338 (73%).

```bash
gh release list --repo barakpe/AlwaysSud     # is explore-s2fastmrv there?
```

If it exists: `./explore/use_design.sh s2fastmrv`, then program and run all four
boards. Expected **187 / 211 / 235**, and `hard1` predicted at **~376**.
If it does not exist, it did not fit — that is a finding, and `s2fast` stands.

### Step 5 — only if there is time

Everything else needs a `comp_fpga` you would have to run yourself, at **4–9 hours
each** on that 1-core cloud box. Almost certainly not worth it. If you do have
time, the only one with a *point* is `courseref` — the course's own `claude_mrv`,
measured at 4.98 MHz and 981 cycles, which would let you say "we are 16.4x the
reference we were given" from hardware rather than from synthesis.

**Do not bother with `s2fasttree` or `s2rr`.** Both were hypotheses that failed:
`s2fasttree` measured 16.90 MHz (slower than the design it was meant to improve)
and `s2rr` measured 21.89 MHz against a 57 MHz break-even. They are documented
dead ends, not candidates.

## Traps that have already bitten someone

- **Every `k5` command is an alias or a shell function.** A plain
  `#!/usr/bin/env bash` script sees none of them; `timeout` and `setsid` cannot
  wrap them.
- **Sourcing the project setup clobbers `"$@"` and changes the working directory.**
  Capture arguments and make paths absolute on the *first lines*, before sourcing.
  This bit the cloud agent even though it was written down.
- **`qsyn_xlr` exits 0 even when it fails.** Parse stdout for `^ERROR ` and three
  `was successful` lines. Never trust `$?`.
- **One Quartus run at a time, one simulator at a time.** Both stage into paths
  derived from the project, not the tag, and silently destroy each other.
- **`.f` files: only `//` comments are skipped.** A `#` comment kills the build.

## What to report back

1. The step 3 table, filled in, with the rate ratio.
2. **`hard1` measured vs predicted** — the single most valuable number you can
   produce, because it is the one thing no amount of cloud work could settle.
3. Every gate result, per board, both checkers.
4. Anything that did **not** reproduce, stated plainly. A number that failed to
   reproduce is worth more than one that did.
5. Your own read on whether the recommendation holds up.

## What would make you disbelieve the whole thing

- `51blanks` not exactly 235 → the design does not behave in silicon as it does in
  simulation, and nothing else in the report can be trusted.
- `hard1` wildly off 478 → either the window overhead does not transfer, or the
  cycle model has a blind spot 3,491 puzzles did not reach.
- A gate failure on any board → **stop. Do not report timing.**

If any of those happens, the correct output is a clear description of what broke,
not a repaired number.
