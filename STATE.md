# State

**Read this first.** Updated at the end of every working session.

**Last updated:** 2026-09-02

## Right now

| | |
|---|---|
| `main` | v0 tagged, measured, and passing on the board |
| Branch in flight | *(none)* |
| **Next action** | RTL units table, then propagation |
| Best `hard1` | **128,760,739 cycles @ 87.02 MHz = 1.4797 s** |

## Working rules

- **Agents do not commit.** Barak reviews and commits.
- One hypothesis per branch; other ideas go to `BACKLOG.md`.
- Correctness gate before any timing number.

## The score

```
rate = cycles / F_max          F_max from standalone qsyn_xlr
```

The full-system clock is **not** graded (instructor, 2026-09-02) — `comp_fpga` missing
50 MHz is acceptable. Fewer cycles and higher standalone F_max are worth the same; judge
every change on the quotient. Protocol: `docs/MEASUREMENT.md`.

## v0 — the baseline

| | |
|---|---|
| cycles | easy1 283 · 20blanks 403 · 51blanks 56,803 · **hard1 128,760,739** |
| setup+load | 235, identical on all four — fixed 32+32+17 burst cost |
| standalone | 9,286 LE · 1,867 registers · 0 memory bits · 87.02 MHz |
| full system | 20,560 LE · 55.29 MHz · 79% memory bits *(context, not graded)* |
| correctness | PASS ×4, in simulation and on the board |
| hardware | matched simulation exactly on all three simulatable boards |

Full report: `logs/v0/REPORT.md`.

**hard1 cannot be simulated** (~30 h). A C model predicted 128,760,553; the board did
128,760,739, so the model is good to +186 cycles in 128.7M and every later rung's hard1
estimate can come from it.

**Cycle counts on the small boards are not pure hardware.** The RISC-V polls in software,
so recompiling moves them by tens of cycles. Under ~50 cycles on easy1 is noise unless the
binary is identical. hard1 is immune. Detail: `logs/timer_probe/RESULT.txt`.

## The propagation floor

Rounds and guesses needed by each technique, measured:

| board | blanks | naked only | naked + hidden | + pairs & box-line |
|---|---|---|---|---|
| easy1 | 3 | 3, 0 | 2, 0 | — |
| 20blanks | 20 | 3, 0 | 2, 0 | — |
| 51blanks | 51 | 11, 0 | 6, 0 | — |
| **hard1** | 64 | 279, 68 | 65, 15 | **13 rounds, zero guesses** |

Three of four boards need no search at all. With pairs and box-line, neither does hard1 —
about 26 cycles against v0's 128.7 million. **That is why the plan is propagation, not
faster guessing.**

## The ladder

| branch | what | why |
|---|---|---|
| **v0** ✓ | the instructor's reference | the reference point |
| **v1-units** | units table in the RTL | a variant becomes data; propagation needs it |
| **v2-prop** | naked + hidden singles on candidate masks | the big cycle win |
| **v3-pairs** | naked pairs + box-line reduction | takes hard1 to zero guesses |
| **v4-load** | attack the LOAD path | at ~26 solve cycles, the fixed 235 is 90% of the rate |
| *v1-mrv* | insurance only | see below |

**MRV is deferred, not planned.** Its value is picking better guesses, and v3 predicts
zero guesses. It measured 5.52 MHz standalone — and the cause is not the 81 popcounts but
a minimum-over-81 written as a serial accumulator, 303 of 334 cells on the critical path,
where a tree is depth 7. Keep it as a fallback if the hackathon variant resists
propagation, and fix the reduction if we ever build it.

**Pipelining and `comp_fpga -mhz` are deleted, not deferred.** Pipelining buys F_max by
adding cycles, on a metric that divides one by the other. `-mhz` moves the system clock,
which the score does not use.

## Risks

1. **The RTL has the geometry baked in.** `bench/units.py` fixed the checker half — the v0
   hard1 grid is legal under classic and illegal under diagonal and windoku. The RTL half
   is untouched, so on hackathon day the checker adapts and the hardware does not. **This
   is the top risk and the next task.**
2. **A variant means new board files.** None of the four course puzzles has a solution
   under `diagonal` — their givens already contradict it.
3. **System memory bits at 79%.** The device ceiling is memory, not logic. Anything that
   moves candidate masks into RAM has to check this.
4. **Backtrack undo is cheap only while masks are recomputed.** An 81-bit placed-mask per
   level is ~4 Kbit. Storing and incrementally updating masks instead would bring back a
   ~59,000-bit problem.

## Hackathon — 9 September

The variant is revealed a few hours to two days before. In a mask design a variant is a
change to which cells constrain which — one more term in an OR. Risk 1 is the whole job.
