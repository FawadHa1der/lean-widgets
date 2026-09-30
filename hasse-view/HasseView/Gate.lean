import HasseView.Extract
import HasseView.Links

/-! # HasseView: the analysis-time verification gate

The honesty gate behind every click-to-insert link (non-negotiable house
rule: *a suggestion that does not provably hold may never be offered*).  A
candidate example becomes a link only when, at `#hasse` elaboration time:

1. **every element label round-trips** (`labelRoundTrips`): the `Repr`-made
   label parses as a term (`Parser.runParserCategory`), elaborates at the
   poset type with no leftover metavariables or `sorry`, and — through the
   same `evalExpr` bridge the extractor uses — is `DecidableEq`-equal to the
   *enumerated element it labels*.  A label that parses to a different value
   than the drawn element would produce a compiling-but-wrong example; this
   check makes that impossible.
2. **the full statement verifies** (`statementHolds`): the exact proposition
   text that would be inserted parses, elaborates at `Prop`, has a
   synthesizable *computable* `Decidable` instance, and that instance
   evaluates to `true`.

Failures of either check are silent (the candidate renders as plain text
with a note); all evaluation runs inside `withoutModifyingState`, so the
gate never leaks messages, metavariables or environment changes into the
command — interrupt/runtime exceptions still propagate, matching
`HasseView/Extract.lean`.

The residual (documented) gap: verification evaluates *compiled* code while
the inserted `by decide` reduces in the kernel.  For lawful instances these
agree; a pathological instance could make an inserted example fail to
*compile* — visibly — but never make it state a falsehood.
-/

namespace HasseView

open Lean Meta Elab

/-- Is the runtime value `v` equal (via `DecidableEq`) to element `i` of the
`Fintype` enumeration?  Only ever run through `evalExpr (safety := .unsafe)`
— the same bridge as `HasseView.Extract.rawLeRows`. -/
unsafe def rawEqAt (V : Type u) [Fintype V] [DecidableEq V] (v : V) (i : Nat) :
    Bool :=
  match (enumElems V)[i]? with
  | some w => decide (v = w)
  | none => false

/-- Run `act`, restoring all elaboration state afterwards and turning any
non-interrupt failure into `false`.  Interrupt/runtime exceptions propagate
(same policy as `evalOrExplain`). -/
def gateCheck (act : Term.TermElabM Bool) : Term.TermElabM Bool :=
  withoutModifyingState do
    try
      Term.withoutErrToSorry act
    catch ex =>
      if ex.isInterrupt || ex.isRuntime then
        throw ex
      return false

/-- Parse `s` as a term and elaborate it at expected type `ty`, requiring a
fully-determined result (no metavariables, no `sorry`).  `none` on any
failure. -/
def elabString? (s : String) (ty : Expr) : Term.TermElabM (Option Expr) := do
  match Parser.runParserCategory (← getEnv) `term s with
  | .error _ => return none
  | .ok stx =>
    let e ← Term.elabTerm stx (some ty)
    Term.synthesizeSyntheticMVarsNoPostponing
    let e ← instantiateMVars e
    if e.hasExprMVar || e.hasSorry then
      return none
    return some e

/-- Gate check 1: does `label` parse, elaborate at `V`, and evaluate equal to
element `idx` of the enumeration?  `finInst`/`deqInst` are the already
synthesized `Fintype V` / `DecidableEq V` instances. -/
def labelRoundTrips (V finInst deqInst : Expr) (label : String) (idx : Nat) :
    Term.TermElabM Bool :=
  gateCheck do
    let some v ← elabString? label V | return false
    let e ← mkAppOptM ``rawEqAt #[V, finInst, deqInst, v, mkNatLit idx]
    unsafe evalExpr Bool (mkConst ``Bool) e (safety := .unsafe)

/-- Gate check 2: does the proposition text elaborate at `Prop` with a
computable `Decidable` instance that evaluates to `true`?  This runs on the
*exact* text a click would insert (minus the `example`/`by decide`
wrapper), so what is verified is what is offered. -/
def statementHolds (prop : String) : Term.TermElabM Bool :=
  gateCheck do
    let some p ← elabString? prop (mkSort .zero) | return false
    let inst ← synthInstance (← mkAppM ``Decidable #[p])
    if inst.getUsedConstants.any (isNoncomputable (← getEnv) ·) then
      return false
    let e ← mkAppOptM ``Decidable.decide #[p, inst]
    unsafe evalExpr Bool (mkConst ``Bool) e (safety := .unsafe)

/-! ## Link building -/

/-- Build one candidate: verified link if every referenced label round-trips
and the statement holds, plain text with the appropriate note otherwise.
`labelOk i` must be the (memoized) round-trip verdict for element `i`. -/
def buildCandidate (display prop : String) (labelIdxs : Array Nat)
    (labelOk : Nat → Bool) : Term.TermElabM InsertableFact := do
  if !labelIdxs.all labelOk then
    return { display, note? := some notInsertableLabelNote }
  if ← statementHolds prop then
    return { display, newText? := some (insertionText prop) }
  return { display, note? := some notVerifiedNote }

/-- Build all insertable-example candidates for the extracted poset `d` of
the elaborated type `V`, whose original source syntax is `tyStr` (used
verbatim in every statement).  Round-trip verdicts are computed once per
element; cover links are skipped (with an honest note) beyond
`maxLinkedCovers` edges. -/
def buildLinks (V : Expr) (tyStr : String) (d : PosetData) :
    Term.TermElabM PanelLinks := do
  -- The same instances extraction synthesized (cheap: instance cache).
  let finInst ← synthOrExplain (← mkAppM ``Fintype #[V])
  let deqInst ← synthOrExplain (← mkAppM ``DecidableEq #[V])
  -- Memoized per-element round-trip verdicts (only for referenced indices).
  let mut cache : Array (Option Bool) := .replicate d.n none
  let mut needed : Array Nat := #[]
  let covers := d.coverPairs
  let linkCovers := coversLinkable d
  if linkCovers then
    for (a, b) in covers do
      needed := needed ++ #[a, b]
  if let some b := d.bot? then needed := needed.push b
  if let some t := d.top? then needed := needed.push t
  let verdict := d.latticeVerdict
  match verdict with
  | .noJoin a b | .noMeet a b => needed := needed ++ #[a, b]
  | .lattice => pure ()
  for i in needed do
    if i < d.n && (cache[i]!).isNone then
      let ok ← labelRoundTrips V finInst deqInst (d.label i) i
      cache := cache.set! i (some ok)
  let labelOk := fun i => (cache[i]?.bind id).getD false
  -- Cover-edge candidates (parallel to `coverPairs`).
  let mut coverFacts : Array InsertableFact := #[]
  for (a, b) in covers do
    let display := s!"{d.label a} ⋖ {d.label b}"
    if linkCovers then
      coverFacts := coverFacts.push
        (← buildCandidate display (coverProp tyStr (d.label a) (d.label b))
          #[a, b] labelOk)
    else
      coverFacts := coverFacts.push { display, note? := some tooManyCoversNote }
  -- ⊥/⊤ badge candidates.
  let bot? ← d.bot?.mapM fun b =>
    buildCandidate s!"∀ x, {d.label b} ≤ x" (botProp tyStr (d.label b)) #[b] labelOk
  let top? ← d.top?.mapM fun t =>
    buildCandidate s!"∀ x, x ≤ {d.label t}" (topProp tyStr (d.label t)) #[t] labelOk
  -- Non-lattice witness candidate.
  let witness? ← match verdict with
    | .lattice => pure none
    | .noJoin a b =>
      some <$> buildCandidate s!"no join of {d.label a}, {d.label b}"
        (noJoinProp tyStr (d.label a) (d.label b)) #[a, b] labelOk
    | .noMeet a b =>
      some <$> buildCandidate s!"no meet of {d.label a}, {d.label b}"
        (noMeetProp tyStr (d.label a) (d.label b)) #[a, b] labelOk
  return { covers := coverFacts, bot?, top?, witness? }

end HasseView
