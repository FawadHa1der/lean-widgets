import ExprXRay
import ExprXRayTests.TestUtil

/-! # Tests for `ExprXRay.Diff`

Pairs of expressions with known classifications, ranking, exact summary
strings, and cross-consistency between diff paths and analyzer trees. -/

namespace ExprXRayTests.DiffTests

open Lean Elab Term Meta ExprXRay ExprXRayTests

/-! ## Pure ranking properties -/

-- instance mismatches rank strictly first, universes second, implicits third
#guard MismatchKind.instanceArgMismatch.rank == 0
#guard MismatchKind.differentUniverse.rank == 1
#guard MismatchKind.implicitArgMismatch.rank == 2
#guard MismatchKind.instanceArgMismatch.rank < MismatchKind.differentUniverse.rank
#guard MismatchKind.differentUniverse.rank < MismatchKind.implicitArgMismatch.rank
#guard MismatchKind.implicitArgMismatch.rank < MismatchKind.differentConst.rank
#guard MismatchKind.implicitArgMismatch.rank < MismatchKind.explicitArgMismatch.rank
#guard MismatchKind.implicitArgMismatch.rank < MismatchKind.binderMismatch.rank
#guard MismatchKind.implicitArgMismatch.rank < MismatchKind.structural.rank

-- rankMismatches is a stable rank sort
#guard
  let mk (k : MismatchKind) (tag : String) : Mismatch :=
    { kind := k, path := [], lhs := tag, rhs := tag }
  let ranked := rankMismatches #[mk .structural "s1", mk .instanceArgMismatch "i1",
                                 mk .explicitArgMismatch "e1", mk .instanceArgMismatch "i2",
                                 mk .differentUniverse "u1"]
  ranked.map (·.lhs) == #["i1", "i2", "u1", "e1", "s1"]

-- ancestor pruning: strict path prefixes
#guard isStrictPrefixOf [1] [1, 2]
#guard isStrictPrefixOf [] [0]
#guard !isStrictPrefixOf [1, 2] [1, 2]
#guard !isStrictPrefixOf [2] [1, 2]
#guard !isStrictPrefixOf [1, 2] [1]

-- pruneAncestors drops entries whose path is a strict prefix of another
-- entry's path, and keeps same-path duplicates and unrelated entries
#guard
  let mk (p : List Nat) (tag : String) : Mismatch :=
    { kind := .structural, path := p, lhs := tag, rhs := tag }
  (pruneAncestors #[mk [1] "anc", mk [1, 2] "leafA", mk [1, 2] "leafB", mk [3] "other"]).map (·.lhs)
    == #["leafA", "leafB", "other"]

-- Mismatch.describe formats site, both sides and the defeq annotation
-- (the default `defeq` status is `notDefeq`)
#guard
  let m : Mismatch := { kind := .instanceArgMismatch, path := [3],
                        lhs := "instA", rhs := "instB", site := "instance argument #3 of ite" }
  m.describe == "instance argument #3 of ite differs: instA vs instB (NOT defeq — this blocks rw)"

-- Mismatch.describe falls back to the kind label when no site is known
#guard
  let m : Mismatch := { kind := .structural, path := [], lhs := "a", rhs := "b" }
  m.describe == "structural difference: a vs b (NOT defeq — this blocks rw)"

/-! ## Identical expressions -/

#eval show TermElabM Unit from do
  -- syntactically identical
  assertEq "identical: empty diff" (← diffT (← `((1 + 1 : Nat))) (← `((1 + 1 : Nat)))).size 0
  -- alpha-equivalent binders (different names) are equal
  assertEq "alpha: empty diff"
    (← diffT (← `(fun (x : Nat) => x + 1)) (← `(fun (y : Nat) => y + 1))).size 0
  -- mdata is transparent: wrapping one side changes nothing
  let e ← elabT (← `((5 : Nat)))
  assertEq "mdata transparent" (← diffExprs (Expr.mdata {} e) e).size 0

/-! ## The motivating case: instance-only difference -/

#eval show TermElabM Unit from do
  let ms ← diffT
    (← `(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
    (← `(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0))
  assertEq "ite inst: exactly one mismatch" ms.size 1
  assertEq "ite inst: classified instanceArgMismatch" ms[0]!.kind .instanceArgMismatch
  assertEq "ite inst: at arg 3" ms[0]!.path [3]
  -- exact curated summary string
  assertEq "ite inst: exact summary"
    (diffSummary ms)
    (some "instance argument #3 of ite differs: instDecidableEqNat 2 2 vs Classical.propDecidable (2 = 2) (NOT defeq — this blocks rw)")

#eval show TermElabM Unit from do
  -- decide-based pair: same shape, different Decidable instances
  let ms ← diffT
    (← `(@decide (1 = 1) (instDecidableEqNat 1 1)))
    (← `(@decide (1 = 1) (Classical.propDecidable (1 = 1))))
  assertEq "decide inst: one mismatch" ms.size 1
  assertEq "decide inst: kind" ms[0]!.kind .instanceArgMismatch
  assertEq "decide inst: path" ms[0]!.path [2]

/-! ## Instance mismatch is ranked FIRST even when an explicit arg also differs -/

#eval show TermElabM Unit from do
  let ms ← diffT
    (← `(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
    (← `(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 5 0))
  assertTrue "inst+expl: several mismatches" (ms.size > 1)
  assertEq "inst+expl: instance ranked first" ms[0]!.kind .instanceArgMismatch
  assertEq "inst+expl: top is the ite instance" ms[0]!.path [3]
  -- the explicit difference is still collected — localized at the deepest
  -- informative site (the numeral literal inside argument #4) ...
  assertTrue "inst+expl: explicit mismatch collected (localized)"
    (ms.any fun m => m.kind == .explicitArgMismatch && m.path == [4, 2])
  -- ... while the redundant ancestor entry at [4] itself is pruned
  assertFalse "inst+expl: ancestor entry pruned"
    (ms.any fun m => m.path == [4])
  -- and the summary talks about the instance, not the explicit arg
  assertContains "inst+expl: summary mentions instance"
    (diffSummary ms).get! "instance argument #3 of ite"

/-! ## Universe-only differences -/

#eval show TermElabM Unit from do
  let ms ← diffT (← `(@PUnit.{1})) (← `(@PUnit.{2}))
  assertEq "univ const: one mismatch" ms.size 1
  assertEq "univ const: kind" ms[0]!.kind .differentUniverse
  assertEq "univ const: at root" ms[0]!.path ([] : List Nat)
  -- note the plural verb: "universe levels ... differ", not "differs"
  assertEq "univ const: exact summary"
    (diffSummary ms)
    (some "universe levels of PUnit differ: [1] vs [2] (NOT defeq — this blocks rw)")

#eval show TermElabM Unit from do
  -- Sort-level difference
  let ms ← diffT (← `(Type 0)) (← `(Type 3))
  assertEq "sort univ: one mismatch" ms.size 1
  assertEq "sort univ: kind" ms[0]!.kind .differentUniverse
  assertEq "sort univ: summary" ms[0]!.describe
    "sort level differs: 1 vs 4 (NOT defeq — this blocks rw)"

#eval show TermElabM Unit from do
  -- universe difference on an APPLIED constant head (heads same name,
  -- different levels): reported at the head path [0]
  let ms ← diffT (← `(@List.nil.{1} (Type 0))) (← `(@List.nil.{2} (Type 1)))
  assertTrue "applied univ: nonempty" !ms.isEmpty
  assertEq "applied univ: top kind" ms[0]!.kind .differentUniverse
  assertEq "applied univ: top path" ms[0]!.path [0]

/-! ## Different constants -/

#eval show TermElabM Unit from do
  let ms ← diffT (← `(Nat.succ 3)) (← `(Nat.pred 3))
  assertEq "const: one mismatch" ms.size 1
  assertEq "const: kind" ms[0]!.kind .differentConst
  assertEq "const: head path" ms[0]!.path [0]
  assertEq "const: sides" (ms[0]!.lhs, ms[0]!.rhs) ("Nat.succ", "Nat.pred")

/-! ## Implicit-argument differences -/

#eval show TermElabM Unit from do
  -- @id Nat 5 vs @id Int 5 : implicit type arg differs (and the explicit
  -- literal 5 elaborates differently too, but implicit ranks first)
  let ms ← diffT (← `(@id Nat 5)) (← `(@id Int 5))
  assertTrue "implicit: found" (ms.any fun m => m.kind == .implicitArgMismatch && m.path == [1])
  -- descending into the explicit numeral finds `instOfNatNat 5` vs
  -- `instOfNatInt 5`-style instance mismatches, which rank even higher
  assertEq "implicit: deep instance mismatch ranked first"
    ms[0]!.kind .instanceArgMismatch
  -- the numeral's arg-level entry at [2] is pruned: the diff localized it
  -- to the implicit/instance mismatches inside the numeral elaboration
  assertFalse "implicit: numeral ancestor entry pruned"
    (ms.any fun m => m.path == [2])
  assertTrue "implicit: localized entries under the numeral"
    (ms.any fun m => m.path.head? == some 2 && m.path.length == 2)
  -- every implicit mismatch still ranks before every lower-ranked kind
  let idxImp := ms.findIdx? (·.kind == .implicitArgMismatch)
  let idxConst := ms.findIdx? (·.kind == .differentConst)
  assertTrue "implicit: implicit ranks before differentConst"
    (idxImp.isSome && idxConst.isSome && idxImp.get! < idxConst.get!)
  let imp := ms[idxImp.get!]!
  assertContains "implicit: summary" imp.describe "implicit argument #1 of id"
  assertEq "implicit: sides" (imp.lhs, imp.rhs) ("Nat", "Int")

/-! ## Explicit-argument differences -/

#eval show TermElabM Unit from do
  -- numeral-free pair so no hidden OfNat instances are involved
  let ms ← diffT (← `(Nat.succ Nat.zero)) (← `(Nat.succ (Nat.succ Nat.zero)))
  assertTrue "explicit: found at arg 1"
    (ms.any fun m => m.kind == .explicitArgMismatch && m.path == [1])
  assertEq "explicit: top kind" ms[0]!.kind .explicitArgMismatch
  -- explicit arguments are numbered among explicit arguments only
  assertContains "explicit: summary" ms[0]!.describe "explicit argument #1 of Nat.succ"

/-! ## Explicit-only ordinals for explicit arguments -/

#eval show TermElabM Unit from do
  -- REGRESSION (bughunt2): the two visible operands of `+` sit at
  -- absolute spine positions #5/#6 of HAdd.hAdd; the summaries must
  -- number them among the *explicit* arguments (#1/#2)
  let ms ← diffT (← `(fun x : Nat => x + 0)) (← `(fun x : Nat => 0 + x))
  assertTrue "hAdd ordinals: first operand"
    (ms.any fun m => m.site == "explicit argument #1 of HAdd.hAdd")
  assertTrue "hAdd ordinals: second operand"
    (ms.any fun m => m.site == "explicit argument #2 of HAdd.hAdd")
  -- absolute spine numbering no longer leaks into explicit-argument sites
  assertFalse "hAdd ordinals: no absolute numbering"
    (ms.any fun m => m.site == "explicit argument #5 of HAdd.hAdd"
                  || m.site == "explicit argument #6 of HAdd.hAdd")
  -- instance/implicit sites keep the absolute position (what you would
  -- write in an @-application)
  let ms₂ ← diffT
    (← `(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
    (← `(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0))
  assertContains "ite inst: absolute numbering kept"
    ms₂[0]!.describe "instance argument #3 of ite"

/-! ## One deep difference → one difference site (ancestor pruning) -/

#eval show TermElabM Unit from do
  -- REGRESSION (bughunt2): one extra Eq.trans layer under 40 nested
  -- Eq.trans used to produce 41 entries (one per ancestor spine level),
  -- and 60-char left-anchored truncation made them all print literally
  -- identical "X vs X" lines. Now only the deepest informative entries
  -- remain and every printed pair shows a visible difference.
  let rfl1 ← elabT (← `((rfl : (1 : Nat) = 1)))
  let one ← elabT (← `((1 : Nat)))
  let natTy := Lean.mkConst ``Nat
  let mkTrans (p q : Expr) : Expr :=
    mkAppN (Lean.mkConst ``Eq.trans [1]) #[natTy, one, one, one, p, q]
  let mut a := rfl1
  for _ in [0:40] do
    a := mkTrans a rfl1
  let b := mkTrans a rfl1
  let ms ← diffExprs a b
  assertEq "cascade: two entries for one difference" ms.size 2
  for m in ms do
    assertTrue s!"cascade: sides visibly differ ({m.site})" (m.lhs != m.rhs)

#eval show TermElabM Unit from do
  -- REGRESSION (bughunt2): when the two sides share a >60-char pretty
  -- prefix, the truncated strings used to coincide; the window is now
  -- anchored at the first differing character
  let long := String.ofList (List.replicate 80 'x')
  let ms ← diffExprs (Expr.lit (.strVal (long ++ "A"))) (Expr.lit (.strVal (long ++ "B")))
  assertEq "window: one structural mismatch" (ms.map (·.kind)) #[.structural]
  assertTrue "window: sides visibly differ" (ms[0]!.lhs != ms[0]!.rhs)
  assertContains "window: lhs shows its differing char" ms[0]!.lhs "A"
  assertContains "window: rhs shows its differing char" ms[0]!.rhs "B"
  assertContains "window: cut marker" ms[0]!.lhs "…"

/-! ## Binder differences -/

#eval show TermElabM Unit from do
  -- binder domain differs
  let ms ← diffT (← `(fun (x : Nat) => x)) (← `(fun (x : Int) => x))
  assertTrue "binder type: reported"
    (ms.any fun m => m.kind == .binderMismatch && m.path == [0])
  assertTrue "binder type: const diff also collected"
    (ms.any (·.kind == .differentConst))

#eval show TermElabM Unit from do
  -- binder ANNOTATION differs: implicit vs explicit lambda
  let a ← elabT (← `(fun (x : Nat) => x))
  let b := Expr.lam `x (mkConst ``Nat) (.bvar 0) .implicit
  let ms ← diffExprs a b
  assertEq "binder info: one mismatch" ms.size 1
  assertEq "binder info: kind" ms[0]!.kind .binderMismatch
  assertContains "binder info: description" ms[0]!.describe "binder annotation of x"

#eval show TermElabM Unit from do
  -- bodies compared alpha-aware under a SHARED fvar: only the real
  -- difference (the +1) shows up, nothing about binder names
  let ms ← diffT (← `(fun (x : Nat) => x + 1)) (← `(fun (z : Nat) => z + 2))
  assertTrue "alpha body: nonempty" !ms.isEmpty
  assertTrue "alpha body: all mismatches inside the body"
    (ms.all fun m => m.path.head? == some 1)
  assertFalse "alpha body: no binder mismatch" (ms.any (·.kind == .binderMismatch))

/-! ## lam vs forall and other structural cases -/

#eval show TermElabM Unit from do
  let a ← elabT (← `(fun (x : Nat) => x = x))
  let b ← elabT (← `(∀ (x : Nat), x = x))
  let ms ← diffExprs a b
  assertEq "lam/forall: one mismatch" ms.size 1
  assertEq "lam/forall: structural" ms[0]!.kind .structural

#eval show TermElabM Unit from do
  -- application arity differs: structural at the application node
  let ms ← diffT (← `(Nat.add 1 2)) (← `(Nat.succ 1))
  assertEq "arity: one mismatch" ms.size 1
  assertEq "arity: structural" ms[0]!.kind .structural
  assertEq "arity: site" ms[0]!.site "application shape"

#eval show TermElabM Unit from do
  -- different literals: structural
  let msLit ← diffExprs (Expr.lit (.strVal "a")) (Expr.lit (.strVal "b"))
  assertEq "lit: structural" (msLit.map (·.kind)) #[.structural]
  -- proj index differs: structural
  let pair ← elabT (← `(((1, 2) : Nat × Nat)))
  let ms ← diffExprs (Expr.proj ``Prod 0 pair) (Expr.proj ``Prod 1 pair)
  assertEq "proj: structural" (ms.map (·.kind)) #[.structural]
  assertEq "proj: site" ms[0]!.site "structure projection"

#eval show TermElabM Unit from do
  -- proj with SAME field: descends into the structure argument
  let p1 ← elabT (← `(((1, 2) : Nat × Nat)))
  let p2 ← elabT (← `(((1, 3) : Nat × Nat)))
  let ms ← diffExprs (Expr.proj ``Prod 0 p1) (Expr.proj ``Prod 0 p2)
  assertTrue "proj descend: nonempty" !ms.isEmpty
  assertTrue "proj descend: paths start with 0"
    (ms.all fun m => m.path.head? == some 0)

/-! ## let-bindings -/

#eval show TermElabM Unit from do
  let ms ← diffT (← `(let k : Nat := 3; k + k)) (← `(let k : Nat := 4; k + k))
  assertTrue "let: value mismatch found"
    (ms.any fun m => m.path.head? == some 1)
  -- body under the shared let-fvar is identical, so nothing at path [2]
  assertFalse "let: no body mismatch" (ms.any fun m => m.path.head? == some 2)

/-! ## Cross-consistency: diff paths address analyzer nodes -/

#eval show TermElabM Unit from do
  let a ← elabT (← `(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
  let b ← elabT (← `(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0))
  let ms ← diffExprs a b
  let na ← analyzeExpr a
  let nb ← analyzeExpr b
  for m in ms do
    -- every mismatch path addresses a real node in BOTH analyzer trees
    let sa ← nodeAt "cross: lhs node" na m.path
    let sb ← nodeAt "cross: rhs node" nb m.path
    -- and for the instance mismatch, both nodes are instance-implicit args
    if m.kind == .instanceArgMismatch then
      assertEq "cross: lhs role" sa.role .instImplicit
      assertEq "cross: rhs role" sb.role .instImplicit
      -- diff's pp strings agree with the analyzer's pp of the same node
      assertEq "cross: lhs pp agrees" m.lhs sa.pp
      assertEq "cross: rhs pp agrees" m.rhs sb.pp

#eval show TermElabM Unit from do
  -- diff is symmetric in classification: swapping sides swaps lhs/rhs
  let a ← (`(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
  let b ← (`(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0))
  let ms₁ ← diffT a b
  let ms₂ ← diffT b a
  assertEq "sym: same count" ms₁.size ms₂.size
  assertEq "sym: same kinds" (ms₁.map (·.kind)) (ms₂.map (·.kind))
  assertEq "sym: sides swapped" (ms₁.map (·.lhs)) (ms₂.map (·.rhs))

end ExprXRayTests.DiffTests
