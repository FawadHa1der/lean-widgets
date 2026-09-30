import TreeScope.Layout
import ProofWidgets.Data.Html

/-! # TreeScope: theme-aware SVG rendering

Pure renderers over `TreeView` / `TreeLayout`:

* `renderPanel` — the InfoView HTML for one tree: an SVG (rounded-rect nodes
  with label, sublabel and badges; edges from parent bottom to child top),
  a legend row for the tones present, and a stats line;
* `renderForest` — a grid of several trees (`gridLayout`), used by the
  stage-2 Catalan gallery;
* `Render.textReport` — header + deterministic ASCII rendering, used by
  `#tree_scope (text := true)` and pinned exactly by `#guard_msgs` tests.

Every color is a VS Code theme variable with a fallback
(`var(--vscode-…, #…)`), so the widget follows light/dark themes.  The tone →
color mapping is a fixed, tested table (`toneStroke`/`toneFill`/`toneRing?`).
All coordinates come from the exact `Rat` layout, serialized by `ratStr`
(decimal, truncated at 6 fractional digits — exact for the dyadic rationals
the layout produces in practice); the output is byte-for-byte deterministic.

`htmlToDebugString` serializes any `Html` tree deterministically for tests
(same serializer as the sibling GraphScope package).
-/

namespace TreeScope

open ProofWidgets

/-- Deterministic serialization of an `Html` tree for tests:
`<tag k="v">children</tag>`; components render as `<component:HASH>`. -/
partial def htmlToDebugString : Html → String
  | .text s => s
  | .element tag attrs cs =>
    let attrStr := attrs.foldl (init := "") fun acc (k, v) =>
      let vs := match v with
        | .str s => s
        | j => j.compress
      acc ++ s!" {k}=\"{vs}\""
    let body := cs.foldl (init := "") fun acc c => acc ++ htmlToDebugString c
    s!"<{tag}{attrStr}>{body}</{tag}>"
  | .component h _ _ cs =>
    let body := cs.foldl (init := "") fun acc c => acc ++ htmlToDebugString c
    s!"<component:{h}>{body}</component:{h}>"

/-- Hyphenated SVG presentation attributes that React rejects as props with an
"Invalid DOM property" warning, paired with the camelCase spelling React
expects (React converts it back to the hyphenated SVG attribute in the DOM, so
rendering is unchanged).  React warns for *all* hyphenated SVG presentation
attributes passed as props — verified empirically to include every font/text
presentation attribute on `<text>` (`text-anchor`, `font-family`, `font-size`,
`font-weight`); an earlier claim that React whitelists those four was an
artifact of React's global warning dedup and is false.  The camelCase props
render to the correct hyphenated SVG attributes in the DOM.  The only
hyphenated names that belong on elements as-is are `data-*`/`aria-*`
attributes; keys inside `style` objects are already camelCase and never appear
here. -/
def warnedSvgAttrs : List (String × String) :=
  [("stroke-width", "strokeWidth"),
   ("stroke-dasharray", "strokeDasharray"),
   ("fill-opacity", "fillOpacity"),
   ("paint-order", "paintOrder"),
   ("dominant-baseline", "dominantBaseline"),
   ("stroke-linecap", "strokeLinecap"),
   ("stroke-linejoin", "strokeLinejoin"),
   ("stroke-opacity", "strokeOpacity"),
   ("letter-spacing", "letterSpacing"),
   ("clip-path", "clipPath"),
   ("fill-rule", "fillRule"),
   ("text-anchor", "textAnchor"),
   ("font-family", "fontFamily"),
   ("font-size", "fontSize"),
   ("font-weight", "fontWeight")]

/-- React contract check.  The InfoView passes `Html` attributes straight to
React as props, so every `style` attribute value must be a JSON *object* with
camelCased property names — a raw CSS string crashes the whole panel at
runtime with React error #62 (compile-time tests never run React, which is
how a string style can slip through) — the attribute name `class` is
flagged too (React expects `className`), and so is every hyphenated SVG
presentation attribute in `warnedSvgAttrs` (React warns "Invalid DOM
property" and wants the camelCase prop name).  Returns one path-labeled entry
per violating element (`r`, `r.0.1`, … from the root); the render tests run
this over every real top-level panel output and assert the list is empty. -/
partial def reactContractViolations (h : Html) : List String :=
  go "r" h
where
  /-- Collect violations below `h`, labeling entries with the dotted
  child-index path `path`. -/
  go (path : String) : Html → List String
    | .text _ => []
    | .element tag attrs cs =>
      let bad := attrs.toList.filterMap fun (k, v) =>
        if k == "style" then
          match v with
          | .obj _ => none
          | _ => some s!"{path}<{tag}>: style is not a Json object: {v.compress}"
        else if k == "class" then
          some s!"{path}<{tag}>: attribute 'class' (React expects className)"
        else if let some (_, camel) := warnedSvgAttrs.find? (·.1 == k) then
          some s!"{path}<{tag}>: hyphenated SVG attribute {k} — React wants camelCase {camel}"
        else none
      bad ++ (cs.toList.zipIdx.flatMap fun (c, i) => go s!"{path}.{i}" c)
    | .component _ _ _ cs =>
      cs.toList.zipIdx.flatMap fun (c, i) => go s!"{path}.{i}" c

namespace Render

/-! ## Exact-to-decimal serialization -/

/-- Render an exact `Rat` as a decimal string: integer part, then up to 6
fractional digits by long division, trailing zeros stripped (`38 → "38"`,
`77/2 → "38.5"`).  Truncation after 6 digits is deterministic; the layout
only produces dyadic rationals, which are exact well within 6 digits for any
tree TreeScope will draw. -/
def ratStr (q : Rat) : String := Id.run do
  let sign := if q.num < 0 then "-" else ""
  let n := q.num.natAbs
  let d := q.den
  let ip := n / d
  let mut r := n % d
  let mut digits : Array Nat := #[]
  for _ in [0:6] do
    if r == 0 then break
    r := r * 10
    digits := digits.push (r / d)
    r := r % d
  -- Strip trailing zeros (can arise from truncation of non-dyadic input).
  while digits.back? == some 0 do
    digits := digits.pop
  if digits.isEmpty then return s!"{sign}{ip}"
  return s!"{sign}{ip}." ++ digits.foldl (fun acc k => acc ++ toString k) ""

/-! ## Theme-aware colors

Every color is a VS Code CSS variable with an explicit fallback, so the SVG
adapts to the editor theme and still renders standalone. -/

/-- Main foreground (neutral node outlines, labels, stats text). -/
def fgColor : String := "var(--vscode-editor-foreground, #333333)"
/-- Editor background (node fill; also the label color on filled black nodes). -/
def bgColor : String := "var(--vscode-editor-background, #ffffff)"
/-- Edge stroke. -/
def edgeColor : String := "var(--vscode-editorLineNumber-foreground, #888888)"
/-- Red-tone color (`rbRed` outlines, `violation` outlines and rings). -/
def redColor : String := "var(--vscode-charts-red, #e51400)"
/-- Green-tone color (`ok` outlines, `added` outlines and rings). -/
def greenColor : String := "var(--vscode-charts-green, #388a34)"
/-- Highlight-tone color. -/
def purpleColor : String := "var(--vscode-charts-purple, #b180d7)"
/-- Secondary text (sublabels, badges, legend, stats). -/
def mutedColor : String := "var(--vscode-descriptionForeground, #717171)"

/-! ## The tone → color table (pinned by RenderTests, one test per tone) -/

/-- Outline color of a node. -/
def toneStroke : NodeTone → String
  | .neutral => fgColor
  | .rbRed => redColor
  | .rbBlack => fgColor
  | .ok => greenColor
  | .violation => redColor
  | .highlight => purpleColor
  | .added => greenColor

/-- Fill color of a node: `rbBlack` is a filled dark node (theme foreground as
fill — dark in light themes, light in dark themes), everything else uses the
editor background. -/
def toneFill : NodeTone → String
  | .rbBlack => fgColor
  | _ => bgColor

/-- Label color on a node (inverted on filled `rbBlack` nodes). -/
def toneText : NodeTone → String
  | .rbBlack => bgColor
  | _ => fgColor

/-- Ring color around a node, when the tone draws one: red for `violation`,
green for `added`. -/
def toneRing? : NodeTone → Option String
  | .violation => some redColor
  | .added => some greenColor
  | _ => none

/-! ## Text report -/

/-- `"tree: 5 nodes, depth 3"` (structural counts, including collapsed-away
descendants). -/
def headerLine (t : TreeView) : String :=
  s!"tree: {t.size} nodes, depth {t.depth}"

/-- Path attribute/caption value: `"r"` for the root, `"r.0.1"` for
descendants (also used by the SVG `data-node`/`data-edge` attributes). -/
def pathStr (p : Array Nat) : String :=
  "r" ++ p.foldl (fun acc i => acc ++ s!".{i}") ""

/-! ## Invariant caption

Semantic instances (stage 2) mark invariant-violating nodes with
`NodeTone.violation` plus a badge naming the broken invariant (`red-red`,
`bh`, `ord`, `heap`, …).  The caption summarizes them generically: it lists
every violating node's path and badges, or reports `invariants ok` for trees
that carry checked tones (`rbRed`/`rbBlack`/`ok`) without violations.  Plain
neutral trees (e.g. reflection output) get no caption at all. -/

/-- One caption entry per `violation`-toned node, in preorder:
`"r.0.1 (red-red|bh)"` (path only when the node has no badges).  A violation
sitting inside a *collapsed* subtree is still listed — invariant breaks must
never be silently hidden — but is marked `[hidden]` because the SVG only
draws the collapsed ancestor's `+N hidden` stub, not the node itself. -/
def violationEntries (t : TreeView) : Array String :=
  t.preorderPaths.filterMap fun p => do
    let n ← t.get? p
    if n.tone == .violation then
      let hidden := (List.range p.size).any fun k =>
        (t.get? (p.take k)).any (·.collapsed)
      some <| pathStr p ++
        (if n.badges.isEmpty then "" else s!" ({"|".intercalate n.badges.toList})") ++
        (if hidden then " [hidden]" else "")
    else none

/-- The invariant caption of a tree (see the section docstring):
`"⚠ entry, entry, …"`, `"invariants ok"`, or `none` for plain trees. -/
def healthCaption? (t : TreeView) : Option String :=
  let vs := violationEntries t
  if vs.isEmpty then
    if t.hasTone .rbRed || t.hasTone .rbBlack || t.hasTone .ok then
      some "invariants ok"
    else none
  else some ("⚠ " ++ ", ".intercalate vs.toList)

/-- The full deterministic report shown by `#tree_scope (text := true)`:
header line, the ASCII rendering, then the invariant caption when one exists. -/
def textReport (t : TreeView) : String :=
  headerLine t ++ "\n" ++ t.ascii
    ++ (match healthCaption? t with | some c => "\n" ++ c | none => "")

/-! ## SVG -/

/-- Build a React-compatible style object. React requires the style prop to be
a JSON OBJECT with camelCased property names — a CSS string crashes the
InfoView with React error #62, so never pass a string style. -/
def css (props : Array (String × String)) : Lean.Json :=
  Lean.Json.mkObj (props.toList.map fun (k, v) => (k, Lean.Json.str v))

/-- Shorthand for an element with string attributes.  Never pass a `style`
attribute through this helper — it would arrive as a string; build style
attributes with `css` and `Html.element` instead. -/
def el (tag : String) (attrs : Array (String × String)) (children : Array Html := #[]) :
    Html :=
  .element tag (attrs.map fun (k, v) => (k, .str v)) children

/-- An SVG `<text>` element (monospace, centered by default). -/
def textEl (x y : Rat) (fill : String) (content : String)
    (size : String := "11") (anchor : String := "middle")
    (extraAttrs : Array (String × String) := #[]) : Html :=
  el "text" (#[("x", ratStr x), ("y", ratStr y), ("fill", fill),
      ("fontSize", size), ("textAnchor", anchor),
      ("fontFamily", "monospace")] ++ extraAttrs) #[.text content]

/-- The badges of a node as drawn: a `⚠` is appended automatically on
`violation` nodes. -/
def displayBadges (pn : PlacedNode) : Array String :=
  if pn.tone == .violation then pn.badges.push "⚠" else pn.badges

/-- The SVG elements of one placed node: optional tone ring, the rounded rect
(dashed when collapsed), then label / sublabel / badges.  Collapsed nodes show
`+N hidden` as their sublabel line. -/
def nodeSvg (pn : PlacedNode) : Array Html := Id.run do
  let mut out : Array Html := #[]
  if let some ringColor := toneRing? pn.tone then
    out := out.push <| el "rect"
      #[("x", ratStr (pn.x - Layout.nodeW / 2 - 3)),
        ("y", ratStr (pn.y - Layout.nodeH / 2 - 3)),
        ("width", ratStr (Layout.nodeW + 6)), ("height", ratStr (Layout.nodeH + 6)),
        ("rx", "8"), ("fill", "none"), ("stroke", ringColor),
        ("strokeWidth", "2"), ("data-ring", pn.tone.name)]
  let mut rectAttrs :=
    #[("x", ratStr (pn.x - Layout.nodeW / 2)), ("y", ratStr (pn.y - Layout.nodeH / 2)),
      ("width", ratStr Layout.nodeW), ("height", ratStr Layout.nodeH),
      ("rx", "6"), ("fill", toneFill pn.tone), ("stroke", toneStroke pn.tone),
      ("strokeWidth", "1.5"), ("data-node", pathStr pn.path)]
  if pn.collapsed then
    rectAttrs := rectAttrs.push ("strokeDasharray", "4 2")
    rectAttrs := rectAttrs.push ("data-collapsed", toString pn.hidden)
  out := out.push (el "rect" rectAttrs)
  -- Label, and a second line for the sublabel (collapsed stubs show the count).
  let sub? : Option String :=
    if pn.collapsed then some s!"+{pn.hidden} hidden" else pn.sublabel
  match sub? with
  | none =>
    out := out.push (textEl pn.x (pn.y + 4) (toneText pn.tone) pn.label)
  | some sub =>
    out := out.push (textEl pn.x (pn.y - 2) (toneText pn.tone) pn.label)
    out := out.push (textEl pn.x (pn.y + 12) (if pn.tone == .rbBlack then bgColor else mutedColor)
      sub (size := "9"))
  let badges := displayBadges pn
  unless badges.isEmpty do
    out := out.push <| textEl (pn.x + Layout.nodeW / 2 - 2) (pn.y - Layout.nodeH / 2 - 4)
      mutedColor (" ".intercalate badges.toList) (size := "9") (anchor := "end")
      (extraAttrs := #[("data-badges", "|".intercalate badges.toList)])
  return out

/-- All SVG elements of a laid-out tree: first every edge (parent bottom
center → child top center, preorder parent order), then every node (preorder).
Element order is fixed so tests can pin the serialized output. -/
def treeSvgBody (l : TreeLayout) : Array Html := Id.run do
  let mut out : Array Html := #[]
  for pn in l.nodes do
    for i in [0:pn.childCount] do
      if let some c := l.at? (pn.path.push i) then
        out := out.push <| el "line"
          #[("x1", ratStr pn.x), ("y1", ratStr (pn.y + Layout.nodeH / 2)),
            ("x2", ratStr c.x), ("y2", ratStr (c.y - Layout.nodeH / 2)),
            ("stroke", edgeColor), ("strokeWidth", "1.5"),
            ("data-edge", pathStr c.path)]
  for pn in l.nodes do
    out := out ++ nodeSvg pn
  return out

/-- Padding around the drawing inside the SVG viewport, px. -/
def pad : Rat := 8

/-- An `<svg>` viewport of the given content bounds (plus padding), with the
body translated by the padding. -/
def svgViewport (width height : Rat) (body : Array Html) : Html :=
  el "svg"
    #[("xmlns", "http://www.w3.org/2000/svg"),
      ("width", ratStr (width + 2 * pad)), ("height", ratStr (height + 2 * pad)),
      ("viewBox", s!"0 0 {ratStr (width + 2 * pad)} {ratStr (height + 2 * pad)}")]
    #[el "g" #[("transform", s!"translate({ratStr pad} {ratStr pad})")] body]

/-- One tree as a complete SVG. -/
def treeSvg (t : TreeView) : Html :=
  let l := layoutTree t
  svgViewport l.width l.height (treeSvgBody l)

/-- The tones (beyond `neutral`) present anywhere in the tree, in the fixed
`NodeTone.all` order. -/
def presentTones (t : TreeView) : Array NodeTone :=
  NodeTone.all.filter fun tn => tn != .neutral && t.hasTone tn

/-- Legend row for the tones present in the tree (`none` when the tree is all
neutral): one colored `■ name` entry per tone, in fixed order. -/
def legendRow? (t : TreeView) : Option Html :=
  let tones := presentTones t
  if tones.isEmpty then none
  else some <| .element "div"
    #[("style", css #[("fontFamily", "monospace"), ("fontSize", "11px"), ("marginTop", "2px")])]
    (tones.map fun tn =>
      .element "span"
        #[("style", css #[("color", toneStroke tn), ("marginRight", "10px")]),
          ("data-legend", .str tn.name)]
        #[.text s!"■ {tn.name}"])

/-- Stats line under the SVG. -/
def statsRow (t : TreeView) : Html :=
  .element "div"
    #[("style", css #[("fontFamily", "monospace"), ("fontSize", "12px"),
        ("color", mutedColor), ("marginTop", "2px")])]
    #[.text (headerLine t)]

/-- Invariant caption row under the SVG (`healthCaption?`); `none` for plain
trees.  Violation captions are drawn in the red tone, `invariants ok` in the
green tone. -/
def captionRow? (t : TreeView) : Option Html :=
  (healthCaption? t).map fun c =>
    let color := if (violationEntries t).isEmpty then greenColor else redColor
    .element "div"
      #[("style", css #[("fontFamily", "monospace"), ("fontSize", "11px"),
          ("color", color), ("marginTop", "2px")]),
        ("data-caption", .str c)]
      #[.text c]

end Render

/-- The full InfoView panel for one tree: SVG, then the legend row (when any
non-neutral tone is present), the invariant caption (when one exists), then
the stats line. -/
def renderPanel (t : TreeView) : Html :=
  .element "div"
    #[("style", Render.css #[("fontFamily", "sans-serif"), ("color", Render.fgColor)])]
    (#[Render.treeSvg t] ++ (Render.legendRow? t).toArray
      ++ (Render.captionRow? t).toArray ++ #[Render.statsRow t])

/-- A grid of several trees as one SVG (`gridLayout` packing): each tree's
body sits in a translated `<g>` tagged with `data-cell`. -/
def renderForest (ts : Array TreeView) (maxRowWidth : Rat := 640) : Html :=
  let g := gridLayout ts maxRowWidth
  Render.svgViewport g.width g.height <|
    g.cells.map fun c =>
      Render.el "g"
        #[("transform", s!"translate({Render.ratStr c.offsetX} {Render.ratStr c.offsetY})"),
          ("data-cell", toString c.index)]
        (Render.treeSvgBody c.layout)

end TreeScope
