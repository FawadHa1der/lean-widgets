import TreeScopeTests.Helpers

/-! # Model tests: `TreeView` measures, paths, updates, ASCII rendering -/

namespace TreeScopeTests

open TreeScope TreeScope.TreeView

/-- `r → [a → [c], b]` — the running example. -/
private def m1 : TreeView := make "r" #[make "a" #[leaf "c"], leaf "b"]

/-! ## Size and depth -/

#guard (leaf "x").size == 1
#guard (leaf "x").depth == 1
#guard m1.size == 4
#guard m1.depth == 3
#guard (chain 4).size == 5
#guard (chain 4).depth == 5
#guard (star 6).size == 7
#guard (star 6).depth == 2
#guard (fullTree 2 2).size == 7
#guard (fullTree 3 2).size == 13

-- Collapsing is display-only: structural measures are unchanged.
#guard (m1.collapseAt #[0]).size == 4
#guard (m1.collapseAt #[0]).depth == 3
#guard m1.hiddenCount == 3
#guard (m1.get? #[0]).map hiddenCount == some 1

/-! ## Paths and access -/

#guard m1.preorderPaths == #[#[], #[0], #[0, 0], #[1]]
#guard (chain 2).preorderPaths == #[#[], #[0], #[0, 0]]
#guard (m1.get? #[]) == some m1
#guard (m1.get? #[0, 0]).map label == some "c"
#guard (m1.get? #[1]).map label == some "b"
#guard m1.get? #[2] == none
#guard m1.get? #[0, 0, 0] == none

/-! ## Updates and mapping -/

#guard ((m1.modifyAt #[0, 0] (·.withLabel "C")).get? #[0, 0]).map label == some "C"
-- Invalid path: tree unchanged.
#guard m1.modifyAt #[5] (·.withLabel "X") == m1
#guard ((m1.collapseAt #[0]).get? #[0]).map collapsed == some true
#guard ((m1.mapLabels (· ++ "!")).get? #[0, 0]).map label == some "c!"
-- mapNodes reaches every node but cannot change the shape.
#guard (m1.mapNodes (·.withTone .ok)).size == 4
#guard (m1.mapNodes (·.withTone .ok)).hasTone .ok
#guard !(m1.hasTone .ok)
#guard m1.hasTone .neutral
#guard (m1.modifyAt #[1] (·.withTone .violation)).hasTone .violation

/-! ## BEq -/

#guard m1 == make "r" #[make "a" #[leaf "c"], leaf "b"]
#guard m1 != make "r" #[make "a" #[leaf "c"], leaf "B"]
#guard leaf "x" != (leaf "x").withCollapsed true
#guard leaf "x" != (leaf "x").addBadge "b"

/-! ## ASCII rendering (pinned byte-exact) -/

#guard (leaf "x").ascii == "x"
#guard m1.ascii == "r\n  a\n    c\n  b"

-- Sublabel, badges, tone and collapsed markers, in their fixed order.
#guard (leaf "n" |>.withSublabel "h=2" |>.addBadge "p" |>.addBadge "q"
    |>.withTone .rbRed).nodeLine == "n · h=2 [p|q] <red>"
#guard (m1.collapseAt #[0]).ascii == "r\n  a (+1 hidden)\n  b"
#guard (make "v" (tone := .violation) (children := #[leaf "w" |>.withTone .added])).ascii
    == "v <violation>\n  w <added>"
#guard ((leaf "s").withCollapsed true).ascii == "s (+0 hidden)"

-- Tone names are the ASCII markers and legend labels.
#guard NodeTone.all.map NodeTone.name
    == #["neutral", "red", "black", "ok", "violation", "highlight", "added"]

end TreeScopeTests
