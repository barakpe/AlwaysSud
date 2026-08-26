# alwaysud

A Sudoku solver in SystemVerilog, running on a DE10-Lite FPGA inside the K5-XBOX SoC.
Bar-Ilan DDP26 summer, hackathon project.

The name is `always_comb` + `sudo`, sharing the middle *s*.

## What this is

The whole backtracking search runs in hardware. Software hands over the puzzle once
and asks a single question: solve it. The goal is to make that as fast as possible,
one measured change at a time.

**Where we are right now: [`STATE.md`](STATE.md).**
Results: [`RESULTS.md`](RESULTS.md) · Reasoning per step: [`DIARY.md`](DIARY.md)

## Layout

```
hw/xlrs/alwaysud/       the accelerator  - mirrors $MY_K5_PROJ/hw/xlrs
sw/apps/alwaysud/       the driver       - mirrors $MY_K5_PROJ/sw/apps
sw/apps/sud_shared/  shared lib + the four puzzle files
bench/               the measurement harness and the golden solutions
reference/           vendored ex2.1 and ex3.1, never built, for diffing
logs/<tag>/          raw run output, committed as evidence
```

One accelerator, one name, everywhere: the folder, the `.f`, the module, the app,
and the argument to `qsyn_xlr` / `comp_fpga` / `prog_fpga` / `launch_k5_app`.
**Versions live in git**, not in duplicated folders - branches for work in
progress, tags (`v0`, `v1`, ...) for milestones.

## Quick start

```bash
# cloud
git clone <this repo> && cd alwaysud
bench/stage.sh                 # copy hw + sw into $MY_K5_PROJ
bench/measure_sim.sh v0        # qsyn + simulate + verify

# laptop, after the cloud has built a bitstream
bench/measure_hw.sh v0         # program the board + run + verify
```

## The rules

- **Cycles, never wall-clock.** Wall time here measures UART, not the design.
- **Correctness gate before any timing number.** Every grid md5-matches
  `bench/golden/`, in simulation *and* on hardware.
- **One hypothesis per branch.** Other ideas go to [`BACKLOG.md`](BACKLOG.md).

Full protocol: [`docs/MEASUREMENT.md`](docs/MEASUREMENT.md).
