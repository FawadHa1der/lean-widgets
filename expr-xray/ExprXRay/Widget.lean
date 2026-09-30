import ProofWidgets.Component.HtmlDisplay
import ProofWidgets.Component.OfRpcMethod
import ProofWidgets.Component.Panel.SelectionPanel
import ExprXRay.Analyze
import ExprXRay.Diff
import ExprXRay.Render

/-! # Expr X-Ray: user-facing surface

* `#xray e` — elaborate the term `e` and display the analysis in the
  InfoView (place the cursor on the command).
* `#xray (text := true) e` — additionally `logInfo` a deterministic
  plain-text rendering, so `#guard_msgs` tests can pin the output.
* `#xray_diff e₁, e₂` — compare two elaborated terms side by side with a
  ranked mismatch list (also supports `(text := true)`).
* `XRayPanel` — an InfoView panel component: with 0 shift-click
  selections it x-rays the main goal's target, with 1 selection the
  selected subterm, with 2 selections it compares them. -/

namespace ExprXRay

open Lean Meta Elab Term Command Server ProofWidgets

/-- Build the full single-expression x-ray `Html` for `e`
(preset trees + `pp.explicit` sections). -/
def xrayHtml (e : Expr) (cfg : XRayConfig := {}) : MetaM Html := do
  let node ← analyzeExpr e cfg
  let explicitTxt ← ppExplicitString e
  let explicitUnivTxt ← ppExplicitString e (universes := true)
  return renderXRay node explicitTxt explicitUnivTxt

/-- Deterministic plain-text x-ray of `e` (the `everything` preset). -/
def xrayText (e : Expr) (cfg : XRayConfig := {}) : MetaM String := do
  let node ← analyzeExpr e cfg
  return node.toText .everything

/-- Build the compare-mode `Html` for `e₁` vs `e₂`. -/
def xrayCompareHtml (e₁ e₂ : Expr) (cfg : XRayConfig := {}) : MetaM Html := do
  let n₁ ← analyzeExpr e₁ cfg
  let n₂ ← analyzeExpr e₂ cfg
  let ms ← diffExprs e₁ e₂
  return renderCompare n₁ n₂ ms

/-- Deterministic plain-text compare of `e₁` vs `e₂`: the ranked mismatch
descriptions (each with its defeq annotation), one per line, preceded by
the pinned all-defeq summary when every mismatch is definitionally equal
(or a fixed no-difference message). -/
def xrayCompareText (e₁ e₂ : Expr) : MetaM String := do
  let ms ← diffExprs e₁ e₂
  if ms.isEmpty then
    return "no structural differences found"
  let lines := ms.toList.map (·.describe)
  let lines := if allDefeq ms then allDefeqSummary ms.size :: lines else lines
  return String.intercalate "\n" lines

/-- Elaborate `t` for inspection: elaborate, synthesize pending synthetic
metavariables (typeclasses, coercions), instantiate assigned mvars. -/
def elabTermForXRay (t : Term) : TermElabM Expr := do
  let e ← Term.elabTerm t none
  Term.synthesizeSyntheticMVarsNoPostponing
  instantiateMVars e

/-- Display `html` as a panel widget attached to `stx` (the same
mechanism as ProofWidgets' `#html`). -/
def savePanelHtml (html : Html) (stx : Syntax) : CommandElabM Unit :=
  liftCoreM <| Widget.savePanelWidgetInfo
    (hash HtmlDisplayPanel.javascript)
    (return json% { html: $(← rpcEncode html) })
    stx

/-- `#xray e` elaborates `e` and displays its analysis in the InfoView.
`#xray (text := true) e` additionally logs a deterministic plain-text
rendering of the analysis tree. -/
syntax (name := xrayCmd) "#xray " (atomic("(" &"text" " := " &"true" ") "))? term : command

/-- `#xray_diff e₁, e₂` elaborates both terms and shows a ranked mismatch
list plus both trees side by side. `#xray_diff (text := true) e₁, e₂`
additionally logs the ranked mismatch descriptions as plain text. -/
syntax (name := xrayDiffCmd)
  "#xray_diff " (atomic("(" &"text" " := " &"true" ") "))? term ", " term : command

@[command_elab xrayCmd]
def elabXRayCmd : CommandElab := fun stx => match stx with
  | `(#xray $t:term) => go t false stx
  | `(#xray (text := true) $t:term) => go t true stx
  | _ => throwUnsupportedSyntax
where
  /-- Shared elaboration of both `#xray` forms. -/
  go (t : Term) (textMode : Bool) (stx : Syntax) : CommandElabM Unit := do
    let (html, txt?) ← liftTermElabM do
      let e ← elabTermForXRay t
      let html ← xrayHtml e
      let txt? ← if textMode then some <$> xrayText e else pure none
      pure (html, txt?)
    if let some txt := txt? then
      logInfo txt
    savePanelHtml html stx

@[command_elab xrayDiffCmd]
def elabXRayDiffCmd : CommandElab := fun stx => match stx with
  | `(#xray_diff $t₁:term, $t₂:term) => go t₁ t₂ false stx
  | `(#xray_diff (text := true) $t₁:term, $t₂:term) => go t₁ t₂ true stx
  | _ => throwUnsupportedSyntax
where
  /-- Shared elaboration of both `#xray_diff` forms. -/
  go (t₁ t₂ : Term) (textMode : Bool) (stx : Syntax) : CommandElabM Unit := do
    let (html, txt?) ← liftTermElabM do
      let e₁ ← elabTermForXRay t₁
      let e₂ ← elabTermForXRay t₂
      let html ← xrayCompareHtml e₁ e₂
      let txt? ← if textMode then some <$> xrayCompareText e₁ e₂ else pure none
      pure (html, txt?)
    if let some txt := txt? then
      logInfo txt
    savePanelHtml html stx

/-! ## The InfoView panel -/

/-- Find the interactive goal a selection belongs to. -/
def findGoalForLocation (goals : Array Widget.InteractiveGoal)
    (loc : SubExpr.GoalsLocation) : Option Widget.InteractiveGoal :=
  goals.find? (·.mvarId == loc.mvarId)

/-- Extract the `Expr` (with its context) for one shift-click selection. -/
def exprOfLocation (props : PanelWidgetProps) (loc : SubExpr.GoalsLocation) :
    RequestM ExprWithCtx := do
  let some g := findGoalForLocation props.goals loc
    | throw <| RequestError.invalidParams
        s!"could not find goal for selection {toJson loc}"
  g.ctx.val.runMetaM {} loc.saveExprWithCtx

/-- Wrap panel content in a collapsible top-level block (a well-behaved
InfoView panel should be collapsible). -/
def panelWrap (inner : Html) : Html :=
  .element "details" #[("open", Json.bool true)] #[
    .element "summary" #[("style", json% { "cursor": "pointer" })]
      #[.text "Expr X-Ray 🩻"],
    .element "div" #[("style", json% { "marginLeft": "0.5em" })] #[inner]
  ]

/-- RPC backend of `XRayPanel`:
* 0 selections → x-ray the main goal's target (or the term-mode goal);
* 1 selection → x-ray the selected subterm;
* 2 selections → compare the two selected subterms;
* more → ask the user to select fewer. -/
@[server_rpc_method]
def XRayPanel.rpc (props : PanelWidgetProps) : RequestM (RequestTask Html) :=
  RequestM.asTask do
    match props.selectedLocations with
    | #[] =>
      if let some g := props.goals[0]? then
        let html ← g.ctx.val.runMetaM {} do
          let md ← g.mvarId.getDecl
          Meta.withLCtx md.lctx md.localInstances do
            xrayHtml (← instantiateMVars md.type)
        return panelWrap html
      else if let some tg := props.termGoal? then
        let ti := tg.term.val
        let html ← tg.ctx.val.runMetaM {} do
          Meta.withLCtx ti.lctx #[] do
            xrayHtml (← instantiateMVars ti.expr)
        return panelWrap html
      else
        return panelWrap <| .text "No goal to inspect. Shift-click a subterm to x-ray it."
    | #[loc] =>
      let ewc ← exprOfLocation props loc
      let html ← ewc.runMetaM fun e => xrayHtml e
      return panelWrap html
    | #[loc₁, loc₂] =>
      let ewc₁ ← exprOfLocation props loc₁
      let ewc₂ ← exprOfLocation props loc₂
      -- Diff in the first selection's context. If the second selection
      -- comes from a different local context its fvars may print oddly,
      -- but analysis is guarded and will not fail.
      let html ← ewc₁.runMetaM fun e₁ => xrayCompareHtml e₁ ewc₂.expr
      return panelWrap html
    | _ =>
      return panelWrap <| .text
        s!"Select at most 2 subterms (currently {props.selectedLocations.size} selected)."

/-- The Expr X-Ray InfoView panel. Use it in a proof as
`with_panel_widgets [ExprXRay.XRayPanel] <tactics>` and shift-click
subterms of the goal to inspect (1 selection) or compare (2 selections). -/
@[widget_module]
def XRayPanel : Component PanelWidgetProps :=
  mk_rpc_widget% XRayPanel.rpc

end ExprXRay
