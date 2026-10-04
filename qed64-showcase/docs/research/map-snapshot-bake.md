# How QED64 bakes environment snapshots and pairs them with a runtime, and a recipe to bake a 'widgets' snapshot (QED64.Essential + the widget roots) for runtime wasm64-4b025db7729c5f89, with every write outside the qed64 repo

## Facts
- bake-snapshot.mjs CLI: `node pipeline/snapshot/bake-snapshot.mjs [--name init] [--probe '#check 2+2'] [--artifact <dir>] [--lib <olean tree>] [--reserve <bytes>] [--out <dir>] [--work <dir>]`. Defaults: --name 'init'; --probe '#check (2 + 2 : Nat)'; --artifact is $QED64_LEAN_ARTIFACT, otherwise <root>/pipeline/toolchain/work/build/stage1; --out is <root>/work/staging/<buildId>/snapshots; --work is <root>/work/snapshot; --reserve is 3.5 GiB; --lib has no default and falls through to node-runner. The usage line does not list --work, but line 72 reads it. <root> is the repo containing the script (two directories above it). Relative paths resolve against <root>, not cwd. The npm alias is `npm run bake:snapshot` (package.json:18).
  - EVIDENCE: qed64/pipeline/snapshot/bake-snapshot.mjs:15 (usage), :27 (root), :32-34, :38, :44, :72, :84-85, :92; qed64/package.json:18
- How the bake works: it writes `<probe>\n` to <work>/probe.lean and deletes any old <work>/<name>.snap. It then spawns `node --stack-size=8192 node-runner.mjs --work <work> --artifact <artifactDir> [--lib <lib>] -- --incr-header-save=/work/<name>.snap /work/probe.lean` with LEAN_COMPACTOR_RESERVE=<reserve> in its environment. The CLI never exits on its own (patch 0031). A supervisor kills it with SIGKILL once stdout/stderr has been quiet for more than 300 s AND the .snap size has been stable for more than 120 s. So every bake has a floor of about 5 minutes of idle waiting.
  - EVIDENCE: bake-snapshot.mjs:73-74, :76-86, :100, :101-134 (quiet >300000 ms, stable >120000 ms at :120-121)
- Bake outputs:
(a) the raw region <work>/<name>.snap, which is kept;
(b) <out>/<name>.<sha256(gz)[:16]>.snapz, gzip level 6, written via a .tmp file and then renamed. The extension is .snapz, not .gz, so servers do not add Content-Encoding. Older .snapz files are never deleted.
(c) <out>/index.json is upserted with schema 'qed64.snapshot-index/v1' and the entry {name, url:'/snapshots/<gzName>', digest:'sha256:<hex of the gz bytes>', bytes:<raw size>, transfer:<gz size>, imports:[the probe's import lines, in order], runtime:<buildId>}.
The imports are taken per line with the regex ^(?:public\s+|private\s+)?(?:meta\s+)?import\s+([A-Za-z_][\w.«»]*).
  - EVIDENCE: bake-snapshot.mjs:136-168, :169-171, :178-198
- Guards that run before the runner starts: --out inside <root>/public/ is refused (symlinks resolved), with exit 2. The existing <out>/index.json is also checked. Any sibling entry paired to a different runtime is refused, and so is any sibling with no `runtime` field. A sibling with the same runtime (for example a copied served `init` entry) is allowed.
  - EVIDENCE: bake-snapshot.mjs:45, :53-66; qed64/pipeline/toolchain/artifact-paths.mjs:35-61
- bake-snapshot does NOT fail on Lean elaboration errors in the probe body. The header snapshot is saved before the `hasErrors` early return. The wedged runner is reaped and resolve() is called whatever was printed. Only a non-zero exit code or a missing .snap fails the bake. The README says 'the bake fails loudly if the examples stop compiling', but the code does not enforce this. Grep the bake log yourself.
  - EVIDENCE: bake-snapshot.mjs:122-133, :137-140; kernel src/Lean/Elab/Frontend.lean:410-416 (saveSnap for incrHeaderSaveFileName? comes before `if hasErrors then return none`); qed64/README.md:100-103
- bake-snapshot captures the runner's stdout through execFile with maxBuffer 64 MiB. A probe that prints a lot could hit that limit and get the child killed (inferred from Node's execFile semantics, not tested). Keep the bake probe to the import lines plus a trivial #check.
  - EVIDENCE: bake-snapshot.mjs:102-105
- Runtime identity: buildId = 'wasm64-' + the first 16 hex characters of sha256(lean.wasm). It is computed by buildIdOfArtifact from <dir>/bin/lean.wasm (or <dir>/lean.wasm). bump-chain.sh and import-packs.sh compute the same value with shasum.
  - EVIDENCE: qed64/pipeline/toolchain/artifact-paths.mjs:14-25; qed64/pipeline/release/bump-chain.sh:33; qed64/pipeline/release/import-packs.sh:115
- The served runtime wasm64-4b025db7729c5f89 is on disk in three places, and each was verified locally:
- /Users/fawadhaider/code/wasm64-lean-fable/qed64/pipeline/toolchain/work/build/stage1/bin/lean.{js,wasm}. sha256 of lean.wasm is 4b025db7729c5f89d686b5…; lean.wasm is 109,872,982 bytes, lean.js 48,971,853. bin/package.json is { "type": "commonjs" }. lib/lean and lib/temp are also there.
- /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0-fix/build/stage1/bin. Same sha. BUILT-COMMIT is 9fbb45afcb9bfe…. There is no bin/package.json. This is the --artifact the actual 965c249 bakes used.
- Chunked for serving as qed64/public/runtime/runtime-manifest.json and runtime-manifest.wasm64-4b025db7729c5f89.json (lean.wasm sha256 4b025db7…), with chunks in public/runtime/chunks.
The staged copy is work/staging/wasm64-4b025db7729c5f89/{runtime,snapshots,profiles}.
  - EVIDENCE: shasum output in this session; ls of stage1/bin; qed64/public/runtime/runtime-manifest.json (buildId, files.lean.wasm.sha256); qed64/pipeline/toolchain/KERNEL-PIN:1, :17, :21; qed64/work/bake-bump-mathlib.log:2
- How pairing is verified:
- Preflight (tests/adversarial/preflight.mjs) fetches the runtime manifest. If ?runtime= is given it requires manifest.buildId to equal it (:58). It HEADs every chunk against the manifest sizes. For each snapshot index entry it re-roots /snapshots/ to /<?snapshots dir>/ and requires the served size to equal entry.transfer ?? entry.bytes (:80-84). It requires entry.runtime === buildId; a missing runtime is only a warning (:85-87). It also checks the profile index runtime (:97).
- The worker separately refuses a mismatched entry.runtime with SNAPSHOT_UNPAIRED (public/workers/lean.worker.js:1236-1245).
- The page selects the manifest with ?runtime=<id> via /runtime/runtime-manifest.<id>.json (frontend/src/qed64-boot.ts:74-75).
- preflight.mjs writes a file only when --run-dir is passed (:150).
  - EVIDENCE: qed64/tests/adversarial/preflight.mjs:56-58, :75-87, :97, :150; qed64/public/workers/lean.worker.js:1228-1245; qed64/frontend/src/qed64-boot.ts:74-75
- Exact commands behind promote 965c249. They were run by `bump-chain.sh stage-artifact` with QED64_ARTIFACT=…-v4.34.0-fix/build/stage1, QED64_SLIM=work/bump-51/slim and QED64_SNAP_WORK=work/bump-51/snapshot:

node pipeline/snapshot/bake-snapshot.mjs --name init --lib /Users/fawadhaider/code/wasm64-lean-fable/qed64/work/bump-51/slim/core-lib-slim --reserve 1073741824 --artifact /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0-fix/build/stage1 --work /Users/fawadhaider/code/wasm64-lean-fable/qed64/work/bump-51/snapshot

node pipeline/snapshot/bake-snapshot.mjs --name mathlib --lib …/work/bump-51/slim/lib-tree-slim --reserve 3221225472 --probe 'import QED64.Essential' --artifact …-v4.34.0-fix/build/stage1 --work …/work/bump-51/snapshot

Results:
- init: 649 modules, 122,364,117 bytes raw, 32,643,645 on the wire, init.35c8c5f5419e0c33.snapz.
- mathlib: 5,004 modules, 1,127,272,685 bytes raw, 321,484,932 on the wire, mathlib.8df0689fbc323eab.snapz.
Both went to the default --out work/staging/wasm64-4b025db7729c5f89/snapshots. The commands are not in git history: 965c249 only changes KERNEL-PIN, the public manifests and the index.
  - EVIDENCE: qed64/work/bake-bump-init.log:2-4, :19-21; qed64/work/bake-bump-mathlib.log:2-4, last 4 lines; qed64/work/bump-51/stage.out:13-16; qed64/pipeline/release/bump-chain.sh:15-23, :49-53; `git show --stat 965c249`; qed64/public/snapshots/index.json
- Source trees of the 965c249 bakes:
- work/bump-51/slim/lib-tree-slim was rsynced from the default QED64_LIB_TREE=work/lib-tree with *.olean.private excluded. Its oleans share inodes with work/lib-tree and work/lib-tree-slim (same inode 68810423 for Mathlib/Order/Lattice.olean; 68816964 for QED64/Essential.olean).
- QED64/Essential.olean{,.server} was compiled 2026-09-21 (the umbrella was compiled under the 4.34 import). REBUILD.md:192-193 names work/umbrella as the umbrella's location. The umbrella source is work/umbrella/Essential.lean, 4,358 lines.
- core-lib-slim is the -fix artifact's lib/lean minus private facets.
- Bake time: init 15:05:37 to 15:11:05 (about 5.5 min); mathlib about 5 min. mathlib.snap's mtime is 15:12, so most of the wall time is the reaper's idle wait.
  - EVIDENCE: `ls -li` of the three trees in this session; qed64/work/bump-51/stage.out:13-14; mtimes of qed64/work/bump-51/snapshot/*.snap; qed64/pipeline/release/bump-chain.sh:27, :49-50
- The olean bytes match across trees. Served Mathlib oleans in qed64/work/lib-tree are byte-identical to the native build's /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0/mathlib/essential-tree and to its mathlib4/.lake/build (checked on Mathlib/Order/Lattice.olean and .olean.private, and ProofWidgets/Data/Html.olean). Init/Prelude.olean is identical in the served tree, in build-v4.34.0/build/stage1 and in qed64 stage1 (9fbb45). KERNEL-PIN states the packs are 'oleans built natively at 8d91aadcda, layout-compatible' with the 9fbb45afcb runtime. So oleans compiled with the native64 compiler (BUILT-COMMIT 8d91aadcda) match the format of the served tree.
  - EVIDENCE: sha256 comparison in this session; qed64/pipeline/toolchain/KERNEL-PIN:20; /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0/BUILT-COMMIT
- node-runner.mjs mounts exactly ONE library tree. --lib (or <artifact>/lib/lean) is NODEFS-mounted at /lib/lean and LEAN_PATH is set to '/lib/lean'. --work is mounted at /work and becomes the cwd. The artifact dir is also mounted at its own host path, because the patch-0031 pthread stats the host argv path. The runner forwards QED64_ALLOW_LEGACY_IMPORTS, LEAN_COMPACTOR_RESERVE and QED64_PROFILE_INIT from the host environment.

To mix served Mathlib oleans with our own, the bake input has to be one flat tree with every module at <Root>/<path>.olean. Lean resolves a module in the first LEAN_PATH entry that contains its root directory, so delta Mathlib.*/ProofWidgets.* oleans must sit beside the served Mathlib/ and ProofWidgets/ directories. lean4game documents and does exactly this: an overlay tree, with compat oleans compiled into the base tree.
  - EVIDENCE: qed64/pipeline/snapshot/node-runner.mjs:71, :107-115, :119-129; /Users/fawadhaider/code/wasm64-lean4game/wasm/build-from-source.sh:207-216, :437-444
- lean4game is a working precedent for using QED64 as a dependency.
- It vendors QED64's pipeline scripts at a pinned commit with `git archive`, so nothing is copied from the working tree (scripts/sync-qed64.sh).
- It runs a COPY of the vendored pipeline from its own out directory, because bake-snapshot hardcodes its work dir under its own root.
- It compiles extra packages with native lean in Docker via wasm/scripts/compile-pkg.py.
- It builds per-game overlay trees, optionally slim (base *.olean.private dropped).
- It bakes with QED64_ALLOW_LEGACY_IMPORTS=1 and --out to its own staging.
- It verifies each bake with `snapshot-probe.mjs --via-mem ... --budget-ms 600000`.
  - EVIDENCE: /Users/fawadhaider/code/wasm64-lean4game/scripts/sync-qed64.sh:1-40; wasm/build-from-source.sh:55-63, :127-133, :196-216, :492-498, :573
- No extra env var is needed for the widget packages (assumed legacy, non-`module` files). Legacy (non-`module`) oleans are tolerated unconditionally on the wasm target (patch 0030): `tolerateLegacy := System.Platform.target.startsWith "wasm" || QED64_ALLOW_LEGACY_IMPORTS`. Admitted legacy modules get irPhases := .all. QED64_ALLOW_LEGACY_IMPORTS matters only to the native compiler.
  - EVIDENCE: /Users/fawadhaider/code/wasm64-lean-kernel/src/Lean/Environment.lean:2163-2179 (kernel HEAD is 9fbb45afcb); qed64/pipeline/toolchain/PATCHES.md:202-211
- Coverage of the widget imports in the served tree. The served slim tree has 5,004 .olean files and no .olean.private. It has only 10 ProofWidgets modules (Cancellable, Compat, Component/{Basic,FilterDetails,MakeEditLink,OfRpcMethod,Panel/Basic,RefreshComponent}, Data/Html, Util).

These widget library imports are MISSING from it:
- Mathlib.Combinatorics.Enumerative.Catalan.Tree
- Mathlib.Combinatorics.SimpleGraph.{Basic, Connectivity.Finite, CycleGraph, Hasse}
- Mathlib.Probability.Distributions.Uniform
- Mathlib.Probability.ProbabilityMassFunction.{Binomial, Constructions, Integrals}
- ProofWidgets.Component.HtmlDisplay
- ProofWidgets.Component.Panel.SelectionPanel

Where they exist natively:
- HtmlDisplay is in build-v4.34.0/mathlib/extra-tree and in mathlib4/.lake/packages/proofwidgets/.lake/build.
- SelectionPanel is only in the latter.
- The Mathlib SimpleGraph and Probability modules are in neither essential-tree, extra-tree nor mathlib4/.lake/build (3,122 oleans). They must be compiled.
  - EVIDENCE: find/ls checks in this session against qed64/work/bump-51/slim/lib-tree-slim and /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0/mathlib/{essential-tree,extra-tree,mathlib4/.lake}
- 'Slim' means the bake's olean tree has every *.olean.private removed. .olean.server facets are kept, so hover and docstrings stay intact. bake-snapshot itself does not require it, since it bakes whatever --lib is given. But the served pairing is slim, and a FAT Mathlib-scale snapshot can no longer be baked on this runtime. The compactor's offset table (patch 0012, 16-byte slots, doubling at 70% load) crosses 2^27 to 2^28 slots, and the transient no longer fits the 16 GiB wasm64 space. Slim also costs about 60% less (mathlib 2,755 MB to 1,114 MB raw). Its residual risks are `import all M` and kernel reduction through private bodies of module-ized files, which is why there is an audit (static `olean-imports.mjs --audit` plus a fresh-import differential). Compiling against the tree still needs FAT facets; lean4game compile trees are always fat.
  - EVIDENCE: qed64/docs/SERVER-SLIM-REBAKE.md:3-6, :10-21, :35-36, :39-46, :54-75, :86-106; qed64/docs/REBUILD.md:99-115; qed64/pipeline/release/bump-chain.sh:12-13, :49-50; lean4game wasm/build-from-source.sh:64-68, :441-444
- Checks available for a baked snapshot:
(1) Bake log: 'Loading N modules', with N/N reached and no error lines.
(2) Raw size against expectations: KERNEL-PIN sizes for unchanged libraries; lean4game uses ±5% of expectedRaw.
(3) snapshot-probe.mjs, run as `node --stack-size=8192 snapshot-probe.mjs (--snap <raw .snap> | --fresh-import --lib <tree>) (--probe-file f | --probe src) [--lib <tree>] [--artifact <dir>] [--budget-ms 90000] [--via-memfs|--via-mem] [--init-flags 1] [--workspace <dir>] [--dump-messages]`. It loads the raw .snap via lean_wasm_load_snapshot(_mem), the worker's path. It then runs lean_wasm_compile on the probe and requires tag 0, zero severity:error JSON messages, and compile time within --budget-ms. A slow compile means a wrong cache key, i.e. a silent re-import. It prints 'SNAPSHOT PROBE PASS'.
(4) Slim-vs-fat differential with --fresh-import: messages must be byte-identical.
(5) In-browser checks: preflight, e2e, battery.
  - EVIDENCE: qed64/pipeline/snapshot/snapshot-probe.mjs:9-12, :27-35, :38-53, :62-66, :94, :180-181, :201-223; qed64/docs/TESTING.md:10, :24-33; qed64/pipeline/toolchain/KERNEL-PIN:17-19; lean4game wasm/build-from-source.sh:509-529
- snapshot-probe has defaults to override:
- --lib defaults to <qed64>/work/lib-tree.
- --artifact defaults to stage1.
- Its Memory64 is initial 4096 pages (256 MiB) and maximum 131072 pages (8 GiB).
- It hard-links the .snap into os.tmpdir()/qed64-snap-probe-*. The .snap must be on the same volume as TMPDIR, which holds on this Mac: both are on /System/Volumes/Data.
  - EVIDENCE: snapshot-probe.mjs:27-35, :62-66, :94; `df` in this session
- The resident FileWorker probes under Node can drive the real LSP loop: initialize/didOpen, `$/lean/rpc/connect`, hover. header-switch-probe.mjs and resident-probe.mjs do this. header-switch-probe loads raw snapshots ONLY from <repoRoot>/work/snapshot/{init.snap, mathlib.snap}, where repoRoot is two directories above the script. A vendored copy therefore reads OUR work/snapshot. This makes it a template for a headless widget/RPC harness.
  - EVIDENCE: qed64/pipeline/snapshot/header-switch-probe.mjs:1-18, :280-300, :330-350; resident-probe.mjs:20-22, :286-303
- The stock page only ever loads snapshots NAMED 'init' and 'mathlib'. 'mathlib' is loaded only when an import line's root is Mathlib, Batteries, MIL or QED64, or after a refused header whose missing modules are all umbrella modules. The initial wasm commit is 2048 MiB when 'mathlib' is loaded, with a 6 GiB cap. The kernel resolves a header to the exact key, else to the smallest loaded environment whose import closure covers it (patch 0032 K1). Consequences:
- An overlay must publish the widget superset under the name 'mathlib'.
- Demo headers must contain at least one QED64.*/Mathlib.* import line.
Once the header is covered, the resident env serves the imports and the page does not install the essential pack.
  - EVIDENCE: qed64/frontend/src/resident-session.ts:74, :78, :85, :94, :101, :188; qed64/frontend/src/main.ts:361, :377-386; qed64/frontend/src/qed64-boot.ts:96-107, :173-189; qed64/pipeline/toolchain/PATCHES.md:250-257
- Other ways the qed64 tree could be written to:
- node-runner defaults --work to <qed64>/work/runner and creates it with mkdirSync.
- bake-snapshot defaults --work to <qed64>/work/snapshot and --out to <qed64>/work/staging/<id>/snapshots. With --out omitted, a bake would upsert into the SERVED staging index.
- Passing absolute --work/--out (and --work to node-runner) avoids every write under qed64.
- Running a vendored copy also moves the defaults out of qed64.
  - EVIDENCE: node-runner.mjs:65-66; bake-snapshot.mjs:44, :72-74; artifact-paths.mjs:28-30
- Running a single .lean file headlessly: `node --stack-size=8192 node-runner.mjs --artifact <stage1> --lib <tree> --work <dir> -- [lean args] /work/File.lean`. Two more pieces are available:
- The kernel CLI supports `--incr-load=file` ('reuse a snapshot saved by --incr-(header-)save'). Whether it works on wasm is not verified here.
- supervised-run.mjs is QED64's wrapper for a one-shot job, because the CLI never exits (HARDENING #47). Its usage is `supervised-run.mjs --target <file> [--quiet-ms 30000] [--stable-ms 30000] [--give-up-ms 7200000] [--runner <script>] -- <node-runner args>`. It unlinks the target first. It fails on output matching /: error[:( ]|^error:|uncaught exception|PANIC|ABORT:|RuntimeError:/. It succeeds when the target is stable and the runner is quiet. QED64 itself uses `-o /work/X.olean` as the target (umbrella compile).
  - EVIDENCE: node-runner.mjs:14-20; supervised-run.mjs:1-23, :39-51, :83-93; kernel src/Lean/Shell.lean:451-454, :708-713; import-packs.sh:263-268
- Resource needs:
- The bake runs on the HOST under Node (v26.3.0 here; Node 24+ required for Memory64), not in Docker.
- The wasm64 space is 16 GiB (runtime manifest memory.maximumBytes 17179869184).
- The compactor output buffer is reserved in one allocation via LEAN_COMPACTOR_RESERVE: init used 1 GiB and mathlib 3 GiB; the bake default is 3.5 GiB.
- Each bake has a minimum of about 7 min of supervisor wait. That comes from 300 s quiet plus 120 s stable checked every 5 s; the observed figure was about 5 min.
- Disk: the raw .snap plus .snapz is about 1.5 GB for a Mathlib-scale region. 747 GiB is free.
- Peak host RSS was not measured anywhere I found.
  - EVIDENCE: qed64/public/runtime/runtime-manifest.json memory block; bake-snapshot.mjs:88-93, :114-128; qed64/docs/REBUILD.md:33, :107-108; `node --version`, `df -h`

## Recipes
### Bake a 'widgets' snapshot (header: import QED64.Essential + the widget roots) paired with wasm64-4b025db7729c5f89, with every write outside /Users/fawadhaider/code/wasm64-lean-fable/qed64
1. 0. Variables. Q=/Users/fawadhaider/code/wasm64-lean-fable/qed64 (read-only). W=<new dir outside Q; prefer a path WITHOUT spaces, e.g. /Users/fawadhaider/code/qed64-widgets-bake, or a symlink to the research dir>. Paths with spaces through node-runner's NODEFS mirror of the artifact path are untested. Run `mkdir -p $W/{logs,out,snapwork,stage1}`.
1. 1. Vendor QED64's pipeline at the promote commit, read-only. `git archive` reads the object store and writes nothing to the repo: `git -C $Q archive 965c249 pipeline/snapshot pipeline/toolchain/artifact-paths.mjs pipeline/artifacts/olean-imports.mjs pipeline/artifacts/unpack.mjs | tar -x -C $W/vendor` (create $W/vendor first). Record the pin, e.g. $W/vendor/QED64-PIN containing 965c249. `git diff 965c249 HEAD -- pipeline` is empty, so HEAD 1859b83 is equivalent. Now <root> for every script is $W/vendor, and its default work/ dirs land under $W/vendor/work.
1. 2. Runtime artifact copy. APFS clonefile copies without touching source inodes: `cp -Rc $Q/pipeline/toolchain/work/build/stage1/bin $W/stage1/bin`. This includes bin/package.json {"type":"commonjs"}, which lean.js needs whenever an ancestor package.json says type=module. Verify: `echo wasm64-$(shasum -a 256 $W/stage1/bin/lean.wasm | cut -c1-16)` must print wasm64-4b025db7729c5f89. lib/lean is not needed when --lib is always passed (node-runner.mjs:71-79).
1. 3. Fat base tree, our copy. Option A: `cp -Rc $Q/work/lib-tree $W/tree-fat`. This is the served packs unpacked, plus QED64/Essential.olean{,.private,.server}. Option B, which reproduces the browser's bytes from the served manifests: `node $W/vendor/pipeline/artifacts/unpack.mjs --manifest $Q/public/profiles/lean-core.manifest.json --out $W/tree-fat`, then the same for mathlib-essential.manifest.json, then `mkdir -p $W/tree-fat/QED64 && cp -c $Q/work/lib-tree/QED64/Essential.olean* $W/tree-fat/QED64/`.
1. 4. Compile the deltas INTO $W/tree-fat, outside this area's detail. Use the native64 lean (Linux/arm64, built at 8d91aadcda, the same commit that built the served packs) in Docker image qed64-toolchain:emsdk-6.0.5. Mount the compiler read-only (`-v /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0:/k:ro`) and $W read-write; set LEAN_PATH=$W/tree-fat. Compile the missing Mathlib modules (SimpleGraph.*, Catalan.Tree, Probability PMF/Uniform and their unbuilt closure), ProofWidgets HtmlDisplay/SelectionPanel (or clone them from the native proofwidgets .lake build), and the eight widget libraries plus any QED64/Widgets shims, in dependency order. lean4game's wasm/scripts/compile-pkg.py does this with `lean <src> -o <out>/<Mod>.olean --root <src>`. Delta Mathlib.* and ProofWidgets.* oleans must live in the SAME tree as the served Mathlib/ and ProofWidgets/ (first-LEAN_PATH-entry rule).
1. 5. Closure check, before any bake. Write a small Node script that imports `oleanImports` from $W/vendor/pipeline/artifacts/olean-imports.mjs. Walk from QED64.Essential plus each widget root and assert that every reachable module has a .olean in $W/tree-fat. Print the delta count beyond the 5,004 served modules.
1. 6. Slim tree, both sides ours: `rsync -a --exclude='*.olean.private' --link-dest=$W/tree-fat $W/tree-fat/ $W/tree-slim/`. Alternatively use `cp -Rc` and then delete the *.olean.private files in the copy. Run the static audit: `node $W/vendor/pipeline/artifacts/olean-imports.mjs --audit $W/tree-slim > $W/logs/import-all-audit.log`. New `import all` edges from widget or delta modules would break on slim.
1. 7. Seed the output index with the served init entry, so one directory carries the pairing. Copy the 'init' object verbatim from $Q/public/snapshots/index.json into $W/out/index.json as {"schema":"qed64.snapshot-index/v1","snapshots":[<init entry>]}. Then `cp -c $Q/public/snapshots/init.35c8c5f5419e0c33.snapz $W/out/`. The bake's sibling check accepts it because its runtime is the same id (bake-snapshot.mjs:56-66).
1. 8. Bake, with absolute --work and --out:
`cd $W && QED64_ALLOW_LEGACY_IMPORTS=1 node --stack-size=8192 $W/vendor/pipeline/snapshot/bake-snapshot.mjs --name widgets --artifact $W/stage1 --lib $W/tree-slim --reserve 3758096384 --work $W/snapwork --out $W/out --probe "$(printf 'import QED64.Essential\nimport IntervalInspector\nimport ExprXRay\nimport SimpLens\nimport GraphScope\nimport TreeScope\nimport HasseView\nimport DistLens\nimport ChartKit\n#check (2 + 2 : Nat)')" 2>&1 | tee $W/logs/bake-widgets.log`
Notes:
- QED64_ALLOW_LEGACY_IMPORTS is harmless and matches lean4game; on wasm the tolerance is unconditional.
- Use 3.5 GiB or 4 GiB of reserve, since the region exceeds the 1.13 GB umbrella.
- Keep the probe tiny (64 MiB maxBuffer). Expect at least 7 minutes, most of it the reaper's wait.
1. 9. Judge the bake yourself, since it never fails on elaboration errors. `grep -nE ': error|PANIC|ABORT:|uncaught|RuntimeError' $W/logs/bake-widgets.log` must be empty. The log must show 'Loading N modules', with N about 5,004 plus the delta, and N/N reached at the last root. It must also show 'baked …/widgets.<d16>.snapz … index updated (imports: [QED64.Essential, …], runtime wasm64-4b025db7729c5f89)'. Then check $W/out/index.json: widgets.runtime == wasm64-4b025db7729c5f89, and init is unchanged. Record the raw bytes, which should be above 1,127,272,685.
1. 10. Snapshot probe on the browser path: `node --stack-size=8192 $W/vendor/pipeline/snapshot/snapshot-probe.mjs --via-mem --init-flags 1 --artifact $W/stage1 --lib $W/tree-slim --snap $W/snapwork/widgets.snap --probe-file $W/probes/<Pkg>Demo.lean --budget-ms 120000 --dump-messages`. Each demo's header must match or be covered by the snapshot's imports. It must print SNAPSHOT PROBE PASS.
1. 11. Slim differential (SERVER-SLIM audit). Run the same probe files with `--fresh-import --lib $W/tree-fat --budget-ms 1800000` and diff the dumped messages against step 10's. They must be byte-identical.
1. 12. Overlay index for the STOCK page. Make $W/overlay/index.json from $W/out/index.json, renaming the widgets entry's name to "mathlib" (its url stays /snapshots/widgets.<d16>.snapz). The page only loads 'init' and 'mathlib' (resident-session.ts:85, main.ts:361/386). Put both .snapz files beside it. Serve that directory same-origin as /<D>/ and open `?runtime=wasm64-4b025db7729c5f89&snapshots=<D>`. Demo headers need at least one QED64.* or Mathlib.* import line, e.g. `import QED64.Essential`, so needsMathlib fires. Preflight can run read-only from Q: `node $Q/tests/adversarial/preflight.mjs --url '<url>'`, with no --run-dir, so nothing is written.
Evidence: Mirrors qed64/docs/REBUILD.md:99-115, qed64/pipeline/release/bump-chain.sh:49-53 and import-packs.sh:256-268, and lean4game wasm/build-from-source.sh:127-133, :207-216, :492-498, :573. Index and pairing rules are at bake-snapshot.mjs:53-66 and :178-198.

### Run widget Demo .lean files headlessly in Node against the wasm runtime before any browser test
1. Fastest and closest to the browser: after the bake, use snapshot-probe with the widgets snapshot, as in recipe 1 step 10. This is lean_wasm_load_snapshot_mem plus lean_wasm_compile, the worker's exact calls. Use --dump-messages to see every JSON message, including #eval and #html output text. The probe fails on any error-severity message or a budget overrun.
1. Without a snapshot (slower; imports the closure from oleans through NODEFS): `node $W/vendor/pipeline/snapshot/supervised-run.mjs --target $W/run/Demo.olean --quiet-ms 30000 --stable-ms 30000 -- --artifact $W/stage1 --lib $W/tree-slim --work $W/run -- -o /work/Demo.olean /work/Demo.lean`. Copy Demo.lean into $W/run first. supervised-run judges the job by output and reaps the kept-alive CLI. Exit 0 means no error lines and the .olean was produced. Use $W/tree-fat instead if a demo needs private facets.
1. For an RPC/InfoView-level check (widget props via $/lean/rpc/connect plus rpc/call), adapt the vendored header-switch-probe.mjs or resident-probe.mjs. They boot the real `--worker` FileWorker on the futex ring. Place raw snapshots at $W/vendor/work/snapshot/init.snap (`cp -c $Q/work/snapshot/init.snap`, 122,364,117 bytes) and $W/vendor/work/snapshot/mathlib.snap (`cp -c $W/snapwork/widgets.snap`). header-switch-probe reads exactly those two names under its own repoRoot (:289-290).
1. Untested alternative: `node-runner.mjs ... -- --incr-load=/work/widgets.snap /work/Demo.lean`. The CLI advertises it (Shell.lean:452), but it has not been exercised on wasm in any QED64 doc I found.
Evidence: snapshot-probe.mjs:9-12, :42-45, :164-223; supervised-run.mjs:20-23, :49-93; node-runner.mjs:14-20; header-switch-probe.mjs:280-300, :330-350; kernel src/Lean/Shell.lean:451-454


## Risks
- bake-snapshot does not detect Lean errors in the probe body. The header snapshot is saved before hasErrors is checked, and the wedged runner is SIGKILLed and resolved as success. A broken widget import that still saves a header, or broken demo text, passes silently unless the log is grepped (bake-snapshot.mjs:122-133; Frontend.lean:410-416).
- Running vendored or in-place scripts without absolute --work/--out writes into qed64: node-runner defaults to qed64/work/runner (node-runner.mjs:65-66); bake-snapshot defaults to qed64/work/snapshot and qed64/work/staging/<id>/snapshots, which is the SERVED staging index (bake-snapshot.mjs:44, :72).
- Hard-linking (rsync --link-dest) from qed64/work/lib-tree into our dir changes the link count and ctime of qed64's inodes. That arguably modifies files under a read-only tree. Use `cp -c` / `cp -Rc` (APFS clonefile) or unpack.mjs from the served manifests instead.
- Compactor capacity. A fat 5,004-module tree already overflows the 16 GiB space through the offset-table rehash (SERVER-SLIM-REBAKE.md:100-105). A slim superset (5,004 plus several hundred delta modules, DistLens's Probability/MeasureTheory closure being the largest) may approach the 2^27-slot doubling point. The headroom is unmeasured, so watch the first bake.
- Browser memory. The stock page commits 2048 MiB initial with a 6 GiB cap when 'mathlib' loads (resident-session.ts:94, :101). That was sized for the 1.11 GiB region (SERVER-SLIM-REBAKE.md:79-80). A larger region exercises the grow-while-streaming path the code blames for renderer crashes.
- The stock page loads only snapshots named 'init' and 'mathlib' and widens only for Mathlib/Batteries/MIL/QED64 roots. A demo header importing only `IntervalInspector` boots init-only and is refused, with no widening (main.ts:377-386; resident-session.ts:74-85).
- The bake's stdout goes through execFile with maxBuffer 64 MiB (bake-snapshot.mjs:102-105). Large probe output could kill the bake. Run demos separately.
- Snapshots are binary-paired. Any new QED64 runtime promote (new buildId) means rebaking widgets, and old overlay links fail loudly with SNAPSHOT_UNPAIRED (lean.worker.js:1236-1245; KERNEL-PIN:9-16).
- Several delta Mathlib modules (SimpleGraph.*, Probability.ProbabilityMassFunction.*, Distributions.Uniform, Catalan.Tree) exist in none of the native trees and must be compiled in Docker. The Docker VM has 8 GB, so parallel Mathlib compiles may OOM; limit the jobs.
- Slim semantics. Kernel reduction through private bodies of module-ized delta files, or any `import all` in the widget closure, could differ on slim. Run the --audit and the --fresh-import differential.
- Paths containing spaces (the research dir 'lean questions') are untested with node-runner's mirror mount of the artifact path (node-runner.mjs:110-114).

## Open questions
- Exact size of the delta closure (Mathlib modules beyond the 4,354-module essential set plus ProofWidgets extras) for all eight packages. This decides the raw region size and whether DistLens fits. It needs a closure walk over a Mathlib v4.34.0 source or olean tree.
- Peak host RSS and wall time of a ~1.3–1.6 GB region bake are unmeasured. The only data points are about 5 min wall for the 1.13 GB mathlib bake and about 5.5 min for init (work/bump-51/stage.out).
- Whether `--incr-load` works on the wasm CLI for headless demo runs. It is not exercised in any QED64 doc or script I read.
- Whether the oleans needed at runtime are all inside the snapshot. When a header is covered by the 'mathlib' env, I infer from K1/processHeaderCore being unreachable (PATCHES.md:250-257) that the page never needs widget oleans or packs. This was not observed directly, e.g. for IR lookups of legacy widget modules during #eval or RPC.
- Does lean.worker.js verify the snapshot digest after download? grep found no sha check near loadSnapshot; only size, cacheKey and runtime pairing were found.
- Whether the 2048 MiB initial commit plus grow-to-6 GiB survives a larger region in real Chrome. This needs browser testing (06-qed64-showcase-options.md §5 item 8).
- How the overlay directory is served same-origin without writing under qed64/public. The ?snapshots=<dir> override fetches /<dir>/index.json from the page's own origin (qed64-boot.ts:100-105), so a server we control must serve the QED64 dist plus our overlay dir. That belongs to the serving/vendoring area.
