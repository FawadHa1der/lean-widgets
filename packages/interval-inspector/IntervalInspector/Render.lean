import IntervalInspector.Layout
import ProofWidgets.Data.Html

/-! # Interval Inspector: SVG rendering

Pure `ProofWidgets.Html` SVG output (no custom JavaScript): a horizontal axis with
labeled endpoint ticks, one colored bar per interval leaf, endpoint glyphs
(**filled circle = closed/included, hollow circle = open/excluded** — tested
convention), stacked aligned rows for the two sides of `⊆` / `⊂` / `=` shapes, red
"mismatch candidate" shading for regions provably covered by the LHS but not provably
by the RHS (only when the order graph totally orders all endpoints), and an
"order unknown" caption instead of a guess when it does not.

All colors are VS Code theme CSS variables with hex fallbacks
(`var(--vscode-charts-blue, #3b82f6)` and friends), so the drawing follows the
user's light/dark InfoView theme.

All coordinates are computed in `Rat` and emitted as integers, so the output string is
fully deterministic; `Html.toDebugString` serializes it for tests.
-/

namespace IntervalInspector

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

/-- Convenience alias for the serializer. -/
def Html.toDebugString (h : Html) : String := htmlToDebugString h

/-- Hyphenated SVG presentation attributes that React warns about when passed as
props ("Invalid DOM property"), paired with the camelCase spelling React wants
(React converts it back to the correct hyphenated SVG attribute in the DOM, so
rendering is unchanged).  Verified empirically against React 18 dev builds:
React warns for hyphenated SVG presentation attributes passed as props —
empirically including all font/text presentation attributes on `<text>`
(`font-size`, `text-anchor`, `font-family`, `font-weight`); the camelCase props
render to the correct hyphenated SVG attributes in the DOM with no warning
(e.g. `fontSize="10"` produces `font-size="10"`).  The only hyphenated things
that belong outside this table are `data-*`/`aria-*` attributes.
Keys inside `style` JSON objects are unaffected (already camelCase, see `css`). -/
def warnedHyphenatedSvgAttrs : List (String × String) :=
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

/-- Permanent React-contract check (see `Render.css`): walk an `Html` tree and
return a path-labeled entry for every element whose `style` attribute value is
*not* a JSON object (React crashes on string styles — minified error #62 — taking
the whole InfoView panel down), for every attribute literally named `class`
(React wants `className`), and for every hyphenated SVG presentation attribute
React warns about (`warnedHyphenatedSvgAttrs`; React wants the camelCase
spelling).  Tests run this over the real top-level panel outputs and assert the
result is empty. -/
partial def reactContractViolations (h : Html) (path : String := "root") : List String :=
  match h with
  | .text _ => []
  | .element tag attrs cs =>
    let here := s!"{path}/{tag}"
    let own := attrs.toList.filterMap fun (k, v) =>
      if k == "style" then
        match v with
        | .obj _ => none
        | _ => some s!"{here}: style attribute is not a Json object ({v.compress})"
      else if k == "class" then
        some s!"{here}: attribute \"class\" (React requires className)"
      else if let some (_, camel) := warnedHyphenatedSvgAttrs.find? (·.1 == k) then
        some s!"{here}: hyphenated SVG attribute \"{k}\" — React wants camelCase \"{camel}\""
      else none
    own ++ (cs.zipIdx.toList.flatMap fun (c, i) =>
      reactContractViolations c s!"{here}[{i}]")
  | .component _ _ _ cs =>
    cs.zipIdx.toList.flatMap fun (c, i) =>
      reactContractViolations c s!"{path}/component[{i}]"

namespace Render

/-- Total SVG width in px. -/
def width : Int := 560
/-- Horizontal margin: `x = 0` maps to this px position. -/
def margin : Int := 40
/-- Plot width: `x = 1` maps to `margin + plotW`. -/
def plotW : Int := 480

/-- Map a layout coordinate in `[0,1]` to an integer pixel x-position. -/
def px (q : Rat) : Int :=
  let s := q * (plotW : Rat)
  margin + s.num / (s.den : Int)

/-- Wrap a VS Code CSS variable with a fallback: `var(--vscode-NAME, FALLBACK)`.
The InfoView is a VS Code webview, so `--vscode-*` theme variables are available;
the fallback hex keeps the SVG legible when the variable is absent. -/
def themed (name fallback : String) : String := s!"var(--vscode-{name}, {fallback})"

/-- Bar / accent color of the left-hand side (and of single-row shapes). -/
def lhsColor : String := themed "charts-blue" "#3b82f6"
/-- Bar / accent color of the right-hand side. -/
def rhsColor : String := themed "charts-green" "#10b981"
/-- Color of the membership marker. -/
def memColor : String := themed "charts-purple" "#8b5cf6"
/-- Color of mismatch-candidate shading. -/
def mismatchColor : String := themed "charts-red" "#ef4444"
/-- Color of unordered-atom labels and warning captions. -/
def warnColor : String := themed "charts-yellow" "#f59e0b"
/-- Foreground for the axis, tick labels and informational captions. -/
def fgColor : String := themed "editor-foreground" "#333333"
/-- Axis color. -/
def axisColor : String := fgColor
/-- Fill of hollow (open-endpoint) glyphs: the theme's background. -/
def openFill : String := themed "editor-background" "#ffffff"
/-- Muted color for provenance badges. -/
def mutedColor : String := themed "descriptionForeground" "#888888"
/-- Panel background. -/
def panelBg : String := themed "editorWidget-background" "#fafafa"

/-- Build a React-compatible style object. React requires the style prop to be
a JSON OBJECT with camelCased property names — a CSS string crashes the
InfoView with React error #62, so never pass a string style. -/
def css (props : Array (String × String)) : Lean.Json :=
  Lean.Json.mkObj (props.toList.map fun (k, v) => (k, Lean.Json.str v))

/-- Shorthand for an SVG element with string attributes.  Do **not** pass a
`style` attribute through this helper (it would coerce it to a string, which
React rejects) — use `.element` with `css` for styles. -/
def el (tag : String) (attrs : Array (String × String)) (children : Array Html := #[]) :
    Html :=
  .element tag (attrs.map fun (k, v) => (k, .str v)) children

/-- An SVG `<text>` element. -/
def textEl (x y : Int) (fill : String) (content : String)
    (anchor : String := "middle") (size : String := "11") : Html :=
  el "text" #[("x", toString x), ("y", toString y), ("fill", fill),
      ("fontSize", size), ("textAnchor", anchor),
      ("fontFamily", "monospace")] #[.text content]

end Render

open Render

/-! ## Provable-coverage semantics (used for mismatch shading) -/

/-- Is the point at atom `p` provably contained in leaf `l`?  Uses only facts known to
the order graph, so `false` means "not provably", not "provably not". -/
def Leaf.coversPoint (g : OrderGraph) (l : Leaf) (p : String) : Bool :=
  match l.kind with
  | .univ => true
  | .empty => false
  | .singleton => (l.lo?.map fun a => g.knownEq a.pp p).getD false
  | k =>
    let leftOk := if k.boundedLeft then
        (l.lo?.map fun a =>
          if k.closedLeft then g.knownLe a.pp p else g.knownLt a.pp p).getD false
      else true
    let rightOk := if k.boundedRight then
        (l.hi?.map fun b =>
          if k.closedRight then g.knownLe p b.pp else g.knownLt p b.pp).getD false
      else true
    leftOk && rightOk

/-- Is the *open* segment between adjacent atoms `u < v` provably contained in leaf
`l`?  Sound when `u`, `v` are adjacent on the line and all interval endpoints are
atoms. -/
def Leaf.coversSeg (g : OrderGraph) (l : Leaf) (u v : String) : Bool :=
  match l.kind with
  | .univ => true
  | .empty | .singleton => false
  | k =>
    let leftOk := if k.boundedLeft then
        (l.lo?.map fun a => g.knownLe a.pp u).getD false
      else true
    let rightOk := if k.boundedRight then
        (l.hi?.map fun b => g.knownLe v b.pp).getD false
      else true
    leftOk && rightOk

/-- Is the open ray strictly below atom `u` provably contained in leaf `l`? -/
def Leaf.coversLeftOuter (g : OrderGraph) (l : Leaf) (u : String) : Bool :=
  match l.kind with
  | .univ => true
  | .empty | .singleton => false
  | k =>
    !k.boundedLeft &&
      (if k.boundedRight then (l.hi?.map fun b => g.knownLe u b.pp).getD false else true)

/-- Is the open ray strictly above atom `u` provably contained in leaf `l`? -/
def Leaf.coversRightOuter (g : OrderGraph) (l : Leaf) (u : String) : Bool :=
  match l.kind with
  | .univ => true
  | .empty | .singleton => false
  | k =>
    !k.boundedRight &&
      (if k.boundedLeft then (l.lo?.map fun a => g.knownLe a.pp u).getD false else true)

/-- Provable point coverage lifted to interval expressions
(union = either side, intersection = both). -/
partial def Tree.coversPoint (g : OrderGraph) : Tree → String → Bool
  | .leaf l, p => l.coversPoint g p
  | .union a b, p => a.coversPoint g p || b.coversPoint g p
  | .inter a b, p => a.coversPoint g p && b.coversPoint g p

/-- Provable segment coverage lifted to interval expressions. -/
partial def Tree.coversSeg (g : OrderGraph) : Tree → String → String → Bool
  | .leaf l, u, v => l.coversSeg g u v
  | .union a b, u, v => a.coversSeg g u v || b.coversSeg g u v
  | .inter a b, u, v => a.coversSeg g u v && b.coversSeg g u v

/-- Provable left-ray coverage lifted to interval expressions. -/
partial def Tree.coversLeftOuter (g : OrderGraph) : Tree → String → Bool
  | .leaf l, u => l.coversLeftOuter g u
  | .union a b, u => a.coversLeftOuter g u || b.coversLeftOuter g u
  | .inter a b, u => a.coversLeftOuter g u && b.coversLeftOuter g u

/-- Provable right-ray coverage lifted to interval expressions. -/
partial def Tree.coversRightOuter (g : OrderGraph) : Tree → String → Bool
  | .leaf l, u => l.coversRightOuter g u
  | .union a b, u => a.coversRightOuter g u || b.coversRightOuter g u
  | .inter a b, u => a.coversRightOuter g u && b.coversRightOuter g u

/-- An elementary region of the number line, delimited by atoms. -/
inductive Region where
  /-- The single point at an atom. -/
  | point (a : String)
  /-- The open segment between two adjacent atoms. -/
  | seg (u v : String)
  /-- The open ray below the leftmost atom. -/
  | leftOuter (u : String)
  /-- The open ray above the rightmost atom. -/
  | rightOuter (u : String)
  deriving Repr, BEq, Inhabited

/-- Coverage of a region by an interval expression, from provable facts only. -/
def Tree.coversRegion (g : OrderGraph) (t : Tree) : Region → Bool
  | .point a => t.coversPoint g a
  | .seg u v => t.coversSeg g u v
  | .leftOuter u => t.coversLeftOuter g u
  | .rightOuter u => t.coversRightOuter g u

/-- Elementary regions of a layout: points at (position-distinct) atoms, segments
between adjacent ones, and the two outer rays.  Atoms sharing a position (known
equal) are represented by the first of them. -/
def elementaryRegions (lay : Layout) : Array Region := Id.run do
  if lay.atoms.isEmpty then return #[]
  let sorted := lay.atoms.qsort (fun a b => a.x < b.x)
  -- Group by position, keeping the first representative of each distinct x.
  let mut reps : Array LayoutAtom := #[]
  for a in sorted do
    if !reps.any (·.x == a.x) then
      reps := reps.push a
  let mut out : Array Region := #[.leftOuter reps[0]!.name]
  for i in [0:reps.size] do
    out := out.push (.point reps[i]!.name)
    if i + 1 < reps.size then
      out := out.push (.seg reps[i]!.name reps[i+1]!.name)
  out := out.push (.rightOuter reps[reps.size - 1]!.name)
  return out

/-- Is the region *known to be nonempty* for an element type with the given
instances?  Point regions always are.  The open segment between adjacent atoms is
only known nonempty when the order is densely ordered (over `ℕ`, `Ioo 0 1 = ∅`);
the outer rays need `NoMinOrder` / `NoMaxOrder`.  Shading a possibly-empty region
as a "mismatch candidate" would flag provably-true goals, so such regions are
excluded from the candidates. -/
def Region.knownInhabited (inst : InstAvail) : Region → Bool
  | .point _ => true
  | .seg _ _ => inst.denselyOrdered
  | .leftOuter _ => inst.noMinOrder
  | .rightOuter _ => inst.noMaxOrder

/-- Regions provably covered by `lhs` but not provably covered by `rhs`
("mismatch candidates").  Only meaningful when the layout is totally ordered;
returns `#[]` otherwise (the renderer shows an "order unknown" caption instead).
Regions that may be empty for the element type (see `Region.knownInhabited`) are
excluded. -/
def mismatchRegions (g : OrderGraph) (lay : Layout) (lhs rhs : Tree)
    (inst : InstAvail := .all) : Array Region :=
  if !lay.totallyOrdered then #[]
  else (elementaryRegions lay).filter fun r =>
    r.knownInhabited inst && lhs.coversRegion g r && !(rhs.coversRegion g r)

/-! ## SVG assembly -/

namespace Render

/-- Render one leaf as a bar (plus endpoint glyphs) at vertical position `y`.
Positions of missing atoms default to the margin (should not happen for recognized
shapes). -/
def leafSvg (lay : Layout) (l : Leaf) (y : Int) (color : String) : Array Html := Id.run do
  let posOf (e? : Option Endpoint) (dflt : Int) : Int :=
    match e? with
    | some e => (lay.x? e.pp).map px |>.getD dflt
    | none => dflt
  match l.kind with
  | .empty =>
    return #[textEl (margin - 24) (y + 4) color "∅" (anchor := "start")]
  | .singleton =>
    let x := posOf l.lo? margin
    return #[el "circle"
      #[("cx", toString x), ("cy", toString y), ("r", "5"),
        ("fill", color), ("stroke", color), ("strokeWidth", "2")]]
  | k =>
    let xl : Int := if k.boundedLeft then posOf l.lo? margin else 8
    let xr : Int := if k.boundedRight then posOf l.hi? (margin + plotW) else width - 8
    let w : Int := if xr > xl then xr - xl else 0
    let mut out : Array Html := #[el "rect"
      #[("x", toString xl), ("y", toString (y - 4)), ("width", toString w),
        ("height", "8"), ("fill", color), ("fillOpacity", "0.55"), ("rx", "3")]]
    let glyph (x : Int) (closed : Bool) : Html :=
      if closed then
        el "circle" #[("cx", toString x), ("cy", toString y), ("r", "5"),
          ("fill", color), ("stroke", color), ("strokeWidth", "2")]
      else
        el "circle" #[("cx", toString x), ("cy", toString y), ("r", "5"),
          ("fill", openFill), ("stroke", color), ("strokeWidth", "2")]
    if k.boundedLeft then out := out.push (glyph xl k.closedLeft)
    if k.boundedRight then out := out.push (glyph xr k.closedRight)
    return out

/-- Render one side (an interval expression) as a stack of leaf bars starting at
vertical position `yTop`; returns the elements and the height consumed. -/
def treeSvg (lay : Layout) (t : Tree) (yTop : Int) (color : String) (label : String) :
    Array Html × Int := Id.run do
  let leaves := t.leaves
  let mut out : Array Html := #[]
  if label != "" then
    out := out.push (textEl 4 (yTop + 4) color label (anchor := "start"))
  let opLabel := match t with
    | .union _ _ => "∪" | .inter _ _ => "∩" | .leaf _ => ""
  if opLabel != "" then
    out := out.push (textEl (width - 14) (yTop + 4) color opLabel (anchor := "start"))
  let mut y := yTop
  for l in leaves do
    out := out ++ leafSvg lay l y color
    y := y + 14
  return (out, (leaves.size : Int) * 14)

end Render

/-- Order-condition caption for emptiness / nonemptiness shapes, tying the shape to
the ordering of its endpoints: e.g. `Nonempty ↔ a < b` for `(Ioc a b).Nonempty`, or
`= ∅ ↔ b ≤ a` for `Ioc a b = ∅` (and the reversed `∅ = Ioc a b`).  Extra instance
requirements (`DenselyOrdered` for `Ioo`, `NoMaxOrder`/`NoMinOrder` for `Ioi`/`Iio`)
are named honestly — and *checked* against `inst`: when the element type lacks the
instance the displayed claim relies on, the caption is dropped rather than shown as
if applicable.  Concretely:

* the `Nonempty`/`≠ ∅` iff for `Ioo` holds only over `DenselyOrdered` types
  (over `ℕ`, `Ioo 0 1 = ∅` although `0 < 1`);
* the "always holds" claims for `Ioi`/`Iio` need `NoMaxOrder`/`NoMinOrder`
  (over `ℕ`, `Iio 0 = ∅`);
* every `= ∅ ↔ hi ≤/< lo` caption needs `LinearOrder`: it negates the
  nonemptiness condition, and `¬(a ≤ b) ↔ b < a` requires totality
  (over `ℝ × ℝ`, `Icc (0,0) (1,-1) = ∅` although `(1,-1) < (0,0)` fails).

`none` for shapes without an emptiness reading or for composite (non-leaf) trees. -/
def emptinessCaption? (shape : Shape) (inst : InstAvail := .all) : Option String := do
  let (word, flip, t) ←
    match shape with
    | .nonempty t => some ("Nonempty", false, t)
    | .neEmpty t _ => some ("≠ ∅", false, t)
    | .eq t (.leaf { kind := .empty, .. }) => some ("= ∅", true, t)
    | .eq (.leaf { kind := .empty, .. }) t => some ("= ∅", true, t)
    | _ => none
  -- The reversed (`= ∅`) captions negate an iff: sound only over linear orders.
  if flip && !inst.linearOrder then none else
  let .leaf l := t | none
  let de ← do
    if l.kind.isDoubleEnded then some ((← l.lo?).pp, (← l.hi?).pp) else some ("", "")
  let (lo, hi) := de
  -- For nonempty/≠∅ the condition is `lo ≤/< hi`; for `= ∅` it is reversed.
  let cond (strict : Bool) : String :=
    let rel := if strict then "<" else "≤"
    if flip then s!"{hi} {rel} {lo}" else s!"{lo} {rel} {hi}"
  match l.kind with
  | .Icc => some s!"{word} ↔ {cond (strict := flip)}"
  | .Ico | .Ioc => some s!"{word} ↔ {cond (strict := !flip)}"
  | .Ioo =>
    if inst.denselyOrdered then some s!"{word} ↔ {cond (strict := !flip)} (DenselyOrdered)"
    else none
  | .Ici | .Iic =>
    if flip then none else some s!"{word} always holds"
  | .Ioi =>
    if flip || !inst.noMaxOrder then none
    else some s!"{word} always holds (NoMaxOrder)"
  | .Iio =>
    if flip || !inst.noMinOrder then none
    else some s!"{word} always holds (NoMinOrder)"
  | .singleton => if flip then none else some s!"{word} always holds"
  | _ => none

/-- Render a recognized shape as an SVG number line.

The output is a single `<svg>` element: axis, tick labels, one row of bars per side,
membership marker for `mem` shapes, red mismatch-candidate shading (when the order is
fully determined; for `=` shapes **both** directions are shaded, the RHS-beyond-LHS
regions marked `R-only` in their `data-mismatch` attribute) and warning captions for
unknown order / contradictory hypotheses.  `inst` gates instance-dependent output:
possibly-empty regions are not shaded over non-dense/bounded types (a muted caption
says so), and emptiness captions relying on unavailable instances are dropped. -/
def renderShapeSvg (shape : Shape) (g : OrderGraph) (lay : Layout)
    (inst : InstAvail := .all) : Html := Id.run do
  -- Rows to draw: (label, tree, color).
  let rows : Array (String × Tree × String) :=
    match shape with
    | .term t => #[("", t, lhsColor)]
    | .mem _ t => #[("", t, lhsColor)]
    | .nonempty t => #[("", t, lhsColor)]
    | .neEmpty t _ => #[("", t, lhsColor)]
    | .subset l r => #[("⊆ L", l, lhsColor), ("⊇ R", r, rhsColor)]
    | .ssubset l r => #[("⊂ L", l, lhsColor), ("⊃ R", r, rhsColor)]
    | .eq l r => #[("= L", l, lhsColor), ("= R", r, rhsColor)]
  let mut body : Array Html := #[]
  -- Provenance badge: any leaf recognized from set-builder notation.
  if (rows.map (·.2.1)).any (·.anyFromSetBuilder) then
    body := body.push
      (textEl (width - 8) 12 mutedColor "from set-builder" (anchor := "end") (size := "9"))
  let mut y : Int := 26
  for (label, t, color) in rows do
    let (els, h) := Render.treeSvg lay t y color label
    body := body ++ els
    y := y + h + 12
  -- Membership marker.
  if let .mem x _ := shape then
    if let some q := lay.x? x.pp then
      let xp := px q
      body := body.push (el "path"
        #[("d", s!"M {xp} {y} l -5 8 l 10 0 z"), ("fill", memColor)])
      body := body.push (textEl xp (y + 22) memColor x.pp)
      y := y + 26
  -- Mismatch shading (candidate regions), just above the axis.  For `=` shapes both
  -- directions are computed; the RHS-beyond-LHS regions carry an `R-only ` prefix in
  -- their `data-mismatch` attribute (a region cannot be in both directions).
  let mismatches : Array (Region × Bool) :=
    match shape with
    | .subset l r | .ssubset l r =>
      (mismatchRegions g lay l r inst).map ((·, false))
    | .eq l r =>
      (mismatchRegions g lay l r inst).map ((·, false))
        ++ (mismatchRegions g lay r l inst).map ((·, true))
    | _ => #[]
  for (r, isRev) in mismatches do
    let tag (s : String) : String := if isRev then s!"R-only {s}" else s
    match r with
    | .point a =>
      if let some q := lay.x? a then
        body := body.push (el "rect"
          #[("x", toString (px q - 3)), ("y", toString y), ("width", "6"),
            ("height", "6"), ("fill", mismatchColor),
            ("data-mismatch", tag s!"point {a}")])
    | .seg u v =>
      match lay.x? u, lay.x? v with
      | some qu, some qv =>
        let x1 := px qu
        let x2 := px qv
        body := body.push (el "rect"
          #[("x", toString x1), ("y", toString y),
            ("width", toString (if x2 > x1 then x2 - x1 else 0)), ("height", "6"),
            ("fill", mismatchColor), ("fillOpacity", "0.7"),
            ("data-mismatch", tag s!"seg {u} {v}")])
      | _, _ => pure ()
    | .leftOuter u =>
      if let some q := lay.x? u then
        body := body.push (el "rect"
          #[("x", "8"), ("y", toString y),
            ("width", toString (px q - 8)), ("height", "6"),
            ("fill", mismatchColor), ("fillOpacity", "0.7"),
            ("data-mismatch", tag s!"left {u}")])
    | .rightOuter u =>
      if let some q := lay.x? u then
        body := body.push (el "rect"
          #[("x", toString (px q)), ("y", toString y),
            ("width", toString (width - 8 - px q)), ("height", "6"),
            ("fill", mismatchColor), ("fillOpacity", "0.7"),
            ("data-mismatch", tag s!"right {u}")])
  if !mismatches.isEmpty then y := y + 10
  -- Axis.
  let axisY := y + 6
  body := body.push (el "line"
    #[("x1", "8"), ("y1", toString axisY), ("x2", toString (width - 8)),
      ("y2", toString axisY), ("stroke", axisColor), ("strokeWidth", "1.5")])
  -- Ticks and labels.
  for a in lay.atoms do
    let xp := px a.x
    body := body.push (el "line"
      #[("x1", toString xp), ("y1", toString (axisY - 4)), ("x2", toString xp),
        ("y2", toString (axisY + 4)), ("stroke", axisColor), ("strokeWidth", "1.5")])
    let (labelColor, suffix) :=
      if a.unordered then (warnColor, "?") else (fgColor, "")
    body := body.push (textEl xp (axisY + 16) labelColor (a.name ++ suffix))
  -- Captions.
  let mut capY := axisY + 34
  if let some c := emptinessCaption? shape inst then
    body := body.push (textEl (width / 2) capY fgColor c)
    capY := capY + 14
  -- When shading would apply but the type is not densely ordered, say why open
  -- segments are not shaded (over e.g. ℕ they may be empty).
  let comparing := match shape with
    | .subset .. | .ssubset .. | .eq .. => true
    | _ => false
  if comparing && !inst.denselyOrdered && lay.totallyOrdered && lay.atoms.size > 1 then
    body := body.push
      (textEl (width / 2) capY mutedColor
        "open segments not shaded: no DenselyOrdered instance (they may be empty)"
        (size := "10"))
    capY := capY + 14
  if lay.inconsistent then
    body := body.push
      (textEl (width / 2) capY mismatchColor "⚠ contradictory order hypotheses")
    capY := capY + 14
  for (a, b) in g.unknownPairs do
    body := body.push
      (textEl (width / 2) capY warnColor s!"order unknown between {a}, {b}")
    capY := capY + 14
  return .element "svg"
    #[("xmlns", .str "http://www.w3.org/2000/svg"), ("width", .str (toString width)),
      ("height", .str (toString (capY + 6))),
      ("viewBox", .str s!"0 0 {width} {capY + 6}"),
      ("style", css #[("background", panelBg), ("borderRadius", "6px")])]
    body

end IntervalInspector
