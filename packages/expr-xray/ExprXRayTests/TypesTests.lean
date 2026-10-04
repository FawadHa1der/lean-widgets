import ExprXRay
import ExprXRayTests.TestUtil

/-! # Tests for `ExprXRay.Types` (pure `#guard` tests) -/

namespace ExprXRayTests.TypesTests

open ExprXRay

-- truncatePP: short strings pass through unchanged
#guard truncatePP "abc" 10 == "abc"
-- truncatePP: exactly at the limit is NOT truncated
#guard truncatePP "abcde" 5 == "abcde"
-- truncatePP: one over the limit is truncated with an ellipsis
#guard truncatePP "abcdef" 5 == "abcde…"
-- truncatePP: newlines are collapsed to spaces before truncation
#guard truncatePP "ab\ncd" 10 == "ab cd"
-- truncatePP: newline collapse counts toward the limit
#guard truncatePP "ab\ncdef" 5 == "ab cd…"
-- truncatePP: default limit is 60
#guard truncatePP (String.ofList (List.replicate 60 'x')) == String.ofList (List.replicate 60 'x')
#guard truncatePP (String.ofList (List.replicate 61 'x'))
    == String.ofList (List.replicate 60 'x') ++ "…"

-- firstDiffIdx: length of the longest common prefix
#guard firstDiffIdx "abc" "abd" == 2
#guard firstDiffIdx "abc" "abc" == 3
#guard firstDiffIdx "abc" "abcdef" == 3
#guard firstDiffIdx "xbc" "abc" == 0
#guard firstDiffIdx "" "abc" == 0

-- truncatePPPair: both under the limit pass through unchanged
#guard truncatePPPair "ab" "cd" 10 == ("ab", "cd")
-- left-anchored truncation is kept when it distinguishes the sides
#guard
  let a := "A" ++ "".pushn 'y' 70
  let b := "B" ++ "".pushn 'y' 70
  truncatePPPair a b 10 == ("Ayyyyyyyyy…", "Byyyyyyyyy…")
-- REGRESSION (bughunt2): a long common prefix used to truncate both
-- sides to the same string ("X vs X"); now the window is anchored at
-- the first differing character so the difference is always visible
#guard
  let a := "".pushn 'x' 70 ++ "A"
  let b := "".pushn 'x' 70 ++ "B"
  let (ta, tb) := truncatePPPair a b 20
  ta != tb && ta == "…xxxxxA" && tb == "…xxxxxB"
-- identical inputs (two exprs whose pretty strings coincide) still
-- truncate left-anchored
#guard
  let s := "".pushn 'z' 70
  truncatePPPair s s 10 == ("zzzzzzzzzz…", "zzzzzzzzzz…")
-- newlines are collapsed before windowing, as in truncatePP
#guard truncatePPPair "a\nb" "a\nc" 10 == ("a b", "a c")

-- XKind names
#guard XKind.const.name == "const"
#guard XKind.forallE.name == "forallE"
#guard XKind.mdata.name == "mdata"

-- BinderRole tags: explicit/none are untagged, hidden roles are tagged
#guard BinderRole.explicit.tag == ""
#guard BinderRole.none.tag == ""
#guard BinderRole.implicit.tag == "{imp}"
#guard BinderRole.instImplicit.tag == "[inst]"

-- BinderRole.isHidden
#guard BinderRole.instImplicit.isHidden
#guard BinderRole.implicit.isHidden
#guard BinderRole.strictImplicit.isHidden
#guard !BinderRole.explicit.isHidden
#guard !BinderRole.none.isHidden

-- roleOfBinderInfo covers all four constructors
#guard roleOfBinderInfo .default == .explicit
#guard roleOfBinderInfo .implicit == .implicit
#guard roleOfBinderInfo .strictImplicit == .strictImplicit
#guard roleOfBinderInfo .instImplicit == .instImplicit

/-- A small hand-built tree: root with two children, second child has one child. -/
private def sampleTree : XNode :=
  { kind := .app, pp := "root",
    children := #[
      { kind := .const, pp := "c0", role := .implicit },
      { kind := .app, pp := "c1", role := .explicit,
        children := #[{ kind := .lit, pp := "c10", role := .instImplicit }] }
    ] }

-- XNode.get? navigation
#guard (sampleTree.get? []).map (·.pp) == some "root"
#guard (sampleTree.get? [0]).map (·.pp) == some "c0"
#guard (sampleTree.get? [1, 0]).map (·.pp) == some "c10"
-- XNode.get? out-of-bounds and too-deep paths return none
#guard (sampleTree.get? [2]).isNone
#guard (sampleTree.get? [0, 0]).isNone

-- XNode.size counts every node exactly once
#guard sampleTree.size == 4
-- XNode.depth: longest chain below the root
#guard sampleTree.depth == 2
#guard ({ kind := .lit, pp := "leaf" } : XNode).depth == 0

-- XNode.any / XNode.count
#guard sampleTree.any (·.role == .instImplicit)
#guard !(sampleTree.any (·.kind == .mvar))
#guard sampleTree.count (·.kind == .app) == 2
#guard sampleTree.count (fun _ => true) == 4

end ExprXRayTests.TypesTests
