import GraphScope.Algo
import GraphScope.Render

/-! # GraphScope: click-to-insert suggestions (pure layer)

The `#graph_scope` panel offers click-to-insert links: clicking a drawn edge,
a vertex, or the components stats line inserts a self-contained
`example : … := by decide` on a new line after the command.  This module is the
*pure* half of that feature:

* the exact text builders (`edgeExampleText`, `degreeExampleText`,
  `connectedExampleText`, `notConnectedExampleText`) — the strings a click
  inserts, `#guard`-pinned and compile-verified by the test suite (the suite's
  house rule: a suggestion that does not provably hold may never be offered);
* `connectivityInsertable` — the experimentally validated bound under which the
  connectivity example is offered (see the docstring for the evidence);
* `LinkInfo` — the verified suggestions computed at elaboration time by
  `GraphScope.computeInsertions` (`GraphScope/Gate.lean`), after every vertex
  label has passed the round-trip honesty gate;
* `renderPanelInteractive` — the panel body with links, parameterized over a
  `mkLink` HTML builder so that the InfoView RPC method (which has the document
  metadata needed for real `MakeEditLink` components) and the compile-time
  tests (which pass a synthetic link builder, or none) share one assembly
  function;
* `componentNewTexts` — a test-facing serializer that extracts the `newText`
  of every component node in an `Html` tree, so tests can pin exactly what a
  click would insert.

Everything here is `#guard`-testable; no elaboration, no RPC.
-/

namespace GraphScope

open ProofWidgets

namespace Insert

/-- The edge fact inserted by clicking edge `a-b`:
`example : (g).Adj (a) (b) := by decide`.  `gSrc` is the user's graph term
verbatim (the `#graph_scope` argument parses at `term:max`, so it is atomic);
labels are parenthesized so application-shaped labels like `Sum.inl 0` stay
well-formed in argument position. -/
def edgeExampleText (gSrc aLbl bLbl : String) : String :=
  s!"example : ({gSrc}).Adj ({aLbl}) ({bLbl}) := by decide"

/-- The degree fact inserted by clicking vertex `v` (with drawn degree `k`):
`example : (g).degree (v) = k := by decide`. -/
def degreeExampleText (gSrc vLbl : String) (k : Nat) : String :=
  s!"example : ({gSrc}).degree ({vLbl}) = {k} := by decide"

/-- The connectivity fact for a connected graph:
`example : (g).Connected := by decide`. -/
def connectedExampleText (gSrc : String) : String :=
  s!"example : ({gSrc}).Connected := by decide"

/-- The connectivity fact for a disconnected graph:
`example : ¬ (g).Connected := by decide`. -/
def notConnectedExampleText (gSrc : String) : String :=
  s!"example : ¬ ({gSrc}).Connected := by decide"

/-- Should the connectivity example be offered for this graph?  Mathlib's
`Decidable G.Connected` instance (under `[Fintype V]`, `[DecidableEq V]`,
`[DecidableRel G.Adj]`, from `Mathlib.Combinatorics.SimpleGraph.Connectivity.Finite`)
decides reachability by enumerating walks, so `by decide` blows the elaborator
budget already for mid-sized graphs; a plain vertex-count cap is *dishonest*
(a 10-vertex "lollipop" — K₅ with a path tail — already times out).  The bound
here is conservative and was picked by compiling worst cases on this pin:

* connected: cost is driven by walk enumeration up to the graph's diameter
  with branching up to the max degree.  `diameter ≤ 4 && n ≤ 16` verified:
  `completeGraph (Fin 10)` (diameter 1), `completeBipartiteGraph (Fin 2) (Fin 3)`,
  `star5`, `pathGraph 5` (diameter 4), `cycleGraph 6` all compile in ≤ 5 s;
  failures start well outside the bound (`pathGraph 16`: recursion depth;
  10-vertex lollipop, diameter 6: heartbeat timeout).
* disconnected: `¬ Connected` must *exhaust* walks up to length `n - 1` inside
  the start component, so density is the killer (two disjoint K₅s time out).
  `maxDegree ≤ 2 && n ≤ 12` verified: `twoTriangles`, two disjoint 5-paths,
  `(⊥ : SimpleGraph (Fin 12))` all compile in ≤ 1 s. -/
def connectivityInsertable (d : GraphData) : Bool :=
  if d.isConnected then
    d.diameter ≤ 4 && d.n ≤ 16
  else
    d.n != 0 && (d.maxDegree?.getD 0) ≤ 2 && d.n ≤ 12

end Insert

/-- The verified click-to-insert suggestions for one drawn graph.  Built by
`computeInsertions` at elaboration time; every entry has already passed the
round-trip honesty gate (`labelRoundTrips`), so the panel may attach it to a
link without further checks. -/
structure LinkInfo where
  /-- Per-edge insertions: `(i, j, exampleText)` for each drawn edge `i-j`
  whose *both* endpoint labels round-trip. -/
  edges : Array (Nat × Nat × String) := #[]
  /-- Per-vertex degree insertions: `(i, exampleText)` for each vertex whose
  label round-trips. -/
  degrees : Array (Nat × String) := #[]
  /-- The connectivity insertion for the components stats line, when
  `Insert.connectivityInsertable` allows it. -/
  connected? : Option String := none
  /-- Labels that failed the round-trip gate (with their vertex index), shown
  as muted plain-text notes instead of links. -/
  notInsertable : Array (Nat × String) := #[]
  deriving Lean.ToJson, Lean.FromJson, Repr, BEq, Inhabited

namespace LinkInfo

/-- Are there any clickable insertions at all? -/
def hasLinks (l : LinkInfo) : Bool :=
  !l.edges.isEmpty || !l.degrees.isEmpty || l.connected?.isSome

/-- Every insertion text, in panel order (edges, then degrees, then
connectivity) — what the test suite compiles. -/
def allTexts (l : LinkInfo) : Array String :=
  l.edges.map (·.2.2) ++ l.degrees.map (·.2) ++ l.connected?.toArray

end LinkInfo

/-- A link builder: `mkLink newText title inner` wraps `inner` in a clickable
element that replaces the (zero-width) insertion range with `newText`.  The
RPC method passes a real `MakeEditLink`-based builder (it has the document
metadata); tests pass a synthetic one.  `renderPanelInteractive` is the single
place that turns an example text into the actual `newText` (`"\n" ++ text`, so
insertions go on a fresh line and never touch user text) — builders must use
`newText` verbatim. -/
abbrev MkLink := String → String → Html → Html

/-- The interactive InfoView panel: `renderPanel` plus click-to-insert links.
Drawn edges and vertices whose facts passed the gate are wrapped in
`mkLink`-built elements (vertices as an SVG `<g>` of circle + label); the
components stats line becomes a link when the connectivity example is offered;
gate-failed labels are listed as muted plain-text notes.  With `links := {}`
the output is *identical* to `renderPanel` (pinned by the tests). -/
def renderPanelInteractive (d : GraphData) (walk? : Option (Array Nat) := none)
    (highlight? : Option (Array Nat) := none) (mode : LayoutMode := .auto)
    (links : LinkInfo := {}) (mkLink : MkLink := fun _ _ h => h) : Html :=
  let lay := mode.resolve d
  -- The single place an example text becomes the edit's `newText`: a fresh
  -- line after the command, never a replacement of user text.
  let link (txt : String) (inner : Html) : Html :=
    mkLink ("\n" ++ txt) s!"insert: {txt}" inner
  let edgeWrap (a b : Nat) (line : Html) : Html :=
    match links.edges.find? (fun e => e.1 == a && e.2.1 == b) with
    | some e => link e.2.2 line
    | none => line
  let vertexWrap (i : Nat) (hs : Array Html) : Array Html :=
    match links.degrees.find? (fun p => p.1 == i) with
    | some p => #[link p.2 (Render.el "g" #[] hs)]
    | none => hs
  let componentsInner? : Option Html :=
    links.connected?.map fun txt =>
      link txt (.text (Render.componentsLine d))
  let notes : Array Html :=
    links.notInsertable.map fun (i, l) =>
      .element "div"
        #[("style", Render.css
            #[("color", Render.mutedColor), ("fontSize", "11px")])]
        #[.text s!"vertex {i}: not insertable — label `{l}` is not valid \
            syntax for the element"]
  let hint : Array Html :=
    if links.hasLinks then
      #[.element "div"
          #[("style", Render.css
              #[("color", Render.mutedColor), ("fontSize", "11px"),
                ("marginTop", "4px")])]
          #[.text "click an edge, a vertex or the components line to insert a \
              verified example after the command"]]
    else #[]
  Html.element "div"
    #[("style", Render.css #[("fontFamily", "sans-serif"), ("color", Render.fgColor)])]
    #[Render.graphSvg d lay walk? highlight? edgeWrap vertexWrap,
      Render.statsBlock d walk? highlight? componentsInner? (notes ++ hint)]

/-- Every `newText` of every component node in an `Html` tree, in tree order:
for each `Html.component`, force its lazily-encoded props and extract
`edit.edits[0].newText` when present (the `MakeEditLinkProps` shape).  Lets
tests pin exactly what a click would insert, without a live server. -/
partial def componentNewTexts : Html → List String
  | .text _ => []
  | .element _ _ cs => cs.foldl (fun acc c => acc ++ componentNewTexts c) []
  | .component _ _ props cs =>
    let j := (props.run {}).1
    let here :=
      match j.getObjVal? "edit" >>= (·.getObjVal? "edits") >>= (·.getArrVal? 0)
          >>= (·.getObjVal? "newText") >>= (·.getStr?) with
      | .ok s => [s]
      | .error _ => []
    cs.foldl (fun acc c => acc ++ componentNewTexts c) here

end GraphScope
