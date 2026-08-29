# Prompt for the cloud agent — v0 baseline

Paste the boxed section into a Claude Code session on the **BIU RC cloud**.

Its job: clone the project the same way we clone the course exercises, run the v0
baseline **by hand with the guide commands**, learn the whole environment while doing
it, and only then turn what it learned into a skill.

It does **not** commit. Barak reviews and commits.

---

```
I am a student in the DDP26-Summer digital design course at Bar-Ilan. You are running on
the BIU-Engineering RC cloud (Linux). We are starting a hackathon project: a Sudoku
solver written in SystemVerilog that runs entirely on an FPGA. This session establishes
the BASELINE and maps out the environment.

Read the repo's own docs before doing anything: README.md, STATE.md,
docs/ARCHITECTURE.md, docs/MEASUREMENT.md, docs/HANDOFF.md.


HARD RULES
==========
1. DO NOT run `git commit`, `git push`, `git tag`, or anything else that writes history.
   I review and commit myself. You MAY draft commit messages and put them in your report.
2. DO NOT modify any file under hw/ or sw/ unless a task says to. This session measures;
   it does not optimise. If you spot an improvement, write it in the report as a proposal.
3. Do not "fix" my design to make something pass. If it fails, capture the exact output
   and stop that task.
4. Tell me before running anything you expect to take more than ~3 minutes.
   `comp_fpga` takes over ten - that one is expected, just say so first.


TASK 1 - clone and stage, the same way we do the course exercises
=================================================================
    tsmc65
    cd $ws
    git clone https://github.com/barakpe/AlwaysSud.git
    cp -r AlwaysSud/hw my_k5_proj
    cp -r AlwaysSud/sw my_k5_proj

The repo mirrors $MY_K5_PROJ, so those two cp commands are the whole staging step.
Confirm afterwards that these exist and tell me their sizes and timestamps:
    $MY_K5_XLRS/alwaysud/{alwaysud.f, alwaysud.sv, alwaysud_solver.sv, alwaysud_def_pkg.sv}
    $K5_SW_APPS/alwaysud/{alwaysud.c, alwaysud.h, alwaysud_enums.svh}
    $K5_SW_APPS/sud_shared/  (lib + four sudoku_input_*.txt)

Also print `md5sum $K5_SW_APPS/alwaysud/alwaysud_enums.svh` - that value is the HW/SW
contract checksum and goes in the handoff block later.

Note: `cp -r` MERGES into an existing directory, it does not replace. If anything looks
like a leftover from another accelerator, say so.


TASK 2 - synthesis, by hand, with the guide commands
====================================================
From ddp26s_qsyn_xlr_guide.pdf. Run them individually, in this order, not `-all` yet -
I want to see what each step produces on its own:

    cd $MY_K5_XLRS/alwaysud
    qsyn_xlr alwaysud -syn
    qsyn_xlr alwaysud -fit
    qsyn_xlr alwaysud -sta

KNOWN ISSUE, do not be surprised: `-fit` on its own is expected to FAIL with
"ERROR qsyn_output_files/alwaysud.fit.rpt not generated". The cause is known -
qsyn_xlr.py line 196 runs `rm -r -f *db*` unconditionally, so a -fit-only run deletes
the synthesis database the fitter needs. Capture the failure as evidence, then continue
with:

    qsyn_xlr alwaysud -all

Report: logic elements, memory registers, memory bits, F_max, error count, and the
warning IDs with counts.

Budget check: LEs must be under 20,000, and F_max must be at least 56.45 MHz - below
that our accelerator becomes the system bottleneck rather than the platform.


TASK 3 - simulation, by hand, two terminals
===========================================
This needs two cooperating processes. `launch_k5_sim` BLOCKS waiting for an app to
connect; `launch_k5_app` is the software side. Per board:
  - start `launch_k5_sim alwaysud` as a BACKGROUND process with output to a file
  - run `launch_k5_app alwaysud -asl sud_shared -gpv <board>` in the foreground
  - the printed boards appear on the APP side
  - confirm the sim process exits before starting the next board

Each needs `set_k5_terminal` in its own shell first.

Run these three, saving each one's full stdout under $ws/AlwaysSud/logs/v0/ :

    easy1        launch_k5_app alwaysud -asl sud_shared -gpv easy1
    20blanks     launch_k5_app alwaysud -asl sud_shared -gpv 20blanks
    51blanks     launch_k5_app alwaysud -asl sud_shared -gpv 51blanks

DO NOT run hard1 in simulation. It needs roughly 30 hours of RTL simulation. It is
measured on the FPGA only.

For each board report:
  a. the cycle count from `Sudoku solve` in the output
  b. the correctness gate:
        python bench/solve_ref.py --check <board> <the-captured-stdout-file>
     All three must PASS. 51blanks is the one that matters - it forces 4,157 backtracks
     and is the only board that exercises the unwind path hard. easy1 backtracks once and
     20blanks not at all.

If a grid does not match, STOP and report. Do not continue to Task 4.


TASK 4 - full FPGA build
========================
From ddp26s_k5x_gen_fpga_guide.pdf. Warn me first, this is the slow one:

    cd $MY_K5_PROJ/hw/gen_fpga
    comp_fpga alwaysud
    ls -l $MY_K5_PROJ/hw/gen_fpga/prog_files/k5_xbox_alwaysud.sof

Report the full-system numbers: logic elements, registers, memory bits, F_max, errors.
Then list what is in the Desktop k5_xbox_links/ folder, since that is where I download
from.

Finally write the handoff block exactly as docs/HANDOFF.md specifies, so my laptop agent
can pick it up.


TASK 5 - map the environment    [this is as valuable as the numbers]
====================================================================
While doing the above, build me a picture of what this environment actually offers. I
want to know what data I can get, not just what I asked for.

  a. COMMANDS. For each of qsyn_xlr, comp_fpga, launch_k5_sim, launch_k5_app: where does
     it live, is it a script or an alias, and what flags does it accept? Run the -h / --help
     where one exists. I especially want to know every flag of launch_k5_app - I currently
     use only -asl, -gpv, -ccd1, -cmp, -hlcm and I suspect there is more.

  b. GENERATED FILES. After the runs, inventory qsyn_output_files/ and output_files/.
     For each report file, one line: what it is and the single most useful thing in it.
     I know about .map.rpt, .fit.rpt, .sta.rpt and sta_*_worst_paths.rpt - tell me what
     else is there and what I have been ignoring.

  c. THE CRITICAL PATH. Open the worst-paths report and tell me where the longest path
     actually is. Which module, which signals. This decides what I can afford to make more
     parallel later, so it matters more than the headline F_max.

  d. WHAT ELSE IS MEASURABLE. Is there any way to get, from simulation or from the
     hardware, a count of placements or backtracks - or anything else about what the
     solver DID rather than how long it took? Right now I can only see total cycles, and
     that cannot distinguish "searched less" from "searched the same amount faster".
     If the answer is "you would have to add counters yourself", say that plainly.

  e. OUR OWN HARNESS. bench/ has stage.sh, measure_sim.sh, measure_hw.sh and
     solve_ref.py. They were written from a plan, before anyone had run this flow. Try
     them. Where are they wrong? Be blunt - that is the point of running by hand first.


TASK 6 - build the skill, from what you just learned
====================================================
Only now, once the manual pass is done. Write a Claude Code skill that performs the
cloud half of one iteration: stage, synthesise, simulate the three boards, run the
correctness gate, build the bitstream, emit the handoff block, and produce the numbers
in the exact shape docs/MEASUREMENT.md specifies.

  - Put it at .claude/skills/<name>/SKILL.md in the repo, with any helper script beside it.
  - Base it on the commands that ACTUALLY worked, including the two-terminal handling and
    anything that surprised you - not on what the guides say should work.
  - It must fail loudly and stop on: a synthesis error, a correctness mismatch, or LEs or
    F_max crossing the limits.
  - It must not commit anything.
  - Tell me honestly what should stay manual. A skill that pretends to automate judgement
    is worse than one that automates only the mechanical parts.


DELIVERABLE
===========
Write $ws/AlwaysSud/logs/v0/REPORT.md containing:

  1. VERDICT up front: did v0 build, simulate and pass correctness - yes or no.
  2. The numbers table: cycles per board; LEs, registers, memory bits, F_max standalone
     and full-system.
  3. The environment map from Task 5.
  4. Where our bench/ scripts are wrong.
  5. Proposals: anything you noticed that could be faster or cleaner. As a LIST, not as
     changes you made.
  6. Suggested commit messages for whatever files you added (the logs, the skill).
  7. Anything you could not determine, stated plainly.

Then print the file path and a 15-line summary to the terminal.

Be honest about failures. "Not reproduced", "could not determine" and "the script is
wrong here" are useful answers. Do not speculate in place of evidence, and do not soften
a failure - I would rather find out now than after I have built five things on top of it.
```

---

## After it reports back

Give me the report and I'll fold it into `RESULTS.md`, `DIARY.md` entry 1 and `STATE.md`,
and we'll fix `bench/` from what it found. Then the laptop half: hardware on all four
boards, `hard1` included, and that number becomes the one everything gets measured against.
