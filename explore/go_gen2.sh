#!/bin/bash
# More variant puzzles, at nice 19 so the fitter keeps the CPU.
# The classic tail is well sampled (3,191 published hard puzzles); the X-Sudoku
# and Windoku tails were 300 and 150, which is thin for a worst-case claim.
cd /project/tsmc65/users/perezba/ws/AlwaysSudAgent/AlwaysSud || exit 2
nice -n 19 python3 explore/model/gen.py --variant diagonal -n 500 --seed 211 \
     --out explore/puzzles/gen_diagonal_min2.txt
nice -n 19 python3 explore/model/gen.py --variant windoku  -n 350 --seed 311 \
     --out explore/puzzles/gen_windoku_min2.txt
echo GEN2_DONE
