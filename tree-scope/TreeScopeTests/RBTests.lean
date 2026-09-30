import TreeScopeTests.Helpers

/-! # Red–black instance tests

Instance rendering pinned in text mode; the three invariant checkers
(`hasRedRed`, `bhConsistent`, `ordered`) exercised on crafted violating *and*
valid raw trees (no false positives); black-height values pinned; `rbHealth`
summaries pinned; and the library-health property — `RBMap.ofList` output is
always violation-free — checked over six differently-shaped inputs.
-/

namespace TreeScopeTests

open TreeScope TreeScope.RB
open Lean (RBNode RBColor RBMap)

/-! ## Crafted raw trees -/

/-- Valid: black root, two red leaves (the "valid red-leaf tree"). -/
def rbRedLeaves : RBNode Nat (fun _ => Nat) :=
  .node .black (.node .red .leaf 1 10 .leaf) 2 20 (.node .red .leaf 3 30 .leaf)

/-- Valid for *red-red* (no red node at all) but bh-inconsistent:
an all-black chain. -/
def rbBlackChain : RBNode Nat (fun _ => Nat) :=
  .node .black (.node .black (.node .black .leaf 1 10 .leaf) 2 20 .leaf) 3 30 .leaf

/-- Valid: a single black node. -/
def rbSingle : RBNode Nat (fun _ => Nat) :=
  .node .black .leaf 5 50 .leaf

/-- Valid: a perfectly balanced black tree of height 2. -/
def rbBlackBalanced : RBNode Nat (fun _ => Nat) :=
  .node .black (.node .black .leaf 1 10 .leaf) 2 20 (.node .black .leaf 3 30 .leaf)

/-- Red-red violation 1: red root with a red left child. -/
def rbRR1 : RBNode Nat (fun _ => Nat) :=
  .node .red (.node .red .leaf 1 10 .leaf) 2 20 .leaf

/-- Red-red violation 2: buried under a black root, on the left spine. -/
def rbRR2 : RBNode Nat (fun _ => Nat) :=
  .node .black (.node .red (.node .red .leaf 1 10 .leaf) 2 20 .leaf) 3 30 .leaf

/-- Red-red violation 3: on the right spine. -/
def rbRR3 : RBNode Nat (fun _ => Nat) :=
  .node .black .leaf 1 10 (.node .red .leaf 2 20 (.node .red .leaf 3 30 .leaf))

/-- Order violation (w.r.t. `compare`): 7 in the left subtree of 5. -/
def rbOrdBroken : RBNode Nat (fun _ => Nat) :=
  .node .black (.node .black .leaf 7 70 .leaf) 5 50 (.node .black .leaf 9 90 .leaf)

/-! ## `hasRedRed`: three violations caught, four valid trees clean -/

#guard hasRedRed rbRR1 == true
#guard hasRedRed rbRR2 == true
#guard hasRedRed rbRR3 == true
#guard hasRedRed rbRedLeaves == false
#guard hasRedRed rbBlackChain == false      -- all-black chain: no false positive
#guard hasRedRed rbSingle == false
#guard hasRedRed rbBlackBalanced == false

/-! ## `blackHeight` and `bhConsistent` -/

#guard blackHeight (RBNode.leaf : RBNode Nat (fun _ => Nat)) == 0
#guard blackHeight rbSingle == 1
#guard blackHeight rbRedLeaves == 1         -- red nodes do not count
#guard blackHeight rbBlackBalanced == 2
#guard blackHeight rbBlackChain == 3        -- max over the (lopsided) subtrees
#guard blackHeight rbRR1 == 0               -- all-red tree

#guard bhConsistent rbRedLeaves == true
#guard bhConsistent rbBlackBalanced == true
#guard bhConsistent rbSingle == true
#guard bhConsistent rbBlackChain == false   -- 2 vs 0 at the root, 1 vs 0 below
#guard bhConsistent rbOrdBroken == true     -- order broken, bh fine

/-! ## `ordered` (BST property w.r.t. an explicit comparator) -/

#guard ordered compare rbRedLeaves == true
#guard ordered compare rbBlackBalanced == true
#guard ordered compare rbOrdBroken == false
#guard ordered compare rbBlackChain == true
-- The *same tree* under a reversed comparator: order flips.
#guard ordered (fun a b => compare b a) rbOrdBroken == false
#guard ordered (fun a b => compare b a) rbRedLeaves == false

/-! ## Pinned instance rendering (text mode) -/

/--
info: tree: 3 nodes, depth 2
2:"b" · bh=1 <red>
  1:"a" · bh=1 <black>
  3:"c" · bh=1 <black>
invariants ok
-/
#guard_msgs in
#tree_scope (text := true) (Lean.RBMap.ofList [(2, "b"), (1, "a"), (3, "c")] : Lean.RBMap Nat String compare)

-- The 8-entry demo map: colors, per-node bh sublabels, health caption.
/--
info: tree: 8 nodes, depth 4
4:"d" · bh=2 <black>
  2:"b" · bh=1 <red>
    1:"a" · bh=1 <black>
    3:"c" · bh=1 <black>
  7:"g" · bh=1 <red>
    6:"f" · bh=1 <black>
      5:"e" · bh=0 <red>
    8:"h" · bh=1 <black>
invariants ok
-/
#guard_msgs in
#tree_scope (text := true) TreeScope.Demo.rbSample

-- Reflect-vs-semantic contrast: the same small map under forced reflection
-- is the raw constructor tree (colors as child nodes, `Subtype.mk` root).
/--
info: tree: 11 nodes, depth 4
mk
  node _ _ 2 "b" _
    red
    node _ _ 1 "a" _
      black
      leaf
      leaf
    node _ _ 3 "c" _
      black
      leaf
      leaf
-/
#guard_msgs in
#tree_scope (text := true) (reflect := true) (Lean.RBMap.ofList [(2, "b"), (1, "a"), (3, "c")] : Lean.RBMap Nat String compare)

-- The hand-crafted invalid tree (demo money-shot): red-red AND bh mismatch,
-- flagged on the guilty nodes, both listed in the caption.
/--
info: tree: 5 nodes, depth 3
5:"e" · bh=3 [bh] <violation>
  2:"b" · bh=0 <red>
    1:"a" · bh=0 [red-red] <violation>
  8:"h" · bh=2 [bh] <violation>
    9:"i" · bh=1 <black>
⚠ r (bh), r.0.0 (red-red), r.1 (bh)
-/
#guard_msgs in
#tree_scope (text := true) TreeScope.Demo.brokenRB

-- An order violation via `rbNodeView` with an explicit comparator (a raw
-- node's type has no comparator, so this is the designated route).
#guard Render.textReport (rbNodeView (fun n => toString n) (fun v => toString v)
    (some compare) rbOrdBroken)
  == "tree: 3 nodes, depth 2\n5:50 · bh=2 <black>\n  7:70 · bh=1 [ord] <violation>\n  9:90 · bh=1 <black>\n⚠ r.0 (ord)"

/-! ## `rbHealth` summaries pinned -/

#guard rbHealth (fun n => toString n) (fun v => toString v) (some compare)
    TreeScope.Demo.brokenRB
  == "⚠ r (bh), r.0.0 (red-red), r.1 (bh)"

#guard rbHealth (fun n => toString n) (fun v => toString v) (some compare)
    rbRedLeaves == "invariants ok"

#guard rbHealth (fun n => toString n) (fun v => toString v) (some compare)
    (RBNode.leaf : RBNode Nat (fun _ => Nat)) == "invariants ok"

#guard rbHealth (fun n => toString n) (fun v => toString v) (some compare)
    rbOrdBroken == "⚠ r.0 (ord)"

#guard rbHealth (fun n => toString n) (fun v => toString v) none
    rbOrdBroken == "invariants ok"   -- no comparator ⇒ no order check

/-! ## Value abbreviation -/

#guard abbreviate "short" == "short"
#guard abbreviate "exactly12ch." == "exactly12ch."
#guard abbreviate "high-quality widget" == "high-qualit…"
#guard (abbreviate "high-quality widget").length == 12

-- A quote-delimited value (`Repr`-printed string) is re-closed before the
-- ellipsis: abbreviation never leaves an unbalanced quote.
#guard abbreviate "\"abcdefghijklmnop\"" == "\"abcdefghi\"…"
#guard (abbreviate "\"abcdefghijklmnop\"").length == 12
#guard abbreviate "\"hi\"" == "\"hi\""

-- The instance route shows the re-closed quote in the label.
/--
info: tree: 1 nodes, depth 1
1:"abcdefghi"… · bh=0 <red>
invariants ok
-/
#guard_msgs in
#tree_scope (text := true) ((Lean.RBMap.empty : Lean.RBMap Nat String compare).insert 1 "abcdefghijklmnop")

/-! ## Property: library-produced maps are always healthy

Six differently-shaped `ofList` inputs (sorted, reversed, shuffled,
singleton, duplicate keys, string keys): zero violations in the semantic
view, and all three raw checkers pass. -/

/-- Sorted 0..19. -/
def mSorted : RBMap Nat Nat compare := Lean.RBMap.ofList ((List.range 20).map fun i => (i, i))
/-- Reversed 19..0. -/
def mRev : RBMap Nat Nat compare := Lean.RBMap.ofList ((List.range 20).reverse.map fun i => (i, i))
/-- Shuffled (multiples of 7 mod 20 — a full cycle). -/
def mShuf : RBMap Nat Nat compare := Lean.RBMap.ofList ((List.range 20).map fun i => ((i * 7) % 20, i))
/-- Singleton. -/
def mOne : RBMap Nat Nat compare := Lean.RBMap.ofList [(5, 50)]
/-- Duplicate keys (later wins; still healthy). -/
def mDup : RBMap Nat Nat compare := Lean.RBMap.ofList [(1, 1), (2, 2), (1, 3), (3, 4), (2, 5)]
/-- String keys under the string comparator. -/
def mStr : RBMap String Nat compare := Lean.RBMap.ofList [("b", 1), ("a", 2), ("d", 3), ("c", 4)]

#guard violationCount (toTreeView mSorted) == 0
#guard violationCount (toTreeView mRev) == 0
#guard violationCount (toTreeView mShuf) == 0
#guard violationCount (toTreeView mOne) == 0
#guard violationCount (toTreeView mDup) == 0
#guard violationCount (toTreeView mStr) == 0

#guard hasRedRed mSorted.val == false
#guard hasRedRed mRev.val == false
#guard hasRedRed mShuf.val == false
#guard bhConsistent mSorted.val == true
#guard bhConsistent mRev.val == true
#guard bhConsistent mShuf.val == true
#guard ordered compare mSorted.val == true
#guard ordered compare mRev.val == true
#guard ordered compare mShuf.val == true
#guard ordered compare mDup.val == true
#guard ordered compare mStr.val == true

-- Sanity: those maps really contain what we think.
#guard mSorted.size == 20 && mRev.size == 20 && mShuf.size == 20
#guard mDup.size == 3 && mOne.size == 1 && mStr.size == 4

-- The semantic view of a healthy map carries rb tones (colors really shown).
#guard (toTreeView mSorted).hasTone .rbBlack
#guard (toTreeView TreeScope.Demo.rbSample).hasTone .rbRed

-- Determinism: the semantic view is a pure function of the value.
#guard toTreeView mShuf == toTreeView mShuf

/-! ## Type-carried `cmp` wiring pin

A map over a *reversed* comparator rendered through the real `ToTreeView`
instance must be violation-free: the instance forwards the `cmp` carried by
the map's type, and a hardcoded `compare` would flag the descending key
order as `ord` violations. -/

def cmpRev : Nat → Nat → Ordering := fun a b => compare b a

def mRevCmp : RBMap Nat Nat cmpRev :=
  Lean.RBMap.ofList ((List.range 20).map fun i => (i, i))

#guard RB.violationCount (toTreeView mRevCmp) == 0

end TreeScopeTests
