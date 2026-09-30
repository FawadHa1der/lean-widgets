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
* **The connectivity budget** (`Insert.connectivityInsertable`): Mathlib's
  `Decidable G.Connected` instance enumerates walks, and `by decide` blows
  the elaborator budget already for some 10-vertex graphs, so the
  connectivity link is offered only inside an experimentally validated
  bound (connected: diameter ≤ 4 and ≤ 16 vertices; disconnected: max
  degree ≤ 2 and ≤ 12 vertices) — see the docstring for the compile
  evidence on this pin.

Every offered text is a self-contained `example … := by decide`; the test
suite *compiles every generated text* for the demo graphs, so a suggestion
that does not provably hold cannot ship.  Scoping caveat: the inserted
example needs the same instances as the command itself, in scope *at the
insertion point*.  That holds for insertion into the same file (e.g.
`pathGraph` demos work because the file's local `DecidableRel` instance
covers both the command and the inserted example), but an example pasted
elsewhere needs those instances too.  `GraphScope` imports
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
…) work out of the box — and so do `pathGraph` and `completeBipartiteGraph`
whenever you `import GraphScope`, because `GraphScope/Demo.lean` ships global
`decidable_of_iff`-derived `DecidableRel` instances for both (the click-E2E
suite relies on exactly this: inserted `by decide` examples compile in user
files that import only `GraphScope`). If you import a narrower module set,
copy those one-line instances from `Demo.lean`.

## Architecture

All analysis is pure and `#guard`-testable; elaboration only extracts data.

| Module | Role |
|---|---|
| `GraphScope/Model.lean` | `GraphData` (vertex count, normalized edge list, labels), smart constructor, adjacency/degree queries |
| `GraphScope/Algo.lean` | degree sequence, components (BFS), connectivity, bipartiteness with validated evidence, isolated vertices, overlay validation |
| `GraphScope/Layout.lean` | deterministic circular layout (vertex 0 at 12 o'clock, clockwise; `Float` only for pixel coordinates, rounded to `Nat`) |
| `GraphScope/Layered.lean` | forest detection, deterministic BFS-layered layout (pure `Nat` arithmetic), `LayoutMode` (auto/circle/layered) |
| `GraphScope/Render.lean` | theme-aware SVG + stats block; label-aware vertex sizing; deterministic ASCII report; `htmlToDebugString` serializer for tests |
| `GraphScope/Insert.lean` | pure click-to-insert layer: exact example-text builders, the connectivity budget, `LinkInfo`, the link-parameterized panel body `renderPanelInteractive`, `componentNewTexts` test serializer |
| `GraphScope/Extract.lean` | impure: instance synthesis (with noncomputable-instance rejection), `Fintype.card` cap check, row-by-row `evalExpr`-based evaluation of adjacency with interrupt checks, labels |
| `GraphScope/Gate.lean` | impure: the round-trip honesty gate (`labelRoundTrips`) and `computeInsertions` (gate every label, build verified `LinkInfo`) |
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

Tests (`GraphScopeTests/`, `lake test`): 422 compile-time assertion commands
(counted as line-leading `#guard`, `#guard_msgs`, `#assert_graph_invariants`
and `#assert_gate` commands) — `#guard` pins on the pure layer (normalization,
algorithms with programmatically validated bipartition evidence, BFS
distances/diameter, circular *and* layered layout positions, serialized SVG,
insertion texts and panel link nodes), `#guard_msgs` pins of the exact
text-mode output, every user-facing error message *and* the exact insertion
suggestions per demo graph, round-trip-gate unit tests (positive and
negative), throwing extraction-invariant asserts on all demo graphs — and,
via `#assert_insertions_compile`, **compilation of every generated insertion
text** for the demo graphs, so a click can never insert a statement that does
not hold.

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
  64-vertex cap in experiments on this pin, but a user graph with an
  expensive `DecidableRel` can still make an inserted example slow to check;
  the connectivity link is budget-gated (see above) because there `decide`
  demonstrably blows up inside the cap.
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

Toolchain `leanprover/lean4:v4.32.2`, Mathlib pinned via the lockfile.

```
lake build   # library + demos
lake test    # 422 compile-time assertion commands
```
