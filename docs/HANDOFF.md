# Cloud → laptop handoff

`comp_fpga` only runs on the cloud. The board only exists on the laptop. `hard1` — the
score — cannot be simulated. So a stage is finished only when both machines have reported.

**The handoff is a GitHub release.** Not a file in the repo, not a portal download.

---

## Why a release, and not a commit

A `.sof` is 3.07 MB of already-compressed build output. Committed, it sits in history
forever, never delta-compresses, and every future clone pays for every iteration. Our own
conventions say never commit a `.sof`. A release asset lives outside the clone, can be
deleted, and costs nothing to anyone who does not want it.

**The real reason is not size.** A release pins the bitstream to the **commit** it was
built from, and that commit is what the laptop checks its sources against. A software tree
that has drifted from the bitstream *compiles clean and misbehaves at runtime*, and it has
already cost us an evening.

Note the release records a commit rather than shipping "the contract file", because there
is no single contract file — see the verification section below.

---

## Cloud: publish at the end of every stage

Run from the repo root, after the correctness gate has passed and `comp_fpga` has
succeeded. `TAG` is the stage name — `v0`, `v1`, `v2`.

```bash
TAG=v1
SOF=$MY_K5_PROJ/hw/gen_fpga/prog_files/k5_xbox_alwaysud.sof
SVH=$K5_SW_APPS/alwaysud/alwaysud_enums.svh

gh release create "$TAG" "$SOF" "$SVH" \
  --repo barakpe/AlwaysSud \
  --title "$TAG" \
  --notes "commit: $(git rev-parse HEAD)
enums_md5: $(md5sum "$SVH" | cut -d' ' -f1)
sof_md5: $(md5sum "$SOF" | cut -d' ' -f1)

expected solve cycles (hardware must match EXACTLY):
  easy1 <n> / 20blanks <n> / 51blanks <n>
setup+load cycles: <n>

standalone: LEs <n> / registers <n> / F_max <n> MHz
system:     LEs <n> / F_max <n> MHz / memory bits <n>%

correctness: all three boards PASS, golden gate and app checker"
```

**Re-publishing the same stage** (a re-measure, a fix) — do not delete the release, update
it in place:

```bash
gh release upload "$TAG" "$SOF" "$SVH" --repo barakpe/AlwaysSud --clobber
gh release edit   "$TAG" --repo barakpe/AlwaysSud --notes "...updated notes..."
```

**Rules for the notes block.** The laptop parses it, so:

- `enums_md5:` and `sof_md5:` are mandatory and must be bare lowercase hex.
- The expected cycle counts are **solve-window** numbers, not the pre-split totals, and
  not `report_total_performance()`. Say which window explicitly.
- If `comp_fpga` was not run, write `system: NOT BUILT` — never leave a stale line saying
  something was not built when it was. `logs/v0/HANDOFF.txt` did exactly that.

---

## Laptop: fetch and verify

Automated — `.claude/skills/board-validate/validate_board.sh <tag>`. It fetches the
release, runs the gates below, programs the board, runs all four puzzles and reports.
The skill's `SKILL.md` carries the laptop gotchas and what it warns about.

**The gates, in order, all before the board is touched:**

| gate | fails when |
|---|---|
| release exists, both assets present | no release, or no `.svh` in it |
| working tree vs the release's **commit** | any drift in `sw/apps` or `hw/xlrs` |
| `sof_md5` / `enums_md5` vs the notes | any mismatch |
| release `.svh` vs the repo `.svh` | any difference |
| JTAG present | `No JTAG hardware available` |

**Why the commit and not a checksum of the contract file.** The register *bit layout*
lives in two hand-maintained copies — the C union in `sw/apps/alwaysud/alwaysud.h` and a
packed struct inside `hw/xlrs/alwaysud/alwaysud.sv`. The `.svh` holds only register
indices and command codes, so adding a `done_reg` field changes both and leaves the
`.svh` byte-identical: an `enums_md5` check would pass with the contract broken.
Comparing against the commit covers every file, including ones nobody listed.

The `.svh` stays a release asset as a diagnostic — when the commit check fails, diffing
it shows *how* things drifted.

**Cycles must match the release's expected values exactly.** They have on every run so
far. A mismatch means simulation and fabric ran different designs; investigate before
recording anything.
