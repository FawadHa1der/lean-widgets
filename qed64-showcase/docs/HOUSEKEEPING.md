# Housekeeping: large artifacts that can be deleted

Written by the final docs lane on 2026-10-02, sizes refreshed on 2026-10-03 (03:51Z, after the v2mit and last-mile
lanes); the boot-fix lane (2026-10-03) moved the v2mit A/B gallery copies from §1 to §3 (they are cited evidence) and
added its own pre-edit copies to §1. **Nothing listed here has been deleted.** Every size is `du -sh` (or `du -sk` summed), logged in
`$W/logs/finaldocs-housekeeping-du.log` and `$W/logs/finaldocs-housekeeping-test-results.log` (the 2026-10-02 figures:
`docsfinal-housekeeping-*.log`). Sizes are **logical**: many of these trees are APFS clones (`cp -c`) that share blocks
with files that stay, so the space actually freed can be smaller. Compare `df -h "$W"` before and
after (445 GiB free on 2026-10-03). `du -sh out/ux`: 58G.

The commands use these variables (the repo path contains a space, so keep the quotes):

```
R="$(git rev-parse --show-toplevel)/qed64-showcase"     # this project (run from inside the repository)
W="$(cd "$R" && bash -c '. scripts/lib/env.sh; echo "$W"')"   # the work dir: QED64_SHOWCASE_WORK (.env.local)
S=<the scratch directory of the lane that made the copies>
```

**Before deleting anything under `out/ux` or `$W`:** no lane may be running. Check that the browser lock is free and no
showcase server or bake runs:

```
test ! -e "$("$R/scripts/with-browser-lock.sh" --print-lock)" && ! pgrep -f 'serve.mjs|bake-snapshot|chrome-headless-shell' && echo idle
```

## 1. Scratch, backups and superseded copies (no tool reads them; no doc cites them as evidence)

| Path | Size | What it is | Command |
|---|---|---|---|
| `$W/pinD-backup/` | 3.2G | Pin D lane's safety copies: `trees/` (APFS clones of C's tree-slim-w7/w8 before restaging; the restaged trees were proven byte-identical), `headless-workdir/` 4.1M, `logs-before-headless/` 1.7M, `logs/` 252K, `files/` 348K (pre-edit script and doc copies) | `rm -rf "$W/pinD-backup"` |
| `$W/deploy-rehearsal/bucket.prev-20261002T091605Z/` | 3.4G | a fake R2 bucket the rehearsal moved aside (pin B era) | `rm -rf "$W/deploy-rehearsal/bucket.prev-20261002T091605Z"` |
| `$W/deploy-rehearsal/bucket.prev-20261002T205606Z/` | 2.3G | the fake bucket moved aside by the final-gate rehearsal | `rm -rf "$W/deploy-rehearsal/bucket.prev-20261002T205606Z"` |
| `$W/deploy-rehearsal/bucket.prev-20261003T104020Z/` | 2.3G | the fake bucket (93 objects, uploaded by the final-gate rehearsal on `2081098d…`) moved aside by the closure lane's first `rehearse.sh all`, whose `upload` step then refused on a G1 timing failure (`out/ux/closure/RESULTS.md` (5)); the second run filled a new `bucket/` | `rm -rf "$W/deploy-rehearsal/bucket.prev-20261003T104020Z"` |
| `$W/deploy-rehearsal/bucket.prev-20261003T184953Z/` | 2.3G | the fake bucket of the closure lane's second rehearsal (gallery `31f6d8d9…`), moved aside by the post-audit fix lane's `rehearse.sh all` on gallery `b7aa521a…` (`$W/logs/postaudit-rehearse-all.log`) | `rm -rf "$W/deploy-rehearsal/bucket.prev-20261003T184953Z"` |
| `$W/l9-desktop/new/`, `old/`, `pinC/` | 1.9G each (5.7G) | per-pin copies (release + gallery + scripts) the l9-desktop lane served from; byte-identical to `release/<id>` (that lane's sha256 check). The lane's scripts, `dr-*` files and `out/ux/l9-desktop/` stay. Its `sequence*.sh` scripts need these copies; the final-gate harness does not (it uses `SHOWCASE_PIN`) | `rm -rf "$W/l9-desktop/new" "$W/l9-desktop/old" "$W/l9-desktop/pinC"` |
| `$W/final-gate/gallery-{1859b83,9fdf9b8,5ac5d00,3b42714}/`, `$W/final-gate/pre-edit/` | 564K each, 528K | per-pin gallery copies for the storm servers (re-made by `$W/final-gate/pin-gallery.mjs`); pre-edit copies of the files the final-gate lane changed | `rm -rf "$W"/final-gate/gallery-* "$W/final-gate/pre-edit"` |
| `$W/v2mit/pre-edit/` | 556K | the v2mit lane's pre-edit copies (its A/B gallery copies are evidence: §3) | `rm -rf "$W/v2mit/pre-edit"` |
| `$W/lastmile/pre-edit/`, `$W/finaldocs/pre-edit/`, `$W/bootfix/pre-edit/`, `$W/closure/pre-edit/`, `$W/postaudit/pre-edit/` | 352K, 408K, 804K, 520K, 19M (with its `out/deploy` copy) | pre-edit copies of the files the last-mile lane (harness, docs), the final docs lane (docs) and the boot-fix lane (gallery, sim, tools, `pin-switch.mjs`, docs, the previous `out/deploy` manifest; `$W/logs/bootfix-du.log`) and the closure lane (`sim-gallery.mjs`, `deploy-manifest.mjs`, `throttle-proxy.mjs`, docs, `out/deploy` before its byte-identical regeneration; `$W/logs/closure-du.log`) and the post-audit fix lane (gallery, sim, check-gallery, `showcase.sh`, `pin-switch.mjs`, three pin descriptors, the throttle tool, `selectors.json`, docs, `out/deploy` before regeneration; `REPIN-LOG.md`, `out/ux/closure/RESULTS.md` and `out/ux/last-mile/RESULTS.md` were edited before a copy was taken; `$W/postaudit/REPIN-LOG.md.AFTER-edit-not-a-backup` is a post-edit copy) changed | `rm -rf "$W/lastmile/pre-edit" "$W/finaldocs/pre-edit" "$W/bootfix/pre-edit" "$W/closure/pre-edit" "$W/postaudit/pre-edit"` |
| older lanes' backups and mutants in `$W` | 0.5–1.0M each (about 5M) | `mutants`, `closeout2-mutC`, `closeout2-mutD`, `closeout3-mutE`, `multipin-migrate-backup`, `final-lane-backup`, `closeout2-backup`, `closeout3-backup`, `dualpin-backup`, `deploy-rehearsal-pre`, and this lane's `docsfinal-pre-edit` (376K) | `cd "$W" && rm -rf mutants closeout2-mutC closeout2-mutD closeout3-mutE multipin-migrate-backup final-lane-backup closeout2-backup closeout3-backup dualpin-backup deploy-rehearsal-pre docsfinal-pre-edit` |
| the session scratchpad `$S` | 18G in 195 entries | the lanes' sandboxes and mutants: `sc dir` 2.6G, `audit` 2.5G, `pinD-sandbox` 2.3G (mostly an APFS clone of `release/5ac5d00`), `warm-mutA`/`B`/`C` 2.0G each, `mut-label` and `mut-parsehash` 1.6G each, `lr` 701M, `ci-checkout` 269M, `ct` 140M, the hardening lane's `mut-A`…`mut-D` and `orig/`, and small files | `rm -rf "$S"` (after this session has ended) |

## 2. Regenerable caches (deleting costs time on the next run, nothing else)

| Path | Size | What it is | Command |
|---|---|---|---|
| `$R/out/ux/profiles/ux-warm/` | 14G | the verdict suite's warm browser profile (OPFS snapshots of every pin served so far, and the auditor's :5192 origin data). UX C2 re-primes it (`tests/ux/lib/qed64.mjs` `launch` creates the directory) | `rm -rf "$R/out/ux/profiles/ux-warm"` |
| `$R/out/ux/profiles/ux-warm-chrome-headed/` | 2.0G | the branded-Chrome headed runs' warm profile (last-mile lane, `UX_CHANNEL=chrome`); re-primed by the next such run | `rm -rf "$R/out/ux/profiles/ux-warm-chrome-headed"` |
| `$R/out/ux/profiles/ux-warm-headed/` | 3.5G | the headed sign-off's warm profile; re-primed by the next headed run | `rm -rf "$R/out/ux/profiles/ux-warm-headed"` |
| `$R/out/ux/profiles/ux-warm-5196-pinA/` | 3.9G | the profile for pin A on its own port, created by the hardening lane on :5196 (2.0G on 2026-10-02) | `rm -rf "$R/out/ux/profiles/ux-warm-5196-pinA"` |
| `$R/out/ux/profiles/explore-warm/` | 3.1G | `tests/ux/tools/stockcases.mjs`'s profile (re-created by it) | `rm -rf "$R/out/ux/profiles/explore-warm"` |
| `$R/out/ux/profiles/x2/` | 1.8G | stage A's X2 experiment profile | `rm -rf "$R/out/ux/profiles/x2"` |
| `$W/deploy-rehearsal/bucket/`, `$W/deploy-rehearsal/state/` | 2.3G, 2.3G | the current fake R2 bucket and wrangler's local R2 state; `scripts/deploy-rehearsal/rehearse.sh all` fills them again (`upload`, `load`) | `rm -rf "$W/deploy-rehearsal/bucket" "$W/deploy-rehearsal/state"` |

## 3. Evidence (no tool needs it to build, serve or test; docs cite some of it)

Delete only if you accept losing the evidence. `node scripts/ux-tally.mjs` reads each run directory's `run-meta.json`,
`report.json`, `tests/*.json` and `explore/`, never `test-results/`, so deleting the traces below leaves every tally
unchanged; deleting a whole run directory changes the tally.

| Path | Size | What it is | Command |
|---|---|---|---|
| `$R/out/ux/<run>/test-results/` in 115 run directories (all but the four below) | 24.2 GiB | Playwright traces and failure attachments; not cited by any doc (list with sizes: `$W/logs/finaldocs-housekeeping-test-results.log`; largest `closeout2-mutD` 1.9G, `auditor-mutCD` 1.8G, `multipin-A-liveness` 1.7G, `dev5` 1.7G, `dev9` 1.6G; the last-mile lane's `lastmile-chrome-headed1` 640M) | `cd "$R/out/ux" && find . -mindepth 2 -maxdepth 2 -type d -name test-results ! -path ./auditor-full/test-results ! -path ./final-D-headed1/test-results ! -path ./v2mit-headed1/test-results ! -path ./lastmile-chrome-headed2/test-results ! -path './profiles/*' -exec rm -rf {} +` (run it first with `-print` in place of `-exec rm -rf {} +`: 115 lines) |
| `$R/out/ux/auditor-full/test-results/` | 4.6G | the trace of the only captured real L7 hang, cited by `out/hang/ROOT-CAUSE.md` | keep (or `rm -rf "$R/out/ux/auditor-full/test-results"`) |
| `$R/out/ux/final-D-headed1/test-results/` | 223M (run dir 238M) | traces of the 7 headed failures that root-caused N3, the headed baselines and the C4 race (docs/UX-RESULTS.md "Final gate") | keep (or `rm -rf "$R/out/ux/final-D-headed1/test-results"`) |
| `$R/out/ux/v2mit-headed1/test-results/`, `$R/out/ux/lastmile-chrome-headed2/test-results/` | 334M, 161M | the failing C13 images the last-mile lane compared pixel for pixel (display-scale root cause; Chrome 154's missing scrollbars in C13b), `out/ux/last-mile/RESULTS.md` (2) | keep (or `rm -rf` each) |
| `$W/v2mit/gallery-ctl/`, `$W/v2mit/gallery-mit/` | 564K, 564K | the v2mit A/B's two served galleries, i.e. what ran (`out/ux/v2mit-storm/RESULTS.md` "What ran": ctl = the gallery before that lane, `2081098d…`; mit = the same plus the rejected `pagehide` teardown, the only full copy of that variant besides `$W/v2mit/teardown-snippet.js`). Cited evidence, so not in §1 (the 2026-10-03 03:51Z version of this page listed them there by mistake) | keep (or `rm -rf "$W/v2mit/gallery-ctl" "$W/v2mit/gallery-mit"`) |
| `$R/out/ux/harden-C-subset1/`, `harden-C-subset2/` | 54M, 8K | a subset run whose one failure was in the new test's premise, and a lock-timeout record (docs/UX-RESULTS.md "Hardening lane"); removing them can lower the run-directory count in the tally header; no per-pin count changes (they ran only C8, C13, C17, C24) | `rm -rf "$R/out/ux/harden-C-subset1" "$R/out/ux/harden-C-subset2"` |
| `$W/audit3-evidence/` | 2.5G | copies of the last audit's UX run directories (`audit-final-full1`, `audit3-c20`, `audit3-mut-M1..M3`); not cited by the docs (they cite `out/ux/audit-cl3-*`) and not read by any tool | `rm -rf "$W/audit3-evidence"` |
| `$W/rollback-wasm64-4b025db7729c5f89/` | 3.2G | the 2026-10-01 re-pin's rollback snapshot (trees and logs; docs/REPIN-LOG.md §3 and its rollback procedure); superseded by the multi-pin stores (pin A's stores are complete without it) | `rm -rf "$W/rollback-wasm64-4b025db7729c5f89"` |
| `$R/rollback/` | 728M | the same re-pin's pre-edit copies, kept "as is" (README "Layout"); docs/UPSTREAM-REPORT-QED64.md cites its `out-experiments/x4.json` (the old-pin X4 result) | `rm -rf "$R/rollback"` |

## 4. Keep (needed to build, verify, serve, test or re-pin)

| Path | Size | Why |
|---|---|---|
| `$W/runtimes/` | 20G | stage1, raw regions, bakes and bake keys of the three runtimes (pins A/C, B, D); `pin check` and `verify` need them; the active links point into them |
| `$R/release/` | 6.2G | the four pins' verified QED64 clones (what `serve.mjs` serves) |
| `$R/out/runtimes/`, `$R/out/overlay/`, `$R/out/deploy/`, `$R/out/deploy-rehearsal/` | 2.1G, 338M, 18M, 216M | overlays and headless results per runtime; deploy inputs; rehearsal logs cited by docs/DEPLOY-CLOUDFLARE.md |
| `$W/frozen-qed64-5ac5d00/`, `$W/frozen-qed64-3b42714/` | 5.7G, 14G | read-only QED64 copies for re-cloning pins C and D after QED64 moves on (`FROZEN.txt`) |
| `$W/golden-env/`, `$W/tree-stock/` | 12G, 1.5G | inputs of `scripts/headless/run-stage4.sh` and `run-controls.sh` |
| `$W/mathlib4/`, `$W/tree-slim-w7/`, `tree-slim-w8/`, `tree-fat/`, `$W/widgets-src/` | 5.5G, 1.5G, 1.7G, 4.2G, 4.7M | native build and staging inputs |
| `$W/logs/` | 34M | every lane's logs, cited throughout |
