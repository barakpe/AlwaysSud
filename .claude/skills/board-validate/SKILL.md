---
name: board-validate
description: Run the laptop half of one AlwaysSud iteration on the physical DE10-Lite - fetch the cloud's GitHub release for a tag, prove the working tree is the one the bitstream was built from, program the FPGA, run easy1/20blanks/51blanks/hard1, gate correctness twice, and compute the score. Use when asked to validate, verify on hardware, program the board, or get the hard1 number for a tag.
---

# board-validate

The other half of `cloud-measure`. The cloud can synthesise, simulate and predict; it
**cannot finish a stage**, because `hard1` is the score and `hard1` only exists here.

**It never runs `git commit`, `push`, or `tag`.** It reads git only to compare the tree
against the release. Barak reviews and commits.

## Run it

```bash
.claude/skills/board-validate/validate_board.sh <tag>
.claude/skills/board-validate/validate_board.sh <tag> --boards easy1,51blanks
.claude/skills/board-validate/validate_board.sh <tag> --no-fetch     # reuse the download
```

Outputs land in `logs/<tag>/hw/`: `hw_<board>.txt` (app stdout — the measurement),
`gate_<board>.txt`, `prog.txt`, `cycles.txt`, `release_notes.txt`, `warnings.txt`, and
`HW_RESULT.txt`. All text, all versioned.

`hard1` takes about 20 s of wall time, of which ~2.3 s is the solve. The rest is UART
and app startup, and none of it is the score.

## The order matters: verify, then touch the board

Everything in phase 2 happens **before** the FPGA is programmed. Programming first and
checking afterwards means the numbers already exist, and a number that exists gets
believed.

| phase | stops the run |
|---|---|
| 1 release exists, both assets present | no release, or the `.svh` is missing from it |
| 2 tree matches the release's commit | any drift in `sw/apps` or `hw/xlrs` |
| 2 `sof_md5` / `enums_md5` vs the notes | any mismatch |
| 2 release `.svh` vs the repo `.svh` | any difference — the contract would be ambiguous |
| 3 JTAG present | `No JTAG hardware available` |
| 5 programming | anything but `Programmer was successful` |

### Why the gate is the commit and not a checksum

The obvious check is "md5 the contract file", and it is not sufficient. The register
*bit layout* lives in **two hand-maintained copies** — the C union in
`sw/apps/alwaysud/alwaysud.h`, and a packed struct declared inline in
`hw/xlrs/alwaysud/alwaysud.sv`. `alwaysud_enums.svh` holds only register indices and
command codes. Adding a field to `done_reg` — the backlog's placement/backtrack counters,
for instance — changes the `.h` and the `.sv` and leaves the `.svh` **byte-identical**.
An `enums_md5` check passes while the contract is broken.

`git diff --quiet <sha> -- sw/apps hw/xlrs` covers every contract-bearing file, including
ones nobody remembered to list. Enumerating files is how the `.h` was missed. Do not
enumerate.

## What it watches for after the run

Stopping on a broken gate is easy. These are the ones that produce a plausible-looking
number that is wrong, which is worse.

| warning | what it means |
|---|---|
| **hardware cycles ≠ the release's expected cycles** | sim and fabric ran different designs. They matched to the digit on every run so far; a mismatch is a red flag, never rounding. Fails the run. |
| **our golden gate and the app checker disagree** | one of the two is lying. Worse than either failing alone, because a single passing gate would have been believed. Fails the run. |
| **"Solved" printed but the checker FAILED** | the week-3 store-bug signature. Run `python bench/diagnose.py <board> logs/<tag>/hw/hw_<board>.txt` — it says whether the damage is burst-aligned, a shifted copy, zeros, or an illegal grid. |
| **`setup+load` varies across boards** | it is a fixed 32+32+17 burst cost and must not depend on the puzzle. If it moves, something now reads the data during load. |
| **every cycle count identical to the previous tag** | either the tag genuinely changed nothing, or **the board is still running the old bitstream**. The second is the common one and it looks exactly like "no improvement". |
| **CR in a `sudoku_input_*.txt`** | `load_hex_file` expects LF and fails quietly on CRLF. |

## Laptop gotchas, all learned the hard way

1. **Every k5 command is an alias**, and bash does not expand aliases in
   non-interactive shells. `k5x_env.sh` does `shopt -s expand_aliases` first. A plain
   script without it sees no `prog_fpga`, no `launch_k5_app`, no `set_k5_terminal`.
   For reference: `set_k5_terminal` is just `cd $MY_K5_PROJ/run`, and `prog_fpga` is
   `source .../prog_fpga.sh` — which is why it resets the shell's cwd when it finishes.

2. **`setup_win.sh` needs `K5X_ROOT` preset.** Without it, it reports
   `cannot find /k5_xbox_fpga_win/setup/setup_common.sh` and returns 0 anyway, leaving
   every variable empty.

3. **`$HOME` in git-bash is `C:\SPB_Data`, not `C:\Users\barak`.** `~/Downloads` is not
   your Downloads folder. Use absolute paths.

4. **`gh release view --json` panics on this laptop.** go-keyring reads the Windows
   credential store from a worker goroutine and dereferences nil:
   `panic: runtime error: invalid memory address ... windowsKeychain.Get`. `gh release
   list` and `gh auth token` work, so auth is fine. `k5x_env.sh` exports `GH_TOKEN`
   explicitly, which keeps `gh` off the keyring path. This is a `gh` bug, not a course
   bug — do not report it for bonus.

5. **JTAG goes stale between sessions.** `No JTAG hardware available` while Device
   Manager shows the USB-Blaster as OK means replug the cable. If that fails,
   `Restart-Service JTAGServer -Force` from an **Administrator** PowerShell —
   `taskkill` on `jtagserver.exe` is Access Denied from a normal shell. Observed
   2026-08-31: the board programmed and ran four boards at 21:17, and JTAG was stale
   again by 22:08 with nothing unplugged.

6. **`prog_fpga` is once per power-up**, not once per app run. The 7-seg reads `Hi ddP`
   when the bitstream is live. But re-program anyway when validating a new tag — see
   the identical-cycles warning above.

7. **`sud_basic` (no `x`) is a different, software-only app** that is not installed
   here. The app is `alwaysud`.

8. **The UART header orientation can permanently damage the board**: facing the
   on-board logos, outer right-hand pin row, green wire right, black wire left.

## What must stay manual

- **The `insight:` line in `HW_RESULT.txt`.** The script leaves it blank on purpose.
  Cycle counts do not say why they moved.
- **Deciding whether a number is good.** An enabler regression — v2 masks costing
  cycles to make v3 possible — looks identical to a plain regression from here.
- **The DIARY entry and the RESULTS.md row.**
- **`git`.** All of it.
