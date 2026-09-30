import ChartKit.Render
import ProofWidgets.Component.HtmlDisplay

/-! # ChartKit: the `#chart` command

```
#chart spec
#chart (text := true) spec
```

`#chart spec` evaluates `spec : ChartSpec` (concrete, computable data — the
command compiles and runs the term, so it must not mention `sorry`,
metavariables or noncomputable constants; each is refused with an honest
error) and renders it as an SVG panel in the InfoView.

`(text := true)` logs the deterministic ASCII report instead of the HTML
panel — this mode is what the `#guard_msgs` tests pin.

Invalid specs (no series, caps exceeded, categorical label mismatches — see
`ChartSpec.validationErrors`) are refused with the full list of problems.

The spec argument parses at `term:max` precedence, so applications need
parentheses: `#chart (myChart 5)`; structure literals `#chart { series := … }`
work directly.
-/

namespace ChartKit

open Lean Meta Server Elab ProofWidgets

/-- Pretty-print an expression to a single line (deterministic error text). -/
def ppOneLine (e : Expr) : MetaM String := do
  return (← ppExpr e).pretty (width := 100000)

/-- Run one evaluation step, rebranding any failure as a `#chart` error
(interrupts and runtime errors pass through untouched). -/
def evalOrExplain (what : String) (act : MetaM α) : MetaM α := do
  try
    act
  catch ex =>
    if ex.isInterrupt || ex.isRuntime then
      throw ex
    throwError "#chart: failed to {what} — {ex.toMessageData}"

/-- Elaborate and evaluate a term against `ChartSpec`.  Refuses — each with an
honest `#chart`-branded error — terms that still contain metavariables, terms
that mention `sorry`, and terms using noncomputable constants (which the
compiler could not evaluate; the raw compiler error would be useless for a
command).  The evaluation itself is one compiled call: a `ChartSpec` is plain
first-order data, but the term may compute it, so arbitrary user code can run
here (see README limitations). -/
def elabChartSpec (t : Syntax.Term) : TermElabM ChartSpec := do
  let expected := mkConst ``ChartKit.ChartSpec
  let e ← Term.elabTerm t (some expected)
  Term.synthesizeSyntheticMVarsNoPostponing
  let e ← instantiateMVars e
  if e.hasSorry then
    throwError "#chart: the spec contains `sorry` — fill it in so the chart \
      is fully determined"
  if e.hasExprMVar then
    throwError "#chart: the spec still contains metavariables (`_`) — fill in \
      the underscores so the chart is fully determined"
  let env ← getEnv
  if let some c := e.getUsedConstants.find? (isNoncomputable env ·) then
    throwError "#chart: the spec uses the noncomputable constant `{c}` — \
      ChartKit evaluates the spec with compiled code, so it must be computable"
  Core.checkSystem "#chart"
  evalOrExplain s!"evaluate `{← ppOneLine e}` as a ChartSpec" <|
    unsafe evalExpr ChartSpec (mkConst ``ChartKit.ChartSpec) e (safety := .unsafe)

/-- `#chart spec` renders the chart described by `spec : ChartSpec` in the
InfoView; `#chart (text := true) spec` logs a deterministic ASCII report
instead (size, exact axis ticks, per-series marks and point counts). -/
syntax (name := chartCmd)
  "#chart" (atomic("(" &"text" " := " &"true" ")"))? term:max : command

open Command in
/-- Elaborator for `#chart` / `#chart (text := true)`. -/
@[command_elab chartCmd]
def elabChartCmd : CommandElab := fun stx => do
  match stx with
  | `(#chart $t:term) => go stx t false
  | `(#chart (text := true) $t:term) => go stx t true
  | _ => throwUnsupportedSyntax
where
  /-- Shared elaboration: evaluate the spec, then log text or attach the
  panel; every rendering error (validation, internal self-checks) becomes a
  command error. -/
  go (stx : Syntax) (t : Syntax.Term) (textMode : Bool) : CommandElabM Unit := do
    let spec ← liftTermElabM (elabChartSpec t)
    if textMode then
      match textReport spec with
      | .ok report => logInfo report
      | .error e => throwError "#chart: {e}"
    else
      match renderChart spec with
      | .ok ht =>
        liftCoreM <| Widget.savePanelWidgetInfo
          (hash HtmlDisplayPanel.javascript)
          (return json% { html: $(← rpcEncode ht) })
          stx
      | .error e => throwError "#chart: {e}"

end ChartKit
