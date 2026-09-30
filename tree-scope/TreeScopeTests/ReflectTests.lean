import TreeScopeTests.Helpers

/-! # Reflection tests

Message-exact `#guard_msgs` pins of `#tree_scope (text := true)` — the
reflection fallback on built-in and user-defined inductives, literal folding
(`Nat`/`Int`/`String`/`Char`/functions), proof-field skipping, and evaluation
(reflection sees *values*, not syntax).
-/

namespace TreeScopeTests

/-! ## Built-in inductives -/

/--
info: tree: 3 nodes, depth 3
cons 1
  cons 2
    nil
-/
#guard_msgs in
#tree_scope (text := true) ([1, 2] : List Nat)

/--
info: tree: 2 nodes, depth 2
some
  some 3
-/
#guard_msgs in
#tree_scope (text := true) (some (some 3))

/--
info: tree: 1 nodes, depth 1
none
-/
#guard_msgs in
#tree_scope (text := true) (none : Option Nat)

/--
info: tree: 1 nodes, depth 1
true
-/
#guard_msgs in
#tree_scope (text := true) true

-- Values are *evaluated* (this is term-structure reflection of the value,
-- not a syntax tree): `2 + 2` is the single node `4`.
/--
info: tree: 1 nodes, depth 1
4
-/
#guard_msgs in
#tree_scope (text := true) (2 + 2)

-- Nested lists: children only where the field type is an inductive.
/--
info: tree: 6 nodes, depth 3
cons
  cons 1
    nil
  cons
    nil
    nil
-/
#guard_msgs in
#tree_scope (text := true) [[1], []]

/-! ## Literal folding -/

-- Char literals fold as `'a'`.
/--
info: tree: 1 nodes, depth 1
mk 'a' 'z'
-/
#guard_msgs in
#tree_scope (text := true) ('a', 'z')

-- String literals fold quoted.
/--
info: tree: 1 nodes, depth 1
mk "hi" 2
-/
#guard_msgs in
#tree_scope (text := true) ("hi", 2)

-- Int literals fold signed (constructor form is `Int.negSucc 2`, folded as `-3`).
/--
info: tree: 1 nodes, depth 1
mk -3 2
-/
#guard_msgs in
#tree_scope (text := true) ((-3 : Int), (2 : Int))

-- When a folded literal comes *after* a child field, the label switches to
-- positional `_` placeholders so the field order is never misrepresented.
/--
info: tree: 3 nodes, depth 3
mk _ 3
  mk 1
    some 2
-/
#guard_msgs in
#tree_scope (text := true) ((1, some 2), 3)

/-! ## Proof fields are skipped -/

-- `Fin.mk` has an explicit `isLt` proof field: only `val` remains, folded.
/--
info: tree: 1 nodes, depth 1
mk 3
-/
#guard_msgs in
#tree_scope (text := true) (3 : Fin 5)

-- Same for `Subtype.mk`.
/--
info: tree: 1 nodes, depth 1
mk 2
-/
#guard_msgs in
#tree_scope (text := true) (⟨2, by simp⟩ : {n : Nat // n < 5})

/-! ## User-defined inductives -/

/-- Test AST (no `Repr`, no `DecidableEq` — reflection needs neither). -/
inductive Arith where
  /-- Literal. -/
  | num (n : Nat)
  /-- Addition. -/
  | add (a b : Arith)
  /-- Multiplication. -/
  | mul (a b : Arith)

-- Definitions unfold: reflecting a `def` shows its value.
/-- `1 + 2 * 3`. -/
def arithSample : Arith := .add (.num 1) (.mul (.num 2) (.num 3))

/--
info: tree: 5 nodes, depth 3
add
  num 1
  mul
    num 2
    num 3
-/
#guard_msgs in
#tree_scope (text := true) arithSample

/-- An inductive with a non-inductive (function) field. -/
inductive FunBox where
  /-- Holds a function and a number. -/
  | box (f : Nat → Nat) (n : Nat)

-- A non-inductive field folds into the label as its pretty-printed form in ⟨…⟩.
/--
info: tree: 1 nodes, depth 1
box ⟨fun x => x + 1⟩ 7
-/
#guard_msgs in
#tree_scope (text := true) (FunBox.box (fun x => x + 1) 7)

/-- A wide inductive for the node cap: `bushN (d+1)` has `3 · size (bushN d) + 1`
nodes. -/
inductive Bush where
  /-- Leaf. -/
  | tip
  /-- Ternary fork. -/
  | fork (a b c : Bush)

/-- Full ternary bush of depth `n`. -/
def bushN : Nat → Bush
  | 0 => .tip
  | n + 1 => .fork (bushN n) (bushN n) (bushN n)

-- `bushN 4` has 121 nodes: still under both caps.
/--
info: tree: 1 nodes, depth 1
tip
-/
#guard_msgs in
#tree_scope (text := true) (bushN 0)

/-! ## Float fields (folded via compiled evaluation, printed with `toString`) -/

/-- The most ordinary numeric data: a plain `Float` structure. -/
structure FPoint where
  /-- x-coordinate. -/
  x : Float
  /-- y-coordinate. -/
  y : Float

-- `Float` never whnf-reduces to a constructor application (it is a structure
-- over an opaque spec); the fields fold into the label anyway.
/--
info: tree: 1 nodes, depth 1
mk 1.500000 2.500000
-/
#guard_msgs in
#tree_scope (text := true) (FPoint.mk 1.5 2.5)

-- A `Float` inside a container folds like any other literal.
/--
info: tree: 2 nodes, depth 2
cons 1.000000
  nil
-/
#guard_msgs in
#tree_scope (text := true) [(1.0 : Float)]

-- A bare `Float` value renders as a single folded node.
/--
info: tree: 1 nodes, depth 1
3.140000
-/
#guard_msgs in
#tree_scope (text := true) (3.14 : Float)

-- `Float32` and negative floats fold the same way.
/--
info: tree: 1 nodes, depth 1
mk 1.500000 -2.500000
-/
#guard_msgs in
#tree_scope (text := true) ((1.5 : Float32), (-2.5 : Float))

/-! ## Long chains: compaction at the depth cap

A pure single-child constructor spine that fits the depth cap keeps its
ordinary one-node-per-level rendering; past the cap the *top-level* value is
rendered as the compact depth-2 `chain · n=len` sequence instead of being
refused. -/

-- 64 levels exactly (63 cons + nil): still the ordinary spine rendering.
/--
info: tree: 64 nodes, depth 64
cons 0
  cons 1
    cons 2
      cons 3
        cons 4
          cons 5
            cons 6
              cons 7
                cons 8
                  cons 9
                    cons 10
                      cons 11
                        cons 12
                          cons 13
                            cons 14
                              cons 15
                                cons 16
                                  cons 17
                                    cons 18
                                      cons 19
                                        cons 20
                                          cons 21
                                            cons 22
                                              cons 23
                                                cons 24
                                                  cons 25
                                                    cons 26
                                                      cons 27
                                                        cons 28
                                                          cons 29
                                                            cons 30
                                                              cons 31
                                                                cons 32
                                                                  cons 33
                                                                    cons 34
                                                                      cons 35
                                                                        cons 36
                                                                          cons 37
                                                                            cons 38
                                                                              cons 39
                                                                                cons 40
                                                                                  cons 41
                                                                                    cons 42
                                                                                      cons 43
                                                                                        cons 44
                                                                                          cons 45
                                                                                            cons 46
                                                                                              cons 47
                                                                                                cons 48
                                                                                                  cons 49
                                                                                                    cons 50
                                                                                                      cons 51
                                                                                                        cons 52
                                                                                                          cons 53
                                                                                                            cons 54
                                                                                                              cons 55
                                                                                                                cons 56
                                                                                                                  cons 57
                                                                                                                    cons 58
                                                                                                                      cons 59
                                                                                                                        cons 60
                                                                                                                          cons 61
                                                                                                                            cons 62
                                                                                                                              nil
-/
#guard_msgs in
#tree_scope (text := true) (List.range 63)

-- 70 elements = a 71-level spine: compacted to depth 2.
/--
info: tree: 72 nodes, depth 2
chain · n=71
  cons 0
  cons 1
  cons 2
  cons 3
  cons 4
  cons 5
  cons 6
  cons 7
  cons 8
  cons 9
  cons 10
  cons 11
  cons 12
  cons 13
  cons 14
  cons 15
  cons 16
  cons 17
  cons 18
  cons 19
  cons 20
  cons 21
  cons 22
  cons 23
  cons 24
  cons 25
  cons 26
  cons 27
  cons 28
  cons 29
  cons 30
  cons 31
  cons 32
  cons 33
  cons 34
  cons 35
  cons 36
  cons 37
  cons 38
  cons 39
  cons 40
  cons 41
  cons 42
  cons 43
  cons 44
  cons 45
  cons 46
  cons 47
  cons 48
  cons 49
  cons 50
  cons 51
  cons 52
  cons 53
  cons 54
  cons 55
  cons 56
  cons 57
  cons 58
  cons 59
  cons 60
  cons 61
  cons 62
  cons 63
  cons 64
  cons 65
  cons 66
  cons 67
  cons 68
  cons 69
  nil
-/
#guard_msgs in
#tree_scope (text := true) (List.range 70)

-- `Array` reflects as `mk` over its backing list: same chain, one level more.
/--
info: tree: 73 nodes, depth 2
chain · n=72
  mk
  cons 0
  cons 1
  cons 2
  cons 3
  cons 4
  cons 5
  cons 6
  cons 7
  cons 8
  cons 9
  cons 10
  cons 11
  cons 12
  cons 13
  cons 14
  cons 15
  cons 16
  cons 17
  cons 18
  cons 19
  cons 20
  cons 21
  cons 22
  cons 23
  cons 24
  cons 25
  cons 26
  cons 27
  cons 28
  cons 29
  cons 30
  cons 31
  cons 32
  cons 33
  cons 34
  cons 35
  cons 36
  cons 37
  cons 38
  cons 39
  cons 40
  cons 41
  cons 42
  cons 43
  cons 44
  cons 45
  cons 46
  cons 47
  cons 48
  cons 49
  cons 50
  cons 51
  cons 52
  cons 53
  cons 54
  cons 55
  cons 56
  cons 57
  cons 58
  cons 59
  cons 60
  cons 61
  cons 62
  cons 63
  cons 64
  cons 65
  cons 66
  cons 67
  cons 68
  cons 69
  nil
-/
#guard_msgs in
#tree_scope (text := true) (Array.range 70)

/-! ## Caps (honest pinned errors, with measured quantities) -/

-- A 150-element chain is compacted, but even its compact form has 152 nodes:
-- refused with the exact count.
/--
error: #tree_scope: the value has 152 nodes, more than the limit of 128 — TreeScope refuses to draw it
-/
#guard_msgs in
#tree_scope (text := true) (List.range 150)

-- Past the probe fuel (1024 spine steps) only a lower bound is known.
/--
error: #tree_scope: the value nests at least 1088 levels deep, more than the limit of 64 — chains count one level per element; render a shorter prefix — TreeScope refuses to draw it
-/
#guard_msgs in
#tree_scope (text := true) (List.replicate 2000 0)

/-- A chain that *branches* at the very bottom: not compactable. -/
inductive DeepD where
  /-- Terminal. -/
  | leafy
  /-- Chain link. -/
  | link (next : DeepD)
  /-- Branch point. -/
  | fork (a b : DeepD)

/-- `n` links ending in a fork. -/
def dchain : Nat → DeepD
  | 0 => .fork (.link .leafy) .leafy
  | n + 1 => .link (dchain n)

-- Branchy over-deep chains are still refused — with the measured depth along
-- the probed path as an honest lower bound.
/--
error: #tree_scope: the value nests at least 71 levels deep, more than the limit of 64 — chains count one level per element; render a shorter prefix — TreeScope refuses to draw it
-/
#guard_msgs in
#tree_scope (text := true) (dchain 70)

-- `bushN 5` has 364 nodes at depth 6: the node cap fires (the traversal
-- aborts at the cap, so only the bound itself is reported).
/--
error: #tree_scope: the value has more than 128 nodes — TreeScope refuses to draw it
-/
#guard_msgs in
#tree_scope (text := true) (bushN 5)

end TreeScopeTests
