import TreeScopeTests.Helpers

/-! # `ToTreeView` dispatch tests

The stage-2 contract: instance synthesis beats reflection, `(reflect := true)`
forces reflection, both share the pipeline and the caps.  The `TreeView`
identity instance makes the two paths maximally distinguishable: the semantic
view of `tvSample` is the 3-node tree itself, its reflection is the 26-node
`TreeView.mk` constructor tree — both pinned for the *same value*.
-/

namespace TreeScopeTests

open TreeScope

/-- A hand-built view; its semantic view is itself (identity instance). -/
def tvSample : TreeView := .make "a" #[.leaf "b", .leaf "c"]

-- Instance beats reflection: the semantic path renders the value itself.
/--
info: tree: 3 nodes, depth 2
a
  b
  c
-/
#guard_msgs in
#tree_scope (text := true) tvSample

-- `(reflect := true)` forces reflection: the same value as a constructor tree.
/--
info: tree: 26 nodes, depth 7
mk "a"
  none
  mk
    nil
  neutral
  false
  mk
    cons
      mk "b"
        none
        mk
          nil
        neutral
        false
        mk
          nil
      cons
        mk "c"
          none
          mk
            nil
          neutral
          false
          mk
            nil
        nil
-/
#guard_msgs in
#tree_scope (text := true) (reflect := true) tvSample

-- The identity instance really is the identity (pure).
#guard (toTreeView tvSample) == tvSample

-- Both panel modes elaborate cleanly (no messages; widget attached to stx).
#guard_msgs in
#tree_scope tvSample

#guard_msgs in
#tree_scope (reflect := true) tvSample

-- Types without an instance keep their stage-1 reflection pins, with and
-- without the flag (byte-identical output: same fallback path).
/--
info: tree: 3 nodes, depth 3
cons 1
  cons 2
    nil
-/
#guard_msgs in
#tree_scope (text := true) ([1, 2] : List Nat)

/--
info: tree: 3 nodes, depth 3
cons 1
  cons 2
    nil
-/
#guard_msgs in
#tree_scope (text := true) (reflect := true) ([1, 2] : List Nat)

/-! ## Caps apply to the semantic path too (with the measured size/depth) -/

-- `star 150` is a `TreeView` with 151 nodes: the identity instance produces
-- it, and the shared cap check refuses it — naming the measured count.
/--
error: #tree_scope: the value has 151 nodes, more than the limit of 128 — TreeScope refuses to draw it
-/
#guard_msgs in
#tree_scope (text := true) (star 150)

-- `chain 70` has depth 71: the semantic depth cap fires with the measured depth.
/--
error: #tree_scope: the value nests 71 levels deep, more than the limit of 64 — TreeScope refuses to draw it
-/
#guard_msgs in
#tree_scope (text := true) (chain 70)

/-! ## Errors stay honest under the flag -/

/--
error: #tree_scope: `Nat.add` does not reduce to a constructor application — TreeScope can only reflect concrete inductive values
-/
#guard_msgs in
#tree_scope (text := true) (reflect := true) (Nat.add)

end TreeScopeTests
