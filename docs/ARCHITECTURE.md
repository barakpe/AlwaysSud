# Architecture

## Now (v0, inherited from ex3.1)

Two host-register commands. `SETUP` hands over the xmem address and the accelerator
pulls 81 bytes in three bursts (32+32+17), packing one cell per nibble. `SOLVE` runs
the entire backtracking search in hardware; when it finishes, `STORE` writes the
solved board back to xmem through `mem_intf_write` and the driver's single polling
read collects the result.

That is two boundary crossings for a whole puzzle, against 37,652 in the week-2
design. The cycle count therefore measures the **search**, not the interface.

## The solver core

`alwaysud_solver.sv` is a faithful state-machine translation of the C solver, which means
it inherits C's sequential shape:

| state | per cycle | cycles per use |
|-------|-----------|----------------|
| `FIND_EMPTY` | advances **one cell** | 1-81 |
| `TRY_VAL` | tests **one digit** | 1-9 |
| `BACKTRACK` | pops one frame | 1 |

A processor tests nine digits one at a time because it has one ALU. Hardware has no
such excuse: the nine checks are independent, and "first empty cell" is a priority
encoder rather than an 81-cycle walk. That gap is the optimisation budget.

## Where it is going

**Candidate masks are the keystone.** A 9-bit mask per cell (81 x 9 = 729 flops)
turns "is digit d legal at cell c?" from 27 comparisons into a bit lookup. Once masks
exist, parallel digit evaluation is free, naked singles are "mask has one bit" tested
on all 81 cells at once, and MRV is 81 popcounts of 9 bits instead of
81 x 9 x 27 = 19,683 comparators. Without masks, MRV is unbuildable.

Ladder: `v1 fastfind` -> `v2 masks` -> `v3 singles` -> `v4 mrv` -> `v5 clock`.

## Two traps to settle before v2

**Packed vs unpacked decides flops vs RAM.** The reference declares `grid` and
`stack` as unpacked arrays; Quartus may infer block RAM. RAM has two ports - fine for
a stack touched one entry at a time, **fatal** for a grid or mask array that must be
read 81-at-once. Anything read in parallel must be packed. If memory bits jump after
v2, that is what happened and the design has silently serialised.

**Mask restore on backtrack.** A full snapshot per stack level is 729 x 81 ~ 59,000
bits - too much for flops. Store the *delta* instead: placing digit d at cell c clears
bit d in at most 20 peers, so push `{cell, digit, 20-bit which-peers-changed}` ~ 28
bits per level, ~2,268 bits total. Unwinding is re-setting bit d in the recorded
peers. Get this right on paper before writing the RTL.
