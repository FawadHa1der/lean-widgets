# Gallery-side L9 V2 mitigation: A/B (2026-10-02, 22:27–23:35 UTC) — negative, reverted

Lane `v2mit`. The question (docs/NEXT-STEPS.md §1.3): does tearing QED64 down from the gallery's own `pagehide`, before
the browser unloads the iframe, lower the V2 crash rate of a reload storm through `/showcase/`? Hypothesis (inference,
not shown): on a reload the outer gallery document plus the iframe document delay the teardown of QED64's ~26 dedicated
workers, so their isolates overlap the next instance's boot.

## Answer: no. Not kept; `gallery/gallery.js` was never changed

| arm | browser | runs | V2 crashes | crashed runs |
|---|---|---|---|---|
| ctl: current gallery | headed Chrome for Testing 151 | 24 | **8/24** | v01 v03 v04 v05 v10 v14 v16 v24 |
| mit: + pagehide teardown | headed Chrome for Testing 151 | 24 | **10/24** | v04 v09 v11 v12 v14 v16 v17 v20 v22 v23 |
| ctl | chrome-headless-shell 151 | 12 | 0/12 | – |
| mit | chrome-headless-shell 151 | 12 | 0/12 | – |

* Every crash is V2 (`MarkCompactCollector: young object promotion failed` in the browser stderr), 2.02–2.16 s after
  reload 2, 3 or 4, in both arms. Headed, Fisher exact two-sided p = 0.77; the first 12 reps alone were ctl 5/12, mit
  4/12 (p = 1.0). The decision rule was written down before the headed extension ran (`$W/logs/v2mit-decision-rule.log`:
  keep only if mit has fewer V2 crashes AND one-sided p < 0.10); mit has more. **Decision: revert** (the mitigation only
  ever existed in the treatment copy `$W/v2mit/gallery-mit/`; `gallery/gallery.js` is byte-equal to the served one).
* No regression signal either way: boot to ready 13.2–13.7 s and ready after the storm 6.0–6.3 s in both arms; no
  non-crash failure in 72 runs.
* **Mechanism probe (why it cannot help).** `$W/v2mit/teardown-probe.mjs` (chrome-headless-shell, 2 runs × 3 single
  reloads per arm, `out/ux/v2mit/explore/teardown-probe-*.json`, `$W/logs/v2mit-probe1.log`): after `page.reload()`
  the top document's `beforeunload` fires at 4–7 ms and its `pagehide` at 9–16 ms, and **all 26 old workers report
  `close` 7–14 ms (ctl) / 11–40 ms (mit) after the reload call**, while the first worker of the new page is created
  113–185 ms after it. So the old page's workers are already gone (as far as the browser reports them) 100+ ms before
  the new page creates any, with or without the gallery-side teardown, and `beforeunload` would start only about 6 ms
  earlier than `pagehide`. Whatever overlaps when V2 hits ~2 s after a reload is not the document teardown order the
  gallery controls (inference: worker isolate memory is released later than the worker target closes; not shown).
* The quiet-round difference (V2 through `/showcase/`, rarely on the stock page) is therefore not explained by the
  gallery's extra document delaying the iframe's teardown; it stays an open question for QED64 (L9 in
  docs/UPSTREAM-REPORT-QED64.md).

## What ran

* Servers: `SHOWCASE_PIN=5ac5d00 GALLERY_DIR=<copy> PORT=<p> scripts/serve-start.sh`; ctl `:5221` =
  `$W/v2mit/gallery-ctl` (made by `$W/final-gate/pin-gallery.mjs 5ac5d00`, `diff -r` equal to `gallery/` at the start,
  gallery content `2081098d…`), mit `:5222` = the same copy plus 17 lines before `start()` in `gallery.js`
  (`$W/v2mit/teardown-snippet.js`): on the top window's `pagehide`, `qed64.relay.unload()` (vendored `lsp-relay.ts`
  `unload()`: `session.dispose()` + the synchronous `Worker.terminate()`, the same call QED64's own pagehide handler
  makes) inside try/catch, then `iframe.remove()`; on a `pageshow` with `persisted` after a teardown, `location.reload()`.
  Both answered `X-Showcase-Pin: 5ac5d00 wasm64-4b025db7729c5f89`; served `gallery.js` sha256 `0fd279d7…` (ctl) and
  `90c5155a…` (mit). Both stopped afterwards (`$W/logs/v2mit-serve-stop.log`).
* Tool: `tests/ux/tools/reload-storm-desktop.mjs --entry showcase` (unchanged; fresh profile, ready, 5 reloads 3 s apart,
  120 s for ready again, crash = page `crash` event, `DEBUG=pw:browser`), run by `$W/v2mit/run-arm.sh` (the final-gate
  `run-arm.sh` writing to `out/ux/v2mit-storm/explore`): host state before every run, renderer RSS sampler.
* Order: `$W/v2mit/master.sh` (reps 1–12: headed and headless-shell × ctl and mit, mode order and arm order alternated
  per rep, 3 reps per browser-lock hold) and `$W/v2mit/master-ext.sh` (reps 13–24: headed only, arm order alternated).
  Each started after a 300 s quiet streak (`explore/quiet-poll.tsv`: ≥ 20 GB reclaimable, no foreign heavy process, swap
  not growing). Every one of the 72 runs launched quiet: 22.5–22.9 GB reclaimable, no foreign heavy process, swap
  605.8 → 597.8 MB (`explore/host-state.tsv`).
* Logs: `$W/logs/v2mit-master.log`, `$W/logs/v2mit-master-ext.log`. Table: `$W/v2mit/tabulate.py` →
  `storm-table.json`, `storm-table.md` (per-run rows: host state, crash time, OOM lines, ready times, renderer peak).

## Deletable (nothing was deleted)

> **Correction (boot-fix lane, 2026-10-03):** the two gallery copies below are this A/B's evidence (they are what the
> two servers served, see "What ran"), so docs/HOUSEKEEPING.md lists them under §3 "Evidence", not as deletable
> scratch. Deleting them loses the only full copy of the `mit` variant.

`$W/v2mit/gallery-ctl/`, `$W/v2mit/gallery-mit/` (APFS clones of `gallery/`, about 0.5 MB each), `$W/v2mit/pre-edit/`
(pre-edit copies of the files this lane changed), `out/ux/v2mit-storm/screens/`, `tests/` (empty or console records of the storm sessions); keep `explore/` and the tables.

**Caveat (added 2026-10-03).** The mechanism probe's worker timings are Playwright Worker `close` events, i.e. CDP target detach, not proof that the worker's V8 isolate was freed. Blink force-terminates a worker that is busy in wasm only after a ~2 s grace (`worker_thread.cc`, per the QED64 V2 session), and every V2 hit lands 2.0–2.16 s after a reload. So this negative result rules out only the page-side teardown ORDER we tried (relay.unload + removing the iframe on pagehide); it does not rule out late isolate death as the mechanism.
