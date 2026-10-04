import ProofWidgets.Data.Html
import ExprXRay.Types
import ExprXRay.Diff

/-! # Expr X-Ray: rendering

Renders `XNode` trees to `ProofWidgets.Html` using nested
`<details>/<summary>` (native expand/collapse, zero custom JavaScript):

* explicit arguments look normal;
* implicit arguments are dimmed (inline `opacity` style);
* instance arguments are dimmed and get an `[inst]` badge;
* coercion heads get a `↑` badge;
* universe levels are rendered small after constant names;
* four preset views actually *filter* nodes: clean / +implicit /
  +instances / everything.

Compare mode renders two trees side by side (flex row) with mismatching
nodes highlighted and a ranked mismatch summary list on top.

The module also provides a deterministic `Html.toStringCompact`
serialization used by the test suite, and `XNode.toText`, the plain-text
tree rendering used by `#xray (text := true)`. -/

namespace ExprXRay

open Lean ProofWidgets

/-- The four preset views. Custom checkbox JS is out of scope, so the
presets are fixed filters over the analysis tree. -/
inductive ViewPreset where
  /-- Explicit arguments only. -/
  | clean
  /-- Explicit + implicit (and strict-implicit) arguments. -/
  | withImplicit
  /-- Explicit + implicit + instance-implicit arguments. -/
  | withInstances
  /-- Everything, additionally showing universe levels. -/
  | everything
  deriving Repr, BEq, Inhabited, DecidableEq

/-- Human label of a preset. -/
def ViewPreset.label : ViewPreset → String
  | .clean         => "clean"
  | .withImplicit  => "+implicit"
  | .withInstances => "+instances"
  | .everything    => "everything"

/-- Does `p` display child nodes with role `r`? `clean` keeps only
explicit/none roles, `+implicit` adds (strict-)implicits, `+instances`
and `everything` keep all. -/
def ViewPreset.showsRole : ViewPreset → BinderRole → Bool
  | .clean, r        => r == .none || r == .explicit
  | .withImplicit, r => r != .instImplicit
  | .withInstances, _ => true
  | .everything, _    => true

/-- Does `p` display universe levels after constant names? -/
def ViewPreset.showsUniverses : ViewPreset → Bool
  | .everything => true
  | _           => false

/-- Deterministic compact serialization of `Html`, used for testing.
Elements become `<tag attr=val…>children</tag>` with attribute values
serialized via `Json.compress`; components become
`<component:EXPORT>children</component>`. -/
partial def Html.toStringCompact : Html → String
  | .text s => s
  | .element tag attrs children =>
    let attrStr := attrs.foldl (init := "") fun acc (k, v) => acc ++ s!" {k}={v.compress}"
    let inner := children.foldl (init := "") fun acc c => acc ++ Html.toStringCompact c
    s!"<{tag}{attrStr}>{inner}</{tag}>"
  | .component _ exp _ children =>
    let inner := children.foldl (init := "") fun acc c => acc ++ Html.toStringCompact c
    s!"<component:{exp}>{inner}</component>"

/-- Inline style used to dim hidden-by-default (implicit/instance) nodes. -/
def dimStyle : Json := json% { "opacity": "0.55" }

/-- Inline style of the highlighted (mismatching) nodes in compare mode. -/
def highlightStyle : Json :=
  json% { "backgroundColor": "rgba(255, 90, 90, 0.22)", "borderRadius": "3px" }

/-- Badge shown before instance-implicit arguments. -/
def instBadge : Html :=
  .element "span"
    #[("style", json% { "color": "var(--vscode-charts-purple, purple)",
                        "fontSize": "0.8em", "marginRight": "0.3em" })]
    #[.text "[inst]"]

/-- Badge shown before coercion applications. -/
def coeBadge : Html :=
  .element "span"
    #[("style", json% { "color": "var(--vscode-charts-blue, blue)",
                        "marginRight": "0.3em" })]
    #[.text "↑coe"]

/-- Badge shown on nodes that differ from their compare-mode counterpart. -/
def diffBadge : Html :=
  .element "span"
    #[("style", json% { "color": "var(--vscode-errorForeground, red)",
                        "marginRight": "0.3em", "fontWeight": "bold" })]
    #[.text "≠"]

/-- Badge showing the `DefeqStatus` of a mismatch in the compare-mode
summary list: red `≢`/`≟` for blocking (or unverified) differences,
green `≈ʳ`/`≈ᵈ` for definitionally equal ones. -/
def defeqBadgeHtml (s : DefeqStatus) : Html :=
  let color := if s.isDefeq then "var(--vscode-charts-green, green)"
               else "var(--vscode-errorForeground, red)"
  .element "span"
    #[("style", json% { "color": $(color), "marginRight": "0.4em",
                        "fontWeight": "bold" })]
    #[.text s.badge]

/-- Small gray suffix (used for kinds, types and universe levels). -/
def subtleText (s : String) : Html :=
  .element "span"
    #[("style", json% { "opacity": "0.6", "fontSize": "0.85em" })]
    #[.text s]

/-- The one-line label of a node: badges, pretty string, universe levels
(when the preset shows them) and the inferred type. -/
def nodeLabel (preset : ViewPreset) (n : XNode) : Array Html := Id.run do
  let mut parts : Array Html := #[]
  if n.highlighted then
    parts := parts.push diffBadge
  parts := parts.push (subtleText s!"{n.kind.name} ")
  if n.role == .instImplicit then
    parts := parts.push instBadge
  if n.isCoe then
    parts := parts.push coeBadge
  if n.isMData then
    parts := parts.push (subtleText "[mdata] ")
  parts := parts.push (.element "code" #[] #[.text n.pp])
  if preset.showsUniverses && !n.levels.isEmpty then
    parts := parts.push (subtleText s!".\{{String.intercalate ", " n.levels}}")
  if let some ty := n.type? then
    parts := parts.push (subtleText s!" : {ty}")
  if n.elided then
    parts := parts.push (subtleText " ⋯(depth limit)")
  return parts

/-- Render one node (and its preset-filtered descendants) as nested
`<details>`. Implicit/instance nodes are dimmed; leaves render as `<div>`. -/
partial def renderNode (preset : ViewPreset) (n : XNode) : Html :=
  let visible := n.children.filter (fun c => preset.showsRole c.role)
  let baseStyle := if n.role.isHidden then dimStyle else json% {}
  let style := if n.highlighted then baseStyle.mergeObj highlightStyle else baseStyle
  let label := nodeLabel preset n
  if visible.isEmpty then
    .element "div" #[("style", style)] label
  else
    .element "details" #[("open", Json.bool true), ("style", style)] <|
      #[.element "summary" #[] label] ++
      #[.element "div"
          #[("style", json% { "marginLeft": "1.2em",
                              "borderLeft": "1px solid rgba(128,128,128,0.35)",
                              "paddingLeft": "0.4em" })]
          (visible.map (renderNode preset))]

/-- Mark every node addressed by one of `paths` as `highlighted`.
Paths use diff numbering, which skips `mdata` wrappers: when descending
into an `mdata` node the remaining path is delegated to its child. -/
partial def markMismatches (n : XNode) (paths : List (List Nat)) : XNode :=
  if paths.isEmpty then n else
  let (here, deeper) := paths.partition (·.isEmpty)
  if n.kind == .mdata then
    -- transparent for diff paths
    { n with highlighted := n.highlighted || !here.isEmpty,
             children := n.children.map (markMismatches · paths) }
  else
    let children := n.children.mapIdx fun i c =>
      let sub := deeper.filterMap fun p => match p with
        | j :: rest => if j == i then some rest else Option.none
        | [] => Option.none
      markMismatches c sub
    { n with highlighted := n.highlighted || !here.isEmpty, children }

/-- A collapsible section wrapping arbitrary content. -/
def section' (title : String) (content : Array Html) (opened : Bool := false) : Html :=
  .element "details" #[("open", Json.bool opened)] <|
    #[.element "summary"
        #[("style", json% { "cursor": "pointer", "fontWeight": "600" })]
        #[.text title]] ++
    #[.element "div" #[("style", json% { "marginLeft": "0.8em" })] content]

/-- Selectable monospace text block (used for the `pp.explicit` section). -/
def preBlock (s : String) : Html :=
  .element "pre"
    #[("style", json% { "userSelect": "text", "whiteSpace": "pre-wrap",
                        "fontFamily": "var(--vscode-editor-font-family, monospace)",
                        "margin": "0.2em 0" })]
    #[.text s]

/-- Full single-expression view: the four preset trees (each in its own
collapsible section, `clean` open by default) plus a `pp.explicit`
section rendering `explicitTxt` (`pp.explicit`) and `explicitUnivTxt`
(`pp.explicit` + `pp.universes`) as selectable text. -/
def renderXRay (n : XNode) (explicitTxt explicitUnivTxt : String) : Html :=
  .element "div" #[] #[
    section' (ViewPreset.clean.label ++ " (explicit only)") #[renderNode .clean n] (opened := true),
    section' ViewPreset.withImplicit.label #[renderNode .withImplicit n],
    section' ViewPreset.withInstances.label #[renderNode .withInstances n],
    section' (ViewPreset.everything.label ++ " (with universes)") #[renderNode .everything n],
    section' "pp.explicit" #[
      preBlock explicitTxt,
      subtleText "with pp.universes:",
      preBlock explicitUnivTxt
    ]
  ]

/-- Compare mode: ranked mismatch summaries on top (each with its defeq
badge, plus the pinned all-defeq banner when every mismatch is
definitionally equal), then the two trees side by side (flex row) with
mismatch sites highlighted. Trees are shown with the `everything` preset
so instance/implicit mismatches are visible. -/
def renderCompare (l r : XNode) (ms : Array Mismatch) : Html :=
  let paths := ms.toList.map (·.path)
  let l := markMismatches l paths
  let r := markMismatches r paths
  let summaries : Array Html :=
    if ms.isEmpty then
      #[.element "li" #[] #[.text "no structural differences found"]]
    else
      ms.map fun m => .element "li" #[] #[defeqBadgeHtml m.defeq, .text m.describe]
  let banner : Array Html :=
    if allDefeq ms then
      #[.element "div"
          #[("style", json% { "color": "var(--vscode-charts-green, green)",
                              "fontWeight": "600" })]
          #[.text (allDefeqSummary ms.size)]]
    else #[]
  .element "div" #[] #[
    section' s!"mismatches ({ms.size}, ranked)"
      (banner ++
       #[.element "ul" #[("style", json% { "marginTop": "0.2em" })] summaries])
      (opened := true),
    .element "div"
      #[("style", json% { "display": "flex", "flexDirection": "row",
                          "gap": "1em", "alignItems": "flex-start" })]
      #[.element "div" #[("style", json% { "flex": "1", "minWidth": "0" })]
          #[subtleText "left", renderNode .everything l],
        .element "div" #[("style", json% { "flex": "1", "minWidth": "0" })]
          #[subtleText "right", renderNode .everything r]]
  ]

/-- Deterministic plain-text tree rendering (used by `#xray (text := true)`
so tests can pin exact output with `#guard_msgs`). One line per node:
`kind «pp» : type [tags]`, indented two spaces per level, children
filtered by `preset`. -/
partial def XNode.toText (n : XNode) (preset : ViewPreset := .everything)
    (indent : Nat := 0) : String := Id.run do
  let pad := "".pushn ' ' (indent * 2)
  let mut tags := ""
  unless n.role.tag.isEmpty do tags := tags ++ s!" {n.role.tag}"
  if n.isCoe then tags := tags ++ " ↑coe"
  if n.isMData then tags := tags ++ " [mdata]"
  if n.elided then tags := tags ++ " ⋯"
  if n.highlighted then tags := tags ++ " ≠"
  let levels := if preset.showsUniverses && !n.levels.isEmpty
    then s!".\{{String.intercalate ", " n.levels}}" else ""
  let ty := match n.type? with
    | some t => s!" : {t}"
    | none => " : ⟨type unknown⟩"
  let mut out := s!"{pad}{n.kind.name} «{n.pp}»{levels}{ty}{tags}"
  for c in n.children do
    if preset.showsRole c.role then
      out := out ++ "\n" ++ c.toText preset (indent + 1)
  return out

end ExprXRay
