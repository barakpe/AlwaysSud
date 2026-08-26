# State

**Read this first.** Updated at the end of every working session.

**Last updated:** 2026-08-26

## Right now

| | |
|---|---|
| Current tag on `main` | *(none yet - v0 not measured)* |
| Branch in flight | *(none)* |
| Next action | **Measure the v0 baseline** - see below |
| Best `hard1` result | *(none yet)* |

## What has happened

Step 0 is done: the repo exists, `hw/xlrs/alwaysud/` holds ex3.1's `sudx_scan` ported
under our name, the golden solutions are generated and verified, and the
measurement protocol is written.

**Nothing has been optimised yet, and nothing has been measured yet.**

## The immediate next step

Measure v0, by hand, following `docs/MEASUREMENT.md`:

1. On the cloud: `bench/stage.sh` then `bench/measure_sim.sh v0`
2. On the cloud: `comp_fpga alwaysud` to build the bitstream
3. On the laptop: fetch the bitstream + app sources, then `bench/measure_hw.sh v0`
   - **including `hard1`**, which is the score and cannot be simulated
4. Fill in `RESULTS.md` row 1 and `DIARY.md` entry 1, then `git tag v0`

Do it by hand this first time. The harness scripts are a first cut written from
the plan, not from experience - the manual pass is what tells us where they are
wrong.

## The ladder after that

`v1 fastfind` -> `v2 masks` -> `v3 singles` -> `v4 mrv` -> `v5 clock`.
Masks are the keystone: they make v3 and v4 cheap and subsume "parallel TRY_VAL".
Rationale and estimates: the roadmap artifact, and `docs/ARCHITECTURE.md`.
