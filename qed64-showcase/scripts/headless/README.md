# `scripts/headless/` — headless wasm verifiers (BUILD-PLAN §6: E1, E3, E3b)

These tools check a snapshot pairing *before* any browser is opened. They run the
target pin's QED64 runtime (`node scripts/lib/pins.mjs target-bid`; pin I `385a1ac`: `wasm64-f69cca24d0878a58`, active
since 2026-10-09; earlier `wasm64-3ab1c6a9da03bc29` for D–H, `wasm64-2c18773ecfba45bb` for B, `wasm64-4b025db7729c5f89`
for A and C) in Node, using only:

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
# runtime (plan X6): the served stage1 bin in the runtime's store, $W/runtimes/<bid>/stage1/bin ($W/stage1 is the active
# pin's link to it); buildIdOf must be the lock buildId. Pin I on, from the kernel fork's release that QED64's
# toolchain/lean4-wasm64-release.json names (T = its unpacked tools package, REL = the release directory):
node $T/cli.mjs fetch --from $REL --id lean-v4.34.0-e1a79c1 --digest <record digest> --out $W/toolchains/lean-v4.34.0-e1a79c1 --only runtime
mkdir -p $W/runtimes/wasm64-f69cca24d0878a58/stage1 && cp -Rc $W/toolchains/lean-v4.34.0-e1a79c1/bin $W/runtimes/wasm64-f69cca24d0878a58/stage1/bin
# (the retired pins up to H cloned QED64's own build: cp -Rc $Q/pipeline/toolchain/work/build/stage1/bin …)
# raw stock snapshots (122,364,117 and 1,127,272,685 bytes; .snapz digests checked against the index,
# raw sha256 recorded in $W/raw/<name>.snap.provenance.json and re-verified on every rerun)
scripts/headless/derive-raw.sh
# olean tree for the stock controls, $W/tree-stock: the tree the served mathlib region was baked from (the target pin's
# servedTrees.baseSlim; 5,004 .olean up to 58ebbad, bump-0035's byte-identical to bump-51's, docs/REPIN-LOG.md; 5,092
# for 521cf3f). Not cloned by hand: run-controls.sh makes it when missing, together with its sidecar
# $W/tree-stock.SOURCE.json {schema, base, pin, n, clonedAt}, which a hand-made copy lacks: on a pin that records servedTrees.baseSlimDigest (521cf3f) it is written once the copy passes G0; on any other pin such a copy is refused
node scripts/stage-trees.mjs --stock-copy $W/tree-stock
```

Every wasm tool refuses to run when `buildIdOf(--artifact)` is not the pinned buildId. `$W/tree-stock` is one copy shared
by every pin, so `run-controls.sh` checks it against the target pin before any control runs
(`stage-trees.mjs --stock-copy`), in both switching directions:

* a pin whose descriptor records `servedTrees.baseSlimDigest` (`521cf3f` is the first; its base tree has 5,092 modules):
  G0, the tree digest of the copy == that digest. A copy cloned for an older pin FAILs it. A copy that passes with no
  sidecar, or with one naming another pin or base (a copy moved back by hand), gets one written for the target pin.
* a pin that records none (every pin before `521cf3f`, which until then printed `SKIP G0 baseSlim`): the sidecar's `base`
  must be the pin's expanded `servedTrees.baseSlim` and the copy must hold `servedTrees.baseN` `.olean` files. A copy
  cloned for `521cf3f`, or one with no sidecar, is refused. Pins with textually different but byte-identical bases
  (bump-51 vs bump-0035b) are refused too, and recloning costs only an APFS clone.

Each refusal (exit 2) names the pin the copy was cloned for and prints the command that moves it aside together with
its sidecar, e.g. `mv "$W/tree-stock" "$W/tree-stock.prev-521cf3f" && mv "$W/tree-stock.SOURCE.json"
"$W/tree-stock.prev-521cf3f.SOURCE.json"`; the rerun then clones the copy again from the target pin's tree. Moving a
copy back (both files) is how to return to it: its sidecar travels with it.

*Note (2026-10-08, updated 2026-10-09).* The `$Q/pipeline/toolchain/work/` copy is how every pin up to H was set up;
QED64 `385a1ac` (pin I) has no such tree. The kernel fork's toolchain releases ship the runtime instead
([`lean-v4.34.0-a8817d0`](https://github.com/FawadHa1der/lean4/releases/tag/lean-v4.34.0-a8817d0) for D–H,
`lean-v4.34.0-e1a79c1` for I): `node <pkg dir>/cli.mjs fetch --only runtime` (with `node`, never `npx`) fetches and
verifies the runtime's `bin/`. Pin I's stage1 came that way (`$W/logs/pinI-stage1-fetch.log`: `FETCH VERIFIED`; the
`bin/` byte-identical to QED64's own adopted copy), and its controls passed on it (`CONTROLS PASS`,
`$W/logs/pinI-hl-controls.log`).

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
7. It calls `callMain(RESIDENT_ARGV)`: the resident FileWorker's command line, parsed from the pin's own
   `public/workers/lean.worker.js` (`residentArgv()` in `wasm-lsp.mjs`), so the lane runs exactly what the browser
   worker runs. For pin K `62a06e2` on that is `["--worker", "-Dserver.reportDelayMs=0", "-DElab.async=false"]`
   (QED64 HARDENING #70). A pin whose worker has no `RESIDENT_ARGV` (before K: the argv is inlined in `callMain`) is
   refused before anything boots. The log names the argv (`lean --worker … (RESIDENT_ARGV of …)`).
   A pin that ships `public/workers/worker-constants.js` (QED64's shared Lean policy, `e367f95` on; not O or N) is run
   by it instead, as its browser worker and its `resident-probe.mjs` are: the argv is
   `Qed64WorkerConstants.residentArgv()` (same shape check; the log says `Qed64WorkerConstants.residentArgv() of …`),
   `LEAN_WASM_PARKED_DEDICATED` is set at preRun, and the task manager gets
   `leanWorkers(os.availableParallelism())` workers through `_lean_init_task_manager_using`. Without the file, steps 2
   and 7 are as before (`_lean_init_task_manager()`, the hardware default), so O's results stay comparable.

*Note (2026-10-27): `Elab.async`.* Until 2026-10-27 `wasm-lsp.mjs` hard-coded `["--worker",
"-Dserver.reportDelayMs=0"]`, so every E3 result up to pin N (`58ebbad`), whose worker already ran
`-DElab.async=false`, elaborated with asynchronous elaboration ON (the FileWorker's default when the command line leaves
it unset), unlike the browser. From the Lean 4.35 re-pin (QED64 `521cf3f`) on, the runs that boot this transport use
QED64's argv, i.e. `Elab.async=false`, as QED64's EMBEDDING §12 (`c512c21`) advises for embedders that lint their own
tactic blocks (the widgets do: SimpLens, DistLens). Those are E3 (`rpc-probe.mjs`: stage 4's E3 steps and the wasm E3
controls) and E3b (it renders the panels E3 produced), and `hang-repro.mjs` until P1 removed it; their 4.35 results are **not directly
comparable** with N's or earlier: a difference between them may come from the flag as well as from Lean 4.35. E1
(`exact-header.mjs`, QED64's `snapshot-probe.mjs` batch compile) and E2 (`run-e2.sh`, QED64's `supervised-run.mjs` →
`node-runner.mjs` CLI, no `-D` option) do not use `wasm-lsp.mjs`: they keep their own command lines and this change
does not touch them. The native side (`NativeLsp`, stock `lean --server`, and the goldens) is unchanged and still runs
with Lean's default.

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
  [--golden-env w8] [--golden <rpc-or-expect json> | --golden none] [--golden-html <html json>] \
  [--index <index.json>]… [--allow-unpaired] \
  [--transport wasm|native] [--native-env w8] [--timeout-ms 300000] [--min-free-gb 12] [--out <json>]
```

* Golden selection (`--pkg` without `--golden`): `lean/expect/<pkg>.json`, the w8 golden of every package (one golden set
  since P2; any `--golden-env` other than `w8` is a usage error, exit 2). Until P2 the phase-1 packages' base goldens were
  w7 and their w8 goldens sat in `lean/expect/w8/`.
* Golden Html dump (`--golden-html` overrides): `lean/expect/<pkg>.json` → `lean/expect/html/<pkg>.json`;
  `<x>.rpc.json` → `<x>.html.json`.
  If the golden has MakeEditLink panels and the dump (or the panel in it) is missing, the
  comparison FAILS — it is never skipped. The result records `comparison.goldenHtml` and `goldenHtmlLooked`.
* Environment guards (comparison checks): with `--golden-env`, the golden's own
  `environment.golden` (or `run.goldenEnv`) must equal it; and when a `--snap` path names a
  bake (`…-w8/…`, `widgets8.snap`) the golden env must equal that bake.
* `--native-env` defaults to `--golden-env`, else w8 (until P2 the default was w7, so control `b-e3-conv-native` could
  resolve `import Mathlib` in the wrong environment once the w7 env was gone; `golden-env.sh path` refuses any name but
  `w8` since P2).

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

One bake exists since P2 (until then also a 7-package bake w7, without DistLens, with its own key, tree, raw region,
index and goldens). Check the paths before use:

| bake | serves | BAKE-KEY | raw region | index (for `--index`) | olean tree | goldens (`--golden-env`) |
|---|---|---|---|---|---|---|
| w8 | all 8 packages | `$W/BAKE-KEY-w8.txt` | `$W/bake-work-w8/widgets.snap` (1,267,834,573 B on the first runtime) | `$W/bake-out-w8/index.json` | `$W/tree-slim-w8` | `w8`: `lean/expect/<pkg>.json` + `lean/expect/html/<pkg>.json` |

The w8 bake is the one the gallery serves, and the stage-4 gate is the w8 block. Run one package at a time (each wasm step ≈12 GB RSS; the
lock enforces it).

```bash
scripts/headless/run-stage4.sh all        # the w8 block (8 packages; `all` is an alias of w8 since P2); or: w8 [pkg …]
scripts/headless/run-e2.sh                # E2: each Demo.lean verbatim on $W/tree-fat (serial)
node scripts/headless/summarize-stage4.mjs   # -> out/headless/summary.json + markdown tables
```

Before any step, `run-stage4.sh` and `run-e2.sh` refuse (exit 2) an olean tree that was not staged for the target pin
(`stage-trees.mjs --check-provenance $W/tree-slim-w8`: `<tree>.STAGED.json` names the runtime, served base and widget
export it was staged for). The trees are shared by every pin, so after another pin's `stage` the remedy is the one the
refusal prints, `SHOWCASE_PIN=<id> scripts/showcase.sh stage w8|fat --force`. The direct commands below take `--lib`
as given and check nothing: run `--check-provenance` on the tree first.

`run-stage4.sh` runs, per package, exactly these three commands (dist-lens uses `--budget-ms 900000 --timeout-ms
900000`):

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

`$W/raw/init.snap` pairs against the bake index (it carries the stock `init` snapz of the runtime). `$W/raw/widgets8.snap`
(if present) may be used in place of `bake-work-w8/widgets.snap`; `--index` proves they are the same bytes.

Proven on 2026-10-01 for graph-scope on w8 (the audit's failing case):
`E1 PASS graph-scope.widgets8 (9/9)`, `E3 PASS graph-scope.widgets8 (131/131)` including
`golden Html dump present (5 MakeEditLink panel(s) need it) PASS lean/expect/html/w8/graph-scope.json` (the w8
goldens' path until P2) and 5 `Html hash with MakeEditLink …` checks, `react verification: 5/5 panels clean`. The same
run without `--golden-env` (then the w7 golden on the w8 bake) failed with
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
| (e) negatives | byte-flipped APFS clone of `init.snap` (offset 60,000,000) with its sidecar; with `--index` the release index; E1 with `--index`; native graph-scope vs the w8 golden (then `lean/expect/w8`) with `--golden-html` pointing at a missing file | each must exit 1: E3/E1 `FAIL … (raw snapshot provenance; worker not booted / probe not run)`; `E3 FAIL graph-scope.nohtml (114/120)` with 6 FAILs (dump missing + 5 MakeEditLink Html hashes) |

The positive wasm controls run with `--index` on the release index (E1, conv) or the
derive-raw sidecar (hasse-refused), so both pairing paths are exercised on every run.
