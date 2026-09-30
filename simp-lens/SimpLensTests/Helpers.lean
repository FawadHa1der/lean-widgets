import SimpLens

/-!
# SimpLensTests.Helpers — test infrastructure

Compile-time assertion commands. Every command elaborates the goal, runs the
Simp Lens pipeline, and `throwError`s on any mismatch, so `lake build` of the
test lib is the test run. Each command checks *specific expected values*.
-/

namespace SimpLensTests

open Lean Meta Elab Command Term SimpLens

/-- Throw unless `cond`. -/
def assert (cond : Bool) (msg : MessageData) : MetaM Unit := do
  unless cond do throwError "assertion failed: {msg}"

/-- Throw unless `actual = expected`, printing both. -/
def assertEq [BEq α] [ToMessageData α] (what : String) (actual expected : α) : MetaM Unit := do
  unless actual == expected do
    throwError "assertion failed: {what}\n  actual:   {actual}\n  expected: {expected}"

/-- Result of one full traced run for the test commands. -/
structure RunResult where
  /-- The traced run. -/
  res : SimpLens.TraceResult
  /-- Its filmstrip. -/
  film : Film
  /-- The goal *before* simplification (binders already intro'd). -/
  goalBefore : MVarId
  /-- Context the run used. -/
  ctx : Simp.Context
  /-- Simprocs the run used. -/
  simprocs : Simp.SimprocsArray

/-- Display key for an origin: full name for globals, user-facing name for
local hypotheses. -/
def originDisplay (o : Meta.Origin) : MetaM String := do
  match o with
  | .decl n _ inv => return (if inv then "← " else "") ++ n.toString
  | .fvar id =>
    match (← getLCtx).find? id with
    | some d => return d.userName.toString
    | none => return "‹fvar›"
  | .stx _ ref => return toString ref.prettyPrint
  | .other n => return n.toString

/--
Elaborate `t` as a proposition, intro all leading binders, extend the default
simp set with `extra` global lemmas and `hyps` local hypotheses (by user
name), and run the traced simp on the resulting goal. Everything runs in the
goal's local context via the returned `RunResult.goalBefore`.
-/
def runLens (t : Term) (extra : Array Name := #[]) (hyps : Array Name := #[]) :
    TermElabM RunResult := do
  let type ← Term.elabType t
  Term.synthesizeSyntheticMVarsNoPostponing
  let type ← instantiateMVars type
  let mut mvar := (← mkFreshExprSyntheticOpaqueMVar type).mvarId!
  -- intro all leading binders, *preserving* user-facing names (so tests can
  -- refer to hypotheses and pinned goal strings stay readable)
  while (← instantiateMVars (← mvar.getType)).isForall do
    let (_, mvar') ← mvar.intro1P
    mvar := mvar'
  mvar.withContext do
    let mut thms ← getSimpTheorems
    for n in extra do
      thms ← thms.addConst n
    let mut thmsArr : SimpTheoremsArray := #[thms]
    let lctx ← getLCtx
    for h in hyps do
      let some ldecl := lctx.findFromUserName? h
        | throwError "runLens: no hypothesis named {h}"
      thmsArr ← thmsArr.addTheorem (.fvar ldecl.fvarId) ldecl.toExpr
    let ctx ← Simp.mkContext (config := {}) (simpTheorems := thmsArr)
      (congrTheorems := ← getSimpCongrTheorems)
    let simprocs : Simp.SimprocsArray := #[← Simp.getSimprocs]
    let res ← traceSimpTarget mvar ctx simprocs
    return { res, film := Film.ofTrace res, goalBefore := mvar, ctx, simprocs }

/-- Optional `with [lemma, ...]` clause: extra global simp lemmas. -/
syntax lensWith := " with " "[" ident,* "]"
/-- Optional `hyps [h, ...]` clause: local hypotheses added as simp lemmas. -/
syntax lensHyps := " hyps " "[" ident,* "]"

/-- Parse the optional clauses of a test command. -/
def parseClauses (ex : Option (TSyntax ``lensWith)) (hy : Option (TSyntax ``lensHyps)) :
    CommandElabM (Array Name × Array Name) := do
  let extra ← match ex with
    | some stx =>
      match stx with
      | `(lensWith| with [$ids,*]) => ids.getElems.mapM fun i =>
          liftCoreM <| realizeGlobalConstNoOverload i
      | _ => throwUnsupportedSyntax
    | none => pure #[]
  let hyps := match hy with
    | some stx =>
      match stx with
      | `(lensHyps| hyps [$ids,*]) => ids.getElems.map (·.getId)
      | _ => #[]
    | none => #[]
  return (extra, hyps)

/-- Run `k` on the traced result of `t` (with optional extra lemmas/hyps),
inside the goal's local context. -/
def withRun (t : Term) (ex : Option (TSyntax ``lensWith)) (hy : Option (TSyntax ``lensHyps))
    (k : RunResult → MetaM Unit) : CommandElabM Unit := do
  let (extra, hyps) ← parseClauses ex hy
  liftTermElabM do
    let r ← runLens t extra hyps
    r.goalBefore.withContext do k r

/-- Resolve an expected-name ident: full global name if it resolves, else the
raw identifier (for local hypothesis names). -/
def expectedName (i : Ident) : MetaM String := do
  match (← observing? (realizeGlobalConstNoOverload i) : Option Name) with
  | some n => pure n.toString
  | none => pure i.getId.toString

/-- Pretty-print the type of a possibly-assigned goal. -/
def goalString (m : MVarId) : MetaM String :=
  m.withContext do return toString (← ppExpr (← instantiateMVars (← m.getType)))

/-- Landing description of an optional goal: goal text or `"<closed>"`. -/
def landing (g? : Option MVarId) : MetaM String := do
  match g? with
  | none => pure "<closed>"
  | some m => goalString m

/--
`#lens_used t => [n1, n2, ...]` — assert that the traced run's used-theorem
set (in firing order) is *exactly* the given list (globals by full name,
hypotheses by user name).
-/
elab "#lens_used " t:term ex:(lensWith)? hy:(lensHyps)? " => " "[" expected:ident,* "]" : command => do
  withRun t ex hy fun r => do
    let actual ← r.res.usedTheorems.toArray.mapM originDisplay
    let expected ← expected.getElems.mapM expectedName
    assertEq "used-theorem list" actual.toList expected.toList

/-- `#lens_steps t => n` — assert the filmstrip has exactly `n` frames
(depth-0 rewrite steps). -/
elab "#lens_steps " t:term ex:(lensWith)? hy:(lensHyps)? " => " n:num : command => do
  withRun t ex hy fun r => do
    assertEq "filmstrip length" r.film.length n.getNat

/-- `#lens_principal t at i => name` — assert frame `i`'s principal origin. -/
elab "#lens_principal " t:term ex:(lensWith)? hy:(lensHyps)? " at " i:num " => "
    principal:ident : command => do
  withRun t ex hy fun r => do
    let i := i.getNat
    let some fr := r.film.frames[i]?
      | throwError "no frame {i} (filmstrip has {r.film.length} frames)"
    assertEq s!"frame {i} principal" (← originDisplay fr.step.principal) (← expectedName principal)

/--
`#lens_step t at i => name, "before" ~> "after"` — assert frame `i`'s
principal origin *and* the exact pretty-printed subterm before/after.
-/
elab "#lens_step " t:term ex:(lensWith)? hy:(lensHyps)? " at " i:num " => "
    principal:ident ", " before:str " ~> " after:str : command => do
  withRun t ex hy fun r => do
    let i := i.getNat
    let some fr := r.film.frames[i]?
      | throwError "no frame {i} (filmstrip has {r.film.length} frames)"
    assertEq s!"frame {i} principal" (← originDisplay fr.step.principal) (← expectedName principal)
    assertEq s!"frame {i} before" (toString (← ppExpr fr.step.before)) before.getString
    assertEq s!"frame {i} after" (toString (← ppExpr fr.step.after)) after.getString

/-- `#lens_lands t => "goal"` — assert the traced run leaves exactly this goal
open (use `#lens_closes` for closed goals). -/
elab "#lens_lands " t:term ex:(lensWith)? hy:(lensHyps)? " => " g:str : command => do
  withRun t ex hy fun r => do
    assertEq "landing goal" (← landing r.res.goal?) g.getString

/-- `#lens_closes t` — assert the traced run closes the goal. -/
elab "#lens_closes " t:term ex:(lensWith)? hy:(lensHyps)? : command => do
  withRun t ex hy fun r => do
    assert r.res.goal?.isNone m!"expected closed goal, landed at: {← landing r.res.goal?}"

/-- `#lens_min t => "simp only [...]"` — assert the generated minimal call
pretty-prints exactly as given. -/
elab "#lens_min " t:term ex:(lensWith)? hy:(lensHyps)? " => " s:str : command => do
  withRun t ex hy fun r => do
    assertEq "minimal simp only call" (← minimalSimpOnlyString r.res.usedTheorems) s.getString

/-- `#lens_chain t` — assert all chain-consistency invariants of the traced
filmstrip (pure + type-level). -/
elab "#lens_chain " t:term ex:(lensWith)? hy:(lensHyps)? : command => do
  withRun t ex hy fun r => do
    let vs := r.film.chainViolations
    assert vs.isEmpty m!"chain violations: {vs}"
    let tvs ← r.film.typeViolations
    assert tvs.isEmpty m!"type violations: {tvs}"

/--
`#lens_equiv t` — the core value guarantee, asserted three ways:
1. the traced run lands exactly where plain (untraced) `Meta.simpTarget` with
   the same context lands;
2. traced and plain runs report identical `usedTheorems` (in order);
3. the generated minimal `simp only [...]` call, executed by the real tactic
   elaborator, lands in the same place as plain `simp`.
-/
elab "#lens_equiv " t:term ex:(lensWith)? hy:(lensHyps)? : command => do
  withRun t ex hy fun r => do
    let tracedGoal ← landing r.res.goal?
    -- 1. plain `Meta.simpTarget` with the same context (untraced)
    let plainGoalMVar := (← mkFreshExprSyntheticOpaqueMVar (← r.goalBefore.getType)).mvarId!
    let (plain?, plainStats) ← simpTarget plainGoalMVar r.ctx r.simprocs
    let plainGoal ← landing plain?
    assertEq "traced vs plain simp landing goal" tracedGoal plainGoal
    -- 2. identical used-theorem lists
    let tracedUsed ← r.res.usedTheorems.toArray.mapM originDisplay
    let plainUsed ← plainStats.usedTheorems.toArray.mapM originDisplay
    assertEq "traced vs plain usedTheorems" tracedUsed.toList plainUsed.toList
    -- 3. run the generated minimal call as a real tactic
    let minStx ← minimalSimpOnly (← `(tactic| simp)) r.res.usedTheorems
    let minGoalMVar := (← mkFreshExprSyntheticOpaqueMVar (← r.goalBefore.getType)).mvarId!
    let minGoal ←
      try
        let (remaining, _) ← Elab.runTactic minGoalMVar minStx
        match remaining with
        | [] => pure "<closed>"
        | [m] => goalString m
        | gs => throwError "minimal call left {gs.length} goals"
      catch e =>
        -- "`simp` made no progress" is valid *parity* behavior: the plain run
        -- must then have been a no-op as well (checked below).
        if (← e.toMessageData.toString).startsWith "`simp` made no progress" then
          goalString r.goalBefore
        else
          throw e
    assertEq "minimal simp only vs plain simp landing goal" minGoal plainGoal

/-- Shared implementation of the `#lens_exclude*` commands. -/
def checkExclusion (r : RunResult) (l : Ident)
    (k : ExclusionOutcome → String → MetaM Unit) : MetaM Unit := do
  let lname ← expectedName l
  let mut found := none
  for o in r.res.usedTheorems.toArray do
    if (← originDisplay o) == lname then
      found := some o
  let some origin := found
    | throwError "lemma {lname} was not used by the run; used: {← r.res.usedTheorems.toArray.mapM originDisplay}"
  let fullLanding ← match r.res.goal? with
    | none => pure none
    | some m => pure (some (← goalString m))
  let oc ← runExclusion r.goalBefore r.ctx r.simprocs none origin fullLanding
  assert (!oc.errored) m!"exclusion re-run errored"
  k oc lname

/-- `#lens_exclude t without L => "goal"` — assert the landing goal when `L`
is erased from the simp set. -/
elab "#lens_exclude " t:term ex:(lensWith)? hy:(lensHyps)? " without " l:ident " => " g:str : command => do
  withRun t ex hy fun r =>
    checkExclusion r l fun oc lname => do
      assertEq s!"landing goal without {lname}" (oc.landingGoal?.getD "<closed>") g.getString

/-- `#lens_exclude_closes t without L` — assert the goal still closes when `L`
is erased. -/
elab "#lens_exclude_closes " t:term ex:(lensWith)? hy:(lensHyps)? " without " l:ident : command => do
  withRun t ex hy fun r =>
    checkExclusion r l fun oc lname => do
      assert oc.landingGoal?.isNone
        m!"expected closed without {lname}, landed at: {oc.landingGoal?.getD ""}"

/-- `#lens_essential t without L => true/false` — assert whether erasing `L`
changes the landing goal. -/
elab "#lens_essential " t:term ex:(lensWith)? hy:(lensHyps)? " without " l:ident " => "
    b:(&"true" <|> &"false") : command => do
  withRun t ex hy fun r =>
    checkExclusion r l fun oc lname => do
      let expected := b.raw.getKind == `token.true
      assertEq s!"essentiality of {lname}" oc.essential expected

/-- Find the used origin displayed as `l` in a run, or throw. -/
def findUsedOrigin (r : RunResult) (l : Ident) : MetaM Meta.Origin := do
  let lname ← expectedName l
  let mut found := none
  for o in r.res.usedTheorems.toArray do
    if (← originDisplay o) == lname then
      found := some o
  let some origin := found
    | throwError "lemma {lname} was not used by the run; used: {← r.res.usedTheorems.toArray.mapM originDisplay}"
  return origin

/--
`#lens_exclude_status t without L budget n => ok/errored/timedOut` — run the
exclusion re-run with `L` erased under an explicit heartbeat sub-budget of `n`
raw heartbeats and assert the *contained* outcome status. The command itself
must never fail: this pins the fix for the escaped-timeout bug (runtime
exceptions used to sail through the preview's `catch _` and hard-fail the
tactic).
-/
elab "#lens_exclude_status " t:term ex:(lensWith)? hy:(lensHyps)? " without " l:ident
    " budget " n:num " => " s:(&"ok" <|> &"errored" <|> &"timedOut") : command => do
  withRun t ex hy fun r => do
    let origin ← findUsedOrigin r l
    let fullLanding ← match r.res.goal? with
      | none => pure none
      | some m => pure (some (← goalString m))
    let oc ← runExclusion r.goalBefore r.ctx r.simprocs none origin fullLanding
      (budget? := some n.getNat)
    -- the alternatives wrap each keyword in a `token.<kw>` node (getAtomVal
    -- would be empty), so discriminate by kind — same as `#lens_essential`
    let expected : PreviewStatus :=
      if s.raw.getKind == `token.errored then .errored
      else if s.raw.getKind == `token.timedOut then .timedOut
      else if s.raw.getKind == `token.ok then .ok
      else panic! s!"#lens_exclude_status: unexpected status syntax kind {s.raw.getKind}"
    assert (oc.status == expected)
      m!"status of exclusion without {← expectedName l}: {repr oc.status} ≠ {repr expected}"
    -- a non-ok preview must be flagged errored and essential (unknown landing)
    unless expected == .ok do
      assert oc.errored m!"non-ok preview not flagged errored"
      assert oc.essential m!"non-ok preview not flagged essential"
      assert oc.landingGoal?.isNone m!"non-ok preview reported a landing goal"

/-- `#lens_phases t => ["post", "pre", ...]` — assert the exact phase labels
of the filmstrip frames, in order. -/
elab "#lens_phases " t:term ex:(lensWith)? hy:(lensHyps)? " => " "[" expected:str,* "]" : command => do
  withRun t ex hy fun r => do
    let actual := r.film.frames.map (·.step.phase.label)
    assertEq "frame phases" actual.toList (expected.getElems.map (·.getString)).toList

/-- `#lens_depths t => [0, 1, ...]` — assert the exact discharge depths of
*all* traced steps (not just depth-0 frames), in firing order. -/
elab "#lens_depths " t:term ex:(lensWith)? hy:(lensHyps)? " => " "[" expected:num,* "]" : command => do
  withRun t ex hy fun r => do
    let actual := r.res.steps.map (·.depth)
    assertEq "step depths" actual.toList (expected.getElems.map (·.getNat)).toList

/--
`#lens_diag t => L used u tried t` — assert the diagnostics counters recorded
for lemma `L` (requires `set_option diagnostics true in`; a *used* count > 1
distinguishes per-firing counters from the deduplicated `usedTheorems`).
`tried` is asserted as a lower bound (`≥`), since tried counts depend on
discrimination-tree candidate sets.
-/
elab "#lens_diag " t:term ex:(lensWith)? hy:(lensHyps)? " => " l:ident
    " used " u:num " tried " tr:num : command => do
  withRun t ex hy fun r => do
    let lname ← expectedName l
    let mut usedCount := 0
    let mut triedCount := 0
    for (o, c) in r.res.diag.usedThmCounter.toList do
      if (← originDisplay o) == lname then usedCount := c
    for (o, c) in r.res.diag.triedThmCounter.toList do
      if (← originDisplay o) == lname then triedCount := c
    assertEq s!"diagnostics used-count of {lname}" usedCount u.getNat
    assert (triedCount >= tr.getNat)
      m!"diagnostics tried-count of {lname}: {triedCount} < {tr.getNat}"

/-- `#lens_diag_empty t` — assert that no diagnostics counters are recorded
(the `diagnostics` option is off). -/
elab "#lens_diag_empty " t:term ex:(lensWith)? hy:(lensHyps)? : command => do
  withRun t ex hy fun r => do
    assert r.res.diag.usedThmCounter.toList.isEmpty m!"expected empty used counters"
    assert r.res.diag.triedThmCounter.toList.isEmpty m!"expected empty tried counters"

/-- `#lens_classify t => ["label1", ...]` — assert the `OriginClass.label` of
every used origin, in order. -/
elab "#lens_classify " t:term ex:(lensWith)? hy:(lensHyps)? " => " "[" expected:str,* "]" : command => do
  withRun t ex hy fun r => do
    let actual ← r.res.usedTheorems.toArray.mapM fun o =>
      return (← classifyOrigin o).label
    assertEq "origin classes" actual.toList (expected.getElems.map (·.getString)).toList

/-! ## Location-aware commands (`simp_lens ... at ...` engine) -/

/-- One location item of a `lensAt` clause: a hypothesis name or `⊢`. -/
syntax lensAtItem := ident <|> "⊢"
/-- Optional location clause of the `#lens_at_*` commands: `at h₁ h₂ ⊢` or
`at *` (mirroring real `simp ... at ...` syntax). Absent means target-only. -/
syntax lensAt := " at " ("*" <|> lensAtItem+)

/-- Parsed `lensAt` clause: hypothesis names in order, whether the target is
included, and whether the clause was the `*` wildcard. -/
structure LensAtSpec where
  /-- Hypothesis names, in the order written. -/
  atHyps : Array Name := #[]
  /-- Whether `⊢` was included (always true for absent clause / wildcard). -/
  atTarget : Bool := true
  /-- Whether the clause was `at *`. -/
  wildcard : Bool := false

/-- The `" at ..."` suffix of the spec as source text (empty for target-only),
used to build genuine `simp` syntax via the parser. -/
def LensAtSpec.suffix (s : LensAtSpec) : String :=
  if s.wildcard then " at *"
  else if s.atHyps.isEmpty && s.atTarget then ""
  else
    let items := s.atHyps.map (·.toString) ++ (if s.atTarget then #["⊢"] else #[])
    " at " ++ " ".intercalate items.toList

/-- Parse an optional `lensAt` clause. -/
def parseLensAt (la : Option (TSyntax ``lensAt)) : CommandElabM LensAtSpec := do
  let some stx := la | return {}
  let arg := stx.raw[1]
  if arg.getKind == nullKind then
    -- a non-empty sequence of `lensAtItem`s
    let mut atHyps := #[]
    let mut atTarget := false
    for item in arg.getArgs do
      if item[0].isIdent then
        atHyps := atHyps.push item[0].getId
      else
        atTarget := true
    return { atHyps, atTarget }
  else
    -- the `*` token
    return { wildcard := true }

/-- Result of one traced multi-location run for the test commands. -/
structure RunAtResult where
  /-- The traced run. -/
  res : SimpLens.GoalTraceResult
  /-- The goal *before* simplification (binders already intro'd). -/
  goalBefore : MVarId
  /-- Context the run used. -/
  ctx : Simp.Context
  /-- Simprocs the run used. -/
  simprocs : Simp.SimprocsArray
  /-- Whether the target was simplified. -/
  simplifyTarget : Bool
  /-- The hypotheses that were simplified, in processing order. -/
  fvarIdsToSimp : Array FVarId
  /-- The `" at ..."` source suffix of the location clause. -/
  locSuffix : String

/-- Location-aware sibling of `runLens`: elaborate `t`, intro binders, build
the same simp context, resolve the location spec (named hypotheses by user
name; wildcard via `getNondepPropHyps`, like core), and run the traced
`simpGoal` mirror on the resulting goal. -/
def runLensAt (t : Term) (extra : Array Name := #[]) (hypLemmas : Array Name := #[])
    (spec : LensAtSpec := {}) : TermElabM RunAtResult := do
  let type ← Term.elabType t
  Term.synthesizeSyntheticMVarsNoPostponing
  let type ← instantiateMVars type
  let mut mvar := (← mkFreshExprSyntheticOpaqueMVar type).mvarId!
  while (← instantiateMVars (← mvar.getType)).isForall do
    let (_, mvar') ← mvar.intro1P
    mvar := mvar'
  mvar.withContext do
    let mut thms ← getSimpTheorems
    for n in extra do
      thms ← thms.addConst n
    let mut thmsArr : SimpTheoremsArray := #[thms]
    let lctx ← getLCtx
    for h in hypLemmas do
      let some ldecl := lctx.findFromUserName? h
        | throwError "runLensAt: no hypothesis named {h}"
      thmsArr ← thmsArr.addTheorem (.fvar ldecl.fvarId) ldecl.toExpr
    let ctx ← Simp.mkContext (config := {}) (simpTheorems := thmsArr)
      (congrTheorems := ← getSimpCongrTheorems)
    let simprocs : Simp.SimprocsArray := #[← Simp.getSimprocs]
    let (fvarIdsToSimp, simplifyTarget) ←
      if spec.wildcard then
        pure (← mvar.getNondepPropHyps, true)
      else do
        let ids ← spec.atHyps.mapM fun h => do
          let some ldecl := lctx.findFromUserName? h
            | throwError "runLensAt: no hypothesis named {h}"
          pure ldecl.fvarId
        pure (ids, spec.atTarget)
    let res ← traceSimpGoal mvar ctx simprocs none simplifyTarget fvarIdsToSimp
    return { res, goalBefore := mvar, ctx, simprocs, simplifyTarget, fvarIdsToSimp,
             locSuffix := spec.suffix }

/-- Run `k` on the traced multi-location result of `t`, inside the goal's
local context. -/
def withRunAt (t : Term) (ex : Option (TSyntax ``lensWith)) (hy : Option (TSyntax ``lensHyps))
    (la : Option (TSyntax ``lensAt)) (k : RunAtResult → MetaM Unit) : CommandElabM Unit := do
  let (extra, hypLemmas) ← parseClauses ex hy
  let spec ← parseLensAt la
  liftTermElabM do
    let r ← runLensAt t extra hypLemmas spec
    r.goalBefore.withContext do k r

/-- Parse a tactic-category string into syntax (used to build genuine
`simp ... at ...` calls for the minimizer and equivalence replay). -/
def parseTacticString (s : String) : CoreM Syntax := do
  match Parser.runParserCategory (← getEnv) `tactic s with
  | .ok stx => return stx
  | .error err => throwError "parse error in {s}: {err}"

/-- The minimal `simp only [...] (at ...)` call of a multi-location run, as a
string (location clause preserved verbatim, like `simp?`). -/
def minimalSimpOnlyStringAt (r : RunAtResult) : MetaM String := do
  let call ← parseTacticString ("simp" ++ r.locSuffix)
  ppTacticCall (← minimalSimpOnly call r.res.usedTheorems)

/-- Full landing state of an optional goal: `Meta.ppGoal` text (hypotheses and
target) or `"<closed>"`. -/
def landingState (g? : Option MVarId) : MetaM String := do
  match g? with
  | none => pure "<closed>"
  | some m => m.withContext do return toString (← Meta.ppGoal m)

/-- `#lens_at_used t at ... => [n1, ...]` — assert the union used-theorem set
over all locations (in first-use order). -/
elab "#lens_at_used " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? " => "
    "[" expected:ident,* "]" : command => do
  withRunAt t ex hy la fun r => do
    let actual ← r.res.usedTheorems.toArray.mapM originDisplay
    let expected ← expected.getElems.mapM expectedName
    assertEq "used-theorem list" actual.toList expected.toList

/-- `#lens_at_locs t at ... => ["h", "⊢", ...]` — assert the location labels
of the processed locations, in processing order. -/
elab "#lens_at_locs " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? " => "
    "[" expected:str,* "]" : command => do
  withRunAt t ex hy la fun r => do
    let actual := r.res.locs.map (·.loc.label)
    assertEq "location labels" actual.toList (expected.getElems.map (·.getString)).toList

/-- `#lens_at_steps t at ... => [n1, n2, ...]` — assert the per-location
filmstrip lengths (depth-0 frames), in processing order. -/
elab "#lens_at_steps " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? " => "
    "[" expected:num,* "]" : command => do
  withRunAt t ex hy la fun r => do
    let actual := r.res.films.map (·.film.length)
    assertEq "per-location filmstrip lengths" actual.toList
      (expected.getElems.map (·.getNat)).toList

/-- `#lens_at_step t at ... frame i of loc => name, "before" ~> "after"` —
assert frame `i` of the given location's film: principal origin and exact
pretty-printed subterm before/after. -/
elab "#lens_at_step " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)?
    " frame " i:num " of " l:lensAtItem " => "
    principal:ident ", " before:str " ~> " after:str : command => do
  withRunAt t ex hy la fun r => do
    let want : LocTag := if l.raw[0].isIdent then .hyp l.raw[0].getId else .target
    let some lf := r.res.films.find? (·.loc == want)
      | throwError "no film for location {want.label}; locations: {r.res.locs.map (·.loc.label)}"
    let i := i.getNat
    let some fr := lf.film.frames[i]?
      | throwError "no frame {i} of location {want.label} (film has {lf.film.length} frames)"
    assertEq s!"frame {i} of {want.label} principal"
      (← originDisplay fr.step.principal) (← expectedName principal)
    assertEq s!"frame {i} of {want.label} before" (toString (← ppExpr fr.step.before)) before.getString
    assertEq s!"frame {i} of {want.label} after" (toString (← ppExpr fr.step.after)) after.getString
    assertEq s!"frame {i} of {want.label} loc tag" fr.step.loc.label want.label

/-- `#lens_at_lands t at ... => "goal"` — assert the run leaves exactly this
target open. -/
elab "#lens_at_lands " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? " => " g:str : command => do
  withRunAt t ex hy la fun r => do
    assertEq "landing target" (← landing r.res.goal?) g.getString

/-- `#lens_at_hyp t at ... => h : "type"` — assert hypothesis `h`'s exact
pretty-printed type in the resulting goal. -/
elab "#lens_at_hyp " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? " => "
    h:ident " : " ty:str : command => do
  withRunAt t ex hy la fun r => do
    let some m := r.res.goal?
      | throwError "goal was closed; no hypothesis {h.getId} to inspect"
    m.withContext do
      let some ldecl := (← getLCtx).findFromUserName? h.getId
        | throwError "no hypothesis named {h.getId} in the resulting goal"
      assertEq s!"landing type of {h.getId}"
        (toString (← ppExpr (← instantiateMVars ldecl.type))) ty.getString

/-- `#lens_at_closes t at ...` — assert the run closes the goal. -/
elab "#lens_at_closes " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? : command => do
  withRunAt t ex hy la fun r => do
    assert r.res.goal?.isNone m!"expected closed goal, landed at: {← landingState r.res.goal?}"

/-- `#lens_at_defonly t at ... => ["h", "⊢", ...]` — assert exactly which
locations changed by *definitional reductions only* (location changed, but no
lemma-driven rewrite recorded — beta/zeta/eta/proj steps have no origin). -/
elab "#lens_at_defonly " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? " => "
    "[" expected:str,* "]" : command => do
  withRunAt t ex hy la fun r => do
    let actual := (r.res.films.filter (·.definitionalOnly)).map (·.loc.label)
    assertEq "definitional-only locations" actual.toList
      (expected.getElems.map (·.getString)).toList

/-- `#lens_at_progress t at ... => true/false` — assert whether any location
made progress (the `failIfUnchanged` test of core `simpGoal`). -/
elab "#lens_at_progress " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? " => "
    b:(&"true" <|> &"false") : command => do
  withRunAt t ex hy la fun r => do
    let expected := b.raw.getKind == `token.true
    assertEq "progress" r.res.progress expected

/-- `#lens_at_min t at ... => "simp only [...] at ..."` — assert the generated
minimal call (location clause included) pretty-prints exactly as given. -/
elab "#lens_at_min " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? " => " s:str : command => do
  withRunAt t ex hy la fun r => do
    assertEq "minimal simp only call" (← minimalSimpOnlyStringAt r) s.getString

/-- `#lens_at_chain t at ...` — assert the chain-consistency invariants (pure
and type-level) of every location's film. -/
elab "#lens_at_chain " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? : command => do
  withRunAt t ex hy la fun r => do
    for lf in r.res.films do
      let vs := lf.film.chainViolations
      assert vs.isEmpty m!"chain violations at {lf.loc.label}: {vs}"
      let tvs ← lf.film.typeViolations
      assert tvs.isEmpty m!"type violations at {lf.loc.label}: {tvs}"

/--
`#lens_at_equiv t at ...` — THE location equivalence guarantee, asserted three
ways:
1. the traced multi-location run lands exactly where plain (untraced)
   `Meta.simpGoal` with the same context, hypotheses and target flag lands —
   compared on the *full* goal state (`Meta.ppGoal`: every hypothesis and the
   target), or on both having closed the goal;
2. traced and plain runs report identical `usedTheorems` (in order), and
   identical no-progress behavior (the traced run reports no progress iff
   plain `simp` throws its no-progress error);
3. the generated minimal `simp only [...] at ...` call, executed by the real
   tactic elaborator, reaches the same full goal state as plain `simp`.
-/
elab "#lens_at_equiv " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? : command => do
  withRunAt t ex hy la fun r => do
    let tracedState ← landingState r.res.goal?
    -- 1./2. plain `Meta.simpGoal` with the same context (untraced)
    let plainMVar := (← mkFreshExprSyntheticOpaqueMVar (← r.goalBefore.getType)).mvarId!
    let plainOutcome ←
      try
        let (res?, stats) ← simpGoal plainMVar r.ctx r.simprocs none
          (simplifyTarget := r.simplifyTarget) (fvarIdsToSimp := r.fvarIdsToSimp)
        pure (some (res?.map (·.2), stats))
      catch e =>
        if (← e.toMessageData.toString).startsWith "`simp` made no progress" then
          pure none
        else
          throw e
    let plainState ← match plainOutcome with
      | none =>
        -- plain simp made no progress: the traced run must agree, and must
        -- have landed on an unchanged goal
        assert (!r.res.progress) m!"traced run claims progress but plain simp made none"
        let unchanged ← landingState (some r.goalBefore)
        assertEq "traced vs unchanged goal state" tracedState unchanged
        pure unchanged
      | some (plainGoal?, plainStats) =>
        assert r.res.progress m!"plain simp made progress but traced run claims none"
        let plainState ← landingState plainGoal?
        assertEq "traced vs plain simp goal state" tracedState plainState
        let tracedUsed ← r.res.usedTheorems.toArray.mapM originDisplay
        let plainUsed ← plainStats.usedTheorems.toArray.mapM originDisplay
        assertEq "traced vs plain usedTheorems" tracedUsed.toList plainUsed.toList
        pure plainState
    -- 3. run the generated minimal call as a real tactic at the same locations
    let call ← parseTacticString ("simp" ++ r.locSuffix)
    let minStx ← minimalSimpOnly call r.res.usedTheorems
    let minMVar := (← mkFreshExprSyntheticOpaqueMVar (← r.goalBefore.getType)).mvarId!
    let minState ←
      try
        let (remaining, _) ← Elab.runTactic minMVar minStx
        match remaining with
        | [] => pure "<closed>"
        | [m] => landingState (some m)
        | gs => throwError "minimal call left {gs.length} goals"
      catch e =>
        if (← e.toMessageData.toString).startsWith "`simp` made no progress" then
          landingState (some r.goalBefore)
        else
          throw e
    assertEq "minimal simp only vs plain simp goal state" minState plainState

/-- Shared implementation of the `#lens_at_exclude*` commands: find `origin`
by display name, re-run at the same locations with it erased, and hand the
outcome (plus the watched-location computation) to `k`. -/
def checkExclusionAt (r : RunAtResult) (l : Ident)
    (k : ExclusionOutcome → String → MetaM Unit) : MetaM Unit := do
  let lname ← expectedName l
  let mut found := none
  for o in r.res.usedTheorems.toArray do
    if (← originDisplay o) == lname then
      found := some o
  let some origin := found
    | throwError "lemma {lname} was not used by the run; used: {← r.res.usedTheorems.toArray.mapM originDisplay}"
  let watch? := watchOf r.res r.simplifyTarget
  let fullLanding ← landingAt r.res.goal? watch?
  let oc ← runExclusionAt r.goalBefore r.ctx r.simprocs none origin fullLanding
    r.simplifyTarget r.fvarIdsToSimp watch?
  assert (!oc.errored) m!"exclusion re-run errored"
  k oc lname

/-- `#lens_at_exclude t at ... without L => "landing"` — assert the landing
state of the watched location (target if included, else the first changed
hypothesis) when `L` is erased from the simp set. -/
elab "#lens_at_exclude " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)?
    " without " l:ident " => " g:str : command => do
  withRunAt t ex hy la fun r =>
    checkExclusionAt r l fun oc lname => do
      assertEq s!"landing without {lname}" (oc.landingGoal?.getD "<closed>") g.getString

/-- `#lens_at_essential t at ... without L => true/false` — assert whether
erasing `L` changes the watched landing state. -/
elab "#lens_at_essential " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)?
    " without " l:ident " => " b:(&"true" <|> &"false") : command => do
  withRunAt t ex hy la fun r =>
    checkExclusionAt r l fun oc lname => do
      let expected := b.raw.getKind == `token.true
      assertEq s!"essentiality of {lname}" oc.essential expected

/-! ## React style-contract checker (permanent)

The InfoView passes `ProofWidgets.Html` element attributes straight through
as React props. React requires the `style` prop to be a JSON *object* with
camelCased property names — a raw CSS string (e.g. `"font-family:monospace"`)
crashes the entire panel at runtime with minified React error #62, and
compile-time tests never run React, so the only way to catch a regression in
the suite is to walk the produced `Html`. The checker lives in the test
helper (not the lib) because it is test infrastructure: the lib's rendering
contract is *checked* by it, not implemented with it. -/

/-- Does any text node in `h` contain `needle`? (Structural completeness
checks on rendered panels.) -/
partial def htmlContainsText (needle : String) : ProofWidgets.Html → Bool
  | .text s => (s.splitOn needle).length > 1
  | .element _ _ cs => cs.any (htmlContainsText needle)
  | .component _ _ _ cs => cs.any (htmlContainsText needle)

/-- Walk an `Html` tree and return one path-labeled entry for every element
whose `"style"` attribute value is NOT a `Json.obj` (the React error #62
shape), plus every attribute literally named `"class"` (React requires
`className`). An empty result means the tree satisfies the React contract.
Recurses into both element and component children. -/
partial def reactContractViolations (h : ProofWidgets.Html) : List String :=
  go "" h
where
  /-- Worker carrying the `path/tag[idx]` label of the current node. -/
  go (path : String) : ProofWidgets.Html → List String
    | .text _ => []
    | .element tag attrs children =>
      let here := s!"{path}/{tag}"
      let attrIssues := attrs.toList.filterMap fun (k, v) =>
        if k == "style" then
          match v with
          | .obj _ => Option.none
          | _ => some s!"{here}: style attribute is not a JSON object \
                   (React error #62): {v.compress}"
        else if k == "class" then
          some s!"{here}: attribute \"class\" — React requires \"className\""
        else Option.none
      let childIssues :=
        (children.mapIdx fun i c => go s!"{here}[{i}]" c).foldl (· ++ ·) []
      attrIssues ++ childIssues
    | .component _ exp _ children =>
      (children.mapIdx fun i c => go s!"{path}/component:{exp}[{i}]" c).foldl (· ++ ·) []

/--
`#lens_react_contract t` — build the REAL top-level filmstrip panel `Html`
for a target-only traced run (the same `renderPanel` output `simp_lens` saves
as its widget: header, minimal call, frames, exclusion previews,
diagnostics), plus the degraded `renderPanelFallback` panel, and assert that
neither violates the React style contract (`reactContractViolations = []`).
-/
elab "#lens_react_contract " t:term ex:(lensWith)? hy:(lensHyps)? : command => do
  withRun t ex hy fun r => do
    let suggestion ← minimalSimpOnlyString r.res.usedTheorems
    let report ← excludeEach r.goalBefore r.ctx r.simprocs none r.res
    let html ← renderPanel r.film suggestion report r.res.diag r.res.goal?.isNone
    let vs := reactContractViolations html
    assert vs.isEmpty m!"React contract violations in filmstrip panel: {vs}"
    let fb ← renderPanelFallback r.film.length suggestion report r.res.diag r.res.goal?.isNone
    let fvs := reactContractViolations fb
    assert fvs.isEmpty m!"React contract violations in fallback panel: {fvs}"

/--
`#lens_at_react_contract t at ...` — build the REAL top-level multi-location
panel `Html` (the same `renderPanelAt` output the located tactic saves,
including per-location sections and location-aware exclusion previews) and
assert it violates no React style contract.
-/
elab "#lens_at_react_contract " t:term ex:(lensWith)? hy:(lensHyps)? la:(lensAt)? : command => do
  withRunAt t ex hy la fun r => do
    let suggestion ← minimalSimpOnlyStringAt r
    let report ← excludeEachAt r.goalBefore r.ctx r.simprocs none r.res
      r.simplifyTarget r.fvarIdsToSimp
    let html ← renderPanelAt r.res.films suggestion report r.res.diag r.res.goal?.isNone
    let vs := reactContractViolations html
    assert vs.isEmpty m!"React contract violations in multi-location panel: {vs}"
    -- Completeness regression: a do-notation `return` in renderPanelAt used to
    -- exit the whole function for location runs, silently dropping the
    -- <details> wrapper, minimal-call row, exclusion previews and diagnostics
    -- (caught by browser-side React verification of the dumped output).
    assert (match html with | .element "details" _ _ => true | _ => false)
      m!"multi-location panel is not the full <details> panel"
    assert (htmlContainsText "minimal call: " html)
      m!"multi-location panel lost the minimal-call row"

end SimpLensTests
