#!/usr/bin/env bash
# Copy the repo's hw/ and sw/ into the K5 build tree.
# Repo is the truth; $MY_K5_PROJ is generated and disposable.
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)

[ -n "${MY_K5_PROJ:-}" ] || { echo "MY_K5_PROJ not set - run set_k5_terminal / source the env first"; exit 1; }

echo "staging $REPO -> $MY_K5_PROJ"
# delete first: cp -r MERGES, so a stale file from a previous variant would survive
rm -rf "$MY_K5_PROJ/hw/xlrs/alwaysud"
cp -r "$REPO/hw/xlrs/alwaysud"      "$MY_K5_PROJ/hw/xlrs/"
cp -r "$REPO/sw/apps/alwaysud"      "$MY_K5_PROJ/sw/apps/"
cp -r "$REPO/sw/apps/sud_shared" "$MY_K5_PROJ/sw/apps/"

echo "staged:"
ls -1 "$MY_K5_PROJ/hw/xlrs/alwaysud"
md5sum "$MY_K5_PROJ/sw/apps/alwaysud/alwaysud_enums.svh" 2>/dev/null || md5 "$MY_K5_PROJ/sw/apps/alwaysud/alwaysud_enums.svh"
