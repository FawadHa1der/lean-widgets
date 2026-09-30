import TreeScope.Model

/-! # TreeScope: the semantic typeclass

`ToTreeView α` is the stage-2 semantic entry point: a type that knows how to
draw *itself* as a `TreeView` (with meaningful tones, sublabels and invariant
badges) provides an instance, and `#tree_scope` uses it **instead of** the
stage-1 constructor-reflection fallback.

Dispatch contract (implemented in `TreeScope.Widget.valueToTreeView`):

* `#tree_scope value` synthesizes `ToTreeView (type of value)` first and
  evaluates `toTreeView value`; when no instance exists it falls back to
  reflection;
* `#tree_scope (reflect := true) value` skips synthesis and always reflects;
* both paths share the same panel/text pipeline and the same
  `maxNodes`/`maxDepth` caps.

Instances shipped by TreeScope live under `TreeScope/Instances/`:
`Lean.RBNode`/`Lean.RBMap` (red–black invariants), `Batteries.BinomialHeap`
(heap invariants), Mathlib's `BinaryTree`, and `Std.TreeMap`.
-/

namespace TreeScope

/-- Types that can draw themselves as a semantic `TreeView`.

The produced tree should be a *view of the value's meaning* (keys, colors,
ranks, invariant annotations), not of its constructors — the constructor tree
is what the reflection fallback already shows.  Instances must be pure and
deterministic: the same value always produces byte-for-byte the same tree. -/
class ToTreeView (α : Type u) where
  /-- The semantic tree view of a value. -/
  toTreeView : α → TreeView

export ToTreeView (toTreeView)

/-- A `TreeView` *is* its own semantic view.  (Under reflection the same value
would render as its `TreeView.mk` constructor tree — the dispatch tests pin
both renderings of one value to prove which path ran.) -/
instance : ToTreeView TreeView := ⟨id⟩

end TreeScope
