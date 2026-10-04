import SimpLens.Trace
import SimpLens.Film
import SimpLens.Minimize
import SimpLens.Exclude
import SimpLens.Render

/-!
# SimpLens.Tactic — the `simp_lens` tactic

A drop-in wrapper around `simp` (with full `at` location support) that
1. performs the simplification *identically* to `simp` — the simp context is
   built by core's `mkSimpContext` from a real `simp` syntax tree rebuilt from
   the `simp_lens` arguments, locations are resolved exactly like core
   `simpLocation`, the run itself is the `simpGoal`-mirroring traced engine,
   and failure behavior (`\`simp\` made no progress`) is replicated exactly;
2. emits a `Try this: simp only [...] (at ...)` suggestion with the minimal
   used-lemma set (via core's `mkSimpOnly`, the same machinery as `simp?`,
   which preserves the location clause verbatim);
3. attaches the Simp Lens filmstrip panel widget at the tactic position, with
   one filmstrip section per location.

`simp_all` remains separate syntax and is not wrapped (documented in the
README); `simp_lens at *` has plain `simp at *` semantics, not `simp_all`'s.

## Cost containment

The traced run itself executes under the ambient heartbeat budget, exactly
like `simp` (if `simp` would time out, so does `simp_lens`, with the same
error). Everything simp_lens *adds* — exclusion previews, the suggestion, the
panel rendering — is heartbeat-neutral (`withHeartbeatsNeutral`): it cannot
trip the surrounding command's heartbeat check, so `simp_lens` succeeds
wherever `simp` does. Each exclusion preview additionally gets its own
sub-budget derived from the traced run's measured cost (`previewBudgetOf`);
a preview that exceeds it is shown as a "timed out" row, never an error.
Previews can be skipped entirely with `simp_lens -previews` (or
`(previews := false)`).
-/

namespace SimpLens

open Lean Elab Parser Tactic Meta Simp Tactic.TryThis
open ProofWidgets Server

/-- `simp_lens` accepts the same configuration, discharger, `only` flag,
lemma-list arguments and `at` locations as core `simp`, plus one extra config
flag of its own: `-previews` / `(previews := false)` skips the exclusion
previews (the filmstrip and `Try this:` suggestion are unaffected). -/
syntax (name := simpLensStx) "simp_lens" optConfig (discharger)?
  (&" only")? (" [" withoutPosition((simpStar <|> simpErase <|> simpLemma),*,?) "]")?
  (location)? : tactic

/--
Split the `simp_lens`-specific `previews` flag out of the config clause:
returns the config with any `previews` item removed (core's `Simp.Config` has
no such field, so it must not reach `mkSimpContext`) and the flag's value
(default `true`). Accepts `+previews` / `-previews` /
`(previews := true/false)` with a literal boolean value.
-/
def extractPreviewsFlag (cfg : TSyntax ``Lean.Parser.Tactic.optConfig) :
    TacticM (TSyntax ``Lean.Parser.Tactic.optConfig × Bool) := do
  let items := Lean.Parser.Tactic.getConfigItems cfg
  let views := Lean.Elab.Tactic.mkConfigItemViews items
  let mut keep : TSyntaxArray ``Lean.Parser.Tactic.configItem := #[]
  let mut previews := true
  for (item, view) in (items : Array _).zip views do
    if view.option.getId.eraseMacroScopes == `previews then
      let v := view.value.raw.getId.eraseMacroScopes
      if v == `true || v == `Bool.true then
        previews := true
      else if v == `false || v == `Bool.false then
        previews := false
      else
        throwErrorAt view.value "'previews' expects a literal 'true' or 'false'"
    else
      keep := keep.push item
  return (Lean.Parser.Tactic.mkOptConfig keep, previews)

/-- Attach the Simp Lens filmstrip panel at `stx`'s position. -/
def saveLensWidget (stx : Syntax) (html : Html) : CoreM Unit :=
  Widget.savePanelWidgetInfo (hash HtmlDisplayPanel.javascript)
    (return json% { html: $(← rpcEncode html) }) stx

/-- Resolve a parsed `Location` to the hypotheses to simplify and whether the
target is included, exactly like core `simpLocation`: named targets via
`getFVarIds`, wildcard via `getNondepPropHyps` (plus the target). -/
def resolveLocation (location : Location) : TacticM (Array FVarId × Bool) := do
  match location with
  | .targets hyps simplifyTarget =>
    withMainContext do
      return (← getFVarIds hyps, simplifyTarget)
  | .wildcard =>
    withMainContext do
      return (← (← getMainGoal).getNondepPropHyps, true)

/-- Elaborator for `simp_lens`: run the traced simp identically to `simp` (at
the same locations), emit the minimal `Try this: simp only [...]` suggestion,
and attach the filmstrip panel widget. -/
@[tactic simpLensStx] def evalSimpLens : Tactic := fun stx => withMainContext do
  withSimpDiagnostics do
  match stx with
  | `(tactic| simp_lens%$tk $cfg:optConfig $(discharger)? $[only%$o]? $[[$args,*]]? $(loc)?) =>
    let argsArr : TSyntaxArray [`Lean.Parser.Tactic.simpStar, `Lean.Parser.Tactic.simpErase, `Lean.Parser.Tactic.simpLemma] :=
      if let some a := args then a.getElems else #[]
    -- split off the `simp_lens`-only `previews` flag before the config
    -- reaches core's `Simp.Config` elaborator
    let (cfg, previews) ← extractPreviewsFlag cfg
    -- Rebuild a genuine core `simp` call so that `mkSimpContext` (and hence
    -- the simplification itself) is exactly what `simp` would do. The
    -- location clause is carried along so `mkSimpOnly` preserves it in the
    -- suggestion, exactly like `simp?`.
    let simpStx ← `(tactic| simp%$tk $cfg:optConfig $[$discharger]? $[only%$o]? [$argsArr,*] $[$loc]?)
    let r@{ ctx, simprocs, dischargeWrapper, .. } ← mkSimpContext simpStx (eraseLocal := false)
    if ctx.config.suggestions then
      throwError "+suggestions requires using simp? instead of simp_lens"
    let location := (loc.map fun l => expandLocation l.raw).getD (.targets #[] true)
    let mvarId ← getMainGoal
    let (res, report) ← dischargeWrapper.with fun discharge? =>
      withLoopChecking r do
        let (fvarIdsToSimp, simplifyTarget) ← resolveLocation location
        withInstancesTypeCheckNote (← mvarId.getType) do
          -- the traced run executes under the ambient heartbeat budget,
          -- exactly like `simp` (timeout parity); its measured cost sizes the
          -- per-preview sub-budget below
          let hb0 ← IO.getNumHeartbeats
          let res ← traceSimpGoal mvarId ctx simprocs discharge? simplifyTarget fvarIdsToSimp
          -- fail exactly like `simp` when no location changed
          throwIfNoProgressGoal ctx res
          let tracedCost := (← IO.getNumHeartbeats) - hb0
          let report ←
            if previews then
              -- heartbeat-neutral: previews can never trip the surrounding
              -- command's budget; each re-run is individually contained
              -- (tryCatchRuntimeEx) and sub-budgeted, so a pathological
              -- exclusion degrades to a "timed out" row, never a failure
              withHeartbeatsNeutral <|
                excludeEachAt mvarId ctx simprocs discharge? res simplifyTarget fvarIdsToSimp
                  (budget? := some (previewBudgetOf tracedCost))
            else
              pure { outcomes := #[], truncated := false, disabled := true }
          pure (res, report)
    match res.goal? with
    | none => replaceMainGoal []
    | some m => replaceMainGoal [m]
    -- everything below is simp_lens-added inspection output; keep it
    -- heartbeat-neutral so the tactic succeeds wherever `simp` does
    withHeartbeatsNeutral do
      -- minimal `simp only [...] (at ...)` suggestion (same machinery as `simp?`)
      let suggestionStx ← mvarId.withContext do minimalSimpOnly simpStx res.usedTheorems
      addSuggestion tk suggestionStx (origSpan? := ← getRef)
      -- unused-argument warnings, same linter and rendering as plain `simp`:
      -- the info leaf must carry a `simp`-kind syntax (the linter checks the
      -- kind) with a *canonical* range (quotation splices are non-canonical,
      -- so the rebuilt syntax needs the original call's range stamped on).
      -- When the original call has no canonical range (inside a macro) the
      -- leaf stays rangeless and the linter skips it, exactly like core.
      if Linter.getLinterValue linter.unusedSimpArgs (← Linter.getLinterOptions) then
        if let (some pos, some tailPos) :=
            (stx.getPos? (canonicalOnly := true), stx.getTailPos? (canonicalOnly := true)) then
          let lintRef := simpStx.raw.setInfo (.synthetic pos tailPos true)
          withRef lintRef do
            warnUnusedSimpArgs r.simpArgs res.usedTheorems
      -- filmstrip panel widget at the tactic position, one section per
      -- location. Interactive expression rendering can blow the (fresh,
      -- ambient-limit) budget on huge terms even with the frame cap, and that
      -- failure is a *runtime* exception a plain catch would rethrow — contain
      -- it and degrade to a filmstrip-less fallback panel (each attempt under
      -- its own fresh heartbeat count so the fallback isn't charged for the
      -- blown render).
      let suggestionStr ← ppTacticCall suggestionStx
      let html ← tryCatchRuntimeEx
        (withHeartbeatsNeutral <| mvarId.withContext do
          renderPanelAt res.films suggestionStr report res.diag res.goal?.isNone)
        fun _ =>
          withHeartbeatsNeutral <| mvarId.withContext do
            let totalRewrites := res.films.foldl (· + ·.film.length) 0
            renderPanelFallback totalRewrites suggestionStr report res.diag res.goal?.isNone
      saveLensWidget stx html
    return res.diag
  | _ => throwUnsupportedSyntax

end SimpLens
