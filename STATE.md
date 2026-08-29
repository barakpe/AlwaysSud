# State

**Read this first.** Updated at the end of every working session.

**Last updated:** 2026-08-29

## Right now

| | |
|---|---|
| Current tag on `main` | *(none - v0 measured but on pre-fix RTL, needs redo)* |
| Branch in flight | *(none)* |
| Next action | **Re-measure v0 on the fixed RTL**, then start `feat/v1-mrv` |
| Best `hard1` result | *(none yet - hardware only)* |

## Working rules

- **Agents do not commit.** Barak reviews and commits. An agent may draft a commit
  message and put it in its report, but never runs `git commit` or `git push`.
- One hypothesis per branch; other ideas go to `BACKLOG.md`.
- Correctness gate before any timing number.

## THE SCORE

From `docs/Project_and_Hackathon_Assignment.pdf`:

```
solve_time_us = cycle_count / max_freq_mhz
```

`max_freq_mhz` comes from **standalone `qsyn_xlr`**, explicitly not from `comp_fpga`,
"to neutralize the platform infrastructure speed bottleneck."

> **F_max is a first-class target, worth exactly as much as cycle count.** There is no
> platform ceiling in the score. Halving cycles and doubling frequency are worth the same.

## Where v0 actually landed

Cloud session 2026-08-26, at commit `28c7d69` - **before** the store fix. Full report:
`logs/v0/REPORT.md`.

| | measured |
|---|---|
| cycles, easy1 / 20blanks / 51blanks | **363 / 483 / 56,883** (identical across two runs) |
| LEs | **9,393** synthesis, **8,967** fitter (18% of device) |
| registers | 1,867 |
| **memory bits** | **0** |
| **F_max standalone** | **89.46 MHz** |
| errors | 0 |
| correctness | **FAIL on all three** - the store bug, now fixed |

**The regime change is confirmed.** 51blanks went from 12,247,683 cycles under
`sudx_basic` to **56,883** - a 215x reduction, inside the 150-300x that was predicted.
On the scoring formula: 86,038 us -> **636 us**, about 135x better.

The cycle numbers are believed still valid after the fix (the store bug corrupts what is
written, not how many bursts run) but **must be reconfirmed** before they become the v0
row in `RESULTS.md`.

## THE PLAN CHANGED - MRV, not the incremental ladder

The earlier ladder was `v1 fastfind -> v2 masks -> v3 singles -> v4 mrv`: improve the
scan solver step by step and arrive at MRV eventually. **The numbers say go straight
there.** On `hard1`, using the assignment's own figures and our measured F_max:

| | cycles | F_max | **solve time** | vs v0 |
|---|---|---|---|---|
| v0 `sudx_scan` (ours) | ~50,000,000 | 89.46 MHz | ~559,000 us | - |
| scan + masks + singles (old ladder, est.) | ~10,000,000 | ~100 MHz | ~100,000 us | ~6x |
| **`claude_mrv` as-is** | ~1,000 | ~5 MHz | **~200 us** | **~2,800x** |
| **MRV pipelined** | ~3,000 | ~50 MHz | **~60 us** | **~9,300x** |

The whole old ladder is worth ~6x. Integrating MRV is worth ~2,800x. It was optimising
the wrong solver.

### The revised ladder

| branch | what | why |
|---|---|---|
| **v0-fix** | re-measure on the fixed RTL | the baseline every claim is measured against |
| **v1-mrv** | integrate `claude_mrv` as our solver | ~2,800x. The assignment explicitly suggests this path |
| **v2-pipeline** | break MRV's combinational selection path across cycles | **the differentiator.** Everyone integrates MRV; few will fix its 5 MHz |
| **v3-masks** | incremental candidate masks | buys cycles *and* F_max - see below |
| **v4-clock** | `comp_fpga -mhz <n>` | no RTL change; the flag exists |

## What the v0 report unlocked

Four findings that were open risks and are now settled:

1. **Memory bits = 0 everywhere.** Neither `grid` nor `stack` became block RAM; both are
   in flip-flops. This was the risk that could have sunk MRV - RAM has two ports and MRV
   must read all 81 cells every cycle. **Green light.**
2. **The critical path is one `is_valid`** - column pointer, box-start lookup, 81-way
   variable-index grid read, compare, reduce, into the grid write enable. 14.76 ns,
   **~55% of it routing**. Crucially: testing all nine digits in parallel *replicates*
   this path, it does not *lengthen* it. Parallelism costs area and routing, not depth.
3. **Masks buy F_max as well as cycles.** The dominant hop is the variable-index grid
   read (3.2 ns of mux + routing). A bitmask representation removes it. On a metric that
   divides by F_max, that is a double win.
4. **The wrapper costs 5,819 ALUTs against the solver's 2,357** - 69% of the
   combinational logic is LOAD/STORE burst plumbing, not the search. If area ever binds,
   take it from there first.

Plus: **13 spare host registers** (only 3 of 16 used), so counters are cheap and need no
bit-packing; and **`comp_fpga -mhz <n>`** exists, so the clock rung needs no RTL change.

## Measurement problems to fix first

- **The timer measures the wrong thing.** `report_task_performance` wraps
  `xlr_setup()` **and** `xlr_solver()`, so it includes the board LOAD and both polling
  handshakes. Fixed overhead is ~340 cycles - on `easy1` that is **94% of the number**.
  Split it before anyone reads an easy-board delta as a solver improvement.
- **Record both LE numbers** (synthesis 9,393, fitter 8,967) and say which the 20,000
  limit applies to.
- **Stop quoting `*.sta.summary` slack.** `$QSYN/basic.sdc` is absent from the shared
  install, so every slack figure is meaningless. Only the Fmax panel is real.
- **`bench/measure_*.sh` have never run and cannot** - every k5 command is an alias or a
  shell function, invisible inside a plain script. The cloud skill solves this; the
  scripts should be deleted or rewritten around it.
- **`.gitignore` swallows the archived Quartus reports** (`*.rpt` at any depth). Either
  negate for `logs/**` or stop claiming they are kept as evidence.

## Hackathon constraint - and MRV happens to help

9 September; a variant is revealed a few hours to two days before.

> Keep the constraint check modular. Anything encoding "conflicts if same row, column or
> box" belongs in one place, so a variant (diagonal, killer, hyper) touches only that.

Note this now points the same way as performance: **a mask-based MRV design is both the
fastest and the most adaptable**, because a variant is mostly a change to how candidate
masks are computed. The old scan-based ladder had no such property.
