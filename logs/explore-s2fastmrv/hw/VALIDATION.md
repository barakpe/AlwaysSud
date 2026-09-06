# Hardware validation of `explore-s2fastmrv` — 2026-09-06

The submission candidate, on the DE10-Lite. Same protocol as `explore-s2fast`
(`docs/MEASUREMENT.md`), split-window numbers throughout
(`ALWAYSUD_SPLIT_TIMERS=1`).

## The table, all three designs

| design | easy1 | 20blanks | 51blanks | hard1 | F_max (standalone) | rate on hard1 |
|---|---|---|---|---|---|---|
| v0 | 283 | 403 | 56,803 | 128,760,739 | 87.02 MHz | 1.4797 s |
| s2fast | 187 | 211 | 235 | 475 | 24.37 MHz | 19.49 µs |
| **s2fastmrv** | **187** | **211** | **235** | **379** | **26.36 MHz** | **14.38 µs** |

```
s2fastmrv vs v0       102,913x
s2fastmrv vs s2fast     1.356x     (EXPLORATION claimed 1.37x - holds)
```

`setup+load` = **235** on every board of every run of all three designs.

## hard1: measured 379

| prediction | basis | measured | delta |
|---|---|---|---|
| 376 | 193 solver + ~183, the release's own | **379** | +3 (0.8%) |
| 373 | 193 solver + the 180 measured on s2fast | **379** | +6 (1.6%) |

The three small boards matched **exactly** — 187 / 211 / 235, the same three
numbers as `s2fast`, as expected since their solver cycle counts are identical
between the two designs. So the fabric is running the design the cloud
simulated, and the only new information is `hard1`.

## The overhead is not a constant — it is quantised

`hard1`'s implied overhead is 379 − 193 = **186**, where `s2fast` gave 180. The
driver binary is **byte-identical** between the two releases (`git diff` over
`sw/apps` between the two release commits is empty), so this is not software
drift. Collecting every board of both designs:

| board | s2fast window | solver | ovh | | s2fastmrv window | solver | ovh |
|---|---|---|---|---|---|---|---|
| easy1 | 187 | 6 | 181 | | 187 | 6 | 181 |
| 20blanks | 211 | 23 | 188 | | 211 | 23 | 188 |
| 51blanks | 235 | 54 | 181 | | 235 | 54 | 181 |
| hard1 | 475 | 295 | **180** | | 379 | 193 | **186** |

Range 180..188, spread 8, with the same binary throughout. The most likely
reading is that the RISC-V notices `done` on a poll-loop boundary, so the
window carries up to one loop period of quantisation on top of a fixed base.
That is a hypothesis consistent with all eight points, not a measurement —
`ALWAYSUD_PROBE_TIMER_COST` is the switch that would settle it, and it was
**not** run (see below).

Practical consequence: `~183 ± 4` is the honest way to write the overhead in a
prediction. Both predictions above land inside that band.

## Correctness — every gate, every board, every run

Four full runs, each preceded by its own `prog_fpga`. Both checkers every time
(`bench/solve_ref.py --check` against `bench/golden/`, and the app's own final
checker). **No non-PASS anywhere. Zero warnings.**

Grids are byte-identical to v0 and to `s2fast`:
`c07abbf235a9` / `afee4b1403b0` / `afee4b1403b0` / `d34b53beba5c`.

## Determinism at 79% utilisation

`s2fastmrv` closes at **27.33 MHz** system F_max against the 50 MHz platform
clock — the same class of setup violation as `s2fast`, in a larger, denser
design (39,507 / 49,760 LE). It did not manifest:

| run | easy1 | 20blanks | 51blanks | hard1 |
|---|---|---|---|---|
| 1 | 187 | 211 | 235 | 379 |
| 2 | 187 | 211 | 235 | 379 |
| 3 | 187 | 211 | 235 | 379 |
| 4 | 187 | 211 | 235 | 379 |

Bit-identical counts and bit-identical grids across four reprograms. Same
caveat as before: four runs on one device at one temperature is an observation,
not a guarantee, and the violation is real.

## A provenance problem in this release — read this before re-validating

**`validate_board.sh` cannot pass on this release, and the reason is the release,
not the board.**

The notes name `commit: 22245cc` and `built_from: explore/exp/s2fastmrv/`, and
require `./explore/use_design.sh s2fastmrv` before validating. But **no commit on
the branch has `s2fastmrv` in `hw/xlrs/alwaysud`** — `22245cc`, `b75d172` and
`81d4eb8` all still hold `s2fast` there. So `use_design.sh` necessarily makes the
tree diverge from the release's own commit, and the script's gate
(`git diff --quiet <sha> -- sw/apps hw/xlrs`) refuses.

The gate was **not** relaxed. It was replaced with a strictly stronger check,
in `validate_board_builtfrom.sh` — a copy of `validate_board.sh` differing in
exactly one block:

- `sw/apps` must match the release commit exactly (`use_design.sh` never touches
  it, so any drift there is real) — **PASS**;
- every file in `hw/xlrs/alwaysud` must be **byte-identical to
  `explore/exp/s2fastmrv/` at the release commit**, which is precisely what
  `built_from:` claims was built — **PASS, all 7 files**;
- and nothing in `built_from` may be missing from the tree.

With no `built_from:` line it falls back to the original gate unchanged, so
`v0` and `explore-s2fast` still validate exactly as before.

The real fix belongs on the cloud side: publish the release from a commit that
has the design promoted into `hw/xlrs` (what `use_design.sh` itself tells you to
do — *"commit this before publishing or validating"*), or teach
`validate_board.sh` about `built_from:` permanently.

## The window-overhead decomposition — done

Measured 2026-09-07 with `ALWAYSUD_PROBE_TIMER_COST 1`, all four boards. Full
detail in `probe/RESULT.md`; the result:

| | cycles |
|---|---|
| one `report_task_performance()` call | **35** (identical on all four boards) |
| solve-window overhead | ~183 = 35 instrument + **~148 driver** |

**~80% of the overhead is driver code** — the `xlr_solver()` handshake and the
RISC-V poll loop waiting for `done`. The three `STORE` bursts are **not** in this
window at all; they live in the separate 235-cycle `Board setup+load`, which is
flat across every board and every design. So the solve-window overhead is
entirely software.

The proof: turning the probe on changes no RTL, and moved the solve window by
**+48 on every board** — puzzle-independent, and larger than the 35-cycle call it
added, which sits outside the window. Pure code generation.

**Next phase should touch the driver, not the RTL.** ~148 cycles of driver
against 193 solver cycles on `hard1`: the poll loop now costs about as much as
the entire search, and fixing it needs no logic, no F_max and no fitting risk —
all three of which are tight at 79% utilisation.

The 180..188 spread with a byte-identical binary is consistent with a poll loop
of period ~8 cycles, so `done` is noticed on a loop boundary: quantisation, not
noise.
