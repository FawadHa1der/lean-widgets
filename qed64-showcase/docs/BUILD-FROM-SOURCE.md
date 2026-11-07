# Building the showcase from source

There are two paths. Most people need only the first.

* **Light path: serve and test.** QED64's page is built from source. QED64's binaries and our widget overlays are
  fetched by content hash. No kernel build, no Docker, no QED64 build. About 10 minutes plus a 2.4 GB download.
* **Heavy path: rebuild the overlays.** The kernel fork's native toolchain compiles the widget oleans, the trees are
  staged, and the pinned wasm runtime bakes the snapshot regions. Then come the headless verifiers, the gallery and the
  UX suite. This takes hours and a large Mac (it was built on a 36 GB machine). The bakes' peak RSS has grown with each
  runtime: about 11 GB on the first, 15.9 GB on `3ab1c6a9`, and up to about 18 GB on pin I's `f69cca24` (`time -l`
  maxrss 18.1 GB for w8, peak tree RSS 16.87 GiB, and 16.6 GB / 15.45 GiB for the w7 bake that P2 retired; `$W/logs/pinI-bake-w{7,8}.log`).

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
   submodule and installs `release/<id>/dist` only if every file is byte-identical to the lock.
5. **The binaries.** `scripts/fetch-artifacts.mjs` takes the tracked manifests from git and fetches the 81 runtime,
   pack and snapshot files plus the 3 overlay files (6 until P2, with widgets7) from the origins, checking sha256 against
   the lock. The overlay comes from the URL the lock records (`overlays.widgets8.url`, `/snapshots/widgets8.<bid16>/`;
   O: `widgets8.36d7f415704473d9`). The fetch is resumable.
6. **The served pin's links.** `pin use <id>`: the lock link, `out/overlay/snapshots/widgets8` and
   `gallery/pin.json`.
7. `scripts/showcase.sh verify`.

**Origins.** `--origin` is the showcase's own origin, which serves QED64's files *and* our overlays. The deployed
Worker has only the overlays uploaded to it (since 2026-11-05 O's `widgets8.36d7f415704473d9/`, and the unused `widgets7.<bid16>/` of O and the bare `widgets{7,8}/` of H, kept while each is a rollback target). Any other pin's overlays exist only
where they were baked until they are uploaded, so point `--origin` at the `serve.mjs` of
a checkout that has them (`PORT=5297 scripts/showcase.sh serve` there; plain HTTP GETs) or take the heavy path.
`--qed64-origin` serves QED64's own files only, and QED64's live site serves them for **one** release, the one it
deploys now: since QED64 `4b98279` its Worker reads `/runtime/*` and `/profiles/<not index.json>` only from that
release's prefix, with no fallback to the bucket root (its `runtime/` and `profiles/` copies were removed on
2026-10-23), and its R2 sweep of 2026-10-23 kept only the live and the previous pairing's snapshots. So
`--qed64-origin https://qed64.fawadworkaddress.workers.dev` works only for the pin whose release QED64 deploys now;
any other pin (bootstrapping or rolling back to N, H or older) takes its `/snapshots/` objects from the deployed
showcase (`--origin`) if that pin was uploaded, since our upload never deletes: of those only an overlay's `index.json`, one
per served directory, is the last upload's. Under release routing its runtime and packs come only from `scripts/serve.mjs`
of a checkout that has them ([ARCHITECTURE.md](ARCHITECTURE.md) "Binary dependency").
`node scripts/fetch-artifacts.mjs --remote-check --qed64-origin <url> --only public` checks an origin without
downloading; a FAIL for which QED64's origin was the last one tried carries that advice.

What `verify` prints in such a checkout: **ABSENT** for the build stores of the runtime (stage1, raw regions, bakes,
headless results), which only the heavy path makes; **NOT MATERIALIZED** for staged pins you did not bootstrap;
**N/A** for the kernel-build checks (`QED64_KERNEL_BUILD` unset, or naming no kernel build of the pin) and for an
undownloaded browser. Everything that is served is checked file by file.

Proved on 2026-10-04 from a fresh `git clone --recursive` (logs in `$W/logs/r2/`): `clone-bootstrap-*.log` and
`clone-verify-2.log` (macOS), `linux-rehearsal-1.log` (Docker `node:26-bookworm`), and the clone's full UX run
(`clone-ux-full1.log`).

## Heavy path: rebuilding the overlays

### What you need

*Note (2026-10-08, updated 2026-10-09 for pin I).* The kernel fork publishes these inputs as toolchain releases with a
CLI in their `lean4-wasm64` package (call it with `node`, never through `npx`):
[`lean-v4.34.0-a8817d0`](https://github.com/FawadHa1der/lean4/releases/tag/lean-v4.34.0-a8817d0) (the kernel of every
pin from D to H) and `lean-v4.34.0-e1a79c1` (pin I's; kernel patch 0037, runtime `wasm64-f69cca24d0878a58`). QED64
`385a1ac` (pin I) ships the release record `toolchain/lean4-wasm64-release.json` that names the release (id, digest,
kernel, runtime buildId, Docker image) and no longer has `pipeline/toolchain/build.sh`, `KERNEL-PIN` or the
`pipeline/toolchain/work/` tree. **Pin I's runtime was taken from the release** (first time; `$W/logs/pinI-stage1-fetch.log`:
`FETCH VERIFIED`; its `bin/` byte-identical to QED64's own adopted copy). The rows below say which source applies to
which pins; the native toolchain rows were unchanged for pin I (the e1a79c1 record names the same native64 `857544b439` and Mathlib
`5ed2965`), and nothing native was rebuilt for pin I; pin O `521cf3f` (Lean 4.35) has its own, named in the rows.

| Input | Where it comes from | Variable | Pinned in the lock as |
|---|---|---|---|
| The kernel fork, branch `qed64-wasm64` | github.com/FawadHa1der/lean4 (`wasm64-build/README.md` there). The served runtime's kernel is `kernel.commit` of QED64's release record `toolchain/lean4-wasm64-release.json` at the pin (QED64 `4f46477` on, so every registered pin; I: `e1a79c1ce9`), for the retired pins A–H QED64's `pipeline/toolchain/KERNEL-PIN` (E: `a8817d01f9`). The native64 compiler our oleans were built with is `NATIVE_COMMIT 857544b439` from build tree `BUILT_COMMIT 8d91aadcda` (pins up to 58ebbad; for `521cf3f` `b081e7c041` for both, the kernel release lean-v4.35.0-b081e7c) | `QED64_KERNEL_SRC` (optional; only `assert-untouched` watches it) | `qed64.kernel`, `toolchain.native64` |
| Its build tree: `native/stage1/{bin/lean,bin/lake,lib/lean}` (the fork's native 64-bit Linux compiler, which writes oleans the wasm64 runtime can load), `mathlib/mathlib4` (Mathlib built with it), `mathlib/MATHLIB-COMMIT`, `BUILT-COMMIT`, `native/NATIVE-COMMIT` | in the kernel fork: `wasm64-build/build.sh` (Docker image + wasm build), `wasm64-build/import-release.sh build v4.34.0`, `wasm64-build/native64.sh v4.34.0`, `wasm64-build/mathlib-tree.sh v4.34.0` (pins up to 58ebbad; `521cf3f` uses the lean-v4.35.0-b081e7c build, e.g. `$W/kernel-build-native64-v4.35`). Do not use `lake exe cache get`: community oleans are GMP builds for another target | `QED64_KERNEL_BUILD` | `toolchain.native64` (`stage1/bin/{lean,lake}` sha256), `toolchain.mathlib` (`5ed2965`, ProofWidgets `106ff4f` up to 58ebbad; `56a00585`, ProofWidgets `df72b022` for 521cf3f) |
| The Docker image `qed64-toolchain:emsdk-6.0.5` | `docker build -t qed64-toolchain:emsdk-6.0.5 docker-wasm64` in the kernel fork (the fork's `wasm64-build/build.sh` does this; the recipe is `docker-wasm64/Dockerfile`, last changed in `974ee228b0`). Docker Desktop with an 8 GB VM is enough for our build (peak 3.75 GiB) | `QED64_TOOLCHAIN_IMAGE` (default that tag) | `toolchain.docker.id` plus `equivalent` ids (see "Docker image drift" below) |
| QED64's served olean trees: the slim base tree the stock `mathlib` region was baked from (5004 modules) and the slim core lib | QED64's `docs/REBUILD.md` §2–3 in the submodule (`work/lib-tree-slim`, `work/core-lib-slim`; per pin `pins/<id>/pin.json servedTrees`, e.g. E: `${QED64_REPO}/work/bump-0035b/slim/…`) and `work/lib-tree` for the fat tree (from `521cf3f` on the descriptor names the fat base too, `servedTrees.baseFat`, which `stage fat` then uses instead). **Pin I:** `baseSlim` is H's (digest-identical, `8c247f41…`), and `coreSrc` is the release's own core library, `node <package>/cli.mjs fetch --from <release dir> --id lean-v4.34.0-e1a79c1 --digest <digest> --out $W/toolchains/lean-v4.34.0-e1a79c1 --only lean-lib`, then `node <package>/cli.mjs unpack --slim --manifest $W/toolchains/lean-v4.34.0-e1a79c1/profiles/lean-lib.manifest.json --out $W/core-lib-slim.f69cca24d0878a58` (10,074 files, 0.77 GB; tree digest `sha256:e442c951…` == QED64's `embedding/base-tree.json` `core-lib-slim`) | `QED64_REPO` (a QED64 checkout with its `work/` trees built; read-only); `QED64_SHOWCASE_WORK` for pin I's `coreSrc` | `pin.json servedTrees` (optional `baseSlimDigest` / `baseFatDigest` / `coreDigest`, checked by `stage-trees.mjs --check-digest baseSlim\|baseFat\|coreSrc`; pins up to K record none, so the check prints SKIP; L and N record `coreDigest`, `521cf3f` all three) |
| The pinned runtime's `stage1/bin` (`lean.wasm` + `lean.js` + `package.json` + `leanmake`) for the bakes and headless verifiers | **Pin I on:** the kernel fork's release that QED64's record names: unpack its `tools/lean4-wasm64-<version>.tgz` (pin I: `tools/lean4-wasm64-4.34.0-e1a79c1.tgz`, sha256 `65445d21bc64…`, as in the record and `SHA256SUMS`) into an empty directory, then `node <package>/cli.mjs fetch --from <release dir> --id lean-v4.34.0-e1a79c1 --digest sha256:bd71636b… --out $W/toolchains/lean-v4.34.0-e1a79c1 --only runtime` (`FETCH VERIFIED`) and copy its `bin/`; `node <package>/cli.mjs id <stage1 dir>` prints the buildId. Use the base release id, not its `-r2`/`-r3` revisions (same buildId, other digests). **Pins up to H:** QED64's `pipeline/toolchain/work/build/stage1/bin` of the pinned runtime (QED64 `docs/REBUILD.md` §1). Either way its `lean.wasm` sha256 must give the pin's buildId | copied to `$W/runtimes/<bid>/stage1/bin` | `qed64.buildId` (`wasm64-<sha256(lean.wasm)[0:16]>`) |
| The stock Lean toolchain of the widget packages (native goldens): their Lean, `packages/*/lean-toolchain` (v4.35.0, the Lean of `521cf3f`'s runtime); the golden scripts refuse (exit 2) any other version, so they run with `521cf3f` as the target pin or with `LEAN_TOOLCHAIN_DIR` set to it | `elan toolchain install leanprover/lean4:v4.35.0` | `LEAN_TOOLCHAIN_DIR` (default: elan's toolchain of the target pin's Lean, the `leanVersion` of its runtime manifest; without the manifest v4.34.0 only for a pin whose lock records the lean-v4.34.0 native compiler `857544b439`, any other pin leaves it unset) | – |

Set the variables in `qed64-showcase/.env.local` (template `.env.example`); `node scripts/lib/env.mjs` prints what
resolved. `QED64_KERNEL_BUILD` is one kernel build dir or a `:`-separated list of them (one per Lean release); every
script takes the target pin's, the one whose `native/NATIVE-COMMIT` and `mathlib/MATHLIB-COMMIT` are its lock's (`K`
in that output; `K_FROM` names each rejected dir when none is). When it holds the pin's kernel build,
`scripts/showcase.sh verify` also checks the toolchain pins (#7); unset, or naming only other releases' builds or
missing dirs, #7 prints N/A naming them. An empty value in the environment (`QED64_KERNEL_BUILD=`) wins over
`.env.local`, so verify reports those inputs N/A, as in CI: pin I's final verify ran that way
(`$W/logs/pinI-verify2b.log`) after the kernel build dir `.env.local` names was deleted on this host on 2026-10-09; a
set but missing directory made `pin-qed64.mjs verify` refuse at start then (`$W/logs/pinI-verify2.log`); it is an N/A
naming the dir now.

### The command sequence

The commands are listed in order. Each command is the same one the project was built with; `showcase.sh --help` and
README "One-command workflow" describe the guards. `$W` is `QED64_SHOWCASE_WORK` (no spaces; tens of GB).

```
# 0. light-path bootstrap first: sources, the page, QED64's binaries (the overlays may be absent: --only public).
#    QED64's origin serves only the release it deploys now (4b98279): for any other pin use --origin <showcase origin>
scripts/showcase.sh bootstrap --qed64-origin <QED64 origin> --no-verify     # or fetch-artifacts.mjs --only public
node scripts/export-widgets.mjs                                              # $W/widgets-src (git archive packages/)
#    B0: the target pin's MATHLIB_CLONE, $W/mathlib4.<first 8 hex of its lock's toolchain.mathlib.commit> (pins up to
#    58ebbad also accept the legacy $W/mathlib4 at their commit), from the target pin's kernel build K (its
#    mathlib/MATHLIB-COMMIT is that commit; QED64_KERNEL_BUILD may be a list, so never "$QED64_KERNEL_BUILD/..."; an
#    empty K: `node scripts/lib/env.mjs` prints K_FROM, why)
K="$(node scripts/lib/env.mjs --json | node -pe 'JSON.parse(require("fs").readFileSync(0)).K')"
cp -cpR "$K/mathlib/mathlib4" "$W/mathlib4.<Mathlib 8 hex>"               # a copy-on-write clone (Linux: cp -a --reflink=auto)
#    the runtime's bin (pin I on: from the kernel fork's release named by QED64's toolchain/lean4-wasm64-release.json;
#    T = the unpacked tools package, REL = the release directory, ID/DIGEST from the record)
node "$T/cli.mjs" fetch --from "$REL" --id "$ID" --digest "$DIGEST" --out "$W/toolchains/$ID" --only runtime   # FETCH VERIFIED
mkdir -p "$W/runtimes/<bid>/stage1" && cp -Rc "$W/toolchains/$ID/bin" "$W/runtimes/<bid>/stage1/bin"
#    (the retired pins up to H took cp -Rc <QED64>/pipeline/toolchain/work/build/stage1/bin)

# 1. native: the widget oleans with the fork's native64 compiler in Docker (--network none)
scripts/showcase.sh native all        # identity → reuse gate → delta (38 Mathlib modules, lean/native/delta-phase1.txt)
                                      # → append lean/lakefile-append.lean → widgets (64) → distlens (410, T=4) →
                                      # header gates (no GMP, empty githash) → reuse gate → native-report.py
# 2. stage: the bake trees = QED64's served slim tree + our delta and widget oleans
scripts/showcase.sh stage all         # tree-slim-w8 (5684 modules), tree-fat; gates G1–G6 (tree-slim-w7 until P2)
# 3. bake: the snapshot regions with the pinned wasm runtime (under the browser lock; no browser or Docker alongside;
#    peak RSS up to about 18 GB on pin I's runtime; bake.sh's default floor is MIN_FREE_GB=12, pin I's ran with 16)
scripts/showcase.sh bake all          # bake-snapshot.mjs from deps/qed64; judge-bake; pair-check (digest, runtime)
# 4. overlay: the page-loadable regions (widgets renamed 'mathlib', the stock init beside it); the preflight boots each
#    at the pin's served directory (pins.mjs overlay-dir) with QED64's pipeline/release/preflight.mjs
scripts/showcase.sh overlay all --preflight
node scripts/pin-qed64.mjs record-overlays   # record their sha256s and served URL in the lock (what bootstrap checks fetched overlays against)
# 5. headless: wasm verification in Node (E1/E3/E3b, E2, controls; ~20 min, 12 GB+ peaks; pin I: about 17 min, 14.24 GB peak)
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

**Drift again (2026-10-06, open).** The kernel session rebuilt the tag for its patches 0036/0037 (QED64's report); it
now names `sha256:5708c2dbf5a1`, which is neither `8b6698bbf474` nor the recorded equivalent, so `verify` prints
`DRIFT #7` (pin H entry in REPIN-LOG.md, `$W/logs/pinH-verify.log`). Not acted on: the served artifacts are unaffected,
and the experiment above decides it when a native rebuild is next needed.

**Pin I (2026-10-09).** The tag now names `sha256:0de79b891eb9…`, the image the release `lean-v4.34.0-e1a79c1` records
as `docker.imageId` (recipe `974ee228b0`), a third id: `verify` prints `DRIFT #7 … sha256:0de79b891eb9`
(`$W/logs/pinI-verify1.log`). Nothing native ran for pin I (its base trees are digest-identical to H's and the kernel
change touched only runtime files), so the drift was not acted on.
