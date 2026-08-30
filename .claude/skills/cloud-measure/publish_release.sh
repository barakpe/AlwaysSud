#!/bin/bash
# Publish (or update) the cloud->laptop handoff as a GitHub release.
#   publish_release.sh <tag> <notes-file> <sof> <svh>
#
# The release binds k5_xbox_alwaysud.sof and alwaysud_enums.svh together atomically.
# That .svh is included by BOTH the SystemVerilog package and the C driver; a stale one
# against a fresh bitstream compiles clean and misbehaves at runtime. Fetched together,
# that failure is impossible rather than a thing to stay disciplined about.
#
# This is the ONLY write to GitHub the skill performs. It creates no commit, no tag
# object beyond the release's own ref, and never pushes. See SKILL.md.
TAG="$1"; NOTES="$2"; SOF="$3"; SVH="$4"       # capture BEFORE sourcing (k5_env.sh)
# ...and make the paths absolute before sourcing too: startProject.bash cd's to $ws, so a
# relative argument silently resolves against the wrong directory afterwards.
for v in NOTES SOF SVH; do
  [ -n "${!v}" ] && printf -v "$v" '%s' "$(readlink -m -- "${!v}")"
done
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/k5_env.sh"
REPO_SLUG="barakpe/AlwaysSud"

[ -n "$TAG" ] && [ -n "$NOTES" ] && [ -n "$SOF" ] && [ -n "$SVH" ] || {
  echo "usage: publish_release.sh <tag> <notes-file> <sof> <svh>"; exit 2; }

fail() { echo; echo "########## PUBLISH FAILED: $* ##########"; }

manual_fallback() {
cat <<EOF

Publish it by hand from a machine that has an authenticated gh:

  TAG=$TAG
  gh release create "\$TAG" \\
      "$SOF" \\
      "$SVH" \\
      --repo $REPO_SLUG --title "\$TAG" --notes-file "$NOTES"

  # if the release already exists, update in place instead of deleting it:
  gh release upload "\$TAG" "$SOF" "$SVH" --repo $REPO_SLUG --clobber
  gh release edit   "\$TAG" --repo $REPO_SLUG --notes-file "$NOTES"

Then verify from the outside before trusting it:
  gh release download "\$TAG" --repo $REPO_SLUG -D /tmp/verify
  md5sum /tmp/verify/*        # must match sof_md5 / enums_md5 in the notes
EOF
}

#--- preconditions -----------------------------------------------------------
for f in "$NOTES" "$SOF" "$SVH"; do
  [ -f "$f" ] || { fail "missing $f"; exit 1; }
done

# The notes must describe THIS bitstream. If they disagree, something upstream
# regenerated one without the other - refuse rather than publish a lie.
WANT_SOF=$(grep -m1 '^sof_md5:'   "$NOTES" | awk '{print $2}')
WANT_SVH=$(grep -m1 '^enums_md5:' "$NOTES" | awk '{print $2}')
HAVE_SOF=$(md5sum "$SOF" | cut -d' ' -f1)
HAVE_SVH=$(md5sum "$SVH" | cut -d' ' -f1)
[ "$WANT_SOF" = "$HAVE_SOF" ] || { fail "notes say sof_md5=$WANT_SOF but the file is $HAVE_SOF"; exit 1; }
[ "$WANT_SVH" = "$HAVE_SVH" ] || { fail "notes say enums_md5=$WANT_SVH but the file is $HAVE_SVH"; exit 1; }
grep -q 'system: *NOT BUILT' "$NOTES" && { fail "notes say the system was NOT BUILT - do not publish a stage without a bitstream"; exit 1; }

# The notes name a commit. If hw/ or sw/ is dirty, that commit does not describe what was
# actually built, and the laptop's ancestor check will pass anyway and tell it nothing.
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
DIRTY=$(cd "$REPO_DIR" && git status --porcelain hw/ sw/)
[ -z "$DIRTY" ] || { fail "hw/ or sw/ is dirty - the commit in the notes would not describe the bitstream"; echo "$DIRTY"; exit 1; }

# We publish the STAGED .svh (it is what comp_fpga compiled). It must equal the repo copy,
# or the laptop will git pull sources that disagree with the contract file it just fetched.
cmp -s "$SVH" "$REPO_DIR/sw/apps/alwaysud/alwaysud_enums.svh" || {
  fail "the staged .svh differs from the repo copy - staging is stale or the repo moved"; exit 1; }

#--- gh must exist and be authenticated --------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  fail "gh is not installed on this machine"
  echo "  (checked PATH; the RC cloud image does not ship it)"
  manual_fallback; exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  fail "gh is installed but not authenticated for $REPO_SLUG"
  echo "  run: gh auth login    (or set GH_TOKEN to a PAT with 'repo' scope)"
  manual_fallback; exit 1
fi

#--- create, or update in place ----------------------------------------------
if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  echo "release $TAG exists - updating in place (never delete-and-recreate:"
  echo "a laptop mid-download would get a 404, and the old assets' URLs would die)"
  gh release upload "$TAG" "$SOF" "$SVH" --repo "$REPO_SLUG" --clobber || { fail "asset upload"; exit 1; }
  gh release edit   "$TAG" --repo "$REPO_SLUG" --notes-file "$NOTES"   || { fail "notes update"; exit 1; }
else
  echo "creating release $TAG"
  gh release create "$TAG" "$SOF" "$SVH" \
     --repo "$REPO_SLUG" --title "$TAG" --notes-file "$NOTES" || { fail "release create"; exit 1; }
fi

#--- verify from the outside -------------------------------------------------
# A release nobody has re-downloaded is not evidence.
V=$(mktemp -d)
gh release download "$TAG" --repo "$REPO_SLUG" -D "$V" --clobber >/dev/null 2>&1 || { fail "re-download"; rm -rf "$V"; exit 1; }
GOT_SOF=$(md5sum "$V/$(basename "$SOF")" 2>/dev/null | cut -d' ' -f1)
GOT_SVH=$(md5sum "$V/$(basename "$SVH")" 2>/dev/null | cut -d' ' -f1)
rm -rf "$V"
[ "$GOT_SOF" = "$HAVE_SOF" ] || { fail "downloaded .sof md5 $GOT_SOF != $HAVE_SOF"; exit 1; }
[ "$GOT_SVH" = "$HAVE_SVH" ] || { fail "downloaded .svh md5 $GOT_SVH != $HAVE_SVH"; exit 1; }

echo "published and verified: $(gh release view "$TAG" --repo "$REPO_SLUG" --json url -q .url)"
echo "  sof_md5   $HAVE_SOF"
echo "  enums_md5 $HAVE_SVH"
