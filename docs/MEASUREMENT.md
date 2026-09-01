# Measurement protocol

**Both agents obey this file.** If it changes, every earlier row in `RESULTS.md` is
re-measured or struck through - otherwise the numbers are not comparable and the
diary is fiction.

## The board set, and where each one runs

| board | checks | backtracks | simulation | hardware |
|-------|--------|-----------|------------|----------|
| `easy1` | 13 | 1 | yes | yes |
| `20blanks` | 111 | **0** | yes | yes |
| `51blanks` | 37,652 | **4,157** | yes | yes |
| `hard1` | 87,546,317 | 9,727,332 | **no - ~30 h** | **yes - THE score** |

Two things follow, and both matter:

- **`51blanks` is the correctness gate**, not `easy1`. The default 20-blank board
  never backtracks at all, so it cannot catch an unwind bug. `easy1` backtracks once.
  Only `51blanks` exercises the unwind path hard.
- **`hard1` is the score, and only hardware can measure it.** So the cloud can never
  declare a step finished on its own.

## The metric

**Solve cycles**, as printed by `report_task_performance("Sudoku solve")`.

**Never wall-clock.** Measured on this setup: run-to-run jitter ~4 s against a
compute signal of ~0.3 s. Wall time here measures UART and host startup, not the
design. Cycles are exact and match between simulation and silicon - verified in
week 2, to the digit, on four runs.

## The correctness gate

The geometry lives in `bench/units.py` and nowhere else. `solve_ref.py` and `diagnose.py`
derive peers, hidden singles and legality from that table, so a hackathon variant is a
change to one file - `python bench/solve_ref.py --check <board> <log> --variant diagonal`.
Verified 2026-08-31: the v0 hard1 grid is legal under `classic` and illegal under
`diagonal` and `windoku`, which is the check the old hardcoded gate could not make.

Note the RTL does **not** yet share this table.

Runs **before** any timing number is recorded. A faster wrong answer is not a result.

```bash
python bench/solve_ref.py --check <board> <captured-stdout>
```

The oracle in `bench/solve_ref.py` uses constraint propagation + MRV - deliberately a
*different* algorithm from the hardware, so a misunderstanding baked into the RTL
cannot cancel itself out against the golden. Its `51blanks` solution has been
confirmed identical to what the FPGA produced in week 2.

## Which window, and the switches that choose it

`report_task_performance()` reports the delta since the previous call, so where the calls
sit defines what a number means. `sw/apps/alwaysud/alwaysud.c` has two compile switches:

| switch | default | effect |
|---|---|---|
| `ALWAYSUD_SPLIT_TIMERS` | 1 | separate `Board setup+load` and `Sudoku solve` windows |
| | 0 | one window spanning setup+solve - **identical in shape to the course's `sudx_scan`** |
| `ALWAYSUD_PROBE_TIMER_COST` | 0 | adds a back-to-back report call; its delta is the cost of one call |

**Never compare a split number to an unsplit one.** Our easy1 "Sudoku solve" is 283 with
the split and would be larger without it, and the smaller number is not an improvement -
it is a different question. Quote the window whenever you quote a cycle count.

**Use `=0` for a scoring run**, so the number is directly comparable to the baseline and
to other students. The split is for development, where separating a fixed cost from the
search is what makes a change legible.

**The split costs a flat +155 cycles**, measured on the board across all four puzzles
(`logs/timer_probe/RESULT.txt`). Only 35 of that is the call seam - the rest is code
generation, because the RISC-V waits for the accelerator in a *software* poll loop and
recompiling changes when that loop notices.

Which means: **small-board cycle counts are not a pure hardware property.** Adding one
probe call moved `setup+load` from 235 to 275 with the RTL untouched. Treat an easy1
movement under ~50 cycles as noise unless the binary is byte-identical. hard1, at
128.7M, is immune to all of this.

## What gets recorded, every time

| metric | source | limit |
|--------|--------|-------|
| solve cycles, per board | app stdout | minimise |
| grid md5 | `solve_ref.py --check` | **must pass** |
| logic elements | `qsyn_xlr -syn` | < 20,000 |
| registers | `qsyn_xlr -syn` | watch |
| memory bits | `comp_fpga` | system already at 83% |
| F_max standalone | `qsyn_xlr -sta` | **>= 56.45 MHz** |
| F_max system | `comp_fpga` | >= 50 MHz |
| placements / backtracks | HW counters (backlog 1) | minimise |

**F_max is a budget you are spending.** You start at ~142 MHz and only need ~56.45.
Every parallel structure spends some. Record it every step and watch it drain - the
step that drops below the platform's 56.45 MHz is where the accelerator becomes the
system bottleneck, which is a real finding worth reporting, not a failure.

## Sequence

**Cloud** (`.claude/skills/cloud-measure/measure_cloud.sh <tag> [--with-fpga]`)

1. `bench/stage.sh` - copy `hw/` and `sw/` into `$MY_K5_PROJ`
2. `qsyn_xlr alwaysud -all` - parse LEs, registers, F_max. Any error stops here.
3. For each of easy1 / 20blanks / 51blanks: `launch_k5_sim` in the background,
   `launch_k5_app` in the foreground, capture stdout
4. Correctness gate on each
5. `comp_fpga alwaysud` - bitstream + system F_max + memory bits
6. Write the handoff block and publish the GitHub release - see `HANDOFF.md`

**Laptop** (`.claude/skills/board-validate/validate_board.sh <tag>`)

1. Fetch the release for the tag; verify the tree against its **commit**, plus both
   md5s. **Refuse to program if any of them fails** - see `board-validate/SKILL.md`
   for why the commit and not just the contract file.
2. `prog_fpga alwaysud`
3. All four boards including `hard1`, capture stdout
4. Correctness gate on each, twice: `bench/golden/` and the app's own checker
5. Compare cycles against the release's expected values - an inexact match fails
6. Logs under `logs/<tag>_hw/`; the `RESULTS.md` row is written by hand

## Merge criteria

| gate | threshold |
|------|-----------|
| all grids md5-match, sim + hardware | mandatory |
| `hard1` cycles improved | or a written reason it is an **enabler** |
| logic elements | < 20,000 |
| F_max standalone | >= 56.45 MHz |
| diary entry complete, incl. **Surprise** | mandatory |

The enabler clause is real: v2 masks may cost cycles alone while making v3 and v4
possible at all. That is a legitimate merge - but write down why, or in three weeks
nobody remembers what a regression is doing in `main`.
