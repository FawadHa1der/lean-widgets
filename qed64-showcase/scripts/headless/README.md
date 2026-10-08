# `scripts/headless/` — headless wasm verifiers (BUILD-PLAN §6: E1, E3, E3b)

These tools check a snapshot pairing *before* any browser is opened. They run the
pinned QED64 runtime (`wasm64-2c18773ecfba45bb` since the 2026-10-01 re-pin; previously `wasm64-4b025db7729c5f89`) in Node, using only:

* QED64's sources at the pin's commit: the git submodule `deps/qed64` (a staged pin: its worktree
  `$W/qed64-pins/<id>`; `scripts/lib/qed64-src.mjs`), never a copy, and
* our own clones under `$W` (the work dir: `QED64_SHOWCASE_WORK`, resolved by `scripts/lib/env.sh`).

They never write to a QED64 tree or a widget tree.

| file | lane | what it does |
|---|---|---|
| `exact-header.mjs` | E1 | Compiles an example through the worker's batch path on the exact bake key, using QED64's `snapshot-probe.mjs --via-mem` (deps/qed64) |
| `rpc-probe.mjs` + `wasm-lsp.mjs` | E3 | Runs `lean --worker` (the resident FileWorker) in Node and walks the InfoView's path: header status, then RPC, then panels and clicks. Compares the result with the native golden |
| `react-contract.mjs` | E3b | Renders wasm-produced Html trees with React 18.3.1 in development mode. Any React error or warning fails the run |
| `lib.mjs` | | Shared helpers: buildId pairing check, raw-snapshot provenance (`snapProvenance`), memory guard, single-runner lock, header parsing, tables |
| `derive-raw.sh` | | Writes `$W/raw/{init,mathlib}.snap` from the release `.snapz` files, plus a `<raw>.provenance.json` sidecar. Idempotent (re-verifies the content by sha256, not just the size) and safe if two lanes run it at once |
| `run-controls.sh` | | Runs the four controls below plus the negative controls (e), one after another |
| `controls/` | | Control documents and specs, plus `stock-mathlib.BAKE-KEY.txt` |

## Prerequisites

Each of these is created once, and each creation is idempotent.

```bash
. scripts/lib/env.sh   # W (QED64_SHOWCASE_WORK) and Q (QED64_REPO), from the environment or .env.local
# runtime (plan X6): APFS clone of the served stage1 bin; buildIdOf must be the lock buildId (wasm64-2c18773ecfba45bb)
mkdir -p $W/stage1 && cp -Rc $Q/pipeline/toolchain/work/build/stage1/bin $W/stage1/bin
# raw stock snapshots (122,364,117 and 1,127,272,685 bytes; .snapz digests checked against the index,
# raw sha256 recorded in $W/raw/<name>.snap.provenance.json and re-verified on every rerun)
scripts/headless/derive-raw.sh
# olean tree for the stock controls: the tree the served mathlib region was baked from (5,004 .olean;
# bump-0035's is byte-identical to bump-51's, docs/REPIN-LOG.md)
cp -Rc $Q/work/bump-0035/slim/lib-tree-slim $W/tree-stock
```

Every wasm tool refuses to run when `buildIdOf(--artifact)` is not the pinned buildId.

*Note (2026-10-08).* The `stage1/bin` copy above reads QED64's `pipeline/toolchain/work/` tree, which is how every pin
up to H was set up. The kernel fork's toolchain release
[`lean-v4.34.0-a8817d0`](https://github.com/FawadHa1der/lean4/releases/tag/lean-v4.34.0-a8817d0) also ships the runtime:
`node <pkg dir>/cli.mjs fetch --only runtime` (with `node`, never `npx`) fetches and verifies the runtime's
`bin/{lean.js,lean.wasm}` (the release's e2e log: `FETCH VERIFIED`). It is the planned source once we re-pin onto a QED64 release (docs/NEXT-STEPS.md); the
buildId check above applies to it unchanged. Not yet run here.

## Raw snapshot provenance (E1 and E3)

A headless PASS is only meaningful if the raw `.snap` it loaded is byte-identical to the
inflation of the `.snapz` that is (or will be) served. Both wasm tools therefore hash the
CONTENT of every `--snap` before the ≈10 GB worker boots, and fail fast (exit 1, no boot)
unless it is paired:

* `--index <index.json>` (repeatable; a `qed64.snapshot-index/v1` index, e.g. the release
  index or a bake's `bake-out-wN/index.json`): the entry whose `bytes` equals the raw size
  is gunzipped now (≈2.5 s for 1.27 GB); `sha256(.snapz)` must equal the entry `digest`,
  `runtime` must be the pinned buildId, and `sha256(inflated)` must equal `sha256(raw)` —
  the same test as `scripts/pair-check.mjs --cmp`.
* otherwise `<raw>.provenance.json` written by `derive-raw.sh` right after a digest-checked
  gunzip: `sha256(raw)` must equal its `rawSha256`.
* neither: UNPAIRED = FAIL, unless `--allow-unpaired` (recorded as such). A mismatch is
  always a FAIL.

E3 additionally hashes the bytes it actually stages into wasm memory
(`run.snapshots[i].sha256`) and requires them to equal the verified file; E1 requires the
file's size and mtime to be unchanged after the probe read it. Every `rpc.json` records
`run.snapshotProvenance` and every `e1.json` records `snapSha256` + `snapProvenance` (with
the `.snapz` digest), so each result can be tied to a served artifact. Prefer `--index` in
stage 4: it pairs against the bake's own index, which is exactly what gets served.

## Memory

Measured on this host with `/usr/bin/time -l` and `process.resourceUsage()`. One wasm
Node process peaks at roughly:

* about 10.4 GB peak footprint and 11.9 GB max RSS with `mathlib.snap` loaded;
* about 9.1 GB max RSS with `init.snap` only.

Two safeguards follow from this:

* **Memory guard.** Each wasm tool first checks `vm_stat` free+inactive memory, and
  refuses to start below `--min-free-gb` (default 12). It also prints whether a
  `bake-snapshot` is running. Detection counts only real `node` / `/usr/bin/time` processes
  running `bake-snapshot.mjs`. A plain `pgrep -f bake-snapshot` also matches any shell or
  monitor whose command line mentions the name, including the pgrep caller itself.
* **Single-runner lock.** At most one wasm verifier runs at a time, enforced by a lock
  at `$W/headless/.lock`. A stale lock is removed automatically.

The `--transport native` mode of `rpc-probe` uses about 80 MB.

These tools never start a browser. Even so, do not run them while a bake is in its
region/compaction phase unless the guard shows plenty of headroom.

## E1 — `exact-header.mjs`

`snapshot-probe` and `lean_wasm_compile` only look up exact cache keys (plan C2). The
tool therefore replaces the example's import lines with the import lines of the
BAKE-KEY file:

* Nothing else in the document changes.
* The new import lines go where the first import line was.
* Diagnostics are mapped back to the example's own line numbers.

It then runs QED64's probe from the source dependency:

```
/usr/bin/time -l node --stack-size=8192 deps/qed64/pipeline/snapshot/snapshot-probe.mjs --via-mem \
  --artifact $W/stage1 --lib <tree> --snap <raw snap> --probe-file $W/headless/<name>.<snapset>.exact.lean \
  --budget-ms <n> --dump-messages
```

From the probe's output it parses:

* `SNAPSHOT PROBE PASS/FAIL`;
* the key the snapshot seeded (`cached env for #[…]`), which must equal `Init` plus the key;
* load and compile times, which must stay within the budget (an overrun means a silent re-import, i.e. the wrong key);
* every message, as `[lean:stdout] {json}` lines;
* max RSS and peak footprint.

```bash
node scripts/headless/exact-header.mjs (--pkg <pkg> | --example <file.lean>) \
  --bake-key <BAKE-KEY.txt> --snap <raw .snap> --lib <olean tree> \
  [--snapset <label>] [--artifact $W/stage1] [--budget-ms 120000] [--allow-warnings] \
  [--expect fail] [--index <index.json>]… [--allow-unpaired] [--min-free-gb 12] [--out <json>]
```

* Exit codes: 0 = gate passed, 1 = gate failed, 2 = usage or setup error.
* Gate, by default: raw snapshot paired (see above), probe PASS, the seeded key equals `Init` + the key, compile within budget, zero errors and zero warnings.
* Gate with `--expect fail` (a negative control): the probe must fail on the compile step itself, with at least one error. Failing on load or budget does not count.
* Outputs:
  * `out/headless/<name>.<snapset>.e1.json`
  * the exact-key document at `$W/headless/<name>.<snapset>.exact.lean`
  * the probe log at `$W/logs/e1-<name>.<snapset>.log`

For widget bakes (stage 4) see [Stage 4](#stage-4-the-widget-bakes) below.

## E3 — `rpc-probe.mjs`

**What it does.** This is the wasm counterpart of `lean/goldens/lsp-golden.mjs`. Its
panel, selection, hover, Try-this and click logic is copied from there.

**How it boots** (`wasm-lsp.mjs`). It follows the browser worker and QED64's
`resident-probe.mjs` / `header-switch-probe.mjs`:

1. It sets up its own shared Memory64, sized as the browser does: 2 GiB initial when a
   non-init region is loaded, 256 MiB otherwise, and 6 GiB maximum.
2. It runs full Lean initialization.
3. It calls `_lean_wasm_load_snapshot_mem(ptr, bytes, 1n)` once per `--snap`, in the
   order given.
4. It calls `mark_preinitialized`.
5. It sets up the stdin ring.
6. It installs a per-byte stdout tap that feeds the product's own `LspFrameDecoder`
   (`deps/qed64/public/workers/lsp-frames.js`).
7. It calls `callMain(["--worker", "-Dserver.reportDelayMs=0"])`.

**Front-door rules.** Client frames follow `lsp-front-door.js`:

* The opening sequence is `initialize` followed by `didOpen`. `initialize` is never
  answered and no `initialized` is sent.
* Only allowlisted notifications are forwarded.

**Then, per document:**

1. **Header.** The document is opened with the browser header, unchanged. The tool
   asserts that `$/qed64/headerStatus` has the expected `mode` and `missing`, then
   waits until `waitForDiagnostics` returns and `fileProgress` has drained. A refused
   header settles when its fatal progress entry arrives.
2. **Cursors.** It connects with `$/lean/rpc/connect`. For each spec cursor it calls:
   * `getWidgets`;
   * `getWidgetSource` for every hash (the source must be non-empty and import `@leanprover/infoview`);
   * for `mk_rpc_widget%` panels, the panel's own `@[server_rpc_method]`, using the cancellable protocol where it applies.
3. **Selections and hovers.** Selections are made by shift-click; hovers use `infoToInteractive`.
4. **Clicks.** Each MakeEditLink or Try-this edit is applied with UTF-16 offsets and
   sent as a full-text `didChange`. The diagnostics for that version are checked, and
   the document is then reverted.
   * A click can come from a selection panel: add `"selection": <index>` to the spec's click entry.

**Outputs.** The tool writes `out/headless/<name>.<snapset>.rpc.json` (same schema as
the goldens, plus `headerStatus`, snapshot loads, memory and frame statistics) and
`<name>.<snapset>.html.json` (Html with refs normalized, the input for E3b).

**Golden comparison.** It compares against the native golden (by default
`lean/expect/<pkg>.json` plus `lean/expect/html/<pkg>.json`) and prints a per-check
PASS/FAIL table. The comparison covers:

* document diagnostics;
* per panel: id, kind/method, widget JS sha256, tag counts, SVG tag counts, components, texts, code texts, link texts, and links (text, title, edit, newSelection);
* `htmlSha256`;
* selected locations;
* hover types;
* each click's edit, edited text, and post-click diagnostics;
* code actions (spec `codeActions[]`, the lightbulb): `textDocument/codeAction` (+ `codeAction/resolve`)
  at the declared range — titles, kinds and edits must equal the golden's, and with
  `sameEditAsClick` an action's edit must equal the rendered Try-this link's edit in this run.

The comparison ignores the fields that depend on the environment:

* MakeEditLink `textDocument.uri` and `version` (link `documentVersion`).
* The raw `htmlSha256` of panels that contain a MakeEditLink. Instead it compares a
  hash of the Html with uri, version and mvarId normalized, recomputed from both html
  dumps.
* Selection mvarIds and fvarIds.
* Code-action edit `documentVersion`.
* Timings. They are recorded, never compared: per cursor `cursorMs` (getWidgets + goals + term
  goal + widget sources + panel RPCs, what the InfoView waits for after a cursor move),
  `getWidgetsMs`, `goalsMs`; per panel `jsMs` and `rpcMs`; per click `reElaborationMs`; per code
  action `codeActionMs`.

```bash
node scripts/headless/rpc-probe.mjs (--pkg <pkg> | --example <file.lean> [--spec <file.json>]) \
  --snap <raw.snap> [--snap <raw2.snap> …] --lib <olean tree> [--artifact $W/stage1] [--snapset <label>] \
  [--expect-mode covered|exact|refused] [--expect-missing A,B] \
  [--golden-env w7|w8] [--golden <rpc-or-expect json> | --golden none] [--golden-html <html json>] \
  [--index <index.json>]… [--allow-unpaired] \
  [--transport wasm|native] [--native-env w7|w8] [--timeout-ms 300000] [--min-free-gb 12] [--out <json>]
```

* Golden selection (`--pkg` without `--golden`):
  * `--golden-env w7` → `lean/expect/<pkg>.json` (dist-lens: usage error, it has no w7 golden);
  * `--golden-env w8` → `lean/expect/w8/<pkg>.json` for the 7 phase-1 packages, `lean/expect/dist-lens.json` for dist-lens;
  * no `--golden-env` → `lean/expect/<pkg>.json` (its `environment.golden` is w7 for phase-1, w8 for dist-lens).
* Golden Html dump (`--golden-html` overrides): `lean/expect/<sub>/<pkg>.json` → `lean/expect/html/<sub>/<pkg>.json`
  (so `lean/expect/w8/x.json` → `lean/expect/html/w8/x.json`); `<x>.rpc.json` → `<x>.html.json`.
  If the golden has MakeEditLink panels and the dump (or the panel in it) is missing, the
  comparison FAILS — it is never skipped. The result records `comparison.goldenHtml` and `goldenHtmlLooked`.
* Environment guards (comparison checks): with `--golden-env`, the golden's own
  `environment.golden` (or `run.goldenEnv`) must equal it; and when a `--snap` path names a
  bake (`…-w7/…`, `…-w8/…`, `widgets7.snap`, `widgets8.snap`) the golden env must equal that
  bake — a w8 bake judged against a w7 golden FAILS.
* `--native-env` defaults to `--golden-env`, else w7 (dist-lens w8).

* Exit codes: 0 = every probe and comparison check passed, 1 = a check failed, 2 = usage, setup or boot error.
* Expected header: `headless.expectMode` / `headless.expectMissing` in the spec, else `covered` / `[]`.
* `--transport native` runs the same client against stock `lean --server` with the golden-env `LEAN_PATH`. Use it only to make control goldens; the package goldens are `lean/expect`.
* Logs: the wasm-side stderr goes to `$W/logs/e3-<name>.<snapset>.wasm.log`. Set `LSP_DEBUG=1` to trace incoming notifications.

For widget bakes (stage 4) see [Stage 4](#stage-4-the-widget-bakes) below.

## E3b — `react-contract.mjs`

This is a parameterised copy of `widgets-v4.34/showcase/verify.mjs` (sha256 `9a28f527…`).

* Its `toElement` conversion and its render loop are unchanged.
* React and ReactDOMServer 18.3.1 development builds are cloned (`cp -c`) into
  `vendor/react` and checked against `vendor/react/SHA256SUMS` on every run.
* Html in RPC wire format is mapped to the dump schema the same way
  `showcase/probes/*.lean` `probeHtmlJson` does it.
* A panel with no Html, i.e. a failed RPC, fails.

```bash
node scripts/headless/react-contract.mjs --in out/headless/<name>.<snapset>.html.json [--in …] [--out <json>] [--allow-empty]
node scripts/headless/react-contract.mjs --self-test   # proves it flags #62 string style, `class`, `stroke-width`
```

It also accepts `lean/expect/html/<pkg>.json` and `widgets-v4.34/showcase/dumps/<pkg>.json`.
The default output is `out/headless/<name>.<snapset>.react.json`.

## Stage 4: the widget bakes

Two bakes exist (the bake lane's; check the paths before use). Each needs its own key,
olean tree, raw region, index, and golden set — never mix them:

| bake | serves | BAKE-KEY | raw region | index (for `--index`) | olean tree | goldens (`--golden-env`) |
|---|---|---|---|---|---|---|
| w7 (phase 1) | 7 packages, **no DistLens** | `$W/BAKE-KEY-w7.txt` | `$W/bake-work-w7/widgets.snap` (1,163,657,293 B) | `$W/bake-out-w7/index.json` (`widgets.3619cfd519e6f82d.snapz`) | `$W/tree-slim-w7` | `w7`: `lean/expect/<pkg>.json` + `lean/expect/html/<pkg>.json` |
| w8 (phase 2) | all 8 packages | `$W/BAKE-KEY-w8.txt` | `$W/bake-work-w8/widgets.snap` (1,267,834,573 B) | `$W/bake-out-w8/index.json` (`widgets.0880fd91b58098c0.snapz`) | `$W/tree-slim-w8` | `w8`: `lean/expect/w8/<pkg>.json` + `lean/expect/html/w8/<pkg>.json`; dist-lens `lean/expect/dist-lens.json` + `lean/expect/html/dist-lens.json` |

The w8 bake is the one the gallery serves (it is the only one with DistLens), so the
stage-4 gate is the w8 block. Run one package at a time (each wasm step ≈12 GB RSS; the
lock enforces it).

```bash
scripts/headless/run-stage4.sh all        # w8 block (8 packages) then w7 block (7); or: w8 | w7 [pkg …]
scripts/headless/run-e2.sh                # E2: each Demo.lean verbatim on $W/tree-fat (serial)
node scripts/headless/summarize-stage4.mjs   # -> out/headless/summary.json + markdown tables
```

`run-stage4.sh` runs, per package and bake, exactly these three commands (w8 shown; dist-lens
uses `--budget-ms 900000 --timeout-ms 900000`; w7 swaps every `w8`/`widgets8` for `w7`/`widgets7`
and skips dist-lens):

```bash
node scripts/headless/exact-header.mjs --pkg $p --bake-key $W/BAKE-KEY-w8.txt \
  --snap $W/bake-work-w8/widgets.snap --index $W/bake-out-w8/index.json --lib $W/tree-slim-w8 \
  --snapset widgets8 --budget-ms 120000                                                  # E1
node scripts/headless/rpc-probe.mjs --pkg $p --golden-env w8 \
  --snap $W/raw/init.snap --snap $W/bake-work-w8/widgets.snap --index $W/bake-out-w8/index.json \
  --lib $W/tree-slim-w8 --snapset widgets8 --timeout-ms 300000                           # E3
node scripts/headless/react-contract.mjs --in out/headless/$p.widgets8.html.json         # E3b
```

It deletes the package's old `out/headless/<p>.<snapset>.{e1,rpc,html,react}.json` first (a
stale file is never judged), logs each step with `/usr/bin/time -l` to
`$W/logs/s4-<E1|E3|E3b>-<p>.<bake>.log`, appends a row to `$W/logs/s4-steps.tsv`, requires BOTH
exit 0 AND the tool's own PASS verdict line (an uncaught crash never counts), continues past
a failure so one run shows every result, and exits 1 if any step failed. `run-e2.sh` does the
same for E2 (`$W/logs/s4-E2-<p>.log`, `$W/logs/s4-e2.tsv`); see docs/HEADLESS-RESULTS.md.

`$W/raw/init.snap` pairs against either bake index (both carry the stock
`init.7cf361eb941eda2c.snapz` on the 9fdf9b8 pin). `$W/raw/widgets7.snap` / `widgets8.snap` (if present) may be
used in place of `bake-work-wN/widgets.snap`; `--index` proves they are the same bytes.

Proven on 2026-10-01 for graph-scope on w8 (the audit's failing case):
`E1 PASS graph-scope.widgets8 (9/9)`, `E3 PASS graph-scope.widgets8 (131/131)` including
`golden Html dump present (5 MakeEditLink panel(s) need it) PASS lean/expect/html/w8/graph-scope.json`
and 5 `Html hash with MakeEditLink …` checks, `react verification: 5/5 panels clean`. The same
run without `--golden-env` (w7 golden on the w8 bake) fails with
`golden environment matches the bake under test FAIL golden w7 vs snapshot w8`.

## Lane hygiene

The read-only trees are stamped at the START of a headless lane, before any file is
written (`scripts/assert-untouched.sh stamp headless-fix`, 2026-10-01T04:07:44Z for the
audit-fix pass), and checked at its end (`scripts/assert-untouched.sh check headless-fix`).

## Controls (`run-controls.sh`), 2026-09-30/10-01

| control | command (abridged) | result |
|---|---|---|
| (a) E1 positive | `exact-header --example controls/e1-essential.lean --bake-key controls/stock-mathlib.BAKE-KEY.txt --snap $W/raw/mathlib.snap --lib $W/tree-stock` | PASS: seeded `#[Init, QED64.Essential]`, compile 1.7 s, 0 errors / 0 warnings, `#eval` info mapped to line 14 |
| (a′) E1 negative | the same with `controls/e1-essential-bad.lean --expect fail` | PASS: probe FAIL on compile, `error` L7 `unsolved goals` |
| (b) E3 positive | `rpc-probe --example controls/conv-control.lean --snap init.snap --snap mathlib.snap --lib $W/tree-stock --golden out/headless/conv-control.native.rpc.json` | see `out/headless/conv-control.stock.rpc.json`: header `covered`, `#[Init, Mathlib.Tactic.Widget.Conv]` (5,004 modules); conv panel JS 3,854 B; `Mathlib.Tactic.Conv.SelectionPanel.rpc` answers; selecting `c + b` gives "Generate conv", whose edit `conv =>\n    enter [2, 1]\n    skip` re-elaborates clean; compared with the native golden |
| (c) E3 negative | `rpc-probe --example controls/hasse-refused.lean --snap init.snap --lib $W/tree-stock` | PASS: `mode: refused`, `missing: ["HasseView"]`, fatal progress, error `modules #[HasseView] are not loaded in this session …` |
| (d) E3b | `react-contract --self-test`; `react-contract --in out/headless/conv-control.stock.html.json` | PASS 4/4 self-test cases; 2/2 wasm control panels clean. Parity: 60/60 on the widget dumps, the same as the original `verify.mjs` (run on a scratch clone); 49/49 on `lean/expect/html/*` |
| (e) negatives | byte-flipped APFS clone of `init.snap` (offset 60,000,000) with its sidecar; with `--index` the release index; E1 with `--index`; native graph-scope vs `lean/expect/w8` with `--golden-html` pointing at a missing file | each must exit 1: E3/E1 `FAIL … (raw snapshot provenance; worker not booted / probe not run)`; `E3 FAIL graph-scope.nohtml (114/120)` with 6 FAILs (dump missing + 5 MakeEditLink Html hashes) |

The positive wasm controls run with `--index` on the release index (E1, conv) or the
derive-raw sidecar (hasse-refused), so both pairing paths are exercised on every run.
