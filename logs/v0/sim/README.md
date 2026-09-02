# Empty, and that is the point

The cloud simulation console output for v0 was never committed: the `.gitignore` in force
at the time excluded `logs/**/*.txt`. The numbers survived only because an agent had
transcribed them into a write-up.

That is why the rule was inverted on 2026-08-31 — every text file under `logs/` is now
kept, binaries never are. From v1 onward `sim/` holds the raw `sim_<board>.txt` and the
archived Quartus reports.
