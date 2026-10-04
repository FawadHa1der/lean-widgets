import IntervalInspectorTests.Helpers

/-! # Order graph tests

Direct hypotheses, transitivity chains (with strictness propagation), literal
comparisons, equality merging, unknown pairs, and contradiction safety.
-/

namespace IntervalInspectorTests

open IntervalInspector

/-! ## Direct facts -/

#guard (graphOf ["a", "b"] [fLe "a" "b"]).knownLe "a" "b" == true
#guard (graphOf ["a", "b"] [fLe "a" "b"]).knownLt "a" "b" == false
#guard (graphOf ["a", "b"] [fLe "a" "b"]).knownLe "b" "a" == false
#guard (graphOf ["a", "b"] [fLt "a" "b"]).knownLt "a" "b" == true
#guard (graphOf ["a", "b"] [fLt "a" "b"]).knownLe "a" "b" == true  -- < implies ≤
#guard (graphOf ["a", "b"] [fEq "a" "b"]).knownEq "a" "b" == true
#guard (graphOf ["a", "b"] [fEq "a" "b"]).knownLt "a" "b" == false
-- Reflexivity, even with no facts.
#guard (graphOf ["a"] []).knownLe "a" "a" == true
#guard (graphOf ["a"] []).knownEq "a" "a" == true
-- Facts about atoms not in the graph are ignored; queries on missing atoms are false.
#guard (graphOf ["a", "b"] [fLe "a" "z"]).knownLe "a" "z" == false
#guard (graphOf ["a", "b"] [fLe "a" "z"]).knownLe "a" "b" == false

/-! ## Transitivity -/

#guard (graphOf ["a", "b", "c"] [fLe "a" "b", fLe "b" "c"]).knownLe "a" "c" == true
#guard (graphOf ["a", "b", "c"] [fLe "a" "b", fLe "b" "c"]).knownLt "a" "c" == false
-- a ≤ b, b < c ⇒ a < c (strictness through the chain).
#guard (graphOf ["a", "b", "c"] [fLe "a" "b", fLt "b" "c"]).knownLt "a" "c" == true
#guard (graphOf ["a", "b", "c"] [fLt "a" "b", fLe "b" "c"]).knownLt "a" "c" == true
-- Four-element chain.
#guard (graphOf ["a", "b", "c", "d"] [fLe "a" "b", fLt "b" "c", fLe "c" "d"]).knownLt "a" "d"
    == true
-- Direction matters: nothing flows backwards.
#guard (graphOf ["a", "b", "c"] [fLe "a" "b", fLe "b" "c"]).knownLe "c" "a" == false

/-! ## Equality merging -/

#guard (graphOf ["a", "b", "c"] [fEq "a" "b", fLe "b" "c"]).knownLe "a" "c" == true
#guard (graphOf ["a", "b", "c"] [fEq "a" "b", fLt "b" "c"]).knownLt "a" "c" == true
#guard (graphOf ["a", "b", "c"] [fEq "a" "b", fEq "b" "c"]).knownEq "a" "c" == true
-- Equality from two inclusions.
#guard (graphOf ["a", "b"] [fLe "a" "b", fLe "b" "a"]).knownEq "a" "b" == true

/-! ## Literal comparisons (automatic) -/

#guard (graphOfV [("2", some 2), ("7", some 7)] []).knownLt "2" "7" == true
#guard (graphOfV [("2", some 2), ("7", some 7)] []).knownLe "7" "2" == false
#guard (graphOfV [("-3", some (-3)), ("2", some 2)] []).knownLt "-3" "2" == true
#guard (graphOfV [("1/2", some (1/2 : Rat)), ("3/4", some (3/4 : Rat))] []).knownLt "1/2" "3/4"
    == true
-- Same value, different atoms: known equal.
#guard (graphOfV [("x", some 2), ("y", some 2)] []).knownEq "x" "y" == true
-- Literal + symbolic bridge: a ≤ 2 < 7 ⇒ a < 7.
#guard (graphOfV [("a", none), ("2", some 2), ("7", some 7)] [fLe "a" "2"]).knownLt "a" "7"
    == true

/-! ## Unknown pairs stay unknown -/

#guard (graphOf ["a", "b"] []).unknown "a" "b" == true
#guard (graphOf ["a", "b"] []).knownLe "a" "b" == false
#guard (graphOf ["a", "b", "c"] [fLe "a" "b"]).unknown "a" "c" == true
#guard (graphOf ["a", "b", "c"] [fLe "a" "b"]).unknown "a" "b" == false
#guard (graphOf ["a", "b", "c"] [fLe "a" "b"]).unknownPairs == #[("a", "c"), ("b", "c")]
#guard (graphOf ["a", "b"] [fLe "a" "b"]).totallyOrdered == true
#guard (graphOf ["a", "b", "c"] [fLe "a" "b"]).totallyOrdered == false

/-! ## Contradiction safety: flagged, queries answer unknown, no panic -/

#guard (graphOf ["a", "b"] [fLt "a" "b", fLt "b" "a"]).inconsistent == true
#guard (graphOf ["a", "b"] [fLt "a" "b", fLt "b" "a"]).knownLt "a" "b" == false
#guard (graphOf ["a", "b"] [fLt "a" "b", fLt "b" "a"]).knownLe "a" "b" == false
#guard (graphOf ["a", "b"] [fLt "a" "b", fLt "b" "a"]).totallyOrdered == false
-- ≤ + strict backwards is also a strict cycle.
#guard (graphOf ["a", "b"] [fLe "a" "b", fLt "b" "a"]).inconsistent == true
-- Contradiction with a literal comparison: 1 < 2 but the fact says 2 < 1.
#guard (graphOfV [("1", some 1), ("2", some 2)] [fLt "2" "1"]).inconsistent == true
-- A consistent graph is not flagged.
#guard (graphOf ["a", "b"] [fLe "a" "b", fLe "b" "a"]).inconsistent == false
-- Equality cycles are fine (they are not strict).
#guard (graphOf ["a", "b", "c"] [fEq "a" "b", fEq "b" "c", fEq "c" "a"]).inconsistent == false

/-! ## Deduplication of atoms -/

#guard (graphOfV [("a", none), ("a", none), ("b", none)] []).atoms == #["a", "b"]

/-! ## Restriction: derived facts survive, dropped atoms disappear -/

private def gChain := graphOf ["a", "b", "c"] [fLe "a" "b", fLe "b" "c"]

#guard (gChain.restrict #["a", "c"]).atoms == #["a", "c"]
#guard (gChain.restrict #["a", "c"]).knownLe "a" "c" == true  -- derived through b
#guard (gChain.restrict #["a", "c"]).knownLe "b" "c" == false  -- b is gone
#guard (gChain.restrict #["a", "c"]).unknownPairs == #[]
#guard (gChain.restrict #["a", "c"]).totallyOrdered == true
-- Restriction keeps `keep` order and drops unknown names.
#guard (gChain.restrict #["c", "a", "zz"]).atoms == #["c", "a"]
-- Inconsistency is inherited even when the cycle's atoms are dropped.
#guard ((graphOf ["a", "p", "q"] [fLt "p" "q", fLt "q" "p"]).restrict #["a"]).inconsistent
    == true

/-! ## `Shape.orderGraph`: facts flow through atoms that are not shape endpoints

The shape below has atoms `a`, `c`; the facts chain through `b` (and a literal
`2`), which become auxiliary graph nodes and are then restricted away — the
transitive consequences remain. -/

private def sac : Shape := .subset (de .Icc "a" "c") (de .Icc "a" "c")

#guard (sac.orderGraph #[fLe "a" "b", fLe "b" "c"]).knownLe "a" "c" == true
#guard (sac.orderGraph #[fLe "a" "b", fLe "b" "c"]).atoms == #["a", "c"]
#guard (sac.orderGraph #[fLe "a" "b", fLe "b" "c"]).unknownPairs == #[]
-- Strictness propagates through the intermediate atom.
#guard (sac.orderGraph #[fLe "a" "b", fLt "b" "c"]).knownLt "a" "c" == true
-- A longer chain (three intermediates).
#guard (sac.orderGraph #[fLe "a" "m₁", fLe "m₁" "m₂", fLe "m₂" "m₃", fLe "m₃" "c"]).knownLe
    "a" "c" == true
-- Hypothesis atoms carrying literal values join the automatic literal comparisons:
-- with shape atoms `a` and `3` (value 3), the fact `a ≤ 2` (whose right-hand atom
-- `2` carries value 2 but is not a shape endpoint) yields `a < 3` via `2 < 3`.
private def sa3 : Shape := .subset
  (.leaf { kind := .Icc, lo? := some (ep "a"), hi? := some (epv "3" 3) })
  (.leaf { kind := .Icc, lo? := some (ep "a"), hi? := some (epv "3" 3) })
#guard (sa3.orderGraph #[{ lhs := "a", rhs := "2", rel := .le, rhsVal? := some 2 }]).knownLt
    "a" "3" == true
#guard (sa3.orderGraph #[{ lhs := "a", rhs := "2", rel := .le, rhsVal? := some 2 }]).atoms
    == #["a", "3"]

/-! A fact-only *inconsistency* taints the graph even between shape atoms. -/
#guard (sac.orderGraph #[fLt "p" "q", fLt "q" "p"]).inconsistent == true

end IntervalInspectorTests
