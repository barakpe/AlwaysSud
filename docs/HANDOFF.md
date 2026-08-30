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

**The real reason is not size.** A release attaches the `.sof` **and its
`alwaysud_enums.svh` together, atomically**. That contract file is included by both the
SystemVerilog package and the C driver; a stale one against a fresh bitstream *compiles
clean and misbehaves at runtime*, and it has already cost us an evening. When both files
come from one release, you cannot fetch one without the other. The failure stops being a
discipline problem and becomes impossible by construction.

---

## Cloud: publish at the end of every stage

Run from the repo root, after the correctness gate has passed and `comp_fpga` has
succeeded. `TAG` is the stage name — `v0`, `v1-mrv`, `v2-prop`.

```bash
TAG=v1-mrv
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
  something was not built when it was. `logs/v0_verified/HANDOFF.txt` did exactly that.

---

## Laptop: fetch and verify

```bash
TAG=v1-mrv
DL=/c/Users/barak/Downloads/incoming        # NOT ~/Downloads - $HOME is C:\SPB_Data
rm -rf "$DL" && mkdir -p "$DL"
gh release download "$TAG" --repo barakpe/AlwaysSud -D "$DL"
gh release view "$TAG" --repo barakpe/AlwaysSud --json body -q .body > "$DL/NOTES.txt"
```

**Verify before programming anything:**

1. `md5sum "$DL/alwaysud_enums.svh"` matches `enums_md5:` in the notes.
2. `md5sum "$DL/k5_xbox_alwaysud.sof"` matches `sof_md5:`.
3. The release `commit:` is an ancestor of what you have checked out
   (`git merge-base --is-ancestor <sha> HEAD`).

**If any check fails, stop.** Do not program the board and do not report a number.

Then stage and run:

```bash
cp "$DL/k5_xbox_alwaysud.sof" $FPGA_PROG_FILES/
cp "$DL/alwaysud_enums.svh"   $K5_SW_APPS/alwaysud/
# the app sources themselves travel by git, so:
cd $ws_repo && git pull && bench/stage.sh

set_k5_terminal
prog_fpga alwaysud                                   # 7-seg reads "Hi ddP"
launch_k5_app alwaysud -asl sud_shared -gpv easy1
launch_k5_app alwaysud -asl sud_shared -gpv 20blanks
launch_k5_app alwaysud -asl sud_shared -gpv 51blanks
launch_k5_app alwaysud -asl sud_shared -gpv hard1    # the score
```

---

## Laptop reports back

```
## HW RESULT <tag> <date>

cycles      : easy1 <n> / 20blanks <n> / 51blanks <n> / hard1 <n>
vs sim      : match / MISMATCH on <board>
correctness : all four md5 PASS / FAIL on <board>
solve time  : hard1 cycles / <standalone F_max> = <n> us      <- the score
insight     : anything the numbers alone do not say
```

**A simulation/hardware cycle mismatch is a red flag, not rounding.** They matched to the
digit on all four week-2 runs. If they diverge, something differs between what was
simulated and what was fitted — investigate before recording anything.

---

## Laptop gotchas, learned the hard way

- `$HOME` in git-bash is `C:\SPB_Data`, **not** `C:\Users\barak`. `~/Downloads` is wrong.
- JTAG goes stale between sessions. `jtagconfig` saying `No JTAG hardware available` while
  Device Manager shows the USB-Blaster as OK means **replug the cable**. If that fails,
  `Restart-Service JTAGServer -Force` from an **Administrator** PowerShell.
- `sud_basic` (no `x`) is a different, software-only app that is not installed here.
  The app is `alwaysud`.
- Board `.txt` files are parsed by `load_hex_file` — keep them LF, not CRLF.
- The UART header orientation can permanently damage the board: facing the on-board logos,
  outer right-hand pin row, green wire right, black wire left.
