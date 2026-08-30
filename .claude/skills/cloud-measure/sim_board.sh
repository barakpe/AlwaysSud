#!/bin/bash
# Run ONE board in RTL simulation. Usage: sim_board.sh <board> <outdir>
#
# The two processes are cooperating peers, not parent/child:
#   launch_k5_app  is the SERVER  (binds a $USER-hashed TCP port on localhost)
#   launch_k5_sim  is the CLIENT  (xrun/xmsim connects to that port)
# Either may start first; each waits for the other. Only ONE pair can run at a
# time, because the port is derived from the username.
#
# NEVER run hard1 here - ~30 h of RTL simulation. Hardware only.
BOARD="$1"; OUT="$2"                       # capture BEFORE sourcing (see k5_env.sh)
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/k5_env.sh"

[ -n "$BOARD" ] && [ -n "$OUT" ] || { echo "usage: sim_board.sh <board> <outdir>"; exit 2; }
[ "$BOARD" = "hard1" ] && { echo "REFUSING: hard1 cannot be simulated (~30 h). Hardware only."; exit 2; }
mkdir -p "$OUT"; cd "$MY_K5_PROJ/sim" || exit 2     # == what set_k5_terminal does

# A leftover simulator from a previous board owns the port and will corrupt this run.
if pgrep -u "$USER" -x xmsim >/dev/null; then
  echo "FAIL: a stale xmsim is still running - refusing to start $BOARD"
  pgrep -u "$USER" -x xmsim -a
  exit 3
fi

echo "--- $BOARD --- $(date +%T)"
launch_k5_sim alwaysud > "$OUT/sim_${BOARD}.sim.txt" 2>&1 &   # NB: shell function,
SIM=$!                                                        # so `setsid`/`timeout`
                                                              # CANNOT wrap it.
sleep 5
launch_k5_app alwaysud -asl sud_shared -gpv "$BOARD" > "$OUT/sim_${BOARD}.txt" 2>&1
echo "  app exited rc=$? at $(date +%T)"

# OBSERVED 2026-08-26: a simulator that never got a connection (because a second one
# was alive) spins at ~90% CPU forever. With one-at-a-time discipline all runs exited
# via $finish, but enforce the teardown anyway - a wedged xmsim poisons the next board.
for i in $(seq 1 24); do kill -0 $SIM 2>/dev/null || break; sleep 5; done
if kill -0 $SIM 2>/dev/null; then
  echo "  WARNING: simulator did not exit within 120 s - killing it"
  pkill -u "$USER" -x xmsim; sleep 3; pkill -9 -u "$USER" -x xmsim
  kill -9 $SIM 2>/dev/null
fi
wait $SIM 2>/dev/null
pgrep -u "$USER" -x xmsim >/dev/null && { echo "  FAIL: xmsim still alive"; exit 3; }

grep -E "Sudoku solve" "$OUT/sim_${BOARD}.txt" || { echo "  FAIL: no cycle count in output"; exit 4; }
