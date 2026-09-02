# v0 baseline — cloud session report

**Date:** 2026-08-26 · **Host:** BIU-Engineering RC cloud (`ip-10-70-151-48`, Linux)
**Repo:** `$ws/AlwaysSud` @ `28c7d69` (clean, nothing committed by this session)
**Logs:** `$ws/AlwaysSud/logs/v0/`

---

## 1. VERDICT

| | |
|---|---|
| v0 **builds** (standalone synthesis) | **YES** — 0 errors, LEs and F_max both inside budget |
| v0 **simulates** | **YES** — all three simulatable boards run to completion, deterministically |
| v0 **passes correctness** | **NO — all three boards FAIL** |
| Bitstream built (Task 4) | **NO — deliberately not run.** Task 3 says stop on a grid mismatch. |

**v0 is not a usable baseline.** The RTL produces a wrong grid on every board,
including `20blanks`, which never backtracks. The cycle counts below are real and
reproducible, but they are cycle counts of a design that computes the wrong answer,
so they cannot go in `RESULTS.md` as a v0 row.

### The defect, and where it is

Not in the solver. In the write-back burst in `hw/xlrs/alwaysud/alwaysud.sv`.

Evidence, in order of strength:

1. On every board the first **32** cells of the stored grid are correct and
   everything from cell 32 on is wrong. 32 is exactly the first memory burst
   (`LOAD`/`STORE` move 32 + 32 + 17 bytes).
2. On `easy1` and `20blanks` the corrupt tail is not noise — it is a verbatim copy
   of the beginning of the *correct answer*:
   `got[32:62] == want[0:30]`, exactly, on both boards.
3. `20blanks` backtracks **zero** times and fails identically. The search path is
   therefore not involved.
4. The corrupt region contains digits the *solver* produced (e.g. `easy1` cell 0 was
   blank; its solved value `2` reappears at cell 32). So the solver had already
   finished correctly — only the store is wrong.

Mechanism, confirmed against `mannix_mem_farm_lite.sv`: a write commits
combinationally in the same cycle `mem_req` is high (`mem_ack` is merely that signal
registered one cycle later, i.e. an ack of the *previous* write). In `alwaysud.sv`
`STORE`, the address and the data are indexed by **different** counters:

```systemverilog
// alwaysud.sv:157   address uses next_store_start_idx
mem_intf_write.mem_start_addr = xmem_board_addr + next_store_start_idx;
// alwaysud.sv:174   data uses stored_start_idx   <-- one burst behind
mem_intf_write.mem_data[i][3:0] = solver_puzzle_out_flat[stored_start_idx+i];
```

The first burst is correct (both counters are 0). Every later burst writes the
*previous* burst's data to the *current* burst's address. `LOAD` does not have this
bug: read data returns a cycle late, so indexing it by `loaded_start_idx` is right.

This is **inherited, not introduced by the port**. `hw/xlrs/alwaysud/*.sv` is
byte-for-byte identical to `reference/ex3.1/.../sudx_scan/*.sv` modulo the rename
(verified by diff). Whatever was validated on hardware in week 2 was not this RTL.

I have **not** changed any file under `hw/` or `sw/`.

---

## 2. The numbers

### Cycles (simulation) — reproducible to the digit across two independent runs

| board | blanks | backtracks (expected) | **cycles** | correctness |
|---|---|---|---|---|
| `easy1` | 3 | 1 | **363** | **FAIL** |
| `20blanks` | 20 | 0 | **483** | **FAIL** |
| `51blanks` | 51 | 4,157 | **56,883** | **FAIL** |
| `hard1` | 64 | 9,727,332 | not run — hardware only (~30 h in RTL) | — |

Both the manual pass and the skill's independent run produced 363 / 483 / 56,883.

**Caveat on what this metric measures.** `report_task_performance("Sudoku solve")`
reads the RISC-V cycle CSR around `solve()`, which is `xlr_setup()` **plus**
`xlr_solver()` — so it includes the board LOAD, both register handshakes and both
polling loops, not just the search. The fixed overhead is ~340 cycles
(363 for 3 blanks vs 483 for 20 ⇒ ~7 cycles per blank plus a large constant). For
`easy1` and `20blanks` the number is **mostly software handshake**; for `hard1` it
will be negligible. Worth separating before anyone reads an easy-board delta as a
solver improvement.

### Cost — standalone (`qsyn_xlr alwaysud -all`)

| metric | value | limit | verdict |
|---|---|---|---|
| Logic elements (Analysis & Synthesis headline) | **9,393** | < 20,000 | PASS (47% of budget) |
| Logic elements (Fitter — what lands on the device) | **8,967** / 49,760 = 18% | — | — |
| Registers | **1,867** / 49,760 = 4% | watch | — |
| Memory bits | **0** / 1,677,312 | — | see below |
| **F_max standalone** | **89.46 MHz** | ≥ 56.45 MHz | PASS (58% headroom) |
| Errors | **0** (syn, fit, sta) | 0 | PASS |
| Pins | 120 / 360 | — | — |
| Wall time | A&S 1:11 · Fitter 2:44 · STA 0:28 · **total 4:23** | — | — |

Two LE numbers exist and they differ. `docs/MEASUREMENT.md` says "logic elements —
source `qsyn_xlr -syn`", which is the 9,393 figure; the fitter's 8,967 is the honest
device number. **Record both.**

### Cost — full system (`comp_fpga`)

**Not measured.** Not run, per the Task 3 stop rule. No prior full-system report
exists anywhere in the tree to fall back on, so system F_max and system memory bits
are genuinely unknown for this design.

### Warning IDs, with counts

`qsyn_xlr` prints a de-duplicated ID list and a count that nets out its own
ignore-list. Raw per-ID counts from the reports:

| stage | tool's "non-justified" count | ID × count (from the report) |
|---|---|---|
| Analysis & Synthesis | 41 | `15610`×24 · `13410`×16 · `12161`×16 · `12158`×3 · `10230`×3 · `21074`×1 · `13024`×1 · `10036`×1 · `10027`×1 |
| Fitter | 1 | `332012`×1 · `292013`×1 · `169085`×1 · `15714`×1 |
| Timing Analyzer | 4 | `332148`×3 · `332012`×1 |

Flagged sets as printed: syn `[10036, 12158, 10230, 10027, 12161, 13024, 13410]`,
fit `[332012]`, sta `[332012, 332148]`. `15610`, `21074`, `292013`, `169085`, `15714`
are on the tool's ignore list.

**Only three point at our code.** The rest come from `qsyn_dummy_xlr_wrap_hri.sv`,
the synthesis-only test wrapper.

| ID | where | what |
|---|---|---|
| `10230` ×3 | `alwaysud.sv:83` | 32-bit host register truncated to the 16-bit `XMEM_ADDR_WIDTH`. Harmless — the board lives at offset 0 of the xmem — but silent. |
| `10027` ×1 | `alwaysud_solver.sv:65` | `grid[br + dr][bc + dc]` — index expression not wide enough for a 9-element array. |
| `10281` (info) | `alwaysud_solver.sv:5` | port `start` differs only in case from state `START`. `START` is declared but never used in the FSM; Quartus removed it. |

`332012` is **not our fault**: it is the missing `$QSYN/basic.sdc` (see 3.b/3.c below).

---

## 3. Environment map

### a. The commands

| command | what it is | lives at |
|---|---|---|
| `tsmc65` | alias | `startProject tsmc65 ; cd /data/project/tsmc65/users/$USER/ws` |
| `set_k5_terminal` | alias | `tsmc65 ; cd $MY_K5_PROJ/sim` — that is **all** it does |
| `qsyn_xlr` | alias → python | `/data/project/tsmc65/shared/qsyn/util/qsyn_xlr.py` |
| `comp_fpga` | alias → python | `$K5_XBOX_ENV/fpga/utils/qsyn_k5_xbox.py` |
| `launch_k5_app` | alias → python | `$K5_ENV/py/k5_server.py -xbox -mx10` |
| `launch_k5_sim` | **bash function** | defined in `$K5_XBOX_ENV/setup/k5_rc3_sim_setup.sh` |
| `kill_k5_app` | alias → python | `$K5_ENV/py/k5_kill_rc3_launch.py` — worth knowing when a run wedges |
| `prog_fpga` | **does not exist on the cloud** | laptop only |

**`ws` is not exported by `.bashrc`** — it is set by `startProject.bash`. And every
one of these is an alias or a function, so **none of them exists inside a plain
shell script**. This is the single biggest reason `bench/measure_*.sh` cannot work.

**`qsyn_xlr`** — `-sri`, `-hri`, `-syn`, `-fit`, `-sta`, `-all`. Only `-syn` and
`-all` actually work: `qsyn_xlr.py:196` runs `rm -r -f *db*` unconditionally on every
invocation, deleting the database `-fit` and `-sta` need. Both reproduced, both
printing `ERROR ... not generated` — **and both exiting 0**. `-hri` is auto-selected by
`if 'sud' in args.top` — "alway**sud**" matches by luck.

**`comp_fpga`** — `-syn`, `-fit`, `-sta`, `-all`, plus two you are not using:
- **`-mhz <int>`** — rewrites `ALTERA_MHZ=50` in the system `.qsf`. This *is* the
  `v5 clock` rung of the ladder; it needs no RTL change.
- **`-dstm`** — defines `DISABLE_STM` (disable single-thread mode).

**`launch_k5_app`** — the full list. You use `-asl`, `-gpv`, `-ccd1`, `-cmp`, `-hlcm`:

| flag | meaning |
|---|---|
| `-fpga` | FPGA mode (default is simulation) |
| `-rfe` | run forever (default: server stops when all threads are done) |
| `-mx10` | MAX10 device (already in the alias) |
| `-br <baud>` | UART baudrate (default 2000000) |
| `-tid <id>` | target k5 thread id |
| `-cmp` | **compile only** — fast C syntax check with no simulator at all |
| `-lx` | **load-execute only, skip compilation** — saves the C rebuild between runs |
| `-spmt` / `-srmt` / `-nt <n>` | multi-thread launch modes |
| `-stm` | single thread mode |
| `-ant` | **annotate the instruction trace** at end of execution (`trace_annotate.py`) |
| `-unrl` | compile with `-funroll-all-loops` |
| `-win` | windows bash environment |
| `-xbox` / `-xon` | XBOX defined / define `XON` |
| `-srld` | simulate real load-dump instead of the fast back-door load |
| `-itr <n>` | defines `_NUM_ITR_` |
| `-gpv <v>` | defines `_GP_VAL_` — this is how the board is chosen |
| `-ccd1/2/3 <d>` | conditional C defines (you use only `-ccd1`) |
| `-cca "<args>"` | **arbitrary extra C compiler arguments** |
| `-ard <dir>` | apps root dir (default `$MY_K5_PROJ/sw/apps`) |
| `-asl <lib>` | app-specific shared lib, relative to `-ard` |
| `-hlcm` | host-local C mode, SW only |

The useful ones you are not using: **`-lx`** (skip recompilation on repeat runs),
**`-cmp`** (compile-only smoke test — verified, takes seconds), **`-ant`**
(instruction-trace annotation), **`-cca`** (compiler flags).

**`-hlcm` does not work for `alwaysud`.** Two independent blockers, both verified:
1. Its default `-ard` is the literal string `NA` (the documented default is applied
   only on the non-HLCM path), so you must pass `-ard $MY_K5_PROJ/sw/apps` explicitly.
2. Even then it does not compile: `alwaysud.c` hides `#include "alwaysud_enums.svh"`
   behind `#ifndef HLCM`, so `SOLVE` is undeclared; and `sud_lib.c:14` (the HLCM
   branch) references an undeclared `sud_shared_path`. That HLCM branch has never
   compiled.

**`launch_k5_sim`** — `-probe`, `-probe_all`, `-xrun_flags "<quoted>"`, `-h`.
`-probe` writes `waves.shm` for SimVision covering the accelerator subtree only;
`-probe_all` covers the whole SoC. Both slow the simulation.

### b. Generated files

`qsyn_output_files/` after `qsyn_xlr -all` — 14 files. Archived to
`logs/v0/qsyn_output_files/`.

| file | what it is | the single most useful thing in it |
|---|---|---|
| `alwaysud.map.rpt` | Analysis & Synthesis | **"Analysis & Synthesis Resource Utilization by Entity"** — LEs and registers *per module*. See below; this is the report you have been under-using. |
| `alwaysud.map.summary` | 20-line digest of the above | the headline LE / register / memory-bit numbers without grepping a 92 KB file |
| `alwaysud.map.smsg` | suppressed/extra synthesis messages | caught `start` vs `START` here (info 10281) — nothing else surfaces it |
| `alwaysud.fit.rpt` | Fitter, 398 KB | **the real device LE count (8,967)**, plus "Non-Global High Fan-Out Signals" — which nets are becoming routing bottlenecks |
| `alwaysud.fit.summary` | Fitter digest | device utilisation as percentages: LE 18%, registers 4%, memory bits 0%, M9K 0 |
| `alwaysud.fit.smsg` | Fitter extra info | whether register packing / moving registers into RAM blocks happened |
| `alwaysud.sta.rpt` | Timing Analyzer, 204 KB | the **Fmax Summary panel** (89.46 MHz), which is the *unconstrained* Fmax and the only trustworthy timing number here |
| `alwaysud.sta.summary` | slack per corner | **currently useless.** Every setup slack is a huge negative because there is no clock constraint. |
| `sta_alwaysud_worst_paths.rpt` | 20 worst setup paths, full detail | the critical path, gate by gate, with per-hop delay |
| `alwaysud.flow.rpt` | flow control | **"Flow Elapsed Time"** — per-stage wall time and peak memory. Tells you what a re-synthesis will cost before you start one. |
| `alwaysud.pin` | 58 KB pin assignment list | irrelevant here — the standalone top is a dummy wrapper, not the real board |
| `map_/fit_/sta_alwaysud.log` | raw stdout of each Quartus binary | **where the error actually is when a stage fails** — `qsyn_xlr` tells you to look here and it is right |
| `src_ref/` | copies of the source files fed to Quartus | deleted at the end of `-all`; only survives after `-syn` |
| `qsyn_alwaysud_<user>_<date>.tgz` | submission archive | written to the accelerator dir, not `qsyn_output_files/` |

**What you have been ignoring, ranked:**

1. **Resource utilisation by entity, in `map.rpt`.** At v0:

   | entity | combinational ALUTs (own) | registers (own) | memory bits |
   |---|---|---|---|
   | `qsyn_dummy_xlr_wrap` (test harness) | 261 | 190 | 0 |
   | **`alwaysud` wrapper alone** | **5,819** | 353 | 0 |
   | `alwaysud_solver` | 2,357 | 1,324 | 0 |

   **The wrapper costs 2.5× the solver.** 69% of the combinational logic is the
   LOAD/STORE burst plumbing — two 32-wide variable-index accesses across an
   81-element array — not the search. Any area budget for parallelising the solver
   should be taken from there first.

2. **Memory bits = 0, everywhere.** This settles `BACKLOG.md` item 3: neither `grid`
   nor `stack` was inferred as block RAM. Both are in flops (1,324 registers in the
   solver ≈ grid 324 + stack 972 + pointers). You are free to read all 81 cells at
   once; no dual-port limit applies.

3. **`flow.rpt`'s elapsed-time table** — cheap way to know a re-synthesis costs 4:23
   before committing to it.

`output_files/` (the `comp_fpga` tree): **not inventoried — `comp_fpga` was not
run.** The only thing present is `map_k5_xbox_rc3.log` from an aborted 08:58 build
of `sudx_basic`, which turned out to be useful anyway — it is the evidence for proposal 17.

### c. The critical path

All **20** worst setup paths are the same path, and all of them are inside
`alwaysud_solver`:

```
From: alwaysud_solver|col[3]   (8 of 20; col[2] 8, col[1] 3, row[2] 1)
To:   alwaysud_solver|grid[6][7][1]   (20 of 20)
```

Gate by gate, with the source line each hop corresponds to:

| hop | delay | source |
|---|---|---|
| `col[3]` register → `q` | 0.21 ns | the column pointer |
| `get_box_start~1` | 0.43 ns | `bc = get_box_start(c)` — solver:54 |
| `Mux92 / Mux96~4,5,6` | 1.0 ns + 3.2 ns routing | `grid[br+dr][bc+dc]` — the 81-way variable-index read, solver:65 |
| `Mux108~7` | 0.30 ns | second stage of the same read mux |
| `Equal21~5,6` | 0.44 ns | `== v`, the digit compare |
| `valid~14,15` | 0.60 ns | the AND-reduction of `valid` across all 27 peers |
| → `grid[6][7][1]|ena` | 1.4 ns routing | `grid[row][col] <= val` gated by `is_valid` — solver:141 |
| **total arrival** | **14.76 ns** | |

**Read:** the path is *one* `is_valid` evaluation, from the column pointer, through
the box-start lookup, through the variable-index grid read, the compare, the
reduction, and into the grid write-enable. Routing is **~55% of it** (the three
worst hops are 1.45, 1.44 and 1.42 ns of pure interconnect) — this is a fan-out and
placement problem as much as a logic-depth problem.

**What that means for the roadmap.** `is_valid` for one digit already costs 11.2 ns
of the 17.7 ns you can afford at 56.45 MHz. Testing all nine digits in parallel
(`v1`/`v2`) does *not* lengthen this path — it replicates it nine times, which costs
area and routing, not depth. What *would* lengthen it is chaining anything else
after the `valid` reduction. The 89.46 → 56.45 MHz budget is ~6.5 ns of extra depth,
and the biggest single win available is not depth at all: it is replacing the
variable-index grid read (3.2 ns of mux + routing) with the bitmask representation
that `v2` is already planned to bring.

### d. What else is measurable

**Placements and backtracks: no, not today. You would have to add counters
yourself.** Stated plainly, as asked. Nothing in the SoC, the tooling or the
libraries counts anything about what the solver *did*.

What *is* available, in increasing order of effort:

1. **More software-side timers, no RTL change, no bitstream rebuild.**
   `k5_utils_lib.h` also exposes `report_total_performance()`,
   `pause_performance_count()` / `resume_performance_count()`, and the raw
   `GET_CYCLE_COUNT_START/END` macros. Putting one call between `xlr_setup()` and
   `xlr_solver()` in `alwaysud.c` would split the current single number into
   **LOAD+handshake** vs **solve**, which the current metric conflates (~340 cycles
   of the 363 on `easy1`). Cheapest real improvement to the measurement available.

2. **Waveform counting in simulation, no RTL change.** `launch_k5_sim alwaysud
   -probe` writes `waves.shm` covering the accelerator subtree. Counting entries
   into `state == BACKTRACK` off that database gives an exact backtrack count for
   `easy1` / `20blanks` / `51blanks` without touching the design. It does **not**
   help for `hard1`, which is the board that matters, and probing slows simulation.

3. **Hardware counters — the real answer, and it is cheap.** `XBOX_NUM_REGS = 16`
   and `alwaysud_enums.svh` uses **3**. There are **13 spare 32-bit host registers**.
   A placement counter and a backtrack counter in `alwaysud_solver`, surfaced on two
   spare registers and read by the C after `done`, is a few dozen lines and costs
   ~64 flops. `BACKLOG.md` item 1 proposes packing them into spare bits of
   `done_reg`; using whole spare registers instead is simpler, avoids narrowing, and
   still changes the `.svh` (so it still needs a bitstream rebuild and a new
   handoff md5).

4. **Instruction-level SW profiling:** `launch_k5_app ... -ant` runs
   `trace_annotate.py` over `trace.log`. That profiles the RISC-V side, which for
   this design is a polling loop — not useful here, but worth knowing it exists.

### e. Our own harness

Blunt, as asked.

| file | verdict |
|---|---|
| `bench/stage.sh` | **works**, with two real defects |
| `bench/measure_sim.sh` | **cannot run at all** |
| `bench/measure_hw.sh` | **cannot run at all** (plus laptop-only issues) |
| `bench/solve_ref.py` | **correct** — the only piece that needed no changes |

**`measure_sim.sh` and `measure_hw.sh` fail on line 1 of real use.** Every k5
command is an alias or a shell function, and a `#!/usr/bin/env bash` script inherits
neither. Verified: inside a plain script, `qsyn_xlr`, `set_k5_terminal`,
`launch_k5_sim`, `launch_k5_app`, `comp_fpga` and even `python` all report
"command not found". These scripts have never been executed.

Specifics beyond that:

1. **`measure_sim.sh:16`** — `grep -qE "0 +errors" || exit 1` runs *after*
   `qsyn_xlr -all`, which prints three separate "0 errors" lines. If synthesis
   succeeds and the fitter fails, the synthesis line alone satisfies the grep and
   the script sails past a failed build. It must require **three** successes and
   must also grep for `^ERROR`, because **`qsyn_xlr` exits 0 even when it fails**
   (`check_report()` uses Python's bare `exit()`).
2. **`measure_sim.sh:21,24`** — `( set_k5_terminal; launch_k5_sim ... )`: aliases
   again, and it never guards against a second simulator. That is the exact failure
   I hit by hand (a stray `xmsim` spun at 90% CPU for six minutes and served a board
   it should not have).
3. **`measure_sim.sh:25`** — `wait $SIM` with no timeout. When the simulator wedges
   this blocks forever.
4. **`measure_sim.sh:22`** — `sleep 2` is a guess about a race that does not exist
   the way the comment implies: `launch_k5_app` is the **server**, `launch_k5_sim` is
   the client. Harmless, but the mental model in the script is backwards.
5. **`measure_sim.sh` never stages.** `docs/MEASUREMENT.md` lists `stage.sh` as step
   1 of the same sequence, but `measure_sim.sh` starts at synthesis, so running it
   alone synthesises whatever happens to be in `$MY_K5_PROJ` — possibly last week's.
6. **`measure_sim.sh` never archives `qsyn_output_files/`**, which the next
   `stage.sh` then deletes (below). Every report is lost on the next iteration.
7. **`stage.sh:11`** deletes `$MY_K5_PROJ/hw/xlrs/alwaysud` — which **contains
   `qsyn_output_files/`**. I lost a full set of reports to this mid-session and had
   to re-synthesise. Correct, but it must run before synthesis, never after, and the
   reports must be copied out first.
8. **`stage.sh:13-14`** deletes nothing before copying `sw/apps/alwaysud` and
   `sw/apps/sud_shared`, contradicting its own comment on line 10. A stale `.c`,
   `.h` or `.svh` there survives — and a stale `.svh` is precisely the failure
   `docs/HANDOFF.md` says cost you an evening.
9. **`measure_hw.sh:22`** calls `set_k5_terminal`, which `cd`s. Everything after it
   that uses a relative path is then wrong. It also calls `prog_fpga`, which does
   not exist on the cloud — fine on the laptop, but the script gives no hint that it
   is laptop-only.
10. **`measure_hw.sh:29`** prints `CORRECTNESS FAIL` and **keeps going**, then prints
    a cycle summary anyway. `docs/MEASUREMENT.md` says the gate runs *before* any
    timing number is recorded. It should exit, as `measure_sim.sh:27` correctly does.
11. **`solve_ref.py` is right.** It re-solved all four boards independently and its
    goldens match. Its `extract()` handles the real `print_board` output correctly
    (the `------+-------+------` separators contain no digits). One latent hazard,
    not a bug today: cells are printed with `%d`, so a corrupt nibble ≥ 10 would
    print two characters and shift the whole 81-digit extraction. Worth an
    `if len(digits) != 81` sanity check rather than `digits[:81]`.
12. Minor: both scripts use `python`, which is an alias for `python3.9`. Use
    `python3` explicitly.

---

## 4. Proposals

Listed only. **No file under `hw/` or `sw/` was modified.**

**Correctness — blocking, do this first**

1. **Fix the STORE index mismatch** in `alwaysud.sv:174`: index the write data by
   `next_store_start_idx`, the same counter the address uses on line 157. One token.
   Re-run the gate on all three boards before believing any cycle number.
2. **Consider gating the write on the burst**, not just on `mem_req`: the current
   `STORE` writes to memory on *every* cycle `mem_req` is high, so it issues more
   writes than the three bursts it intends. Worth confirming with `-probe` once the
   index is fixed.
3. **Add a self-check to the correctness gate for "is this even a legal grid".**
   The corrupt output had duplicate digits within a row — cheap to detect and it
   points at the store rather than the search immediately.

**Measurement quality**

4. **Split the timer**: one `report_task_performance()` after `xlr_setup()` and one
   after `xlr_solver()`. Today ~94% of the `easy1` number is handshake, and nobody
   reading `RESULTS.md` would know.
5. **Record both LE numbers** (A&S 9,393 and fitter 8,967) in `docs/MEASUREMENT.md`,
   and say which one the 20,000 limit applies to.
6. **Stop quoting `*.sta.summary` slack.** With no `.sdc` present the numbers are
   meaningless; only the Fmax panel is real.
7. **Add the counters (`BACKLOG.md` 1) using two spare host registers**, not spare
   bits of `done_reg`. There are 13 free registers; narrowing buys nothing.

**Design, from the v0 reports**

8. **The wrapper, not the solver, is where the area is** — 5,819 ALUTs vs 2,357. If
   area ever binds, the 32-wide variable-index burst muxes are the target.
9. **Routing is ~55% of the critical path.** Depth-reduction alone will
   under-deliver; the bitmask representation planned for `v2` removes the
   variable-index grid read that dominates it, so `v2` may buy F_max as well as
   cycles.
10. **`comp_fpga -mhz <n>` exists** — the `v5 clock` step needs no RTL change.
11. **Delete the unused `START` state** in `alwaysud_solver.sv` (declared, never
    reached, differs only in case from the `start` port — Quartus flags it).
12. **Make the two truncations explicit** (`alwaysud.sv:83`, `alwaysud_solver.sv:65`)
    so the two warnings that point at our code go away and the next real one is
    visible.
13. **`sudx_cmd == STORE`** on `alwaysud.sv:121` compares a command enum against a
    *state* enum. It is unreachable today; it should be removed or given a real
    command.

**Housekeeping**

14. **Leftovers in `$MY_K5_PROJ`** from other accelerators, all of which `cp -r`
    merged around rather than replaced: `hw/xlrs/{sudx_basic, sudx_basic_SAFE_BACKUP_1787693662,
    sudx_scan, xmemcpy_ref}`, `sw/apps/{hello_k5, hello_me, sud_basic, sudx_basic,
    sudx_scan, xmemcpy_ref}`, two `.DS_Store` files, and a stale
    `prog_files/k5_xbox_sudx_basic.svf` from 2026-08-25. Harmless — `xlrs.f` only
    references `xmemcpy_ref` and the accelerator is selected by name — but it means
    "what is in the build tree" is not "what is in the repo".
15. **`hw/xlrs/xlrs.f` still lists only `xmemcpy_ref`.** It is not used by either
    flow (both build `$MY_K5_XLRS/$CRNT_XLR/$CRNT_XLR.f` directly), but it is
    misleading.
16. **`.gitignore` silently swallows the archived reports.** `qsyn_output_files/`,
    `*.rpt`, `*.qsf` and `*.qpf` are ignored at *any* depth, so
    `logs/<tag>/qsyn_output_files/` is preserved on disk against the next
    `stage.sh` but never reaches git. Verified with `git check-ignore`. Either add
    a `!logs/**` negation, or accept that only the console logs are versioned and
    say so in `docs/MEASUREMENT.md`. Right now the protocol implies the reports are
    kept as evidence and they are not.

17. **Never put a `#` comment in a `.f` file.** `dotf_to_qsf()` only skips `//`
    comments; a `#` line is handed to Quartus as a filename and the build dies with
    `Error (125080): Can't open project`. Evidence:
    `hw/gen_fpga/output_files/map_k5_xbox_rc3.log`, 2026-08-26 08:58.

---

## 5. The skill

`.claude/skills/cloud-measure/` — `SKILL.md`, `measure_cloud.sh`, `sim_board.sh`,
`k5_env.sh`.

**Tested end to end.** It staged, synthesised (reproducing 9,393 / 1,867 / 89.46 MHz
exactly), simulated all three boards (reproducing 363 / 483 / 56,883 exactly), then
stopped at the correctness gate with **exit code 1**, before `comp_fpga`. All three
simulators exited cleanly via `$finish`. It ran no `git` command.

It stops loudly on: any synthesis error, inferred latch or combinational loop; LEs
≥ 20,000; F_max < 56.45 MHz; any grid mismatch; a simulator that will not die.

`SKILL.md` also records 14 places where the environment does not behave the way the
guides say, each one something this session hit.

**What I deliberately left manual**, and why — the full list is in `SKILL.md`:
deciding whether a number is *good* (the enabler clause in `docs/MEASUREMENT.md` is a
judgement call and needs a written reason); `hard1`, which is the actual score and
only the laptop can measure; reading the critical path; interpreting a correctness
failure; anything touching `git`; and choosing the tag, because a tag names a
hypothesis.

---

## 6. Suggested commit messages

**Not committed. Nothing was staged. `git status` is untouched.** Only new files
under `logs/v0/` and `.claude/skills/` were created; no tracked file was modified.

```
v0 baseline: raw logs, and the correctness failure they found

Synthesis is clean and inside budget - 9,393 LEs (fitter: 8,967), 1,867
registers, 0 memory bits, F_max 89.46 MHz, 0 errors. Simulation is
deterministic: 363 / 483 / 56,883 cycles on easy1 / 20blanks / 51blanks,
identical across two independent runs.

All three boards FAIL the correctness gate. The first 32 cells - exactly
one memory burst - are correct on every board and everything after is a
verbatim copy of the start of the correct answer. 20blanks never
backtracks and fails identically, which rules out the search entirely.

Cause: alwaysud.sv indexes the STORE write data by stored_start_idx
(line 174) while addressing it by next_store_start_idx (line 157), so
every burst after the first writes the previous burst's data. LOAD is
correct - its data returns a cycle late, so the lagging index is right
there.

Inherited from ex3.1: hw/xlrs/alwaysud/*.sv is byte-identical to
reference/ex3.1/.../sudx_scan/*.sv modulo the rename.

No RTL changed. comp_fpga not run - the gate stops before the bitstream.
Full analysis in logs/v0/REPORT.md.
```

```
skills: add cloud-measure, built from the manual v0 pass

Stages, synthesises, simulates the three simulatable boards, runs the
correctness gate, optionally builds the bitstream, and emits the HANDOFF
block. Stops on a synthesis error, a grid mismatch, or LEs / F_max
crossing the limits. Never runs git.

Written from what actually worked, not from the guides. SKILL.md records
the 14 differences, including: every k5 command is an alias or a shell
function and so is invisible to a plain script; sourcing the project
setup clobbers "$@"; qsyn_xlr exits 0 on failure; -fit and -sta alone
are broken by an unconditional `rm -r -f *db*`; two simulators at once
means one of them spins forever at 90% CPU; and staging deletes the
synthesis reports.

Verified end to end: reproduces the v0 numbers exactly and exits 1 at the
correctness gate, before comp_fpga.
```

---

## 7. What I could not determine

1. **Full-system LEs, F_max and memory bits.** `comp_fpga` was not run — Task 3
   stops on a grid mismatch. No prior full-system report exists in the tree.
2. **Whether the STORE fix is sufficient.** The index mismatch fully explains the
   observed corruption on all three boards, but I did not apply it, so I have not
   proved the grids then pass. The `STORE`-writes-every-cycle question (proposal 2)
   is unresolved for the same reason.
3. **Whether `hard1` even terminates on this RTL.** Never simulated, never built.
4. **What was actually validated on hardware in week 2.** `docs/MEASUREMENT.md` and
   `docs/HANDOFF.md` both refer to `51blanks` matching on silicon. It cannot have
   been this RTL. Most likely `ex2.1`'s `sudx_basic`, but I did not verify that.
5. **Whether `easy1` really backtracks once and `51blanks` 4,157 times.** Those
   figures come from `docs/MEASUREMENT.md`. Nothing in the environment counts
   backtracks, so I could not confirm them.
6. **Why the standalone check ships without `$QSYN/basic.sdc`.** The file is
   referenced by `qsyn_xlr.py` and simply absent from the shared install. Whether
   that is deliberate (unconstrained Fmax reporting) or a broken deployment is a
   question for the course staff.
7. **The Desktop `k5_xbox_links/` contents after a real build.** Today it holds three
   symlinks (`fpga_prog_files` → `prog_files`, `my_k5_proj`, `sw_apps`) and the only
   file behind them is a stale `k5_xbox_sudx_basic.svf` from 2026-08-25. Reading
   `qsyn_k5_xbox.py`, a successful build would add `k5_xbox_alwaysud.sof` and
   `k5_xbox_alwaysud.svf` there — but that is from the script, not observed.
