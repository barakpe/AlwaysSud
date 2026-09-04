# The solver — v0, chronological backtracking

**This document describes the solver as it is now, and is rewritten whenever the
algorithm changes.** Previous versions are in git; what changed and why is in
`logs/<tag>/REPORT.md` and `DIARY.md`.

Everything outside `alwaysud_solver.sv` — the wrapper, the registers, the memory
protocol — is in `ARCHITECTURE.md` and does not change between versions.

---

## The interface (this part does not change)

```systemverilog
module alwaysud_solver (
    input  logic clk, rst_n,
    input  logic [8:0][8:0][3:0] puzzle_in,
    input  logic start,
    output logic done, success,
    output logic [8:0][8:0][3:0] solved_puzzle
);
```

`start` is a one-cycle pulse. The solver latches `puzzle_in`, runs, and holds `done`
high with `success` valid until reset. 0 means empty; 1–9 are digits.

Any replacement solver keeps these ports. `claude_mrv` adds `busy`, which is the only
plumbing difference if we ever swap it in.

## State it keeps

| | size | what |
|---|---|---|
| `grid[0:8][0:8]` | 81 × 4 bits | the board, updated in place |
| `row`, `col` | 4 bits each | where the scan is |
| `val` | 4 bits | the digit being tried |
| `stack[0:80]` | 81 × 12 bits | `{row, col, val}` per placement |
| `sp` | 7 bits | stack pointer |

All flip-flops — v0 synthesises to **0 memory bits**.

## The FSM

| state | does | cycles |
|---|---|---|
| `IDLE` | wait for `start` | — |
| `INIT` | copy `puzzle_in` into `grid`, reset pointers | 1 |
| `FIND_EMPTY` | walk row-major to the next empty cell, **one cell per cycle** | 1–81 |
| `TRY_VAL` | test one digit, **one digit per cycle**; if it fits, place and push | 1–9 |
| `BACKTRACK` | pop, resume that cell from `val + 1` | 1 |
| `DONE_SUCCESS` / `DONE_FAIL` | raise `done` | 1 |

```
FIND_EMPTY --empty--> TRY_VAL --fits--> place, push --> FIND_EMPTY
     |                    |
   past (8,8)          val > 9 --> clear cell --> BACKTRACK --> TRY_VAL
     v                                                |
 DONE_SUCCESS                                     sp == 0 --> DONE_FAIL
```

## How legality is decided

`is_valid(r, c, v)` — combinational, one cycle. Scans the cell's row, its column and
its 3×3 box for `v`: 27 four-bit comparisons feeding one AND tree. This is the critical
path.

**The geometry is hardcoded here.** That is `BACKLOG.md` item 1 and the top risk in
`STATE.md`: a hackathon variant changes which cells constrain which, and this function
would have to be rewritten rather than reconfigured.

## Cost model

**One clock cycle buys one digit trial, or one cell of scanning.** That is the whole
model, and it is what makes hard1 cost 128,760,739 cycles.

| board | solve cycles |
|---|---|
| easy1 | 283 |
| 20blanks | 403 |
| 51blanks | 56,803 |
| hard1 | 128,760,739 |

A validated C model of this FSM lives in `logs/v0/models/v0hard.c` — it predicted hard1
to +186 cycles, so a change's hard1 cost can be estimated without a 30-hour simulation.

## Traps in this code

- **`grid[row][col] <= 0` before `BACKTRACK`.** Without it the failed cell keeps a stale
  digit, and on the way back down `FIND_EMPTY` reads it as filled and walks past it.
  Silently wrong answer.
- **`START` is declared in the state enum and never used.** It also differs from the port
  `start` only in case; Quartus removes it.
- **`sudx_cmd == STORE` in the wrapper is dead.** Software never sends that command —
  `STORE` is entered from `SOLVE` on `solver_done`.

