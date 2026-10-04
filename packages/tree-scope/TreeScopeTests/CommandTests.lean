import TreeScopeTests.Helpers

/-! # `#tree_scope` command tests

Both command modes (panel and `(text := true)`), and every user-facing error
message, pinned by `#guard_msgs`.
-/

namespace TreeScopeTests

-- Panel mode elaborates cleanly (no messages; the widget is attached to stx).
#guard_msgs in
#tree_scope [1, 2]

#guard_msgs in
#tree_scope (some (2 + 2))

-- Text mode on a demo-package value (the Demo AST ships with the library).
/--
info: tree: 9 nodes, depth 4
mul
  add
    num 1
    mul
      num 2
      num 3
  add
    num 4
    num 5
-/
#guard_msgs in
#tree_scope (text := true) TreeScope.Demo.sample

/-! ## Errors -/

-- A bare function does not reduce to a constructor application.
/--
error: #tree_scope: `Nat.add` does not reduce to a constructor application — TreeScope can only reflect concrete inductive values
-/
#guard_msgs in
#tree_scope (text := true) (Nat.add)

-- A lambda is not a concrete inductive value either.
/--
error: #tree_scope: `fun x => x` does not reduce to a constructor application — TreeScope can only reflect concrete inductive values
-/
#guard_msgs in
#tree_scope (text := true) (fun x : Nat => x)

-- Panel mode reports the same errors as text mode (shared pipeline).
/--
error: #tree_scope: `Nat.add` does not reduce to a constructor application — TreeScope can only reflect concrete inductive values
-/
#guard_msgs in
#tree_scope (Nat.add)

-- Panel mode compacts over-deep chains like text mode does (shared pipeline):
-- a 100-element list renders (102 nodes at depth 2), no error.
#guard_msgs in
#tree_scope (List.range 100)

/-! ## Flags (generic grammar: any order, explicit true/false, real errors) -/

-- Reversed flag order parses and behaves identically.
/--
info: tree: 3 nodes, depth 3
cons 1
  cons 2
    nil
-/
#guard_msgs in
#tree_scope (reflect := true) (text := true) ([1, 2] : List Nat)

-- `(text := false)` is the explicit panel mode: elaborates cleanly.
#guard_msgs in
#tree_scope (text := false) [1, 2]

-- `(reflect := false)` is the explicit default dispatch.
/--
info: tree: 3 nodes, depth 3
cons 1
  cons 2
    nil
-/
#guard_msgs in
#tree_scope (text := true) (reflect := false) ([1, 2] : List Nat)

-- Unknown flags get a targeted error, not a parser error.
/--
error: #tree_scope: unknown flag 'foo' — supported flags are (text := true|false) and (reflect := true|false)
-/
#guard_msgs in
#tree_scope (foo := true) [1, 2]

-- Duplicated flags are rejected.
/--
error: #tree_scope: duplicate flag 'text'
-/
#guard_msgs in
#tree_scope (text := true) (text := true) [1, 2]

end TreeScopeTests
