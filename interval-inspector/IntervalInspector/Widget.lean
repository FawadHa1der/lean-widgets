import IntervalInspector.Recognize
import IntervalInspector.Layout
import IntervalInspector.Render
import IntervalInspector.Suggest
import ProofWidgets.Component.HtmlDisplay
import ProofWidgets.Component.OfRpcMethod
import ProofWidgets.Component.MakeEditLink
import Mathlib.Tactic.Linter.UnusedTacticExtension

/-! # Interval Inspector: InfoView panel and `#interval_inspect` command

Two entry points:

* `#interval_inspect e` — a command (like `#html`) that elaborates a term or
  proposition and renders the inspector in the InfoView.  The variant
  `#interval_inspect (text := true) e` instead logs a deterministic ASCII rendering
  (used by `#guard_msgs` tests), e.g. `Ioc a b: (a───b]`.

* `interval_inspect?` — a tactic that displays an InfoView panel for the current
  goal (or a shift-click-selected hypothesis), rendering the number line together
  with applicable lemma suggestions as clickable `MakeEditLink` insertions, following
  the `Mathlib.Tactic.Widget` panel patterns.
-/

namespace IntervalInspector

open Lean Meta Server ProofWidgets Elab

/-- Everything the inspector knows about one statement: recognized shape, order
graph (hypothesis facts + literal comparisons, transitively closed through
auxiliary hypothesis-only atoms), layout, instance availability of the element
type, and suggestions (plus notes about instance-suppressed ones). -/
structure Analysis where
  /-- The recognized statement shape. -/
  shape : Shape
  /-- Order knowledge about the endpoint atoms. -/
  graph : OrderGraph
  /-- Number-line layout of the atoms. -/
  layout : Layout
  /-- Which order typeclasses the element type actually has. -/
  inst : InstAvail
  /-- Applicable lemma suggestions (or fallbacks). -/
  suggestions : Array Suggestion
  /-- Notes about table matches suppressed because the element type lacks a
  required instance (e.g. `Set.nonempty_Iio` over `ℕ`). -/
  suppressed : Array String := #[]

/-- Assemble an `Analysis` from a recognized statement and extra (local-context)
ordering facts. -/
def RecognizedStmt.toAnalysis (r : RecognizedStmt) (lctxFacts : Array OrderFact) :
    Analysis :=
  let graph := r.shape.orderGraph (lctxFacts ++ r.facts)
  let (suggestions, suppressed) := suggestFull r.shape graph r.inst
  { shape := r.shape, graph, layout := computeLayout graph, inst := r.inst
    suggestions, suppressed }

/-- Analyze an expression: recognize its shape (peeling binders, harvesting
comparison binders as facts, checking instance availability) and assemble graph,
layout and suggestions.  `facts` are extra ordering facts (already keyed). -/
def analyze? (e : Expr) (facts : Array OrderFact) : MetaM (Option Analysis) := do
  RecognizeM.run' do
    let some r ← recognizeWithBinders? e | return none
    return some (r.toAnalysis facts)

/-- Analyze an expression using the ordering facts of the current local context.
Shape recognition and fact harvesting share one atom-key table, so hypothesis atoms
match shape endpoints exactly when they are the same expression. -/
def analyzeWithLCtx? (e : Expr) : MetaM (Option Analysis) := do
  RecognizeM.run' do
    let some r ← recognizeWithBinders? e | return none
    return some (r.toAnalysis (← factsFromLCtx))

/-- Render one suggestion as an HTML list item.  `mkLink` turns (label, tactic text)
into the clickable/plain element used for the tactic. -/
def suggestionHtml (s : Suggestion) (mkLink : String → Html) : Html :=
  let condBadges : Array Html := s.conds.map fun (c, ok) =>
    .element "span"
      #[("style", Render.css
          #[("color", if ok then Render.rhsColor else Render.mismatchColor),
            ("marginLeft", "6px")])]
      #[.text s!"{c.desc} {if ok then "✓ ready" else "✗ missing"}"]
  let instBadges : Array Html := s.missingInsts.map fun n =>
    .element "span"
      #[("style", Render.css #[("color", Render.mismatchColor), ("marginLeft", "6px")])]
      #[.text s!"missing instance: {n} ✗"]
  let name : Html :=
    if s.isFallback then
      .element "span" #[("style", Render.css #[("color", Render.mutedColor)])]
        #[.text "fallback"]
    else
      .element "code" #[("style", Render.css #[("color", Render.lhsColor)])]
        #[.text s.lemmaName]
  .element "li" #[("style", Render.css #[("margin", "2px 0")])]
    (#[name, .text " — ", mkLink s.tactic] ++ condBadges ++ instBadges)

/-- Assemble the full inspector HTML: title, number line SVG, suggestion list, and
notes about suggestions suppressed for missing typeclass instances. -/
def inspectorHtml (a : Analysis) (mkLink : String → Html) : Html :=
  let svg := renderShapeSvg a.shape a.graph a.layout a.inst
  let sugTitle : Html := .element "div"
    #[("style", Render.css #[("fontWeight", "bold"), ("marginTop", "6px")])]
    #[.text (if (a.suggestions.map (·.isFallback)).contains false
             then "Suggested lemmas" else "No table entry applies — fallbacks")]
  let items := a.suggestions.map (suggestionHtml · mkLink)
  let suppressedNotes : Array Html := a.suppressed.map fun n =>
    .element "div"
      #[("style", Render.css #[("color", Render.mutedColor), ("fontSize", "11px")])]
      #[.text n]
  .element "div" #[("style", Render.css #[("fontFamily", "sans-serif")])]
    (#[.element "div"
        #[("style", Render.css #[("fontFamily", "monospace"), ("marginBottom", "4px")])]
        #[.text a.shape.desc],
      svg, sugTitle,
      .element "ul"
        #[("style", Render.css
            #[("margin", "4px 0 4px 16px"), ("padding", "0"), ("listStyle", "disc")])]
        items]
     ++ suppressedNotes)

/-- Plain (non-clickable) rendering of a suggested tactic, used by the command. -/
def plainTactic (t : String) : Html :=
  Render.el "code" #[] #[.text t]

/-! ## The `#interval_inspect` command -/

/-- `#interval_inspect e` elaborates the term or proposition `e` and renders the
interval inspector (number line + lemma suggestions) in the InfoView.

`#interval_inspect (text := true) e` instead logs a deterministic ASCII rendering,
e.g. `Ioc a b: (a───b]` — this mode is used by `#guard_msgs` tests. -/
syntax (name := intervalInspectCmd)
  "#interval_inspect" (atomic("(" &"text" " := " &"true" ")"))? term : command

open Command in
@[command_elab intervalInspectCmd]
def elabIntervalInspectCmd : CommandElab := fun stx => do
  match stx with
  | `(#interval_inspect $t:term) => go stx t false
  | `(#interval_inspect (text := true) $t:term) => go stx t true
  | _ => throwUnsupportedSyntax
where
  /-- Shared elaboration: recognize, then render as ASCII or HTML panel.
  `runTermElabM` (not `liftTermElabM`) brings section `variable`s into the local
  context, so `#interval_inspect Set.Icc a b` works inside
  `section variable (a b : ℝ)` — exactly like `#check` — and section hypotheses
  such as `(h : a ≤ b)` feed the harvested ordering facts. -/
  go (stx : Syntax) (t : Syntax) (textMode : Bool) : Command.CommandElabM Unit := do
    let analysis ← runTermElabM fun _ => do
      let e ← Term.elabTerm t none
      Term.synthesizeSyntheticMVarsNoPostponing
      let e ← instantiateMVars e
      analyzeWithLCtx? e
    match analysis with
    | none =>
      throwError "#interval_inspect: not a recognized interval shape (supported: \
        Set.Icc/Ico/Ioc/Ioo/Ici/Iic/Ioi/Iio, Set.univ, ∅, \{a}, set-builder \
        intervals like \{x | a ≤ x ∧ x < b}, combined with ∪/∩, as bare terms or \
        in x ∈ s / s ⊆ t / s ⊂ t / s = t / Set.Nonempty s / s ≠ ∅ / ∅ ≠ s)"
    | some a =>
      if textMode then
        logInfo a.shape.ascii
      else
        let ht := inspectorHtml a plainTactic
        liftCoreM <| Widget.savePanelWidgetInfo
          (hash HtmlDisplayPanel.javascript)
          (return json% { html: $(← rpcEncode ht) })
          stx

/-! ## The `interval_inspect?` tactic panel -/

/-- Props of the inspector panel: standard panel-widget props plus the range to
replace when a suggestion link is clicked. -/
structure InspectorParams where
  /-- Cursor position in the file. -/
  pos : Lsp.Position
  /-- Current tactic-mode goals. -/
  goals : Array Widget.InteractiveGoal
  /-- Locations selected (shift-click) in the goal state. -/
  selectedLocations : Array SubExpr.GoalsLocation
  /-- Source range that a clicked suggestion replaces. -/
  replaceRange : Lsp.Range
  deriving RpcEncodable

/-- RPC method behind the inspector panel: analyzes the main goal (or the
shift-click-selected hypothesis) and renders number line + clickable suggestions. -/
@[server_rpc_method]
def IntervalInspectorPanel.rpc (params : InspectorParams) : RequestM (RequestTask Html) :=
  RequestM.asTask do
    let doc ← RequestM.readDoc
    if h : 0 < params.goals.size then
      let mainGoal := params.goals[0]
      mainGoal.ctx.val.runMetaM {} do
        let md ← mainGoal.mvarId.getDecl
        let lctx := md.lctx.sanitizeNames.run' { options := (← getOptions) }
        Meta.withLCtx lctx md.localInstances do
          -- Inspect a shift-clicked hypothesis if there is one, else the goal.
          let mut target := md.type
          let mut label := "goal"
          for sel in params.selectedLocations do
            match sel.loc with
            | .hyp fvarId | .hypType fvarId _ =>
              target := (← fvarId.getDecl).type
              label := s!"hypothesis {(← fvarId.getDecl).userName}"
            | _ => pure ()
          match ← analyzeWithLCtx? target with
          | none =>
            return Render.el "span" #[]
              #[.text s!"interval inspector: the {label} is not a recognized interval \
                  shape (shift-click a hypothesis to inspect it instead)"]
          | some a =>
            let mkLink (tac : String) : Html :=
              .ofComponent MakeEditLink
                (.ofReplaceRange doc.meta params.replaceRange tac)
                #[.text tac]
            return inspectorHtml a mkLink
    else
      return Render.el "span" #[] #[.text "No goals."]

/-- The inspector panel component. -/
@[widget_module]
def IntervalInspectorPanel : Component InspectorParams :=
  mk_rpc_widget% IntervalInspectorPanel.rpc

open Elab.Tactic in
/-- Display the interval-inspector panel for the current goal.  Shift-click a
hypothesis in the InfoView to inspect that hypothesis instead of the goal.
Clicking a suggestion replaces this tactic call with the suggested tactic text. -/
elab (name := intervalInspectTac) stx:"interval_inspect?" : tactic => do
  let some replaceRange := (← getFileMap).lspRangeOfStx? stx | return
  Widget.savePanelWidgetInfo (hash IntervalInspectorPanel.javascript)
    (pure <| json% { replaceRange: $(replaceRange) }) stx

-- The tactic intentionally changes no goal (it only attaches a panel); tell
-- Mathlib's unused-tactic linter not to flag it.
#allow_unused_tactic! IntervalInspector.intervalInspectTac

end IntervalInspector
