import ExprXRay
import ExprXRayTests.TestUtil

/-! # Tests for `ExprXRay.Analyze`

Binder-role classification, node kinds, universes, coercion detection,
mdata, types, truncation and depth limiting. -/

namespace ExprXRayTests.AnalyzeTests

open Lean Elab Term Meta ExprXRay ExprXRayTests

/-! ## Binder-role classification -/

-- `@id Nat 5`: the type argument is implicit, the value explicit.
#eval show TermElabM Unit from do
  let n ← analyzeT (← `(@id Nat 5))
  assertEq "id: root kind" n.kind .app
  assertEq "id: 3 children (head + 2 args)" n.children.size 3
  assertEq "id: head role is none" ((← nodeAt "id[0]" n [0]).role) .none
  assertEq "id: head kind is const" ((← nodeAt "id[0]" n [0]).kind) .const
  assertEq "id: type arg implicit" ((← nodeAt "id[1]" n [1]).role) .implicit
  assertEq "id: value arg explicit" ((← nodeAt "id[2]" n [2]).role) .explicit
  assertEq "id: type arg pp" ((← nodeAt "id[1]" n [1]).pp) "Nat"
  assertEq "id: root type" n.type? (some "Nat")

-- `1 + 1`: the `HAdd` instance argument is detected as instance-implicit.
#eval show TermElabM Unit from do
  let n ← analyzeT (← `((1 + 1 : Nat)))
  assertEq "add: root pp" n.pp "1 + 1"
  assertEq "add: 7 children (head + 6 args)" n.children.size 7
  assertEq "add: α implicit" ((← nodeAt "add[1]" n [1]).role) .implicit
  assertEq "add: β implicit" ((← nodeAt "add[2]" n [2]).role) .implicit
  assertEq "add: γ implicit" ((← nodeAt "add[3]" n [3]).role) .implicit
  assertEq "add: instance arg detected" ((← nodeAt "add[4]" n [4]).role) .instImplicit
  assertContains "add: instance pp" ((← nodeAt "add[4]" n [4]).pp) "instHAdd"
  assertEq "add: lhs operand explicit" ((← nodeAt "add[5]" n [5]).role) .explicit
  assertEq "add: rhs operand explicit" ((← nodeAt "add[6]" n [6]).role) .explicit
  -- the nested OfNat instance is also classified
  assertEq "add: nested OfNat instance"
    ((← nodeAt "add[5,3]" n [5, 3]).role) .instImplicit

/-- Local function with a strict-implicit argument. -/
private def sfun ⦃n : Nat⦄ (m : Nat) : Nat := n + m

-- strict-implicit arguments are classified as such
#eval show TermElabM Unit from do
  let n ← analyzeT (← `(@sfun 1 2))
  assertEq "sfun: strict-implicit arg"
    ((← nodeAt "sfun[1]" n [1]).role) .strictImplicit
  assertEq "sfun: explicit arg" ((← nodeAt "sfun[2]" n [2]).role) .explicit

/-! ## Node kinds -/

#eval show TermElabM Unit from do
  -- lam: children are domain then body; body sees the named fvar
  let n ← analyzeT (← `(fun (x : Nat) => x))
  assertEq "lam: kind" n.kind .lam
  assertEq "lam: 2 children" n.children.size 2
  assertEq "lam: domain kind" ((← nodeAt "lam[0]" n [0]).kind) .const
  assertEq "lam: body is fvar" ((← nodeAt "lam[1]" n [1]).kind) .fvar
  assertEq "lam: body pp uses binder name" ((← nodeAt "lam[1]" n [1]).pp) "x"
  assertEq "lam: body type" ((← nodeAt "lam[1]" n [1]).type?) (some "Nat")

#eval show TermElabM Unit from do
  -- forallE
  let n ← analyzeT (← `(∀ (n : Nat), n = n))
  assertEq "forall: kind" n.kind .forallE
  assertEq "forall: type is Prop" n.type? (some "Prop")
  assertEq "forall: 2 children" n.children.size 2
  assertEq "forall: body kind is app (Eq)" ((← nodeAt "fa[1]" n [1]).kind) .app

#eval show TermElabM Unit from do
  -- letE: children are type, value, body
  let n ← analyzeT (← `(let k : Nat := 3; k + k))
  assertEq "let: kind" n.kind .letE
  assertEq "let: 3 children" n.children.size 3
  assertEq "let: type child" ((← nodeAt "let[0]" n [0]).pp) "Nat"
  assertEq "let: value child pp" ((← nodeAt "let[1]" n [1]).pp) "3"
  assertEq "let: body kind" ((← nodeAt "let[2]" n [2]).kind) .app
  assertEq "let: body pp uses binder name" ((← nodeAt "let[2]" n [2]).pp) "k + k"

#eval show TermElabM Unit from do
  -- sort: Type 1 = Sort 2, Prop = Sort 0
  let n ← analyzeT (← `(Type 1))
  assertEq "sort: kind" n.kind .sort
  assertEq "sort: level recorded" n.levels ["2"]
  assertEq "sort: type" n.type? (some "Type 2")
  let p ← analyzeT (← `(Prop))
  assertEq "Prop: kind" p.kind .sort
  assertEq "Prop: level 0" p.levels ["0"]

#eval show TermElabM Unit from do
  -- lit
  let n ← analyzeT (← `((37 : Nat)))
  -- 37 elaborates to OfNat.ofNat with a raw literal inside
  let litNode ← nodeAt "lit[2]" n [2]
  assertEq "lit: kind" litNode.kind .lit
  assertEq "lit: pp" litNode.pp "37"
  -- string literals are also lits
  let s ← analyzeT (← `("hi"))
  assertEq "strlit: kind" s.kind .lit
  assertEq "strlit: type" s.type? (some "String")

#eval show TermElabM Unit from do
  -- mvar: a fresh metavariable is analyzed, with its type inferred
  let m ← Meta.mkFreshExprMVar (some (mkConst ``Nat))
  let n ← analyzeExpr m
  assertEq "mvar: kind" n.kind .mvar
  assertEq "mvar: type" n.type? (some "Nat")

#eval show TermElabM Unit from do
  -- proj: built manually since `.1` sugar elaborates to `Prod.fst`
  let pair ← elabT (← `(((1, 2) : Nat × Nat)))
  let n ← analyzeExpr (Expr.proj ``Prod 0 pair)
  assertEq "proj: kind" n.kind .proj
  assertEq "proj: one child" n.children.size 1
  assertEq "proj: child kind" ((← nodeAt "proj[0]" n [0]).kind) .app
  assertEq "proj: type" n.type? (some "Nat")

#eval show TermElabM Unit from do
  -- mdata: marker flag set, child analyzed through the wrapper
  let inner ← elabT (← `((5 : Nat)))
  let n ← analyzeExpr (Expr.mdata {} inner)
  assertEq "mdata: kind" n.kind .mdata
  assertTrue "mdata: isMData flag" n.isMData
  assertEq "mdata: one child" n.children.size 1
  assertEq "mdata: child pp" ((← nodeAt "mdata[0]" n [0]).pp) "5"
  -- non-mdata nodes do not carry the flag
  assertFalse "mdata: inner not flagged" ((← nodeAt "mdata[0]" n [0]).isMData)

/-! ## Universe levels -/

#eval show TermElabM Unit from do
  let n ← analyzeT (← `(@id Nat 5))
  assertEq "univ: id gets level 1" ((← nodeAt "u[0]" n [0]).levels) ["1"]
  -- monomorphic constants have no levels
  assertEq "univ: Nat has no levels" ((← nodeAt "u[1]" n [1]).levels) ([] : List String)

#eval show TermElabM Unit from do
  let n ← analyzeT (← `(@PUnit.{2}))
  assertEq "univ: PUnit.{2} kind" n.kind .const
  assertEq "univ: PUnit.{2} levels" n.levels ["2"]

#eval show TermElabM Unit from do
  -- two-level constant
  let n ← analyzeT (← `(@ULift.{3, 1} (Type 0)))
  assertEq "univ: ULift levels" ((← nodeAt "ul[0]" n [0]).levels) ["3", "1"]

/-! ## Coercion detection -/

#eval show TermElabM Unit from do
  -- elaborated `((3 : Nat) : Int)` has the coercion `Nat.cast` at its head
  let n ← analyzeT (← `(((3 : Nat) : Int)))
  assertTrue "coe: app node flagged" n.isCoe
  assertTrue "coe: head const flagged" ((← nodeAt "coe[0]" n [0]).isCoe)
  assertEq "coe: root type is Int" n.type? (some "Int")
  -- the numeral argument itself is NOT a coercion
  assertFalse "coe: numeral arg not flagged" ((← nodeAt "coe[3]" n [3]).isCoe)

#eval show TermElabM Unit from do
  -- negative: an ordinary application is not flagged
  let n ← analyzeT (← `((1 + 1 : Nat)))
  assertFalse "coe: plain add not flagged" n.isCoe
  assertFalse "coe: HAdd.hAdd not flagged" ((← nodeAt "nc[0]" n [0]).isCoe)

#eval show TermElabM Unit from do
  -- Int.ofNat is a registered/known coercion head
  let n ← analyzeT (← `(Int.ofNat 3))
  assertTrue "coe: Int.ofNat flagged" n.isCoe

/-! ## Depth limiting and elision -/

#eval show TermElabM Unit from do
  -- maxDepth 0: the root itself is cut
  let n ← analyzeT (← `((1 + 1 : Nat))) { maxDepth := 0 }
  assertTrue "depth0: root elided" n.elided
  assertEq "depth0: no children" n.children.size 0
  -- the pretty string is still available on the cut node
  assertEq "depth0: pp survives" n.pp "1 + 1"

#eval show TermElabM Unit from do
  -- maxDepth 1: children present, composite grandchildren elided
  let n ← analyzeT (← `((1 + 1 : Nat))) { maxDepth := 1 }
  assertFalse "depth1: root not elided" n.elided
  assertEq "depth1: children present" n.children.size 7
  let operand ← nodeAt "depth1[5]" n [5]
  assertTrue "depth1: composite child elided" operand.elided
  assertEq "depth1: elided child has no children" operand.children.size 0
  -- atomic children (consts) are complete, not elided
  assertFalse "depth1: const child not elided" ((← nodeAt "depth1[1]" n [1]).elided)

#eval show TermElabM Unit from do
  -- a lam cut at depth 0 is elided too
  let n ← analyzeT (← `(fun (x : Nat) => x + 1)) { maxDepth := 0 }
  assertEq "depthlam: kind" n.kind .lam
  assertTrue "depthlam: elided" n.elided
  assertEq "depthlam: no children" n.children.size 0
  -- with the default maxDepth the same expression is NOT elided anywhere
  let full ← analyzeT (← `(fun (x : Nat) => x + 1))
  assertFalse "depthlam: no elision at default depth"
    (full.any (·.elided))

/-! ## Pretty-string truncation -/

#eval show TermElabM Unit from do
  let n ← analyzeT (← `((1 + 1 : Nat))) { ppMaxLength := 3 }
  assertEq "trunc: root pp cut to 3 + ellipsis" n.pp "1 +…"
  -- short subterm strings survive untouched
  assertEq "trunc: short child pp intact" ((← nodeAt "tr[1]" n [1]).pp) "Nat"

/-! ## Application spine order -/

#eval show TermElabM Unit from do
  let n ← analyzeT (← `(Nat.add 1 2))
  assertEq "spine: 3 children" n.children.size 3
  assertEq "spine: head pp" ((← nodeAt "sp[0]" n [0]).pp) "Nat.add"
  assertEq "spine: first arg pp" ((← nodeAt "sp[1]" n [1]).pp) "1"
  assertEq "spine: second arg pp" ((← nodeAt "sp[2]" n [2]).pp) "2"

end ExprXRayTests.AnalyzeTests
