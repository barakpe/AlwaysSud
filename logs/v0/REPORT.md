# v0 — the instructor's reference, measured

## RATE          <- the grade

`rate = cycles / standalone F_max`. F_max is one number for the whole design, so a
change that costs frequency costs every board at once — all four are listed so a
regression cannot hide behind hard1.

| board | cycles | rate @ 87.02 MHz | vs v0 |
|---|---|---|---|
| easy1 | 283 | 3.25 µs | 1.00x |
| 20blanks | 403 | 4.63 µs | 1.00x |
| 51blanks | 56,803 | 652.8 µs | 1.00x |
| **hard1** | **128,760,739** | **1,479,668 µs = 1.4797 s** | **1.00x** |

**hard1 is the score.** The other three are the correctness gate and an early warning:
they are cheap, they run in simulation, and a change that helps hard1 while hurting
51blanks is a change that got lucky on one search tree.

## RAW

```
CLOUD   (qsyn_xlr + xrun)
  sim cycles     easy1 283 / 20blanks 403 / 51blanks 56,803    hard1 not simulatable (~30 h)
  standalone     9,286 LE · 1,867 registers · 0 memory bits · 87.02 MHz
  synthesis      0 errors · 0 latches · 0 combinational loops · 0 unreviewed warnings
                 46 warnings total (syn 41 / fit 1 / sta 4), all recorded
  full system    20,560 LE · 55.29 MHz · 79% memory bits      <- context, NOT graded
  bitstream      released as v0, sof ac57a19c… / enums 991ee6d3…

LAPTOP  (DE10-Lite)
  hw cycles      easy1 283 / 20blanks 403 / 51blanks 56,803 / hard1 128,760,739
  vs sim         MATCH, exactly, on all three simulatable boards
  setup+load     235 on all four — fixed 32+32+17 burst cost, puzzle-independent
  correct        PASS x4 — bench/golden AND the app's own checker

  window: solve only (ALWAYSUD_SPLIT_TIMERS=1). Single-window figures are
  363 / 483 / 56,883 / 128,760,819, a flat +155 higher. Never mix the two.
```

## WHAT WE DID

Nothing to the design. v0 *is* `sudx_scan` from ex3.1, renamed, with the instructor's
27 Aug store fix applied. Verified by diff: RTL, package and `.svh` byte-identical;
`alwaysud.c` identical plus two lines of timer split.

Built it, synthesised it, simulated three boards, produced a bitstream, published it as
a GitHub release, and ran all four puzzles on the board.

## EFFECT

The reference every later rung divides into. Three facts that shape the ladder:

- **0 memory bits** — the 81-cell grid and the 81×12-bit stack are entirely flip-flops.
  Nothing is competing for block RAM yet.
- **setup is puzzle-independent** at 235 cycles, so all improvement must come out of the
  solve window — until the solve window shrinks enough that 235 dominates it. At v3's
  predicted ~26 solve cycles, load would be 90% of the runtime.
- **hard1 is 128.7M cycles, not the ~50M the assignment estimates**, so every improvement
  ratio written before this measurement was understated by 2.6x.

Also validated the hard1 FSM model to +186 cycles in 128.7M, which is what makes the
rest of the ladder plannable without 30-hour simulations.

## NEXT

RTL units table, so the hackathon variant is a data change; then propagation.

---

*Evidence: `hw/` board console output · `sim/` (empty — see its README) · `HANDOFF.txt`
release notes · `models/` the hard1 and propagation models · `notes/` the long agent
write-ups from before this format existed.*
