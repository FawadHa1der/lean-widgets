import ExprXRay
import ExprXRayTests.TestUtil

/-! # Edge-case tests

Metavariables, `Prop` vs `Type`, deep expressions vs `maxDepth`,
assigned mvars, and analyzer robustness on odd inputs. -/

namespace ExprXRayTests.EdgeTests

open Lean Elab Term Meta ExprXRay ExprXRayTests

/-! ## Metavariables -/

#eval show TermElabM Unit from do
  -- an application containing an unassigned mvar analyzes without failing
  let m ← mkFreshExprMVar (some (mkConst ``Nat))
  let e := mkApp (mkConst ``Nat.succ) m
  let n ← analyzeExpr e
  assertEq "mvar app: root kind" n.kind .app
  assertEq "mvar app: arg kind" ((← nodeAt "mv[1]" n [1]).kind) .mvar
  assertEq "mvar app: arg type" ((← nodeAt "mv[1]" n [1]).type?) (some "Nat")
  assertEq "mvar app: arg role" ((← nodeAt "mv[1]" n [1]).role) .explicit

#eval show TermElabM Unit from do
  -- ASSIGNED mvars are instantiated before analysis: no mvar node remains
  let m ← mkFreshExprMVar (some (mkConst ``Nat))
  m.mvarId!.assign (mkConst ``Nat.zero)
  let e := mkApp (mkConst ``Nat.succ) m
  let n ← analyzeExpr e
  assertFalse "assigned mvar: no mvar node" (n.any (·.kind == .mvar))
  assertEq "assigned mvar: const instead" ((← nodeAt "am[1]" n [1]).kind) .const
  assertEq "assigned mvar: pp" ((← nodeAt "am[1]" n [1]).pp) "Nat.zero"

#eval show TermElabM Unit from do
  -- diff also instantiates assigned mvars: both sides become equal
  let m ← mkFreshExprMVar (some (mkConst ``Nat))
  m.mvarId!.assign (mkConst ``Nat.zero)
  let a := mkApp (mkConst ``Nat.succ) m
  let b := mkApp (mkConst ``Nat.succ) (mkConst ``Nat.zero)
  assertEq "diff mvar: instantiated equal" (← diffExprs a b).size 0
  -- two DIFFERENT unassigned mvars are a structural mismatch, with the
  -- honest `undetermined` status (they are unifiable, so claiming
  -- "NOT defeq" would be wrong)
  let m1 ← mkFreshExprMVar (some (mkConst ``Nat))
  let m2 ← mkFreshExprMVar (some (mkConst ``Nat))
  let ms ← diffExprs m1 m2
  assertEq "diff mvar: distinct mvars mismatch" (ms.map (·.kind)) #[.structural]
  assertEq "diff mvar: annotated undetermined" ms[0]!.defeq .undetermined

/-! ## Prop vs Type -/

#eval show TermElabM Unit from do
  let ms ← diffT (← `(Prop)) (← `(Type))
  assertEq "Prop/Type: one mismatch" ms.size 1
  assertEq "Prop/Type: universe kind" ms[0]!.kind .differentUniverse
  assertEq "Prop/Type: summary" ms[0]!.describe
    "sort level differs: 0 vs 1 (NOT defeq — this blocks rw)"

#eval show TermElabM Unit from do
  -- Prop-valued vs Type-valued foralls: sorts recorded correctly
  let p ← analyzeT (← `(∀ (n : Nat), n = n))
  assertEq "prop forall: type" p.type? (some "Prop")
  let t ← analyzeT (← `(Nat → Nat))
  assertEq "type forall: kind" t.kind .forallE
  assertEq "type forall: type" t.type? (some "Type")
  -- a proof term is analyzed with its Prop type shown
  let prf ← analyzeT (← `((rfl : 1 = 1)))
  assertEq "proof: type is the Prop" prf.type? (some "1 = 1")

/-! ## Deep expressions vs maxDepth -/

/-- Build the `k`-fold application `Nat.succ (Nat.succ (... Nat.zero))`. -/
private def succChain : Nat → Expr
  | 0 => mkConst ``Nat.zero
  | k + 1 => mkApp (mkConst ``Nat.succ) (succChain k)

#eval show TermElabM Unit from do
  -- a 100-deep chain analyzed with the default maxDepth 32 terminates
  -- and marks the cut branch as elided
  let n ← analyzeExpr (succChain 100)
  assertTrue "deep: has an elided node" (n.any (·.elided))
  -- depth of the produced tree never exceeds maxDepth
  assertTrue "deep: tree depth bounded" (n.depth ≤ 32)
  -- with a bigger budget the same expression is fully analyzed
  let full ← analyzeExpr (succChain 100) { maxDepth := 200 }
  assertFalse "deep: no elision with big budget" (full.any (·.elided))
  assertEq "deep: full depth" full.depth 100

#eval show TermElabM Unit from do
  -- maxDepth is honored exactly: nodes AT the limit are cut, not beyond
  let n ← analyzeExpr (succChain 10) { maxDepth := 3 }
  assertEq "exact depth: tree depth" n.depth 3
  let cut ← nodeAt "exact depth: node at limit" n [1, 1, 1]
  assertTrue "exact depth: cut node elided" cut.elided
  assertEq "exact depth: cut node has no children" cut.children.size 0
  -- intermediate nodes are not elided
  assertFalse "exact depth: shallower node intact"
    ((← nodeAt "ed" n [1, 1]).elided)

#eval show TermElabM Unit from do
  -- deep diff terminates and finds the single leaf difference
  let a := succChain 50
  let b := succChain 51
  let ms ← diffExprs a b
  assertTrue "deep diff: found" !ms.isEmpty
  -- the deepest mismatch path has length 50 (all arg steps)
  assertTrue "deep diff: deep path collected"
    (ms.any fun m => m.path.length == 50)
  -- ancestor entries are pruned: one difference, one site (the arg-level
  -- entry plus its leaf-level structural refinement at the same path)
  assertEq "deep diff: localized to the leaf" ms.size 2

/-! ## Diff depth guard (mirrors the analyzer's `maxDepth`) -/

/-- Iteratively-built `Nat.succ` chain: safe to *construct* at any depth
(no recursion), so only the diff itself is exercised. -/
private def succChainIter (n : Nat) (leaf : Expr) : Expr :=
  (List.range n).foldl (fun e _ => mkApp (mkConst ``Nat.succ) e) leaf

#eval show TermElabM Unit from do
  -- REGRESSION (bughunt2): diffing ~600-deep expressions used to die
  -- with an *uncatchable* "maximum recursion depth" error (the analyzer
  -- was depth-guarded, the diff was not). Descent now stops at
  -- `diffExprs`' maxDepth (default 128) with a pinned graceful entry.
  let a := succChainIter 600 (Lean.mkConst ``Nat.zero)
  let b := succChainIter 600 (mkApp (Lean.mkConst ``Nat.succ) (Lean.mkConst ``Nat.zero))
  let ms ← diffExprs a b
  assertEq "depth guard: two entries (arg + depth-limit)" ms.size 2
  let some dm := ms.toList.find? (·.site == "subterm at the diff depth limit")
    | throwError "ASSERT FAILED [depth guard]: no depth-limit entry"
  assertEq "depth guard: structural kind" dm.kind .structural
  assertEq "depth guard: nothing certified" dm.defeq .checkFailed
  assertEq "depth guard: cut at the default cap" dm.path.length 128
  assertContains "depth guard: pinned graceful message"
    dm.describe "subterm at the diff depth limit differs:"
  assertContains "depth guard: annotated as failed check"
    dm.describe "(defeq check failed)"

#eval show TermElabM Unit from do
  -- the cap is configurable, mirroring the analyzer's XRayConfig.maxDepth
  let a := succChainIter 600 (Lean.mkConst ``Nat.zero)
  let b := succChainIter 600 (mkApp (Lean.mkConst ``Nat.succ) (Lean.mkConst ``Nat.zero))
  let ms ← diffExprs a b (maxDepth := 8)
  assertTrue "depth guard: custom cap honored"
    (ms.any fun m => m.site == "subterm at the diff depth limit" && m.path.length == 8)
  -- shallow diffs are unaffected by the guard
  let ms₂ ← diffExprs (succChain 50) (succChain 51)
  assertFalse "depth guard: absent below the cap"
    (ms₂.any fun m => m.site == "subterm at the diff depth limit")

/-! ## Analyzer robustness -/

#eval show TermElabM Unit from do
  -- a loose bvar (never produced by the analyzer's own recursion, but a
  -- caller might hand us one) does not crash: type is unknown
  let n ← analyzeExpr (.bvar 0)
  assertEq "bvar: kind" n.kind .bvar
  assertEq "bvar: no type" n.type? (none : Option String)

#eval show TermElabM Unit from do
  -- nested mdata wrappers each get their own marker node
  let inner ← elabT (← `((5 : Nat)))
  let e := Expr.mdata {} (Expr.mdata {} inner)
  let n ← analyzeExpr e
  assertEq "nested mdata: root" n.kind .mdata
  assertEq "nested mdata: child" ((← nodeAt "nm[0]" n [0]).kind) .mdata
  assertEq "nested mdata: grandchild" ((← nodeAt "nm[0,0]" n [0, 0]).kind) .app
  assertEq "nested mdata: mdata count" (n.count (·.isMData)) 2

#eval show TermElabM Unit from do
  -- lambda whose head is applied: roles default to explicit via FunInfo
  let n ← analyzeT (← `((fun (x : Nat) => x) 5))
  assertEq "beta: root kind" n.kind .app
  assertEq "beta: head kind" ((← nodeAt "beta[0]" n [0]).kind) .lam
  assertEq "beta: arg role" ((← nodeAt "beta[1]" n [1]).role) .explicit

end ExprXRayTests.EdgeTests
