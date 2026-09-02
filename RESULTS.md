# Results

One row per measured tag. Protocol: `docs/MEASUREMENT.md`. Per-phase write-up:
`logs/<tag>/REPORT.md`.

## Rate — the grade

`rate = cycles / standalone F_max`. Solve-window cycles (`ALWAYSUD_SPLIT_TIMERS=1`).

| tag | easy1 | 20blanks | 51blanks | **hard1** | F_max | **rate (hard1)** | vs v0 |
|-----|-------|----------|----------|-----------|-------|------------------|-------|
| **v0** | 283 | 403 | 56,803 | 128,760,739 | 87.02 MHz | **1.4797 s** | 1.00x |

`setup+load` is a further 235 on every board — a fixed 32+32+17 burst cost, outside the
solve window.

## Cost

| tag | LEs | registers | mem bits | F_max standalone | F_max system |
|-----|-----|-----------|----------|------------------|--------------|
| **v0** | 9,286 | 1,867 | 0 | **87.02 MHz** | 55.29 MHz |

**Limits:** LEs < 20,000 · system memory bits already at 79% · **no F_max floor** — the
system clock is not graded, so a low F_max is penalised only through the rate.

## Search efficiency

Separates *searched less* from *searched the same amount faster*. Needs the counters in
`BACKLOG.md` item 2; without them a v2 result cannot be interpreted.

| tag | placements | backtracks | cycles / placement |
|-----|-----------|------------|--------------------|
| *(pending counters)* | | | |
