# Building the showcase from source

There are two paths. Most people need only the first.

* **Light path: serve and test.** QED64's page is built from source. QED64's binaries and our widget overlays are
  fetched by content hash. No kernel build, no Docker, no QED64 build. About 10 minutes plus a 2.4 GB download.
* **Heavy path: rebuild the overlays.** The kernel fork's native toolchain compiles the widget oleans, the trees are
  staged, and the pinned wasm runtime bakes the snapshot regions. Then come the headless verifiers, the gallery and the
  UX suite. This takes hours and a large Mac (it was built on a 36 GB machine, and the bakes peak at about 11 GB RSS).

How QED64 itself is consumed (submodule, content-addressed binaries, toolchain) is described in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Light path

Prerequisites: git, Node 26 (the lock records v26.3.0; another 26.x works and `verify` reports it as a DRIFT) with npm,
and network access to GitHub, npm and an artifact origin. For the UX suite you also need Playwright's Chromium and a
machine with 16 GB of RAM or more. macOS or Linux.

```
git clone --recursive https://github.com/FawadHa1der/lean-widgets.git
cd lean-widgets/qed64-showcase
cp .env.example .env.local        # optional: QED64_SHOWCASE_WORK (default ~/.cache/lean-widgets/qed64-showcase-work), origins
scripts/showcase.sh bootstrap --origin <showcase origin> [--qed64-origin https://qed64.fawadworkaddress.workers.dev]
scripts/showcase.sh gallery       # the static gate (check-gallery + sim-gallery)
scripts/showcase.sh serve         # http://localhost:5190/showcase/
npx playwright install chromium chromium-headless-shell && scripts/showcase.sh ux   # the full UX suite (34 tests)
```

`bootstrap` runs these steps. Each one checks its result against `pins/<id>/QED64.lock.json`, and nothing that does not
match is installed:

1. **QED64's sources.** `git submodule update --init` if the clone was not recursive. `--pin <id>` for a staged pin
   adds its worktree under `$W/qed64-pins/<id>`.
2. `npm ci` (Playwright 1.62.1) if `node_modules/` is missing.
3. **Widget sources.** `$W/widgets-src` = `git archive <lock WIDGETS_COMMIT> packages/` (`scripts/export-widgets.mjs`).
4. **The page.** `scripts/build-shell.mjs` runs QED64's own `npm ci --prefix frontend && npm run build:site` in the
   submodule and installs `release/<id>/dist` only if all 58 files are byte-identical to the lock.
5. **The binaries.** `scripts/fetch-artifacts.mjs` takes the tracked manifests from git and fetches the 81 runtime,
   pack and snapshot files plus the 6 overlay files from the origins, checking sha256 against the lock. The fetch is
   resumable.
6. **The served pin's links.** `pin use <id>`: the lock link, `out/overlay/snapshots/widgets{7,8}` and
   `gallery/pin.json`.
7. `scripts/showcase.sh verify`.

**Origins.** `--origin` is the showcase's own origin, which serves QED64's files *and* our overlays. Until the
showcase's Worker is deployed, the overlays exist only where they were baked, so point `--origin` at the `serve.mjs` of
a checkout that has them (`PORT=5297 scripts/showcase.sh serve` there; plain HTTP GETs) or take the heavy path.
`--qed64-origin` serves QED64's own files only, and QED64's live site serves exactly those paths.
`node scripts/fetch-artifacts.mjs --remote-check --qed64-origin <url> --only public` checks an origin without
downloading.

What `verify` prints in such a checkout: **ABSENT** for the build stores of the runtime (stage1, raw regions, bakes,
headless results), which only the heavy path makes; **NOT MATERIALIZED** for staged pins you did not bootstrap;
**N/A** for the kernel-build checks (`QED64_KERNEL_BUILD` unset) and for an undownloaded browser. Everything that is
served is checked file by file.

Proved on 2026-10-04 from a fresh `git clone --recursive` (logs in `$W/logs/r2/`): `clone-bootstrap-*.log` and
`clone-verify-2.log` (macOS), `linux-rehearsal-1.log` (Docker `node:26-bookworm`), and the clone's full UX run
(`clone-ux-full1.log`).

## Heavy path: rebuilding the overlays

### What you need

| Input | Where it comes from | Variable | Pinned in the lock as |
|---|---|---|---|
| The kernel fork, branch `qed64-wasm64` | github.com/FawadHa1der/lean4 (`wasm64-build/README.md` there). The served runtime's kernel is QED64's `pipeline/toolchain/KERNEL-PIN` at the pin (E: `a8817d01f9`). The native64 compiler our oleans were built with is `NATIVE_COMMIT 857544b439` from build tree `BUILT_COMMIT 8d91aadcda` | `QED64_KERNEL_SRC` (optional; only `assert-untouched` watches it) | `qed64.kernel`, `toolchain.native64` |
| Its build tree: `native/stage1/{bin/lean,bin/lake,lib/lean}` (the fork's native 64-bit Linux compiler, which writes oleans the wasm64 runtime can load), `mathlib/mathlib4` (Mathlib built with it), `mathlib/MATHLIB-COMMIT`, `BUILT-COMMIT`, `native/NATIVE-COMMIT` | in the kernel fork: `wasm64-build/build.sh` (Docker image + wasm build), `wasm64-build/import-release.sh build v4.34.0`, `wasm64-build/native64.sh v4.34.0`, `wasm64-build/mathlib-tree.sh v4.34.0`. Do not use `lake exe cache get`: community oleans are GMP builds for another target | `QED64_KERNEL_BUILD` | `toolchain.native64` (`stage1/bin/{lean,lake}` sha256), `toolchain.mathlib` (`5ed2965`, ProofWidgets `106ff4f`) |
| The Docker image `qed64-toolchain:emsdk-6.0.5` | `docker build -t qed64-toolchain:emsdk-6.0.5 docker-wasm64` in the kernel fork (the fork's `wasm64-build/build.sh` does this; the recipe is `docker-wasm64/Dockerfile`, last changed in `974ee228b0`). Docker Desktop with an 8 GB VM is enough for our build (peak 3.75 GiB) | `QED64_TOOLCHAIN_IMAGE` (default that tag) | `toolchain.docker.id` plus `equivalent` ids (see "Docker image drift" below) |
| QED64's served olean trees: the slim base tree the stock `mathlib` region was baked from (5004 modules) and the slim core lib | QED64's `docs/REBUILD.md` §2–3 in the submodule (`work/lib-tree-slim`, `work/core-lib-slim`; per pin `pins/<id>/pin.json servedTrees`, e.g. E: `${QED64_REPO}/work/bump-0035b/slim/…`) and `work/lib-tree` for the fat tree | `QED64_REPO` (a QED64 checkout with its `work/` trees built; read-only) | `pin.json servedTrees` |
| The pinned runtime's `stage1/bin` (`lean.wasm` + `lean.js` + `package.json` + `leanmake`) for the bakes and headless verifiers | QED64's `pipeline/toolchain/work/build/stage1/bin` of the pinned runtime (QED64 `docs/REBUILD.md` §1); its `lean.wasm` sha256 must give the pin's buildId | copied to `$W/runtimes/<bid>/stage1/bin` | `qed64.buildId` (`wasm64-<sha256(lean.wasm)[0:16]>`) |
| The stock Lean toolchain v4.34.0 (native goldens) | `elan toolchain install leanprover/lean4:v4.34.0` | `LEAN_TOOLCHAIN_DIR` | – |

Set the variables in `qed64-showcase/.env.local` (template `.env.example`); `node scripts/lib/env.mjs` prints what
resolved. With `QED64_KERNEL_BUILD` set, `scripts/showcase.sh verify` also checks the toolchain pins (#7).

### The command sequence

The commands are listed in order. Each command is the same one the project was built with; `showcase.sh --help` and
README "One-command workflow" describe the guards. `$W` is `QED64_SHOWCASE_WORK` (no spaces; tens of GB).

```
# 0. light-path bootstrap first: sources, the page, QED64's binaries (the overlays may be absent: --only public)
scripts/showcase.sh bootstrap --qed64-origin <QED64 origin> --no-verify     # or fetch-artifacts.mjs --only public
node scripts/export-widgets.mjs                                              # $W/widgets-src (git archive packages/)
cp -cpR "$QED64_KERNEL_BUILD/mathlib/mathlib4" "$W/mathlib4"                 # B0: a copy-on-write clone (Linux: cp -a --reflink=auto)
mkdir -p "$W/runtimes/<bid>/stage1" && cp -Rc <QED64>/pipeline/toolchain/work/build/stage1/bin "$W/runtimes/<bid>/stage1/bin"

# 1. native: the widget oleans with the fork's native64 compiler in Docker (--network none)
scripts/showcase.sh native all        # identity → reuse gate → delta (38 Mathlib modules, lean/native/delta-phase1.txt)
                                      # → append lean/lakefile-append.lean → widgets (64) → distlens (410, T=4) →
                                      # header gates (no GMP, empty githash) → reuse gate → native-report.py
# 2. stage: the bake trees = QED64's served slim tree + our delta and widget oleans
scripts/showcase.sh stage all         # tree-slim-w7 (5107 modules), tree-slim-w8 (5684), tree-fat; gates G1–G6
# 3. bake: the snapshot regions with the pinned wasm runtime (under the browser lock; no browser or Docker alongside)
scripts/showcase.sh bake all          # bake-snapshot.mjs from deps/qed64; judge-bake; pair-check (digest, runtime)
# 4. overlay: the page-loadable regions (widgets renamed 'mathlib', the stock init beside it)
scripts/showcase.sh overlay all --preflight
node scripts/pin-qed64.mjs record-overlays   # record their sha256s in the lock (what bootstrap checks fetched overlays against)
# 5. headless: wasm verification in Node (E1/E3/E3b, E2, controls; ~20 min, 12 GB+ peaks)
scripts/showcase.sh headless all
# 6. gallery and UX
scripts/showcase.sh gallery && scripts/showcase.sh ux
```

`scripts/showcase.sh all --rebuild` runs steps 1–6 in order (plus `verify` before and after). A rebuilt overlay has new
digests unless the bake is bit-reproducible. The bakes were reproduced earlier (docs/REPIN-LOG.md), but nobody has
proved this for every pin. So step 4's `record-overlays` changes the lock, and the gallery then needs new UX verdicts.

The native goldens (`lean/expect/`, including `lean/expect/click-all/`) come from `lean/goldens/run-all.sh` with the
stock toolchain and `lean/goldens/golden-env.sh build` (lean/README.md).

### Docker image drift

The native build runs in `qed64-toolchain:emsdk-6.0.5`. QED64's `pipeline/toolchain/build.sh` and the kernel fork's
`wasm64-build/build.sh` both re-run `docker build -t` on this tag, so the tag moves. The image that built the served
oleans was `8b6698bbf474`, and it is gone. The tag now names `8228ea564e7b`, created 2026-08-25 19:26:43Z from the same
recipe: its `docker history` RUN steps are the kernel fork's `docker-wasm64/Dockerfile` at `974ee228b0`.

The native64 compiler itself comes from the kernel build tree (`-v $K/native:/native:ro`), not from the image. The image
supplies the Linux userland: glibc, the C compiler named by `LEAN_CC`, and the shell. The result of re-running the
native build in the current image is recorded below ("Drift resolution"). When `verify` reports a DRIFT on the image,
the resolution is one of these:

* the current image builds the same oleans byte for byte: record its id under `toolchain.docker.equivalent`
  (`verify` then prints OK and `native` accepts it);
* or it does not: `native` keeps refusing until the oleans have been rebuilt in it and every later stage redone.

**Drift resolution (2026-10-04, R2 lane): the current image is equivalent.** In a fresh copy-on-write copy of
`$W/mathlib4` (`$W/r2-drift`), every output file of the 512 modules the original native build produced was moved
aside: 38 phase-1 delta modules, 64 widget modules, and the 410 modules of the DistLens/LeanWidgetKit closure, 7,616
files in all. `scripts/build-native.sh delta`, `widgets` and `distlens` (T=4) then ran in image `8228ea564e7b` with the
same mounts, `--network none` and environment. Lake rebuilt exactly those 512 modules (its new-oleans lists equal the
original ones) in 83 s + 112 s + 912 s, with a peak of 4.1 GiB. **All 7,616 files are byte-identical to the
originals**: `.olean`, `.ilean`, `.c`, `.ir`, `.ir.sig`, `.olean.server`, `.olean.private`, their `.hash` files,
`.trace` and `.setup.json` (`$W/logs/r2/drift-compare.log`; build log `drift-rebuild.log`; image recipe and layer check
`drift-image-recipe.log`). So every lock records `8228ea564e7b` under `toolchain.docker.equivalent`, with the recipe and
this evidence. `verify` #7 prints OK, and `showcase.sh native` accepts the image
(`$W/logs/r2/native-guard-dryrun.log`). The served oleans, bakes and overlays did not change.
