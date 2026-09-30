# Interval Inspector

A Lean 4 InfoView widget that draws interval goals and hypotheses as a **labeled
number line** and suggests applicable Mathlib lemmas — including their ordering side
conditions, checked against your hypotheses and reported as *ready* or *missing*.

Motivating scenario: proving `Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c`. The
inspector shows two bars joining at `b` and suggests `Set.Ioc_union_Ioc_eq_Ioc`,
reporting whether `a ≤ b` and `b ≤ c` are already known.

Pure Lean: the widget is built entirely from the ProofWidgets `Html`/SVG DSL — no
custom JavaScript, no npm.

## What it looks like (honest description)

The rendering is an inline SVG in the InfoView:

- **theme-aware colors**: every color is a VS Code CSS variable with a hex
  fallback (`var(--vscode-charts-blue, #3b82f6)` for bars,
  `var(--vscode-editor-foreground, #333333)` for axis/labels/captions,
  `var(--vscode-charts-red, #ef4444)` for mismatch shading, and so on), so the
  drawing and the ready/missing badges follow the light/dark InfoView theme;
- a horizontal axis with a tick and label per endpoint atom;
- one semi-transparent colored bar per interval leaf (blue = LHS / single side,
  green = RHS), rays extending to the panel edge for `Ici`/`Iio`/etc., a
  full-width bar for `univ`, a `∅` glyph for the empty set, a single dot for `{a}`;
- endpoint glyphs: **filled circle = closed (endpoint included), hollow circle =
  open (excluded)** — this convention is pinned by tests;
- for `⊆` / `⊂` / `=` the two sides are stacked as aligned rows sharing the axis,
  labeled `⊆ L` / `⊇ R` etc.; union/intersection composites render each leaf as its
  own thin bar with a `∪`/`∩` marker at the row's right edge;
- a purple triangle marker for the member in `x ∈ s` shapes;
- for `Set.Nonempty s`, `s ≠ ∅` / `¬(s = ∅)` / `∅ ≠ s`, `s = ∅` and `∅ = s`
  shapes, a caption tying the shape to its order condition (e.g.
  `Nonempty ↔ a < b` for `Ioc a b`, with `DenselyOrdered` / `NoMaxOrder` /
  `NoMinOrder` requirements named when the iff needs them — and shown **only when
  the element type actually has the instance**: over `ℕ` no
  `Nonempty always holds (NoMinOrder)` caption appears for `Iio 0`, because the
  claim would be false);
- a muted "from set-builder" badge when any interval was recognized from
  set-builder notation (`{x | a ≤ x ∧ x < b}` and friends);
- **red shading** over every region provably covered by the LHS but *not* provably
  covered by the RHS ("mismatch candidates") — only when the order graph fully
  determines the endpoint order; for `=` shapes **both directions** are shaded
  (RHS-beyond-LHS regions carry an `R-only` mark in their `data-mismatch`
  attribute); over element types *without* a `DenselyOrdered` instance the open
  segments between adjacent atoms are **not** shaded (over `ℕ` they may be empty
  — `Ico 0 2 ⊆ Icc 0 1` is true) and a muted caption explains why, and likewise
  the outer rays need `NoMinOrder` / `NoMaxOrder`;
- when the order between two atoms is unknown, the atoms are flagged `a?` in amber
  and a caption `order unknown between a, b` is shown instead of guessing; layout
  then falls back to rank-based placement with unordered atoms sharing slots;
- below the drawing, the suggestion list: lemma name, tactic text (clickable in
  tactic mode — it replaces the `interval_inspect?` call), one badge per side
  condition (`a ≤ b ✓ ready` / `✗ missing`), and a
  `missing instance: DenselyOrdered ✗` badge when the lemma needs a typeclass the
  element type does not have (checked with `Meta.synthInstance?` during analysis);
  condition-free matches whose instance is missing (they would assert a possibly
  false goal outright, e.g. `Set.nonempty_Iio` over `ℕ`) are **suppressed** and
  replaced by an explanatory note below the list.

There are no screenshots in this repository; the description above is generated
from the same code paths the tests assert on.

## Usage in VS Code

Build first (`lake build`; Mathlib oleans come from `lake exe cache get`).

**Command mode** — anywhere in a file:

```lean
import IntervalInspector

#interval_inspect (Set.Ioc (1:ℝ) 2 ∪ Set.Ioc 2 3 = Set.Ioc 1 3)
#interval_inspect ∀ (a b c : ℝ), a ≤ b → b ≤ c → Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c
#interval_inspect (text := true) (fun (a b : ℝ) => Set.Ioc a b)  -- logs `Ioc a b: (a───b]`
```

Put the cursor on the command; the panel appears in the InfoView. `∀`/`fun` binders
are peeled, and comparison binders (`a ≤ b → …`) are harvested as ordering facts.
The command elaborates like `#check` (`runTermElabM`), so it works inside
`section variable (a b : ℝ) …` — and section hypotheses such as `(h : a ≤ b)`
feed the harvested ordering facts.
The `(text := true)` variant logs a deterministic ASCII rendering instead
(`[`/`]` closed, `(`/`)` open, `-∞`/`∞` for rays) — that is what `#guard_msgs`
tests assert on.

Recognized statement shapes: `x ∈ s`, `s ⊆ t`, `s ⊂ t`, `s = t`,
`Set.Nonempty s`, `s ≠ ∅` / `¬(s = ∅)` / `∅ ≠ s` / `¬(∅ = s)`, and bare
interval terms. Interval
expressions are `Set.Icc/Ico/Ioc/Ioo/Ici/Iic/Ioi/Iio`, `Set.univ`, `∅`, `{a}`,
set-builder spellings (`{x | a ≤ x ∧ x ≤ b}` ↦ `Icc a b`, the other one- and
two-sided `≤`/`<` combinations likewise, conjuncts in either order), combined
with `∪`/`∩`:

```lean
#interval_inspect ({x : ℝ | 0 ≤ x ∧ x < 1} ⊆ Set.Icc 0 1)  -- suggests Set.Ico_subset_Icc_self
#interval_inspect (Set.Ioc (1:ℝ) 2).Nonempty               -- suggests Set.nonempty_Ioc
```

**Tactic mode**:

```lean
example {a b c : ℝ} (h₁ : a ≤ b) (h₂ : b ≤ c) :
    Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c := by
  interval_inspect?
  exact Set.Ioc_union_Ioc_eq_Ioc h₁ h₂
```

With the cursor on `interval_inspect?`, the panel shows the goal's number line and
suggestions; hypotheses (`h₁ h₂`, including `≥`/`>`/`=`, and transitive
consequences — also through variables that are *not* interval endpoints, e.g.
`a ≤ b → b ≤ c` makes `a ≤ c` ready even when `b` appears in no interval) feed
the side-condition readiness. Clicking a suggestion inserts its tactic text in
place of the `interval_inspect?` call (via `MakeEditLink`). Shift-click a
hypothesis in the InfoView to inspect that hypothesis instead of the goal.
`IntervalInspector/Demo.lean` walks through twelve scenarios.

## Architecture

```
IntervalInspector/
  Model.lean      -- pure model: IntervalKind (8 kinds + univ/empty/singleton),
                  -- Endpoint (pp + literal value), Leaf (with fromSetBuilder
                  -- provenance), Tree (leaf|union|inter),
                  -- Shape (mem|subset|ssubset|eq|nonempty|neEmpty|term),
                  -- ASCII/debug renderings
  Recognize.lean  -- Expr matchers (syntactic): Set.Ixx/univ/∅/{a}, set-builder
                  -- interval spellings ({x | a ≤ x ∧ x < b} etc.), ∪/∩ trees,
                  -- x ∈ s, s ⊆ t (both HasSubset and Set-order LE.le spellings),
                  -- s ⊂ t, s = t, Set.Nonempty s, s ≠ ∅ / ¬(s = ∅) / ∅ ≠ s,
                  -- bare terms; binder peeling; atoms keyed by expression
                  -- identity (colliding display strings get ′ marks); literal
                  -- extraction (division literals only over DivisionRing types);
                  -- ordering-fact harvesting from the local context; instance
                  -- availability (InstAvail) via Meta.synthInstance?
  OrderGraph.lean -- pure transitive closure of ≤/</= facts over endpoint atoms
                  -- PLUS auxiliary hypothesis-only atoms (chains through
                  -- intermediates survive restriction back to the shape's atoms),
                  -- automatic literal comparison, contradiction flagging,
                  -- O(1) queries (knownLe/knownLt/knownEq/unknown/totallyOrdered)
  Layout.lean     -- pure deterministic x-coordinates in ℚ: proportional when all
                  -- atoms are literals, otherwise rank-based (longest known chain),
                  -- unordered atoms flagged
  Render.lean     -- pure Html SVG assembly (theme-aware colors via --vscode-*
                  -- CSS variables with hex fallbacks) + deterministic serializer
                  -- (htmlToDebugString) + provable-coverage semantics feeding the
                  -- mismatch shading (instance-gated: possibly-empty regions are
                  -- excluded, `=` shapes shaded in both directions) +
                  -- instance-gated emptiness/nonemptiness captions
  Suggest.lean    -- curated table of 62 verified Mathlib lemma entries keyed by
                  -- shape patterns, side conditions checked against the order
                  -- graph, per-entry typeclass needs checked against InstAvail
                  -- (suppression / missing-instance markers), fallbacks when
                  -- nothing applies (all fallback tactics importable from this
                  -- package's own closure)
  Widget.lean     -- #interval_inspect command (HTML + text modes; runTermElabM,
                  -- so section variables work), the InspectorParams RPC panel
                  -- (mk_rpc_widget%), and the interval_inspect? tactic
  Demo.lean       -- twelve demo scenarios
IntervalInspectorTests/  -- see below
```

Everything downstream of recognition is pure (`Expr`-free, `Float`-free — all
geometry in `ℚ`, emitted as integer pixels), so the whole pipeline is
deterministically testable with `#guard`: same input, same output, byte for byte.

## Testing

`lake test` (the test driver builds `IntervalInspectorTests`; a failing `#guard`,
`#assert_*` or `#guard_msgs` is a compile error).

- **ModelTests** — kind flags (the open/closed glyph convention), ASCII/desc/debug
  renderings (including the new `nonempty`/`neEmpty` shapes and the `*`
  set-builder provenance marker), atom collection/dedup.
- **RecognizeTests** — all 8 kinds over ℝ *and* ℕ, univ/∅/{a}, all statement
  shapes (including `Set.Nonempty` / `≠ ∅` / `¬(… = ∅)` and the mirrors
  `∅ ≠ s` / `¬(∅ = s)`), all 8 set-builder mappings plus swapped conjunct
  orders, nested ∪/∩ trees, literal extraction (naturals, negatives, fractions —
  and division literals staying *symbolic* over ℕ/ℤ), binder-fact harvesting,
  instance-availability pins for ℕ/ℤ/ℝ/ℝ×ℝ, a shadowed-binder collision repro
  (two distinct fvars both displayed `a` must key as `a`/`a′`, not merge), and
  25 negatives (Finset.Icc, Set.range, plain set variables, list membership,
  complements, set-builder disjunctions / wrong-variable comparisons /
  non-comparison bodies / triple conjunctions / `≥` spellings, …) that must
  return `none`.
- **OrderGraphTests** — direct facts, transitivity with strictness propagation,
  equality merging, literal comparison, unknown pairs, contradiction safety.
- **LayoutTests** — literal proportionality (exact ℚ positions), rank placement,
  chain-awareness, determinism (compute twice, compare), unordered flagging.
- **RenderTests** — substring assertions on the serialized SVG: every glyph
  open/closed combination, stacked rows, mismatch shading present in `[0,3] ⊆ [1,2]`
  and *absent* in the correct `Ioc`-join equality, **both-direction shading for
  `=` shapes** (`R-only` marks, pinned on the false `Icc 0 1 = Icc 0 2` repro in
  both orientations), **discrete-type gating** (no segment shading over ℕ, the
  explanatory caption, `Region.knownInhabited` unit tests, end-to-end ℕ/ℝ SVG
  pins), instance-gated emptiness captions (density/unboundedness iffs dropped
  when the type lacks the instance), unknown-order caption present without facts
  and gone with them, themed colors (every element a `var(--vscode-…, #hex)`
  expression with the fallback inside the `var()`, and no bare palette hex
  outside one), emptiness/nonemptiness captions, the "from set-builder" badge,
  plus unit tests of the coverage semantics.
- **SuggestTests** — for **each of the 62 table entries**: a firing test (the entry
  matches exactly its intended shape) *and* an `example` proving the suggested lemma
  closes that goal against the pinned Mathlib (the `nonempty_Ioo` /
  `Ioo_eq_empty_iff` / `nonempty_Ioi` / `nonempty_Iio` examples run over `ℝ`
  because those lemmas genuinely need `DenselyOrdered` / `NoMaxOrder` /
  `NoMinOrder`); pinned per-entry instance needs mirroring the pinned Mathlib
  statements' typeclass contexts; instance gating both at the pure level
  (suppression notes, `missing instance` markers, never-`ALL-READY`) and
  **end to end over the actual repro types** (`(Set.Iio (0:ℕ)).Nonempty`,
  `Iic ∪ Ici = univ` over `ℝ × ℝ`, `Ico (1/3:ℕ) (1/2:ℕ)`, transitive chaining
  through a non-endpoint variable — each paired with an `example` proving the
  statement true/false as claimed); plus pinned generated-condition directions
  for every entry, readiness reporting (ready / missing / transitively-derived /
  literal-derived / strict-vs-nonstrict) and fallback behavior.
- **CommandTests** — 21 message-exact `#guard_msgs` tests of
  `#interval_inspect (text := true)` (plus four in `Demo.lean`), including
  section-`variable` scenarios (with a section hypothesis feeding readiness) and
  the `∅ ≠ s` mirror spelling, and substring tests of the assembled panel HTML
  including the themed badges.
- **ImportClosureTests** — imports *only* `IntervalInspector` and proves every
  tactic and lemma constant mentioned in a fallback suggestion is available and
  working in the package's own import closure (the `linarith` repro included).
- **ClickE2E** — click simulation for the tactic-mode suggestions: the real
  `MakeEditLink` payload (range + newText) is applied to realistic user files
  with the server's own UTF-16 edit application (surrogate-pair pins included)
  and the edited file is recompiled by Lean's in-process frontend. Thirteen
  suggestion families covered: all-ready suggestions must close the goal with
  zero messages; missing-condition suggestions must leave *exactly* the pinned
  unsolved-goals report (that is the designed contract — the badges warned
  you); corrupted-payload negatives must fail.

528 `#guard`s, 141 `#assert_*` command assertions, 25 `#guard_msgs`,
97 lemma-verifying `example`s, 3 throwing checks in the shadowed-binder
`run_cmd` repro, and the ClickE2E click-simulation checks — 810+ assertions
in total.

## Limitations (honest)

- **Syntactic recognition only.** No `whnf`/unfolding is attempted. Set-builder
  intervals are recognized purely syntactically: the eight one- and two-sided
  `≤`/`<` bound combinations (conjuncts in either order), but *not* `≥`/`>`
  spellings (`{x | x ≥ a}`), disjunctions, or bodies that are not comparisons of
  the binder. `Finset.Icc`, `Set.range`, complements, images/preimages and set
  variables are deliberately out of scope (a `Finset` number line would suggest a
  continuum that is not there).
- **Atoms are keyed by structural expression identity** (after metadata
  stripping), with pretty-printed strings used only for display (colliding
  displays get `′` marks: `a`, `a′`). Structural, not definitional: `a + 0` and
  `a` are *distinct* atoms, and a hypothesis about one says nothing about the
  other.
- **Ordering facts do not cross casts or arithmetic.** A hypothesis `n ≤ m` over
  `ℕ` does not order the cast endpoints `(↑n : ℝ)` and `(↑m : ℝ)`, and no rule
  knows `x < x + 1` — such atoms are reported order-unknown even when a human
  sees the order instantly.
- **Literal extraction** covers `OfNat` naturals, `Int.negSucc`-style integers,
  `-n` negations and — only over types with a `DivisionRing` instance — `n / d`
  divisions (recursively). Over `ℕ`/`ℤ`, division literals stay *symbolic*
  (`(1/3 : ℕ)` is truncating division; assigning it the value ⅓ would fabricate
  false ordering facts), so e.g. `Ico (1/3:ℕ) (1/2:ℕ)` reports its strict
  condition as missing rather than evaluating the endpoints to 0.
  Scientific-notation literals (`1.5e3`) and casts (`(↑n : ℝ)`) are not
  evaluated — they become symbolic atoms.
- **Mixed literal/symbolic layout is rank-based**, not anchored: with atoms `a`,
  `2`, `7` and `a ≤ 2`, positions are evenly spaced ranks, not proportional to 2
  and 7.
- **Mismatch shading is a *candidate* report**, gated on a totally ordered
  endpoint set. Segment coverage of a union assumes all interval endpoints are
  atoms on the line (true for recognized shapes), and "not provably covered" is
  weaker than "provably not covered". Over element types without `DenselyOrdered`
  (resp. `NoMinOrder`/`NoMaxOrder`) instances, open segments (resp. outer rays)
  are never shaded — honest, but it means *fewer* highlighted regions on discrete
  types, not a claim that those regions match.
- **Instance checks are best-effort `Meta.synthInstance?` calls** in the goal's
  context. If synthesis fails for a type that morally has the instance (unusual
  setups, synthesis depth), the inspector degrades toward *fewer* claims —
  suggestions gain a `missing instance` marker or are suppressed, captions
  disappear — never toward asserting more.
- **Suggestions insert `refine`-with-`?_` skeletons** (or `exact`/`rw` when there
  are no side conditions); they do not attempt to discharge the side-condition
  goals themselves, even when a matching hypothesis exists. Fallback suggestions
  are unverified heuristics and are labeled as such (their tactic scripts may
  fail on the goal at hand — but every tactic they mention is importable from
  this package's own import closure, so they at least always parse).
- **The interactive panel needs a live Lean server**; the RPC round-trip and the
  click-to-insert behavior are exercised manually in VS Code, not by `lake test`
  (the HTML the panel produces *is* tested, via its pure assembly function).
- The `interval_inspect?` tactic changes no goals (it only attaches a panel); it is
  allow-listed for Mathlib's unused-tactic linter.
- **Theme-awareness relies on `--vscode-*` CSS variables** being defined by the
  webview; outside VS Code (or if a theme omits a variable) the hex fallbacks
  inside each `var()` apply, which approximate the default light theme.

## Toolchain

Pinned: `leanprover/lean4:v4.32.2`, Mathlib `v4.32.2`, ProofWidgets (as resolved in
`lake-manifest.json`). Never run `lake update`; fetch Mathlib oleans with
`lake exe cache get`.
