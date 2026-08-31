#!/usr/bin/env bash
# Laptop (Windows/git-bash) K5 environment. SOURCE this, never execute it.
#
# Three things bite here and all three are silent:
#   1. Every k5 command is an ALIAS. A plain script sees none of them, and bash does
#      not expand aliases in non-interactive shells unless told to.
#   2. setup_win.sh needs K5X_ROOT preset, and prints a misleading error without it.
#   3. $HOME in git-bash is C:\SPB_Data, NOT C:\Users\barak. ~/Downloads is wrong.
shopt -s expand_aliases

export K5X_ROOT="${K5X_ROOT:-/c/Users/barak/k5x_win}"
[ -d "$K5X_ROOT/k5_xbox_fpga_win" ] || { echo "FAIL: no k5_xbox_fpga_win under K5X_ROOT=$K5X_ROOT"; return 1 2>/dev/null || exit 1; }

source "$K5X_ROOT/k5_xbox_fpga_win/setup/setup_win.sh" >/dev/null 2>&1

# jtagconfig/quartus_pgm are not on PATH by default.
export PATH="/c/altera/24.1std/qprogrammer/bin64:$PATH"

# `gh release view --json` panics on this laptop: go-keyring reads the Windows
# credential store from a worker goroutine and dereferences nil. Passing the token
# explicitly keeps it off that path. `gh auth token` itself works.
[ -z "${GH_TOKEN:-}" ] && export GH_TOKEN="$(gh auth token 2>/dev/null)"

for v in MY_K5_PROJ K5_SW_APPS FPGA_PROG_FILES; do
  [ -n "${!v}" ] || { echo "FAIL: $v unset after sourcing setup_win.sh"; return 1 2>/dev/null || exit 1; }
done
