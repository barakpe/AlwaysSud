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

Runs **before** any timing number is recorded. A faster wrong answer is not a result.

```bash
python bench/solve_ref.py --check <board> <captured-stdout>
```

The oracle in `bench/solve_ref.py` uses constraint propagation + MRV - deliberately a
*different* algorithm from the hardware, so a misunderstanding baked into the RTL
cannot cancel itself out against the golden. Its `51blanks` solution has been
confirmed identical to what the FPGA produced in week 2.

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

**Cloud** (`bench/measure_sim.sh <tag>`)

1. `bench/stage.sh` - copy `hw/` and `sw/` into `$MY_K5_PROJ`
2. `qsyn_xlr alwaysud -all` - parse LEs, registers, F_max. Any error stops here.
3. For each of easy1 / 20blanks / 51blanks: `launch_k5_sim` in the background,
   `launch_k5_app` in the foreground, capture stdout
4. Correctness gate on each
5. `comp_fpga alwaysud` - bitstream + system F_max + memory bits
6. Write the handoff block - see `HANDOFF.md`

**Laptop** (`bench/measure_hw.sh <tag>`)

1. Verify `md5(alwaysud_enums.svh)` matches the handoff block. **Refuse to run if not.**
2. `prog_fpga alwaysud`
3. All four boards including `hard1`, capture stdout
4. Correctness gate on each
5. Append to `RESULTS.md`, save logs under `logs/<tag>/`

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
