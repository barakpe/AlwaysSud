# Hardware validation of `explore/opus5-phases` — 2026-09-06

Laptop half, DE10-Lite, USB-Blaster [USB-1] `10M50DA` JTAG ID `0x031050DD`.
Protocol: `docs/MEASUREMENT.md`, run through
`.claude/skills/board-validate/validate_board.sh`. Window is
`report_task_performance("Sudoku solve")` with `ALWAYSUD_SPLIT_TIMERS=1`
throughout, both designs — the split-window numbers, never the unsplit totals.

## The table

| design | easy1 | 20blanks | 51blanks | hard1 | F_max (standalone) | rate on hard1 |
|---|---|---|---|---|---|---|
| v0      | 283 | 403 | 56,803 | 128,760,739 | 87.02 MHz | 1.4797 s |
| s2fast  | 187 | 211 |    235 |         475 | 24.37 MHz | **19.49 µs** |

`setup+load` = **235** on every board of every run of both designs.

```
rate ratio  = 1.479668 s / 19.491 us = 75,915x
              271,075x on cycles, less 3.571x of F_max given back
```

## Step 1 — the baseline reproduces, exactly

| board | 2026-08-31 record | 2026-09-06 re-measurement |
|---|---|---|
| easy1 | 283 | 283 |
| 20blanks | 403 | 403 |
| 51blanks | 56,803 | 56,803 |
| hard1 | 128,760,739 | 128,760,739 |

All four grids byte-identical to August. The original hand-written record is
untouched at `logs/v0/hw/`; this re-measurement is in
`logs/v0/hw-revalidate-2026-09-06/`.

## Step 2 — hard1 measured vs predicted, and which term moved

Predicted **478** = 295 solver cycles + ~183 window overhead. Measured **475**.

The −3 is entirely in the overhead term, and the decomposition says so:

| board | measured window | − solver FSM | = overhead | K5 simulation said |
|---|---|---|---|---|
| easy1 | 187 | 6 | **181** | 181 — match |
| 20blanks | 211 | 23 | **188** | 188 — match |
| 51blanks | 235 | 54 | **181** | 181 — match |
| hard1 | 475 | 295 | **180** | never simulated |

The overhead transfers from simulation to silicon exactly on all three
simulatable boards. hard1's 180 sits inside that family; the prediction used a
rounded ~183. The 295 solver-FSM cycles stand. Note that hardware cannot
decompose the hard1 window on its own — 295+180 is inferred from a model that
was exact everywhere it could be checked, not directly separated.

## Correctness — every gate, every board, every run

Both checkers on every run: `bench/solve_ref.py --check` against `bench/golden/`,
and the app's own final checker. **No non-PASS anywhere. Zero warnings.**

Solution grids are byte-identical across v0, s2fast, and the August v0 run:

| board | md5 |
|---|---|
| easy1 | `c07abbf235a9` |
| 20blanks | `afee4b1403b0` |
| 51blanks | `afee4b1403b0` |
| hard1 | `d34b53beba5c` |

## Determinism, given the design misses the platform clock

`s2fast` closes at 28.42 MHz system F_max against a 50 MHz platform clock, so
there are setup violations at the system clock. It did not manifest. Four full
runs, each preceded by its own `prog_fpga`:

| run | easy1 | 20blanks | 51blanks | hard1 |
|---|---|---|---|---|
| 1 | (transport) | 211 | 235 | 475 |
| 3 | 187 | 211 | 235 | 475 |
| 4 | 187 | 211 | 235 | 475 |
| 5 | 187 | 211 | 235 | 475 |

Bit-identical counts and bit-identical grids. An observation over four runs, not
a guarantee — the violation is real and a marginal path could still bite on a
different device, temperature or bitstream.

## What did not reproduce, and what broke

- **Nothing measured failed to reproduce.** Every number in the release notes
  that hardware could check, matched to the digit.
- ~~**`explore-s2fastmrv` does not exist.** Its `comp_fpga` did not produce a
  release, so `s2fast` stands as the validated winner.~~ **CORRECTED
  2026-09-06.** `explore-s2fastmrv` **did** fit and **was** released, at
  20:08 on 2026-09-06 — after this session had finished checking. It is
  39,507 system LE (79%), 27.33 MHz system F_max, `sof` md5
  `45f150b55f6fb66f256653190d67273b`.

  The observation was right and the conclusion was wrong: `gh release list`
  genuinely showed only `explore-s2fast` and `v0`, at the start of the session
  and again at the end. But absence of a release is not evidence of a failed
  fit — it is also what an unfinished `comp_fpga` looks like, and that is what
  it was. The prompt said the build "was still running when this was written
  and may fail to fit", so a not-yet-published release was the *expected*
  intermediate state, and I read a pending build as a failed one. The correct
  statement at the time was "no release yet; cannot distinguish still-building
  from did-not-fit", not "it did not fit".

  `s2fastmrv` is now validated on hardware in its own right — see
  `logs/explore-s2fastmrv/hw/VALIDATION.md`. It is the faster design and the
  submission candidate; `s2fast` is no longer the winner.
- **The USB-UART link is intermittent on this laptop.** Three runs were lost to
  it, in two flavours: `SerialTimeoutException: Write timeout` while uploading
  `instr_loadmem.txt`, and `Sorry, Can't locate a USB serial Port`. Mid-session
  the FTDI node (`VID_0403&PID_6015`) left the USB tree entirely
  (`Present: False`) while the USB-Blaster stayed OK, then re-enumerated on its
  own. Every failure was host transport during app load — none reached the
  solver, none produced a wrong number. Worth watching: it is a plausible way to
  lose a hackathon demo.
- **`jtagconfig` reported `No JTAG hardware available` at session start** with
  the Blaster showing OK in Device Manager. `jtagconfig --enum` recovered it
  without Administrator rights. `board-validate/SKILL.md` gotcha 5 offers only
  replug or `Restart-Service JTAGServer -Force` (which needs an elevated shell
  and fails from a normal one) — `--enum` is a cheaper first try worth adding.

## The honest caveat on the comparison

On the two easy boards `s2fast` is **slower in real time** than v0 — 7.67 µs vs
3.3 µs on easy1 — because the fixed ~181-cycle wrapper overhead now dominates the
window while F_max is 3.57x lower. The win is entirely on boards that actually
search: 68x on 51blanks, 75,915x on hard1. That is the right trade for the graded
metric, and it is also the thing to say out loud rather than let someone find.
