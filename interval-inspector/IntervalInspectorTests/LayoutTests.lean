import IntervalInspectorTests.Helpers

/-! # Layout tests

Literal proportionality, rank placement respecting the order graph, determinism,
and unordered-atom flagging.
-/

namespace IntervalInspectorTests

open IntervalInspector

/-! ## Literal proportionality -/

private def gLits : OrderGraph :=
  graphOfV [("0", some 0), ("1", some 1), ("4", some 4)] []

#guard (computeLayout gLits).proportional == true
#guard (computeLayout gLits).x? "0" == some 0
#guard (computeLayout gLits).x? "1" == some (1/4 : Rat)
#guard (computeLayout gLits).x? "4" == some 1
#guard (computeLayout gLits).totallyOrdered == true
#guard (computeLayout gLits).atoms.all (·.unordered == false)

-- Negative and fractional literals.
private def gLits2 : OrderGraph :=
  graphOfV [("-2", some (-2)), ("0", some 0), ("1/2", some (1/2 : Rat)), ("3", some 3)] []

#guard (computeLayout gLits2).x? "-2" == some 0
#guard (computeLayout gLits2).x? "0" == some (2/5 : Rat)
#guard (computeLayout gLits2).x? "1/2" == some (1/2 : Rat)
#guard (computeLayout gLits2).x? "3" == some 1

-- All-equal literals collapse to the center.
#guard (computeLayout (graphOfV [("x", some 2), ("y", some 2)] [])).x? "x" == some (1/2 : Rat)

/-! ## Symbolic rank placement -/

private def gChain : OrderGraph := graphOf ["a", "b", "c"] [fLe "a" "b", fLt "b" "c"]

#guard (computeLayout gChain).proportional == false
#guard (computeLayout gChain).x? "a" == some 0
#guard (computeLayout gChain).x? "b" == some (1/2 : Rat)
#guard (computeLayout gChain).x? "c" == some 1
#guard (computeLayout gChain).totallyOrdered == true

-- Known-equal atoms share a position.
private def gEq : OrderGraph := graphOf ["a", "b", "c"] [fEq "a" "b", fLt "b" "c"]
#guard (computeLayout gEq).x? "a" == (computeLayout gEq).x? "b"
#guard (computeLayout gEq).x? "a" == some 0
#guard (computeLayout gEq).x? "c" == some 1

-- Chain-aware: d hangs off b (a < b < c, b ≤ d): ranks a=0, b=1, c=2, d=2.
private def gBranch : OrderGraph :=
  graphOf ["a", "b", "c", "d"] [fLt "a" "b", fLt "b" "c", fLe "b" "d"]
#guard (computeLayout gBranch).x? "a" == some 0
#guard (computeLayout gBranch).x? "b" == some (1/2 : Rat)
#guard (computeLayout gBranch).x? "c" == some 1
#guard (computeLayout gBranch).x? "d" == some 1
-- c and d are mutually unordered and flagged; a and b are ordered w.r.t. everything.
#guard (computeLayout gBranch).isUnordered "c" == true
#guard (computeLayout gBranch).isUnordered "d" == true
#guard (computeLayout gBranch).isUnordered "a" == false
#guard (computeLayout gBranch).isUnordered "b" == false
#guard (computeLayout gBranch).totallyOrdered == false

-- A single symbolic atom sits at the center.
#guard (computeLayout (graphOf ["a"] [])).x? "a" == some (1/2 : Rat)

-- Mixed literal/symbolic uses rank placement, not proportionality.
private def gMixed : OrderGraph :=
  graphOfV [("a", none), ("2", some 2)] [fLe "a" "2"]
#guard (computeLayout gMixed).proportional == false
#guard (computeLayout gMixed).x? "a" == some 0
#guard (computeLayout gMixed).x? "2" == some 1

/-! ## Determinism: computing twice yields structurally equal layouts -/

#guard computeLayout gChain == computeLayout gChain
#guard computeLayout gLits2 == computeLayout gLits2
#guard computeLayout gBranch == computeLayout gBranch

/-! ## Inconsistent graphs: everything flagged, nothing guessed -/

private def gBad : OrderGraph := graphOf ["a", "b"] [fLt "a" "b", fLt "b" "a"]
#guard (computeLayout gBad).inconsistent == true
#guard (computeLayout gBad).totallyOrdered == false
#guard (computeLayout gBad).atoms.all (·.unordered == true)
#guard (computeLayout gBad).x? "a" == some (1/2 : Rat)  -- neutral position, no guess

/-! ## Empty layout -/

#guard (computeLayout (graphOf [] [])).atoms == #[]

end IntervalInspectorTests
