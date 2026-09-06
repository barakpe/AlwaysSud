# Follow-up for the hardware agent

Paste below the rule into the same session that produced `VALIDATION.md`.

---

Good work — the validation stands and the prediction held to 0.6%. Three things.

## 1. Correct one conclusion: `s2fastmrv` DID fit

`explore-s2fastmrv` now exists. You checked before its `comp_fpga` had finished —
your reasoning from what you could see was sound, but the fact changed:

```
FPGA_RESULT s2fastmrv: BITSTREAM OK
  system LEs   39,507 / 49,760  (79%)
  system F_max 27.33 MHz
  sof md5      45f150b55f6fb66f256653190d67273b
  released     2026-09-06 20:08
```

Please strike the "It did not fit" line in
`logs/explore-s2fast/hw/VALIDATION.md` and replace it with what actually
happened, including that you inferred absence from a release that had not been
published yet. Keep the reasoning; correct the fact.

## 2. Validate `explore-s2fastmrv` — this is the submission design

The course has since confirmed the scoring: **"a set of several seen and unseen
boards, with the majority being unseen, approximately as difficult as hard1"**,
each in a separate invocation. That makes the *tail* of the hard-board
distribution the thing being scored, not `hard1` alone — and on the held-out set
`s2fastmrv` is 2.2x better in the tail where it is only 1.13x better at the
median.

```bash
./explore/use_design.sh s2fastmrv      # REQUIRED - the tree must match the .sof
git diff --stat                        # expect changes only under hw/xlrs/alwaysud
```

Then the same protocol as before, all four boards.

| board | expected solve window | why |
|---|---|---|
| `easy1` | **187** | solver 6 + ~181, identical to s2fast |
| `20blanks` | **211** | solver 23 + ~188 |
| `51blanks` | **235** | solver 54 + ~181 — **the gate** |
| `hard1` | **~373** | solver 193 + the 180 you measured |

The small boards must match **exactly** — the solver cycle counts there are
identical to `s2fast`, so any difference is the wrapper, not the design.

`hard1` at 373 would be **14.15 µs at 26.36 MHz, 1.38x better than the 19.49 µs
you measured**, and ~104,500x v0.

**Repeat the determinism check.** `s2fastmrv` closes at 27.33 MHz against the
50 MHz platform clock, same class of setup violation as `s2fast`, and it is a
larger, denser design at 79% device utilisation. Four full runs with a
`prog_fpga` between each, as before. If counts or grids differ between runs,
that is the headline finding and it outranks any timing number.

## 3. One measurement worth more than another design

The 180-cycle window overhead is now **48% of the `s2fastmrv` hard1 window**. It
has never been decomposed — nobody knows how much is the wrapper's three `STORE`
memory bursts and how much is the RISC-V software poll loop noticing `done`.

`sw/apps/alwaysud/alwaysud.c` has a switch for exactly this:

```c
#define ALWAYSUD_PROBE_TIMER_COST 1
```

It inserts a back-to-back `report_task_performance()` call whose delta is the
cost of one report call. Combined with the existing split timers, that separates
instrument from design.

If you have time after the four runs: rebuild the app with that switch on and
report the three deltas on one board. **A number that says "120 of the 180 is the
poll loop" is worth more right now than another solver variant**, because it says
whether the next phase should touch the driver or the RTL.

## What NOT to spend a build on

`s2fasttree` (16.90 MHz) and `s2rr` (21.89 MHz) are measured dead ends — both
slower than the design they were meant to improve. Their `comp_fpga` runs have
been cancelled deliberately. Do not build them.

## On committing

The evidence belongs in git, but **on `explore/opus5-phases`, not `main`**, and
separately from Barak's own uncommitted work. Suggested:

```bash
git checkout explore/opus5-phases
git add logs/explore-s2fast/hw logs/explore-s2fastmrv/hw logs/v0/hw-revalidate-2026-09-06
git status --short          # confirm NOTHING else is staged - his main-tree
                            # changes are his, and must not be swept in
```

Then show him the staged list and let him write the commit message, or write a
proposed one and let him edit. Do not push. `logs/v0/hw/HW_RESULT.txt` stays
untouched — it is the hand-written August record.
