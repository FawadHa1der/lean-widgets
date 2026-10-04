import IntervalInspector.Model
import IntervalInspector.OrderGraph
import Mathlib.Order.Interval.Set.Defs
import Mathlib.Order.Lattice
import Mathlib.Order.Max
import Mathlib.Algebra.Field.Defs
import Mathlib.Lean.Expr.Rat

/-! # Interval Inspector: recognition

`Expr`-level matchers turning goals / hypotheses / terms into the pure model of
`IntervalInspector/Model.lean`.

Supported: the eight `Set.Ixx` constructors over any preorder, `Set.univ`, `∅` and
`{a}` (as sets), set-builder interval spellings (`{x | a ≤ x ∧ x < b}` and the other
one- and two-sided `≤`/`<` combinations, conjuncts in either order — recognized
syntactically and marked with a `fromSetBuilder` provenance flag), interval
*expressions* built with `∪` / `∩`, and the statement shapes `x ∈ s`, `s ⊆ t`,
`s ⊂ t`, `s = t`, `Set.Nonempty s`, `s ≠ ∅` / `¬(s = ∅)` / `∅ ≠ s` / `¬(∅ = s)`,
plus bare interval terms.

Atoms are keyed by *expression identity* (structural equality after `consumeMData`),
not merely by their pretty-printed strings: recognition runs in `RecognizeM`, a small
state monad carrying an `Expr ↦ display key` table.  Two distinct expressions that
print identically (e.g. shadowed binders both displayed `a` after hygiene-marker
stripping) get *distinct* keys, disambiguated with `′` marks (`a`, `a′`), so order
facts about one never apply to the other.

Recognition also computes, per statement, which order-typeclass instances
(`LinearOrder`, `DenselyOrdered`, `NoMinOrder`, `NoMaxOrder`, …) are available for
the recognized element type (`InstAvail`), so the suggestion engine and renderer can
gate instance-dependent claims.

Deliberately **not** supported (recognition returns `none`): `Finset.Icc` and friends
(a number line of a `Finset` would suggest a continuum that is not there),
`Set.range`, set-builder bodies that are not `≤`/`<` bounds on the binder
(disjunctions, `≥`/`>` spellings, triple conjunctions, …), and memberships in
non-`Set` collections.  Matching is syntactic: we do not unfold definitions.
-/

namespace IntervalInspector

open Lean Meta

/-- If `ty` is syntactically `Set α`, return `α`. -/
def setElemType? (ty : Expr) : Option Expr :=
  if ty.isAppOfArity ``Set 1 then some ty.appArg! else none

/-- Pretty-print an expression and strip hygiene markers (`✝` daggers and the
superscript indices that follow them), so that binder-bound atoms print as the
user wrote them (`a`, not `a✝`).  Distinct expressions can collide after stripping;
`atomKey` disambiguates such collisions with `′` marks. -/
def ppClean (e : Expr) : MetaM String := do
  let s := toString (← ppExpr e)
  return String.ofList <| s.toList.filter fun c =>
    !['✝', '⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'].contains c

/-- Atom-key state: each distinct atom expression seen so far, with its unique
display key. -/
structure AtomKeys where
  /-- `(expression, key)` pairs, in first-seen order.  Keys are unique. -/
  entries : Array (Expr × String) := #[]

/-- Recognition monad: `MetaM` plus the atom-key table, shared across one whole
statement (shape endpoints *and* harvested ordering facts), so identical
expressions get identical keys and distinct expressions get distinct keys. -/
abbrev RecognizeM := StateRefT AtomKeys MetaM

/-- Run a recognition computation with a fresh atom-key table. -/
def RecognizeM.run' (x : RecognizeM α) : MetaM α := StateRefT'.run' x {}

/-- Unique display key of an atom expression: its `ppClean` form, with `′` marks
appended while the string is already taken by a *different* expression.  Expressions
are compared structurally (after `consumeMData`), so the same variable or literal
always maps to the same key, while distinct shadowed variables that print alike get
`a` / `a′`. -/
def atomKey (e : Expr) : RecognizeM String := do
  let e := e.consumeMData
  let st ← get
  for (e', k) in st.entries do
    if e' == e then return k
  let used := st.entries.map (·.2)
  let mut k ← ppClean e
  for _ in [0:used.size] do
    if used.contains k then k := k ++ "′"
  modify fun st => { st with entries := st.entries.push (e, k) }
  return k

/-- Does `ty` have an instance of the (single-parameter) class `cls`?  The class
application is built by telescoping `cls`'s type: the first explicit argument is
assigned `ty` and every instance-implicit argument (e.g. `DenselyOrdered`'s `[LT α]`)
is synthesized explicitly — `mkAppM` would leave such *trailing* instance arguments
unapplied, making `synthInstance?` fail even for `DenselyOrdered ℝ`.  Any failure
counts as "no". -/
def hasInstance (cls : Name) (ty : Expr) : MetaM Bool := do
  try
    let c ← mkConstWithFreshMVarLevels cls
    let (mvars, binderInfos, _) ← forallMetaTelescope (← inferType c)
    let mut tyAssigned := false
    for m in mvars, bi in binderInfos do
      if !tyAssigned && bi == .default then
        unless ← isDefEq m ty do return false
        tyAssigned := true
      else if bi == .instImplicit then
        let some inst ← Meta.synthInstance? (← instantiateMVars (← inferType m))
          | return false
        unless ← isDefEq m inst do return false
    unless tyAssigned do return false
    let clsE ← instantiateMVars (mkAppN c mvars)
    return (← Meta.synthInstance? clsE).isSome
  catch _ => return false

/-- Which order-typeclass instances are available for element type `ty`.  Must be
called while `ty`'s binders (if any) are still in scope. -/
def instAvailFor (ty : Expr) : MetaM InstAvail := do
  return {
    partialOrder := ← hasInstance ``PartialOrder ty
    linearOrder := ← hasInstance ``LinearOrder ty
    lattice := ← hasInstance ``Lattice ty
    denselyOrdered := ← hasInstance ``DenselyOrdered ty
    noMinOrder := ← hasInstance ``NoMinOrder ty
    noMaxOrder := ← hasInstance ``NoMaxOrder ty }

/-- Extract the rational value of a numeric literal expression.  Handles natural,
integer and rational normal forms via `Lean.Expr.rat?`, plus elaborated surface
syntax: `Neg.neg` negations and — **only when `divOk` is set** — `HDiv.hDiv` /
`Div.div` divisions (e.g. `(1/2 : ℝ)`), applied recursively.  Callers set `divOk`
iff the literal's type is a `DivisionRing`: over `ℕ`/`ℤ`, `1/2` is *truncating*
division (`(1/2 : ℕ) = 0`), so assigning it the rational value `1/2` would fabricate
false ordering facts; such literals stay symbolic (`none`). -/
partial def litVal? (divOk : Bool) (e : Expr) : Option Rat :=
  let e := e.consumeMData
  if e.isAppOfArity ``HDiv.hDiv 6 then do
    guard divOk
    let n ← litVal? divOk (e.getArg! 4)
    let d ← litVal? divOk (e.getArg! 5)
    guard (d ≠ 0)
    pure (n / d)
  else if e.isAppOfArity ``Neg.neg 3 then do
    let n ← litVal? divOk (e.getArg! 2)
    pure (-n)
  else if e.isAppOfArity ``Div.div 4 && !divOk then
    -- `Expr.rat?` would evaluate a `Div.div` of literals as rational division.
    none
  else
    e.rat?

/-- Is `e`'s type a `DivisionRing` (so that division literals have field semantics)? -/
def divisionOk (e : Expr) : MetaM Bool := do
  hasInstance ``DivisionRing (← inferType e)

/-- Build an `Endpoint` from an expression: key it (uniquely, see `atomKey`) and
extract a literal rational value when the expression is a numeric literal in normal
form over a type with field-like division. -/
def mkEndpoint (e : Expr) : RecognizeM Endpoint := do
  return { pp := ← atomKey e, val? := litVal? (← divisionOk e) e }

/-- Try to read a proposition as a bound on the set-builder binder `x`:
`a ≤ x` / `a < x` (lower bound — the binder is the *right* operand) or
`x ≤ b` / `x < b` (upper bound), where the bound side does not mention `x`.
Returns `(isLower, isClosed, bound)`; `none` for anything else (including `≥`/`>`
spellings and comparisons not touching `x`). -/
def setBuilderBound? (x : Expr) (cmp : Expr) : Option (Bool × Bool × Expr) := do
  let cmp := cmp.consumeMData
  let closed ←
    if cmp.isAppOfArity ``LE.le 4 then some true
    else if cmp.isAppOfArity ``LT.lt 4 then some false
    else none
  let lhs := cmp.getArg! 2
  let rhs := cmp.getArg! 3
  let some fv := x.fvarId? | none
  if lhs == x && rhs != x && !rhs.containsFVar fv then
    return (false, closed, rhs)  -- `x ≤ b`: upper bound
  else if rhs == x && lhs != x && !lhs.containsFVar fv then
    return (true, closed, lhs)   -- `a ≤ x`: lower bound
  else none

/-- Is `e` a set-builder application `{x | …}`?  Since Mathlib 2026-07-09 the
notation elaborates to `Set.ofPred fun x => …`; `setOf` survives only as a deprecated
alias (a distinct constant), so terms built from older sources are matched too. -/
def isSetBuilderApp (e : Expr) : Bool :=
  e.isAppOfArity ``Set.ofPred 2 || e.isAppOfArity `setOf 2

/-- Recognize a set-builder interval spelling `{x | …}` (elaborated as
`Set.ofPred fun x => …`): the eight one- and two-sided `≤`/`<` bound combinations, with
two-sided conjuncts accepted in either order.  The resulting leaf is marked
`fromSetBuilder`.  Anything else — disjunctions, bodies not comparing the binder,
triple conjunctions, bounds mentioning the binder — returns `none`. -/
def recognizeSetBuilder? (e : Expr) : RecognizeM (Option Leaf) := do
  unless isSetBuilderApp e do return none
  let pred := (e.getArg! 1).consumeMData
  unless pred.isLambda do return none
  lambdaTelescope pred fun xs body => do
    let #[x] := xs | return none
    let body := body.consumeMData
    if body.isAppOfArity ``And 2 then
      let some b₁ := setBuilderBound? x (body.getArg! 0) | return none
      let some b₂ := setBuilderBound? x (body.getArg! 1) | return none
      -- Exactly one lower and one upper bound, in either conjunct order.
      let some ((cl, lo), (cr, hi)) :=
        (match b₁, b₂ with
          | (true, cl, lo), (false, cr, hi) => some ((cl, lo), (cr, hi))
          | (false, cr, hi), (true, cl, lo) => some ((cl, lo), (cr, hi))
          | _, _ => none) | return none
      let kind : IntervalKind :=
        match cl, cr with
        | true, true => .Icc | true, false => .Ico
        | false, true => .Ioc | false, false => .Ioo
      return some { kind, lo? := some (← mkEndpoint lo), hi? := some (← mkEndpoint hi)
                    fromSetBuilder := true }
    else if let some (isLower, closed, bound) := setBuilderBound? x body then
      let b ← mkEndpoint bound
      if isLower then
        return some { kind := if closed then .Ici else .Ioi, lo? := some b
                      fromSetBuilder := true }
      else
        return some { kind := if closed then .Iic else .Iio, hi? := some b
                      fromSetBuilder := true }
    else
      return none

/-- Recognize a single interval-set constructor application.  Returns `none` for
anything that is not syntactically one of the supported constructors. -/
def recognizeLeaf? (e : Expr) : RecognizeM (Option Leaf) := do
  let e := e.consumeMData
  let mk2 (k : IntervalKind) : RecognizeM (Option Leaf) := do
    let lo ← mkEndpoint (e.getArg! 2)
    let hi ← mkEndpoint (e.getArg! 3)
    return some { kind := k, lo? := some lo, hi? := some hi }
  if e.isAppOfArity ``Set.Icc 4 then mk2 .Icc
  else if e.isAppOfArity ``Set.Ico 4 then mk2 .Ico
  else if e.isAppOfArity ``Set.Ioc 4 then mk2 .Ioc
  else if e.isAppOfArity ``Set.Ioo 4 then mk2 .Ioo
  else if e.isAppOfArity ``Set.Ici 3 then
    return some { kind := .Ici, lo? := some (← mkEndpoint (e.getArg! 2)) }
  else if e.isAppOfArity ``Set.Ioi 3 then
    return some { kind := .Ioi, lo? := some (← mkEndpoint (e.getArg! 2)) }
  else if e.isAppOfArity ``Set.Iic 3 then
    return some { kind := .Iic, hi? := some (← mkEndpoint (e.getArg! 2)) }
  else if e.isAppOfArity ``Set.Iio 3 then
    return some { kind := .Iio, hi? := some (← mkEndpoint (e.getArg! 2)) }
  else if e.isAppOfArity ``Set.univ 1 then
    return some { kind := .univ }
  else if e.isAppOfArity ``EmptyCollection.emptyCollection 2 then
    -- Only the empty *set*.
    if (setElemType? (e.getArg! 0)).isSome then
      return some { kind := .empty }
    else return none
  else if e.isAppOfArity ``Singleton.singleton 4 then
    -- Singleton.singleton : α → γ; only γ = Set α.
    if (setElemType? (e.getArg! 1)).isSome then
      let a ← mkEndpoint (e.getArg! 3)
      return some { kind := .singleton, lo? := some a, hi? := some a }
    else return none
  else if isSetBuilderApp e then
    recognizeSetBuilder? e
  else
    return none

/-- Recognize an interval expression: a supported leaf, or a `∪` / `∩` of interval
expressions (over `Set`).  `none` if any leaf is unrecognized. -/
partial def recognizeTree? (e : Expr) : RecognizeM (Option Tree) := do
  let e := e.consumeMData
  let binop (mk : Tree → Tree → Tree) : RecognizeM (Option Tree) := do
    if (setElemType? (e.getArg! 0)).isSome then
      let some a ← recognizeTree? (e.getArg! 2) | return none
      let some b ← recognizeTree? (e.getArg! 3) | return none
      return some (mk a b)
    else return none
  if e.isAppOfArity ``Union.union 4 then binop .union
  else if e.isAppOfArity ``Inter.inter 4 then binop .inter
  else
    return (← recognizeLeaf? e).map .leaf

/-- Is the tree the single `∅` leaf? -/
def Tree.isEmptyLeaf : Tree → Bool
  | .leaf l => l.kind == .empty
  | _ => false

/-- Recognize a statement shape: `x ∈ s`, `s ⊆ t`, `s ⊂ t`, `s = t`,
`Set.Nonempty s`, `s ≠ ∅` / `¬(s = ∅)` (and the mirror `∅ ≠ s` / `¬(∅ = s)`) over
interval expressions, or a bare interval term.  Also returns the *element type* of
the sets involved (for instance-availability checks).  Returns `none` for anything
else. -/
def recognizeShape? (e : Expr) : RecognizeM (Option (Shape × Expr)) := do
  let e := e.consumeMData
  -- `s ≠ ∅` / `∅ ≠ s` over interval expressions (shared by `Ne` and `¬(… = …)`).
  let neShape? (elemTy l r : Expr) : RecognizeM (Option (Shape × Expr)) := do
    let some lt ← recognizeTree? l | return none
    let some rt ← recognizeTree? r | return none
    if rt.isEmptyLeaf && !lt.isEmptyLeaf then return some (.neEmpty lt false, elemTy)
    else if lt.isEmptyLeaf && !rt.isEmptyLeaf then return some (.neEmpty rt true, elemTy)
    else return none
  if e.isAppOfArity ``Membership.mem 5 then
    -- Membership.mem : γ → α → Prop; args [α, γ, inst, s, x].
    if let some elemTy := setElemType? (e.getArg! 1) then
      let some t ← recognizeTree? (e.getArg! 3) | return none
      return some (.mem (← mkEndpoint (e.getArg! 4)) t, elemTy)
    else return none
  else if e.isAppOfArity ``HasSubset.Subset 4 || e.isAppOfArity ``LE.le 4 then
    -- Mathlib's `s ⊆ t` on sets elaborates to `LE.le` (the `Set` order); the
    -- `HasSubset.Subset` spelling also occurs.  Both are accepted, but only over
    -- `Set` — `LE.le` on plain values is an ordering fact, not a shape.
    if let some elemTy := setElemType? (e.getArg! 0) then
      let some l ← recognizeTree? (e.getArg! 2) | return none
      let some r ← recognizeTree? (e.getArg! 3) | return none
      return some (.subset l r, elemTy)
    else return none
  else if e.isAppOfArity ``HasSSubset.SSubset 4 || e.isAppOfArity ``LT.lt 4 then
    if let some elemTy := setElemType? (e.getArg! 0) then
      let some l ← recognizeTree? (e.getArg! 2) | return none
      let some r ← recognizeTree? (e.getArg! 3) | return none
      return some (.ssubset l r, elemTy)
    else return none
  else if e.isAppOfArity ``Eq 3 then
    if let some elemTy := setElemType? (e.getArg! 0) then
      let some l ← recognizeTree? (e.getArg! 1) | return none
      let some r ← recognizeTree? (e.getArg! 2) | return none
      return some (.eq l r, elemTy)
    else return none
  else if e.isAppOfArity ``Set.Nonempty 2 then
    let some t ← recognizeTree? (e.getArg! 1) | return none
    return some (.nonempty t, e.getArg! 0)
  else if e.isAppOfArity ``Ne 3 then
    -- Only disequalities with `∅` on one side over `Set` (a disequality of two
    -- non-empty intervals carries no emptiness content, and `≠` on scalars is a
    -- fact, not a shape).
    if let some elemTy := setElemType? (e.getArg! 0) then
      neShape? elemTy (e.getArg! 1) (e.getArg! 2)
    else return none
  else if e.isAppOfArity ``Not 1 then
    -- `¬(s = ∅)` / `¬(∅ = s)`, the unfolded spellings of `≠`.
    let inner := (e.getArg! 0).consumeMData
    if inner.isAppOfArity ``Eq 3 then
      if let some elemTy := setElemType? (inner.getArg! 0) then
        neShape? elemTy (inner.getArg! 1) (inner.getArg! 2)
      else return none
    else return none
  else
    match ← recognizeTree? e with
    | some t =>
      let some elemTy := setElemType? (← instantiateMVars (← inferType e)) | return none
      return some (.term t, elemTy)
    | none => return none

/-- Extract an ordering fact from a proposition, if it is a binary comparison.
`≥` and `>` are swapped into `≤` / `<`.  Comparisons and equalities *between sets*
are ignored (they are shapes, not endpoint facts).  Fact atoms are keyed through the
same `atomKey` table as shape endpoints, so a fact applies to a shape atom exactly
when it is about the *same expression*. -/
def factOfProp? (t : Expr) : RecognizeM (Option OrderFact) := do
  let t := t.consumeMData
  let mk (i j : Nat) (rel : OrderRel) : RecognizeM (Option OrderFact) := do
    let a := t.getArg! i
    let b := t.getArg! j
    let divOk ← divisionOk a
    return some { lhs := ← atomKey a, rhs := ← atomKey b, rel
                  lhsVal? := litVal? divOk a, rhsVal? := litVal? divOk b }
  let onSets := t.getAppNumArgs > 0 && (setElemType? (t.getArg! 0)).isSome
  if onSets then return none
  else if t.isAppOfArity ``LE.le 4 then mk 2 3 .le
  else if t.isAppOfArity ``LT.lt 4 then mk 2 3 .lt
  else if t.isAppOfArity ``GE.ge 4 then mk 3 2 .le
  else if t.isAppOfArity ``GT.gt 4 then mk 3 2 .lt
  else if t.isAppOfArity ``Eq 3 then mk 1 2 .eq
  else return none

/-- A fully recognized statement: shape, harvested ordering facts, and the
instance availability of the element type. -/
structure RecognizedStmt where
  /-- The recognized statement shape. -/
  shape : Shape
  /-- Ordering facts harvested from comparison binders (`∀ a b, a ≤ b → …`). -/
  facts : Array OrderFact
  /-- Which order typeclasses the element type actually has. -/
  inst : InstAvail

/-- Recognize a shape after peeling `fun` and `∀` binders, harvesting comparison
binder types (e.g. the `a ≤ b` in `∀ a b, a ≤ b → …`) as ordering facts, and
computing instance availability for the element type.  This lets
`#interval_inspect` work on statements with symbolic endpoints, e.g.
`∀ a b c : ℝ, a ≤ b → b ≤ c → Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c`.

The shape is recognized *before* the binder facts are harvested, so shape endpoints
claim their display keys first (colliding fact atoms get the `′` marks). -/
def recognizeWithBinders? (e : Expr) : RecognizeM (Option RecognizedStmt) := do
  lambdaTelescope e fun lvars ebody =>
    forallTelescope ebody fun fvars body => do
      let some (shape, elemTy) ← recognizeShape? body | return none
      let mut facts : Array OrderFact := #[]
      for fv in lvars ++ fvars do
        if let some f ← factOfProp? (← inferType fv) then
          facts := facts.push f
      return some { shape, facts, inst := ← instAvailFor elemTy }

/-- `recognizeWithBinders?` with a fresh atom-key table (entry point for callers that
do not also harvest local-context facts). -/
def recognizeWithBindersM? (e : Expr) : MetaM (Option RecognizedStmt) :=
  RecognizeM.run' (recognizeWithBinders? e)

/-- Collect ordering facts from the local context (hypotheses `a ≤ b`, `a < b`,
`a = b`, `a ≥ b`, `a > b`).  Must run in the same `RecognizeM` state as the shape
recognition so that hypothesis atoms and shape endpoints share keys. -/
def factsFromLCtx : RecognizeM (Array OrderFact) := do
  let mut out : Array OrderFact := #[]
  for decl in ← getLCtx do
    if decl.isImplementationDetail then continue
    if let some f ← factOfProp? decl.type then
      out := out.push f
  return out

/-- Atoms of a shape as `(name, literal value?)` pairs, ready for `OrderGraph.build`. -/
def Shape.atomsWithVals (s : Shape) : Array (String × Option Rat) :=
  s.atoms.map fun e => (e.pp, e.val?)

/-- Build the order graph for a shape from the given facts (plus automatic literal
comparisons).  Atoms mentioned only by facts (e.g. the `b` in `a ≤ b → b ≤ c → …`
when the shape's endpoints are `a` and `c`) are added as auxiliary nodes, so
transitive consequences flow *through* them; the graph is then restricted back to
the shape's own atoms for display. -/
def Shape.orderGraph (s : Shape) (facts : Array OrderFact) : OrderGraph :=
  let shapeAtoms := s.atomsWithVals
  let names := shapeAtoms.map (·.1)
  let aux : Array (String × Option Rat) := facts.foldl (init := #[]) fun acc f =>
    f.atomsWithVals.foldl (init := acc) fun acc (n, v) =>
      if names.contains n || acc.any (·.1 == n) then acc else acc.push (n, v)
  (OrderGraph.build (shapeAtoms ++ aux) facts).restrict names

end IntervalInspector
