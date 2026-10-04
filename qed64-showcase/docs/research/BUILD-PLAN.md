# QED64 widget showcase: end-to-end build plan and UX test plan

The plan runs as a staged pipeline with go/no-go gates. The deliverable lives in a new repo, `/Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/`. QED64 is a pinned dependency and nothing under the four read-only trees is ever written.

Variables used throughout:
```
SC="/Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase"
Q=/Users/fawadhaider/code/wasm64-lean-fable/qed64
K=/Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0
WS="/Users/fawadhaider/code/lean questions/infoview-widget-research/widgets-v4.34"
W="$SC/work"                 # gitignored heavy work dir (experiment X6 decides if it needs a space-free path)
R="$SC/release/wasm64-4b025db7729c5f89"
QPIN=1859b830b3621dbacc1752a818634d06a1c94bd0     # HEAD; promote = 965c2494b3e4419986a6d0da1fea393a72667b19
BID=wasm64-4b025db7729c5f89
```

---

## 0. Decisions, and corrections to the evidence maps

**Decisions**

- **D1. Depend on a pinned *release*, not a live checkout.**
  - Source files: vendored with `git archive $QPIN` (a read-only operation on the object store).
  - Binary artifacts: APFS clonefile copies (`cp -c`) into `$R`. Each is verified against hashes that git-tracked manifests anchor.
  - Effect: later QED64 rebuilds, promotes, or removal of the dev-only overrides cannot break the local showcase. Only a deliberate re-pin can.
- **D2. No `QED64.Widgets.*` shims (this supersedes 06 §2.3).** Every example header is `import Mathlib` / `import <Pkg>`.
  - `needsMathlib` fires on the `Mathlib` root, so the page boots `['init','mathlib']` (`frontend/src/resident-session.ts:74-85`).
  - The kernel treats `Mathlib` as an alias. It is covered by any environment whose closure contains `QED64.Essential` (`wasm64-lean-kernel/src/Lean/Language/Lean.lean:299-306`).
  - `<Pkg>` is covered because it is in the superset closure. So the header is "covered", and it is also valid in VS Code.
- **D3. Three page milestones.**
  - **M1:** the stock page plus a `?snapshots=` overlay.
  - **M2:** a same-origin gallery wrapper (our page iframes the stock page and drives `contentWindow.qed64`). No npm is needed, examples are preloaded, and it is still literally QED64's page. This is the main user-facing result.
  - **M3:** Option 2, a vendored app. It is the durable, deployable form and the only clean way to control the memory commit. It is built after M2 passes.
- **D4. Phases.** Phase 1 is seven packages; DistLens is phase 2.
  - Phase 1 delta: 38 Mathlib/ProofWidgets modules to compile plus HtmlDisplay, which already exists natively (maps 3 and 6).
  - Phase 2 adds 404 modules to compile, plus 169 that already exist natively.

**Corrections to the maps**

- **C1. Native compiler commit.** It is 857544b439, not 8d91aadcda. `native/NATIVE-COMMIT` reads `857544b439aa…`; `BUILT-COMMIT` reads `8d91aadcda8a…` (both verified). The two commits differ in no compiler source.
- **C2. `snapshot-probe` / `lean_wasm_compile` only looks up exact keys.** `getOrCreateWasmEnvFor` matches the exact key; on a miss it calls `importModules` from `--lib` (`wasm64-lean-kernel/src/Lean/Shell.lean:71-105`). "Covered" resolution exists only in the FileWorker (`src/Lean/Server/FileWorker.lean:429-458`).
  - So map 2's "header must match or be covered" is wrong for snapshot-probe.
  - Headless compile probes must use the exact bake header (§6, E1).
  - Browser-shaped headers are tested through the FileWorker probe (E3).
- **C3. No hard links from QED64 trees.** Map 4's `rsync --link-dest …/qed64/work/lib-tree-slim` is rejected: the inodes are shared, with nlink=5 (map 3, `stat`). Use `cp -c` / `cp -Rc` only.
- **C4. `QED64_ALLOW_LEGACY_IMPORTS` is irrelevant everywhere.**
  - The tolerance is `System.Platform.target.startsWith "wasm" || env` (`wasm64-lean-kernel/src/Lean/Environment.lean:2173-2174`).
  - native64 reports `wasm64-unknown-emscripten` (`native64.sh:52-60`).
  - The tolerance also only applies when importing at `.exported` level (`Environment.lean:2162`).
  - Passing it to the bake is harmless.
- **C5. The widgets ship no JS of their own.** No `include_str` appears in any `widgets-v4.34/**/*.lean` outside `.lake`. All six `@[widget_module]`s are `mk_rpc_widget%`: `ExprXRay/Widget.lean:184`, `IntervalInspector/Widget.lean:220`, `DistLens/Widget.lean:255,268`, `GraphScope/Widget.lean:100`, `HasseView/Widget.lean:102`.
  - All JS is ProofWidgets', embedded through `include_str` of the committed `widget/js` (map 3).
  - It imports `react`, `react/jsx-runtime` and `@leanprover/infoview`. QED64 ships `dist/infoview/react-jsx-runtime.production.min.js` and `esm-shims/` (verified with `ls`).
  - No npm runs anywhere in the build.
- **C6. The 4.34 port is uncommitted.** `widgets-v4.34` HEAD is `c812b91` with 63 modified or untracked paths (`git status --short`). Commit it before pinning (S0.1).

---

## 1. Layout of `qed64-showcase/` (its own git repo)

```
QED64.lock.json         pin: QED64 commit/promote, buildId, sha256 of every consumed file, toolchain pins
QED64-PIN               per-file sha256 of vendor/qed64 (re-verified by every script; lean4game lacks this)
package.json            "@playwright/test": "1.62.1" exact (reuses browser rev 1234 in ~/Library/Caches/ms-playwright)
scripts/  pin-qed64.mjs  assert-untouched.sh  serve.mjs  build-native.sh  stage-trees.mjs
          bake.sh  judge-bake.mjs  make-overlay.mjs  headless/{exact-header.mjs,rpc-probe.mjs,react-contract.mjs}
vendor/qed64/           git archive @QPIN (pipeline subset, public/workers, browser closure for M3)
lean/lakefile-append.lean   lean/examples/<pkg>.lean   lean/expect/<pkg>.json (frozen goldens)
gallery/                M2 wrapper (index.html, gallery.js, gallery.css, examples.json)
app/                    M3 (Option 2) Vite app, later
tests/ux/               Playwright suite
release/<BID>/          (gitignored) clonefile copy of dist/ + public/{runtime,profiles,snapshots}
work/                   (gitignored) mathlib4 clone, widgets-src, stage1, tree-slim, tree-fat, bake-*, raw/, logs/
out/                    (gitignored) overlay/snapshots/<dir>/, headless/, ux/<run-id>/
```

---

## 2. (A) Dependency model — Stage 0, "pin and scaffold" (about 1 h)

**S0.1 Pin the widget sources (our repo).** Commit the port in `$WS`, then record `WIDGETS_COMMIT`. Export an immutable source snapshot, so builds never read a live tree:
```
mkdir -p "$W/widgets-src" && git -C "$WS" archive "$WIDGETS_COMMIT" | tar -x -C "$W/widgets-src"
```

**S0.2 Precondition on QED64 (read-only).**
```
test "$(git -C "$Q" rev-parse HEAD)" = "$QPIN" && test -z "$(git -C "$Q" status --porcelain)"
```
Both were verified true today.

**S0.3 Vendor the sources** (read-only on `$Q`):
```
mkdir -p "$SC/vendor/qed64" && git -C "$Q" archive "$QPIN" \
  pipeline/snapshot pipeline/toolchain/artifact-paths.mjs pipeline/artifacts/olean-imports.mjs pipeline/artifacts/unpack.mjs \
  public/workers frontend/src/qed64-boot.ts frontend/src/resident-session.ts frontend/src/lsp-relay.ts \
  src/install/profiles.ts src/runtime/client.ts src/runtime/snapshots.ts \
  frontend/package.json frontend/package-lock.json frontend/vite.config.ts frontend/index.html \
| tar -x -C "$SC/vendor/qed64"
```
- `public/workers` is required. `resident-probe.mjs:16` imports `../../public/workers/lsp-frames.js`, and `:189` reads `lean.worker.js`.
- The vendored scripts resolve `<root>` to `vendor/qed64`, so their defaults (`node-runner.mjs:65-66`, `bake-snapshot.mjs:44,72`) land under our tree. We still pass absolute `--work` / `--out`.
- `preflight.mjs` runs in place from `$Q`. It is read-only without `--run-dir` (`tests/adversarial/preflight.mjs:144-152`).

**S0.4 Clone the release** (`scripts/pin-qed64.mjs pin`, using `cp -c` per file):
- `dist/` in full (17 MB).
- `public/runtime/runtime-manifest.json`, `runtime-manifest.$BID.json`, and the 10 chunks the manifest lists.
- `public/profiles/index.json`, `lean-core.manifest.json` plus 8 parts, and `mathlib-essential.manifest.json` plus 61 parts. The clone costs nothing on disk, and it keeps "Load exact imports" working.
- `public/snapshots/index.json`, `init.35c8c5f5419e0c33.snapz`, and `mathlib.8df0689fbc323eab.snapz` (the stock pair, used for the X2 rehearsal and as controls).

**S0.5 Chain of trust, as written into `QED64.lock.json` and checked by `pin-qed64.mjs verify`:**
1. Each git-tracked JSON equals `git -C "$Q" show $QPIN:<path>` byte for byte. These are `public/runtime/runtime-manifest.json`, `public/profiles/*.json` and `public/snapshots/index.json`. Tracking was verified with `git ls-files`; for example, the index sha256 `c9563408…` matches git.
2. The per-build runtime manifest is identical to the tracked one (map 1).
3. Every runtime chunk's sha256 equals the manifest's `chunks[].sha256`, and the reassembled `lean.wasm` sha256 equals `files["lean.wasm"].sha256` = `4b025db7729c5f89d686b5cc…` (`runtime-manifest.json`, verified).
4. Every profile part matches its manifest digest.
5. Every `.snapz` sha256 equals its index `digest`. Verified for init: `35c8c5f5…`.
6. `dist/` is untracked build output (`.gitignore:2`), so it cannot be anchored in git. Instead, record every file's sha256 and assert `grep -oh 'wasm64-[0-9a-f]\{16\}' dist/assets/*.js | sort -u` equals exactly `$BID` (map 1).
7. Toolchain pins:
   - native64: NATIVE-COMMIT and BUILT-COMMIT, plus sha256 of `native/stage1/bin/{lean,lake}`.
   - Docker image `qed64-toolchain:emsdk-6.0.5`, id `8b6698bbf474`.
   - Mathlib `5ed2965` (`$K/mathlib/MATHLIB-COMMIT`), ProofWidgets `106ff4f`.
   - Node v26.3.0; Playwright 1.62.1 / browser rev 1234.
   - `WIDGETS_COMMIT`.
8. Re-hash `vendor/qed64` against `QED64-PIN`.

**S0.6 `scripts/assert-untouched.sh`** is run at the end of every stage.
- Before each stage, record `HEAD` and `status --porcelain` for `$Q`, `wasm64-lean-kernel` and `wasm64-lean4game`. lean4game has the user's own pre-existing edits, so compare against the stamp rather than requiring a clean tree.
- After the stage, require them unchanged.
- Require `find <tree> -newer "$SC/out/.stage-stamp" -print -quit` to print nothing for `$Q`, `$K` and the kernel repo.

**Pin upgrade procedure:** `pin-qed64.mjs refresh` → new lock → rebake (S3) → rerun S4–S6. Snapshots are binary-paired; the worker refuses a mismatch with `SNAPSHOT_UNPAIRED` (`public/workers/lean.worker.js:1236-1246`).

**Go/no-go S0:** every verify line is OK, the bundle buildId equals `$BID`, and assert-untouched is clean.

---

## 3. Stage 1 — cheap experiments, cheapest first (about half a day, no builds)

| # | Cost | Experiment | Pass criterion | Decides |
|---|---|---|---|---|
| X1 | 5 min | `serve.mjs` (§7.1) serving `$R` on :5190. Then `node "$Q/tests/adversarial/preflight.mjs" --url http://localhost:5190/ --no-boot`, then the same without `--no-boot` | `PREFLIGHT OK buildId=wasm64-4b025db7729c5f89` | The server is correct |
| X2 | 10 min | Re-root rehearsal. `out/overlay/snapshots/rehearsal/` = clones of the stock init and mathlib snapz plus a copy of the stock index. Open `/?snapshots=snapshots/rehearsal` with `EXAMPLES.mathlib` | `qed64.status().phase=='ready'`, `header.mode` is `covered`/`exact`, no `SNAPSHOT_UNPAIRED`; the 2nd visit downloads 0 snapz bytes (OPFS key `name.digest16`, `src/runtime/snapshots.ts:60-71`) | Overlay mechanics work with zero bake |
| X3 | 10 min | M2 skeleton. `/showcase/` seeds `localStorage['qed64.buffer']` (`main.ts:340-342`), iframes `/?snapshots=snapshots/rehearsal`, then reaches `iframe.contentWindow.qed64` (`main.ts:403-410`) and calls `editor.getModel().setValue()` | `iframe.contentWindow.crossOriginIsolated===true`; seeded header picks the boot snapshots; switch-to-ready time recorded (ARCHITECTURE.md:434 cites ~322 ms for a covered header switch) | M2 is feasible |
| X4 | 20 min | Click paths on the stock pair. (a) Init-only `example (n : Nat) : n + 0 = n := by simp?`: click `span.link.pointer.dim.font-code` (core Try-this, `src/Lean/Meta/Hint.lean:62-84`). (b) `import Mathlib.Tactic.Widget.Conv` (in the essential pack, verified) with `conv?`: shift-click a goal subterm, then click "Generate conv" (`Mathlib/Tactic/Widget/Conv.lean:258,261,275`) | Text changes, re-elaboration is clean, `relay.stats.rangedChanges` unchanged. (b) also proves ProofWidgets JS import resolution, a library `@[server_rpc_method]` running from a baked region, and the MakeEditLink applyEdit path. Selectors get frozen into `tests/ux/selectors.json` | The riskiest UX assumption: lean4monaco `applyEdit` silently no-ops when `getVisibleLeanEditorsByUri` is empty (map 5, `infoview.js:303-320`) |
| X5 | 10 min | Memory knob contingency, from the same origin. Wrap `qed64.relay.makeSession` (a plain instance property: `lsp-relay.ts:76-90`; the bundle has `makeSession=e`, used again on reboot) so each new session gets `initialBytes = 3 GiB` (`resident-session.ts:118,128,187`; `readonly` is TS-only). Then `relay.restart({snapshots:['init','mathlib']})` | Telemetry shows a 3 GiB initial commit | Whether phase 2 can stay on Option 1 if the 2 GiB grow path crashes |
| X6 | 10 min | Vendored pipeline smoke. Run the stage1 copy (`cp -Rc "$Q/pipeline/toolchain/work/build/stage1/bin" "$W/stage1/bin"`, which includes `bin/package.json`) via `vendor/qed64/pipeline/snapshot/node-runner.mjs --artifact "$W/stage1" --work "$W/x6" -- /work/t.lean` on `#eval 1+1`. The artifact path contains a space | Prints `2`. buildId equals `$BID`. assert-untouched clean | Whether `$W` may contain spaces (node-runner mirrors the artifact path, `node-runner.mjs:110-114`). If it fails, use `W=/Users/fawadhaider/code/qed64-showcase-work` plus a symlink |
| X7 | 15 min | Docker identity and Lake reuse on the clone (§4, B1–B2) | `--no-build` succeeds for the essential set | The R5a/R5b path |
| X8 | 5 min | Re-home the closure scripts (`scratchpad/closure-agent-modlist/cl.py`) into `scripts/`. Emit exact phase-1 and phase-2 delta lists | Expected 39 missing non-widget modules for phase 1; 609 for all 8 (map 6) | Exact `EXPECTED-N` for the bake judge |
| X9 | 10 min, optional | Open :5190 in the Claude Browser pane | `crossOriginIsolated` is true | Whether agent-driven exploratory UX is possible in addition to Playwright |

**Go/no-go S1:**
- X1, X2, X3 and X6 must pass.
- If X4 fails, do not stop. Panel rendering is still showable, but click tests become known failures in QED64's shipped lean4monaco wiring, the owner gets a report, and M3 is raised in priority.
- X5 only matters for phase 2.

---

## 4. (B) Stage 2 — native64 build in Docker, writing only to `$W` (about 1–2 h machine time for phase 1)

**B0. Clone the workspace.** APFS clone; new inodes, so the nlink=5 sources are never shared:
```
cp -cpR "$K/mathlib/mathlib4" "$W/mathlib4"
stat -f '%i %l' "$W/mathlib4/.lake/build/lib/lean/Mathlib/Order/Basic.olean"   # new inode, nlink 1
```

**Docker template.** It mirrors `mathlib-tree.sh:74-80`: same container path, so Lake traces still match. `--network none` plus `LAKE_NO_CACHE` mean no Reservoir barrel fetch and no ProofWidgets `npm` (`proofwidgets/lakefile.lean:54-79`).
```
run() { docker run --rm --network none \
  -e LEAN_CC=/usr/bin/gcc -e LEAN_NUM_THREADS="${T:-6}" -e LAKE_NO_CACHE=1 -e LAKE_ARTIFACT_CACHE=false \
  -v "$K/native:/native:ro" -v "$W/mathlib4:/work/mathlib4" -v "$W/widgets-src:/work/mathlib4/widgets:ro" \
  -w /work/mathlib4 qed64-toolchain:emsdk-6.0.5 \
  bash -lc "export PATH=/native/stage1/bin:\$PATH; git config --global --add safe.directory '*'; $1"; }
```
`LEAN_PATH` is not set by hand. Lake computes it from the clone's `.lake/build/lib/lean` plus each `.lake/packages/*/.lake/build/lib/lean`; core comes from `/native/stage1/lib/lean`.

**B1. Identity check.**
```
run 'lean --version; lake --version; which lean lake'
```
Expect `4.34.0, wasm64-unknown-emscripten`, `Lake version 5.0.0-src`, and `/native/stage1/bin/*`.

**B2. Reuse gate (X7).**
```
run 'lake build --no-build -q Mathlib.Order.Basic Mathlib.Tactic ProofWidgets.Component.HtmlDisplay'
```
Must exit 0. Any non-zero exit means stop; never let Lake rebuild about 3,500 modules. `--no-build` is at `src/lake/Lake/CLI/Main.lean:60,283`; the exact exit code is unknown, so treat any non-zero as failure.

**B3. Phase-1 Mathlib/ProofWidgets delta** (Lake applies `mathlibLeanOptions`, `lakefile.lean:76-79`):
```
T=6 run 'lake build -q ProofWidgets.Component.Panel.SelectionPanel Mathlib.Combinatorics.Enumerative.Catalan.Tree Mathlib.Combinatorics.SimpleGraph.Basic Mathlib.Combinatorics.SimpleGraph.Connectivity.Finite Mathlib.Combinatorics.SimpleGraph.CycleGraph Mathlib.Combinatorics.SimpleGraph.Hasse' 2>&1 | tee "$W/logs/b3-delta7.log"
```
SelectionPanel must be rebuilt: the existing one is a GMP barrel olean (map 3/6).

**B4. Widget libraries (R5a).** Append `lean/lakefile-append.lean` to the clone's lakefile only:
```
lean_lib ChartKit where srcDir := "widgets/chart-kit"
lean_lib ExprXRay where srcDir := "widgets/expr-xray"
… (one per package, plus LeanWidgetKit for phase 2)
```
Rerun B2 to show the edit did not invalidate Mathlib traces. Then:
```
T=6 run 'lake build -q ChartKit ExprXRay GraphScope HasseView IntervalInspector SimpLens TreeScope' 2>&1 | tee "$W/logs/b4-widgets7.log"
```
- Widget lakefiles set no `leanOptions` (map 3), so default options reproduce their build.
- Do not build the `*Tests` libraries into the release tree. `ClickE2E` calls `processHeader`.
- **Fallback R5b**, if B2 fails after the append: drop the append and compile the widgets with raw `lean <src> -o … -i … --root …` in topological order, with `LEAN_PATH=$(run 'lake env printenv LEAN_PATH'):/out` (pattern: `wasm64-lean4game/wasm/scripts/compile-pkg.py`, copied into our repo, never run in place).

**Memory and ordering rules (8 GB VM, 7.65 GiB usable):**
- `T=6` for phase 1, which the original 6-thread Mathlib build proved safe (`mathlib-tree.sh:51`).
- `T=4` for DistLens. On rc 137 (a silent OOM kill), rerun with `T=4`, then `T=2`. Lake resumes incrementally.
- Never run Docker concurrently with a bake or a browser lane (`RELEASE-PIPELINE.md:101-103`).

**Go/no-go S2:**
- Every olean staged in S3 passes the header gate: `[0:5]=='olean'`, `byte5∈{2,3}`, `byte6==0` (no GMP), and bytes 40..80 all zero (empty githash). The format is at `wasm64-lean-kernel/src/library/module.cpp:109-146`.
- B2 is green both before and after the append.
- assert-untouched is clean.

---

## 5. (C) Stage 3 — trees, bake, pairing, overlay (about 1 h)

**C1. Slim bake tree.** Start from the exact tree that produced the served `mathlib` region (5,004 `.olean`, verified):
```
cp -Rc "$Q/work/bump-51/slim/lib-tree-slim" "$W/tree-slim"
node "$SC/scripts/stage-trees.mjs" --clone "$W/mathlib4" --into "$W/tree-slim" --slim \
  --roots QED64.Essential,ChartKit,ExprXRay,GraphScope,HasseView,IntervalInspector,SimpLens,TreeScope
```
`stage-trees.mjs` does the following:
- Computes the closure with the vendored `olean-imports.mjs`.
- Computes delta = closure minus modules present in the tree.
- Clones every facet except `*.olean.private` (`.olean`, `.olean.server`, `.ir`, `.ir.sig`) with `fs.copyFileSync(…, COPYFILE_FICLONE)`.

Its gates:
1. The header gate on every delta olean.
2. Byte identity, for every closure module already in the tree, between the tree and the clone. Compare full files for Mathlib, ProofWidgets, Batteries, Aesop and Qq, and bytes 80 onward for core, since headers differ only in githash (`native-d.log:279`). A mismatch means the delta was compiled against different bytes: STOP.
3. Disjointness with `$K/mathlib/essential-modules.txt` (the `import-packs.sh:212-223` pattern).
4. Closure completeness.
5. `node vendor/qed64/pipeline/artifacts/olean-imports.mjs --audit "$W/tree-slim"` must report no new `import all` edges (`SERVER-SLIM-REBAKE.md`).
6. It writes `EXPECTED-N` = 5,004 + |delta| + |own|.

**C2. Fat tree** (Demo replay and debugging only):
```
cp -Rc "$Q/work/lib-tree" "$W/tree-fat"
```
Then run the same `stage-trees.mjs` without `--slim`.

**C3. Seed the bake output** with the served init, so one directory carries the whole pairing. The bake's sibling check accepts a sibling with the same runtime (`bake-snapshot.mjs:53-66`).
```
mkdir -p "$W/bake-out" && cp -c "$R/public/snapshots/init.35c8c5f5419e0c33.snapz" "$W/bake-out/"
```
`index.json` = `{"schema":"qed64.snapshot-index/v1","snapshots":[<init entry verbatim from $R/public/snapshots/index.json>]}`.

**C4. Bake phase 1** (`scripts/bake.sh`; every path absolute; never with `$Q` as root):
```
QED64_ALLOW_LEGACY_IMPORTS=1 node --stack-size=8192 "$SC/vendor/qed64/pipeline/snapshot/bake-snapshot.mjs" \
  --name widgets --artifact "$W/stage1" --lib "$W/tree-slim" --reserve 3758096384 \
  --work "$W/bake-work" --out "$W/bake-out" \
  --probe "$(printf 'import QED64.Essential\nimport ChartKit\nimport ExprXRay\nimport GraphScope\nimport HasseView\nimport IntervalInspector\nimport SimpLens\nimport TreeScope\n#check (2 + 2 : Nat)')" \
  2>&1 | tee "$W/logs/bake-widgets7.log"
```
- Write the probe's import list to `BAKE-KEY.txt`. It is the exact key E1 uses.
- Expect at least about 7 minutes; the reaper waits for 300 s quiet plus 120 s stable (`bake-snapshot.mjs:101-134`).
- The bake runs on the host under Node v26.3.0, not in Docker.

**C5. Judge the bake ourselves.** The bake does not fail on elaboration errors (`bake-snapshot.mjs:122-133`; `Frontend.lean:410-416`). `judge-bake.mjs` requires all of:
- `grep -nE ': error|PANIC|ABORT:|uncaught|RuntimeError'` finds nothing.
- `Loading N modules` with N == `EXPECTED-N`, and N/N reached.
- A `baked …/widgets.<d16>.snapz … runtime wasm64-4b025db7729c5f89` line.
- Raw bytes in [1.13, 1.30] GB. The estimate is the stock region of 1,127,272,685 bytes plus the phase-1 delta and widgets.

If the compactor reserve is exhausted, rerun with 4 GiB.

**C6. Pairing checks:**
- `buildIdOf("$W/stage1")` == `$BID`.
- Every index entry has `runtime == $BID`.
- `sha256(file) == digest`; `size == transfer`; `gunzip -c | wc -c == bytes`.
- Then the live check: `node "$Q/tests/adversarial/preflight.mjs" --url 'http://localhost:5190/?snapshots=snapshots/widgets7'`, first with `--no-boot`, then with a boot.

**C7. Overlay for the stock page.** `make-overlay.mjs` writes `out/overlay/snapshots/widgets7/index.json` with exactly two entries:
- `init`, copied verbatim.
- The `widgets` entry renamed to `"mathlib"`. It keeps `url:"/snapshots/widgets.<d16>.snapz"`, which the page re-roots to `/snapshots/widgets7/…` (`qed64-boot.ts:96-106`).

Both `.snapz` files are cloned beside the index. This avoids the untested `/./snapshots/` trick. The stock page loads only these two names (`resident-session.ts:85,127`; `main.ts:361,386`). The OPFS key becomes `mathlib.<d16>` and never collides with the stock key.

**Fallback ordering ("widgets-lite"):**
- If the SimpleGraph/Catalan delta (B3) or the phase-1 bake fails, bake **lite-5** = {ChartKit, SimpLens, IntervalInspector, HasseView, ExprXRay}. Its only delta is the SelectionPanel rebuild; HtmlDisplay already exists natively.
- Then add TreeScope (2 Catalan modules), then GraphScope (35 modules).
- DistLens is always phase 2 (§9).
- A non-Mathlib "lite region named init" is rejected for the stock page. Its `import Lean` closure would sit in a 256 MiB commit (`resident-session.ts:94`). It is only sensible in M3.

**Go/no-go S3:** the judge is green, pairing is green, and preflight OK.

---

## 6. (E) Stage 4 — headless verification before any browser (about 1 day, mostly writing E3)

Raw snapshots are derived from served artifacts:
```
gunzip -c "$R/public/snapshots/init.35c8c5f5419e0c33.snapz" > "$W/raw/init.snap"
```
Assert 122,364,117 bytes, equal to the index `bytes`. The stock `mathlib.snap` is derived the same way (1,127,272,685 bytes) for controls.

**E1. Examples on the exact key, through the worker's compile path.** `exact-header.mjs` replaces each example's import lines with `BAKE-KEY.txt` (because of C2). Then:
```
node --stack-size=8192 "$SC/vendor/qed64/pipeline/snapshot/snapshot-probe.mjs" --via-mem \
  --artifact "$W/stage1" --lib "$W/tree-slim" --snap "$W/bake-work/widgets.snap" \
  --probe-file "$W/headless/<pkg>.exact.lean" --budget-ms 120000 --dump-messages
```
- It must print `SNAPSHOT PROBE PASS` (`snapshot-probe.mjs:201-223`). `--init-flags` defaults to 1, the same as the worker (`:180` vs `lean.worker.js:1367`).
- A budget overrun means a silent re-import, i.e. a wrong key.
- Designed-error click blocks (`-- @ux begin-click … end-click`) are stripped here. Their expected post-click texts are compiled as separate files here.

**E2. Each Demo, verbatim, run by the wasm runtime.** This executes every `#guard` / `#guard_msgs` inside wasm, catching interpreter, Float and 1 MB-stack issues. No collision is possible: a Demo's own header does not import its Demo module.
```
node "$SC/vendor/qed64/pipeline/snapshot/supervised-run.mjs" --target "$W/run/<pkg>/Demo.olean" \
  --quiet-ms 60000 --stable-ms 30000 -- --artifact "$W/stage1" --lib "$W/tree-fat" \
  --work "$W/run/<pkg>" -- -o /work/Demo.olean /work/Demo.lean
```
- Copy `Demo.lean` from `widgets-src` into `$W/run/<pkg>` first.
- `supervised-run` fails on `: error|PANIC|ABORT|RuntimeError` (`supervised-run.mjs:83-93`).
- Alternative: `snapshot-probe --fresh-import --lib "$W/tree-fat" --budget-ms 1800000`.
- Run serially in the background. This blocks the final sign-off, not M1.

**E3. FileWorker and RPC probe** (`scripts/headless/rpc-probe.mjs`). It is a copy adapted from vendored `resident-probe.mjs` and `header-switch-probe.mjs`:
1. Boot `--worker` and load `init.snap` plus `widgets.snap` via `_lean_wasm_load_snapshot_mem` (`header-switch-probe.mjs:289-306`).
2. Send `initialize` and `didOpen` with the browser header (`import Mathlib` / `import <Pkg>`).
3. Assert that `$/qed64/headerStatus.mode=="covered"` (`FileWorker.lean:433-436`). Then wait for diagnostics.
4. Call `$/lean/rpc/connect`. For each `@ux cursor`, call `Lean.Widget.getWidgets`, then `getWidgetSource` for every hash (JS non-empty and containing `@leanprover/infoview`).
5. For `mk_rpc_widget%` panels, call the panel's RPC method with the stored props → Html.
6. Extract the `MakeEditLink` edits, apply them UTF-16-correctly, send a full-text `didChange`, and require zero severity-1 diagnostics. This is the wasm twin of `*Tests/ClickE2E.lean`.
7. Output `out/headless/<pkg>.rpc.json`: the panel signature (tag counts, texts, link texts, edit texts).
8. Compare with the native goldens in `$WS/showcase/dumps/<pkg>.json` by id. For example: `hasse-view/powerset-cube` has rect 8, line 12, text 16; `chart-kit/diceChart` has rect 12, line 24, text 15; `interval-inspector/union_eq_real_with_suggestions` has circle 6, line 4, rect 3 (counted today).
9. Freeze the results into `lean/expect/<pkg>.json`.

Controls:
- **Positive:** the stock `mathlib.snap` with the X4 `conv?` document.
- **Negative:** `import HasseView` alone with only init loaded must give `refused`, `missing=[HasseView]`.

**E3b. React contract.** Convert the E3 Html to the showcase dump schema and run the dev-React checks from `$WS/showcase/verify.mjs`, via a parameterized copy in our repo. Any React error or warning on a wasm-produced panel fails.

**Go/no-go S4:** E1 is green for all seven packages; E3 shows every panel's JS retrievable, every RPC method answering, and every simulated click re-elaborating clean; E3b is green. E2 must be green before final sign-off.

---

## 7. (D) Stages 5, 6 and 8 — the pages

### 7.1 Local server (`scripts/serve.mjs`; Node `http`, no dependencies, port 5190)

Routes, first match wins:
1. `/showcase/` → `$SC/gallery/`
2. `/snapshots/{widgets7,widgets8,rehearsal}/` → `$SC/out/overlay/snapshots/<dir>/`
3. `/runtime/`, `/profiles/`, `/snapshots/` → `$R/public/…`
4. Everything else → `$R/dist/` (`/` → `index.html`)

The `?snapshots=snapshots/widgets7` form keeps parity with production prefix routing (`infra/worker.js:11,39-48`).

Every response:
- Sends `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp`, `Cross-Origin-Resource-Policy: same-origin` (`public/_headers:6-9`).
- Is streamed with `createReadStream` and carries `Content-Length`. HEAD is answered.
- Never carries `Content-Encoding`; the worker refuses transformed chunks (`lean.worker.js:594-596`).
- Missing files get a 404, never an SPA fallback (HARDENING #32).
- MIME types: `.wasm` → `application/wasm`; `.snapz` and `.part-N` → `application/octet-stream`.
- `Cache-Control` mirrors production: immutable for digest-named files, `no-cache` for `index.json` and `runtime-manifest*.json` (`infra/worker.js:13-35`).
- Requests are logged with byte counts, for metrics.
- An optional env knob `CHAOS=<regex>:<afterBytes>:<times>` cuts responses mid-stream, for C11.

No HTTP Range is needed: the workers never send Range (grep). No framing restriction exists (`_headers`, `dist/index.html`).

### 7.2 M1 (Stage 5) — the stock page plus overlay (about half a day)

1. Open `http://localhost:5190/?snapshots=snapshots/widgets7`. `?runtime=` is unnecessary, because the bundle pins `$BID` (`qed64-boot.ts:66-79`).
2. Paste each example. Headers are `import Mathlib` / `import <Pkg>` (D2).
3. Examples are the map-6 snippets, wrapped in `namespace Showcase.<Pkg>`. This avoids "already declared" collision notes in covered mode (`lsp-front-door.js:73,418-426`). The Demos are themselves namespaced (`ChartKit/Demo.lean:16` … `TreeScope/Demo.lean:18`, verified).
4. Drop the redundant GraphScope `pathGraph` instance: `GraphScope.Demo`'s global instance is in scope.

**Go/no-go S5:** all seven panels render in the real InfoView, with signatures equal to `lean/expect`; X4-style clicks apply.

### 7.3 M2 (Stage 6) — gallery wrapper (Option 1+; zero npm, zero QED64 change; about 1–2 days)

`/showcase/` has a left rail of eight cards (name, one line, static preview linked from `$WS/showcase/site`) and an iframe of `/?snapshots=snapshots/widgets7`.

**Before load:**
1. Pairing preflight in JS: the overlay index has `runtime==BID`; HEAD each `.snapz` is 200, `content-length==transfer`, and not HTML. This mirrors lean4game `game-boot.ts:113-145`.
2. Save any existing `qed64.buffer` under `qed64-showcase:saved`. Seed `qed64.buffer` with the selected example (the initial document is a boot input: `main.ts:335-342`).
3. Set the iframe `src`.

**After `status().phase==='ready'`:** `setPosition` to the example's `@ux cursor`, then `focus`.

**Switching examples:** `contentWindow.qed64.editor.getModel().setValue(text)`, wait for ready at an advanced version, then set the cursor. Deep links use our own hash (`/showcase/#hasse-view`).

**Errors:** a friendly card replaces QED64's late `snapshot 'init' failed to load` (`resident-session.ts:192-194`).

The user's real buffer is not at risk: localhost:5190 is a different origin from production.

### 7.4 M3 (Stage 8) — Option 2, the vendored app (feasible; build after M2; about 3–5 days)

- **Precedent:** lean4game vendors the same ten files (`scripts/sync-qed64.sh:30-33`). Exact dependency versions come from the vendored `frontend/package-lock.json` via `npm ci` in `$SC/app` (network needed; ours only): lean4monaco 1.1.16 and @leanprover/infoview 0.11.1.
- **Build config:** `define __QED64_BUILD_ID__=BID`; static-copy `/infoview/*` and `/workers/*` as in `frontend/vite.config.ts:47-61`. `root`, `cacheDir` and `node_modules` all live in `$SC/app`.
- **Policy:**
  - `snapshotsFor: () => ['widgets']`, with no init; lean4game does the same (`game-boot.ts:247-271`).
  - `initialBytesFor` = max(2 GiB, roundUp256MiB(region × 1.1 + 1 GiB)).
  - `maximumBytes` 6 GiB (`resident-session.ts:27-40,101`).
  - Our own `installArtifacts` with `installed=new Map()`, so no 120 MB core pack (`game-boot.ts:147-182`).
- **Editor:** documents are opened with `editor.start(el, <one folder>/Example.lean, text)` (lean4game lesson 6a). A status sink that publishes on change only (lesson 6b), and `pagehide → relay.unload()` (`main.ts:401`).
- **Why it is the durable form:** it does not depend on the dev-only overrides, it controls memory, and it can be deployed as our own Worker.

### 7.5 Production (owner-gated; not part of local completion)

- **Option 1 / M2:** additive R2 objects under `snapshots/widgets7/` in QED64's bucket. This needs the owner's explicit consent, since it is QED64's deployment.
- **M3:** our own Worker following the lean4game `wrangler.toml` / `infra/worker.js` pattern.

---

## 8. (F) Exhaustive UX test plan (Playwright 1.62.1, browser rev 1234)

### 8.1 Harness (`tests/ux/lib/qed64.mjs`)

**Launch and lanes:**
- Launch: `chromium.launch({args:['--enable-features=SharedArrayBuffer']})` (`buffer-probe.cjs:14`).
- Projects: headless-shell (default), `channel:'chromium'` (new headless), and one headed Chrome-for-Testing sign-off run.
- `workers: 1`, `retries: 0`, `trace: 'retain-on-failure'`.
- Cooldown before every boot: at least 6 GB free+inactive and no `chrome-headless-shell` processes (`docs/TESTING.md:85-90`; `node "$Q/tests/adversarial/harness.mjs" cooldown` is read-only).
- Never run alongside Docker or a bake.

**Oracles:**
- `qed64.status()` (`main.ts:403-410`).
- A diagnostics and RPC tap that wraps `qed64.relay.toClient` on the instance. It works because `s.onLsp` calls `this.toClient` dynamically (`lsp-relay.ts:137,218`). Do NOT use buffer-probe's markers: the Vite-only import silently yields "clean" on `dist` (`buffer-probe.cjs:32-33`).
- `relay.stats` deltas, and the RPC replies captured by the tap.

**InfoView access:**
- `page.frameLocator('#infoview iframe')` (`infowebview.js:39-75`).
- HtmlDisplayPanel is `details > summary.mv2.pointer` with text "HTML Display" (ProofWidgets `widget/js/htmlDisplayPanel.js`).
- MakeEditLink is `a.link.pointer.dim` (`makeEditLink.js`).
- Core Try-this is `span.link.pointer.dim.font-code`.
- Settled = no `summary[class*=gold]` and no `div.error` containing "Error updating" (map 5: the class is concatenated without a space).

**Assertions:**
- **Render:** the panel's SVG present plus a signature (tag multiset and texts) equal to `lean/expect/<pkg>.json`.
- **Click:**
  1. Capture the text before.
  2. Click.
  3. Poll until the text changes, and require the diff to equal the frozen edit (range plus newText; a zero-width insertion where designed).
  4. Wait for phase ready at an advanced version, stable for 1 s.
  5. Require the latest `publishDiagnostics` for that version to have zero severity-1 entries, or the exact designed set.
  6. Require `relay.stats` to show workerDeaths=0, reboots=0 and rangedChanges unchanged.
- **Console:** fail on any `pageerror`, `page.on('crash')`, or `console.error` matching `/Minified React error|React|No connection to Lean|RPC|SNAPSHOT_UNPAIRED/`. The allowlist starts empty.

**Artifacts:** `out/ux/<run>/{metrics.json,screens/,traces/}`.

### 8.2 Per-widget tests

Two lanes:
- **L-switch:** one boot; all widgets via the gallery's `setValue`.
- **L-isolated:** a warm boot per widget.

Timeouts: panel 30 s after ready; elaboration 120 s (DistLens 300 s).

| ID | Package | Panels to assert (cursor on each command) | Interactions | Expected after |
|---|---|---|---|---|
| W1 | ChartKit | `#chart diceChart` = dump `diceChart`; `#chart weekChart` has 5 tick labels Mon–Fri and value labels | Toggle the details summary (collapse, then expand) | `#guard` lines give 0 errors; no edit (no interactivity documented) |
| W2 | HasseView | `#hasse (Finset (Fin 3))` = `powerset-cube` (8 rect, 12 line); `#hasse Bowtie highlight [1,2]` = `bowtie-non-lattice` caption | Click each link kind in the candidate list (`README.md:43-48`) | `example : … := by decide` inserted after the command; equals the E3 text; 0 errors |
| W3 | IntervalInspector | `#interval_inspect` union = `union_eq_real_with_suggestions`; subset mismatch shaded = `subset_mismatch_shaded_real`; `interval_inspect?` panel with suggestions | (a) Click the suggestion `exact Set.Ioc_union_Ioc_eq_Ioc h₁ h₂`; (b) shift-click hypothesis `h₁` (`README.md:114-116`) | (a) Tactic replaced; pre-click designed "unsolved goals" changes to 0 errors; (b) panel signature changes to the hypothesis view |
| W4 | SimpLens | "Simp Lens — N rewrites", "✓ goal closed", "minimal call: simp only […]" = `target_arith_multi_frame` | (a) Hover a lemma in InteractiveCode, which shows a popup (`README.md:42`); (b) click "Try this: simp only […]"; (c) the lightbulb/code action offers the same edit (`README.md:24-25`) | `simp_lens` replaced by the minimal call (location clause kept); 0 errors |
| W5 | ExprXRay | `#xray (1+1 : Nat)` = `xray-1plus1-nat` (23 details); `#xray_diff` ranks the Decidable instance first | (a) Click summaries, so `open` toggles; (b) 1 shift-click selection in the goal, then the panel x-rays the subterm; (c) a 2nd selection gives compare mode (`README.md:136-141`) | No edit; 0 errors; panel signatures for 0, 1 and 2 selections are frozen |
| W6 | TreeScope | `rbSample` (red/black tones, `bh=` sublabels, caption), `#tree_evolve` frame count, `#html renderForest (catalanGallery 4)` = `forest-catalan-gallery-n4` | None (`README.md:222-224`) | Light and dark: SVG colours follow `var(--vscode-…)` (`README.md:122`) |
| W7 | GraphScope | `cycleGraph 5` (5 circles, 5 lines, "not bipartite" plus witness), `completeGraph (Fin 5)`, walk overlay, `layout layered` | Click an edge, a vertex, and the components line (`README.md:37-44`) | `Adj` / `degree` / `Connected` examples inserted after the command with zero width; 0 errors |
| W8 | DistLens (phase 2) | `#dist die` = `die6_dist_panel` (6 rects, labels 1/6); `#dist_film`; `#chain weather …` | Click a weight suggestion | `example … := by … pmf_num` inserted; 0 errors within 300 s |

### 8.3 Cross-cutting tests

| ID | Scenario | Assertion / metric |
|---|---|---|
| C1 | Cold boot: fresh context, empty OPFS and HTTP cache | Time to ready, per-phase timeline from status transitions, bytes per prefix; budget ≤180 s locally |
| C2 | Warm boot: persistent `userDataDir` in `out/ux/profiles/warm` | ≤20 s; 0 `.snapz` bytes; only revalidations |
| C3 | Memory | Renderer RSS (`ps`, summed per process) at ready and after all 8 widgets; the wasm heap from `relay.session.lean.request('telemetry')`; note whether the heap grew after region load. Fail at ≥10.5 GB (macOS kill seen at about 11 GB, `RESIDENT-WORKER-PLAN.md:173-175`) |
| C4 | Switching: 8 sequential, then a storm of 8 in 2 s | Final panel correct; no stale panel; no "No connection to Lean"; workerDeaths 0 |
| C5 | Edit, break, fix | Insert a typo: error diagnostic, panel degrades without a page error; fix it: panel returns with the same signature |
| C6 | Refused header: `import HasseView` with no `Mathlib` line | `headerRefused`, `missing=['HasseView']`, no widen (`main.ts:381-382`); the gallery never emits this |
| C7 | Unknown module `import Mathlib.NotAModule` | Refused, with the stock diagnostic text (`FileWorker.lean:451`) |
| C8 | Bad overlay `?snapshots=snapshots/nope` | Stock: boot-failure card. Gallery: friendly preflight error before navigation |
| C9 | Unpaired fixture (`runtime` altered) | Gallery refuses; the stock page surfaces `SNAPSHOT_UNPAIRED` |
| C10 | Reload storm: 5 reloads in 15 s | No `crash`; ready at the end; pagehide unload works |
| C11 | Network cut mid-`.snapz` (`CHAOS`) | Failure is surfaced; a reload recovers to ready |
| C12 | Offline warm reload: Playwright aborts `/snapshots/widgets7/*` | Boots from OPFS |
| C13 | Visual: each widget in light and dark (`colorScheme`) at 1440×900; gallery at 390×844 | Baseline approval after the first green run; then `maxDiffPixelRatio` 0.01 |
| C14 | Console hygiene across the whole suite | 0 page errors and 0 matching `console.error` lines |
| C15 | Stock regression: `EXAMPLES.mathlib` text on the superset | Ready, 0 errors |
| C16 | No collision offer for gallery examples | `status().collision===null`; `#action` hidden. If forced, "Load exact imports" degrades gracefully (`resident-session.ts:209-224`) |
| C17 | Gallery accessibility | Tab/Enter navigation, aria labels, iframe title |
| C18 | Two tabs at once | RSS is recorded only |
| C19 | Headed Chrome for Testing sign-off | Manual exploratory checklist (and X9 pane if available) |

---

## 9. Stage 7 — DistLens (phase 2)

1. **Build:**
   ```
   T=4 run 'lake build -q DistLens LeanWidgetKit'
   ```
   This adds 404 modules to compile. The 168 Mathlib plus 1 ProofWidgets modules already exist natively in the clone (map 6).
2. **Stage and bake:** stage again into a fresh `tree-slim`. Bake `widgets8` with the probe plus `import DistLens`, `--reserve 4294967296`.
   - Judge range: raw bytes [1.35, 1.75] GB; N = 5,004 + 609 + own.
   - The compactor is close to its limit: a fat tree already overflows (`SERVER-SLIM-REBAKE.md:100-105`). Watch the first bake.
3. **Run S4 and S6 for W8,** plus C1–C3 three times cold.
4. **Memory gate:**
   - Phase 2 stays on Option 1 only if the heap stays under the 2 GiB commit or grows without a crash in 3 of 3 cold boots, with RSS at most 10.5 GB.
   - Otherwise use the X5 wrapper in the gallery (contingency), or ship DistLens only in M3.

---

## 10. (G) Risks and go/no-go checkpoints

| Risk | Mitigation | Detection |
|---|---|---|
| A write into a read-only tree: bake/runner defaults (`bake-snapshot.mjs:44,72`; `node-runner.mjs:65-66`), Vite dev's `.vite` cache, or a hard link | Vendored copies only; absolute `--work`/`--out`; `cp -c` only; own server, never `npm run dev`/`serve-dist` | `assert-untouched.sh` after every stage |
| applyEdit no-ops (never tested in QED64; map 5) | X4 first; text-change assertions | X4 / W2–W8 |
| GMP barrel olean leaks (151 in the clone; SelectionPanel) | Header gate in S2/S3; `--network none` | stage-trees gate |
| Lake rebuilds everything (identity mismatch) | B2 `--no-build` gate before and after the append; R5b fallback | B2 |
| Docker OOM (rc 137, silent) | T=6, then 4, then 2; one Docker job at a time | Exit code and logs |
| Bake passes despite errors | `judge-bake.mjs` with N == EXPECTED-N | C5 |
| Superset exercises the 2 GiB grow path (`resident-session.ts:87-94`) | Phase 1 ≈ stock size (+~70 MB); X5 wrapper or M3 policy for phase 2 | C3 |
| Covered-mode name collisions | `namespace Showcase.<Pkg>` | C16, E3 |
| Interpreter 1 MB stack / slow `evalExpr` gates (HasseView, GraphScope) | Trimmed examples, not full Demos, in the gallery; E2 runs the full Demos headless | E2 timings |
| Delta compiled against bytes that differ from the served ones | Byte-identity gate in S3 | stage-trees gate |
| Dev-only overrides removed upstream (`qed64-boot.ts:53,71,96`) | Our pinned release copy is immune; M3 removes the dependency | Re-pin only |
| Runtime promote invalidates the bake | Pin upgrade procedure (§2) | `pin-qed64 verify`, preflight |
| OPFS quota fills with stale raw regions (1.2–1.6 GB per bake) | Delete `out/ux/profiles/*` per bake iteration | C2 |
| Path with spaces | X6 decides `$W` | X6 |

| Stage | GO when | NO-GO action |
|---|---|---|
| S0 pin | All hashes verify; buildId == BID; untouched | Stop; re-pin |
| S1 experiments | X1, X2, X3, X6 pass | Fix server or wrapper; X4 failure re-scopes clicks and raises M3 |
| S2 build | B1, B2 green; header gate green | R5b; T=4; lite-5 |
| S3 bake | Judge, pairing and preflight green | Raise reserve; lite-5 |
| S4 headless | E1, E3, E3b green (E2 before sign-off) | Debug in Node, not the browser |
| S5 M1 | 7 panels plus clicks | Selector discovery; report upstream |
| S6 M2 and UX | W1–W7 plus C1–C19 green | Fix the wrapper or examples |
| S7 DistLens | Memory gate | X5 or M3-only |
| S8 M3 | Same suite green on `app/` | Keep M2 as the deliverable |

---

## 11. Open questions, in experiment order

1. Re-root plus OPFS reuse on our server (X2).
2. Iframe cross-origin isolation (X3).
3. lean4monaco `applyEdit` visible-editor lookup, ProofWidgets JS import resolution, and library RPC from a baked region (X4).
4. Whether the `makeSession` wrapper is effective (X5).
5. Spaces in the node-runner path (X6).
6. Lake reuse after the lakefile append, and `--no-build`'s exit code (X7).
7. Exact delta and EXPECTED-N; whether any of the 72 skipped deprecated shims are now needed (X8).
8. Native compile time and RSS for the widgets and for DistLens (S2).
9. Bake peak RSS, wall time, region size, and compactor headroom (S3).
10. IR availability for `evalExpr` on delta, Mathlib and widget definitions; interpreted recursion depth (E1–E3).
11. Heap high-water versus the 2 GiB commit, renderer RSS, and cold/warm times with the superset (C1–C3).
12. Panel DOM selectors, and whether QED64's page follows `prefers-color-scheme` (S5/C13).
13. DistLens memory under the stock commit (S7).
14. Owner decisions: commit the port (S0.1); any production publish (§7.5).

Not needed, and therefore not tested: the `/./snapshots/` init-reuse trick (init is cloned into the overlay instead) and cross-origin snapshot URLs.