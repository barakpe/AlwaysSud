# Prompt for the cloud agent — publish v0 as a release, and make it standard

Paste the boxed section into the cloud Claude Code session.

Short job: publish the bitstream that already exists, then bake the same step into the
skill so every future stage ends this way.

---

```
Change to how we hand off from cloud to laptop. Read docs/HANDOFF.md first - I rewrote it
and it is now the spec for this.

Until now the .sof was downloaded by hand through the cloud portal. That is the most
error-prone step we have: it has cost us a wrong $HOME, a zip with the full cloud path
buried inside it, and a stale contract file. From now on the handoff is a GitHub release.

The point is not convenience. Attaching k5_xbox_alwaysud.sof and alwaysud_enums.svh to the
SAME release binds them atomically. That .svh is included by both the SystemVerilog package
and the C driver, and a stale one against a fresh bitstream compiles clean and misbehaves at
runtime. If they can only be fetched together, that failure becomes impossible rather than
something we keep reminding ourselves about.

Do NOT commit the .sof to git. It is 3.07 MB of already-compressed build output; in history
it is permanent, never delta-compresses, and every future clone pays for every iteration.
Our own conventions say never commit a .sof.


TASK 1 - publish the v0 bitstream that already exists
=====================================================
comp_fpga already succeeded for v0 and the .sof is sitting in
$MY_K5_PROJ/hw/gen_fpga/prog_files/. Publish it as release `v0`, following the exact
format in docs/HANDOFF.md, "Cloud: publish at the end of every stage".

Fill the notes from the REAL v0_verified numbers, not from my summary:
  - commit SHA, enums_md5, sof_md5
  - expected SOLVE-window cycles per board, and the setup+load figure separately.
    Be explicit that these are the split numbers, not the pre-split totals. From the
    handoff I have: easy1 283 / 20blanks 403 / 51blanks 56,803, setup+load 235.
    Confirm those against your own logs before publishing them.
  - standalone LEs / registers / F_max
  - system LEs / F_max / memory bit percentage. comp_fpga DID run for v0, so fill these
    in properly. logs/v0_verified/HANDOFF.txt currently says "(not built)" for the system
    numbers, which is wrong - that block was written before the build and never refreshed.
    Fix that file too.

Then verify the release from the outside: re-download both assets to a scratch directory,
md5 them, and confirm they match what the notes claim. A release nobody has verified is
not evidence.


TASK 2 - make it part of the skill
==================================
Update .claude/skills/cloud-measure so publishing is the last step of a successful stage.

  - Only publish when the correctness gate PASSED and comp_fpga succeeded. Never publish a
    stage that failed the gate - a bitstream nobody should program must not be sitting
    there looking official.
  - Take the tag as an argument. If the release already exists, update it in place with
    `gh release upload --clobber` plus `gh release edit --notes`, rather than deleting and
    recreating it.
  - Generate the notes from the values the run actually measured. Do not template numbers
    in by hand - that is how HANDOFF.txt ended up claiming the system was not built.
  - Still no git commit, tag or push. Publishing a release is not committing; that is fine
    and it is the one write to GitHub the skill may do. If that distinction seems wrong to
    you, say so rather than silently doing more.
  - If `gh` is unavailable or unauthenticated at runtime, fail loudly with the manual
    fallback printed, rather than skipping the step quietly.

Update SKILL.md to describe the new final step and what it refuses to do.


TASK 3 - tell me what you would change
======================================
You have now used this flow once. Before I rely on it for ten iterations:

  a. Is anything in docs/HANDOFF.md's release format wrong or missing? I chose the notes
     fields by guessing at what the laptop will want to parse.
  b. Should the console logs be release assets too, or is committing them enough? Note the
     .gitignore currently excludes logs/**/*.txt except HANDOFF.txt, so right now the raw
     simulation output is versioned nowhere. That seems wrong to me either way - pick one.
  c. Anything else about the handoff that will break on the tenth iteration but not the
     first.


DELIVERABLE
===========
The v0 release published and externally verified, the skill updated, HANDOFF.txt corrected,
and a short report - what you published, what you changed in the skill, and your answers to
task 3. Draft a commit message for the skill change; do not commit it.
```

---

## Then, on the laptop

```bash
gh release download v0 --repo barakpe/AlwaysSud -D /c/Users/barak/Downloads/incoming
```

and the `hard1` run — which is still the only number nobody has.
