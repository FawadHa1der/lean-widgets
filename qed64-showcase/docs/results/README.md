# docs/results — curated run records

Copies of the lane RESULTS documents that live under `out/` on the machine that ran them (`out/` itself is
machine-local and never committed: bakes, overlays, run directories, screenshots). The path under `docs/results/`
is the path under `out/`, so a reference to `out/ux/pin-e/RESULTS.md` in README.md or docs/ is
`docs/results/ux/pin-e/RESULTS.md` in a clone.

These are historical evidence: they quote the absolute paths, logs and run names of the machine that produced them
(`$W` = the work dir, `work/logs/…`). They are records, not instructions; `scripts/check-portable.mjs` allows machine
paths here and nowhere in code or configuration.
