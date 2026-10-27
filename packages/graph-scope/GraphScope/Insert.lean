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
* `connectivityInsertable` — the walk-work cost model under which the
  connectivity example is offered (`walkWork`, `WalkWork.heartbeats`,
  `connectivityVerdict`; see "The connectivity cost model" for the evidence);
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

/-! ### The connectivity cost model

Mathlib's `Decidable G.Connected` instance (under `[Fintype V]`,
`[DecidableEq V]`, `[DecidableRel G.Adj]`, from
`Mathlib.Combinatorics.SimpleGraph.Connectivity.Finite`) decides
`Preconnected ∧ univ.Nonempty`, with `Preconnected` as `∀ u v, G.Reachable u v`
over the `Fintype` enumeration (in order, stopping at the first unreachable
pair) and `G.Reachable u v` as `∃ k : Fin (Fintype.card V),
(G.finsetWalkLength k u v).Nonempty` (ascending `k`, stopping at the first
nonempty set, i.e. at `k = dist u v`).  `finsetWalkLength k u v`
(`Mathlib.Combinatorics.SimpleGraph.Walk.Counting`) builds **every** walk of
length `k` out of `u`: each inner node of that walk tree lists its neighbours
by filtering `univ` (one adjacency decision per vertex) and deduplicates the
walks returned by its children (`Finset.biUnion`), each leaf decides one
vertex equality.  So the cost of `by decide` is governed by walk *branching*
— the number of walks of length up to the distance, i.e. degree^distance —
not by the shape alone: the 4-cube (16 vertices, diameter 4, degree 4) needs
328678 heartbeats with a cheap closed adjacency (`Nat.xor` on `Fin 16`), more
than the default `maxHeartbeats 200000`, while `completeGraph (Fin 16)`
(diameter 1) needs 34124.  The cost of each adjacency decision matters as
much: the same 3-cube needs 16091 heartbeats through `Nat.xor`, 33784 through
`Finset` `⊆`/`card` and 61840 through a `fromEdgeSet` literal.

So the estimate has two inputs.  `walkWork` counts the enumeration exactly on
the drawn graph (same enumeration order, same stopping rules).  The cost of
one adjacency decision is *measured* at panel time by `GraphScope/Gate.lean`
(`adjacencyCostOf?`: `whnf` of `decide (∀ a b, ¬ (G.Adj a b ∧ False))`, the
reduction `decide` itself performs, divided by the `n²` decisions).
`WalkWork.heartbeats` combines them with coefficients fitted to
`#count_heartbeats` measurements of the offered example on this pin (a sweep
of 250 graphs with at most 16 vertices: families, spellings and vertex types
listed in `PORT-NOTES.md`): the fit is an upper envelope, so the estimate is
at least the measurement on every graph of the sweep.  The link is offered
only when the estimate is at most `connectivityHeartbeatBudget`, half the
default `maxHeartbeats`.

The other resource `decide` can exhaust is `maxRecDepth` (512): the
reduction nests one level per vertex of the enumerations and per child of a
walk-tree node, so high degrees along long walks fail on recursion depth
even with a modest walk count (K₁₀ with a 3-vertex tail, diameter 4;
a 12-leaf broom with a 3-vertex tail).  `recursionEstimate` bounds it from
the `GraphData` (an upper envelope of bisected minimal depths, see its
docstring), and the link also needs it to be at most
`connectivityRecursionBudget`. -/

/-- The walk enumeration that `decide` runs for `G.Connected` (see "The
connectivity cost model"), counted on the drawn graph. -/
structure WalkWork where
  /-- Walk sets `finsetWalkLength k u v` tested for nonemptiness. -/
  sets : Nat := 0
  /-- Inner nodes of the walk trees built; each one decides `n` adjacencies
  (it filters `univ` for the neighbour set). -/
  inner : Nat := 0
  /-- Leaves of the walk trees; each one decides one vertex equality. -/
  leaves : Nat := 0
  deriving Repr, BEq, Inhabited

/-- Walk counts out of `u`: entry `j` maps each vertex `w` to the number of
walks of length `j` from `u` to `w`, for `j = 0, …, maxLen` (`adj` are the
adjacency lists of a graph on `adj.size` vertices). -/
def walkCountsFrom (adj : Array (Array Nat)) (u maxLen : Nat) : Array (Array Nat) :=
  Id.run do
    let n := adj.size
    let mut x : Array Nat := (Array.replicate n 0).set! u 1
    let mut out := #[x]
    for _ in [0:maxLen] do
      let mut y : Array Nat := Array.replicate n 0
      for w in [0:n] do
        let c := x[w]!
        if c != 0 then
          for w' in adj[w]! do
            y := y.set! w' (y[w']! + c)
      x := y
      out := out.push x
    return out

/-- Count the walk enumeration of Mathlib's `Decidable G.Connected` on `d`
(see "The connectivity cost model"): pairs `(u, v)` in enumeration order, walk
lengths `k = 0, …, dist u v` for a reachable pair, and `k = 0, …, n - 1` for
the first unreachable pair, after which the decision is `false` and nothing
else is evaluated.  The walk tree of `(u, v, k)` has `Σ_{j<k} #walks_j(u)`
inner nodes and `#walks_k(u)` leaves, where `#walks_j(u)` is the number of
walks of length `j` out of `u`. -/
def walkWork (d : GraphData) : WalkWork := Id.run do
  let n := d.n
  let adj := d.adjacencyLists
  let maxLen := if d.isConnected then d.diameter else n - 1
  let mut acc : WalkWork := {}
  for u in [0:n] do
    let walks := walkCountsFrom adj u maxLen
    -- `before[k] = Σ_{j<k} #walks_j(u)`, `total[k] = #walks_k(u)`
    let total : Array Nat := walks.map (·.foldl (· + ·) 0)
    let before : Array Nat := total.foldl (init := #[0]) fun a t => a.push (a.back! + t)
    let dist := d.distancesFrom u
    for v in [0:n] do
      let (lens, unreachable) := match dist[v]! with
        | some D => (D + 1, false)
        | none => (n, true)
      for k in [0:lens] do
        acc := { sets := acc.sets + 1, inner := acc.inner + before[k]!,
                 leaves := acc.leaves + total[k]! }
      if unreachable then
        return acc
  return acc

/-- Heartbeat estimate (in `maxHeartbeats` units) of `by decide` on
`G.Connected` / `¬ G.Connected` for a graph on `n` vertices with this walk
work, when one adjacency decision costs `adjCost` raw heartbeats
(`IO.getNumHeartbeats` units, a thousandth of a `maxHeartbeats` unit):
`(1 + adjCost / 1000) · (0.71 · n · inner + 1.87 · leaves + 2.91 · sets) + 170`.
The coefficients are the upper envelope of the calibration sweep
(`PORT-NOTES.md`, "Connectivity cost model"), rounded up. -/
def WalkWork.heartbeats (w : WalkWork) (n adjCost : Nat) : Nat :=
  (1000 + adjCost) * (71 * n * w.inner + 187 * w.leaves + 291 * w.sets) / 100000 + 170

/-- The heaviest walk of `d` with at most `len + 1` vertices, weighting each
vertex by its degree (vertices may repeat), over walks starting at a vertex
of `starts`.  Feeds `recursionEstimate`: `whnf` nests one level per child of
a walk-tree node while it concatenates the children's walk sets, so the
recursion depth of the enumeration grows with the degrees along a walk. -/
def heaviestWalk (d : GraphData) (len : Nat) (starts : Array Nat) : Nat := Id.run do
  let adj := d.adjacencyLists
  let deg := (Array.range d.n).map fun v => adj[v]!.size
  -- `cur[w]`: the heaviest walk found so far that ends at `w` (`none`: no walk)
  let mut cur : Array (Option Nat) := Array.replicate d.n none
  for s in starts do
    if s < d.n then
      cur := cur.set! s (some deg[s]!)
  let mut best := cur.foldl (fun b x => Nat.max b (x.getD 0)) 0
  for _ in [0:len] do
    let mut nxt : Array (Option Nat) := Array.replicate d.n none
    for v in [0:d.n] do
      if let some val := cur[v]! then
        for w in adj[v]! do
          nxt := nxt.set! w (some (Nat.max (nxt[w]!.getD 0) (val + deg[w]!)))
    cur := nxt
    best := cur.foldl (fun b x => Nat.max b (x.getD 0)) best
  return best

/-- An upper estimate of the `maxRecDepth` that `by decide` needs for the
connectivity example: `13.85 · n + 11.53 · L + 6.5 · W + 37.5`, where `L` is
the longest walk length enumerated (the diameter for a connected graph,
`n - 1` for a disconnected one, whose first unreachable pair starts at
vertex `0`) and `W` the heaviest such walk (`heaviestWalk`, from every vertex
resp. from vertex `0`).  The coefficients are the upper envelope of the
smallest `maxRecDepth` under which the example compiles, bisected for 58
graphs of the calibration sweep (`PORT-NOTES.md`, "Recursion depth"),
rounded up.  `maxRecDepth` is a deterministic counter (512 by default),
unlike heartbeats. -/
def recursionEstimate (d : GraphData) : Nat :=
  let (len, starts) :=
    if d.isConnected then (d.diameter, Array.range d.n) else (d.n - 1, #[0])
  (1385 * d.n + 1153 * len + 650 * heaviestWalk d len starts + 3750) / 100

/-- The connectivity link needs `recursionEstimate` to be at most this, a
little under Lean's default `maxRecDepth 512`. -/
def connectivityRecursionBudget : Nat := 500

/-- The connectivity link is offered only when the estimate is at most this
many heartbeats: half of Lean's default `maxHeartbeats 200000`, the safety
margin for graphs and spellings outside the calibration sweep and for
heartbeat drift across toolchains and runtimes. -/
def connectivityHeartbeatBudget : Nat := 100000

/-- Why the connectivity example is or is not offered (`connectivityVerdict`). -/
inductive ConnectivityVerdict where
  /-- Inside the validated domain, with this heartbeat estimate, within the
  budget: offered. -/
  | offered (estimate : Nat)
  /-- Inside the validated domain, but the estimate exceeds the budget. -/
  | overBudget (estimate : Nat)
  /-- Outside the domain the model was calibrated on (`reason` says which
  bound failed). -/
  | outsideDomain (reason : String)
  deriving Repr, BEq, Inhabited

/-- Is the verdict `offered`? -/
def ConnectivityVerdict.isOffered : ConnectivityVerdict → Bool
  | .offered _ => true
  | _ => false

/-- Classify the connectivity example for this graph when one adjacency
decision costs `adjCost` raw heartbeats.  The domain bounds are the
recursion-depth limits validated on this pin, unchanged since v4.32.2:
connected graphs need `diameter ≤ 4` and `n ≤ 16` (the walk length
enumerated is the distance; `pathGraph 16` and `cycleGraph 24` fail on
recursion depth), disconnected ones `n ≤ 12` (`¬ Connected` enumerates walks
up to length `n - 1` from the first vertex); the empty graph has no example.
Inside them, `recursionEstimate` must stay within
`connectivityRecursionBudget` (high-degree walks nest deeper: K₁₀ with a
3-vertex tail, diameter 4, fails on recursion depth) and
`(walkWork d).heartbeats d.n adjCost` within `connectivityHeartbeatBudget`. -/
def connectivityVerdict (d : GraphData) (adjCost : Nat) : ConnectivityVerdict :=
  if d.n == 0 then .outsideDomain "no vertices"
  else if d.isConnected && d.n > 16 then .outsideDomain s!"{d.n} vertices > 16"
  else if d.isConnected && d.diameter > 4 then .outsideDomain s!"diameter {d.diameter} > 4"
  else if !d.isConnected && d.n > 12 then
    .outsideDomain s!"disconnected with {d.n} vertices > 12"
  else if recursionEstimate d > connectivityRecursionBudget then
    .outsideDomain s!"recursion estimate {recursionEstimate d} > {connectivityRecursionBudget}"
  else
    let est := (walkWork d).heartbeats d.n adjCost
    if est ≤ connectivityHeartbeatBudget then .offered est else .overBudget est

/-- The largest adjacency cost (raw heartbeats per decision) under which
`connectivityVerdict d` still offers the link, or `none` when it is not
offered even at zero cost.  `GraphScope/Gate.lean` caps its measurement of
the adjacency cost at this value, so measuring never costs more than the
budget allows. -/
def maxAdjacencyCost? (d : GraphData) : Option Nat :=
  if (connectivityVerdict d 0).isOffered then
    let w := walkWork d
    let work := 71 * d.n * w.inner + 187 * w.leaves + 291 * w.sets
    -- the largest `c` with `(1000 + c) * work / 100000 + 170 ≤ budget`, i.e.
    -- `(1000 + c) * work < (budget - 169) * 100000` (nonnegative here, since
    -- `c = 0` qualifies)
    some (((connectivityHeartbeatBudget - 169) * 100000 - 1) / work - 1000)
  else none

/-- A cheap adjacency decision, in raw heartbeats: roughly what a closed
arithmetic formula on `Fin n` or Mathlib's `⊤` / `cycleGraph` instances cost
in the calibration sweep (2390 for `completeGraph (Fin 16)`, 2792 for
`pathGraph 5` through `GraphScope.Demo`'s instance, 4225 for `Nat.xor` on
`Fin 16`).  Only the pure pins of `connectivityInsertable` use it; the panel
measures the graph's own cost. -/
def cheapAdjacencyCost : Nat := 3000

/-- Would the connectivity example be offered for this graph, at adjacency
cost `adjCost` (default `cheapAdjacencyCost`)?  See `connectivityVerdict` and
"The connectivity cost model".  This is the pure half of the decision;
`GraphScope.computeInsertions` also requires the graph's `DecidableRel`
instance to pass the adjacency-cost guard (`GraphScope/Gate.lean`) and
measures its actual adjacency cost. -/
def connectivityInsertable (d : GraphData) (adjCost : Nat := cheapAdjacencyCost) : Bool :=
  (connectivityVerdict d adjCost).isOffered

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
