import TreeScope.Render
import TreeScope.ToTreeView
import TreeScope.Instances.RB
import Std.Data.TreeMap

/-! # TreeScope instances: `Std.TreeMap` (stretch)

In this toolchain the internals are public all the way down:
`Std.TreeMap.inner : Std.DTreeMap`, `Std.DTreeMap.inner :
Std.DTreeMap.Internal.Impl`, and `Impl` is the plain inductive
`inner (size : Nat) (k : α) (v : β k) (l r : Impl α β) | leaf` of a
size-balanced BST — so a real semantic instance is possible.

The view labels nodes `key:value` (values abbreviated as for `RBMap`),
sublabels each node with its **stored** size field `sz=n`, and checks two
invariants:

* `sz` badge + `violation` tone where the stored size disagrees with the
  recomputed subtree size (`1 + realSize l + realSize r`);
* `ord` badge + `violation` tone where a key falls outside its ancestor
  bounds w.r.t. the comparator **from the map's type**.

Balance-factor checking (the `delta`/`ratio` invariant) is deliberately not
implemented — see README limitations.

`leaf` children are elided exactly as for `RBNode` (keys disambiguate the
side of a single child); an empty map is the single node `(empty)`.
-/

namespace TreeScope.STM

open Std.DTreeMap.Internal (Impl)

universe u v

variable {α : Type u} {β : Type v} {γ : α → Type v}

/-- The recomputed number of entries of a raw `Impl` tree (the stored `size`
fields are *checked against* this, never trusted). -/
def realSize : Impl α γ → Nat
  | .leaf => 0
  | .inner _ _ _ l r => 1 + realSize l + realSize r

/-- Does every stored `size` field equal its recomputed subtree size? -/
def sizesConsistent : Impl α γ → Bool
  | .leaf => true
  | .inner sz _ _ l r =>
    sz == 1 + realSize l + realSize r && sizesConsistent l && sizesConsistent r

/-- Is every key inside its open ancestor interval w.r.t. `cmp`? -/
def orderedWithin (cmp : α → α → Ordering) : Impl α γ → Option α → Option α → Bool
  | .leaf, _, _ => true
  | .inner _ k _ l r, lo, hi =>
    (lo.all fun a => cmp a k == .lt) && (hi.all fun b => cmp k b == .lt)
      && orderedWithin cmp l lo (some k) && orderedWithin cmp r (some k) hi

/-- Is the tree a BST w.r.t. `cmp`? -/
def ordered (cmp : α → α → Ordering) (t : Impl α γ) : Bool :=
  orderedWithin cmp t none none

/-- The annotated view of one non-leaf subtree (bounds from the ancestors). -/
def viewGo (repK : α → String) (repV : β → String) (cmp : α → α → Ordering) :
    Impl α (fun _ => β) → Option α → Option α → TreeView
  | .leaf, _, _ => .leaf "∅"
  | .inner sz k v l r, lo, hi =>
    let badges : Array String :=
      (if sz != 1 + realSize l + realSize r then #["sz"] else #[])
      ++ (if (lo.all fun a => cmp a k == .lt) && (hi.all fun b => cmp k b == .lt)
          then #[] else #["ord"])
    let kids : Array TreeView :=
      (match l with
        | .leaf => #[]
        | l@(.inner ..) => #[viewGo repK repV cmp l lo (some k)])
      ++ (match r with
        | .leaf => #[]
        | r@(.inner ..) => #[viewGo repK repV cmp r (some k) hi])
    .mk s!"{repK k}:{RB.abbreviate (repV v)}" (some s!"sz={sz}") badges
      (if badges.isEmpty then .neutral else .violation) false kids

/-- The annotated view of a raw `Impl` tree with an explicit comparator.
A **non-empty** tree that passed both checks gets the `ok` tone on its root,
so the generic `Render.healthCaption?` captions it `invariants ok` exactly
like a clean RB tree; the empty map stays the neutral `(empty)` node (nothing
was checked — mirroring the RB convention), and a tree with violations is
left untouched (the guilty nodes carry the violation tone themselves). -/
def implView (repK : α → String) (repV : β → String) (cmp : α → α → Ordering)
    (t : Impl α (fun _ => β)) : TreeView :=
  match t with
  | .leaf => .leaf "(empty)"
  | t@(.inner ..) =>
    let v := viewGo repK repV cmp t none none
    if v.hasTone .violation then v else v.withTone .ok

end STM

/-- `Std.TreeMap` semantic view: stored sizes as sublabels (checked against
recomputed sizes), BST order checked with the comparator from the type. -/
instance {α : Type u} {β : Type v} {cmp : α → α → Ordering} [Repr α] [Repr β] :
    ToTreeView (Std.TreeMap α β cmp) :=
  ⟨fun m => STM.implView reprStr reprStr cmp m.inner.inner⟩

end TreeScope
