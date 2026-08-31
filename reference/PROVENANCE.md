# reference/ — what this is, and how it goes wrong

Vendored copies of course code. **Never built, never staged.** Two jobs:

1. `ex3.1/sudx_standalone_ref/claude_mrv/` — the starting point for `v1-mrv`
   (`BACKLOG.md` item 1). The cloud agent clones only this repo, so it needs the
   source here.
2. `ex3.1/my_k5_proj_ref/` — what our accelerator was derived from, so a diff can
   show exactly what we changed.

## Provenance

| what | upstream | commit |
|---|---|---|
| `ex3.1/` | `github.com/DDP26-summer/ex3.1` | `6c0e3e9` *(Added docs/bug_and_checker_fixing.md)* |
| `ex2.1/` | `github.com/DDP26-summer/ex2.1` | *not recorded — vendored before this file existed* |

## The trap this file exists to prevent

**On 2026-08-31 the vendored `ex3.1/my_k5_proj_ref/` was found to be stale**: it
predated upstream `81f7a4d Support Solved Board Checker`, so all four of
`sud_lib.c`, `sud_lib.h`, `sudx_scan.c` and `sudx_scan.sv` differed from what the
course actually ships. `README.md` describes this directory as "for diffing", and
every diff against it was wrong.

That is the same failure that got two bonus candidates rejected: comparing against
our own local copy instead of the artifact **as distributed**. A stale copy is worse
than no copy, because it looks authoritative.

**So: never diff against `reference/` to make a claim about course code.** Diff
against the real clone in `week-N/ex*/`, which git keeps honest. `reference/` is for
the cloud agent, which has no access to those clones.

## Check it before trusting it

```bash
REAL=../../week-3/ex3.1                     # from the repo root
git -C "$REAL" fetch --quiet && git -C "$REAL" status -sb | head -1
diff -r --brief -x '.git*' "$REAL/my_k5_proj_ref" reference/ex3.1/my_k5_proj_ref
```

Silence means fresh. Any output means refresh the copy and update the commit in the
table above, in the same sitting.

## `ex2.1/` is a candidate for deletion

Week 2's `sudx_basic` is a different accelerator. Nothing in this repo references it,
and its provenance was never recorded. Kept for now only because the hackathon variant
is unknown; delete it if it is still unused when the variant lands.
