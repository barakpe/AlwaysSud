# Cloud -> laptop handoff

`comp_fpga` only runs on the cloud. The board only exists on the laptop. `hard1` -
the score - cannot be simulated. So a step is finished only when both machines have
reported, and this file is the contract between them.

## The cloud agent writes this into the branch

```
## HANDOFF <tag> <date>

bitstream   : $MY_K5_PROJ/hw/gen_fpga/prog_files/k5_xbox_alwaysud.sof
              (desktop shortcut: k5_xbox_links/)
enums md5   : <md5 of sw/apps/alwaysud/alwaysud_enums.svh>
commit      : <sha>

download    : the .sof, plus sw/apps/alwaysud/ and sw/apps/sud_shared/
              -- from the SAME build, in the SAME sitting

expected    : easy1 <n> / 20blanks <n> / 51blanks <n> cycles in simulation
              hardware must match these EXACTLY - they are cycle counts, not timings

cost        : LEs <n>  registers <n>  F_max standalone <n> MHz
              system F_max <n> MHz  memory bits <n>
```

## The laptop agent checks before running anything

1. **enums md5 matches.** If not, **stop** - do not program the board, do not
   report a number. A stale `.svh` against a fresh `.sof` compiles clean and
   misbehaves at runtime; we lost an evening to exactly this in week 2.
2. The `.sof` timestamp is newer than the last one programmed.
3. `sud_shared/` is present - `-asl sud_shared` needs it.

## The laptop agent reports back

```
## HW RESULT <tag> <date>

cycles      : easy1 <n> / 20blanks <n> / 51blanks <n> / hard1 <n>
vs sim      : match / MISMATCH on <board>
correctness : all four md5 PASS / FAIL on <board>
insight     : anything the numbers alone do not say
```

**A simulation/hardware cycle mismatch is a red flag, not a rounding error.** They
matched to the digit on all four week-2 runs. If they diverge, something is
genuinely different between what was simulated and what was fitted - investigate
before recording the number.

## Laptop gotchas, learned the hard way

- `$HOME` in git-bash is `C:\SPB_Data`, **not** `C:\Users\barak`. `~/Downloads`
  is wrong; use `/c/Users/barak/Downloads`.
- The portal ships `SOCA_Download_*.zip` whose internal path is the full cloud path.
  Unzip, then `find`, then copy. There are no loose folders to `cp`.
- Line endings: the board `.txt` files are parsed by `load_hex_file`. Keep them LF.
