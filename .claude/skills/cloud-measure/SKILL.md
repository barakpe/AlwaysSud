---
name: cloud-measure
description: Run the cloud half of one AlwaysSud iteration on the BIU RC cloud - stage hw/ and sw/ into $MY_K5_PROJ, synthesise with qsyn_xlr, simulate easy1/20blanks/51blanks, run the correctness gate, optionally build the bitstream with comp_fpga, and publish the .sof + enums contract as a GitHub release. Use when asked to measure, baseline, or benchmark a tag/branch of the alwaysud accelerator.
---

# cloud-measure

Mechanical half of `docs/MEASUREMENT.md`. Everything here was verified by hand on
2026-08-26; where the course guides and reality disagree, this file follows reality.

**It never runs `git`.** Barak reviews and commits.

## Run it

```bash
.claude/skills/cloud-measure/measure_cloud.sh <tag>              # stage+syn+sim+gate
.claude/skills/cloud-measure/measure_cloud.sh <tag> --with-fpga  # ... + bitstream
```

Outputs land in `logs/<tag>/`: `qsyn.txt`, an archived `qsyn_output_files/`,
`sim_<board>.txt` (app stdout - this is the measurement), `gate.txt`, `cycles.txt`,
and `HANDOFF.txt`. Only `HANDOFF.txt` is versioned; the rest is gitignored tool output.

`HANDOFF.txt` is the release notes verbatim. Every value in it is scraped from the logs
that run produced - nothing is templated in by hand, which is how an earlier version came
to claim `system: (not built)` for a build that had in fact succeeded.

Warn the user before starting: synthesis is ~4.5 min, the three sims ~2 min total,
and `--with-fpga` adds **more than ten minutes**.

## It stops, loudly, on

| gate | threshold |
|---|---|
| synthesis error / inferred latch / combinational loop | any |
| logic elements | >= 20,000 |
| F_max standalone | < 56.45 MHz |
| grid mismatch vs `bench/golden/` | any board |
| a simulator that will not die | any |

A correctness mismatch stops the run **before** `comp_fpga`, and therefore before the
release. A faster wrong answer is not a result, and a bitstream nobody should program
must not be sitting on the releases page looking official.

## The last step: publish the release

`docs/HANDOFF.md` is the spec. With `--with-fpga`, and only if the gate passed *and*
`comp_fpga` succeeded, the run ends by publishing `k5_xbox_alwaysud.sof` and
`alwaysud_enums.svh` to a GitHub release named for the tag.

**Why both files in one release.** The `.svh` is included by the SystemVerilog package and
by the C driver. A stale one against a fresh bitstream compiles clean and misbehaves at
runtime. Attached to the same release, they cannot be fetched apart - the failure becomes
impossible rather than something to stay disciplined about.

`publish_release.sh` refuses to publish when:

- `sof_md5:` or `enums_md5:` in the notes disagrees with the actual file (something
  regenerated one without the other);
- the notes say `system: NOT BUILT`;
- `hw/` or `sw/` is dirty - the commit named in the notes would not describe the
  bitstream, and the laptop's ancestor check would pass anyway and tell it nothing;
- the staged `.svh` differs from the repo copy - the laptop would `git pull` sources
  that disagree with the contract file it just fetched;
- an asset is missing;
- `gh` is absent or unauthenticated - it fails with a **non-zero exit** and prints the
  exact manual `gh release create` / `upload --clobber` commands. It never skips quietly.

An existing release is **updated in place** (`upload --clobber` + `edit --notes-file`),
never deleted and recreated: deleting breaks a laptop mid-download and kills the old asset
URLs. After publishing it re-downloads both assets and re-checks their md5s, because a
release nobody has verified from the outside is not evidence.

**On the one write to GitHub.** Publishing a release creates a release object and a tag ref
on the remote. That is not a commit and not a push of history, and it is the only remote
write here - `git commit`, `git push` and `git tag` remain yours. But it is a real,
externally visible, hard-to-fully-undo write, so: it happens only on a fully passing run,
it is idempotent for a given tag, and the tag is an explicit argument, never inferred.

## Things that are not what the guides say

1. **Every k5 command is an alias or a shell function.** `qsyn_xlr`, `comp_fpga`,
   `launch_k5_app`, `set_k5_terminal`, `python` are aliases; `launch_k5_sim` is a
   function. A plain `#!/usr/bin/env bash` script sees **none** of them. Source
   `k5_env.sh` first. Corollary: `timeout` and `setsid` **cannot** wrap them - they
   exec real binaries and fail with "No such file or directory".

2. **Sourcing the project setup clobbers `"$@"` and changes the working directory.**
   After `source startProject.bash`, `$1` is a prompt string and the cwd is `$ws`.
   Capture your arguments on the first line of the script, and make any path argument
   absolute (`readlink -m`) *before* sourcing - otherwise a relative path silently
   resolves against the wrong directory.

3. **`qsyn_xlr` exits 0 even when it fails.** `check_report()` calls Python's bare
   `exit()`, which is status 0. Parse stdout for `^ERROR ` and for three
   `was successful` lines. Never trust `$?`.

4. **`qsyn_xlr -fit` and `-sta` alone always fail.** `qsyn_xlr.py:196` runs
   `rm -r -f *db*` unconditionally on every invocation, deleting the database the
   fitter and timing analyzer need. Only `-syn` and `-all` are usable.

5. **Parse the value after the colon, never with a bare `tr -dc '0-9'`.** `comp_fpga`
   labels its lines `Total FPGA Logic Elements (out of about 50K available):   20,560`,
   so stripping non-digits across the whole line yields `5020560`, and the memory-bits
   line yields `9618%`. Use `sed 's/.*: *//'` first.

6. **Two different LE numbers exist.** The headline `Total FPGA Logic Elements`
   comes from Analysis & Synthesis (9,393 at v0). The fitter reports what actually
   lands on the device (8,967 at v0). Record both; the 20,000 limit is checked
   against the headline because that is what `docs/MEASUREMENT.md` names.

7. **`$QSYN/basic.sdc` does not exist**, so the standalone check runs with **no
   clock constraint** - Quartus derives `create_clock -period 1.0` (1 GHz) and every
   setup slack in `*.sta.summary` is a meaningless large negative. The `F_max` line
   is still valid (it is the unconstrained Fmax panel, min across corners). Ignore
   the slack numbers; quote F_max.

8. **The two sim processes are peers, not parent/child.** `launch_k5_app` is the
   *server* and binds a `$USER`-hashed localhost port; `launch_k5_sim` (xrun/xmsim)
   is the *client*. Only one pair can run at a time. Start the sim in the
   background, the app in the foreground.

9. **Never let two simulators be alive at once.** Because the port is derived from
   `$USER`, a second `launch_k5_sim` cannot get a connection: it prints
   `Waiting for server connection` and then **spins at ~90% CPU forever**, and the
   app silently talks to the *other* simulator instead. This happened on
   2026-08-26: a stray simulator from an aborted run served the `easy1` app while
   the simulator that run had just started sat orphaned for 6 minutes until killed.
   The numbers were still correct, but only by luck.
   `sim_board.sh` therefore **refuses to start while any `xmsim` exists** and kills
   the simulator if it has not exited 120 s after the app quits. With that
   discipline all three boards exited cleanly via `$finish`. Check by hand with
   `pgrep -u $USER -x xmsim`.

10. **`hard1` is never simulated.** ~30 h of RTL. `sim_board.sh` refuses it.

11. **Staging deletes the synthesis reports.** `hw/xlrs/alwaysud/qsyn_output_files/`
    lives inside the directory that staging removes. `measure_cloud.sh` copies the
    reports into `logs/<tag>/` immediately after synthesis, before anything can
    re-stage. Do not reorder those steps.

12. **The archived reports are gitignored.** `.gitignore` excludes
    `qsyn_output_files/`, `*.rpt`, `*.qsf`, `*.qpf` at any depth, so the copy in
    `logs/<tag>/` survives the next staging but is never committed. Only the console
    logs (`qsyn.txt`, `sim_*.txt`, `HANDOFF.txt`, `cycles.txt`) are versioned.

13. **`.f` files: only `//` comments are skipped.** `dotf_to_qsf()` drops lines whose
    first token starts with `//`. A `#` comment is passed to Quartus as a filename
    and the build dies with `Error (125080): Can't open project`. Evidence:
    `hw/gen_fpga/output_files/map_k5_xbox_rc3.log` from the 2026-08-26 08:58 build.

14. **`-hri` is selected by a substring match on the top name**
    (`qsyn_xlr.py:189`: `if 'sud' in args.top`). "alwaysud" contains "sud", so we get
    the host-regs wrapper by luck. Renaming the accelerator to something without
    "sud" in it would silently synthesise the wrong wrapper.

15. **`comp_fpga` moves the `.sof` to the Desktop.** It lands in
    `~/Desktop/k5_xbox_links/fpga_prog_files/`, which is a symlink to
    `$MY_K5_PROJ/hw/gen_fpga/prog_files/`, so both paths resolve. It also emits a
    `.svf`. The symlinks are only created if `k5_xbox_links/` did not already exist.

16. **`prog_fpga` does not exist on the cloud.** Laptop only.

## What must stay manual

The script automates the mechanical parts. It cannot do these, and should not pretend to:

- **Deciding whether a number is good.** The gates catch limit violations. They
  cannot tell an enabler regression (v2 masks costing cycles to make v3/v4 possible)
  from a plain regression. `docs/MEASUREMENT.md`'s enabler clause is a judgement
  call, and it needs a written reason.
- **`hard1`, which is the actual score.** Only the laptop can measure it. The cloud
  can never declare a step finished.
- **Reading the critical path.** The script records `sta_*_worst_paths.rpt`; deciding
  what to parallelise next from it is design work.
- **Interpreting a correctness failure.** The script stops and prints the diff. Which
  of the RTL, the golden, or the board file is wrong is not something to guess.
- **`git`.** Staging, branching, tagging, committing: all human.
- **Choosing the tag.** A tag names a hypothesis, and hypotheses are human.
