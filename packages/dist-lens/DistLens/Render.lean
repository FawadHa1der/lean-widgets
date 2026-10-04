import DistLens.Model
import ProofWidgets.Data.Html

/-! # DistLens: rendering

Pure renderers over the ℚ models of `DistLens/Model.lean`:

* `Render.textReport` / `Render.filmTextReport` / `Render.chainTextReport` —
  deterministic multi-line ASCII reports, used by the `(text := true)` command
  modes and pinned exactly by `#guard_msgs` tests;
* `renderDistPanel` / `renderFilmPanel` / `renderChainPanel` — the InfoView
  HTML: themed SVG bar charts with exact fraction labels, a CDF staircase,
  expectation/variance tiles, bind/power filmstrips with diff badging, and a
  circular transition graph for chains.  All colors are VS Code theme
  variables with fallbacks.

React contract: every `style` attribute is built by the `css` helper (a Json
**object** with camelCased keys — a CSS string crashes the InfoView with
minified React error #62); `reactContractViolations` checks any `Html` tree
for violations and the test suite runs it over every real panel output.

Bar-chart geometry is exact: bar heights are `⌊w · chartH⌋` computed in ℚ.
The only floating point anywhere is the circular chain layout's `sin`/`cos`,
immediately rounded to whole pixels (the audited GraphScope pattern), so all
rendered output is byte-for-byte deterministic.
-/

namespace DistLens

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

/-- Hyphenated SVG presentation attributes that React rejects as props with
an "Invalid DOM property" warning, paired with the camelCase prop name React
wants (React itself renders the correct hyphenated SVG attribute to the
DOM, so output is unchanged).  Verified empirically against React 18 dev
builds: React warns for hyphenated SVG presentation attributes passed as
props — including all font/text presentation attributes on `<text>`
(`font-size`, `text-anchor`, `font-family`, `font-weight`); the camelCase
props render to the correct hyphenated SVG attributes in the DOM.  The only
hyphenated things that belong outside this list are `data-*`/`aria-*`
attributes (keys inside `style` objects are already camelCase). -/
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

/-- React-contract checker over an `Html` tree.  The InfoView passes
attributes straight through as React props, and React requires the `style`
prop to be a JSON *object* with camelCased keys — a raw CSS string crashes
the whole panel at runtime with minified React error #62.  Returns one
path-labeled entry for every element whose `style` value is not a
`Json.obj`, for any attribute literally named `class` (React wants
`className`), and for any hyphenated SVG presentation attribute in
`warnedSvgAttrs` (React warns "Invalid DOM property" and wants the
camelCase prop name).  Empty result ⇒ safe to hand to React. -/
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
        else if let some (_, camel) := warnedSvgAttrs.find? (·.1 == k) then
          [s!"{path}: hyphenated SVG attribute \"{k}\" — React wants camelCase \"{camel}\""]
        else []
      cs.foldl (init := here) fun acc c => acc ++ go path c
    | .component _ _ _ cs =>
      cs.foldl (init := []) fun acc c => acc ++ go s!"{path}/component" c

namespace Render

/-! ## Theme-aware colors -/

/-- Main foreground (labels, axis text). -/
def fgColor : String := "var(--vscode-editor-foreground, #333333)"
/-- Editor background (halos behind labels). -/
def bgColor : String := "var(--vscode-editor-background, #ffffff)"
/-- Bar fill. -/
def barColor : String := "var(--vscode-charts-blue, #3794ff)"
/-- Diff-badged ("new"/"changed") bar fill. -/
def newColor : String := "var(--vscode-charts-orange, #d18616)"
/-- CDF staircase stroke. -/
def cdfColor : String := "var(--vscode-charts-purple, #b180d7)"
/-- Secondary text (captions, muted labels). -/
def mutedColor : String := "var(--vscode-descriptionForeground, #717171)"
/-- Warning overlay text. -/
def warnColor : String := "var(--vscode-editorWarning-foreground, #bf8803)"
/-- Chain edge stroke. -/
def edgeColor : String := "var(--vscode-editorLineNumber-foreground, #888888)"

/-- Build a React-compatible style object.  React requires the style prop to
be a JSON OBJECT with camelCased property names — a CSS string crashes the
InfoView with React error #62, so never pass a string style. -/
def css (props : Array (String × String)) : Lean.Json :=
  Lean.Json.mkObj (props.toList.map fun (k, v) => (k, Lean.Json.str v))

/-- Shorthand for an element with string attributes.  Never pass a `style`
attribute through this helper (it coerces values to `Json.str`, violating
the React contract) — use `.element` with `css #[…]` instead. -/
def el (tag : String) (attrs : Array (String × String))
    (children : Array Html := #[]) : Html :=
  .element tag (attrs.map fun (k, v) => (k, .str v)) children

/-- An SVG `<text>` element (monospace, centered by default). -/
def textEl (x y : Nat) (fill : String) (content : String)
    (size : String := "11") (anchor : String := "middle") : Html :=
  el "text" #[("x", toString x), ("y", toString y), ("fill", fill),
      ("fontSize", size), ("textAnchor", anchor),
      ("fontFamily", "monospace")] #[.text content]

/-! ## Text reports -/

/-- Space-joined exact fractions: `"1/6 1/3 1/2"`. -/
def ratsLine (ws : Array Rat) : String :=
  " ".intercalate (ws.toList.map ratStr)

/-- `"dist: 6 outcomes over Fin 6"` (singular for one outcome). -/
def headerLine (d : DistModel) : String :=
  let noun := if d.size == 1 then "outcome" else "outcomes"
  s!"dist: {d.size} {noun} over {d.carrier}"

/-- `"moments: E[X] = 5/2, Var[X] = 35/12"`, or `none` when the carrier has
no canonical value map. -/
def momentsLine? (d : DistModel) : Option String := do
  let e ← d.expectation?
  let v ← d.variance?
  pure s!"moments: E[X] = {ratStr e}, Var[X] = {ratStr v}"

/-- Invariant-violation overlay lines (`warning: …`); empty when the model
passes its self-checks. -/
def warningLines (vs : Array String) : Array String :=
  vs.map (s!"warning: {·}")

/-- The full deterministic ASCII report of one distribution: header,
outcomes, weights, CDF, optional moments, then any invariant warnings. -/
def textReport (d : DistModel) : String :=
  let lines := #[headerLine d,
    "outcomes: " ++ " ".intercalate d.labels.toList,
    "weights: " ++ ratsLine d.weights,
    "cdf: " ++ ratsLine d.cdf]
    ++ (momentsLine? d).toArray
    ++ warningLines d.invariantViolations
  "\n".intercalate lines.toList

/-- The `#dist_film` ASCII report: one `== caption` block per frame, each
followed by that frame's full report. -/
def filmTextReport (f : FilmModel) : String :=
  "\n".intercalate <| f.frames.toList.map fun (caption, d) =>
    s!"== {caption}\n{textReport d}"

/-- `"stationary: unique"` / `"… non-unique (reducible chain)"` /
`"… inconsistent (extraction bug!)"`. -/
def stationaryLine : StationaryResult → String
  | .unique _ => "stationary: unique"
  | .nonUnique => "stationary: non-unique (reducible chain — the solution \
      space has dimension > 1; DistLens picks no representative)"
  | .inconsistent => "stationary: inconsistent (extraction bug!)"

/-- The `#chain` ASCII report: state count, matrix rows, stationary verdict
(and `π` when unique), optional power-iteration frames, then any invariant
warnings. -/
def chainTextReport (c : ChainModel) (frames : Array (Array Rat) := #[]) :
    String :=
  let rows := (Array.range c.matrix.size).map fun i =>
    s!"row {i}: {ratsLine c.matrix[i]!}"
  let stat := c.stationary
  let statLines := #[stationaryLine stat]
    ++ (match stat with
        | .unique π => #["π: " ++ ratsLine π]
        | _ => #[])
  let frameLines := (Array.range frames.size).map fun k =>
    s!"step {k}: {ratsLine frames[k]!}"
  let lines := #[s!"chain: {c.n} states"] ++ rows ++ statLines
    ++ frameLines ++ warningLines c.invariantViolations
  "\n".intercalate lines.toList

/-! ## Bar-chart SVG (exact ℚ geometry) -/

/-- Bar slot width in px. -/
def slotW : Nat := 44
/-- Bar width in px. -/
def barW : Nat := 30
/-- Chart height (the px height of weight 1). -/
def chartH : Nat := 120
/-- Horizontal margin. -/
def marginX : Nat := 10
/-- Top margin (room for the fraction label of a full bar). -/
def marginY : Nat := 14

/-- `⌊q · chartH⌋` clamped to `[0, chartH]` — exact ℚ scaling. -/
def barPx (q : Rat) : Nat :=
  let q := if q < 0 then 0 else if q > 1 then 1 else q
  ((q * chartH).floor).toNat

/-- Total SVG width for `n` bars. -/
def chartWidth (n : Nat) : Nat := 2 * marginX + n * slotW

/-- The bar chart: one bar per outcome with its exact fraction above and its
label below; `marks[i] = true` tints bar `i` with the diff color and is used
by the filmstrips.  Element order fixed for test pinning. -/
def barChart (d : DistModel) (marks : Array Bool := #[]) : Html := Id.run do
  let n := d.size
  let w := chartWidth n
  let h := marginY + chartH + 18
  let mut body : Array Html := #[]
  -- Baseline.
  body := body.push <| el "line"
    #[("x1", toString marginX), ("y1", toString (marginY + chartH)),
      ("x2", toString (w - marginX)), ("y2", toString (marginY + chartH)),
      ("stroke", mutedColor), ("strokeWidth", "1")]
  for i in [0:n] do
    let x := marginX + i * slotW + (slotW - barW) / 2
    let bh := barPx d.weights[i]!
    let y := marginY + chartH - bh
    let color := if marks[i]? == some true then newColor else barColor
    body := body.push <| el "rect"
      #[("x", toString x), ("y", toString y), ("width", toString barW),
        ("height", toString bh), ("fill", color),
        ("data-bar", toString i), ("data-weight", ratStr d.weights[i]!)]
    -- Exact fraction above the bar.
    body := body.push <| textEl (x + barW / 2) (y - 3) fgColor
      (ratStr d.weights[i]!) (size := "10")
    -- Outcome label below the baseline (index fallback keeps even a
    -- violating model renderable next to its warning overlay).
    body := body.push <| textEl (x + barW / 2) (marginY + chartH + 13)
      mutedColor (d.labels[i]?.getD (toString i)) (size := "10")
  return el "svg"
    #[("xmlns", "http://www.w3.org/2000/svg"), ("width", toString w),
      ("height", toString h), ("viewBox", s!"0 0 {w} {h}")] body

/-- The CDF staircase: a polyline through the exact partial sums, one
horizontal tread per outcome, with a dashed guide at mass 1. -/
def cdfChart (d : DistModel) : Html := Id.run do
  let n := d.size
  let w := chartWidth n
  let stairH : Nat := 80
  let h := 8 + stairH + 6
  let yOf (q : Rat) : Nat := 8 + stairH - (((if q > 1 then 1 else q) * stairH).floor).toNat
  let mut pts : Array String := #[s!"{marginX},{8 + stairH}"]
  let mut level : Rat := 0
  let cdf := d.cdf
  for i in [0:n] do
    let x0 := marginX + i * slotW
    let x1 := marginX + (i + 1) * slotW
    let c := cdf[i]!
    pts := pts.push s!"{x0},{yOf level}"
    pts := pts.push s!"{x0},{yOf c}"
    pts := pts.push s!"{x1},{yOf c}"
    level := c
  return el "svg"
    #[("xmlns", "http://www.w3.org/2000/svg"), ("width", toString w),
      ("height", toString h), ("viewBox", s!"0 0 {w} {h}")]
    #[el "line"
        #[("x1", toString marginX), ("y1", toString (yOf 1)),
          ("x2", toString (w - marginX)), ("y2", toString (yOf 1)),
          ("stroke", mutedColor), ("strokeWidth", "1"),
          ("strokeDasharray", "3 3")],
      el "polyline"
        #[("points", " ".intercalate pts.toList), ("fill", "none"),
          ("stroke", cdfColor), ("strokeWidth", "2"),
          ("data-cdf", ratsLine cdf)],
      textEl (w - marginX - 2) (yOf 1 - 3) mutedColor "cdf" (size := "9")
        (anchor := "end")]

/-- One stat tile (`E[X] = 5/2` etc.) as an inline block. -/
def tile (label value : String) : Html :=
  .element "div"
    #[("style", css #[("display", "inline-block"), ("border", "1px solid"),
        ("borderColor", mutedColor), ("borderRadius", "4px"),
        ("padding", "2px 8px"), ("marginRight", "6px"),
        ("fontFamily", "monospace"), ("fontSize", "12px")])]
    #[.text s!"{label} = {value}"]

/-- The moments row: `E[X]` and `Var[X]` tiles, or a muted note when the
carrier has no canonical ℚ value map. -/
def momentsBlock (d : DistModel) : Html :=
  match d.expectation?, d.variance? with
  | some e, some v =>
    .element "div" #[("style", css #[("marginTop", "4px")])]
      #[tile "E[X]" (ratStr e), tile "Var[X]" (ratStr v)]
  | _, _ =>
    .element "div"
      #[("style", css #[("marginTop", "4px"), ("fontSize", "11px"),
          ("color", warnColor)])]
      #[.text "no canonical ℚ value map for this carrier — E/Var omitted"]

/-- A single warning line. -/
def warnDiv (s : String) : Html :=
  .element "div"
    #[("style", css #[("color", warnColor), ("fontFamily", "monospace"),
        ("fontSize", "12px")])]
    #[.text s!"warning: {s}"]

/-- Header line as HTML. -/
def headerDiv (s : String) : Html :=
  .element "div"
    #[("style", css #[("fontFamily", "monospace"), ("fontSize", "13px"),
        ("marginBottom", "2px")])]
    #[.text s]

/-- A muted caption line. -/
def captionDiv (s : String) : Html :=
  .element "div"
    #[("style", css #[("color", mutedColor), ("fontFamily", "monospace"),
        ("fontSize", "12px"), ("marginTop", "6px")])]
    #[.text s]

end Render

/-! ## Panels -/

/-- The full `#dist` InfoView panel: header, invariant warnings (if any —
they flag extractor bugs), bar chart, CDF staircase, moments tiles, then the
verified-weight-goal suggestion rows (`mkSuggestion` is injected by the
widget layer, so this stays pure: it maps each suggestion's `example …`
source text to a row, typically a MakeEditLink). -/
def renderDistPanel (d : DistModel) (suggestions : Array String := #[])
    (mkSuggestion : String → Html := fun s => .text s) : Html := Id.run do
  let mut body : Array Html := #[Render.headerDiv (Render.headerLine d)]
  for v in d.invariantViolations do
    body := body.push (Render.warnDiv v)
  body := body.push (Render.barChart d)
  body := body.push (Render.cdfChart d)
  body := body.push (Render.momentsBlock d)
  if !suggestions.isEmpty then
    body := body.push (Render.captionDiv "verified weight goals (click to insert):")
    for s in suggestions do
      body := body.push <| Html.element "div"
        #[("style", Render.css #[("fontFamily", "monospace"),
            ("fontSize", "12px")])]
        #[mkSuggestion s]
  return .element "div"
    #[("style", Render.css #[("fontFamily", "sans-serif"),
        ("color", Render.fgColor)])] body

/-- The `#dist_film` panel: one captioned, diff-badged bar chart per frame.
Frame 0 is never badged; frame `i > 0` badges outcomes marked by
`FilmModel.marks` (new or changed weight vs the previous frame). -/
def renderFilmPanel (f : FilmModel) : Html := Id.run do
  let mut body : Array Html := #[]
  for i in [0:f.frames.size] do
    let (caption, d) := f.frames[i]!
    let marks := f.marks i
    let changed := (marks.filter id).size
    let suffix := if i == 0 || changed == 0 then "" else s!" ({changed} changed)"
    body := body.push (Render.captionDiv s!"{caption}{suffix}")
    for v in d.invariantViolations do
      body := body.push (Render.warnDiv v)
    body := body.push (Render.barChart d marks)
  return .element "div"
    #[("style", Render.css #[("fontFamily", "sans-serif"),
        ("color", Render.fgColor)])] body

/-! ### Chain layout (GraphScope's audited Float→px pattern) -/

namespace Render

/-- Side length of the chain-graph viewport, in px. -/
def chainViewSize : Nat := 300

/-- Round a nonnegative pixel coordinate to `Nat`. -/
def toPx (f : Float) : Nat := f.round.toUInt32.toNat

/-- Circular chain layout: state `i` of `n` at angle `2πi/n` clockwise from
12 o'clock.  Float only for the final pixel rounding (deterministic). -/
def chainPos (n i : Nat) : Nat × Nat :=
  let center := 150.0
  let radius := 110.0
  let θ := 6.283185307179586 * i.toFloat / n.toFloat
  (toPx (center + radius * θ.sin), toPx (center - radius * θ.cos))

/-- The transition graph: states on a circle, an edge per nonzero transition
labeled with its exact probability (self-loops as a ring above the state).
Edge labels sit at 1/3 of the way from source to target, so the two
directions of a bidirectional pair do not collide. -/
def chainGraph (c : ChainModel) : Html := Id.run do
  let n := c.n
  let mut body : Array Html := #[]
  -- Edges first (under the nodes).
  for i in [0:n] do
    for j in [0:n] do
      let p := (c.matrix[i]!)[j]!
      if p > 0 then
        let (x1, y1) := chainPos n i
        let (x2, y2) := chainPos n j
        if i == j then
          body := body.push <| el "circle"
            #[("cx", toString x1), ("cy", toString (y1 - 22)), ("r", "12"),
              ("fill", "none"), ("stroke", edgeColor),
              ("strokeWidth", "1.5"), ("data-loop", toString i)]
          body := body.push <| textEl x1 (y1 - 38) fgColor (ratStr p)
            (size := "10")
        else
          body := body.push <| el "line"
            #[("x1", toString x1), ("y1", toString y1),
              ("x2", toString x2), ("y2", toString y2),
              ("stroke", edgeColor), ("strokeWidth", "1.5"),
              ("data-edge", s!"{i}-{j}")]
          let lx := (2 * x1 + x2) / 3
          let ly := (2 * y1 + y2) / 3
          body := body.push <| el "text"
            #[("x", toString lx), ("y", toString (ly - 3)),
              ("fill", fgColor), ("fontSize", "10"),
              ("textAnchor", "middle"), ("fontFamily", "monospace"),
              ("stroke", bgColor), ("strokeWidth", "3"),
              ("paintOrder", "stroke"), ("data-plabel", s!"{i}-{j}")]
            #[.text (ratStr p)]
  -- Nodes.
  for i in [0:n] do
    let (x, y) := chainPos n i
    body := body.push <| el "circle"
      #[("cx", toString x), ("cy", toString y), ("r", "14"),
        ("fill", bgColor), ("stroke", fgColor), ("strokeWidth", "1.5"),
        ("data-state", toString i)]
    body := body.push <| textEl x (y + 4) fgColor (toString i)
  return el "svg"
    #[("xmlns", "http://www.w3.org/2000/svg"),
      ("width", toString chainViewSize), ("height", toString chainViewSize),
      ("viewBox", s!"0 0 {chainViewSize} {chainViewSize}")] body

end Render

/-- The `#chain` panel: transition graph, stationary verdict (with π bars
and per-state verification suggestions when unique), an optional
power-iteration filmstrip (diff-badged via `FilmModel.marks`), and any
invariant warnings. -/
def renderChainPanel (c : ChainModel) (film : FilmModel := ⟨#[]⟩)
    (suggestions : Array String := #[])
    (mkSuggestion : String → Html := fun s => .text s) : Html := Id.run do
  let mut body : Array Html := #[Render.headerDiv s!"chain: {c.n} states"]
  for v in c.invariantViolations do
    body := body.push (Render.warnDiv v)
  body := body.push (Render.chainGraph c)
  let stat := c.stationary
  body := body.push (Render.captionDiv (Render.stationaryLine stat))
  if let .unique π := stat then
    let d : DistModel :=
      { carrier := s!"Fin {c.n}"
        labels := (Array.range c.n).map toString
        weights := π }
    body := body.push (Render.barChart d)
    if !suggestions.isEmpty then
      body := body.push
        (Render.captionDiv "verify the stationary equations (click to insert):")
      for s in suggestions do
        body := body.push <| Html.element "div"
          #[("style", Render.css #[("fontFamily", "monospace"),
              ("fontSize", "12px")])]
          #[mkSuggestion s]
  for i in [0:film.frames.size] do
    let (caption, d) := film.frames[i]!
    let marks := film.marks i
    let changed := (marks.filter id).size
    let suffix := if i == 0 || changed == 0 then "" else s!" ({changed} changed)"
    body := body.push (Render.captionDiv s!"{caption}{suffix}")
    body := body.push (Render.barChart d marks)
  return .element "div"
    #[("style", Render.css #[("fontFamily", "sans-serif"),
        ("color", Render.fgColor)])] body

end DistLens
