import IntervalInspectorTests.Helpers

/-! # Model tests: kind flags, ASCII/desc/debug rendering, atom collection -/

namespace IntervalInspectorTests

open IntervalInspector

/-! ## Open/closed and boundedness flags — the glyph convention rests on these -/

#guard IntervalKind.Icc.closedLeft == true
#guard IntervalKind.Icc.closedRight == true
#guard IntervalKind.Ico.closedLeft == true
#guard IntervalKind.Ico.closedRight == false
#guard IntervalKind.Ioc.closedLeft == false
#guard IntervalKind.Ioc.closedRight == true
#guard IntervalKind.Ioo.closedLeft == false
#guard IntervalKind.Ioo.closedRight == false
#guard IntervalKind.Ici.closedLeft == true
#guard IntervalKind.Iic.closedRight == true
#guard IntervalKind.Ioi.closedLeft == false
#guard IntervalKind.Iio.closedRight == false

#guard IntervalKind.Icc.boundedLeft && IntervalKind.Icc.boundedRight
#guard IntervalKind.Ici.boundedLeft && !IntervalKind.Ici.boundedRight
#guard IntervalKind.Ioi.boundedLeft && !IntervalKind.Ioi.boundedRight
#guard !IntervalKind.Iic.boundedLeft && IntervalKind.Iic.boundedRight
#guard !IntervalKind.Iio.boundedLeft && IntervalKind.Iio.boundedRight
#guard !IntervalKind.univ.boundedLeft && !IntervalKind.univ.boundedRight
#guard IntervalKind.singleton.boundedLeft && IntervalKind.singleton.boundedRight

#guard IntervalKind.Icc.isDoubleEnded && IntervalKind.Ico.isDoubleEnded
    && IntervalKind.Ioc.isDoubleEnded && IntervalKind.Ioo.isDoubleEnded
#guard !IntervalKind.Ici.isDoubleEnded && !IntervalKind.univ.isDoubleEnded

/-! ## ASCII rendering (the exact convention promised in the docs) -/

#guard (Tree.ascii (de .Icc "a" "b")) == "[a───b]"
#guard (Tree.ascii (de .Ico "a" "b")) == "[a───b)"
#guard (Tree.ascii (de .Ioc "a" "b")) == "(a───b]"
#guard (Tree.ascii (de .Ioo "a" "b")) == "(a───b)"
#guard (Tree.ascii (rayLo .Ici "a")) == "[a───∞)"
#guard (Tree.ascii (rayLo .Ioi "a")) == "(a───∞)"
#guard (Tree.ascii (rayHi .Iic "b")) == "(-∞───b]"
#guard (Tree.ascii (rayHi .Iio "b")) == "(-∞───b)"
#guard (Tree.ascii univT) == "(-∞───∞)"
#guard (Tree.ascii emptyT) == "∅"
#guard (Tree.ascii (singT "a")) == "{a}"
#guard (Tree.ascii (.union (de .Ioc "a" "b") (de .Ioc "b" "c"))) == "(a───b] ∪ (b───c]"
#guard (Tree.ascii (.inter (de .Icc "a" "b") (de .Icc "c" "d"))) == "[a───b] ∩ [c───d]"

/-! ## desc / debugString -/

#guard (Tree.desc (de .Ioc "a" "b")) == "Ioc a b"
#guard (Tree.desc (rayLo .Ici "a")) == "Ici a"
#guard (Tree.desc (rayHi .Iio "b")) == "Iio b"
#guard (Tree.desc (singT "a")) == "{a}"
#guard (Tree.desc (.union (de .Ioc "a" "b") (.inter (de .Icc "c" "d") univT)))
    == "Ioc a b ∪ (Icc c d ∩ univ)"
#guard (Shape.desc (.eq (.union (de .Ioc "a" "b") (de .Ioc "b" "c")) (de .Ioc "a" "c")))
    == "Ioc a b ∪ Ioc b c = Ioc a c"
#guard (Shape.ascii (.term (de .Ioc "a" "b"))) == "Ioc a b: (a───b]"
#guard (Shape.ascii (.mem (ep "x") (de .Icc "a" "b"))) == "x ∈ Icc a b: x ∈ [a───b]"
#guard (Shape.ascii (.subset (de .Ioo "a" "b") (de .Icc "a" "b")))
    == "Ioo a b ⊆ Icc a b: (a───b) ⊆ [a───b]"
#guard (Shape.debugString (.eq (.union (de .Ioc "a" "b") (de .Ioc "b" "c")) (de .Ioc "a" "c")))
    == "eq(union(Ioc(a,b),Ioc(b,c)),Ioc(a,c))"
#guard (Shape.debugString (.ssubset (rayLo .Ioi "a") (rayLo .Ici "a")))
    == "ssubset(Ioi(a),Ici(a))"

/-! ## Atom collection: traversal order, dedup by pp, mem-atom first -/

#guard (Shape.atoms (.eq (.union (de .Ioc "a" "b") (de .Ioc "b" "c")) (de .Ioc "a" "c"))).map
    (·.pp) == #["a", "b", "c"]
#guard (Shape.atoms (.mem (ep "x") (de .Icc "a" "b"))).map (·.pp) == #["x", "a", "b"]
#guard (Shape.atoms (.subset (de .Icc "b" "a") (de .Icc "a" "b"))).map (·.pp) == #["b", "a"]
#guard (Shape.atoms (.term emptyT)).map (·.pp) == (#[] : Array String)
#guard (Shape.atoms (.term (singT "a"))).map (·.pp) == #["a"]

/-! ## Nonempty / neEmpty shapes -/

#guard (Shape.desc (.nonempty (de .Ioc "a" "b"))) == "(Ioc a b).Nonempty"
#guard (Shape.desc (.neEmpty (de .Icc "a" "b"))) == "Icc a b ≠ ∅"
#guard (Shape.ascii (.nonempty (de .Ioc "a" "b"))) == "(Ioc a b).Nonempty: (a───b] ≠ ∅"
#guard (Shape.ascii (.neEmpty (de .Icc "a" "b"))) == "Icc a b ≠ ∅: [a───b] ≠ ∅"
#guard (Shape.ascii (.nonempty (rayLo .Ici "a"))) == "(Ici a).Nonempty: [a───∞) ≠ ∅"
#guard (Shape.debugString (.nonempty (de .Ioc "a" "b"))) == "nonempty(Ioc(a,b))"
#guard (Shape.debugString (.neEmpty (rayLo .Ici "a"))) == "neEmpty(Ici(a))"
#guard (Shape.atoms (.nonempty (de .Ioc "a" "b"))).map (·.pp) == #["a", "b"]
#guard (Shape.atoms (.neEmpty (de .Icc "a" "b"))).map (·.pp) == #["a", "b"]

/-! ## Set-builder provenance marker -/

#guard (Tree.debugString (deSB .Ico "a" "b")) == "Ico*(a,b)"
#guard (Tree.debugString (de .Ico "a" "b")) == "Ico(a,b)"
#guard (deSB .Ico "a" "b").anyFromSetBuilder == true
#guard (de .Ico "a" "b").anyFromSetBuilder == false
#guard (Tree.union (de .Icc "a" "b") (deSB .Ioo "c" "d")).anyFromSetBuilder == true
-- Provenance does not leak into desc/ascii (only debugString and the SVG badge).
#guard (Tree.desc (deSB .Ico "a" "b")) == "Ico a b"
#guard (Tree.ascii (deSB .Ico "a" "b")) == "[a───b)"

/-! ## strContains sanity -/

#guard strContains "hello world" "o w" == true
#guard strContains "hello" "z" == false
#guard strContains "aaa" "aa" == true

end IntervalInspectorTests
