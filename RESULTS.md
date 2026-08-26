# Results

One row per measured tag. Filled in by `bench/measure_*.sh`; never edited by hand
except to add the notes column.

**Protocol:** `docs/MEASUREMENT.md`. If the protocol changes, every earlier row is
re-measured or explicitly struck through - otherwise the numbers are not comparable.

## Cycles (the score)

| tag | easy1 | 20blanks | 51blanks | **hard1** | vs v0 |
|-----|-------|----------|----------|-----------|-------|
| *(v0 pending)* | | | | | |

## Cost

| tag | LEs | registers | mem bits | F_max standalone | F_max system | notes |
|-----|-----|-----------|----------|------------------|--------------|-------|
| *(v0 pending)* | | | | | | |

**Limits:** LEs < 20,000 · F_max standalone >= 56.45 MHz (below that the accelerator
becomes the system bottleneck) · system memory bits already at 83% of ~1.6 Mbit before
we add anything.

## Search efficiency

Separates *the algorithm searched less* from *the hardware searched the same amount
faster*. Needs the placement/backtrack counters (BACKLOG item 1) - without them a
v4 result is uninterpretable.

| tag | placements | backtracks | cycles / placement |
|-----|-----------|------------|--------------------|
| *(pending counters)* | | | |
