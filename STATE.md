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
Two consequences, the second only established on 08-31:

- F_max is worth exactly as much as cycle count.
- **`comp_fpga -mhz` is worth precisely zero for the score.** It moves the system clock,
  which the formula does not use. The old `v5-clock` rung has been deleted, not demoted.

## v0 - measured, verified, PASSING

Cloud, 2026-08-31, on the fixed RTL. Full report: `logs/v0_verified/REPORT.md`.

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

> **Measurement caveat.** The timer split added a fixed **+155 cycle** artifact to all
> three boards; subtracting it reproduces 363 / 483 / 56,883 exactly. Which of the two
> windows absorbs the 155 is not yet known - there is a one-line experiment in the report.
> Until that is settled, compare split numbers only against other split numbers.

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
2. **The correctness gate is variant-blind.** `bench/solve_ref.py` hardcodes standard
   rows/columns/boxes. On 9 September a *variant* arrives, and the gate will happily pass a
   solver that ignores the new constraint. Rebuild it on an explicit **units table** so a
   variant is a data change - and that same table is the right shape for the RTL.
3. F_max is a budget: 87.02 MHz standalone today, and the system needs ~56.
4. System memory bits are at **79%**. That is the real device ceiling, not logic.
5. `51blanks` is the correctness gate that matters; easy1 and 20blanks never backtrack.

## Hackathon - 9 September

A variant is revealed a few hours to two days before. In a mask design a variant is a
change to *which cells constrain which*, i.e. one more `used` register in an OR. Combined
with risk 2 above: **build the units table now**, in both the checker and the RTL, and the
variant becomes data rather than a rewrite.
