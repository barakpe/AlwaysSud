# Phase report — the format

One file per phase: `logs/<tag>/REPORT.md`. **Fits on one screen.** The cloud fills
sections 1–3, the laptop fills 4, and only the laptop can compute the rate.

Anything longer belongs in `DIARY.md` (why) or the raw logs (evidence). This file is
what you read when someone asks "what changed and did it help".

---

The metric is defined once, in `docs/MEASUREMENT.md`. Every phase reports cycles,
standalone F_max, and their quotient; everything else is context.

---

## The template

Copy this, fill it, delete nothing. `n/a` is a valid value; a missing line is not.

```markdown
# <tag> — <the hypothesis, one line>

## RATE          <- the grade

`rate = cycles / standalone F_max`, at <n> MHz.

| board | cycles | rate | vs v0 |
|---|---|---|---|
| easy1 | 283 | 3.25 µs | 1.00x |
| 20blanks | 403 | 4.63 µs | 1.00x |
| 51blanks | 56,803 | 652.8 µs | 1.00x |
| **hard1** | **128,760,739** | **1.4797 s** | **1.00x** |

## RAW

CLOUD
  sim cycles     easy1 / 20blanks / 51blanks        hard1 not simulatable (~30 h)
  standalone     <n> LE · <n> registers · <n> memory bits · <n> MHz
  synthesis      0 errors · 0 latches · 0 loops · 0 unreviewed warnings
  full system    <n> LE · <n> MHz · <n>% memory bits    <- context, NOT graded
  bitstream      released as <tag>, sof <md5> / enums <md5>

LAPTOP
  hw cycles      all four
  vs sim         MATCH / MISMATCH on <board>
  setup+load     235
  correct        PASS x4 — bench/golden AND the app's own checker
  window         solve only (SPLIT=1) or single (SPLIT=0) — say which

## WHAT WE DID

<2-4 lines. The change, not the story.>

## EFFECT

<2-4 lines. What moved, why, and what it cost. If nothing moved, say so.>

## NEXT

<1 line.>
```

---

## Rules that keep it honest

**Rate is cycles ÷ F_max, both measured, no exceptions.** A cycle win paid for with F_max
can be a net loss. Compute it, do not estimate it.

**All four boards, not just hard1.** hard1 is the score, but F_max is one number for the
whole design, so a frequency cost hits every board at once — and a change that improves
hard1 while regressing 51blanks got lucky on one search tree rather than being better.
The three small boards are also the only ones that run in simulation, so they are the
early warning the cloud can give before anything reaches the laptop.

**Both machines appear.** The cloud owns F_max, area and the synthesis line; the laptop
owns hard1 and the final correctness. Neither half is a result on its own — the cloud
cannot compute a rate, and the laptop cannot tell you what the design cost.

**A regression is reported, not hidden.** If the rate got worse, the row still goes in with
`vs v0` above 1.00x. An *enabler* — v2 masks costing cycles to make v3 possible — is
allowed, but EFFECT must say so in words and name what it enables.

**Never compare across timer windows.** Quote cycles from the solve window
(`ALWAYSUD_SPLIT_TIMERS=1`) or the single window (`=0`), and say which. They differ by
155 cycles, and on small boards that is most of the number.

**Small-board numbers move on recompilation alone.** Under ~50 cycles on easy1 is noise
unless the binary is byte-identical — the RISC-V polls in software. hard1 is immune.

**If the algorithm changed, rewrite `docs/SOLVER.md` in the same commit.** It always
describes the *current* solver; git holds the older ones. A phase that changes the search
and leaves SOLVER.md describing the previous one is how the quiz answer goes stale.

**Synthesis line is not optional.** `check_synth.sh` produces it. `0 unreviewed warnings`
means every warning was either fixed or written down; see `.claude/skills/cloud-measure/`.

## Not in this report

| | where it lives |
|---|---|
| why we tried it, what surprised us | `DIARY.md` |
| console output, Quartus reports | `logs/<tag>/` |
| the running table of every phase | `RESULTS.md` |
| full-system LE / F_max / memory bits | `HANDOFF.txt` — context only, not graded |
