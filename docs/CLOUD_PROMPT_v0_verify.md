# Prompt for the cloud agent — re-measure v0, and challenge the plan

Paste the boxed section into a Claude Code session on the **BIU RC cloud**.

Two jobs: re-run v0 on the fixed RTL so we have a real baseline, and then **try to prove
the roadmap wrong** before we spend eleven days building it.

It does **not** commit.

---

```
I am a student in the DDP26-Summer course at Bar-Ilan, working on a hackathon project: a
Sudoku solver in SystemVerilog running on the k5_xbox FPGA platform. You ran the v0
baseline for me three days ago and wrote logs/v0/REPORT.md - read it first, it is yours.
Then read STATE.md, docs/ARCHITECTURE.md and docs/MEASUREMENT.md.

Since that session two things changed:

  1. The store bug you diagnosed (STORE addressed by next_store_start_idx but indexed the
     data by stored_start_idx) was independently found and fixed by the course staff. Your
     diagnosis was exactly right. Our RTL now carries their fix and is byte-identical to
     the course's corrected sudx_scan modulo the rename.
  2. I split the performance timer per your proposal 4. report_task_performance() reports
     the delta since the previous call, so solve() now reports "Board setup+load" after
     xlr_setup(), and main()'s "Sudoku solve" therefore covers the search alone.
     report_total_performance() prints the old combined number.

Pull the repo first - the fixes are in.


HARD RULES
==========
1. NO git commit / push / tag. I commit myself. You may draft commit messages.
2. Do not modify hw/ or sw/ except where TASK 3 explicitly permits a scratch copy under
   /tmp. This session measures and analyses; it does not optimise.
3. Warn me before anything over ~3 minutes. comp_fpga is expected to be slow; say so first.
4. If something fails, capture the exact output and stop that task. Do not work around it.


TASK 1 - the real v0 baseline
=============================
Re-run the full cloud measurement on the fixed RTL, using your own
.claude/skills/cloud-measure skill. Report:

  a. cycles per board for easy1 / 20blanks / 51blanks, now SPLIT into
     "Board setup+load" and "Sudoku solve". I want both numbers separately, and I want to
     know whether the setup overhead is the ~340 cycles you estimated.
  b. Do all three boards now PASS the correctness gate? That is the headline.
  c. Did the cycle totals change from 363 / 483 / 56,883? I predicted they would not,
     because the store bug corrupted what was written rather than how many bursts ran.
     Confirm or correct me.
  d. LEs, registers, memory bits, F_max standalone. Did any move?
  e. Then run comp_fpga and give me the full-system numbers and the handoff block. This is
     the step you correctly refused to run last time; the gate should pass now.


TASK 2 - is my cycle floor real?     [the important one]
========================================================
I claim the roadmap should NOT chase MRV, because propagation beats it. My evidence is a
software model of what parallel hardware could do per cycle, where a "round" recomputes
all 81 candidate masks at once and places EVERY forced cell simultaneously:

    board      blanks | naked-only: rounds guesses | naked+hidden: rounds guesses
    easy1          3  |      3        0            |      2        0
    20blanks      20  |      3        0            |      2        0
    51blanks      51  |     11        0            |      6        0
    hard1         64  |     91       14            |     66       15

The claim: three of four boards need ZERO search, and hard1 needs ~91 rounds and 14
guesses - against 56,883 cycles for 51blanks on the current design.

  a. Independently verify those round and guess counts. Write your own model; do not
     reuse bench/solve_ref.py, and do not trust my numbers. If you disagree, show me where.
  b. My cycles estimate assumes ~2 cycles per round. Is that defensible in RTL? Walk
     through what one round actually costs: recompute 81 masks from row/col/box used
     registers, detect which have exactly one bit, place them all, update the used
     registers. Where would you have to put a register boundary, and how many cycles does
     that really make a round?
  c. What breaks when a round places many cells at once? I know of one: two cells in the
     same unit both forced to the same digit is a contradiction that must be caught in the
     same cycle it is placed. Are there others I have not thought of?
  d. How do you undo a round on backtrack? A round can place 21 cells. Full mask snapshots
     are ~59,000 bits, which will not fit. Is recording only which cells were placed
     sufficient, or is there a case where it is not?


TASK 3 - how bad is claude_mrv's 5 MHz, really, and can it be fixed?
====================================================================
reference/ex3.1/sudx_standalone_ref/claude_mrv/sud_solver_mrv_claude.sv is a standalone
MRV solver. The assignment says it needs ~1,000 cycles for hard1 but synthesises to only
~5 MHz. My plan assumes that is fixable by pipelining.

  a. Synthesise it standalone with qsyn_xlr and tell me the REAL F_max, LEs and registers.
     The 5 MHz figure is from the assignment PDF and I have never verified it. Copy it to
     /tmp to do this - do not add it to hw/xlrs.
  b. Where is its critical path? I expect the 81 popcounts feeding a minimum-reduction
     tree, but check rather than assume - and tell me the delay breakdown the way you did
     for v0, logic vs routing.
  c. Given that path, where would you cut it to pipeline it, and what would each cut cost
     in cycles? I want a concrete proposal, not "it could be pipelined".
  d. Its row_used/col_used/box_used arrays: flops or block RAM? If RAM, that changes the
     plan significantly, because the propagation design must read all 81 masks per cycle.


TASK 4 - challenge the roadmap
==============================
Argue against my plan. The ladder is:
  v0-fix (re-measure) -> v1-mrv (integrate claude_mrv) -> v2-prop (naked-singles
  propagation on the masks it brings) -> v3-pipe (fix the frequency) -> v4-hidden -> v5-clock

  a. Is v1 worth doing at all, or should I go straight to building the propagation solver?
     I argued v1 banks an early win, proves the wrapper integration separately, and
     delivers the mask infrastructure. Is that right, or is it work I will delete?
  b. What is the single biggest risk you see that I have not named?
  c. Is there a materially better approach I have missed? I am optimising
     cycles / F_max. Consider anything: a different algorithm, exploiting something about
     the platform, restructuring the wrapper (you noted it costs 5,819 ALUTs against the
     solver's 2,357), attacking the memory bursts, whatever. Be concrete and quantify it
     if you can.
  d. My scoring assumption: solve_time_us = cycle_count / max_freq_mhz, with max_freq from
     standalone qsyn_xlr, per docs/Project_and_Hackathon_Assignment.pdf. Does anything in
     the environment contradict that, or make one term easier to move than I think?


DELIVERABLE
===========
Write logs/v0_verified/REPORT.md with a section per task, each opening with a verdict.
Then print the path and a 15-line summary.

Be blunt. If my floor numbers are wrong, say so with your own numbers. If the ladder is
wrong, say which rung and why. "You are wrong about X" is the most valuable thing you can
write here - I have eleven days and I would rather spend one of them finding out now.

Do not soften a failure and do not speculate in place of evidence.
```

---

## What comes back

Task 1 gives us the real v0 to tag. Task 2 either confirms the propagation floor or kills
it — and it is the one number the entire roadmap rests on. Task 3 tells us whether MRV's
frequency is fixable, which decides whether v1 is a stepping stone or a trap. Task 4 is
the sanity check on eleven days of work.
