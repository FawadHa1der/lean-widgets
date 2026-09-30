# Lean InfoView Widgets — Implementations

Eight production-quality InfoView widget packages: the top-3 recommendations from the
[visualization research](../02-proposals-ranked.md), a proof-state-integrated
graph visualizer, a universal tree/heap visualizer, and the three
[next-frontier builds](../04-next-frontiers.md): Hasse diagrams, exact
probability distributions, and verified charting primitives. Every package is a self-contained Lake project on
**Lean `v4.32.2`**, builds green, and ships an adversarially-audited compile-time
test suite (`lake test`) — including mutation testing (deliberate logic mutations
must break the suite).

| Package | What it does | Deps | Assertions | Audit |
|---------|--------------|------|-----------:|-------|
| [`interval-inspector/`](interval-inspector/) | Draws interval goals as a theme-aware SVG number line (open/closed endpoint glyphs, stacked subset/eq comparisons, mismatch shading, order-unknown captions) and suggests the right Mathlib lemma from a **62-entry table where every lemma is proof-verified against pinned Mathlib**, side conditions checked ready/missing against an order graph built from your hypotheses. Recognizes `Set.Icc/…/Iio`, `∪`/`∩` trees, **set-builder spellings** (`{x \| a ≤ x ∧ x < b}` → `Ico`), and `Set.Nonempty` / `= ∅` / `≠ ∅` shapes. `#interval_inspect` + panel + `interval_inspect?` tactic with click-to-insert. | Mathlib | 794 | pass (3 audited rounds, 6/6 mutations) |
| [`expr-xray/`](expr-xray/) | Elaborated-expression inspector: collapsible tree with binder-role classification, universe levels, coercion badges, four preset views, `pp.explicit` block — and a **defeq-aware diff**: every mismatch is checked with `isDefEq` (reducible, then default transparency), re-ranked so *definitionally real* blockers come first, with an "all mismatches are defeq — syntactic only" verdict when nothing truly differs. `#xray` / `#xray_diff` + shift-click panel (1 selection = inspect, 2 = compare). | ProofWidgets | 520+ | pass (3 audited rounds, 6/6 mutations) |
| [`simp-lens/`](simp-lens/) | `simp_lens` — a drop-in `simp` **with full location support** (`at h`, `at h ⊢`, `at *`): per-location rewrite filmstrips (origin, before/after, hover/go-to-def), the minimal `Try this: simp only [...] at …` (reusing core's `mkSimpOnly`), and per-lemma **exclusion previews** with essential/redundant badges. Equivalence tests *execute* the generated call and assert it reaches the same state as `simp`. | ProofWidgets | 390+ | pass (3 audited rounds, 6/6 mutations) |
| [`graph-scope/`](graph-scope/) | `#graph_scope g` — evaluates a concrete `SimpleGraph` through its own `Fintype`/`DecidableRel` instances and draws a theme-aware SVG: circular layout, stats (order/size/degrees/components/connectivity/bipartiteness), **walk overlays** with step numbers, **highlight rings** for vertex subsets. Bipartiteness returns *validated evidence* — a proper 2-coloring or an odd-cycle witness the tests verify programmatically. All analysis is pure `#guard`-testable code over an extracted edge list. **Click-to-insert** (RPC panel): edges insert `example : (g).Adj a b := by decide`, vertices insert degree facts, and the stats line inserts (dis)connectivity facts — gated by an experimentally validated cost budget (kernel `decide` on `Connected` is expensive; the pure `diameter` analysis decides insertability). All texts round-trip-gated and compile-verified. | Mathlib | 340+ | pass (3 audited rounds + polish, 7/7 mutations) |
| [`tree-scope/`](tree-scope/) | `#tree_scope v` — **universal tree/heap visualizer**: a `ToTreeView` typeclass with semantic instances (core `RBNode`/`RBMap` rendered in true red/black with **red-red, black-height, and BST-order violation overlays** using the type's own `cmp`; `Batteries.BinomialHeap` forests with rank badges and heap-property checks via the type's `le`; Mathlib `Tree`; `Std.TreeMap`), plus a **constructor-reflection fallback** that renders *any* concrete inductive value (whnf-evaluated, not `Repr`). `#tree_evolve` filmstrips a fold of operations with per-step added-node diff badges — watch RB rebalancing happen. Exact-ℚ tidy layout with proven non-overlap/centering/translation-invariance properties; Catalan gallery demo (all 14 four-node trees). | Mathlib | ~460 | pass (2 audited rounds + polish, 4/4 mutations) |
| [`hasse-view/`](hasse-view/) | `#hasse V` — layered **Hasse diagrams** for any finite decidable order (fills the Zulip request open since Jan 2022): covering relation computed from the extracted ≤ table, ⊥/⊤/atom/coatom badges, **lattice verdict with a concrete no-join witness pair**, upset/downset shading, height and antichain bounds — and validity self-checks that *warn* about non-antisymmetric/non-transitive instances instead of drawing them wrong. **Click-to-insert** (RPC panel): cover edges insert `example : a ⋖ b := by decide` (the package ships its own lawful `DecidableRel (· ⋖ ·)` instance — Mathlib's pin has only `Bool`), ⊥/⊤ badges insert instance-free bound facts, and the non-lattice caption inserts the compiled no-join witness; every offered text is round-trip-gated and compile-verified. Demos: the powerset cube, divisors of 12 (shows the gate *rejecting* unparseable labels), a non-lattice bowtie. | Mathlib | 349 | pass (2 audited rounds, 5/5 mutations) |
| [`dist-lens/`](dist-lens/) | `#dist` / `#dist_film` / `#chain` — **exact probability distributions** (probe-validated architecture): whitelist extraction of PMF terms to exact ℚ weights (uniform/bernoulli/binomial/pure/bind/map/ofFintype), bars + CDF + E/Var with fraction labels, bind-convolution filmstrips, and finite **Markov chains** with exact Gaussian-elimination stationary distributions. Ships the **`pmf_num` tactic**: every displayed weight offers a click-to-insert *compiled* proof `example : p x = 1/6 := by pmf_num` — including bernoulli's truncated-subtraction residues and stationary equations. | Mathlib | 270+ | pass (r1, 2/2 mutations + polish) |
| [`chart-kit/`](chart-kit/) | **Verified-exact charting primitives** (the demand-backed build): `ChartSpec → Html` library for widget authors + `#chart` command — bar/line/step/scatter marks over exact ℚ data, nice-tick computation entirely in ℚ (no Float in the math), categorical bars, legends, themed palette, and `Series.ofFloats` with **bit-exact IEEE-754 decoding** (0.1 charts as its true rational value; NaN/∞ refused by name). | ProofWidgets | 256 | pass (r1, 2/2 mutations + polish) |

## Quick start

Each package is independent. In VS Code:

```bash
cd interval-inspector   # or any of the eight package directories
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

Add to your `lakefile.toml` (adjust the path/git source to where you host it):

```toml
[[require]]
name = "interval-inspector"   # or any of the eight packages
path = "path/to/the/package"
```

All eight pin `leanprover/lean4:v4.32.2` (the ProofWidgets rev matches Mathlib
v4.32.2's manifest, so mixing with Mathlib v4.32.2 projects is safe).

## How these were built and verified

- Implemented and then improved by parallel agents against detailed specs derived
  from the [research phase](../README.md), grepping the **pinned local sources**
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
  Combined: **3,200+ assertions** across the eight packages. The frontier builds were specced directly from [probe-verified feasibility research](../04-next-frontiers.md) — dist-lens's proof tactic implements a closer chain validated by executed probes before a line of the widget existed.

## Showcase site

[showcase/](showcase/) builds a static gallery of every widget's real panels —
the exact `Html` trees the InfoView receives, rendered through the same React
conversion the InfoView uses: `./showcase/build.sh` produces `site/index.html`
(public gallery) and `site/verify.html` (strict build: any React error or
warning on any panel fails the page). `.github/workflows/pages.yml` runs the
full test suite, rebuilds the showcase, and deploys it to GitHub Pages on every
push — the site only deploys from a fully green suite.

Each package README documents its architecture and an honest LIMITATIONS section
(e.g. the live panel round-trip needs a running Lean server and was verified
headlessly at the HTML-assembly level, not by driving VS Code).
