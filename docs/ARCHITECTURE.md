# How it works

## The idea in one paragraph

The RISC-V core cannot solve Sudoku quickly, and it cannot ask the hardware to help
one question at a time either - the round trip costs more than the answer is worth.
So the whole search moves into hardware. Software loads a puzzle into shared memory,
tells the accelerator where it is, says "solve", and waits. The accelerator reads the
board, runs the entire backtracking search itself, writes the answer back, and raises
a done flag. Two commands for a whole puzzle.

## The pieces

| File | What it is |
|---|---|
| `sw/apps/alwaysud/alwaysud.c` | The driver. Loads a puzzle, issues two commands, prints the result. |
| `sw/apps/alwaysud/alwaysud_enums.svh` | The command and register numbering. Included by **both** the C and the SystemVerilog - it is the contract. |
| `hw/xlrs/alwaysud/alwaysud.sv` | The wrapper: talks to the host registers and to shared memory, and owns the outer state machine. |
| `hw/xlrs/alwaysud/alwaysud_solver.sv` | The solver itself. Given a board, produces a solved board. Knows nothing about registers or memory. |
| `hw/xlrs/alwaysud/alwaysud_def_pkg.sv` | A package that just includes the enums file so the hardware can see it. |

The split matters: **the wrapper handles the outside world, the solver handles Sudoku.**
Optimisation work happens almost entirely in `alwaysud_solver.sv`.

## The three registers

Software and hardware talk through three 32-bit registers.

| Register | Direction | Carries |
|---|---|---|
| `XMEM_BOARD_ADDR_RI` | SW writes | where the puzzle sits in shared memory |
| `XLR_START_RI` | SW writes | the command: `SETUP` or `SOLVE` |
| `XLR_DONE_RI` | HW drives | `status` (finished yet?) and `result` (solved?) |

Writing `XLR_START_RI` produces a one-cycle pulse in hardware - that pulse is what
starts things. Reading `XLR_DONE_RI` produces a read pulse, and that is what clears
the done state and returns the machine to idle. The bus access *is* the handshake;
there is no interrupt.

## One solve, start to finish

1. **C:** `load_sud_board()` reads a puzzle file into `board[9][9]` in shared memory.
2. **C:** writes the board's address to `XMEM_BOARD_ADDR_RI`, then `SETUP` to
   `XLR_START_RI`, then polls.
3. **HW, `LOAD`:** reads 81 bytes from memory in three bursts - 32 + 32 + 17, because
   32 bytes is the most the memory interface moves at once and 81 does not divide by
   32. Each byte becomes a 4-bit nibble in an internal board register.
4. **HW, `DONE`:** raises `status`; the C poll sees it and moves on.
5. **C:** writes `SOLVE`, then polls again.
6. **HW, `SOLVE`:** the solver runs. This is where all the time goes.
7. **HW, `STORE`:** writes the solved board back to shared memory, nibbles expanded
   back to bytes.
8. **HW, `DONE`:** raises `status` and `result`. The C poll collects it.
9. **C:** prints the board it can now read back from memory.

## The wrapper's states

| State | Does |
|---|---|
| `IDLE` | waits for a command |
| `LOAD` | pulls the 81 cells in from memory |
| `SOLVE` | starts the solver and waits for its `done` |
| `STORE` | writes the solved board back out |
| `DONE` | reports, waits for the host to read, returns to `IDLE` |

## Inside the solver

The board lives in a register array, one nibble per cell. A stack of at most 81
entries records the choices made so far, so they can be undone.

| State | Does | Cycles |
|---|---|---|
| `INIT` | copies the input board in, resets the pointers | 1 |
| `FIND_EMPTY` | walks forward looking for an empty cell, **one cell per cycle** | 1-81 |
| `TRY_VAL` | tests whether a digit fits, **one digit per cycle**; if it fits, place it and push | 1-9 |
| `BACKTRACK` | pops the last choice and resumes from the next digit | 1 |
| `DONE_SUCCESS` / `DONE_FAIL` | raises `done` | 1 |

Legality is checked by `is_valid(r,c,v)`: a combinational function that scans the
cell's row, its column, and its 3x3 box for the digit `v`. It is one cycle.

## Where the time goes, and why that is the whole project

`is_valid` is one cycle. But the solver only asks it about **one digit at a time**,
and finds empty cells **one per cycle**. That is a direct translation of the C code -
which had to be sequential, because a processor has one ALU.

Hardware does not have that constraint. All nine digits for a cell could be tested in
the same instant. "The first empty cell" is a priority encoder, not an 81-cycle walk.
The gap between what the fabric could do at once and what this design does one step at
a time is the entire optimisation budget.

What we do about that is `STATE.md` and `BACKLOG.md`.
