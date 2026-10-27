import IntervalInspector.Widget
import IntervalInspectorTests.Helpers
import Mathlib.Basic.Real.Basic

/-! # `#interval_inspect` text-mode tests

Message-exact `#guard_msgs` tests of the deterministic ASCII rendering, including
inside `variable` sections (the command elaborates with `runTermElabM`, like
`#check`).  At the end, pins of the panel the real panel-mode command stores
(its suggestion rows, decoded from the saved widget props).
-/

namespace IntervalInspectorTests

/-- info: Ioc a b: (a───b] -/
#guard_msgs in
#interval_inspect (text := true) (fun (a b : ℝ) => Set.Ioc a b)

/-- info: Ioc 1 2 ∪ Ioc 2 3 = Ioc 1 3: (1───2] ∪ (2───3] = (1───3] -/
#guard_msgs in
#interval_inspect (text := true) (Set.Ioc (1:ℝ) 2 ∪ Set.Ioc 2 3 = Set.Ioc 1 3)

/-- info: 3 ∈ Icc 1 4: 3 ∈ [1───4] -/
#guard_msgs in
#interval_inspect (text := true) ((3:ℝ) ∈ Set.Icc 1 4)

/-- info: Ioo a b ⊆ Icc a b: (a───b) ⊆ [a───b] -/
#guard_msgs in
#interval_inspect (text := true) ∀ (a b : ℝ), Set.Ioo a b ⊆ Set.Icc a b

/-- info: Ioo a b ⊂ Icc a b: (a───b) ⊂ [a───b] -/
#guard_msgs in
#interval_inspect (text := true) ∀ (a b : ℝ), Set.Ioo a b ⊂ Set.Icc a b

/-- info: Ici a: [a───∞) -/
#guard_msgs in
#interval_inspect (text := true) (fun (a : ℝ) => Set.Ici a)

/-- info: Iio b: (-∞───b) -/
#guard_msgs in
#interval_inspect (text := true) (fun (b : ℝ) => Set.Iio b)

/-- info: Ioo a b = ∅: (a───b) = ∅ -/
#guard_msgs in
#interval_inspect (text := true) ∀ (a b : ℝ), Set.Ioo a b = (∅ : Set ℝ)

/-- info: Icc a a = {a}: [a───a] = {a} -/
#guard_msgs in
#interval_inspect (text := true) ∀ (a : ℝ), Set.Icc a a = {a}

/-- info: Icc a b ∩ Icc c d: [a───b] ∩ [c───d] -/
#guard_msgs in
#interval_inspect (text := true) (fun (a b c d : ℝ) => Set.Icc a b ∩ Set.Icc c d)

/-- info: univ: (-∞───∞) -/
#guard_msgs in
#interval_inspect (text := true) (Set.univ : Set ℝ)

/-! ## Nonemptiness / emptiness shapes -/

/-- info: (Ioc 1 2).Nonempty: (1───2] ≠ ∅ -/
#guard_msgs in
#interval_inspect (text := true) (Set.Ioc (1:ℝ) 2).Nonempty

/-- info: Icc a b ≠ ∅: [a───b] ≠ ∅ -/
#guard_msgs in
#interval_inspect (text := true) ∀ (a b : ℝ), Set.Icc a b ≠ ∅

/-- info: Ioo a b ≠ ∅: (a───b) ≠ ∅ -/
#guard_msgs in
#interval_inspect (text := true) ∀ (a b : ℝ), ¬(Set.Ioo a b = ∅)

/-! ## The reversed disequality `∅ ≠ s` (mirror of `s ≠ ∅`) -/

/-- info: ∅ ≠ Icc a b: ∅ ≠ [a───b] -/
#guard_msgs in
#interval_inspect (text := true) ∀ (a b : ℝ), (∅ : Set ℝ) ≠ Set.Icc a b

/-! ## Section variables (the confirmed `unknown identifier` repro)

`#interval_inspect` must elaborate like `#check`: inside
`section variable (a b : ℝ)`, the term `Set.Icc a b` elaborates against the
section variables, and a section *hypothesis* `(h : a ≤ b)` is harvested from the
local context exactly like a tactic-mode hypothesis. -/

section
variable (a b : ℝ) (h : a ≤ b)

/-- info: Icc a b: [a───b] -/
#guard_msgs in
#interval_inspect (text := true) Set.Icc a b

/-- info: Ioc a b ∪ Ioc b c = Ioc a c: (a───b] ∪ (b───c] = (a───c] -/
#guard_msgs in
#interval_inspect (text := true) ∀ (c : ℝ), b ≤ c →
  Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c

-- The section hypothesis `h : a ≤ b` feeds the side-condition readiness
-- (`#assert_reports` elaborates through the same `runTermElabM` path).
#assert_reports (Set.Icc a b).Nonempty
  => "Set.nonempty_Icc [a ≤ b (ready)] — refine Set.nonempty_Icc.mpr ?_ [ALL-READY]"

end

/-! ## Set-builder intervals (rendered as their recognized kind) -/

/-- info: Ico 1 2: [1───2) -/
#guard_msgs in
#interval_inspect (text := true) ({x : ℝ | 1 ≤ x ∧ x < 2})

/-- info: Ico 0 1 ⊆ Icc 0 1: [0───1) ⊆ [0───1] -/
#guard_msgs in
#interval_inspect (text := true) ({x : ℝ | 0 ≤ x ∧ x < 1} ⊆ Set.Icc 0 1)

/--
error: #interval_inspect: not a recognized interval shape (supported: Set.Icc/Ico/Ioc/Ioo/Ici/Iic/Ioi/Iio, Set.univ, ∅, {a}, set-builder intervals like {x | a ≤ x ∧ x < b}, combined with ∪/∩, as bare terms or in x ∈ s / s ⊆ t / s ⊂ t / s = t / Set.Nonempty s / s ≠ ∅ / ∅ ≠ s)
-/
#guard_msgs in
#interval_inspect (text := true) (42 : ℕ)

end IntervalInspectorTests

/-! ## Panel HTML assembly (the pure part of the InfoView panel) -/

namespace PanelHtmlTests

open IntervalInspector

private def joinLit : Shape :=
  .eq (.union (.leaf { kind := .Ioc, lo? := some { pp := "1", val? := some 1 },
                       hi? := some { pp := "2", val? := some 2 } })
              (.leaf { kind := .Ioc, lo? := some { pp := "2", val? := some 2 },
                       hi? := some { pp := "3", val? := some 3 } }))
      (.leaf { kind := .Ioc, lo? := some { pp := "1", val? := some 1 },
               hi? := some { pp := "3", val? := some 3 } })

private def analysis : Analysis :=
  let g := joinLit.orderGraph #[]
  { shape := joinLit, graph := g, layout := computeLayout g, inst := .all
    suggestions := suggest joinLit g }

private def panel : String := htmlToDebugString (inspectorHtml analysis plainTactic)

-- The panel shows the statement, the SVG, the firing lemma and its ready conditions.
#guard strContains panel "Ioc 1 2 ∪ Ioc 2 3 = Ioc 1 3"
#guard strContains panel "<svg"
#guard strContains panel "Set.Ioc_union_Ioc_eq_Ioc"
#guard strContains panel "refine Set.Ioc_union_Ioc_eq_Ioc ?_ ?_"
#guard strContains panel "1 ≤ 2 ✓ ready"
#guard strContains panel "2 ≤ 3 ✓ ready"
#guard strContains panel "Suggested lemmas"
#guard !strContains panel "✗ missing"

-- With symbolic endpoints and no facts, conditions are reported missing.
private def joinSym : Shape :=
  .eq (.union (.leaf { kind := .Ioc, lo? := some { pp := "a" }, hi? := some { pp := "b" } })
              (.leaf { kind := .Ioc, lo? := some { pp := "b" }, hi? := some { pp := "c" } }))
      (.leaf { kind := .Ioc, lo? := some { pp := "a" }, hi? := some { pp := "c" } })

private def analysisSym : Analysis :=
  let g := joinSym.orderGraph #[]
  { shape := joinSym, graph := g, layout := computeLayout g, inst := .all
    suggestions := suggest joinSym g }

private def panelSym : String := htmlToDebugString (inspectorHtml analysisSym plainTactic)

#guard strContains panelSym "a ≤ b ✗ missing"
#guard strContains panelSym "b ≤ c ✗ missing"

-- Ready/missing badges and lemma names are themed: VS Code CSS variables with the
-- fallback hex inside the var() expression.  Styles are React-style JSON objects
-- (never CSS strings — see `Render.css`), so they serialize as compressed JSON.
#guard strContains panel "\"color\":\"var(--vscode-charts-green, #10b981)\""
#guard strContains panel "\"color\":\"var(--vscode-charts-blue, #3b82f6)\""
#guard strContains panelSym "\"color\":\"var(--vscode-charts-red, #ef4444)\""
#guard !strContains panel "\"color\":\"#10b981\""
#guard !strContains panelSym "\"color\":\"#ef4444\""

end PanelHtmlTests

/-! ## The real `#interval_inspect` panel, end to end

Panel mode (no `text := true`) stores one `HtmlDisplayPanel` widget whose props
carry the inspector HTML the InfoView shows.  The assertion command below
elaborates the *actual* `#interval_inspect e` command (a nested `elabCommand`, as
in a user's file), reads the stored widget back out of the info tree, decodes its
`html` prop with the `RpcEncodable` instance the InfoView round-trip uses, and
pins the suggestion rows the user sees.

Pinned on the `≠ ∅` spelling of the `Ioo` repro: `Set.nonempty_Ioo` needs
`DenselyOrdered`, which `ℕ` lacks.  Over `ℕ` the suggestion must carry the
`missing instance: DenselyOrdered ✗` badge; over the dense control `ℝ`, and for
`Ico` over `ℕ` (no density needed), it must not. -/

namespace CommandPanelTests

open Lean Elab Command Server ProofWidgets IntervalInspector

/-- All text leaves of an `Html` tree, concatenated in document order. -/
partial def htmlText : Html → String
  | .text s => s
  | .element _ _ cs => String.join (cs.toList.map htmlText)
  | .component _ _ _ cs => String.join (cs.toList.map htmlText)

/-- The suggestion rows (`li` elements) of an `Html` tree, in document order.
`suggestionHtml` lays a row out as `#[name, " — ", tactic] ++ condBadges ++
instBadges`; it is rendered here as the text of those first three children
followed by each badge in brackets, e.g.
`Set.foo — refine … [a ≤ b ✓ ready] [missing instance: X ✗]`. -/
partial def htmlItems : Html → Array String
  | .element "li" _ cs =>
    #[String.join ((cs.toList.take 3).map htmlText)
      ++ String.join ((cs.toList.drop 3).map fun c => s!" [{htmlText c}]")]
  | .element _ _ cs => cs.flatMap htmlItems
  | .component _ _ _ cs => cs.flatMap htmlItems
  | .text _ => #[]

/-- Elaborate the real `#interval_inspect t` (panel mode) and return the `Html`
stored in the single `HtmlDisplayPanel` widget it saves. -/
def inspectPanelHtml (t : Syntax.Term) : CommandElabM Html := do
  let before := (← getInfoState).trees.size
  withEnableInfoTree true <| elabCommand (← `(command| #interval_inspect $t))
  let stored := ((← getInfoState).trees.toList.drop before).flatMap fun tree =>
    tree.deepestNodes fun _ i _ =>
      match i with
      | .ofUserWidgetInfo wi => some (wi.javascriptHash, (wi.props.run {}).1)
      | _ => none
  let [(h, props)] := stored
    | throwError "expected exactly 1 stored panel widget, got {stored.length}"
  unless h == hash HtmlDisplayPanel.javascript do
    throwError "the stored widget is not an HtmlDisplayPanel"
  let .ok htmlJson := props.getObjVal? "html"
    | throwError "stored props have no html field: {props.compress}"
  match Id.run ((ExceptT.run (rpcDecode (α := Html) htmlJson)).run {}) with
  | .ok html => return html
  | .error e => throwError "stored html does not decode: {e}"

/-- `#assert_panel_items e => "row₁ | row₂"`: run the real `#interval_inspect e`
and pin the suggestion rows of its stored panel (see `htmlItems`), joined by
`" | "`. -/
elab "#assert_panel_items " t:term " => " s:str : command => do
  let actual := String.intercalate " | " (htmlItems (← inspectPanelHtml t)).toList
  unless actual == s.getString do
    throwError "panel items mismatch:\n  expected: {s.getString}\n  actual:   {actual}"

-- ℕ (no `DenselyOrdered`): offered only with the missing-instance badge, in both
-- orientations.
#assert_panel_items (Set.Ioo (0:ℕ) 2 ≠ ∅)
  => "Set.Nonempty.ne_empty — refine (Set.nonempty_Ioo.mpr ?_).ne_empty \
      [0 < 2 ✓ ready] [missing instance: DenselyOrdered ✗]"
#assert_panel_items ((∅ : Set ℕ) ≠ Set.Ioo 0 2)
  => "Set.Nonempty.ne_empty — refine ((Set.nonempty_Ioo.mpr ?_).ne_empty).symm \
      [0 < 2 ✓ ready] [missing instance: DenselyOrdered ✗]"
-- The gate is `Ioo`-only: `Ico` over ℕ shows no badge.
#assert_panel_items (Set.Ico (0:ℕ) 2 ≠ ∅)
  => "Set.Nonempty.ne_empty — refine (Set.nonempty_Ico.mpr ?_).ne_empty [0 < 2 ✓ ready]"
-- Dense control: the same `Ioo` statement over ℝ shows the suggestion, no badge.
#assert_panel_items (Set.Ioo (0:ℝ) 2 ≠ ∅)
  => "Set.Nonempty.ne_empty — refine (Set.nonempty_Ioo.mpr ?_).ne_empty [0 < 2 ✓ ready]"

end CommandPanelTests
