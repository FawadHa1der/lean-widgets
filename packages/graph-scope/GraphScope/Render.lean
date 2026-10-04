import GraphScope.Algo
import GraphScope.Layout
import GraphScope.Layered
import ProofWidgets.Data.Html

/-! # GraphScope: rendering

Two pure renderers over `GraphData` (+ optional overlays):

* `Render.textReport` — a deterministic multi-line ASCII summary (adjacency,
  stats, overlays), used by `#graph_scope (text := true)` and pinned exactly by
  `#guard_msgs` tests;
* `renderPanel` — the InfoView HTML: a theme-aware SVG (BFS-layered layout for
  forests, circular otherwise, overridable via `LayoutMode`; labeled vertices,
  walk/highlight overlays) plus a stats block.  All colors are VS Code theme
  variables with fallbacks (`var(--vscode-…, #…)`), so the widget follows
  light/dark themes.  Vertex circles auto-grow (up to `r = 40`) so long
  `Repr`-derived labels fit, and labels carry a background-colored halo.

`htmlToDebugString` serializes any `Html` tree deterministically for tests.
-/

namespace GraphScope

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
expects (React converts it back to the correct hyphenated SVG attribute in the
DOM, so rendering is unchanged).  React warns for hyphenated SVG presentation
attributes passed as props — empirically including all font/text presentation
attributes on `<text>` (`font-size`, `text-anchor`, `font-family`,
`font-weight`); the camelCase props render to the correct hyphenated SVG
attributes with zero warnings.  `data-*`/`aria-*` attributes and style-object
keys are the only hyphenated things that legitimately stay hyphenated, so they
are deliberately absent here (style-object keys are already camelCase and
never hit this list anyway). -/
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
   ("font-size", "fontSize"),
   ("text-anchor", "textAnchor"),
   ("font-family", "fontFamily"),
   ("font-weight", "fontWeight")]

/-- React-contract checker over an `Html` tree (lives in the lib so both the
renderers and the test suite can use it).  The InfoView passes attributes
straight through as React props, and React requires the `style` prop to be a
JSON *object* with camelCased keys — a raw CSS string crashes the whole panel
at runtime with minified React error #62.  Returns one path-labeled entry for
every element whose `style` attribute value is not a `Json.obj`, for any
attribute literally named `class` (React wants `className`), and for any
hyphenated SVG presentation attribute in `warnedSvgAttrs` (React warns
"Invalid DOM property" and wants the camelCase spelling).  An empty result
means the tree is safe to hand to React. -/
partial def reactContractViolations : Html → List String :=
  go "root"
where
  go (path : String) : Html → List String
    | .text _ => []
    | .element tag attrs cs =>
      let path := s!"{path}/{tag}"
      let here := attrs.toList.flatMap fun (k, v) =>
        if k == "style" then
          match v with
          | .obj _ => []
          | _ => [s!"{path}: style attribute is not a Json object ({v.compress})"]
        else if k == "class" then
          [s!"{path}: attribute \"class\" should be \"className\""]
        else match warnedSvgAttrs.lookup k with
          | some camel =>
            [s!"{path}: hyphenated SVG attribute \"{k}\" — React wants camelCase \"{camel}\""]
          | none => []
      cs.foldl (init := here) fun acc c => acc ++ go path c
    | .component _ _ _ cs =>
      cs.foldl (init := []) fun acc c => acc ++ go s!"{path}/component" c

namespace Render

/-! ## Theme-aware colors

Every color is a VS Code CSS variable with an explicit fallback, so the SVG
adapts to the editor theme and still renders standalone. -/

/-- Main foreground (vertex outlines, labels, stats text). -/
def fgColor : String := "var(--vscode-editor-foreground, #333333)"
/-- Editor background (vertex fill). -/
def bgColor : String := "var(--vscode-editor-background, #ffffff)"
/-- Edge stroke. -/
def edgeColor : String := "var(--vscode-editorLineNumber-foreground, #888888)"
/-- Walk overlay (highlighted edges and step numbers). -/
def walkColor : String := "var(--vscode-charts-orange, #d18616)"
/-- Highlight-ring overlay. -/
def highlightColor : String := "var(--vscode-charts-purple, #b180d7)"
/-- Secondary text (captions, legend). -/
def mutedColor : String := "var(--vscode-descriptionForeground, #717171)"

/-- Shorthand for an element with string attributes.  Never pass a `style`
attribute through this helper: it coerces every value to `Json.str`, and a
string-valued `style` prop crashes the InfoView with React error #62 — use
`.element` with `css #[…]` for styles instead (enforced suite-wide by
`reactContractViolations` tests). -/
def el (tag : String) (attrs : Array (String × String)) (children : Array Html := #[]) :
    Html :=
  .element tag (attrs.map fun (k, v) => (k, .str v)) children

/-- Build a React-compatible style object. React requires the style prop to be
a JSON OBJECT with camelCased property names — a CSS string crashes the
InfoView with React error #62, so never pass a string style. -/
def css (props : Array (String × String)) : Lean.Json :=
  Lean.Json.mkObj (props.toList.map fun (k, v) => (k, Lean.Json.str v))

/-- An SVG `<text>` element (monospace, centered by default). -/
def textEl (x y : Nat) (fill : String) (content : String)
    (size : String := "11") (anchor : String := "middle") : Html :=
  el "text" #[("x", toString x), ("y", toString y), ("fill", fill),
      ("fontSize", size), ("textAnchor", anchor),
      ("fontFamily", "monospace")] #[.text content]

/-! ## Text report -/

/-- `"graph: 4 vertices, 3 edges"` (singular `vertex`/`edge` for count 1). -/
def headerLine (d : GraphData) : String :=
  let v := if d.n == 1 then "vertex" else "vertices"
  let e := if d.edgeCount == 1 then "edge" else "edges"
  s!"graph: {d.n} {v}, {d.edgeCount} {e}"

/-- `"edges: 0-1 1-2 2-3"` (or `"edges: (none)"`). -/
def edgesLine (d : GraphData) : String :=
  if d.edges.isEmpty then "edges: (none)"
  else "edges: " ++ " ".intercalate (d.edges.toList.map fun (a, b) => s!"{a}-{b}")

/-- `"labels: a, b, c"`, or `none` when all labels are the default indices. -/
def labelsLine? (d : GraphData) : Option String :=
  if d.labels == GraphData.defaultLabels d.n then none
  else some ("labels: " ++ ", ".intercalate d.labels.toList)

/-- `"degrees: 1 2 2 1 (min 1, max 2)"` (or `"degrees: (none)"`). -/
def degreesLine (d : GraphData) : String :=
  match d.minDegree?, d.maxDegree? with
  | some lo, some hi =>
    "degrees: " ++ " ".intercalate (d.degreeSequence.toList.map toString)
      ++ s!" (min {lo}, max {hi})"
  | _, _ => "degrees: (none)"

/-- `"components: 2 (disconnected)"` etc. -/
def componentsLine (d : GraphData) : String :=
  let status := if d.n == 0 then "empty" else if d.isConnected then "connected"
    else "disconnected"
  s!"components: {d.componentCount} ({status})"

/-- Render a vertex-index set as `\{0, 2, 4}`. -/
def indexSet (vs : Array Nat) : String :=
  "{" ++ ", ".intercalate (vs.toList.map toString) ++ "}"

/-- `"bipartite: yes (parts: {0, 2} / {1, 3})"` or
`"bipartite: no (odd cycle: 0-1-2)"`. -/
def bipartiteLine (d : GraphData) : String :=
  match d.bipartition with
  | .parts color =>
    let left := (Array.range d.n).filter fun i => color[i]! == false
    let right := (Array.range d.n).filter fun i => color[i]! == true
    s!"bipartite: yes (parts: {indexSet left} / {indexSet right})"
  | .oddCycle c =>
    "bipartite: no (odd cycle: " ++ "-".intercalate (c.toList.map toString) ++ ")"

/-- `"isolated: 3, 5"`, or `none` when there are no isolated vertices. -/
def isolatedLine? (d : GraphData) : Option String :=
  let iso := d.isolatedVertices
  if iso.isEmpty then none
  else some ("isolated: " ++ ", ".intercalate (iso.toList.map toString))

/-- `"walk: 0 → 1 → 2 (2 steps)"`. -/
def walkLine (w : Array Nat) : String :=
  let steps := w.size - 1
  let noun := if steps == 1 then "step" else "steps"
  "walk: " ++ " → ".intercalate (w.toList.map toString) ++ s!" ({steps} {noun})"

/-- `"highlight: 0, 2, 4"`. -/
def highlightLine (hs : Array Nat) : String :=
  "highlight: " ++ ", ".intercalate (hs.toList.map toString)

/-- The full deterministic ASCII report shown by `#graph_scope (text := true)`:
header, optional labels, edges, degrees, components, bipartiteness, optional
isolated vertices, then any overlay lines. -/
def textReport (d : GraphData) (walk? : Option (Array Nat) := none)
    (highlight? : Option (Array Nat) := none) : String :=
  let lines := #[headerLine d]
    ++ (labelsLine? d).toArray
    ++ #[edgesLine d, degreesLine d, componentsLine d, bipartiteLine d]
    ++ (isolatedLine? d).toArray
    ++ (walk?.map walkLine).toArray
    ++ (highlight?.map highlightLine).toArray
  "\n".intercalate lines.toList

/-! ## SVG -/

/-- Normalize an unordered pair to `(min, max)` for edge-set membership. -/
def normPair (a b : Nat) : Nat × Nat :=
  if a < b then (a, b) else (b, a)

/-- The set of edges traversed by a walk, normalized. -/
def walkEdges (w : Array Nat) : Array (Nat × Nat) :=
  (Array.range (w.size - 1)).map fun i => normPair w[i]! w[i+1]!

/-- Vertex circle radius in px: at least 13, auto-grown so the longest label
fits inside (labels render at 11px monospace, ≈ 7px per character, half of the
label on each side of the center, plus 4px padding), capped at 40 so a single
huge label cannot swallow the drawing.  Default index labels (≤ 2 chars up to
the 64-vertex cap) always yield the classic 13. -/
def vertexRadius (d : GraphData) : Nat :=
  d.labels.foldl (init := 13) fun r s =>
    Nat.max r (Nat.min 40 ((7 * s.length) / 2 + 4))

/-- The graph itself as SVG: edges (walk edges emphasized), walk step numbers,
highlight rings, then labeled vertex circles.  Element order is fixed so tests
can pin the serialized output.

`edgeWrap a b line` may wrap an edge's `<line>` (e.g. in a click-to-insert
link) and `vertexWrap i #[circle, label]` may wrap a vertex's circle + label
pair; both default to the identity, in which case the output is exactly the
classic display-only SVG. -/
def graphSvg (d : GraphData) (lay : Layout) (walk? : Option (Array Nat) := none)
    (highlight? : Option (Array Nat) := none)
    (edgeWrap : Nat → Nat → Html → Html := fun _ _ h => h)
    (vertexWrap : Nat → Array Html → Array Html := fun _ hs => hs) : Html := Id.run do
  let wEdges := (walk?.map walkEdges).getD #[]
  let r := vertexRadius d
  let mut body : Array Html := #[]
  -- Edges.
  for (a, b) in d.edges do
    let (x1, y1) := lay.pos a
    let (x2, y2) := lay.pos b
    let onWalk := wEdges.contains (a, b)
    body := body.push <| edgeWrap a b <| el "line"
      #[("x1", toString x1), ("y1", toString y1),
        ("x2", toString x2), ("y2", toString y2),
        ("stroke", if onWalk then walkColor else edgeColor),
        ("strokeWidth", if onWalk then "3" else "1.5"),
        ("data-edge", s!"{a}-{b}")]
  -- Walk step numbers at step-edge midpoints.
  if let some w := walk? then
    for i in [1:w.size] do
      let (x1, y1) := lay.pos w[i-1]!
      let (x2, y2) := lay.pos w[i]!
      body := body.push <| el "text"
        #[("x", toString ((x1 + x2) / 2)), ("y", toString ((y1 + y2) / 2 - 4)),
          ("fill", walkColor), ("fontSize", "10"), ("fontWeight", "bold"),
          ("textAnchor", "middle"), ("fontFamily", "monospace"),
          ("data-step", toString i)] #[.text (toString i)]
  -- Highlight rings (dedup, ascending).
  if let some hs := highlight? then
    for v in (Array.range d.n).filter (fun i => hs.contains i) do
      let (x, y) := lay.pos v
      body := body.push <| el "circle"
        #[("cx", toString x), ("cy", toString y), ("r", toString (r + 6)),
          ("fill", "none"), ("stroke", highlightColor), ("strokeWidth", "2.5"),
          ("data-ring", toString v)]
  -- Vertices with labels (labels get a background-colored halo via
  -- `paint-order:stroke`, so they stay legible over edge lines).
  for i in [0:d.n] do
    let (x, y) := lay.pos i
    body := body ++ vertexWrap i
      #[el "circle"
          #[("cx", toString x), ("cy", toString y), ("r", toString r),
            ("fill", bgColor), ("stroke", fgColor), ("strokeWidth", "1.5"),
            ("data-vertex", toString i)],
        el "text"
          #[("x", toString x), ("y", toString (y + 4)), ("fill", fgColor),
            ("fontSize", "11"), ("textAnchor", "middle"),
            ("fontFamily", "monospace"), ("stroke", bgColor),
            ("strokeWidth", "4"), ("paintOrder", "stroke")]
          #[.text (d.label i)]]
  return el "svg"
    #[("xmlns", "http://www.w3.org/2000/svg"),
      ("width", toString Layout.viewSize), ("height", toString Layout.viewSize),
      ("viewBox", s!"0 0 {Layout.viewSize} {Layout.viewSize}")]
    body

/-- One stats line as a `<div>`. -/
def statsDiv (color content : String) : Html :=
  .element "div" #[("style", css #[("color", color)])] #[.text content]

/-- The stats block: header, degrees, components, bipartiteness, isolated
vertices and overlay legend, all as text lines under the SVG.

`componentsInner?` may replace the *content* of the components line (e.g. by a
click-to-insert link around the same text) and `extra` appends further lines
at the end; with the defaults the output is exactly the classic stats block. -/
def statsBlock (d : GraphData) (walk? : Option (Array Nat) := none)
    (highlight? : Option (Array Nat) := none)
    (componentsInner? : Option Html := none)
    (extra : Array Html := #[]) : Html := Id.run do
  let componentsHtml : Html := match componentsInner? with
    | some inner => .element "div" #[("style", css #[("color", mutedColor)])] #[inner]
    | none => statsDiv mutedColor (componentsLine d)
  let mut lines : Array Html :=
    #[statsDiv fgColor (headerLine d),
      statsDiv mutedColor (degreesLine d),
      componentsHtml,
      statsDiv mutedColor (bipartiteLine d)]
  if let some iso := isolatedLine? d then
    lines := lines.push (statsDiv mutedColor iso)
  if let some w := walk? then
    lines := lines.push (statsDiv walkColor (walkLine w))
  if let some hs := highlight? then
    lines := lines.push (statsDiv highlightColor (highlightLine hs))
  lines := lines ++ extra
  return .element "div"
    #[("style", css #[("fontFamily", "monospace"), ("fontSize", "12px"),
        ("marginTop", "4px")])] lines

end Render

/-- The full InfoView panel: SVG on top, stats block below.  The layout is
chosen by `mode` — by default `.auto`: BFS-layered for forests, circular
otherwise (`LayoutMode.resolve`). -/
def renderPanel (d : GraphData) (walk? : Option (Array Nat) := none)
    (highlight? : Option (Array Nat) := none) (mode : LayoutMode := .auto) : Html :=
  let lay := mode.resolve d
  Html.element "div"
    #[("style", Render.css #[("fontFamily", "sans-serif"), ("color", Render.fgColor)])]
    #[Render.graphSvg d lay walk? highlight?,
      Render.statsBlock d walk? highlight?]

end GraphScope
