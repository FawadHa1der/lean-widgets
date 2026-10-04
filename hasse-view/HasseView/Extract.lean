import HasseView.Model
import Mathlib.Data.Fintype.Basic
import Mathlib.Data.Fintype.Card
import Mathlib.Data.Quot

/-! # HasseView: extraction of `PosetData` from a type

The single impure layer of the package.  Given an elaborated term `V` that
denotes a *type* carrying `[Fintype V]`, `[DecidableEq V]`, `[LE V]` and a
decidable order, `extractPosetData`:

1. rejects non-types and underdetermined terms (metavariables) with a
   `#hasse`-branded error instead of leaking internal exceptions;
2. synthesizes the four instances, naming the missing one in a clear error —
   and rejects *noncomputable* synthesized instances (e.g. the classical
   fallback `Classical.propDecidable` that `open scoped Classical` puts in
   scope) with an equally clear error, instead of letting `evalExpr` fail
   later with raw compiler advice.  On decidability of the order: in
   v4.34.0 `DecidableLE V` is a *reducible abbreviation* for
   `DecidableRel (· ≤ · : V → V → Prop)`, so one synthesis query covers both
   spellings (instance search unfolds the abbreviation; per-pair instances
   like core's `Decidable (x ≤ y)` for `Bool` are found by introducing the
   binders of the `DecidableRel` pi type);
3. evaluates `Fintype.card V` and enforces the honest hard cap of
   `maxElements = 64` elements *before* deciding any `≤`;
4. self-checks the `Fintype` enumeration for duplicates (via `DecidableEq V`)
   — a malformed instance would silently corrupt every index, so it is
   reported as an extraction bug instead;
5. compiles `rawLeRows V` **once** (via the standard `Lean.Meta.evalExpr`
   pattern, `safety := .unsafe`, exactly as Mathlib commands do) into a
   `Nat → Array Bool` closure, then calls it row by row from `MetaM`, running
   `Lean.Core.checkSystem` between rows — so a slow decidability instance can
   be interrupted between rows (editor cancellation, heartbeats) instead of
   hanging the whole command in one opaque evaluation;
6. labels elements via `Repr V` when available (`reprStr` of each element in
   enumeration order), falling back to plain indices (also when the `Repr`
   instance is noncomputable).

Element indices are positions in the `Fintype.elems` enumeration, so
extraction is deterministic by construction: the same type and instances
always produce the same `PosetData` (for `Fin n`, element `i` is literally
`i`).

The extracted table is *not* assumed to be a partial order: the model's
validity checkers run downstream and the renderer reports violations as
warnings (see `HasseView.Model`).  A single `≤` decision is arbitrary user
code and cannot be bounded from here; see the README's limitations section.
-/

namespace HasseView

open Lean Meta Elab

/-- The elements of `V` in `Fintype` enumeration order.  Unsafe because it
reveals the runtime representative of the `elems` multiset — which is exactly
the deterministic "enumeration order" the widget indexes elements by.  Only
ever run through `evalExpr (safety := .unsafe)`. -/
unsafe def enumElems (V : Type u) [Fintype V] : Array V :=
  ((Fintype.elems (α := V)).val.unquot).toArray

/-- The `≤` table, one row at a time: `rawLeRows V i` is the array
`#[decide (vᵢ ≤ v₀), …, decide (vᵢ ≤ vₙ₋₁)]` over the enumeration.  The
enumeration is computed once, when the closure is created; the caller
(`extractPosetData`) evaluates this closure once with `evalExpr` and then
calls it per row from `MetaM`, checking for interrupts between rows.
Evaluated (never type-checked as safe code) at elaboration time. -/
unsafe def rawLeRows (V : Type u) [Fintype V] [LE V] [DecidableLE V] :
    Nat → Array Bool :=
  let vs := enumElems V
  fun i =>
    if h : i < vs.size then
      let v := vs[i]
      vs.map fun w => decide (v ≤ w)
    else #[]

/-- The number of *distinct* elements in the enumeration (self-check: must
equal `Fintype.card V`; a duplicate would silently corrupt every index). -/
unsafe def rawDistinctCount (V : Type u) [Fintype V] [DecidableEq V] : Nat :=
  (enumElems V).toList.eraseDups.length

/-- Element labels in enumeration order, via `Repr`. -/
unsafe def rawLabels (V : Type u) [Fintype V] [Repr V] : Array String :=
  (enumElems V).map fun v => reprStr v

/-- Hard cap on the number of elements HasseView will evaluate and draw
(`n²` order decisions and an `n³` transitivity check live downstream). -/
def maxElements : Nat := 64

/-- Pretty-print an expression to a single line (deterministic error text). -/
def ppOneLine (e : Expr) : MetaM String := do
  return (← ppExpr e).pretty (width := 100000)

/-- Synthesize an instance of `type`, or fail with a `#hasse` error naming
exactly the missing instance.  Also rejects noncomputable synthesized
instances (the value mentions a constant tagged `noncomputable`, e.g. the
classical fallback `Classical.propDecidable` under `open scoped Classical`):
those would otherwise surface much later as a raw compiler error from
`evalExpr` whose advice ("mark it as noncomputable") is meaningless for a
command. -/
def synthOrExplain (type : Expr) : MetaM Expr := do
  match ← synthInstance? type with
  | none => throwError "#hasse: cannot synthesize `{← ppOneLine type}` — \
      #hasse needs [Fintype V], [DecidableEq V], [LE V] and a decidable order \
      (DecidableLE V, equivalently DecidableRel (· ≤ ·)) to evaluate the poset"
  | some inst =>
    let inst ← instantiateMVars inst
    let env ← getEnv
    if let some c := inst.getUsedConstants.find? (isNoncomputable env ·) then
      throwError "#hasse: the instance synthesized for `{← ppOneLine type}` \
          is noncomputable (it uses `{c}`) — #hasse evaluates the order with \
          compiled code, so it needs computable instances; define one by hand \
          (`decidable_of_iff` is the idiomatic fix, see HasseView/Demo.lean)"
    return inst

/-- Run one evaluation step, rebranding any failure as a `#hasse` error
(interrupts and runtime errors pass through untouched). -/
def evalOrExplain (what : String) (act : MetaM α) : MetaM α := do
  try
    act
  catch ex =>
    if ex.isInterrupt || ex.isRuntime then
      throw ex
    throwError "#hasse: failed to {what} — {ex.toMessageData}"

/-- Extract a `PosetData` from an elaborated term `V` denoting a finite,
decidably ordered type (see the module docstring for the contract and error
behavior). -/
def extractPosetData (V : Expr) : MetaM PosetData := do
  let V ← instantiateMVars V
  if V.hasExprMVar then
    throwError "#hasse: the type still contains metavariables (`_`) — fill \
        in the underscores so the poset is fully determined"
  let Vty ← whnf (← inferType V)
  match Vty with
  | .sort u =>
    if u.isZero then
      throwError "#hasse: `{← ppOneLine V}` is a proposition, not a type — \
          #hasse draws the order of a finite *type* V"
  | _ =>
    throwError "#hasse: expected a type, but `{← ppOneLine V}` has type \
        `{← ppOneLine Vty}` — #hasse draws the order of a finite type V, \
        e.g. `#hasse (Fin 4)`"
  -- Instances, with a precise error for the missing (or noncomputable) one.
  let finInst ← synthOrExplain (← mkAppM ``Fintype #[V])
  let deqInst ← synthOrExplain (← mkAppM ``DecidableEq #[V])
  let leInst ← synthOrExplain (← mkAppM ``LE #[V])
  let dleInst ← synthOrExplain (← mkAppOptM ``DecidableLE #[V, leInst])
  -- Element-count cap, checked before any `≤` is decided.
  let cardE ← mkAppOptM ``Fintype.card #[V, finInst]
  let n ← evalOrExplain "evaluate the element count" <|
    unsafe evalExpr' Nat ``Nat cardE
  if n > maxElements then
    throwError "#hasse: the poset has {n} elements, more than the limit of \
        {maxElements} — #hasse refuses to draw it"
  -- Enumeration self-check: duplicates would corrupt every index downstream.
  let distinctE ← mkAppOptM ``rawDistinctCount #[V, finInst, deqInst]
  let distinct ← evalOrExplain "check the element enumeration" <|
    unsafe evalExpr Nat (mkConst ``Nat) distinctE (safety := .unsafe)
  if distinct != n then
    throwError "#hasse: extraction bug — the Fintype enumeration of \
        `{← ppOneLine V}` has {distinct} distinct elements but \
        `Fintype.card` is {n}; the Fintype instance is malformed"
  -- The `≤` table: compile the row closure once, then decide row by row with
  -- an interrupt check between rows (the order's own Decidable instances
  -- decide each entry).
  let natT := mkConst ``Nat
  let rowTy ← mkArrow natT (mkApp (mkConst ``Array [.zero]) (mkConst ``Bool))
  let rowFnE ← mkAppOptM ``rawLeRows #[V, finInst, leInst, dleInst]
  let rowFn ← evalOrExplain "compile the order's decidability test" <|
    unsafe evalExpr (Nat → Array Bool) rowTy rowFnE (safety := .unsafe)
  let mut table : Array (Array Bool) := #[]
  for i in [0:n] do
    Core.checkSystem "#hasse"
    let row := rowFn i
    if row.size != n then
      throwError "#hasse: extraction bug — row {i} of the ≤ table has \
          {row.size} entries for {n} elements"
    table := table.push row
  -- Labels via `Repr V` when available (and computable); indices otherwise.
  let labels ← do
    match ← synthInstance? (← mkAppM ``Repr #[V]) with
    | some reprInst =>
      let reprInst ← instantiateMVars reprInst
      if reprInst.getUsedConstants.any (isNoncomputable (← getEnv) ·) then
        pure #[]
      else
        let labE ← mkAppOptM ``rawLabels #[V, finInst, reprInst]
        let labTy := mkApp (mkConst ``Array [.zero]) (mkConst ``String)
        evalOrExplain "evaluate the element labels" <|
          unsafe evalExpr (Array String) labTy labE (safety := .unsafe)
    | none => pure #[]
  return PosetData.ofTable n table labels

end HasseView
