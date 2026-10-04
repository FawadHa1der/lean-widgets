# Lean InfoView Widgets — Implementations (Lean v4.34.0 port)

> This repository holds the **v4.34.0 / Mathlib v4.34.0 port** of the widget suite. The
> v4.32.2 original is the git tag [`lean-v4.32.2`](https://github.com/FawadHa1der/lean-widgets/tree/lean-v4.32.2) of this repository.
> The port exists so the suite can be baked into [QED64](https://github.com/FawadHa1der/QED64)
> (in-browser wasm64 Lean), which pairs its snapshots to Lean 4.34.0 + Mathlib `5ed2965`.
> Every package carries a `PORT-NOTES.md` listing exactly what changed and why; see
> [Port summary](#port-summary-v4322--v4340) below.

## Repository layout

```
packages/<name>/   the eight widget packages + lean-widget-kit (each a self-contained Lake project)
showcase/          static React gallery of every widget's real panels (built from probes/ dumps)
qed64-showcase/    the widgets running live in the stock QED64 page (in-browser wasm64 Lean): pins, native
                   build of packages/, snapshot bakes, gallery, Playwright UX suite, Cloudflare deploy kit
  deps/qed64       QED64 itself, as a git SUBMODULE at the served pin (github.com/FawadHa1der/QED64)
test-all.sh        lake build + lake test in every package, with a summary table
.github/workflows/ CI for the packages, the static showcase, portability and the QED64 page built from source
```

Clone with the submodule:

```bash
git clone --recursive https://github.com/FawadHa1der/lean-widgets.git
# (an existing clone: git submodule update --init)
```

Build from source: `./test-all.sh` builds and tests every package (stock `elan`; the Mathlib-dependent
packages need `lake exe cache get` once), `./showcase/build.sh && node showcase/verify.mjs` builds and checks
the static showcase. The QED64 showcase builds QED64's page from the submodule and fetches QED64's binaries and the
widget overlays by content hash: `qed64-showcase/scripts/showcase.sh bootstrap --origin <origin>` (macOS or Linux; no
QED64 checkout, kernel build or Docker needed). Rebuilding the overlays themselves needs the wasm64 kernel fork's
toolchain. See [qed64-showcase/docs/BUILD-FROM-SOURCE.md](qed64-showcase/docs/BUILD-FROM-SOURCE.md) and
[qed64-showcase/docs/ARCHITECTURE.md](qed64-showcase/docs/ARCHITECTURE.md).

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

## Showcase site

[showcase/](showcase/) builds a static gallery of every widget's real panels —
the exact `Html` trees the InfoView receives, rendered through the same React
conversion the InfoView uses: `./showcase/build.sh` produces `site/index.html`
(public gallery) and `site/verify.html` (strict build: any React error or
warning on any panel fails the page). `.github/workflows/pages.yml` runs the
full test suite, rebuilds the showcase and verifies it headlessly on every push
and pull request; it deploys the site to GitHub Pages only when the repository
variable `DEPLOY_GITHUB_PAGES` is `true` (and Settings → Pages → Source is
"GitHub Actions"), and only from a fully green suite.

Each package README documents its architecture and an honest LIMITATIONS section
(e.g. the live panel round-trip needs a running Lean server and was verified
headlessly at the HTML-assembly level, not by driving VS Code).


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
