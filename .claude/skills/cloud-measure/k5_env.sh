#!/bin/bash
# Source this FIRST in any script that needs the K5 toolchain.
#
# WHY THIS FILE EXISTS
# --------------------
# qsyn_xlr, comp_fpga, launch_k5_app, set_k5_terminal and python are ALIASES, and
# launch_k5_sim is a shell FUNCTION. Neither survives into a `#!/usr/bin/env bash`
# script: a plain script sees "command not found" for every one of them. Verified
# 2026-08-26 on the RC cloud.
#
# TRAP: sourcing startProject.bash OVERWRITES the caller's positional parameters
# ("$1" becomes a prompt string). Capture your own args BEFORE sourcing this.
shopt -s expand_aliases
source ~/.bashrc                                        >/dev/null 2>&1
source /apps/common/bin/startProject.bash tsmc65        >/dev/null 2>&1
export ws="/data/project/tsmc65/users/$USER/ws"

# prog_fpga does NOT exist on the cloud - it is a laptop-only command.
