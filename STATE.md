# State

**Read this first.** Updated at the end of every working session.

**Last updated:** 2026-08-31 (evening - hardware)

## Right now

| | |
|---|---|
| `main` | `7253138`, pushed. v0 measured on **hardware** and PASSING |
| Branch in flight | *(none)* |
| **Next action** | tag `v0`, then open `feat/v1-mrv` |
| Best `hard1` result | **128,760,739 cycles = 1.4797 s** @ 87.02 MHz standalone |

## Working rules

- **Agents do not commit.** Barak reviews and commits.
- One hypothesis per branch; other ideas go to `BACKLOG.md`.
- Correctness gate before any timing number.

## THE SCORE

```
solve_time_us = cycle_count / max_freq_mhz        (standalone qsyn_xlr F_max)
```

Standalone, explicitly, "to neutralize the platform infrastructure speed bottleneck".

The full-system clock is *not* graded. `comp_fpga` failing to close
timing at 50 MHz is acceptable. Only the rate counts.

- Fewer cycles and higher standalone F_max are worth exactly the same.
- Judge every change on the **quotient**, never on either alone. A cycle win paid for in
  F_max can be a net loss.
- **The old "F_max >= 56.45 MHz" floor is deleted.** It protected the system clock, which
  nobody scores. Low F_max is still bad - because it divides into the rate.
- `comp_fpga -mhz` remains worth zero, for the same reason as before.

Report format: `docs/REPORT_TEMPLATE.md` - one screen: rate, raw, what we did, effect, next.

## v0 - measured, verified, PASSING

Cloud, 2026-08-31, on the fixed RTL. Full report: `logs/v0/REPORT.md`.

| | |
|---|---|
| correctness | **PASS on all three boards** - our golden gate *and* the app's own checker |
| cycles (easy1 / 20blanks / 51blanks) | **363 / 483 / 56,883** |
| standalone | **9,286 LEs · 1,867 regs · 0 mem bits · 87.02 MHz** |
| full system | 20,560 LEs · **55.29 MHz** · 79% memory bits · meets 50 MHz with 1.9 ns slack |
| bitstream | **built, programmed, and run** - release `v0`, verified by commit + md5 |
| **hardware** | **all four boards PASS on the board**, 2026-08-31 |

**hard1 is 128,760,739 cycles, measured on the board** - not the ~50M the assignment
estimates. So v0 on hard1 is **1.4797 s**, and every improvement ratio previously written
here was understated by 2.6x.

The FSM model predicted 128,760,553. It was **186 cycles low out of 128.7 million -
0.00014%**. That matters beyond this one number: hard1 needs ~30 h of RTL simulation, so
every future rung's hard1 estimate comes from that model, and the model has now been
checked against reality once.

> **Measurement windows - settled on the board, 2026-08-31.** The timer split costs a
> flat **+155 cycles**, on all four boards. Measured properly this time: one bitstream,
> one flag, `ALWAYSUD_SPLIT_TIMERS=0` reproduces 363 / 483 / 56,883 / 128,760,819 exactly.
>
> Earlier today I withdrew this claim after reading `k5_utils_lib.h` and concluding the
> split had to be free. The reading was right about the print - the counter *is* reset
> after `bm_printf`, so the print is excluded - and the conclusion was wrong, because the
> print is not the only thing an extra call costs. A direct back-to-back probe puts the
> seam at **35 cycles**; the other ~120 is code generation.
>
> **The bigger finding.** Adding that one probe call also moved `setup+load` 235 -> 275
> and `solve` 283 -> 331, with no added work before either and the RTL untouched. The
> RISC-V polls a done register in software, so register allocation and loop layout change
> *when the poll notices*. Small-board cycle counts are therefore not a pure hardware
> property: **treat an easy1 change under ~50 cycles as noise unless the binary is
> identical.** hard1 is immune - 155 in 128.7M, and the score is 1.4797 s either way.
>
> Full data: `logs/timer_probe/RESULT.txt`.

## The propagation floor - corrected

I had this wrong and the correction matters.

| board | blanks | naked only | naked+hidden | + pairs & box-line |
|---|---|---|---|---|
| easy1 | 3 | 3 rounds, 0 guesses | 2, 0 | - |
| 20blanks | 20 | 3, 0 | 2, 0 | - |
| 51blanks | 51 | 11, 0 | 6, 0 | - |
| **hard1** | 64 | **279, 68** | **65, 15** | **13 rounds, ZERO guesses** |

**My earlier hard1 naked-only figure (91 rounds, 14 guesses) was wrong.** The model placed
every naked single in a round simultaneously without checking whether two cells in the
same unit were being forced to the *same digit* - which is a contradiction. It therefore
built illegal grids and, because it never validated the final board, returned one. Adding
the conflict check gives 279/68, matching the cloud agent independently.

The tell was logical, not numerical: naked-only cannot need *fewer* guesses than the
strictly stronger naked+hidden. That is exactly the trap named in the roadmap's own risk
list - and then not handled in the model that produced the roadmap's numbers.

**But the floor is far lower than even the corrected numbers suggest.** With naked pairs
and box-line reduction, **hard1 needs 13 rounds and no search at all.** Every board
becomes pure propagation. At ~2 cycles per round that is ~26 cycles against v0's
128,760,553.

## The ladder - revised 08-31

| branch | what | why |
|---|---|---|
| **v0** | tag what is measured and passing | the reference point |
| **v1-mrv** | integrate `claude_mrv` **and replace its serial min-chain with a min-tree** | see below - the frequency fix is nearly free |
| **v2-prop** | propagation: naked **and hidden** singles on the mask infrastructure | hidden is 4.3x on its own and belongs here, not in a later rung |
| **v3-pairs** | naked pairs + box-line reduction | takes hard1 to zero guesses |
| ~~v3-pipe~~ | **deleted** | the frequency problem is not a pipelining problem |
| ~~v5-clock~~ | **deleted** | `-mhz` cannot move the standalone F_max the score uses |

### Why `claude_mrv` is slow, and why that is good news

Measured standalone: **5.52 MHz** - the assignment's figure is right. But the cause is not
what I assumed. It is **not** the 81 popcounts (8 cells on the critical path). It is the
`best_cnt` minimum reduction, **written as a serial accumulator chain instead of a tree**:
**303 of the 334 cells** on the critical path.

A minimum over 81 values is a *tree* - depth log2(81) = 7 - and someone wrote it as a
loop, giving depth 81. So the fix is a rewrite of one reduction, worth roughly
**5.5 -> 28 MHz at zero cycle cost**. That is not pipelining, and pipelining would have
been strictly worse: it buys frequency by *adding* cycles, on a metric that divides one by
the other.

### Backtrack undo - resolved, with a condition

An **81-bit placed-mask per branch level** is sufficient to undo a round. At 81 levels that
is ~4 Kbit(*, comfortable in flops - not the ~59,000 bits I feared.

**The condition:** that only holds while candidate masks are *recomputed* from the grid
each round rather than stored and incrementally updated. A future "store the masks in
registers" optimisation would destroy this property and bring the 59,000-bit problem back.
Anything that touches mask storage must revisit this.

## Risks

1. ~~**This design has never been on the board.**~~ **Closed 2026-08-31.** All four
   boards run and pass on the DE10-Lite. The whole cloud-to-laptop path - release,
   commit gate, md5, stage, program, run - has been exercised end to end and is in
   `docs/HANDOFF.md`. What remains is to keep it working, not to prove it can.
2. **The correctness gate is variant-blind - HALF CLOSED 2026-08-31.** The *software*
   half is done: `bench/units.py` is now the single source of the geometry, and
   `solve_ref.py` and `diagnose.py` both derive every rule from it. Proof it works: the
   real v0 hard1 grid is LEGAL under classic and **ILLEGAL under diagonal and windoku**.
   Before, the gate could not have told the difference.
   **Still open: the RTL.** `alwaysud_solver.sv` still has the geometry baked in, so on
   hackathon day the checker adapts by editing one file and the hardware does not. That
   is now the whole of this risk, and it is the thing to fix next.
   Also learned: none of the four course boards has a solution under `diagonal`, so a
   variant means new board files too, not just new rules.
3. F_max is a budget: 87.02 MHz standalone today, and the system needs ~56.
4. System memory bits are at **79%**. That is the real device ceiling, not logic.
5. `51blanks` is the correctness gate that matters; easy1 and 20blanks never backtrack.

## Hackathon - 9 September

A variant is revealed a few hours to two days before. In a mask design a variant is a
change to *which cells constrain which*, i.e. one more `used` register in an OR.
`bench/units.py` now does this for the checker - `classic`, `diagonal` and `windoku` are
three lines each. **The RTL is the remaining half**, and it is the one that is graded.
