# Results

One row per measured tag. Filled in by `bench/measure_*.sh`; never edited by hand
except to add the notes column.

**Protocol:** `docs/MEASUREMENT.md`. If the protocol changes, every earlier row is
re-measured or explicitly struck through - otherwise the numbers are not comparable.

## Cycles (the score)

| tag | easy1 | 20blanks | 51blanks | **hard1** | vs v0 |
|-----|-------|----------|----------|-----------|-------|
| **v0** (hardware) | 283 | 403 | 56,803 | **128,760,739** | 1.00x |

Solve-window cycles. `setup+load` is a further **235** on every board, all four,
including hard1 - it is a fixed burst cost, not a function of how many cells are blank.

**v0 score: 128,760,739 / 87.02 MHz = 1,479,668 us = 1.4797 s.**

Hardware matched simulation *exactly* on all three simulatable boards. hard1 cannot be
simulated; it was predicted at 128,760,553 by the FSM model and measured 186 cycles
higher - 0.00014% - so the model is usable for planning the ladder.

## Cost

| tag | LEs | registers | mem bits | F_max standalone | F_max system | notes |
|-----|-----|-----------|----------|------------------|--------------|-------|
| **v0** | 9,286 | 1,867 | 0 | **87.02 MHz** | 55.29 MHz | 79% system mem bits; 1.9 ns slack at 50 MHz |

**Limits:** LEs < 20,000 · **no F_max floor** — the full-system clock is not graded, so a low F_max is penalised only through the rate itself
· system memory bits measured at 79% of ~1.6 Mbit with v0 in place.

**The grade is `cycles / standalone F_max`.** Both columns matter equally; judge a change
on the quotient. Format for a phase write-up: `docs/REPORT_TEMPLATE.md`.

## Search efficiency

Separates *the algorithm searched less* from *the hardware searched the same amount
faster*. Needs the placement/backtrack counters (BACKLOG item 1) - without them a
v4 result is uninterpretable.

| tag | placements | backtracks | cycles / placement |
|-----|-----------|------------|--------------------|
| *(pending counters)* | | | |
