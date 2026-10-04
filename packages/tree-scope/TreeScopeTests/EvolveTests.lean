import TreeScopeTests.Helpers

/-! # `#tree_evolve` filmstrip tests

Pure `diffMark` unit tests (new-node detection by `(label, path)`, tone
preservation, counts) and the mirror `removedCount`; the full 4-step RBMap
evolution pinned frame by frame (the rotation at step 3 re-labels the root —
its `new` badge is asserted both in the pin and by a pure diff of the same
two maps); a shrinking RBMap `erase` step pinned as `(+a new, −r gone)`;
frame counts (singular `1 frame` header included); the step cap error; the
per-step `#tree_evolve` wrapping of pipeline errors; and determinism of the
filmstrip renderers.
-/

namespace TreeScopeTests

open TreeScope TreeScope.TreeView

/-! ## `diffMark` (pure) -/

/-- Two-leaf sample. -/
private def dA : TreeView := make "a" #[leaf "b", leaf "c"]
/-- Same shape, one child relabeled. -/
private def dB : TreeView := make "a" #[leaf "b", leaf "x"]
/-- A third child appended. -/
private def dC : TreeView := make "a" #[leaf "b", leaf "c", leaf "d"]

-- Identical frames: nothing new, tree unchanged.
#guard diffMark (some dA) dA == (dA, 0)

-- A relabeled child is new: `added` tone + `new` badge, count 1.
#guard (diffMark (some dA) dB).2 == 1
#guard (diffMark (some dA) dB).1.children[1]!.tone == .added
#guard (diffMark (some dA) dB).1.children[1]!.badges == #["new"]
#guard (diffMark (some dA) dB).1.children[0]!.badges == #[]

-- An appended child is new (no node at its path before).
#guard (diffMark (some dA) dC).2 == 1
#guard (diffMark (some dA) dC).1.children[2]!.badges == #["new"]

-- No previous frame: every node is new.
#guard (diffMark none dA).2 == 3

-- Non-neutral tones are preserved (only the badge is added): a recolored RB
-- node keeps its color.
#guard (diffMark (some dA) (dB.modifyAt #[1] (·.withTone .rbRed))).1.children[1]!.tone == .rbRed
#guard (diffMark (some dA) (dB.modifyAt #[1] (·.withTone .rbRed))).1.children[1]!.badges == #["new"]

-- New-ness is by path: the same label at a *different* path is new.
#guard (diffMark (some (make "a" #[leaf "b"])) (make "a" #[leaf "z", leaf "b"])).2 == 2

/-! ## `removedCount` (the mirror diff) -/

-- Identical frames: nothing removed.
#guard removedCount dA dA == 0
-- A relabeled child both adds and removes one `(label, path)` pair.
#guard removedCount dA dB == 1
-- Pure growth removes nothing; the mirror direction removes the extra child.
#guard removedCount dA dC == 0
#guard removedCount dC dA == 1
-- A dropped subtree counts every vanished node.
#guard removedCount dC (leaf "a") == 3
-- Removal is by path too: `b` still exists but moved from path 0 to path 1.
#guard removedCount (make "a" #[leaf "b"]) (make "a" #[leaf "z", leaf "b"]) == 1

/-! ## `Frame.title` -/

#guard (Frame.mk "init" dA 0 0).title 0 == "step 0: init"
#guard (Frame.mk "(·.insert 3)" dA 2 0).title 3 == "step 3: (·.insert 3) (+2 new)"
-- A step that removed nodes is visibly marked, never shown as pure growth.
#guard (Frame.mk "(·.erase 2)" dA 2 3).title 1 == "step 1: (·.erase 2) (+2 new, −3 gone)"

/-! ## Filmstrip renderers (pure, deterministic) -/

/-- A tiny two-frame strip (the relabel step adds one node and removes one). -/
private def strip : Array Frame :=
  #[⟨"init", dA, 0, 0⟩, ⟨"op", (diffMark (some dA) dB).1, 1, 1⟩]

#guard countOccurrences (htmlToDebugString (renderFilmstrip strip)) "data-frame=" == 2
#guard countOccurrences (htmlToDebugString (renderFilmstrip strip)) "data-removed=" == 2
#guard containsSubstr (htmlToDebugString (renderFilmstrip strip)) "step 0: init"
#guard containsSubstr (htmlToDebugString (renderFilmstrip strip)) "step 1: op (+1 new, −1 gone)"
#guard htmlToDebugString (renderFilmstrip strip) == htmlToDebugString (renderFilmstrip strip)
-- React style contract (see RenderTests): every filmstrip style is a JSON
-- object — the frame wrapper/caption divs carried string styles before
-- `Render.css`, which crashed the `#tree_evolve` panel with React error #62.
#guard reactContractViolations (renderFilmstrip strip) == []
#guard filmstripReport strip
  == "filmstrip: 2 frames\n== step 0: init\ntree: 3 nodes, depth 2\na\n  b\n  c\n== step 1: op (+1 new, −1 gone)\ntree: 3 nodes, depth 2\na\n  b\n  x [new] <added>"

-- A zero-op evolution reports a singular `1 frame`, not `1 frames`.
#guard filmstripReport #[⟨"init", dA, 0, 0⟩]
  == "filmstrip: 1 frame\n== step 0: init\ntree: 3 nodes, depth 2\na\n  b\n  c"

/--
info: filmstrip: 1 frame
== step 0: init
tree: 1 nodes, depth 1
some 3
-/
#guard_msgs in
#tree_evolve (text := true) (some 3) []

/-! ## The 4-step RBMap evolution, pinned frame by frame

Step 3 (`insert 3`) recolors *and rotates*: the root re-labels from `1:"a"`
to `2:"b"`, so all three nodes carry `new` badges in that frame — the
rotation evidence the task asks for — and the two vanished `(label, path)`
pairs are counted as `−2 gone`.  (Step 1's `−1 gone` is the `(empty)`
placeholder node being replaced.) -/

/--
info: filmstrip: 5 frames
== step 0: init
tree: 1 nodes, depth 1
(empty)
== step 1: (·.insert 1 "a") (+1 new, −1 gone)
tree: 1 nodes, depth 1
1:"a" · bh=0 [new] <red>
invariants ok
== step 2: (·.insert 2 "b") (+1 new)
tree: 2 nodes, depth 2
1:"a" · bh=1 <black>
  2:"b" · bh=0 [new] <red>
invariants ok
== step 3: (·.insert 3 "c") (+3 new, −2 gone)
tree: 3 nodes, depth 2
2:"b" · bh=1 [new] <red>
  1:"a" · bh=1 [new] <black>
  3:"c" · bh=1 [new] <black>
invariants ok
== step 4: (·.insert 4 "d") (+1 new)
tree: 4 nodes, depth 3
2:"b" · bh=2 <black>
  1:"a" · bh=1 <black>
  3:"c" · bh=1 <black>
    4:"d" · bh=0 [new] <red>
invariants ok
-/
#guard_msgs in
#tree_evolve (text := true) (Lean.RBMap.empty : Lean.RBMap Nat String compare) [
  (·.insert 1 "a"), (·.insert 2 "b"), (·.insert 3 "c"), (·.insert 4 "d")]

-- The rotation step, reproduced purely: diffing the semantic views of the
-- 2-entry and 3-entry maps marks the *root* new (label `1:"a"` → `2:"b"`).
private def rbm2 : Lean.RBMap Nat String compare :=
  (Lean.RBMap.empty.insert 1 "a").insert 2 "b"
private def rbm3 : Lean.RBMap Nat String compare := rbm2.insert 3 "c"

#guard (diffMark (some (toTreeView rbm2)) (toTreeView rbm3)).2 == 3
#guard (diffMark (some (toTreeView rbm2)) (toTreeView rbm3)).1.label == "2:\"b\""
#guard (diffMark (some (toTreeView rbm2)) (toTreeView rbm3)).1.badges == #["new"]
#guard (diffMark (some (toTreeView rbm2)) (toTreeView rbm3)).1.tone == .rbRed
#guard removedCount (toTreeView rbm2) (toTreeView rbm3) == 2

/-! ## A shrinking step: `erase` reads as removal, not growth

3 entries → 2 entries: the two surviving (shifted) nodes are `new` at their
new paths, and all three old `(label, path)` pairs are counted `gone` — the
caption can never present a deletion as pure insertion. -/

/--
info: filmstrip: 2 frames
== step 0: init
tree: 3 nodes, depth 2
2:"b" · bh=1 <red>
  1:"a" · bh=1 <black>
  3:"c" · bh=1 <black>
invariants ok
== step 1: (·.erase 2) (+2 new, −3 gone)
tree: 2 nodes, depth 2
1:"a" · bh=1 [new] <black>
  3:"c" · bh=0 [new] <red>
invariants ok
-/
#guard_msgs in
#tree_evolve (text := true) ((Lean.RBMap.empty : Lean.RBMap Nat String compare).insert 1 "a"
    |>.insert 2 "b" |>.insert 3 "c") [
  (·.erase 2)]

/-! ## The reflection path evolves too (no instance for `Option Nat`) -/

/--
info: filmstrip: 3 frames
== step 0: init
tree: 1 nodes, depth 1
some 1
== step 1: (·.map (· + 1)) (+1 new, −1 gone)
tree: 1 nodes, depth 1
some 2 [new] <added>
== step 2: (fun _ => none) (+1 new, −1 gone)
tree: 1 nodes, depth 1
none [new] <added>
-/
#guard_msgs in
#tree_evolve (text := true) (some 1) [(·.map (· + 1)), (fun _ => none)]

/-! ## Caps -/

-- 17 steps: refused with the pinned error.
/--
error: #tree_evolve: 17 steps exceed the limit of 16 — TreeScope refuses to draw it
-/
#guard_msgs in
#tree_evolve (text := true) (0 : Nat) [
  (· + 1), (· + 1), (· + 1), (· + 1), (· + 1), (· + 1), (· + 1), (· + 1),
  (· + 1), (· + 1), (· + 1), (· + 1), (· + 1), (· + 1), (· + 1), (· + 1), (· + 1)]

#guard TreeScope.maxSteps == 16

-- The per-frame node cap is the `#tree_scope` one; a frame that grows past
-- 128 nodes aborts the filmstrip with a `#tree_evolve` error naming the
-- offending step and the measured size.
/--
error: #tree_evolve: step 1: the value has 203 nodes, more than the limit of 128 — TreeScope refuses to draw it
-/
#guard_msgs in
#tree_evolve (text := true) (star 100) [(fun t => make "r" #[t, star 100])]

-- An oversized *initial* value names step 0 explicitly as `init`.
/--
error: #tree_evolve: step 0 (init): the value has 201 nodes, more than the limit of 128 — TreeScope refuses to draw it
-/
#guard_msgs in
#tree_evolve (text := true) (star 200) [(fun t => t)]

-- An ill-typed op is rejected during elaboration (`α → α` enforced; a single
-- clean type error, no sorry-recovery cascade).
/--
error: Type mismatch
  x ++ "!"
has type
  String
but is expected to have type
  ℕ
-/
#guard_msgs in
#tree_evolve (text := true) (0 : Nat) [(fun x : String => x ++ "!")]

/-! ## Flags -/

-- `(text := false)` is the panel mode: elaborates cleanly, no messages.
#guard_msgs in
#tree_evolve (text := false) (some 1) [(·.map (· + 1))]

-- `reflect` is a `#tree_scope`-only flag: real error, not a parser error.
/--
error: #tree_evolve: unknown flag 'reflect' — the only supported flag is (text := true|false)
-/
#guard_msgs in
#tree_evolve (reflect := true) (some 1) [(·.map (· + 1))]

end TreeScopeTests
