import HasseView.Layout
import ProofWidgets.Data.Html

/-! # HasseView: rendering

Two pure renderers over `PosetData` (+ optional overlays):

* `Render.textReport` — a deterministic multi-line ASCII summary (one line
  per rank from top to bottom, then the caption lines), used by
  `#hasse (text := true)` and pinned exactly by `#guard_msgs` tests;
* `renderPanel` — the InfoView HTML: a theme-aware SVG Hasse diagram
  (layered layout, minimal elements at the **bottom** per the classical
  convention — the renderer flips the layout's rank-increasing `y` axis),
  with rounded labeled node boxes, straight cover edges, ⊥/⊤ and
  atom/coatom badges, highlight rings and upset/downset shading, plus a
  caption block (lattice verdict with concrete witness, height, antichain
  lower bound, validity warnings in warning color).

All colors are VS Code theme variables with fallbacks
(`var(--vscode-…, #…)`), so the widget follows light/dark themes.  All
geometry arrives as integer-valued `Rat`s from `HasseView.Layout` and is
serialized exactly (`ratPx`); no floating point anywhere.

`htmlToDebugString` serializes any `Html` tree deterministically for tests;
`reactContractViolations` checks the React style contract (see its
docstring — a string-valued `style` prop crashes the InfoView).
-/

namespace HasseView

open ProofWidgets

/-- Deterministic serialization of an `Html` tree for tests:
`<tag k="v">children</tag>`; components render as
`<component:HASH props>…</component:HASH>` with their props JSON (encoded
against an empty `RpcObjectStore` — exact for plain-JSON props such as
`MakeEditLinkProps`), so tests can pin the edit texts links carry. -/
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
  | .component h _ props cs =>
    let body := cs.foldl (init := "") fun acc c => acc ++ htmlToDebugString c
    s!"<component:{h} {(props.run {}).1.compress}>{body}</component:{h}>"

/-- Hyphenated SVG presentation attributes that React warns about ("Invalid
DOM property") when passed as props, paired with the camelCase spellings it
wants instead (React converts them back to the correct hyphenated SVG
attribute in the DOM, so rendering is unchanged).  React warns for hyphenated
SVG presentation attributes passed as props — empirically including all
font/text presentation attributes on `<text>` (`font-size`, `text-anchor`,
`font-family`, `font-weight`).  The only hyphenated names that legitimately
stay hyphenated as props are `data-*`/`aria-*` attributes; keys inside
`style` objects are already camelCase and never appear here. -/
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
hyphenated SVG presentation attribute React warns about (`warnedSvgAttrs`,
e.g. `stroke-width` — React wants `strokeWidth`).  An empty result means the
tree is safe to hand to React. -/
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

/-! ## Theme-aware colors -/

/-- Main foreground (node outlines, labels, header text). -/
def fgColor : String := "var(--vscode-editor-foreground, #333333)"
/-- Editor background (node fill). -/
def bgColor : String := "var(--vscode-editor-background, #ffffff)"
/-- Cover-edge stroke. -/
def edgeColor : String := "var(--vscode-editorLineNumber-foreground, #888888)"
/-- Secondary text (caption lines). -/
def mutedColor : String := "var(--vscode-descriptionForeground, #717171)"
/-- ⊥/⊤ badge text. -/
def botTopColor : String := "var(--vscode-charts-blue, #3794ff)"
/-- Atom/coatom badge text. -/
def atomColor : String := "var(--vscode-charts-green, #89d185)"
/-- Validity warnings. -/
def warnColor : String := "var(--vscode-errorForeground, #f48771)"
/-- Highlight-ring overlay. -/
def highlightColor : String := "var(--vscode-charts-purple, #b180d7)"
/-- Upset shading (updown overlay). -/
def upsetColor : String := "var(--vscode-charts-green, #89d185)"
/-- Downset shading (updown overlay). -/
def downsetColor : String := "var(--vscode-charts-blue, #3794ff)"
/-- Focused element of the updown overlay. -/
def focusColor : String := "var(--vscode-charts-orange, #d18616)"

/-- Shorthand for an element with string attributes.  Never pass a `style`
attribute through this helper: it coerces every value to `Json.str`, and a
string-valued `style` prop crashes the InfoView with React error #62 — use
`.element` with `css #[…]` for styles instead (enforced suite-wide by
`reactContractViolations` tests). -/
def el (tag : String) (attrs : Array (String × String))
    (children : Array Html := #[]) : Html :=
  .element tag (attrs.map fun (k, v) => (k, .str v)) children

/-- Build a React-compatible style object.  React requires the style prop to
be a JSON OBJECT with camelCased property names — a CSS string crashes the
InfoView with React error #62, so never pass a string style. -/
def css (props : Array (String × String)) : Lean.Json :=
  Lean.Json.mkObj (props.toList.map fun (k, v) => (k, Lean.Json.str v))

/-- Serialize an exact pixel coordinate.  The layout guarantees integers
(all constants are even), so this is normally `toString q.num`; a
non-integer would honestly show as `num/den` (and fail the integrality
property test) instead of being rounded. -/
def ratPx (q : Rat) : String :=
  if q.den == 1 then toString q.num else s!"{q.num}/{q.den}"

/-! ## Shared caption / report lines -/

/-- Render index list as labels joined by `", "` (`"(none)"` if empty). -/
def labelList (d : PosetData) (is : Array Nat) : String :=
  if is.isEmpty then "(none)"
  else ", ".intercalate (is.toList.map d.label)

/-- `"poset: 8 elements, 12 cover edges"` (singular for count 1). -/
def headerLine (d : PosetData) : String :=
  let e := if d.n == 1 then "element" else "elements"
  let c := if d.coverCount == 1 then "cover edge" else "cover edges"
  s!"poset: {d.n} {e}, {d.coverCount} {c}"

/-- `"⊥ = ∅, ⊤ = \{0, 1, 2}"` (with `(none)` for a missing bound). -/
def boundsLine (d : PosetData) : String :=
  let b := (d.bot?.map d.label).getD "(none)"
  let t := (d.top?.map d.label).getD "(none)"
  s!"⊥ = {b}, ⊤ = {t}"

/-- `"atoms: \{0}, \{1}"`, only when `⊥` exists. -/
def atomsLine? (d : PosetData) : Option String :=
  if d.bot?.isSome then some s!"atoms: {labelList d d.atoms}" else none

/-- `"coatoms: …"`, only when `⊤` exists. -/
def coatomsLine? (d : PosetData) : Option String :=
  if d.top?.isSome then some s!"coatoms: {labelList d d.coatoms}" else none

/-- `"lattice ✓"`, or the concrete witness pair:
`"not a lattice: \{1}, \{2} have no join"`. -/
def latticeLine (d : PosetData) : String :=
  match d.latticeVerdict with
  | .lattice => "lattice ✓"
  | .noJoin a b => s!"not a lattice: {d.label a}, {d.label b} have no join"
  | .noMeet a b => s!"not a lattice: {d.label a}, {d.label b} have no meet"

/-- `"height: 3 (longest chain: 4 elements)"` — height counts cover steps. -/
def heightLine (d : PosetData) : String :=
  if d.n == 0 then "height: 0 (empty poset)"
  else
    let k := d.height + 1
    let e := if k == 1 then "element" else "elements"
    s!"height: {d.height} (longest chain: {k} {e})"

/-- `"antichain width ≥ 3 (largest rank layer; exact width not computed)"` —
honestly labeled as only a lower bound. -/
def antichainLine (d : PosetData) : String :=
  s!"antichain width ≥ {d.maxLayerSize} (largest rank layer; exact width not computed)"

/-- The validity warning lines: empty for a genuine partial order, otherwise
one summary line plus one line per violated axiom with the first concrete
counterexample (using labels) and the violation count. -/
def warningLines (d : PosetData) : Array String := Id.run do
  if d.isValidPoset then
    return #[]
  let mut out := #["warning: not a partial order — the diagram may be misleading"]
  let rv := d.reflexivityViolations
  if let some i := rv[0]? then
    let e := if rv.size == 1 then "element" else "elements"
    out := out.push
      s!"warning: not reflexive — {rv.size} {e} (e.g. ¬ {d.label i} ≤ {d.label i})"
  let av := d.antisymmetryViolations
  if let some (i, j) := av[0]? then
    let e := if av.size == 1 then "pair" else "pairs"
    out := out.push
      s!"warning: not antisymmetric — {av.size} {e} (e.g. {d.label i} ≤ {d.label j} and {d.label j} ≤ {d.label i})"
  let tv := d.transitivityViolations
  if let some (i, j, k) := tv[0]? then
    let e := if tv.size == 1 then "triple" else "triples"
    out := out.push
      s!"warning: not transitive — {tv.size} {e} (e.g. {d.label i} ≤ {d.label j} ≤ {d.label k} but ¬ {d.label i} ≤ {d.label k})"
  return out

/-- `"highlight: 0, 2"` (indices, matching the clause the user wrote). -/
def highlightLine (hs : Array Nat) : String :=
  "highlight: " ++ ", ".intercalate (hs.toList.map toString)

/-- The two updown legend lines:
`"upset of \{0}: \{0}, \{0, 1}"` / `"downset of \{0}: ∅, \{0}"`. -/
def updownLines (d : PosetData) (f : Nat) : Array String :=
  #[s!"upset of {d.label f}: {labelList d (d.upset f)}",
    s!"downset of {d.label f}: {labelList d (d.downset f)}"]

/-- One rank row of the text report: `"rank 2: \{0, 1}, \{0, 2}"`. -/
def rankLine (d : PosetData) (r : Nat) : String :=
  s!"rank {r}: {labelList d (d.layer r)}"

/-- The full deterministic ASCII report shown by `#hasse (text := true)`:
header, one line per rank from TOP (highest rank) to BOTTOM (rank 0, the
minimal elements — same vertical order as the drawing), then bounds, atoms,
coatoms, lattice verdict, height, antichain bound, validity warnings and any
overlay legend lines. -/
def textReport (d : PosetData) (highlight? : Option (Array Nat) := none)
    (updown? : Option Nat := none) : String :=
  let rankLines := if d.n == 0 then #[] else
    ((List.range (d.height + 1)).reverse.map (rankLine d ·)).toArray
  let lines := #[headerLine d]
    ++ rankLines
    ++ #[boundsLine d]
    ++ (atomsLine? d).toArray
    ++ (coatomsLine? d).toArray
    ++ #[latticeLine d, heightLine d, antichainLine d]
    ++ warningLines d
    ++ (highlight?.map highlightLine).toArray
    ++ ((updown?.map (updownLines d ·)).getD #[])
  "\n".intercalate lines.toList

/-! ## SVG -/

/-- Margin around the drawing, px. -/
def margin : Rat := 12

/-- Half the node box width. -/
def halfW : Rat := Layout.nodeW / 2
/-- Half the node box height. -/
def halfH : Rat := Layout.nodeH / 2

/-- Badges of element `i`: `⊥`/`⊤`, then `atom`/`coatom`. -/
def badges (d : PosetData) (i : Nat) : Array String := Id.run do
  let mut out := #[]
  if d.bot? == some i then out := out.push "⊥"
  if d.top? == some i then out := out.push "⊤"
  if d.atoms.contains i then out := out.push "atom"
  if d.coatoms.contains i then out := out.push "coatom"
  return out

/-- The Hasse diagram as SVG.  Element order is fixed (cover edges, highlight
rings, then node boxes with labels and badges) so tests can pin the
serialized output.  The layout's `y` grows with rank; here it is flipped
(`svgY = margin + height − y`) so rank 0 sits at the bottom. -/
def hasseSvg (d : PosetData) (l : PLayout)
    (highlight? : Option (Array Nat) := none) (updown? : Option Nat := none) :
    Html := Id.run do
  let svgW := l.width + 2 * margin
  let svgH := l.height + 2 * margin
  let cx := fun (i : Nat) => margin + (l.pos i).1
  let cy := fun (i : Nat) => margin + (l.height - (l.pos i).2)
  let upSet := (updown?.map (d.upset ·)).getD #[]
  let downSet := (updown?.map (d.downset ·)).getD #[]
  let mut body : Array Html := #[]
  -- Cover edges: from the top of the lower box to the bottom of the upper.
  for (a, b) in d.coverPairs do
    body := body.push <| el "line"
      #[("x1", ratPx (cx a)), ("y1", ratPx (cy a - halfH)),
        ("x2", ratPx (cx b)), ("y2", ratPx (cy b + halfH)),
        ("stroke", edgeColor), ("strokeWidth", "1.5"),
        ("data-cover", s!"{a}-{b}")]
  -- Highlight rings (dedup, ascending).
  if let some hs := highlight? then
    for i in (Array.range d.n).filter (hs.contains ·) do
      body := body.push <| el "rect"
        #[("x", ratPx (cx i - halfW - 4)), ("y", ratPx (cy i - halfH - 4)),
          ("width", ratPx (Layout.nodeW + 8)), ("height", ratPx (Layout.nodeH + 8)),
          ("rx", "9"), ("fill", "none"), ("stroke", highlightColor),
          ("strokeWidth", "2.5"), ("data-ring", toString i)]
  -- Node boxes, labels, badges.
  for i in [0:d.n] do
    let isFocus := updown? == some i
    let fillAttrs : Array (String × String) :=
      if isFocus then #[("fill", bgColor)]
      else if upSet.contains i then #[("fill", upsetColor), ("fillOpacity", "0.35")]
      else if downSet.contains i then #[("fill", downsetColor), ("fillOpacity", "0.35")]
      else #[("fill", bgColor)]
    body := body.push <| el "rect"
      (#[("x", ratPx (cx i - halfW)), ("y", ratPx (cy i - halfH)),
         ("width", ratPx Layout.nodeW), ("height", ratPx Layout.nodeH),
         ("rx", "6")] ++ fillAttrs ++
       #[("stroke", if isFocus then focusColor else fgColor),
         ("strokeWidth", if isFocus then "3" else "1.5"),
         ("data-node", toString i)])
    body := body.push <| el "text"
      #[("x", ratPx (cx i)), ("y", ratPx (cy i + 4)), ("fill", fgColor),
        ("fontSize", "11"), ("textAnchor", "middle"),
        ("fontFamily", "monospace"), ("stroke", bgColor),
        ("strokeWidth", "4"), ("paintOrder", "stroke")]
      #[.text (d.label i)]
    let bs := badges d i
    unless bs.isEmpty do
      let color := if bs.contains "⊥" || bs.contains "⊤" then botTopColor
        else atomColor
      body := body.push <| el "text"
        #[("x", ratPx (cx i)), ("y", ratPx (cy i - halfH - 3)),
          ("fill", color), ("fontSize", "9"), ("textAnchor", "middle"),
          ("fontFamily", "monospace"),
          ("data-badges", " ".intercalate bs.toList)]
        #[.text (" ".intercalate bs.toList)]
  return el "svg"
    #[("xmlns", "http://www.w3.org/2000/svg"),
      ("width", ratPx svgW), ("height", ratPx svgH),
      ("viewBox", s!"0 0 {ratPx svgW} {ratPx svgH}")]
    body

/-- One caption line as a `<div>`. -/
def captionDiv (color content : String) : Html :=
  .element "div" #[("style", css #[("color", color)])] #[.text content]

/-- The caption block under the SVG: header, bounds, atoms/coatoms, lattice
verdict, height, antichain bound, validity warnings (warning color) and
overlay legend lines. -/
def captionBlock (d : PosetData) (highlight? : Option (Array Nat) := none)
    (updown? : Option Nat := none) : Html := Id.run do
  let mut lines : Array Html :=
    #[captionDiv fgColor (headerLine d),
      captionDiv mutedColor (boundsLine d)]
  if let some a := atomsLine? d then
    lines := lines.push (captionDiv mutedColor a)
  if let some c := coatomsLine? d then
    lines := lines.push (captionDiv mutedColor c)
  lines := lines
    ++ #[captionDiv fgColor (latticeLine d),
         captionDiv mutedColor (heightLine d),
         captionDiv mutedColor (antichainLine d)]
  for w in warningLines d do
    lines := lines.push (captionDiv warnColor w)
  if let some hs := highlight? then
    lines := lines.push (captionDiv highlightColor (highlightLine hs))
  if let some f := updown? then
    for u in updownLines d f do
      lines := lines.push (captionDiv focusColor u)
  return .element "div"
    #[("style", css #[("fontFamily", "monospace"), ("fontSize", "12px"),
        ("marginTop", "4px")])] lines

end Render

/-- The full InfoView panel: layered Hasse SVG (minimal elements at the
bottom) on top, caption block below.  This is exactly the `Html` the `#hasse`
command hands to `Widget.savePanelWidgetInfo`, so the React-contract tests
run over it. -/
def renderPanel (d : PosetData) (highlight? : Option (Array Nat) := none)
    (updown? : Option Nat := none) : Html :=
  let l := layoutPoset d
  Html.element "div"
    #[("style", Render.css #[("fontFamily", "sans-serif"), ("color", Render.fgColor)])]
    #[Render.hasseSvg d l highlight? updown?,
      Render.captionBlock d highlight? updown?]

end HasseView
