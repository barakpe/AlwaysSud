#!/usr/bin/env bash
# LAPTOP side of one AlwaysSud iteration: fetch the cloud's release, prove the sources
# in this tree are the ones it was built from, program the board, run all four puzzles,
# and report. hard1 is the score and only exists here.
#
# Usage: validate_board.sh <tag> [--no-fetch] [--boards a,b,c]
#
# It never runs git commit/push/tag. It reads git only to compare against the release.
set -u
TAG="${1:?usage: validate_board.sh <tag> [--no-fetch] [--boards list]}"; shift
FETCH=1; BOARDS="easy1,20blanks,51blanks,hard1"
while [ $# -gt 0 ]; do
  case "$1" in
    --no-fetch) FETCH=0 ;;
    --boards)   BOARDS="${2:?--boards needs a list}"; shift ;;
    *) echo "unknown argument: $1"; exit 2 ;;
  esac; shift
done

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"          # .claude/skills/board-validate -> repo root
source "$HERE/k5x_env.sh" || exit 1
OUT="$REPO/logs/$TAG/hw"; mkdir -p "$OUT"   # one directory per phase; cloud writes sim/
DL="/c/Users/barak/Downloads/incoming/$TAG"   # NOT ~/Downloads - $HOME is C:\SPB_Data
XLR=alwaysud
WARN=0
warn() { WARN=$((WARN+1)); echo "  !! WARN: $*" | tee -a "$OUT/warnings.txt"; }
die()  { echo "STOP: $*"; exit 1; }
: > "$OUT/warnings.txt"

echo "=============================================================="
echo " board-validate  tag=$TAG  $(date '+%F %T')"
echo "=============================================================="

# ---------------------------------------------------------------- 1. fetch
if [ "$FETCH" = 1 ]; then
  echo "=== 1. fetch release $TAG ==="
  rm -rf "$DL"; mkdir -p "$DL"
  gh release download "$TAG" --repo barakpe/AlwaysSud -D "$DL" \
    || die "no release '$TAG'. The cloud has not published this stage - nothing to validate."
  gh release view "$TAG" --repo barakpe/AlwaysSud --json body -q .body > "$DL/NOTES.txt" \
    || die "could not read the release notes (gh keyring? see k5x_env.sh)"
else
  echo "=== 1. fetch SKIPPED (--no-fetch), reusing $DL ==="
  [ -f "$DL/NOTES.txt" ] || die "--no-fetch but $DL/NOTES.txt is missing"
fi
cp "$DL/NOTES.txt" "$OUT/release_notes.txt"
SOF="$DL/k5_xbox_${XLR}.sof"; SVH="$DL/${XLR}_enums.svh"
[ -f "$SOF" ] || die "release has no $(basename "$SOF")"
[ -f "$SVH" ] || die "release has no $(basename "$SVH") - the HW/SW contract is not in the release"

# ---------------------------------------------------------------- 2. gates
echo "=== 2. verify BEFORE touching the board ==="
SHA=$(grep -m1 '^commit:' "$DL/NOTES.txt" | awk '{print $2}')
[ -n "$SHA" ] || die "release notes carry no 'commit:' line - cannot prove what was built"
git -C "$REPO" cat-file -e "${SHA}^{commit}" 2>/dev/null \
  || die "commit $SHA is not in this clone. git fetch first - do not guess."

# The gate is the COMMIT, not a file list. The register bit layout lives in
# sw/apps/alwaysud/alwaysud.h AND in a packed struct inside hw/xlrs/alwaysud/alwaysud.sv;
# the .svh holds only indices and command codes. Adding a done_reg field changes both
# and leaves the .svh byte-identical, so an enums-md5 check would pass while the
# contract was broken. Enumerating files is how the .h got missed in the first place.
if git -C "$REPO" diff --quiet "$SHA" -- sw/apps hw/xlrs ; then
  echo "  PASS  sources match the bitstream's commit ($SHA)"
else
  echo "  SOURCE DRIFT vs $SHA:"; git -C "$REPO" diff --stat "$SHA" -- sw/apps hw/xlrs
  die "the tree is not what was built. Programming this would measure a design you are not looking at."
fi

check_md5() { # <label> <file> <notes-key>
  local want have
  want=$(grep -m1 "^$3:" "$DL/NOTES.txt" | awk '{print $2}')
  have=$(md5sum "$2" | cut -d' ' -f1)
  if [ -z "$want" ]; then warn "$3 missing from the release notes - cannot verify $1"; return; fi
  if [ "$want" = "$have" ]; then echo "  PASS  $1 md5 $have"
  else die "$1 md5 mismatch: notes=$want actual=$have"; fi
}
check_md5 sof "$SOF" sof_md5
check_md5 enums "$SVH" enums_md5

# The .svh is also in git. If the release's differs, the pull and the download disagree.
if ! cmp -s "$SVH" "$REPO/sw/apps/$XLR/${XLR}_enums.svh"; then
  die "release .svh differs from the repo copy at this commit - the contract is ambiguous."
fi

# ---------------------------------------------------------------- 3. board present
echo "=== 3. board ==="
JT=$(jtagconfig 2>&1)
echo "$JT" | sed 's/^/  /'
echo "$JT" | grep -q "USB-Blaster" \
  || die "no JTAG hardware. Replug the USB-Blaster; if Device Manager shows it OK, run 'Restart-Service JTAGServer -Force' from an Administrator PowerShell."

# ---------------------------------------------------------------- 4. stage
echo "=== 4. stage repo -> \$MY_K5_PROJ ==="
"$REPO/bench/stage.sh" 2>&1 | sed 's/^/  /' || die "staging failed"
cp "$SOF" "$FPGA_PROG_FILES/" || die "could not place the .sof"
cp "$SVH" "$K5_SW_APPS/$XLR/" || die "could not place the .svh"
# Board files are parsed by load_hex_file; CRLF breaks it silently.
for f in "$K5_SW_APPS/sud_shared"/sudoku_input_*.txt; do
  if grep -q $'\r' "$f" 2>/dev/null; then warn "$(basename "$f") contains CR - load_hex_file expects LF"; fi
done

# ---------------------------------------------------------------- 5. program
echo "=== 5. program ==="
( set_k5_terminal; prog_fpga "$XLR" ) > "$OUT/prog.txt" 2>&1
grep -q "Quartus Prime Programmer was successful" "$OUT/prog.txt" \
  || { tail -20 "$OUT/prog.txt"; die "programming failed - see $OUT/prog.txt"; }
grep -oE "Using programming file .* with checksum 0x[0-9A-F]+" "$OUT/prog.txt" | sed 's/^/  /'
echo "  programmed. The 7-seg should read 'Hi ddP'."

# ---------------------------------------------------------------- 6. run
echo "=== 6. run ==="
FAIL=0
: > "$OUT/cycles.txt"
IFS=',' read -ra BLIST <<< "$BOARDS"
for B in "${BLIST[@]}"; do
  S=$(date +%s)
  ( set_k5_terminal; launch_k5_app "$XLR" -asl sud_shared -gpv "$B" ) > "$OUT/hw_$B.txt" 2>&1
  printf -- "--- %-9s (%ss wall)\n" "$B" "$(( $(date +%s) - S ))"
  SOLVE=$(grep -oE 'Sudoku solve[ ]+[0-9,]+' "$OUT/hw_$B.txt" | grep -oE '[0-9,]+$')
  SETUP=$(grep -oE 'Board setup\+load[ ]+[0-9,]+' "$OUT/hw_$B.txt" | grep -oE '[0-9,]+$')
  if [ -z "$SOLVE" ]; then echo "    FAIL: no cycle count - the app did not finish"; FAIL=1; continue; fi
  echo "    setup+load $SETUP   solve $SOLVE"

  # correctness: our golden gate AND the app's own checker must agree
  GATE=PASS
  python "$REPO/bench/solve_ref.py" --check "$B" "$OUT/hw_$B.txt" > "$OUT/gate_$B.txt" 2>&1 || GATE=FAIL
  sed 's/^/    /' "$OUT/gate_$B.txt"
  APP=$(grep -oE "Solved board (PASSED|FAILED)" "$OUT/hw_$B.txt" | tail -1)
  case "$APP" in *PASSED*) APPV=PASS ;; *FAILED*) APPV=FAIL ;; *) APPV=ABSENT ;; esac
  echo "    app checker: $APPV"
  [ "$GATE" = FAIL ] && FAIL=1
  [ "$APPV" = FAIL ] && FAIL=1
  # The two gates disagreeing is worse than either failing: one of them is lying.
  if [ "$GATE" != "$APPV" ] && [ "$APPV" != ABSENT ]; then
    warn "$B: our gate says $GATE but the app checker says $APPV - they cannot both be right"
    FAIL=1
  fi
  # Reported Solved but failed the checker is the week-3 store-bug signature.
  if [ "$APPV" = FAIL ] && grep -q "Solved ===" "$OUT/hw_$B.txt"; then
    warn "$B: reported Solved but FAILED the checker. Run: python bench/diagnose.py $B $OUT/hw_$B.txt"
  fi

  # cycles must match what the cloud simulated, exactly. Rounding is not a thing here.
  EXP=$(grep -A2 'expected solve cycles' "$DL/NOTES.txt" | grep -oE "$B [0-9,]+" | head -1 | awk '{print $2}')
  if [ -n "$EXP" ]; then
    if [ "$EXP" = "$SOLVE" ]; then
      echo "    vs sim: MATCH ($EXP)"
    else
      warn "$B: hardware $SOLVE vs simulated $EXP. Sim and fabric ran different designs - investigate before recording anything."
      FAIL=1
    fi
  elif [ "$B" = hard1 ]; then
    echo "    vs sim: n/a - hard1 is never simulated"
  fi
  echo "$B $SETUP $SOLVE $GATE $APPV" >> "$OUT/cycles.txt"
done

# ---------------------------------------------------------------- 7. invariants
echo "=== 7. invariants ==="
# setup+load is a fixed 32+32+17 burst cost. It must not depend on the puzzle, and it
# must not move between tags unless the LOAD path was deliberately changed.
SETUPS=$(awk '{print $2}' "$OUT/cycles.txt" | sort -u | tr '\n' ' ')
if [ "$(echo $SETUPS | wc -w)" -le 1 ]; then
  echo "  setup+load constant at $SETUPS - as designed"
else
  warn "setup+load varies across boards ($SETUPS). It is a fixed burst cost; something now depends on the data."
fi

# The classic silent failure: the board was never actually reprogrammed, so the OLD
# design answers and the tag looks like it changed nothing. Identical cycles across two
# different tags is the signature.
PREV=$(ls -1d "$REPO"/logs/*/hw 2>/dev/null | grep -v "/$TAG/hw\$" | tail -1)
if [ -n "$PREV" ] && [ -f "$PREV/cycles.txt" ]; then
  if cmp -s <(awk '{print $1,$3}' "$PREV/cycles.txt") <(awk '{print $1,$3}' "$OUT/cycles.txt"); then
    warn "every cycle count is identical to $(basename "$PREV"). Either this tag changed nothing, or the board is still running the previous bitstream."
  fi
fi

# ---------------------------------------------------------------- 8. score
echo "=== 8. score ==="
FMAX=$(grep -m1 '^standalone:' "$DL/NOTES.txt" | sed 's/.*F_max *//' | grep -oE '[0-9.]+' | head -1)
H=$(awk '$1=="hard1"{print $3}' "$OUT/cycles.txt" | tr -d ,)
SCORE=""
if [ -n "$FMAX" ] && [ -n "$H" ]; then
  SCORE=$(python -c "print('%.4f' % ($H/$FMAX/1e6))")
  US=$(python -c "print(format($H/$FMAX, ',.0f'))")
  echo "  hard1 $H cycles / $FMAX MHz (standalone) = $US us = $SCORE s"
else
  warn "cannot compute the score: F_max='$FMAX' hard1='$H'"
fi

{
  echo "## HW RESULT $TAG $(date '+%F')"
  echo
  echo "release     : $TAG   commit $SHA"
  echo "sof_md5     : $(md5sum "$SOF" | cut -d' ' -f1)"
  echo "enums_md5   : $(md5sum "$SVH" | cut -d' ' -f1)"
  echo "gate        : git diff --quiet $SHA -- sw/apps hw/xlrs  ->  clean"
  echo
  printf "%-10s %12s %14s %6s %6s\n" board setup solve gate app
  awk '{printf "%-10s %12s %14s %6s %6s\n",$1,$2,$3,$4,$5}' "$OUT/cycles.txt"
  echo
  [ -n "$SCORE" ] && echo "solve time  : $H / $FMAX MHz = $SCORE s      <- THE SCORE"
  echo "warnings    : $WARN"
  [ "$WARN" -gt 0 ] && sed 's/^/  /' "$OUT/warnings.txt"
  echo
  echo "insight     : <-- fill this in by hand. The numbers do not say why."
} > "$OUT/HW_RESULT.txt"

echo
echo "=============================================================="
sed 's/^/  /' "$OUT/HW_RESULT.txt"
echo "=============================================================="
echo "wrote $OUT/  (the .gitignore keeps the text, drops binaries)"
echo
if [ "$FAIL" != 0 ]; then
  echo "RESULT: FAILED. Do not record this as a measurement."
  exit 1
fi
echo "RESULT: PASS with $WARN warning(s)."
echo "Next, by hand: the DIARY entry, the RESULTS.md row, then commit. Not me."
