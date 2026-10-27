# GraphScope

Proof-state-integrated `SimpleGraph` visualizer for the Lean 4 InfoView.

ProofWidgets can draw abstract node–edge data, but nothing takes a concrete
`SimpleGraph` from a Lean development, evaluates its adjacency through its own
`Decidable` instances, and draws it with proof-relevant overlays. GraphScope
does:

```lean
import GraphScope

open SimpleGraph GraphScope.Demo

#graph_scope (pathGraph 5)                        -- InfoView panel (layered: a path is a tree)
#graph_scope (text := true) (cycleGraph 5)        -- deterministic ASCII report
#graph_scope (pathGraph 5) walk [0, 1, 2, 3]      -- walk overlay, step numbers
#graph_scope (cycleGraph 6) highlight [0, 2, 4]   -- vertex highlight rings
#graph_scope (pathGraph 5) walk [1, 2] highlight [0, 4]
#graph_scope (pathGraph 5) highlight [0, 4] walk [1, 2]  -- clauses in any order
#graph_scope (pathGraph 5) layout circle          -- force the circular layout
#graph_scope (cycleGraph 6) layout layered        -- force BFS layers
```

The panel shows the graph with labeled vertices plus a stats block: order,
size, degree sequence with min/max, connected components, connectivity,
bipartiteness with *evidence* (a 2-coloring split or an odd-cycle witness),
and isolated vertices. **Forests are laid out as BFS-layered rooted trees**
(root = smallest vertex of each component, one row per BFS depth, components
side by side); all other graphs are drawn on a circle. `layout circle` /
`layout layered` force either layout. Colors are VS Code theme variables
(`var(--vscode-…, fallback)`), so the widget follows light/dark themes.
Vertex circles auto-grow so `Repr`-derived labels like `Sum.inl 0` fit
(capped at radius 40), and labels get a background-colored halo so they stay
legible over edge lines.

## Interactivity: click-to-insert

The panel is interactive: clicking a drawn **edge** inserts
`example : (g).Adj (a) (b) := by decide`, clicking a **vertex** inserts
`example : (g).degree (v) = k := by decide`, and clicking the **components
stats line** inserts `example : (g).Connected := by decide` (or its `¬` form
for disconnected graphs).  Insertions land on a new line *after* the
`#graph_scope` command (a zero-width edit — user text is never replaced),
with `(g)` the graph term verbatim from the command.  This is implemented
with ProofWidgets' `MakeEditLink` component behind an RPC panel
(`mk_rpc_widget%`), so the package is no longer JavaScript-free — it reuses
the two stock ProofWidgets components (`MakeEditLink`, the RPC panel shim)
and still ships no hand-written JS.

Two honesty mechanisms decide which links are offered:

* **The round-trip gate** (`GraphScope/Gate.lean`): a vertex term in an
  inserted example is built from the vertex's `Repr` label, and a label that
  parses to a *different* value than the drawn element would produce a
  compiling-but-wrong example.  So a link is attached only when the label
  parses, elaborates at the vertex type without leftover metavariables, and
  is *proved equal* to the drawn element via the type's own `DecidableEq`
  (evaluated through the same `evalExpr` bridge extraction uses, against the
  same `Fintype` enumeration).  This also catches two vertices sharing one
  lossy label: the label can equal at most one of them.  Gate-failed labels
  render as muted plain text ("not insertable"), never as links.
* **The connectivity cost model** (`GraphScope.connectivityCheck`,
  "The connectivity cost model" in `GraphScope/Insert.lean`): Mathlib's
  `Decidable G.Connected` instance builds every walk of length up to
  `dist u v` out of every vertex `u`, and every node of those walk trees
  decides `n` adjacencies, so the cost of `by decide` grows like
  degree^distance *and* with the cost of one adjacency decision — the
  4-cube (16 vertices, diameter 4) needs 328678 heartbeats with a cheap
  `Nat.xor` relation, `completeGraph (Fin 16)` 34124, and the 3-cube 16091
  through `Nat.xor` but 61840 through a `fromEdgeSet` literal.  So
  `Insert.walkWork` counts the enumeration exactly on the drawn graph (walk
  sets tested, walk-tree nodes, leaves), the panel *measures* the cost of one
  adjacency decision of the graph's own instance (`adjacencyCostOf?`: the
  heartbeats of the same `whnf` reduction `decide` runs, on
  `∀ a b, ¬ (G.Adj a b ∧ False)`, divided by its `n²` decisions; capped at
  the largest cost the budget allows), and `Insert.connectivityVerdict`
  combines both into a heartbeat estimate whose coefficients were fitted to
  `#count_heartbeats` measurements of a sweep of 250 graphs with at most 16
  vertices, as an upper envelope: the estimate is at least the measurement on
  every graph of the sweep, and on 50 further validation graphs; every one of
  the 156 offered examples of both sweeps compiles (`PORT-NOTES.md`).  The
  link is offered only when
  the estimate is at most 100000, half the default `maxHeartbeats`.  The
  recursion-depth domain of the v4.34 bound is kept (connected: diameter ≤ 4
  and ≤ 16 vertices; disconnected: ≤ 12 vertices), and inside it
  `Insert.recursionEstimate` (an upper envelope of bisected minimal
  `maxRecDepth`s, from the size, the longest walk and the heaviest walk by
  degree) must stay at most 500 of the default 512: high degrees along long
  walks fail on recursion depth before heartbeats (K₁₀ with a 3-vertex
  tail).  The estimate was
  calibrated only with instances that do not decide adjacency by quantifying
  over a finite type, so a second guard (`adjacencyCost`,
  `GraphScope/Gate.lean`) inspects the graph's own `DecidableRel` instance
  and the definitions it unfolds to, and withholds the link when it reaches
  a library quantifier instance (Mathlib's `Fintype.decidableForallFintype`
  / `decidableExistsFintype`, core's bounded `Nat` / `Fin` ones) or one of
  Mathlib v4.35.0's `CovBy` / `WCovBy` / `hasse` / `pathGraph` instances
  (which decide `⋖` by a pass over the vertex type).  Up to the v4.35 port
  the link was gated by the shape alone (diameter ≤ 4, ≤ 16 vertices), which
  offered a connectivity example that exhausts `maxHeartbeats 200000` for
  the 4-cube in every spelling measured (`Nat.xor` on `Fin 16`, `⊆`/`card`
  on `Finset (Fin 4)`, `hasse (Finset (Fin 4))`).

Every offered text is a self-contained `example … := by decide`; the test
suite *compiles every generated text* for the demo graphs and the cost
model's most expensive offered examples (the latter under half the default
heartbeat budget), so for those a suggestion that does not provably hold
cannot ship; for other graphs the cost model's calibration is the evidence
(see the limitations).  Scoping caveat: the inserted
example needs the same instances as the command itself, in scope *at the
insertion point*.  That holds for insertion into the same file (e.g.
`completeBipartiteGraph` demos work because the `DecidableRel` instance from
`GraphScope.Demo` covers both the command and the inserted example), but an
example pasted elsewhere needs those instances too.  `GraphScope` imports
`Mathlib.Combinatorics.SimpleGraph.Connectivity.Finite`, so the
`Decidable G.Connected` instance is in scope wherever `#graph_scope` is.

## Requirements on the graph term

`#graph_scope g` needs `g : SimpleGraph V` with synthesizable

* `Fintype V` — to enumerate the vertices,
* `DecidableEq V`,
* `DecidableRel g.Adj` — to decide each adjacency.

A missing instance is reported by name — and so is a *noncomputable* one: with
`open scoped Classical` in scope, instance synthesis happily produces
`Classical.propDecidable`, which cannot be evaluated; GraphScope rejects it
with an error naming the culprit instead of surfacing a raw compiler error.
Underdetermined terms (`(⊥ : SimpleGraph _)`) are also reported honestly.

Labels use `Repr V` when available (e.g. `Sum.inl 0` for
`completeBipartiteGraph`), falling back to plain indices. Mathlib's
`cycleGraph`, `⊥`, `⊤`/`completeGraph`, `fromRel` graphs (over decidable
relations) and `fromEdgeSet` over `Set` literals (`∅`, `{s(0, 1), s(1, 2)}`,
…) work out of the box — and so do `completeBipartiteGraph` and `pathGraph`
whenever you `import GraphScope`, because `GraphScope/Demo.lean` ships global
`decidable_of_iff`-derived `DecidableRel` instances for both (the click-E2E
suite relies on exactly these: inserted `by decide` examples compile in user
files that import only `GraphScope`). If you import a narrower module set,
copy those one-line instances from `Demo.lean`.

Since Mathlib v4.35.0, `hasse α` (for `[Fintype α] [DecidableLT α]`) and
`pathGraph n` are decidable out of the box as well, but through instances
that decide `a ⋖ b` by quantifying over the whole vertex type.  Such graphs render, and
their edge and vertex links are offered — the test suite compiles every one
of them for `hasse (Fin 4)`, for `hasse (Fin 64)` at the vertex cap, and,
with `Finset`-literal labels (`Mathlib.Data.Finset.Sort`, part of `import
Mathlib`), for `hasse (Finset (Fin 2))` … `hasse (Finset (Fin 4))` — but the
connectivity link is withheld for them by the adjacency-cost guard above,
even where it would compile, since the cost model was not calibrated for
that class.
`pathGraph` keeps its connectivity link under `import GraphScope`: Demo's
instance (one arithmetic comparison per adjacency, declared after Mathlib's)
is the one synthesis picks.

## Architecture

All analysis is pure and `#guard`-testable; elaboration only extracts data.

| Module | Role |
|---|---|
| `GraphScope/Model.lean` | `GraphData` (vertex count, normalized edge list, labels), smart constructor, adjacency/degree queries |
| `GraphScope/Algo.lean` | degree sequence, components (BFS), connectivity, bipartiteness with validated evidence, isolated vertices, overlay validation |
| `GraphScope/Layout.lean` | deterministic circular layout (vertex 0 at 12 o'clock, clockwise; `Float` only for pixel coordinates, rounded to `Nat`) |
| `GraphScope/Layered.lean` | forest detection, deterministic BFS-layered layout (pure `Nat` arithmetic), `LayoutMode` (auto/circle/layered) |
| `GraphScope/Render.lean` | theme-aware SVG + stats block; label-aware vertex sizing; deterministic ASCII report; `htmlToDebugString` serializer for tests |
| `GraphScope/Insert.lean` | pure click-to-insert layer: exact example-text builders, the connectivity cost model (`walkWork`, `WalkWork.heartbeats`, `connectivityVerdict`), `LinkInfo`, the link-parameterized panel body `renderPanelInteractive`, `componentNewTexts` test serializer |
| `GraphScope/Extract.lean` | impure: instance synthesis (with noncomputable-instance rejection), `Fintype.card` cap check, row-by-row `evalExpr`-based evaluation of adjacency with interrupt checks, labels |
| `GraphScope/Gate.lean` | impure: the round-trip honesty gate (`labelRoundTrips`), the connectivity link's impure inputs (`adjacencyCost`: does the graph's `DecidableRel` instance quantify over a finite type?; `adjacencyCostOf?`: the measured cost of one adjacency decision; `connectivityCheck`) and `computeInsertions` (gate every label, build verified `LinkInfo`) |
| `GraphScope/Widget.lean` | the `#graph_scope` command (RPC panel with `MakeEditLink` insertions + `(text := true)` mode; `walk`/`highlight`/`layout` clauses in any order, duplicates rejected) |
| `GraphScope/Demo.lean` | path/cycle/complete/empty/custom-disconnected/star/bipartite/`fromEdgeSet` demos, decidability workarounds, overlay and layout demos |

Vertex *indices* are positions in the `Fintype.elems` enumeration (for
`Fin n`, vertex `i` is literally `i`). Extraction is deterministic by
construction: the same term and instances always produce the same `GraphData`.

The panel follows the RPC-panel pattern (like Mathlib's tactic widgets and
interval-inspector's `interval_inspect?`): the command stores the pure
snapshot plus the gate-verified suggestions and the insertion range; the RPC
method reads the *live* document uri and version via `RequestM.readDoc` at
render time and only then builds the `MakeEditLink` props.  Building links at
command time would have to guess the uri from the file name and pin a stale
(or no) document version.  The panel body itself is a pure function
(`renderPanelInteractive`), so tests exercise the exact rendered tree —
including real `MakeEditLink` component props — without a live server.

Tests (`GraphScopeTests/`, `lake test`): 513 compile-time assertion commands
(counted as line-leading `#guard`, `#guard_msgs`, `#assert_graph_invariants`
and `#assert_gate` commands) — `#guard` pins on the pure layer (normalization,
algorithms with programmatically validated bipartition evidence, BFS
distances/diameter, circular *and* layered layout positions, serialized SVG,
insertion texts and panel link nodes), `#guard_msgs` pins of the exact
text-mode output, every user-facing error message *and* the exact insertion
suggestions per demo graph, round-trip-gate unit tests (positive and
negative), throwing extraction-invariant asserts on all demo graphs — and,
via `#assert_insertions_compile`, **compilation of every generated insertion
text** for the demo graphs, for the cost model's most expensive offered
graphs and for Hasse diagrams decided through Mathlib's quantifying instance
(so for these graphs a click can never insert a statement that does not
compile; for other graphs see the limitations) — plus `#connectivity_gate`
pins of both connectivity verdicts (the walk-work estimate, and the
adjacency-cost guard's validated / quantifying / unknown, and whether the
connectivity link is offered) on both classes of instance, exact pins of the
walk counts, heartbeat and recursion estimates, and `#adjacency_cost` band
pins of the measured adjacency cost.

## Limitations (honest)

* **Vertex cap: 64.** Above `Fintype.card V = 64` the command refuses with an
  error (quadratically many adjacency checks and an unreadable drawing
  otherwise). The cap is checked before any adjacency is decided.
* **The cap bounds the *number* of adjacency checks, not the cost of one.**
  Each check runs the graph's own `DecidableRel` code; for graphs defined in
  the current file that code runs in Lean's IR interpreter (10–100× slower
  than compiled imports), and a single check can take arbitrarily long.
  Extraction decides adjacency row by row and runs `Lean.Core.checkSystem`
  between rows, so editor cancellation and heartbeat limits take effect
  between rows — but a single pathological adjacency decision (at most 63 per
  row) cannot be interrupted from the outside. Note also that Lean heartbeats
  advance on allocation, so an allocation-heavy slow predicate hits
  `maxHeartbeats` between rows, but a purely arithmetic one (small-`Nat`
  recursion) barely advances the counter — for those, only editor
  cancellation bounds the run.
* **Walks are index lists, not `g.Walk a b` terms.** `walk [0, 1, 2]` takes
  vertex indices into the enumeration and validates consecutive adjacency.
  Term-level extraction of `SimpleGraph.Walk` values (their `support` lists
  live in `V`, not in indices, and need their own evaluation pass) is not
  implemented.
* **Enumeration order is the runtime representative of `Fintype.elems`.**
  Extraction evaluates compiled code (`Lean.Meta.evalExpr`, `safety :=
  .unsafe`, the standard Mathlib command pattern) and reads the multiset's
  runtime list. This is deterministic for a fixed instance, and for `Fin n` it
  is `0, …, n-1`, but a custom `Fintype` instance dictates its own vertex
  order.
* **The term parses at `term:max`**, so applications need parentheses:
  `#graph_scope (pathGraph 5)`, not `#graph_scope pathGraph 5`.
* **Two layouts only: BFS-layered (auto for forests) and circular.** No
  force-directed or planar layout; dense cyclic graphs near the cap will have
  many crossing edges, and `layout layered` on a cyclic graph draws non-tree
  edges as chords between rows.
* **Very long vertex labels can still overflow.** Vertex circles grow with
  the longest label but are capped at radius 40 (≈10 characters); beyond
  that, the halo keeps labels readable but they extend past their circle.
* **Repeated walk steps over the same edge** draw their step numbers at the
  same midpoint (they overlap visually; the text mode lists every step).
* **Non-`Fin` vertex labels require a computable `Repr V`**; without one
  (or with a noncomputable one), labels fall back to indices — which then
  fail the round-trip gate for non-numeric vertex types, so such graphs get
  no edge/vertex links (the connectivity link needs no labels and survives).
* **Inserted `by decide` proofs are compile-verified for the demo sizes, not
  for arbitrary graphs.**  Adjacency and degree facts decided fine up to the
  64-vertex cap in experiments on this pin — also through Mathlib's
  quantifying `hasse` instance (`hasse (Fin 64)`: at most ~1.7k of the
  200k-heartbeat budget per degree fact; `hasse (Finset (Fin 6))` with
  `Finset` labels: ~12k) — but a user graph with an expensive `DecidableRel`
  can still make an inserted example slow to check; the connectivity link is
  gated by the cost model (see above) because there `decide` demonstrably
  blows up inside the cap.
* **The connectivity cost model is calibrated, not exact.**  The walk
  enumeration is counted exactly and the adjacency cost is measured on the
  graph's own instance, but the coefficients that combine them were fitted
  to the sweep's graphs (paths, cycles, complete and complete bipartite
  graphs, hypercubes, generalized Petersen graphs, circulants, grids, tori,
  trees, wheels, lollipops, barbells, disjoint unions) and spellings
  (closed arithmetic, `List` and `fromEdgeSet` literals, `Finset` `⊆`/`card`,
  Mathlib's and `GraphScope.Demo`'s instances; vertex types `Fin n`,
  `Finset (Fin k)`, `Sum`, products, functions, subtypes).  The estimate is
  at least the measurement on every graph of the sweep and the budget is
  half of `maxHeartbeats`, but a graph whose cost depends on something the
  model does not see — say an expensive vertex equality with a cheap
  adjacency — could still push an offered example over the default budget.
  Conversely the model is conservative: graphs whose example compiles
  comfortably (`completeBipartiteGraph (Fin 8) (Fin 8)`, ~130k heartbeats;
  the 3-cube as a `fromEdgeSet` literal, ~62k) are withheld when the
  estimate exceeds the budget.  Measuring the adjacency cost adds the
  heartbeats of `n²` adjacency decisions to each `#graph_scope` whose walk
  work fits the budget (well under a second at 16 vertices).
* **The adjacency-cost guard is a deny-list, not a cost analysis.**  It
  recognises adjacency decided through the library quantifier instances
  (Mathlib's `Fintype` ones, core's bounded `Nat` / `Fin` ones) and Mathlib
  v4.35.0's `CovBy` / `WCovBy` / `hasse` / `pathGraph` instances, by searching
  the synthesized instance and the definitions it unfolds to.  A hand-written
  instance that walks the vertex type by other means (its own recursion, a
  list of all vertices) is not recognised; its adjacency cost is still
  measured, so it gets the connectivity link only when the estimate at that
  cost fits the budget (outside the calibrated class of instances, though).
  Conversely the guard is
  conservative: any hit — even a quantifier over a tiny fixed type —
  withholds the link.  Quantifiers inside proofs count only where the proof
  term is inlined in a definition's value: Lean abstracts tactic proofs in an
  instance body into auxiliary theorems, which the search does not unfold
  (sound, since `decide` never evaluates a proof).
* **Suggestions refresh with elaboration.**  The insertion range and the
  document version are those of the last elaboration; clicking after editing
  but before the file re-elaborates targets the editor's current document
  state like any LSP edit (the RPC reads the live version), but the panel's
  facts are only as fresh as the last run of the command.
* **Edge/vertex links are SVG anchors.**  `MakeEditLink` renders an `<a>`;
  inside the drawing it becomes an SVG anchor element wrapping the edge line
  or the vertex group, while the components-line link is a regular HTML
  anchor (the exact pattern interval-inspector's panel uses).  Tests pin the
  component nodes and their props; this round did not include a live-editor
  visual audit of the SVG anchors' hover styling.
* **Walk and highlight overlays stay display-only** (no `g.Walk`-term
  insertion), and there is no `interval_inspect?`-style tactic mode.

## Build / test

Toolchain `leanprover/lean4:v4.35.0` (Mathlib `v4.35.0`, ProofWidgets `df72b022`
via Mathlib's manifest), pinned via the lockfile; see `PORT-NOTES.md` for the
v4.34.0 → v4.35.0 and v4.32.2 → v4.34.0 port records.

```
lake build   # library + demos
lake test    # 513 compile-time assertion commands
```
