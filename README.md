# Lean InfoView Widgets (Lean v4.34.0)

**Live:** https://qed64-showcase.fawadworkaddress.workers.dev/showcase/ (deployed 2026-10-05; Chromium-based desktop browser, ~16 GB RAM; first visit downloads ~680 MB).

Eight InfoView widget packages for Lean 4 and Mathlib (v4.34.0), and two ways to see them without installing anything:
a static gallery of their real panels, and the widgets running live in [QED64](https://github.com/FawadHa1der/QED64),
Lean compiled to wasm64 and running in the browser. Everything in this repository builds from a clone.

The v4.32.2 original of the packages is the git tag
[`lean-v4.32.2`](https://github.com/FawadHa1der/lean-widgets/tree/lean-v4.32.2). The port to v4.34.0 exists because
QED64 pairs its snapshots to Lean 4.34.0 and Mathlib `5ed2965`. Every package has a `PORT-NOTES.md` that lists what
changed and why ([Port summary](#port-summary-v4322--v4340)).

## What is in this repository

| Part | Directory | What it is | Build and test from a clone |
|---|---|---|---|
| Widget packages | [`packages/`](packages/) | The eight packages (table below) and `lean-widget-kit`, which re-exports all of them. Each is a self-contained Lake project with a compile-time test suite. | `./test-all.sh` |
| Static showcase | [`showcase/`](showcase/) | A static site with every widget's real panels: the `Html` trees the InfoView receives, rendered through the same React conversion. Deployed to GitHub Pages when enabled. | `./showcase/build.sh && node showcase/verify.mjs` |
| QED64 showcase | [`qed64-showcase/`](qed64-showcase/) | The widgets live in the stock, unmodified QED64 page: a gallery at `/showcase/` that drives QED64's editor and InfoView. It also holds the pins, native build, snapshot bakes, the Playwright UX suite and the Cloudflare deploy kit. QED64 itself is the git submodule `qed64-showcase/deps/qed64`. | `qed64-showcase/scripts/showcase.sh bootstrap --origin <origin>`, then `verify`, `gallery`, `ux` |
| CI | [`.github/workflows/`](.github/workflows/), [`ci/`](ci/) | `lean-ci.yml` (packages, static showcase, QED64-showcase static gates, optional Pages) and `qed64-deploy.yml` (QED64 showcase to Cloudflare). `ci/run-local.mjs` runs any job on your machine in a fresh clone. | `node ci/run-local.mjs --workflow .github/workflows/lean-ci.yml` |

```
packages/<name>/        the eight widget packages + lean-widget-kit (Lake projects)
showcase/               static gallery: probes/ (dump scripts), dumps/ (committed panel dumps), build.sh, verify.mjs
qed64-showcase/         the widgets in the QED64 page
  deps/qed64            QED64 at the served pin (git submodule, github.com/FawadHa1der/QED64)
  pins/<id>/            per QED64 pin: pin.json and QED64.lock.json (sha256 of every file that is served)
  gallery/              the /showcase/ page (rail of 8 examples, iframe of the stock page, a small bridge)
  scripts/              showcase.sh (one entry point), build-shell, fetch-artifacts, serve, deploy scripts, …
  tests/ux/             Playwright UX suite (34 tests)
  infra/                Cloudflare Worker (worker.js), its tests, wrangler pin, committed UX verdict record
  lean/                 widget examples, native goldens, native delta lists
  docs/                 architecture, build from source, deploy, results, history
test-all.sh             lake build + lake test in every package, with a summary table
.github/workflows/      lean-ci.yml, qed64-deploy.yml
ci/                     run-local.mjs (local workflow runner), install-elan.sh, rehearse-deploy.sh
```

## Get the code

```bash
git clone --recursive https://github.com/FawadHa1der/lean-widgets.git
cd lean-widgets
# an existing clone without the submodule: git submodule update --init
```

| You want to | You need |
|---|---|
| build and test the packages | [elan](https://github.com/leanprover/elan) (each package pins `leanprover/lean4:v4.34.0`), git, about 8 GB of disk per Mathlib-dependent package (each package fetches its own Mathlib build cache) |
| build the static showcase | the packages built (to regenerate the dumps), Python 3, Node (any recent version) |
| run the QED64 showcase | Node 26 with npm (the lock records v26.3.0; another 26.x is reported as a DRIFT), git, an artifact origin, about 2.4 GB of disk for the artifacts; macOS or Linux |
| run its browser tests | Playwright's Chromium (`npx playwright install chromium chromium-headless-shell`), 16 GB of RAM |
| rebuild its snapshot overlays (rarely) | the wasm64 kernel fork's toolchain, Docker, a large machine: [heavy path](qed64-showcase/docs/BUILD-FROM-SOURCE.md#heavy-path-rebuilding-the-overlays) |

## Build and test each part

### 1. The widget packages

```bash
./test-all.sh                       # lake build + lake test in all 9 packages; prints a GREEN/FAILED table, exit 1 on any failure
```

One package at a time:

```bash
cd packages/interval-inspector      # or any package directory
lake exe cache get                  # once, for the packages that depend on Mathlib (see the table below)
lake build && lake test
```

The tests are compile-time assertions (`#guard`, `#guard_msgs`, throwing `MetaM` asserts): a failing assertion is a
build error. To see a widget, open the package folder in VS Code with the Lean 4 extension and open
`<Lib>/Demo.lean` ([Quick start](#quick-start)).

### 2. The static showcase

```bash
./showcase/build.sh                 # regenerate showcase/dumps/ from showcase/probes/ (needs the packages built), assemble showcase/site/
./showcase/build.sh --no-dump       # or assemble from the committed dumps only (no Lean needed)
node showcase/verify.mjs            # every panel through React's development checks in Node; exit 1 on any error or warning
open showcase/site/index.html       # the gallery (site/verify.html is the same check in a browser)
```

After `./showcase/build.sh`, `git status` must show no change under `showcase/dumps/`: the committed dumps are
exactly what the probes produce. CI checks this. Details: [showcase/README.md](showcase/README.md).

### 3. The QED64 showcase

The light path serves and tests the showcase without building QED64's binaries or the widget snapshots. Run it in
`qed64-showcase/`:

```bash
cd qed64-showcase
cp .env.example .env.local          # optional: QED64_SHOWCASE_WORK (work dir, no spaces), artifact origins
scripts/showcase.sh bootstrap --origin <artifact origin>
scripts/showcase.sh verify          # chain of trust: sources, page, binaries and overlays against the lock
scripts/showcase.sh gallery         # static gallery gate (check-gallery + sim-gallery), prints the gallery hash
scripts/showcase.sh serve           # http://localhost:5190/showcase/  (stop: scripts/showcase.sh stop)
npx playwright install chromium chromium-headless-shell
scripts/showcase.sh ux              # the Playwright UX suite (34 tests, 25–40 min; one browser at a time on the host)
```

`bootstrap` checks out QED64's sources (the submodule), builds QED64's page from them with QED64's own build and
installs it only if all 58 files are byte-identical to the committed lock. It then fetches QED64's binaries and the
widget overlays by path from the artifact origin and checks every file's sha256 against the lock, links the served pin
and runs `verify`. So an origin never has to be trusted. `--origin` is the deployed showcase, or `scripts/serve.mjs`
of a checkout that has the artifacts (`PORT=5297 scripts/showcase.sh serve` there). `--qed64-origin
https://qed64.fawadworkaddress.workers.dev` serves QED64's own files. Until the showcase is deployed, the widget
overlays exist only on the machine that baked them.

Other checks: `node scripts/check-portable.mjs` (no machine path in code or configuration),
`node scripts/deploy-manifest.mjs --check` (deploy gates), `node --test infra/worker.test.mjs` (the Worker),
`scripts/showcase.sh pin list` (registered QED64 pins and their UX verdicts). `scripts/showcase.sh headless controls`
(the wasm runtime in Node, no browser) needs the build stores of the heavy path, so in a bootstrapped clone `verify`
lists those stores as ABSENT.

Full guide: [qed64-showcase/docs/BUILD-FROM-SOURCE.md](qed64-showcase/docs/BUILD-FROM-SOURCE.md). Everything
`showcase.sh` can do: [qed64-showcase/README.md](qed64-showcase/README.md).

### 4. CI on your machine

```bash
npm ci --prefix ci
node ci/run-local.mjs --workflow .github/workflows/lean-ci.yml                  # every job, each in a fresh clone of HEAD
node ci/run-local.mjs --workflow .github/workflows/lean-ci.yml --job qed64-static
ci/rehearse-deploy.sh                                                           # the deploy job against local fakes (macOS, after rehearse.sh all)
```

`run-local.mjs` runs the `run:` steps of the committed workflow file as GitHub would (shell flags, working
directories, env, outputs, `if:`, `needs`, matrix, `timeout-minutes`) and lists every place where it differs from a
GitHub runner. A full `lean-ci` run clones Mathlib once per Mathlib-dependent package, so it needs about 50 GB of disk.

## How the QED64 showcase works

```
 visitor's browser ── /showcase/ ──► gallery (rail of 8 examples)
                                        │ iframe, same origin
                                        ▼
                     / ?snapshots=snapshots/widgets8 ──► the STOCK QED64 page, built from deps/qed64, unmodified
                                        │ fetches
                                        ▼
        /runtime/  /profiles/  /snapshots/              QED64's wasm64 runtime, packs and stock snapshots
        /snapshots/widgets8/ (widgets7)                 our snapshot region: Mathlib + the eight packages
```

* **QED64 is a dependency, never a copy.** Its sources are the submodule `qed64-showcase/deps/qed64` at the served
  pin's commit. Several QED64 commits can be registered as pins (`pins/<id>/`); one is active. Each pin's
  `QED64.lock.json` records the sha256 of every file that is served.
* **The widgets reach the browser as a snapshot region.** The packages are compiled to oleans with the kernel fork's
  native64 compiler, staged on top of QED64's served Mathlib tree and baked by QED64's pinned wasm runtime into a
  snapshot (`widgets8`: the eight packages; `widgets7`: without DistLens). QED64 loads it like its own `mathlib`
  region, so the example files start with a plain `import Mathlib` / `import HasseView` and also work in VS Code.
* **The gallery** iframes the stock page from the same origin, checks that the region is paired with the runtime
  before navigating, fills the editor and moves the cursor through QED64's page API, and installs a small bridge for
  two InfoView defects of the shipped page (D1, D2 in the
  [upstream report](qed64-showcase/docs/UPSTREAM-REPORT-QED64.md)).
* **Tests:** a static gate (`showcase.sh gallery`), headless wasm checks in Node, and the Playwright UX suite.
  Every full `ux` run is recorded with the gallery, lock and overlay hashes it ran on. A run is a VERDICT only if it
  was green on unchanged inputs, and a deploy needs a verdict on exactly the inputs it deploys.

In depth: [ARCHITECTURE.md](qed64-showcase/docs/ARCHITECTURE.md) (how QED64 is consumed and which QED64 internals
are used), [qed64-showcase/README.md](qed64-showcase/README.md) (pins, results, limitations: visitors need a
Chromium-based desktop browser and 16 GB of RAM, and a first visit downloads about 700 MB).

## How it deploys

The QED64 showcase is hosted on Cloudflare the way lean4game and QED64 are: a Worker `qed64-showcase` serves the
shell (QED64's page and the gallery, about 18 MB of static assets) and streams the 2.4 GB of artifacts from the R2
bucket `qed64-artifacts` under the prefix `qed64-showcase/`, with the cross-origin isolation headers the wasm runtime
needs. A release has two steps:

1. **Artifacts to R2**, from the machine that has them: `scripts/upload-artifacts.sh` (rclone, copy only, never sync;
   the bucket is shared with QED64 and lean4game, so it refuses QED64's root and their prefixes, and any prefix other
   than `qed64-showcase/` needs an explicit override). CI never uploads artifacts, so no R2 key is ever stored in
   GitHub.
2. **The shell to the Worker**, either locally with `scripts/deploy-app.sh`, or from GitHub Actions:
   [`qed64-deploy.yml`](.github/workflows/qed64-deploy.yml) runs on pushes to `main` that touch `qed64-showcase/` and
   on manual dispatch. It builds QED64's page from the submodule (byte-identical to the lock), runs the gallery gate,
   requires the committed UX verdict record `qed64-showcase/infra/ux-verdict.json` to match the gallery, lock and
   overlays it deploys, checks that every artifact is already published (`SHOWCASE_ORIGIN`), runs
   `wrangler deploy` and smoke-tests the deployed URL. Without the secrets `CLOUDFLARE_API_TOKEN` and
   `CLOUDFLARE_ACCOUNT_ID` it logs a skip line and deploys nothing.

Both paths are rehearsed locally against fakes (`scripts/deploy-rehearsal/rehearse.sh all`, `ci/rehearse-deploy.sh`):
an rclone local backend and a local S3 endpoint for R2, `wrangler deploy --dry-run` and `wrangler dev --local`, inside
a macOS sandbox that blocks outbound traffic. The owner's steps for the first real deploy (token scope, the two
secrets, the `SHOWCASE_ORIGIN` variable) are the
[first deploy checklist](qed64-showcase/docs/DEPLOY-CLOUDFLARE.md#first-deploy-checklist).

The static showcase deploys to GitHub Pages from `lean-ci.yml`, only on a push to `main` with the repository variable
`DEPLOY_GITHUB_PAGES=true` and Settings → Pages → Source set to "GitHub Actions", and only from a fully green suite.

## Test results

Current state is printed by commands, not written here: `./test-all.sh`, `node showcase/verify.mjs`, and in
`qed64-showcase/` `scripts/showcase.sh verify`, `scripts/showcase.sh gallery` (`UX CURRENT …` names the newest
verdict on exactly the current gallery, lock and overlays, or says `UX STALE`), `scripts/showcase.sh pin list` and
`node scripts/deploy-manifest.mjs --check`. Dated records of full test rounds:
[qed64-showcase/docs/results/REPO-TEST-ROUND.md](qed64-showcase/docs/results/REPO-TEST-ROUND.md) (the whole
repository, main checkout and a fresh clone), [qed64-showcase/docs/UX-RESULTS.md](qed64-showcase/docs/UX-RESULTS.md)
and [qed64-showcase/docs/REPIN-LOG.md](qed64-showcase/docs/REPIN-LOG.md).

## The widget packages

Eight production-quality InfoView widget packages: the top-3 recommendations from the
visualization research (not part of this repository), a proof-state-integrated
graph visualizer, a universal tree/heap visualizer, and the three
next-frontier builds: Hasse diagrams, exact
probability distributions, and verified charting primitives. Every package is a self-contained Lake project on
**Lean `v4.34.0`**, builds green, and ships an adversarially-audited compile-time
test suite (`lake test`) — including mutation testing (deliberate logic mutations
must break the suite).

| Package | What it does | Deps | Assertions | Audit |
|---------|--------------|------|-----------:|-------|
| [`interval-inspector/`](packages/interval-inspector/) | Draws interval goals as a theme-aware SVG number line (open/closed endpoint glyphs, stacked subset/eq comparisons, mismatch shading, order-unknown captions) and suggests the right Mathlib lemma from a **62-entry table where every lemma is proof-verified against pinned Mathlib**, side conditions checked ready/missing against an order graph built from your hypotheses. Recognizes `Set.Icc/…/Iio`, `∪`/`∩` trees, **set-builder spellings** (`{x \| a ≤ x ∧ x < b}` → `Ico`), and `Set.Nonempty` / `= ∅` / `≠ ∅` shapes. `#interval_inspect` + panel + `interval_inspect?` tactic with click-to-insert. | Mathlib | 794 | pass (3 audited rounds, 6/6 mutations) |
| [`expr-xray/`](packages/expr-xray/) | Elaborated-expression inspector: collapsible tree with binder-role classification, universe levels, coercion badges, four preset views, `pp.explicit` block — and a **defeq-aware diff**: every mismatch is checked with `isDefEq` (reducible, then default transparency), re-ranked so *definitionally real* blockers come first, with an "all mismatches are defeq — syntactic only" verdict when nothing truly differs. `#xray` / `#xray_diff` + shift-click panel (1 selection = inspect, 2 = compare). | ProofWidgets | 520+ | pass (3 audited rounds, 6/6 mutations) |
| [`simp-lens/`](packages/simp-lens/) | `simp_lens` — a drop-in `simp` **with full location support** (`at h`, `at h ⊢`, `at *`): per-location rewrite filmstrips (origin, before/after, hover/go-to-def), the minimal `Try this: simp only [...] at …` (reusing core's `mkSimpOnly`), and per-lemma **exclusion previews** with essential/redundant badges. Equivalence tests *execute* the generated call and assert it reaches the same state as `simp`. | ProofWidgets | 390+ | pass (3 audited rounds, 6/6 mutations) |
| [`graph-scope/`](packages/graph-scope/) | `#graph_scope g` — evaluates a concrete `SimpleGraph` through its own `Fintype`/`DecidableRel` instances and draws a theme-aware SVG: circular layout, stats (order/size/degrees/components/connectivity/bipartiteness), **walk overlays** with step numbers, **highlight rings** for vertex subsets. Bipartiteness returns *validated evidence* — a proper 2-coloring or an odd-cycle witness the tests verify programmatically. All analysis is pure `#guard`-testable code over an extracted edge list. **Click-to-insert** (RPC panel): edges insert `example : (g).Adj a b := by decide`, vertices insert degree facts, and the stats line inserts (dis)connectivity facts — gated by an experimentally validated cost budget (kernel `decide` on `Connected` is expensive; the pure `diameter` analysis decides insertability). All texts round-trip-gated and compile-verified. | Mathlib | 340+ | pass (3 audited rounds + polish, 7/7 mutations) |
| [`tree-scope/`](packages/tree-scope/) | `#tree_scope v` — **universal tree/heap visualizer**: a `ToTreeView` typeclass with semantic instances (core `RBNode`/`RBMap` rendered in true red/black with **red-red, black-height, and BST-order violation overlays** using the type's own `cmp`; `Batteries.BinomialHeap` forests with rank badges and heap-property checks via the type's `le`; Mathlib `Tree`; `Std.TreeMap`), plus a **constructor-reflection fallback** that renders *any* concrete inductive value (whnf-evaluated, not `Repr`). `#tree_evolve` filmstrips a fold of operations with per-step added-node diff badges — watch RB rebalancing happen. Exact-ℚ tidy layout with proven non-overlap/centering/translation-invariance properties; Catalan gallery demo (all 14 four-node trees). | Mathlib | ~460 | pass (2 audited rounds + polish, 4/4 mutations) |
| [`hasse-view/`](packages/hasse-view/) | `#hasse V` — layered **Hasse diagrams** for any finite decidable order (fills the Zulip request open since Jan 2022): covering relation computed from the extracted ≤ table, ⊥/⊤/atom/coatom badges, **lattice verdict with a concrete no-join witness pair**, upset/downset shading, height and antichain bounds — and validity self-checks that *warn* about non-antisymmetric/non-transitive instances instead of drawing them wrong. **Click-to-insert** (RPC panel): cover edges insert `example : a ⋖ b := by decide` (the package ships its own lawful `DecidableRel (· ⋖ ·)` instance — Mathlib's pin has only `Bool`), ⊥/⊤ badges insert instance-free bound facts, and the non-lattice caption inserts the compiled no-join witness; every offered text is round-trip-gated and compile-verified. Demos: the powerset cube, divisors of 12 (shows the gate *rejecting* unparseable labels), a non-lattice bowtie. | Mathlib | 349 | pass (2 audited rounds, 5/5 mutations) |
| [`dist-lens/`](packages/dist-lens/) | `#dist` / `#dist_film` / `#chain` — **exact probability distributions** (probe-validated architecture): whitelist extraction of PMF terms to exact ℚ weights (uniform/bernoulli/binomial/pure/bind/map/ofFintype), bars + CDF + E/Var with fraction labels, bind-convolution filmstrips, and finite **Markov chains** with exact Gaussian-elimination stationary distributions. Ships the **`pmf_num` tactic**: every displayed weight offers a click-to-insert *compiled* proof `example : p x = 1/6 := by pmf_num` — including bernoulli's truncated-subtraction residues and stationary equations. | Mathlib | 270+ | pass (r1, 2/2 mutations + polish) |
| [`chart-kit/`](packages/chart-kit/) | **Verified-exact charting primitives** (the demand-backed build): `ChartSpec → Html` library for widget authors + `#chart` command — bar/line/step/scatter marks over exact ℚ data, nice-tick computation entirely in ℚ (no Float in the math), categorical bars, legends, themed palette, and `Series.ofFloats` with **bit-exact IEEE-754 decoding** (0.1 charts as its true rational value; NaN/∞ refused by name). | ProofWidgets | 256 | pass (r1, 2/2 mutations + polish) |

Each package README documents its architecture and an honest LIMITATIONS section
(e.g. the live panel round-trip needs a running Lean server and was verified
headlessly at the HTML-assembly level, not by driving VS Code).

## Quick start

Each package is independent. In VS Code:

```bash
cd packages/interval-inspector   # or any of the eight package directories
lake build
```

then open the package folder in VS Code with the Lean 4 extension and open
`<Lib>/Demo.lean` — every demo elaborates on build, so what you see is tested.

Run a package's test suite (compile-time assertions; a failing `#guard` /
`#guard_msgs` / assert is a build error):

```bash
lake test
```

Note: `interval-inspector`, `graph-scope`, `tree-scope`, `hasse-view` and `dist-lens` depend on Mathlib — run
`lake exe cache get` before the first build if you cloned them fresh.

## Using one in your own project

Add to your `lakefile.toml`, either from git (the package lives in a subdirectory of
this repository):

```toml
[[require]]
name = "interval-inspector"   # or any of the eight packages
git = "https://github.com/FawadHa1der/lean-widgets"
rev = "main"                  # better: a commit hash
subDir = "packages/interval-inspector"
```

or from a local checkout:

```toml
[[require]]
name = "interval-inspector"
path = "path/to/lean-widgets/packages/interval-inspector"
```

All eight pin `leanprover/lean4:v4.34.0`, Mathlib `v4.34.0` (rev `5ed2965`) and
ProofWidgets `106ff4fafc74ef4ac99d81dbf3ab399118f497a5` (the rev in Mathlib v4.34.0's
manifest, so mixing with Mathlib v4.34.0 projects is safe).

## How these were built and verified

- Implemented and then improved by parallel agents against detailed specs derived
  from the research phase (not part of this repository), grepping the **pinned local sources**
  (toolchain `src/lean/`, vendored ProofWidgets/Mathlib) as API ground truth.
- Every implementation and every improvement round was audited by fresh
  adversarial agents: full rebuild, every file read, stub/fake hunting, assertion
  census, README-claim verification, and **two mandatory mutations per round**
  that the test suite had to catch. Improvement audits additionally enforced
  no-regression: baselines could only grow, and every snapshot change needed a
  written justification.
- The process caught real bugs: an inverted suggestion side-condition direction
  that survived 408 assertions (fixed with direction-pinning tests), an
  `Expr.eqv` binder-annotation blind spot, and a weak component invariant that
  let a BFS mutation slip one test layer (strengthened and re-mutation-tested).
- A dedicated **adversarial bug-hunt round** (six hunters, evidence-only rule:
  every finding needs an executed repro) then found 43 findings — 13 major —
  including ALL-READY lemma suggestions on provably false statements (missing
  typeclass gating), ℕ division literals valued as rationals, continuum-semantics
  mismatch shading over discrete types, a timeout that escaped `catch` and failed
  `simp_lens` where `simp` succeeds, and false "NOT defeq" verdicts on
  metavariable-containing terms. Every fix round was audited by **re-executing
  the original repros** (33/34 verified fixed; the 34th is a documented stretch
  item) — and one fix round caught a real bug in another agent's fix
  (`mkAppM` leaving trailing instance args unapplied in the gating check).
- Test philosophy: all tests are compile-time (`#guard`, `#guard_msgs`, throwing
  MetaM asserts), deterministic on the pinned toolchain; CI needs nothing but
  `lake` — or `./test-all.sh` for the whole suite (incl. the `lean-widget-kit`
  meta-package: one require + `import LeanWidgetKit` = the entire suite).
  Combined: **3,200+ assertions** across the eight packages. The frontier builds were specced directly from probe-verified feasibility research — dist-lens's proof tactic implements a closer chain validated by executed probes before a line of the widget existed.

## Port summary (v4.32.2 → v4.34.0)

Ported package by package by parallel agents, each port adversarially audited (pin
check, assertion census, two mandatory mutations, re-execution of every claimed
transcript). Assertion counts are preserved or grown; no test was weakened. (Counts are the
line-anchored census each package's README now states; the audit follow-up found two
historic over-counts, tree-scope 478→476 and dist-lens 346→345, identical on both trees.)

| Package | Lean source changes | Assertions (4.32.2 → 4.34.0) |
|---------|--------------------|-----------------------------:|
| `expr-xray` | none (one docstring) | 456 → 456 |
| `chart-kit` | none (one module docstring) | 261 → 261 |
| `tree-scope` | none (byte-identical sources) | 476 → 476 |
| `hasse-view` | none | 463 → 463 |
| `simp-lens` | test helper renamed `assert` → `assertThat` (gotcha 7); two `#guard_msgs` pins follow the new `unusedSimpArgs` hint format | 404 → 404 |
| `interval-inspector` | `Mathlib.Data.Real.Basic` → `Mathlib.Basic.Real.Basic`; set-builder recognizer accepts `Set.ofPred` as well as the deprecated `setOf`; click-E2E uses `enableInitializersExecution : BaseIO Unit` | 845 → 846 |
| `graph-scope` | tests only: `import Lean.Meta.ExprDefEq`, `Lean.FileMap.ofString`, a new section pinning the flipped `backward.isDefEq.respectTransparency.types` default | 421 → 426 |
| `dist-lens` | `pmf_num`'s internal `simp` runs under `backward.isDefEq.respectTransparency.types false` (the 4.34 default breaks the fraction normalisation) | 345 → 345 |

**4.34.0 gotchas worth knowing** (each one cost a port iteration):

1. `setOf` is now a deprecated alias of `Set.ofPred` — a *distinct constant*, so
   `Expr.isAppOfArity` matchers must accept both.
2. `Mathlib.Data.Real.Basic` moved to `Mathlib.Basic.Real.Basic` (the old name is a
   `deprecated_module` shim that warns).
3. `Lean.Elab.enableInitializersExecution` is now `BaseIO Unit` (was `IO Unit`).
4. `String.toFileMap` is gone: use `Lean.FileMap.ofString`.
5. `backward.isDefEq.respectTransparency.types` defaults to **true**; tactics that
   relied on `isDefEq` unfolding through type-level definitions (here: `pmf_num`'s
   `simp` over `PMF` coercions) need the option set to `false` locally.
6. The `unusedSimpArgs` linter hint is now `[apply] simp` text instead of a
   strike-through diff, so any `#guard_msgs` pinning it must change.
7. A do-block line starting with the identifier `assert` now parses as core's new
   `doAssertion` element (experimental intrinsic verification), so a test helper
   named `assert` fails with "Function expected" plus a `WPMonad` instance error.
   Rename such helpers (`assert!` is unaffected).

## Links

* QED64 (in-browser wasm64 Lean): <https://github.com/FawadHa1der/QED64>, live at <https://qed64.fawadworkaddress.workers.dev>
* The wasm64 kernel fork (branch `qed64-wasm64`): <https://github.com/FawadHa1der/lean4/tree/qed64-wasm64>
* ProofWidgets: <https://github.com/leanprover-community/ProofWidgets4>; Mathlib: <https://github.com/leanprover-community/mathlib4>
* QED64 showcase docs: [README](qed64-showcase/README.md), [ARCHITECTURE](qed64-showcase/docs/ARCHITECTURE.md),
  [BUILD-FROM-SOURCE](qed64-showcase/docs/BUILD-FROM-SOURCE.md), [DEPLOY-CLOUDFLARE](qed64-showcase/docs/DEPLOY-CLOUDFLARE.md),
  [UPSTREAM-REPORT-QED64](qed64-showcase/docs/UPSTREAM-REPORT-QED64.md), [NEXT-STEPS](qed64-showcase/docs/NEXT-STEPS.md)
* Static showcase: [showcase/README.md](showcase/README.md)
* License: [LICENSE](LICENSE)
