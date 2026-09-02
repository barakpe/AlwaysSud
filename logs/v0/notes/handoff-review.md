# Handoff-by-release — session report

**Date:** 2026-08-30 · **Commit:** `74e1b12` · Nothing committed, nothing pushed.

---

## TASK 1 — publish the v0 release

### VERDICT: **published and externally verified.**

<https://github.com/barakpe/AlwaysSud/releases/tag/v0> — `k5_xbox_alwaysud.sof`
(3,216,564 bytes) and `alwaysud_enums.svh` (313 bytes), one release, notes as below.

Verified independently of the script that created it: fresh `gh release download` into a
scratch dir, notes fetched from the API, both md5s matched what the notes claim, both
assets byte-identical to the originals on disk, and the notes' commit confirmed an
ancestor of HEAD (the laptop's check). Re-running the publisher against the existing tag
updated it in place — still one release, one copy of each asset. No `.sof` anywhere in
git history.

It was blocked earlier in the session; the record of that is below, because the blocker
will recur on any fresh machine.

**Resolved during the session:** `gh` 2.98.0 is now installed at `~/.local/bin/gh`
(user-local, checksum-verified, no root), and Barak authenticated as `barakpe` with
`repo` scope. What follows is what the blocker looked like, since a fresh cloud instance
will have neither.

`gh` was not installed on the RC cloud image, and there was no GitHub credential of any
kind on this machine. Creating a release requires authentication, so installing `gh`
would not have helped either. Evidence, in the order I checked:

```
$ which gh
/usr/bin/which: no gh in (…full PATH…)          # not in PATH, not under /tools or /apps,
                                                # no gh module

$ git config --get credential.helper            # (nothing)
  absent: ~/.git-credentials
  absent: ~/.config/gh/hosts.yml
  absent: ~/.netrc
  GITHUB_TOKEN unset · GH_TOKEN unset · GITHUB_PAT unset

$ curl -s -o /dev/null -w '%{http_code}' https://api.github.com/repos/barakpe/AlwaysSud
200                                             # network egress is fine

$ curl -X POST https://api.github.com/repos/barakpe/AlwaysSud/releases -d '{"tag_name":"__probe__"}'
401  {"message":"Requires authentication"}      # this is the whole blocker

$ curl -s https://api.github.com/repos/barakpe/AlwaysSud/releases
[]                                              # no releases exist yet
```

So: the network path works, the repo is reachable, and the only missing piece is a token.
I did not try to obtain one, and I did not fall back to `git push` — that writes history,
which is yours.

**Everything else in Task 1 is done**, and the release is one command away.

### Verified, ready to publish

| field | value | how confirmed |
|---|---|---|
| `commit` | `74e1b1279b9cb2d6429030c2434b31e780abc84c` | see note below |
| `enums_md5` | `991ee6d38809bb0b6997e50ae81709f8` | `md5sum` of the staged `.svh`, byte-identical to the repo copy |
| `sof_md5` | `ac57a19c42e404ff14d87f45d65928bf` | `md5sum` of the 3,216,564-byte `.sof` built at 21:08 |
| easy1 / 20blanks / 51blanks | **283 / 403 / 56,803** solve cycles | re-read from `logs/v0_verified/sim_*.txt`, not from the summary |
| setup+load | **235** | identical on all three boards, as it should be |
| standalone | LEs **9,286** · registers **1,867** · F_max **87.02 MHz** | `logs/v0_verified/qsyn.txt` |
| system | LEs **20,560** · F_max **55.29 MHz** · memory bits **79%** | `logs/v0_verified/comp_fpga.txt` |

Your quoted cycle figures were right; I confirmed all four against the logs before using them.

**On the commit SHA.** `comp_fpga` ran while HEAD was `5c71b72`; HEAD is now `74e1b12`.
I checked that `hw/` and `sw/` are byte-identical at both, and that all nine source files
in `$MY_K5_PROJ` still md5-match the repo — so the bitstream genuinely corresponds to
`74e1b12`'s sources. Publishing HEAD also makes the laptop's
`git merge-base --is-ancestor` check trivially satisfiable. If you would rather record the
commit the build literally ran at, use `5c71b72`; both are honest, and both pass.

### To publish it

```bash
cd $ws/AlwaysSud
.claude/skills/cloud-measure/publish_release.sh v0 \
    logs/v0_verified/HANDOFF.txt \
    $MY_K5_PROJ/hw/gen_fpga/prog_files/k5_xbox_alwaysud.sof \
    $K5_SW_APPS/alwaysud/alwaysud_enums.svh
```

It re-checks both md5s against the notes, creates or updates the release, then
re-downloads both assets and re-verifies them. If it cannot authenticate it exits
non-zero and prints the manual `gh` commands.

**The `.sof` is not in the repo and was never staged** — 3.07 MB of already-compressed
build output, permanent in history, no delta compression.

### HANDOFF.txt fixed

`logs/v0_verified/HANDOFF.txt` said `system F_max (not built) MHz  memory bits (not built)`
for a build that had in fact succeeded. Two causes, both now fixed in the skill:

1. The handoff block was emitted **unconditionally**, using `SYS_*="(not built)"` defaults
   that only got overwritten inside the `--with-fpga` branch. My run of `comp_fpga` was a
   separate invocation, so the block never saw its numbers.
2. The parser was `grep 'Total FPGA Logic Elements' | tr -dc '0-9'`. `comp_fpga` writes
   `Total FPGA Logic Elements (out of about 50K available):   20,560`, so stripping
   non-digits across the whole line gives **5020560**, and the memory-bits line gives
   **9618%**. I hit exactly this while regenerating the file and caught it only because I
   printed the result before trusting it.

The file is now regenerated from the logs, in the `docs/HANDOFF.md` notes format, and
every number matches the report.

---

## TASK 2 — what changed in the skill

New file **`publish_release.sh`**; `measure_cloud.sh` steps 4/6/7 rewritten and a step 8
added; `sim_board.sh` and `SKILL.md` touched.

| change | why |
|---|---|
| step 8 publishes the release | only when the gate passed **and** `comp_fpga` succeeded; otherwise it says so and does nothing |
| notes generated from measured values | `HANDOFF.txt` **is** the release notes, byte for byte. No number is templated in |
| `system: NOT BUILT` when no bitstream | replaces the silent `(not built)` default, and the publisher refuses such notes |
| after-colon parsing | kills the `5020560` / `9618%` class of bug |
| gate output saved to `gate.txt` | there was no on-disk record that the gate had passed |
| update in place, never delete | `upload --clobber` + `edit --notes-file`; deleting breaks a laptop mid-download and kills the old asset URLs |
| external verification | re-downloads both assets and re-checks md5s after publishing |
| loud failure | `gh` missing or unauthenticated ⇒ non-zero exit plus the exact manual commands |
| absolute paths before sourcing | see below |

**Four refusal guards, each tested for real rather than assumed:**

```
notes sof_md5 != actual .sof     -> PUBLISH FAILED …but the file is ac57a19c…   rc=1
notes say system: NOT BUILT      -> PUBLISH FAILED …do not publish a stage…     rc=1
notes enums_md5 != actual .svh   -> PUBLISH FAILED …but the file is 991ee6d3…   rc=1
missing asset                    -> PUBLISH FAILED missing /nonexistent.sof     rc=1
gh absent                        -> PUBLISH FAILED …+ manual fallback printed   rc=1
```

**A bug I hit while building this, now fixed and documented:** sourcing the project setup
does not only clobber `"$@"` — it also **changes the working directory** to `$ws`. So a
relative path passed as an argument silently resolves against the wrong directory. My first
real invocation died with `missing logs/v0_verified/HANDOFF.txt` for a file that plainly
existed. Path arguments are now made absolute with `readlink -m` *before* sourcing, in both
`publish_release.sh` and `sim_board.sh`.

### On the one write to GitHub

You asked me to say so if the distinction seemed wrong. **It doesn't — but it is narrower
than "not committing".** A release creates a release object *and a tag ref* on the remote.
It writes no history and no commit, and `git commit` / `push` / `tag` stay yours. But it is
a real, externally visible write that others can fetch and that is not cleanly undoable, so
I gave it the same treatment as a commit: it happens only on a fully passing run, it is
idempotent per tag, and the tag is an explicit argument the skill never infers. I'm
comfortable with that; I'd be uncomfortable if it also moved `main` or created a git tag
you hadn't chosen, and it does neither.

---

## TASK 3 — what I would change

### a. The release-notes format

It is close. Five things I would change before iteration ten:

1. **Add `sof_bytes:`.** md5 catches corruption but you only learn that after a 3 MB
   download. A size line lets the laptop reject a truncated fetch immediately, and
   distinguishes "download broke" from "wrong bitstream".
2. **Add `built_at:`** (ISO-8601 UTC). The laptop gotchas list already says to check the
   `.sof` timestamp is newer than the last one programmed — but a release asset's
   timestamp is its *upload* time, not its build time. Without this the check is unreliable
   on a re-published tag.
3. **Make the parsed fields machine-parseable and put the prose elsewhere.** Right now
   `enums_md5:` is greppable but the cycles live inside an indented free-text block that
   a laptop script has to parse positionally. If the laptop is going to parse this, give it
   `cycles_easy1: 283` / `cycles_20blanks: 403` / `cycles_51blanks: 56803` as flat keys —
   and note the comma in `56,803` will bite any naive `int()`. Keep the explanatory prose
   below a `---` the parser ignores.
4. **`enums_md5` is the only contract file covered, and the contract is wider than that.**
   `alwaysud.h` carries the `start_reg_t` / `done_reg_t` bitfields that must match the
   SystemVerilog structs, and it is *not* in the release. A stale `alwaysud.h` fails
   exactly the way a stale `.svh` does. Either attach it too, or add
   `sw_md5: <md5 of alwaysud.c + .h + _enums.svh concatenated>`. Today `alwaysud.h`
   travels only by `git pull`, which is the discipline problem this design exists to remove.
5. **Drop `registers` from the notes, or add memory bits to `standalone:`.** The laptop
   cannot act on the register count, and the standalone line omits the one resource figure
   that has ever been near a limit. Asymmetric for no reason.

One thing that is **right** and worth keeping: mandating that the cycles are the
solve-window numbers, in the notes themselves. That ambiguity is live right now —
`report_total_performance()` prints 518/638/57,038 and the pre-split numbers were
363/483/56,883, so there are three plausible triples for the same run.

### b. Console logs: assets, or committed?

**Make them release assets, not commits — one small tarball per release.**

You are right that the current state is incoherent: `.gitignore` excludes `logs/**/*.txt`
except `HANDOFF.txt`, so the raw simulation output is versioned nowhere, while
`README.md` and `docs/MEASUREMENT.md` both still promise that `logs/<tag>/` holds raw run
output as evidence. Three of us made that inconsistent across two sessions — me included.

Why assets rather than commits:

- They are **tool output**: regenerable, never diffed, never merged. Git gives you history
  and blame for them and you want neither.
- They are already **bound to the thing they describe**. The whole argument for the release
  is atomic binding; logs describing a bitstream belong with that bitstream.
- They **cost nothing in the clone**, and after ten iterations that matters: ~50 KB of
  console output per stage is trivial as an asset and permanent noise in history.
- Deleting a superseded stage's logs becomes possible. In git it never is.

Concretely: `tar czf logs-<tag>.tgz` over `qsyn.txt comp_fpga.txt gate.txt cycles.txt
sim_*.txt`, attach as a third asset. Keep `REPORT.md` and `HANDOFF.txt` committed — those
are hand-written and get read by humans.

Then fix the docs, because the promise is currently false either way: `README.md`'s
"`logs/<tag>/` raw run output, kept as evidence" and `docs/MEASUREMENT.md`'s
"save logs under `logs/<tag>/`" should say the raw output ships with the release.

I did **not** make this change — it is a policy decision about your repo, and you asked
me to pick one, not to implement it.

### c. What breaks on the tenth iteration, not the first

1. **Nothing enforces that the release matches the working tree.** `publish_release.sh`
   checks the notes against the files, but `measure_cloud.sh` writes `commit: $(git rev-parse HEAD)`
   with no check that `hw/` and `sw/` are clean. On iteration ten you will publish from a
   dirty tree, the notes will name a commit whose RTL is not what was built, and the
   laptop's ancestor check will pass anyway. **Fix: refuse to publish if
   `git status --porcelain hw/ sw/` is non-empty.** I verified this by hand for v0; the
   skill should not rely on me doing that.
2. **The tag is free-form, so `v1-mrv` and `v1_mrv` will both get created eventually**, and
   nothing will notice. A pattern check, or a list of known stage names, costs one line.
3. **A re-published tag silently changes what a laptop already downloaded.** `--clobber`
   is the right call over delete-and-recreate, but a laptop that fetched `v1-mrv` yesterday
   has no way to know today's `v1-mrv` is different. The `built_at:` field in (a2) is the
   minimum fix; better is never reusing a tag for a different bitstream and going
   `v1-mrv.2`. My worry is the tenth iteration is exactly when you re-measure an old stage.
4. **`prog_files/` accumulates.** It already holds a stale `k5_xbox_sudx_basic.svf` from
   25 August, and `comp_fpga` only removes `k5_xbox_<top>.sof` for the current top. Ten
   stages of `.sof` + `.svf` is ~55 MB of look-alike files on the Desktop link, and the
   laptop half is a manual `cp`. The release makes the *download* safe; it does nothing
   about picking the wrong local file afterwards.
5. **`enums_md5` will be identical across most stages**, because the register contract
   rarely changes. So the check that is supposed to catch staleness will pass trivially
   nine times out of ten and give false confidence — right up to the stage that adds the
   placement/backtrack counters, where it is the only thing standing between you and a
   silent runtime misbehaviour. It is doing real work only on the rare stage; that is worth
   knowing, not fixing.
6. **The `.svh` is published from `$MY_K5_PROJ`, not from the repo.** They are identical
   today (I checked), but `$MY_K5_PROJ` is the *staged* copy, and staging is what would be
   stale if a run were interrupted between `stage.sh` and `comp_fpga`. Publishing the repo
   copy while building from the staged copy would be worse. **The right fix is to assert
   they are identical at publish time** — one `cmp`, currently absent.
