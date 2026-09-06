# Window-overhead decomposition — `s2fastmrv`, 2026-09-07

`ALWAYSUD_PROBE_TIMER_COST 1` with `ALWAYSUD_SPLIT_TIMERS 1`, on the validated
`explore-s2fastmrv` bitstream (`sof` md5 `45f150b55f6fb66f256653190d67273b`),
all four boards. Diagnostic build — **these are not scoring numbers**.

## What one instrument call costs

**35 cycles**, identical on all four boards. That is a direct measurement: the
probe is a second `report_task_performance()` with no work between it and the
first, so its delta *is* the cost of one call.

## What the solve-window overhead is made of

| board | solve window | − solver FSM | = overhead | = report call | + driver |
|---|---|---|---|---|---|
| easy1 | 187 | 6 | 181 | 35 | **146** |
| 20blanks | 211 | 23 | 188 | 35 | **153** |
| 51blanks | 235 | 54 | 181 | 35 | **146** |
| hard1 | 379 | 193 | 186 | 35 | **151** |

**~148 of the ~183 — about 80% — is driver code**: the `xlr_solver()` register
handshake and the RISC-V software poll loop waiting for `done`.

**The three `STORE` memory bursts are not in this window at all.** They are in
the separate `Board setup+load` window, which is a flat 235 on every board of
every design measured. So the question "how much of the overhead is the memory
bursts" has the answer *none* — the solve-window overhead is entirely software.

## The proof that it is software, not fabric

Turning the probe on changes **no RTL**. It moved:

| window | probe off | probe on | delta |
|---|---|---|---|
| Board setup+load | 235 | 275 | **+40** |
| Sudoku solve, easy1 | 187 | 235 | **+48** |
| Sudoku solve, 20blanks | 211 | 259 | **+48** |
| Sudoku solve, 51blanks | 235 | 283 | **+48** |
| Sudoku solve, hard1 | 379 | 427 | **+48** |

`+48` on every board — puzzle-independent, so it is not the solver. And note it
is *larger* than the 35-cycle call it added, and the added call sits **outside**
the solve window: the window now starts at the probe's report, not the setup
report. So none of the +48 is the probe's own cost. It is pure code generation —
one extra call shifted register allocation and moved when the poll loop notices
`done`.

That is `docs/MEASUREMENT.md`'s warning made concrete: *"small-board cycle counts
are not a pure hardware property."* One line of C moved the measured window by
26% of `easy1`'s baseline with the fabric untouched.

## What it says about the next phase

**Touch the driver, not the RTL.** ~148 cycles of driver against 193 solver
cycles on `hard1`: the poll loop is now comparable in cost to the entire search.
Removing the search completely would buy 2.04x; making the software notice
`done` promptly is worth most of a similar factor and costs no logic, no F_max
and no fitting risk — the three things that are already tight at 79%
utilisation.

The 180..188 spread across boards, with a byte-identical binary, is consistent
with the poll loop having a period of roughly 8 cycles, so `done` is noticed on
a loop boundary. Quantisation, not noise.

## Correctness and reversibility

All four probe runs passed both checkers, grids byte-identical to every other
run (`c07abbf235a9` / `afee4b1403b0` / `afee4b1403b0` / `d34b53beba5c`).

Reverting the switch and re-staging returned `hard1` to **235 setup / 379 solve**
— the fifth identical measurement of this design (`recheck_hard1.txt`).
