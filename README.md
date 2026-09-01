# alwaysud

A Sudoku solver in SystemVerilog, running on a DE10-Lite FPGA inside the K5-XBOX SoC.
Bar-Ilan DDP26 summer, hackathon project.

## What this is

The whole backtracking search runs in hardware. Software hands over the puzzle once
and asks a single question: solve it. The goal is to make that as fast as possible,
one measured change at a time.

**Where we are right now: [`STATE.md`](STATE.md).**
Results: [`RESULTS.md`](RESULTS.md) · Reasoning per step: [`DIARY.md`](DIARY.md) ·
How it works: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

## Getting started

Same shape as the course exercise repos: clone it, then copy `hw` and `sw` into the
K5 project tree.

```sh
tsmc65
cd $ws
git clone https://github.com/barakpe/AlwaysSud.git
cp -r AlwaysSud/hw my_k5_proj
cp -r AlwaysSud/sw my_k5_proj
```

### Synthesis check

```sh
cd $MY_K5_XLRS/alwaysud
qsyn_xlr alwaysud -all
```

### Simulation — two terminals

```sh
# terminal 1
set_k5_terminal
launch_k5_sim alwaysud

# terminal 2
set_k5_terminal
launch_k5_app alwaysud -asl sud_shared -gpv 51blanks
```

### Full FPGA build

```sh
cd $MY_K5_PROJ/hw/gen_fpga
comp_fpga alwaysud
ls $MY_K5_PROJ/hw/gen_fpga/prog_files/k5_xbox_alwaysud.sof
```

### On the board

```sh
set_k5_terminal
prog_fpga alwaysud
launch_k5_app alwaysud -asl sud_shared -gpv hard1
```

## Layout

```
hw/xlrs/alwaysud/       the accelerator  - mirrors $MY_K5_PROJ/hw/xlrs
sw/apps/alwaysud/       the driver       - mirrors $MY_K5_PROJ/sw/apps
sw/apps/sud_shared/  shared lib + the four puzzle files
bench/units.py       THE units table - the only place that knows the geometry.
                     A hackathon variant is a change to this file.
bench/               golden solutions, the correctness gate, staging, diagnosis
.claude/skills/      cloud-measure (synthesise+simulate+publish) and
                     board-validate (fetch+verify+program+run) - one per machine
reference/           vendored course code - read reference/PROVENANCE.md first
logs/<tag>/          cloud run output      } every text file versioned,
logs/<tag>_hw/       laptop run output     } binaries never
```

One accelerator, one name, everywhere: the folder, the `.f`, the module, the app, and
the argument to `qsyn_xlr` / `comp_fpga` / `prog_fpga` / `launch_k5_app`.
**Versions live in git** - branches for work in progress, tags (`v0`, `v1`, ...) for
milestones.

## The rules

- **Cycles, never wall-clock.** Wall time here measures UART, not the design.
- **Correctness gate before any timing number.** Every grid md5-matches
  `bench/golden/`, in simulation *and* on hardware.
- **One hypothesis per branch.** Other ideas go to [`BACKLOG.md`](BACKLOG.md).
- **Agents do not commit.** Barak reviews and commits. An agent may draft a commit
  message and leave it in its report.

Full protocol: [`docs/MEASUREMENT.md`](docs/MEASUREMENT.md).
