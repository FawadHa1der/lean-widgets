# TreeScope

A universal tree/heap visualizer for the Lean 4 InfoView: one widget, a
semantic typeclass (`ToTreeView`, stage 2) with invariant-checking instances
for red–black maps, binomial heaps, binary trees and `Std.TreeMap`, plus a
reflection fallback (stage 1) that renders **any concrete inductive value**
as its constructor tree.

```lean
import TreeScope

#tree_scope [10, 20, 30]                 -- HTML panel in the InfoView
#tree_scope (text := true) [10, 20, 30]  -- deterministic text report
#tree_scope (reflect := true) value      -- skip the instance, force reflection

#tree_evolve (Lean.RBMap.empty : Lean.RBMap Nat String compare) [
  (·.insert 1 "a"), (·.insert 2 "b"), (·.insert 3 "c")]   -- filmstrip
```

```
info: tree: 3 nodes, depth 2
2:"b" · bh=1 <red>
  1:"a" · bh=1 <black>
  3:"c" · bh=1 <black>
invariants ok
```

Built against `leanprover/lean4:v4.34.0` + Mathlib `v4.34.0` +
ProofWidgets (pure-Lean `Html` DSL only, no npm build).  Ported unchanged from
the v4.32.2 build; see `PORT-NOTES.md` for the verification and 4.34 notes.

## Stage 2: semantic dispatch

`#tree_scope value` first tries to synthesize `ToTreeView (type of value)`
and evaluates `toTreeView value` (the standard compiled-`evalExpr` pattern);
without an instance it falls back to reflection.  `(reflect := true)` forces
reflection — the dispatch tests pin *both* renderings of the same value.
Both paths share the panel/text pipeline and the `maxNodes = 128` /
`maxDepth = 64` caps; cap errors name the measured quantity (`the value has
151 nodes, more than the limit of 128`, exact on the semantic path and for
compacted chains, a measured lower bound otherwise).

Flags may appear in **any order**, each at most once, with an explicit
`true` or `false` value (`(text := false)` is the default panel mode);
unknown or duplicated flags get a targeted error naming the supported flags,
not a parser error.

### Shipped instances

| Instance | View | Invariants checked (violation tone + named badge) |
|---|---|---|
| `Lean.RBNode α (fun _ => β)` | color tones, `key:value` labels, `bh=k` sublabels | `red-red` (guilty child), `bh` (subtree black-height mismatch) |
| `Lean.RBMap α β cmp` | same | + `ord` (BST order **with the `cmp` from the type**) |
| `Batteries.BinomialHeap α le` | forest under a synthetic `heap` root, `rank=r` sublabels | `heap` (edge violating the `le` from the type), `rank`, `rank-order` |
| Mathlib `BinaryTree α` | values as labels; both-`nil` children elided, single `nil` as `∅` stub | — (order overlay is the separate helper `BinTree.treeWithOrderCheck`) |
| `Std.TreeMap α β cmp` (stretch) | `key:value`, stored `sz=n` sublabels | `sz` (stored size ≠ recomputed), `ord` (cmp from the type) |
| `TreeView` | identity | — (makes the two dispatch paths observably different) |

A tree with violations gets a caption (panel row + last text-mode line):
`⚠ r.0.0 (red-red), r.1 (bh)`; a checked-but-clean tree captions
`invariants ok` (derived generically from tones/badges by
`Render.healthCaption?`).  RB trees carry their color tones; the heap and
`Std.TreeMap` views mark a checked-and-clean **non-empty** value with the
`ok` tone on the root, so all invariant-checking instances caption
`invariants ok` when clean.  Empty containers (`(empty)`, `heap · n=0`)
stay neutral and uncaptioned — nothing was checked.  The health summary for
raw RB trees is also available as the pure `RB.rbHealth`.

### `#tree_evolve` filmstrips

`#tree_evolve init [op1, …, opN]` elaborates `init : α` and each
`opI : α → α`, folds, and renders one frame per step (semantic view when an
instance exists) with the operation source as the step caption.  Diff
badging: a node whose `(label, path)` pair is absent from the previous frame
gets a `new` badge, plus the `added` tone when it had no semantic tone of its
own (RB colors and violations are never overwritten — a rotated node shows
its color *and* the badge).  The mirror diff is counted too: `(label, path)`
pairs of the previous frame absent from the current one appear as `−r gone`
in the caption (`step 5: … (+3 new, −4 gone)`), so a deletion never reads as
pure growth.  Caps: ≤ 16 steps, the per-frame node/depth caps — a frame that
crosses a cap is reported as a `#tree_evolve` error naming the offending
step (`#tree_evolve: step 3: the value has 218 nodes, …`).  `(text := true)`
prints every frame's report plus the per-step counts, all pinned by tests.

## What reflection shows

`#tree_scope (reflect := true) value` (or any value without an instance)
recursively `whnf`-evaluates the value in `MetaM`:

* each node is a constructor (short name: `cons`, `some`, `mk`, …);
* **explicit** fields with inductive types become child subtrees, in field
  order;
* literal-like explicit fields fold into the node label instead: `Nat` and
  `String` literals, `Char`s (`'a'`), `Int`s (`-3`), `Float`/`Float32`s
  (compiled-evaluated and `toString`-printed, e.g. `1.500000` — floats never
  whnf-reduce to constructors, so a `Float` field renders folded rather than
  failing), free variables (by name); other non-inductive fields (e.g.
  functions) fold as `⟨pretty-printed⟩`;
* implicit fields and proofs (`Prop`-typed fields, e.g. `Fin.mk`'s bound) are
  skipped;
* if a folded field comes *after* a child field, all fields are shown
  positionally with `_` for children (`mk _ 3`), so the label never
  misrepresents field order.

This is genuine **term-structure reflection of the evaluated value** — not
`Repr` (no instance needed), and not a syntax tree: `#tree_scope (2 + 2)`
renders the single node `4`, and reflecting a `def` unfolds it.

**Chain compaction**: a top-level value that is a pure single-child
constructor spine deeper than the 64-level cap (a `List`/`Array` cons chain,
nested `Option`s, …) is rendered as the compact depth-2 sequence
`chain · n=len` with one leaf per spine node, instead of being refused — so
`#tree_scope (List.range 70)` draws 72 nodes at depth 2.  Chains that fit
the cap keep the ordinary one-node-per-level spine rendering.

## Architecture

| Module | Contents |
|---|---|
| `TreeScope/Model.lean` | `TreeView` rose tree (label, sublabel, badges, `NodeTone`, collapsed flag, children); size/depth/paths, path access & modification, mapping utilities, deterministic ASCII rendering |
| `TreeScope/Layout.lean` | Tidy layout in exact `Rat`: recursive bounding-box packing, parents centered exactly over first/last child midpoint; `gridLayout` for galleries |
| `TreeScope/Render.lean` | Theme-aware SVG (`var(--vscode-…, #hex)` everywhere), tone → color table, legend, invariant caption (`healthCaption?`), collapsed stubs, `renderForest` grid, `htmlToDebugString` test serializer |
| `TreeScope/Reflect.lean` | The `MetaM` reflection fallback with depth/node caps |
| `TreeScope/ToTreeView.lean` | The semantic typeclass + the `TreeView` identity instance |
| `TreeScope/Instances/RB.lean` | RB view + pure checkers (`hasRedRed`, `bhConsistent`, `ordered`, `blackHeight`, `rbHealth`); `RBNode`/`RBMap` instances |
| `TreeScope/Instances/Heap.lean` | Binomial-heap forest view + `heapOrdered`/`ranksValid`; `BinomialHeap` instance |
| `TreeScope/Instances/MathlibTree.lean` | `BinaryTree` instance, BST order overlay, `allBinTrees`/`catalanGallery` |
| `TreeScope/Instances/StdTreeMap.lean` | `Std.TreeMap` instance + `sizesConsistent`/`ordered` checkers |
| `TreeScope/Widget.lean` | The `#tree_scope` command: instance-first dispatch, `(text := true)` / `(reflect := true)` flags |
| `TreeScope/Evolve.lean` | Pure `diffMark`, `Frame`, filmstrip renderers, the `#tree_evolve` command |
| `TreeScope/Demo.lean` | Demos: reflection basics (incl. Float folding and the compacted 70-element chain); RB semantic vs reflect, 8-insert RB evolution, a shrinking `erase` step, the hand-crafted invalid RB tree, heap forest + deleteMin filmstrip, `BinaryTree` + order overlay, the 14-tree Catalan gallery, `Std.TreeMap` |

Everything after elaboration is pure and `#guard`-testable; the exact-`Rat`
layout and the fixed element order make every rendering byte-for-byte
deterministic.

### Layout guarantees (checked as pure test checkers over a 12-tree family)

(a) no two nodes overlap (same-row centers ≥ `nodeW` apart, rows ≥
`nodeH + vGap` apart); (b) every parent sits exactly over the midpoint of its
first and last child's roots (single-child parents directly above the child);
(c) determinism; (d) subtree translation invariance (a subtree's internal
geometry is independent of its siblings).

### Tones

`neutral` | `rbRed` (red outline) | `rbBlack` (filled, theme-inverted label) |
`ok` (green) | `violation` (red + red ring + automatic `⚠` badge) |
`highlight` (purple) | `added` (green ring).  The full mapping is pinned by
tests, one assertion per tone.

### The Catalan gallery

`BinTree.allBinTrees n` enumerates the binary-tree shapes with `n` internal
nodes as a deterministic list (ordered by left-subtree size); the tests prove
it equals Mathlib's `BinaryTree.treesOfNumNodesEq n` *as a set* (matching
cardinality `= catalan n = 14` for `n = 4`, no duplicates, every element a
member).  The gallery itself deliberately does not iterate the `Finset`:
`Finset` element order is a `Multiset` quotient artifact, not a stable
contract, while the gallery must be byte-for-byte deterministic.

## Limitations (honest)

* **No contour-based tightening.**  The layout packs sibling subtrees by
  bounding *box*, not by contour: two tall-but-narrow subtrees with
  interleavable outlines are still placed box-beside-box, so wide shallow
  trees over deep spines can be wider than a Reingold–Tilford layout would
  be.  All four layout properties hold regardless.
* **Hard caps:** both paths refuse values nested deeper than 64 levels or
  with more than 128 nodes (pinned errors naming the measured quantity —
  exact on the semantic path and for compacted chains, a lower bound when
  the reflection traversal aborts mid-way).  Chain compaction lifts the
  depth cap for pure cons chains, but the *node* cap still applies: a
  150-element list is refused with its exact node count (152).
* **Chain compaction is top-level and pure-spine only.**  A deep chain
  *inside* a larger value, or an over-deep chain that branches somewhere
  (e.g. a 70-element list of lists), is still refused — with a measured
  lower bound on the depth and a hint that chains count one level per
  element.  The spine probe walks at most 1024 levels; beyond that only
  `at least 1088 levels` is reported.
* **Reflection needs concrete values.**  Anything that does not `whnf` to a
  constructor application (functions, opaque constants, stuck terms, terms
  with free/meta variables) is rejected with a pinned error.  Well-founded or
  very large definitions may also be slow to reduce with kernel `whnf`.
* **Semantic instances need `Repr`** on keys/values (labels have to be
  printed); the raw `RBNode` instance covers only the non-dependent
  `RBNode α (fun _ => β)` shape (which is what `RBMap` uses) — a genuinely
  dependent `RBNode α β` has no instance and falls back to reflection.
* **A raw `RBNode` has no comparator in its type**, so its instance skips the
  BST order check; order-check raw nodes explicitly via
  `RB.rbNodeView … (some cmp)`.  Similarly, one-`leaf` RB/TreeMap children
  are elided, so the *side* of a single child is conveyed by its key, not by
  position (for keyless `BinaryTree` the `∅` stub preserves the side
  instead).
* **Violation tone replaces the RB color tone** on guilty nodes (the badge
  names the broken invariant; the color is recoverable from the `bh`
  sublabel context but not shown on that node).
* **Diff badging compares `(label, path)` only:** a changed *sublabel* (e.g.
  a heap's `n=` count or a changed RB `bh=`) does not mark a node as new, and
  a value moved to a different path counts as new there *and* gone at its old
  path (no move detection) — a binomial-tree merge or an RB rotation
  therefore reads as `+k new, −k gone` even though no entry was inserted or
  deleted.  Replacing the `(empty)` placeholder counts as `−1 gone`.
* **`#tree_evolve` captions reprint the operation source text** (trimmed) —
  they are as readable as the source; a multi-line op prints with its inner
  line breaks.
* **`Std.TreeMap` balance factors are not checked** (`delta`/`ratio`
  invariant of the size-balanced tree) — only stored-size consistency and
  order.
* **Char/Int/Float folding is best-effort:** a `Char`/`Int` field that does
  not reduce to a literal, or a `Float` that fails compiled evaluation,
  falls through to ordinary (structural) reflection.  Folded floats print
  with Lean's `Float.toString` (`1.5` renders as `1.500000`) — fixed
  formatting, deterministic, but not the shortest decimal.
* **Node labels are not measured.**  Node boxes are fixed-size (76×36); very
  long constructor names or folded literals can overflow the box visually
  (SVG text is not clipped).  The ASCII mode always shows full labels.
* **`ratStr` truncates at 6 fractional digits.**  The layout only produces
  dyadic rationals (denominators `2^k`, one halving per tree level), so
  coordinates render exactly for any tree within the caps; the truncation is
  deterministic in all cases.
* **Fixed viewport, no interactivity.**  No pan/zoom/click-to-collapse; the
  `collapsed` flag is set programmatically (`TreeView.collapseAt`).  The
  `#tree_scope` command itself has no collapse syntax.
* **Grid width bound is honest but soft:** a single tree wider than
  `maxRowWidth` gets its own row and the grid reports the true (larger)
  width.
* **`Lean.RBMap` is a deprecated module in Lean v4.34.0** (`deprecated_module`,
  since 2026-06-01; successor `Std.TreeMap`, whose instance is also shipped).
  The `RBNode`/`RBMap` instances still work because this package reaches the
  module through `import Lean`; a consumer importing `Lean.Data.RBMap`
  *directly* gets a deprecation warning unless the import carries a trailing
  `-- deprecated_module: ignore` comment.  Expect the instance to be retired
  when upstream drops the module.

## Tests

`lake test` builds `TreeScopeTests`: 476 compile-time assertions
(404 `#guard` + 72 message-exact `#guard_msgs`, counting only lines that
*start* with the command — two module docstrings also mention `#guard_msgs`
and are not assertions).  `TreeScope/Demo.lean` holds
no pins; its `#tree_scope` / `#tree_evolve` / `#html` demos only have to
elaborate under `lake build`.  Stage 1: model measures and ASCII
pins, the four layout properties (+ row alignment and bounds containment)
over 12 crafted trees, pinned exact coordinates, tone→color table pins, SVG
substring assertions, grid packing pins, reflection shape pins (incl. Float
folding and the compacted / boundary / refused chain family), flag-grammar
pins (reversed order, `:= false`, unknown and duplicate flags), and every
user-facing error message (with measured cap quantities).  Stage 2: dispatch
pins (semantic vs forced reflection of the same value, caps on the semantic
path), RB checker true/false tables over crafted valid/invalid raw trees
plus pinned views and `rbHealth` strings and the `ofList`-always-healthy
property over six input shapes, heap forest/rank pins with crafted
`WF`-impossible violations (plus the `ok`-root / `invariants ok` caption
pins for clean heaps and `Std.TreeMap`s), the `BinaryTree` `nil` convention
and order overlay, `diffMark`/`removedCount` unit tests and fully pinned
filmstrips (including the rotation step, a shrinking `erase` step, the
17-step cap and per-step cap errors), and the Catalan gallery cross-checked
against Mathlib.
