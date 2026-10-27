import GraphScopeTests.Helpers
-- v4.34.0: core, Mathlib and ProofWidgets are `module` files now, so a
-- non-`module` file like this one only sees their *public* import closure, and
-- the `backward.isDefEq.*` option constants (declared in
-- `Lean.Meta.ExprDefEq`) are not reachable through the Mathlib path.  The
-- transparency-default pin at the end of this file needs them, hence the
-- explicit import (test-only; the library itself does not need it).
import Lean.Meta.ExprDefEq

/-! # Click-to-insert tests

The panel's click-to-insert links must never offer a misleading fact, so this
file audits every layer of the feature:

* **pure text builders** — `#guard` pins of the exact inserted strings;
* **`diameter` / `connectivityInsertable`** — pins of the pure analysis that
  gates the connectivity example, including replicas of the graphs that were
  *experimentally shown* to blow the `decide` budget (a 10-vertex lollipop,
  two disjoint K₅s, `pathGraph 16`, `cycleGraph 24`, the 4-cube) — all must
  be refused — and of the walk-work counts and heartbeat estimates of the
  cost model (`walkWork`, `connectivityVerdict`);
* **the round-trip honesty gate** — `#assert_gate` unit tests, positive
  (`Fin`, `Bool`, products, `Finset` literals — including order-insensitive
  `Finset` equality) and negative (parse failures, labels with proof holes,
  labels that elaborate to a *different* element than the drawn one);
* **compile checks** — `#assert_insertions_compile` runs the real
  extraction + gate pipeline on demo graphs, then *compiles every generated
  example text* (the house rule: a suggestion that does not provably hold may
  never be offered) and logs a deterministic summary pinned by `#guard_msgs`;
* **serializer pins on the panel** — component nodes carry the expected
  `newText` (extracted from real `MakeEditLink` props via
  `componentNewTexts`), gate-failed labels degrade to plain text with a muted
  note, the React contract still holds, and with no links the interactive
  panel is *byte-identical* to the display-only `renderPanel`.
-/

namespace GraphScopeTests

open GraphScope ProofWidgets

/-! ## Pure text builders -/

#guard Insert.edgeExampleText "(pathGraph 5)" "0" "1"
  == "example : ((pathGraph 5)).Adj (0) (1) := by decide"
#guard Insert.edgeExampleText "twoTriangles" "Sum.inl 0" "Sum.inr 1"
  == "example : (twoTriangles).Adj (Sum.inl 0) (Sum.inr 1) := by decide"
#guard Insert.degreeExampleText "(pathGraph 5)" "0" 1
  == "example : ((pathGraph 5)).degree (0) = 1 := by decide"
#guard Insert.degreeExampleText "star5" "3" 1
  == "example : (star5).degree (3) = 1 := by decide"
#guard Insert.connectedExampleText "(cycleGraph 6)"
  == "example : ((cycleGraph 6)).Connected := by decide"
#guard Insert.notConnectedExampleText "twoTriangles"
  == "example : ¬ (twoTriangles).Connected := by decide"

/-! ## BFS distances and diameter -/

#guard (path 4).distancesFrom 0 == #[some 0, some 1, some 2, some 3]
#guard (path 4).distancesFrom 3 == #[some 3, some 2, some 1, some 0]
#guard twoPaths.distancesFrom 0 == #[some 0, some 1, some 2, none, none, none]
#guard (empty 3).distancesFrom 1 == #[none, some 0, none]
-- Out-of-range source: all `none`.
#guard (path 3).distancesFrom 7 == #[none, none, none]
#guard (path 5).diameter == 4
#guard (cycle 6).diameter == 3
#guard (cycle 5).diameter == 2
#guard (complete 7).diameter == 1
#guard (star 6).diameter == 2
#guard (empty 0).diameter == 0
#guard (empty 4).diameter == 0
-- Disconnected: max over components (two 3-paths → 2).
#guard twoPaths.diameter == 2

/-! ## The connectivity budget (`connectivityInsertable`)

Positive entries were verified by compiling `example : … := by decide` on this
pin; the negative entries replicate the graphs that were experimentally shown
to exhaust the elaborator (recursion depth or heartbeats).  Since the v4.35
round-2 fix, `connectivityInsertable` is the walk-work cost model
(`connectivityVerdict`: the v4.34 recursion-depth domain, then the heartbeat
estimate against the budget); the walk counts and estimates themselves are
pinned in "The connectivity cost model" further down. -/

-- Connected side: domain diameter ≤ 4 and n ≤ 16, then the estimate.
#guard Insert.connectivityInsertable (path 4) == true
#guard Insert.connectivityInsertable (path 5) == true      -- diameter 4, the edge of the budget
#guard Insert.connectivityInsertable (path 6) == false     -- diameter 5
#guard Insert.connectivityInsertable (cycle 6) == true
#guard Insert.connectivityInsertable (complete 10) == true -- compiled: < 1 s
#guard Insert.connectivityInsertable (complete 16) == true -- compiled below
#guard Insert.connectivityInsertable (star 16) == true     -- diameter 2
#guard Insert.connectivityInsertable (star 17) == false    -- n = 17 > 16
#guard Insert.connectivityInsertable (path 16) == false    -- compiled: recursion-depth failure
#guard Insert.connectivityInsertable (cycle 24) == false   -- compiled: recursion-depth failure

/-- Replica of the 10-vertex lollipop (K₅ with a 5-path tail) that *times out*
under `decide`: connected, diameter 6 — must be refused. -/
def lollipop10 : GraphData :=
  .ofEdges 10 (#[(0,1),(0,2),(0,3),(0,4),(1,2),(1,3),(1,4),(2,3),(2,4),(3,4)]
    ++ #[(4,5),(5,6),(6,7),(7,8),(8,9)])

#guard lollipop10.isConnected == true
#guard lollipop10.diameter == 6
#guard Insert.connectivityInsertable lollipop10 == false

/-- Replica of two disjoint K₅s, which *time out* under `decide` (refuting
`Connected` must exhaust all walks inside a dense component): disconnected
with max degree 4 — must be refused. -/
def twoK5 : GraphData :=
  .ofEdges 10 <| Id.run do
    let mut es := #[]
    for i in [0:5] do
      for j in [i+1:5] do
        es := es.push (i, j)
        es := es.push (i + 5, j + 5)
    return es

#guard twoK5.isConnected == false
#guard twoK5.maxDegree? == some 4
#guard Insert.connectivityInsertable twoK5 == false

-- Disconnected side: domain n ≤ 12, then the estimate (verified by compiling).
#guard Insert.connectivityInsertable twoPaths == true
#guard Insert.connectivityInsertable (empty 12) == true
#guard Insert.connectivityInsertable (empty 13) == false
#guard Insert.connectivityInsertable (empty 0) == false  -- nothing to say about the empty graph

/-! ## `LinkInfo` helpers -/

/-- Hand-built links for `path 3`, mirroring what `computeInsertions` produces
for `#graph_scope (pathGraph 3)` (pinned against it further down). -/
def path3Links : LinkInfo :=
  { edges := #[(0, 1, Insert.edgeExampleText "(pathGraph 3)" "0" "1"),
               (1, 2, Insert.edgeExampleText "(pathGraph 3)" "1" "2")]
    degrees := #[(0, Insert.degreeExampleText "(pathGraph 3)" "0" 1),
                 (1, Insert.degreeExampleText "(pathGraph 3)" "1" 2),
                 (2, Insert.degreeExampleText "(pathGraph 3)" "2" 1)]
    connected? := some (Insert.connectedExampleText "(pathGraph 3)") }

#guard (({} : LinkInfo)).hasLinks == false
#guard path3Links.hasLinks == true
#guard ({ notInsertable := #[(0, "x")] } : LinkInfo).hasLinks == false
#guard path3Links.allTexts ==
  #["example : ((pathGraph 3)).Adj (0) (1) := by decide",
    "example : ((pathGraph 3)).Adj (1) (2) := by decide",
    "example : ((pathGraph 3)).degree (0) = 1 := by decide",
    "example : ((pathGraph 3)).degree (1) = 2 := by decide",
    "example : ((pathGraph 3)).degree (2) = 1 := by decide",
    "example : ((pathGraph 3)).Connected := by decide"]

/-! ## Serializer pins on the panel

`testMkLink` builds *real* `MakeEditLink` components (the same
`MakeEditLinkProps.ofReplaceRange` call the RPC method makes, over a synthetic
`DocumentMeta`), so these pins exercise the exact props shape a click uses —
without a live server. -/

/-- Synthetic document metadata for the tests. -/
def testDocMeta : Lean.Server.DocumentMeta where
  uri := "file:///GraphScopeTests.lean"
  mod := `GraphScopeTests
  version := 7
  -- v4.34.0: `String.toFileMap` moved into the `Lean` namespace
  -- (`Lean.String.toFileMap`, a wrapper over `Lean.FileMap.ofString`).
  text := Lean.FileMap.ofString ""
  dependencyBuildMode := default

/-- A zero-width insertion range like the command's (line 3, end of command). -/
def testRange : Lean.Lsp.Range :=
  { start := { line := 3, character := 20 }, «end» := { line := 3, character := 20 } }

/-- The real link builder over the synthetic document — the same
`MakeEditLinkProps.ofReplaceRange` call `GraphScopePanel.rpc` makes, with
`newText` used verbatim (the `"\n"` prefix is `renderPanelInteractive`'s
responsibility, pinned below). -/
def testMkLink : MkLink := fun newText title inner =>
  .ofComponent MakeEditLink
    { MakeEditLinkProps.ofReplaceRange testDocMeta testRange newText
        with title? := some title }
    #[inner]

/-- The interactive panel for `path 3` with the hand-built links. -/
def path3Panel : Html :=
  renderPanelInteractive (path 3) (links := path3Links) (mkLink := testMkLink)

-- One component node per link (2 edges + 3 vertices + connectivity = 6), each
-- carrying exactly the insertion text on a fresh line after the command.
#guard countOccurrences (htmlToDebugString path3Panel) "<component:" == 6
#guard componentNewTexts path3Panel == path3Links.allTexts.toList.map ("\n" ++ ·)

-- Component nodes are legal React children: the contract checker stays green.
#guard reactContractViolations path3Panel == []

-- The click hint renders once links exist.
#guard containsSubstr (htmlToDebugString path3Panel)
  "click an edge, a vertex or the components line to insert a verified example"

-- The linked components line still shows the classic stats text.
#guard containsSubstr (htmlToDebugString path3Panel) "components: 1 (connected)"

-- With no links the interactive panel is byte-identical to the display-only
-- panel, across overlays and layouts.
#guard htmlToDebugString (renderPanelInteractive (path 4))
  == htmlToDebugString (renderPanel (path 4))
#guard htmlToDebugString
    (renderPanelInteractive (path 4) (walk? := some #[0, 1]) (highlight? := some #[3]))
  == htmlToDebugString (renderPanel (path 4) (walk? := some #[0, 1]) (highlight? := some #[3]))
#guard htmlToDebugString (renderPanelInteractive (cycle 5) (mode := .layered))
  == htmlToDebugString (renderPanel (cycle 5) (mode := .layered))

/-- A panel where vertex 1's label failed the gate: no degree link for it, no
edge links touching it, and a muted plain-text note instead. -/
def gateFailPanel : Html :=
  renderPanelInteractive (path 3)
    (links := { degrees := #[(0, Insert.degreeExampleText "(pathGraph 3)" "0" 1)]
                notInsertable := #[(1, "⟨1, _⟩")] })
    (mkLink := testMkLink)

#guard countOccurrences (htmlToDebugString gateFailPanel) "<component:" == 1
#guard containsSubstr (htmlToDebugString gateFailPanel)
  "vertex 1: not insertable — label `⟨1, _⟩` is not valid syntax for the element"
#guard reactContractViolations gateFailPanel == []

-- Gate-failure notes render even when no link survived (and then no hint).
#guard containsSubstr
  (htmlToDebugString (renderPanelInteractive (path 3)
    (links := { notInsertable := #[(0, "junk")] }) (mkLink := testMkLink)))
  "vertex 0: not insertable"
#guard !containsSubstr
  (htmlToDebugString (renderPanelInteractive (path 3)
    (links := { notInsertable := #[(0, "junk")] }) (mkLink := testMkLink)))
  "click an edge"

-- `ofReplaceRange` on a zero-width range: the edit targets the synthetic
-- document, replaces nothing, and moves the cursor to the end of the inserted
-- line — pinned so an accidental switch to a replacing edit fails loudly.
#guard (MakeEditLinkProps.ofReplaceRange testDocMeta testRange "\nexample").edit.edits.map
    (fun e => (e.range, e.newText))
  == #[(testRange, "\nexample")]
#guard (MakeEditLinkProps.ofReplaceRange testDocMeta testRange "\nexample").newSelection?
  == some { start := { line := 4, character := 7 }, «end» := { line := 4, character := 7 } }
#guard (MakeEditLinkProps.ofReplaceRange testDocMeta testRange "\nexample").edit.textDocument.uri
  == "file:///GraphScopeTests.lean"

/-! ## The round-trip honesty gate -/

open Lean Elab Command in
/-- `#assert_gate V "label" i pass|fail`: run the round-trip gate for `label`
against element `i` of `V`'s `Fintype` enumeration and require the given
verdict.  The build fails on a mismatch (one compile-time assertion per use). -/
elab "#assert_gate " V:term:max ppSpace s:str ppSpace i:num ppSpace e:ident : command => do
  let expected ← match e.getId with
    | `pass => pure true
    | `fail => pure false
    | _ => throwErrorAt e "#assert_gate: expected 'pass' or 'fail'"
  liftTermElabM do
    let Vty ← Term.elabTerm V none
    Term.synthesizeSyntheticMVarsNoPostponing
    let Vty ← instantiateMVars Vty
    let some finInst ← Meta.synthInstance? (← Meta.mkAppM ``Fintype #[Vty])
      | throwError "#assert_gate: no Fintype instance"
    let some deqInst ← Meta.synthInstance? (← Meta.mkAppM ``DecidableEq #[Vty])
      | throwError "#assert_gate: no DecidableEq instance"
    let got ← labelRoundTrips Vty finInst deqInst s.getString i.getNat
    unless got == expected do
      throwError "#assert_gate: label {s.getString} at index {i.getNat} was expected to \
        {if expected then "pass" else "fail"} the round-trip gate, but it did not"

-- Positive: `Fin` labels (what default and `Fin` `Repr` labels look like).
#assert_gate (Fin 5) "0" 0 pass
#assert_gate (Fin 5) "3" 3 pass
-- The gate proves *semantic* equality through `DecidableEq`, not string equality.
#assert_gate (Fin 5) "2 + 1" 3 pass
-- Positive: `Bool` (`Fintype Bool` enumerates `true` first on this pin).
#assert_gate Bool "true" 0 pass
#assert_gate Bool "false" 1 pass
-- Positive: products (`Repr` prints `(0, 1)`; enumeration is lexicographic).
#assert_gate (Fin 2 × Fin 2) "(0, 1)" 1 pass
#assert_gate (Fin 2 × Fin 2) "(1, 0)" 2 pass
-- Positive: `Finset` literals — `{1, 0}` equals enumerated element `{0, 1}`
-- by `DecidableEq` even though the label is written in another order.
#assert_gate (Finset (Fin 2)) "∅" 0 pass
#assert_gate (Finset (Fin 2)) "{0, 1}" 3 pass
#assert_gate (Finset (Fin 2)) "{1, 0}" 3 pass

-- Negative: right syntax, WRONG element — the compiling-but-false case the
-- gate exists to block.
#assert_gate (Fin 5) "3" 2 fail
#assert_gate Bool "true" 1 fail
#assert_gate (Finset (Fin 2)) "{0}" 3 fail
-- Negative: index out of range.
#assert_gate (Fin 5) "0" 7 fail
-- Negative: not term syntax at all.
#assert_gate (Fin 5) ")(" 0 fail
-- Negative: anonymous-constructor label with a proof hole (`⟨0, _⟩`) leaves a
-- metavariable — rejected.
#assert_gate {n : Fin 4 // n.val % 2 = 0} "⟨0, _⟩" 0 fail
-- Negative: the label a `Subtype` vertex actually *gets* on this pin (core's
-- `Repr (Subtype p)` prints just the value), which does not elaborate at the
-- subtype.
#assert_gate {n : Fin 4 // n.val % 2 = 0} "0" 0 fail
-- Negative: elaborates at a different type only (type mismatch).
#assert_gate (Fin 5) "true" 0 fail

/-! ## Compile checks over the demo graphs -/

open Lean Elab Command in
/-- Shared implementation of `#assert_insertions_compile`: run the real
extraction + gate pipeline on the graph term (with the term's verbatim source,
exactly like `#graph_scope`), **compile every generated example text**, and
log a deterministic summary (full texts, or counts only). -/
def runInsertionsCompile (t : Syntax.Term) (countsOnly : Bool) : CommandElabM Unit := do
  let fm ← getFileMap
  let some tRange := t.raw.getRange?
    | throwError "#assert_insertions_compile: the graph term has no source range"
  let gSrc := String.Pos.Raw.extract fm.source tRange.start tRange.stop
  let links ← liftTermElabM do
    let g ← Term.elabTerm t none
    Term.synthesizeSyntheticMVarsNoPostponing
    let g ← instantiateMVars g
    let d ← extractGraphData g
    computeInsertions gSrc g d
  for txt in links.allTexts do
    match Parser.runParserCategory (← getEnv) `command txt with
    | .error err =>
      throwError "#assert_insertions_compile: generated text does not parse \
        ({err}):\n{txt}"
    | .ok cstx => elabCommand cstx
  let conn := if links.connected?.isSome then "yes" else "no"
  let summary := s!"({links.edges.size} edges, {links.degrees.size} degrees, \
    connectivity: {conn}; {links.notInsertable.size} not insertable)"
  if countsOnly then
    logInfo s!"compiled {links.allTexts.size} insertions {summary}"
  else
    logInfo ("\n".intercalate (links.allTexts.toList ++ [summary]))

/-- `#assert_insertions_compile g` (optionally `(counts := true)`): compile
every insertion the panel would offer for `g` and log the texts (or counts).
Used under `#guard_msgs`, it pins exactly which suggestions are offered *and*
proves each one by compiling it. -/
syntax (name := assertInsertionsCompileCmd)
  "#assert_insertions_compile " (atomic("(" &"counts" " := " &"true" ")"))? term:max : command

open Lean Elab Command in
@[command_elab assertInsertionsCompileCmd]
def elabAssertInsertionsCompile : CommandElab := fun stx => do
  match stx with
  | `(#assert_insertions_compile $t:term) => runInsertionsCompile t false
  | `(#assert_insertions_compile (counts := true) $t:term) => runInsertionsCompile t true
  | _ => throwUnsupportedSyntax

open SimpleGraph GraphScope.Demo

-- Every text the panel offers for `(pathGraph 3)`, verbatim — and compiled.
/--
info: example : ((pathGraph 3)).Adj (0) (1) := by decide
example : ((pathGraph 3)).Adj (1) (2) := by decide
example : ((pathGraph 3)).degree (0) = 1 := by decide
example : ((pathGraph 3)).degree (1) = 2 := by decide
example : ((pathGraph 3)).degree (2) = 1 := by decide
example : ((pathGraph 3)).Connected := by decide
(2 edges, 3 degrees, connectivity: yes; 0 not insertable)
-/
#guard_msgs in
#assert_insertions_compile (pathGraph 3)

/-- info: compiled 10 insertions (4 edges, 5 degrees, connectivity: yes; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (pathGraph 5)

/-- info: compiled 13 insertions (6 edges, 6 degrees, connectivity: yes; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (cycleGraph 6)

/-- info: compiled 11 insertions (5 edges, 5 degrees, connectivity: yes; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (cycleGraph 5)

/-- info: compiled 16 insertions (10 edges, 5 degrees, connectivity: yes; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (completeGraph (Fin 5))

/-- info: compiled 5 insertions (0 edges, 4 degrees, connectivity: yes; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (⊥ : SimpleGraph (Fin 4))

/-- info: compiled 13 insertions (6 edges, 6 degrees, connectivity: yes; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) twoTriangles

/-- info: compiled 12 insertions (5 edges, 6 degrees, connectivity: yes; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) star5

/-- info: compiled 6 insertions (2 edges, 3 degrees, connectivity: yes; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (SimpleGraph.fromEdgeSet {s(0, 1), s(1, 2)} : SimpleGraph (Fin 3))

/-- info: compiled 12 insertions (6 edges, 5 degrees, connectivity: yes; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (completeBipartiteGraph (Fin 2) (Fin 3))

-- The disconnected budget edge (n = 12, degree 0) and a 2-regular disconnected
-- graph, both inside `connectivityInsertable`'s validated bound.
/-- info: compiled 13 insertions (0 edges, 12 degrees, connectivity: yes; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (⊥ : SimpleGraph (Fin 12))

/-- Two disjoint 5-paths (max degree 2, n = 10): inside the disconnected
connectivity budget. -/
def twoPaths10 : SimpleGraph (Fin 10) :=
  SimpleGraph.fromRel fun a b => b.val = a.val + 1 ∧ b.val ≠ 5

instance : DecidableRel twoPaths10.Adj := by unfold twoPaths10; infer_instance

/-- info: compiled 19 insertions (8 edges, 10 degrees, connectivity: yes; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) twoPaths10

-- The gate failing through the *real* pipeline: `Subtype` vertices get labels
-- from core's `Repr (Subtype p)` (just the value, e.g. `"0"`), which do not
-- elaborate at the subtype — so no edge/degree links are offered, only the
-- connectivity fact (which needs no vertex label) survives, and both labels
-- are reported as not insertable.
/-- info: compiled 1 insertions (0 edges, 0 degrees, connectivity: yes; 2 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (⊥ : SimpleGraph {n : Fin 4 // n.val % 2 = 0})

-- Budget validation at the connected extreme the pure predicate allows
-- (n = 16, diameter 1): the connectivity example itself must compile.
example : (completeGraph (Fin 16)).Connected := by decide

-- Mid-budget validation (not just the corners): a connected mid case
-- (cycleGraph 6: n = 6, diameter 3) and a disconnected mid case
-- (twoTriangles: n = 6, max degree 2) — both inside the budget, both texts
-- pinned above, and both claims must compile as offered.
example : (cycleGraph 6).Connected := by decide
example : ¬ (twoTriangles).Connected := by decide

/-! ## Toolchain transparency defaults (v4.34.0 port)

Between v4.32.2 and v4.34.0 the core option
`backward.isDefEq.respectTransparency.types` flipped its default from `false`
to `true` (`backward.isDefEq.respectTransparency` itself was already `true`),
so `isDefEq` no longer bumps transparency to `.default` when matching a
metavariable's type against the assigned term.  The inserted examples lean on
`by decide` through `GraphScope.Demo`'s `decidable_of_iff` instances for
`pathGraph` and `completeBipartiteGraph`, which is exactly the kind of
instance-unfolding that stricter transparency can break — so the pins below
require those examples to decide under the toolchain's **default** options (no
`set_option … respectTransparency … false` escape hatch anywhere in this
package), and pin the default itself so a silent flip in either direction is
caught here rather than in a user's file. -/

-- The stricter default really is what this toolchain ships.
open Lean in
/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from
  return Meta.backward.isDefEq.respectTransparency.types.get (← getOptions)

-- `pathGraph` (`hasse (Fin n)` via `decidable_of_iff _ pathGraph_adj.symm`).
#guard_msgs in
example : (pathGraph 5).Adj 3 4 := by decide
#guard_msgs in
example : (pathGraph 5).degree 2 = 2 := by decide

-- `completeBipartiteGraph` (`decidable_of_iff` over `Sum.isLeft`/`isRight`),
-- whose vertex terms are the `Repr`-derived `Sum.inl`/`Sum.inr` labels.
#guard_msgs in
example : (completeBipartiteGraph (Fin 2) (Fin 3)).Adj (Sum.inl 0) (Sum.inr 2) := by decide
#guard_msgs in
example : (completeBipartiteGraph (Fin 2) (Fin 3)).degree (Sum.inl 0) = 3 := by decide

/-! ## `pathGraph` instance selection (v4.35.0 port)

Mathlib v4.35.0 (mathlib4 #40728) added its own `DecidableRel (pathGraph n).Adj`
(through `hasse`'s new `[Fintype α] [DecidableLT α]` instance, which decides
`⋖` by quantifying over the vertex type).  `GraphScope.Demo`'s
`decidable_of_iff` instance is declared later, so instance synthesis still
picks it.  The pin below guards *which evaluation path* every `pathGraph`
example in this suite takes: Demo's closed arithmetic formula (one comparison
per adjacency) rather than Mathlib's pass over `Fin n` per adjacency.  At the
demo sizes both instances decide every offered `pathGraph` example (the audit
demoted Demo's instance and only this pin failed), so on its own the
selection is a performance question; since the adjacency-cost guard (next
section) it is also a behaviour one — Mathlib's instance is classified as
quantifying, so selecting it would withdraw `pathGraph`'s connectivity link,
which the `pathGraph` insertion pins above and ClickE2E's `path5` scenario
would also catch.  `pp.fullNames`, scoped to the one command, prints the
namespace (Mathlib's instance is `SimpleGraph.instDecidableRelFinAdjPathGraph`). -/

/-- info: GraphScope.Demo.instDecidableRelFinAdjPathGraph_graphScope 5 -/
#guard_msgs in
set_option pp.fullNames true in
#synth DecidableRel (pathGraph 5).Adj

/-! ## The adjacency-cost guard (v4.35.0 post-audit)

The connectivity cost model (`Insert.connectivityVerdict`, at the adjacency
cost measured by `GraphScope.adjacencyCostOf?`) was calibrated only with
adjacency instances that do not quantify over a finite type (see
`GraphScope/Gate.lean`, "The adjacency-cost guard").  Mathlib v4.35.0's
`hasse` / `CovBy` / `WCovBy` instances do, so every adjacency decision costs a
pass over the vertex type; the guard withholds the link for them.  (The
audit's failing link, `#graph_scope (hasse (Finset (Fin 4)))`, was in the
first place a failure of the v4.34 shape budget: that graph is the 4-cube,
whose walk enumeration exceeds `maxHeartbeats 200000` with any adjacency
instance — see "The connectivity cost model" below; the round-1 fix
attributed it to the quantifying instance alone.)  `#connectivity_gate g`
logs the inputs of the connectivity decision on the real pipeline
(`GraphScope.connectivityCheck`) — the walk-work verdict at zero adjacency
cost, the adjacency-cost guard's verdict on `g`'s own `DecidableRel`
instance, whether the measured cost of one adjacency decision is within the
cap the budget allows — and whether `computeInsertions` offers the link. -/

open Lean Elab Command in
/-- Shared implementation of `#connectivity_gate`: extract `g`, run
`connectivityCheck` (with `adjacencyCost` search limit `limit`) and log its
inputs — the walk-work verdict at zero adjacency cost (with the estimate, or
the domain bound that failed), the adjacency-cost guard's verdict (with the
nearest quantifying constant found), whether the measured cost of one
adjacency decision is within the cap `Insert.maxAdjacencyCost?` — and whether
`computeInsertions` (with the same limit) offers the connectivity link.  Fails if `computeInsertions`
disagrees with the check, or if a measured cost within the cap does not lead
to an offer. -/
def runConnectivityGate (t : Syntax.Term) (limit : Nat) : CommandElabM Unit := do
  let fm ← getFileMap
  let some tRange := t.raw.getRange?
    | throwError "#connectivity_gate: the graph term has no source range"
  let gSrc := String.Pos.Raw.extract fm.source tRange.start tRange.stop
  let msg ← liftTermElabM do
    let g ← Term.elabTerm t none
    Term.synthesizeSyntheticMVarsNoPostponing
    let g ← instantiateMVars g
    let d ← extractGraphData g
    let some V := (← Meta.whnf (← Meta.inferType g)).app1? ``SimpleGraph
      | throwError "#connectivity_gate: not a SimpleGraph"
    let check ← connectivityCheck g V d limit
    let offered := (← computeInsertions gSrc g d limit).connected?.isSome
    unless offered == check.offered d do
      throwError "#connectivity_gate: computeInsertions disagrees with connectivityCheck"
    if check.adjCost.isSome && !check.offered d then
      throwError "#connectivity_gate: a measured cost within the cap must lead to an offer"
    let walkStr := match check.atZeroCost with
      | .offered e => s!"yes (estimate {e})"
      | .overBudget e => s!"no (estimate {e} > {Insert.connectivityHeartbeatBudget})"
      | .outsideDomain r => s!"no ({r})"
    let costStr := match check.guard with
      | some .validated => "validated"
      | some (.quantifies c) => s!"quantifies ({c})"
      | some .unknown => "unknown"
      | none => "no instance"
    -- The measured cost itself varies by a few raw heartbeats between runs,
    -- so the pins show where it falls relative to the (pure) cap; the cost is
    -- pinned within a band by `#adjacency_cost` below.
    let measuredStr := match check.adjCost, check.cap with
      | some _, some c => s!"within the cap of {c} per decision"
      | some k, none => s!"{k} per decision (no cap?)"
      | none, some c =>
        if check.guard.any AdjCost.connectivityOk then s!"above the cap of {c} per decision"
        else "not measured"
      | none, none => "not measured"
    return s!"walk budget at zero adjacency cost: {walkStr}; adjacency: {costStr}; \
      measured adjacency cost: {measuredStr}; \
      connectivity link: {if offered then "offered" else "withheld"}"
  logInfo msg

/-- `#connectivity_gate g` (optionally `(limit := k)`, the `adjacencyCost`
search limit, default `adjCostSearchLimit`): log both inputs of the
connectivity decision on the real pipeline and whether the link is offered
(see `runConnectivityGate`).  Pinned with `#guard_msgs`. -/
syntax (name := connectivityGateCmd)
  "#connectivity_gate " (atomic("(" &"limit" " := " num ")"))? term:max : command

open Lean Elab Command in
@[command_elab connectivityGateCmd]
def elabConnectivityGate : CommandElab := fun stx => do
  match stx with
  | `(#connectivity_gate $t:term) => runConnectivityGate t adjCostSearchLimit
  | `(#connectivity_gate (limit := $k:num) $t:term) => runConnectivityGate t k.getNat
  | _ => throwUnsupportedSyntax

-- The validated class: every graph whose connectivity example the suite
-- compiles (above, and in ClickE2E) keeps its link.
/--
info: walk budget at zero adjacency cost: yes (estimate 919); adjacency: validated; measured adjacency cost: within the cap of 132196 per decision; connectivity link: offered
-/
#guard_msgs in
#connectivity_gate (pathGraph 5)

/--
info: walk budget at zero adjacency cost: yes (estimate 1372); adjacency: validated; measured adjacency cost: within the cap of 82014 per decision; connectivity link: offered
-/
#guard_msgs in
#connectivity_gate (cycleGraph 6)

/--
info: walk budget at zero adjacency cost: yes (estimate 11550); adjacency: validated; measured adjacency cost: within the cap of 7772 per decision; connectivity link: offered
-/
#guard_msgs in
#connectivity_gate (completeGraph (Fin 16))

/--
info: walk budget at zero adjacency cost: yes (estimate 713); adjacency: validated; measured adjacency cost: within the cap of 182580 per decision; connectivity link: offered
-/
#guard_msgs in
#connectivity_gate (completeBipartiteGraph (Fin 2) (Fin 3))

/--
info: walk budget at zero adjacency cost: yes (estimate 584); adjacency: validated; measured adjacency cost: within the cap of 239992 per decision; connectivity link: offered
-/
#guard_msgs in
#connectivity_gate twoTriangles

/--
info: walk budget at zero adjacency cost: yes (estimate 280); adjacency: validated; measured adjacency cost: within the cap of 906224 per decision; connectivity link: offered
-/
#guard_msgs in
#connectivity_gate (SimpleGraph.fromEdgeSet {s(0, 1), s(1, 2)} : SimpleGraph (Fin 3))

/--
info: walk budget at zero adjacency cost: yes (estimate 305); adjacency: validated; measured adjacency cost: within the cap of 736903 per decision; connectivity link: offered
-/
#guard_msgs in
#connectivity_gate (⊥ : SimpleGraph (Fin 12))

/--
info: walk budget at zero adjacency cost: yes (estimate 2815); adjacency: validated; measured adjacency cost: within the cap of 36740 per decision; connectivity link: offered
-/
#guard_msgs in
#connectivity_gate twoPaths10

-- For contrast, a refusal by the walk budget alone (diameter 15 is outside
-- the validated recursion-depth domain).
/--
info: walk budget at zero adjacency cost: no (diameter 15 > 4); adjacency: validated; measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate (pathGraph 16)

-- The audit's graph (round 1): the 4-cube, whose estimate exceeds the budget
-- at any real adjacency cost (the cap is 344 raw heartbeats per decision, see
-- "The connectivity cost model" below); its instance also quantifies over the
-- vertex type, so the guard withholds the link before anything is measured.
/--
info: walk budget at zero adjacency cost: yes (estimate 74436); adjacency: quantifies (SimpleGraph.instDecidableRelAdjHasseOfFintypeOfDecidableLT); measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate (hasse (Finset (Fin 4)))

-- Smaller Hasse diagrams inside the walk budget, whose connectivity example
-- happens to compile, are withheld too: the estimate is not calibrated for a
-- quantifying adjacency, so the guard is conservative rather than size-tuned.
/--
info: walk budget at zero adjacency cost: yes (estimate 3647); adjacency: quantifies (SimpleGraph.instDecidableRelAdjHasseOfFintypeOfDecidableLT); measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate (hasse (Finset (Fin 3)))

/--
info: walk budget at zero adjacency cost: yes (estimate 472); adjacency: quantifies (SimpleGraph.instDecidableRelAdjHasseOfFintypeOfDecidableLT); measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate (hasse (Fin 4))

-- Mathlib's own `pathGraph` instance (selected when `GraphScope.Demo`'s is
-- absent, e.g. with a narrower import) is in the same class.
/--
info: walk budget at zero adjacency cost: yes (estimate 919); adjacency: quantifies (SimpleGraph.instDecidableRelFinAdjPathGraph); measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
attribute [-instance] GraphScope.Demo.instDecidableRelFinAdjPathGraph_graphScope in
#connectivity_gate (pathGraph 5)

-- The underlying `CovBy` / `WCovBy` instances, reached through `fromRel`.
/--
info: walk budget at zero adjacency cost: yes (estimate 472); adjacency: quantifies (Fintype.instDecidableRelCovByOfDecidableLT); measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate (SimpleGraph.fromRel fun a b : Fin 4 => a ⋖ b)

/--
info: walk budget at zero adjacency cost: yes (estimate 472); adjacency: quantifies (Fintype.instDecidableRelWCovByOfDecidableLE); measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate (SimpleGraph.fromRel fun a b : Fin 4 => a ⩿ b)

/-- `hasse (Finset (Fin 4))` behind a user `def` with its own instance: the
guard follows the instance's definition to Mathlib's. -/
def hasseQ4 : SimpleGraph (Finset (Fin 4)) := hasse (Finset (Fin 4))

instance : DecidableRel hasseQ4.Adj := by unfold hasseQ4; infer_instance

/--
info: walk budget at zero adjacency cost: yes (estimate 74436); adjacency: quantifies (SimpleGraph.instDecidableRelAdjHasseOfFintypeOfDecidableLT); measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate hasseQ4

-- A user relation that quantifies over the vertex type `Fin 5`: core decides
-- `∃ c : Fin 5, …` with `Nat.decidableExistsFin` (bounded `Nat` search).
/--
info: walk budget at zero adjacency cost: yes (estimate 919); adjacency: quantifies (Nat.decidableExistsFin); measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate
  (SimpleGraph.fromRel fun a b : Fin 5 => ∃ c : Fin 5, a.val + c.val = b.val ∧ c.val = 1)

-- The two most general deny-list entries, each the nearest hit:
-- quantifiers over a non-`Fin` `Fintype` vertex type are decided through
-- Mathlib's `Fintype.decidableForallFintype` / `Fintype.decidableExistsFintype`
-- (round-2 re-audit: deleting both entries passed the suite before these pins).
-- A `∀` over `Bool × Bool` (adjacent iff the first components agree):
/--
info: walk budget at zero adjacency cost: yes (estimate 223); adjacency: quantifies (Fintype.decidableForallFintype); measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate
  (SimpleGraph.fromRel fun a b : Bool × Bool => ∀ c : Bool × Bool, c = c ∧ a.1 = b.1)

-- An `∃` over `Fin 2 × Fin 3`:
/--
info: walk budget at zero adjacency cost: yes (estimate 584); adjacency: quantifies (Fintype.decidableExistsFintype); measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate
  (SimpleGraph.fromRel fun a b : Fin 2 × Fin 3 => ∃ c : Fin 2 × Fin 3, c ≠ a ∧ c ≠ b ∧ a.1 = b.1)

-- The covering relation of `Finset (Fin 4)` spelled out with a `Finset`-bounded
-- `∀`: instance synthesis decides the binder through the `Fintype` instance.
-- (The 4-cube again: it would also fail the measured-cost cap of 344.)
/--
info: walk budget at zero adjacency cost: yes (estimate 74436); adjacency: quantifies (Fintype.decidableForallFintype); measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate (SimpleGraph.fromRel fun a b : Finset (Fin 4) =>
  a < b ∧ ∀ c ∈ (Finset.univ : Finset (Finset (Fin 4))), ¬ (a < c ∧ c < b))

-- The conservative `.unknown` verdict: a definitional closure larger than the
-- search limit withholds the link.  With the default limit `pathGraph 5`'s
-- instance is validated (pinned above); with `limit := 1` the closure is
-- already larger than the limit before any hit is found.
/--
info: walk budget at zero adjacency cost: yes (estimate 919); adjacency: unknown; measured adjacency cost: not measured; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate (limit := 1) (pathGraph 5)

#guard AdjCost.validated.connectivityOk == true
#guard AdjCost.unknown.connectivityOk == false
#guard (AdjCost.quantifies ``Fintype.decidableForallFintype).connectivityOk == false
#guard adjCostSearchLimit == 20000

-- What the panel offers for Hasse diagrams, compiled: edge and vertex links
-- (one adjacency / one row each) compile; the connectivity link is withheld.
/--
info: example : ((hasse (Fin 4))).Adj (0) (1) := by decide
example : ((hasse (Fin 4))).Adj (1) (2) := by decide
example : ((hasse (Fin 4))).Adj (2) (3) := by decide
example : ((hasse (Fin 4))).degree (0) = 1 := by decide
example : ((hasse (Fin 4))).degree (1) = 2 := by decide
example : ((hasse (Fin 4))).degree (2) = 2 := by decide
example : ((hasse (Fin 4))).degree (3) = 1 := by decide
(3 edges, 4 degrees, connectivity: no; 0 not insertable)
-/
#guard_msgs in
#assert_insertions_compile (hasse (Fin 4))

-- `Finset` vertices have no `Repr` in this import closure (Mathlib's lives in
-- `Mathlib.Data.Finset.Sort`), so their index labels fail the round-trip gate;
-- with the connectivity link withheld nothing is offered at all.  With
-- `Finset` labels (`HasseLinkTests.lean`) every edge and vertex link is
-- offered and compiles.
/-- info: compiled 0 insertions (0 edges, 0 degrees, connectivity: no; 8 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (hasse (Finset (Fin 3)))

/-- info: compiled 0 insertions (0 edges, 0 degrees, connectivity: no; 16 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) (hasse (Finset (Fin 4)))

/-! ## The connectivity cost model (v4.35.0 post-audit, round 2)

The round-1 fix kept the v4.34 shape budget (connected: `diameter ≤ 4 && n ≤
16`) and blamed the audit's failing link on `hasse`'s quantifying instance.
The re-audit showed that the shape budget itself is unsound: the 4-cube with
a cheap closed adjacency (`Nat.xor` on `Fin 16`) is inside it, and its
connectivity example needs 324048–328678 heartbeats (822363 in a `Finset`
spelling).  Mathlib's `Decidable G.Connected` builds every walk of length up
to `dist u v` out of every vertex, so the cost grows like degree^distance,
and every walk-tree node decides `n` adjacencies.  `Insert.walkWork` counts
that enumeration exactly, `GraphScope.adjacencyCostOf?` measures the cost of
one adjacency decision of the graph's own instance, and
`Insert.connectivityVerdict` combines them into a heartbeat estimate that
must stay within half the default budget (calibration sweep and coefficients:
`PORT-NOTES.md`). -/

/-- The `k`-cube on `2^k` vertices: `i ~ j` iff `i` and `j` differ in one bit. -/
def hypercube (k : Nat) : GraphData :=
  .ofEdges (2 ^ k) <| Id.run do
    let mut es := #[]
    for i in [0:2 ^ k] do
      for b in [0:k] do
        es := es.push (i, i ^^^ (2 ^ b))
    return es

/-- The circulant graph on `n` vertices with the given steps. -/
def circulant (n : Nat) (steps : List Nat) : GraphData :=
  .ofEdges n <| Id.run do
    let mut es := #[]
    for i in [0:n] do
      for s in steps do
        es := es.push (i, (i + s) % n)
    return es

#guard (hypercube 4).n == 16 && (hypercube 4).edgeCount == 32
#guard (hypercube 4).diameter == 4 && (hypercube 4).maxDegree? == some 4

-- Walk work, exact (the same counts the calibration probe simulated; for
-- `path 5`, `complete 16` and the cubes they match its matrix-power replica).
#guard Insert.walkWork (path 5) == { sets := 65, inner := 92, leaves := 125 }
#guard Insert.walkWork (complete 16) == { sets := 496, inner := 240, leaves := 3856 }
#guard Insert.walkWork (hypercube 3) == { sets := 160, inner := 288, leaves := 736 }
#guard Insert.walkWork (hypercube 4) == { sets := 768, inner := 4160, leaves := 13248 }
-- Disconnected: stops after the first unreachable pair `(0, 3)`, which runs
-- through every length `k < n`.
#guard Insert.walkWork twoPaths == { sets := 12, inner := 27, leaves := 21 }
#guard Insert.walkWork (empty 12) == { sets := 13, inner := 11, leaves := 2 }

-- The estimate: `(1 + adjCost/1000) · (0.71 n·inner + 1.87 leaves + 2.91 sets) + 170`.
-- `completeGraph (Fin 16)` at its measured cost (2390 per decision in the
-- sweep; 34124 heartbeats measured):
#guard (Insert.walkWork (complete 16)).heartbeats 16 2390 == 38749
#guard Insert.connectivityVerdict (complete 16) 2390 == .offered 38749
-- The 4-cube: inside the budget only at zero adjacency cost; the cap on the
-- per-decision cost is 344 raw heartbeats, far below any real instance (the
-- `Nat.xor` spelling measured 4225: estimate 388211, measured 328678).
#guard Insert.connectivityVerdict (hypercube 4) 0 == .offered 74436
#guard Insert.connectivityVerdict (hypercube 4) 4225 == .overBudget 388211
#guard Insert.maxAdjacencyCost? (hypercube 4) == some 344
#guard Insert.connectivityVerdict (hypercube 4) 344 == .offered 99983
#guard Insert.connectivityVerdict (hypercube 4) 345 == .overBudget 100058
#guard Insert.connectivityInsertable (hypercube 4) == false
#guard Insert.connectivityInsertable (hypercube 3) == true
-- The cap is exact for `completeGraph (Fin 16)` too.
#guard Insert.maxAdjacencyCost? (complete 16) == some 7772
#guard Insert.connectivityVerdict (complete 16) 7772 == .offered 99999
#guard Insert.connectivityVerdict (complete 16) 7773 == .overBudget 100010
-- No cap outside the domain or over the budget at zero cost.
#guard Insert.maxAdjacencyCost? (path 16) == none
#guard Insert.maxAdjacencyCost? (empty 0) == none
#guard Insert.connectivityHeartbeatBudget == 100000
#guard Insert.cheapAdjacencyCost == 3000

-- Graphs the v4.34 shape budget offered whose example fails or nearly
-- fails (measured in the round-2 sweep): all refused now.
-- `C16(1, 2)`: diameter 4, 411022 heartbeats (over the default budget).
#guard Insert.connectivityInsertable (circulant 16 [1, 2]) == false
#guard Insert.connectivityVerdict (circulant 16 [1, 2]) 0 == .overBudget 132304
-- K₁₀ with a 3-vertex tail: diameter 4, fails on recursion depth.
#guard Insert.connectivityInsertable
    (.ofEdges 13 ((complete 10).edges ++ #[(9, 10), (10, 11), (11, 12)])) == false
-- Two disjoint 6-cycles (max degree 2, n = 12, inside the old disconnected
-- budget): 160229 heartbeats, over half the default budget.
#guard Insert.connectivityInsertable
    (.ofEdges 12 ((cycle 6).edges ++ (cycle 6).edges.map fun (a, b) => (a + 6, b + 6))) == false

-- Recursion depth: `13.85 n + 11.53 L + 6.5 W + 37.5` (`L` the longest walk
-- length enumerated, `W` the heaviest such walk by degree), at most 500.
#guard Insert.recursionEstimate (star 16) == 483        -- bisected need: 408
#guard Insert.recursionEstimate (complete 16) == 465    -- bisected need: 391
#guard Insert.recursionEstimate (hypercube 4) == 435    -- bisected need: 407
#guard Insert.recursionEstimate (empty 12) == 330       -- bisected need: 143
#guard Insert.recursionEstimate twoPaths == 236
#guard Insert.heaviestWalk (star 16) 2 (Array.range 16) == 31
#guard Insert.heaviestWalk (empty 12) 11 #[0] == 0
#guard Insert.connectivityRecursionBudget == 500
-- A broom (hub with 12 leaves and a 3-vertex tail, n = 16, diameter 4): the
-- walk work alone is cheap at low adjacency cost, but the example fails on
-- recursion depth (round-2 validation sweep: after 37947 heartbeats), and
-- the recursion estimate refuses it.
#guard Insert.recursionEstimate
    (.ofEdges 16 ((Array.range 13).map (fun i => (0, i + 1)) ++ #[(13, 14), (14, 15)])) == 584
#guard Insert.connectivityVerdict
    (.ofEdges 16 ((Array.range 13).map (fun i => (0, i + 1)) ++ #[(13, 14), (14, 15)])) 0
  == .outsideDomain "recursion estimate 584 > 500"
-- K₁₀ with a 3-vertex tail (diameter 4, fails on recursion depth in the
-- calibration sweep, need 575 when raised): refused on both counts.
#guard Insert.recursionEstimate
    (.ofEdges 13 ((complete 10).edges ++ #[(9, 10), (10, 11), (11, 12)])) == 575

/-- The 4-cube on `Fin 16` with a cheap closed adjacency (the re-audit's
`q4fin`). -/
def q4fin : SimpleGraph (Fin 16) :=
  SimpleGraph.fromRel fun a b => a.val ^^^ b.val = 1 ∨ a.val ^^^ b.val = 2 ∨
    a.val ^^^ b.val = 4 ∨ a.val ^^^ b.val = 8

instance : DecidableRel q4fin.Adj := by unfold q4fin; infer_instance

-- The re-audit's counterexample: validated instance, inside the old shape
-- budget, example over the default budget — now withheld (the measured
-- adjacency cost is above the cap of 344).
/--
info: walk budget at zero adjacency cost: yes (estimate 74436); adjacency: validated; measured adjacency cost: above the cap of 344 per decision; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate q4fin

/--
info: walk budget at zero adjacency cost: yes (estimate 74436); adjacency: validated; measured adjacency cost: above the cap of 344 per decision; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate (SimpleGraph.fromRel fun a b : Finset (Fin 4) => a ⊆ b ∧ a.card + 1 = b.card)

-- Through the production pipeline: every edge and degree link compiles, the
-- connectivity link is not offered.
/-- info: compiled 48 insertions (32 edges, 16 degrees, connectivity: no; 0 not insertable) -/
#guard_msgs in
#assert_insertions_compile (counts := true) q4fin

/-! ### The measurement itself

`adjacencyCostOf?` starts from an empty `MetaM` cache, so measuring twice in
one command gives nearly the same value — otherwise the second `whnf` would
hit the cache and cost almost nothing, and the estimate would collapse.  The
value is not bit-for-bit repeatable (heartbeats count allocations; a
repeated measurement in the same command comes out up to ~2% lower, as some
caches outside `MetaM` stay warm, and runs differ by a few raw heartbeats),
so it is pinned within a band; a tiny cap cuts the measurement off
(`none`). -/

open Lean Elab Command in
/-- `#adjacency_cost g lo hi`: measure the cost of one adjacency decision of
`g`, reduce the measured proposition once more (warming this command's
`MetaM` cache), measure again (cap 100000 per decision), then once with a cap
of 1; log whether the two measurements agree within 5%, whether both lie in
`[lo, hi]`, and the capped result. -/
elab "#adjacency_cost " t:term:max ppSpace lo:num ppSpace hi:num : command => liftTermElabM do
  let g ← Term.elabTerm t none
  Term.synthesizeSyntheticMVarsNoPostponing
  let g ← instantiateMVars g
  let d ← extractGraphData g
  let some V := (← Meta.whnf (← Meta.inferType g)).app1? ``SimpleGraph
    | throwError "#adjacency_cost: not a SimpleGraph"
  let some first ← adjacencyCostOf? g V d.n 100000
    | throwError "#adjacency_cost: no measurement"
  -- Warm this command's `MetaM` cache with the very reduction the
  -- measurement performs: without the cache reset in `adjacencyCostOf?` the
  -- second measurement would then cost (almost) nothing.
  let p ← adjacencyCostProp g V
  let some inst ← Meta.synthInstance? (mkApp (mkConst ``Decidable) p)
    | throwError "#adjacency_cost: no Decidable instance"
  discard <| Meta.withAtLeastTransparency .default <|
    Meta.whnf (mkApp2 (mkConst ``Decidable.decide) p inst)
  let some second ← adjacencyCostOf? g V d.n 100000
    | throwError "#adjacency_cost: no second measurement"
  let capped ← adjacencyCostOf? g V d.n 1
  let close : Bool := 100 * (max first second - min first second) ≤ 5 * max first second
  let inBand := lo.getNat ≤ min first second && max first second ≤ hi.getNat
  logInfo m!"repeatable within 5%: {close}; in [{lo.getNat}, {hi.getNat}]: {inBand}; \
    with cap 1: {capped}"

-- `pathGraph 5` through `GraphScope.Demo`'s instance: 2791 / 2790 / 2789 /
-- 2773 raw heartbeats in the runs so far.
/-- info: repeatable within 5%: true; in [2500, 3100]: true; with cap 1: none -/
#guard_msgs in
#adjacency_cost (pathGraph 5) 2500 3100

-- `completeGraph (Fin 16)`: 2389–2390.
/-- info: repeatable within 5%: true; in [2150, 2650]: true; with cap 1: none -/
#guard_msgs in
#adjacency_cost (completeGraph (Fin 16)) 2150 2650

-- The `Finset (Fin 3)` `⊆`/`card` 3-cube: 18049–18054.
/-- info: repeatable within 5%: true; in [16000, 20000]: true; with cap 1: none -/
#guard_msgs in
#adjacency_cost (SimpleGraph.fromRel fun a b : Finset (Fin 3) => a ⊆ b ∧ a.card + 1 = b.card) 16000 20000

/-! ### The most expensive offered examples, compiled with half the heartbeat budget

The sweep's most expensive offered connectivity examples (for the spellings
pinned here), compiled under `maxHeartbeats 100000` — half the default — so
the suite itself proves the margin the budget promises.  The
`#connectivity_gate` pins show that each is offered. -/

/-- Two disjoint `K₄`s via `fromRel` (disconnected; its `¬ Connected` example
needs 61632 heartbeats in the round-2 validation sweep, estimate 63610). -/
def twoK4 : SimpleGraph (Fin 8) :=
  SimpleGraph.fromRel fun a b => a.val / 4 = b.val / 4

instance : DecidableRel twoK4.Adj := by unfold twoK4; infer_instance

-- `K₇,₇` through `GraphScope.Demo`'s instance: 79781–79788 heartbeats in the
-- round-2 runs (estimate 88809 at the measured cost of 3371 per decision).
/--
info: walk budget at zero adjacency cost: yes (estimate 20449); adjacency: validated; measured adjacency cost: within the cap of 3922 per decision; connectivity link: offered
-/
#guard_msgs in
#connectivity_gate (completeBipartiteGraph (Fin 7) (Fin 7))

set_option maxHeartbeats 100000 in
example : ((completeBipartiteGraph (Fin 7) (Fin 7))).Connected := by decide

/--
info: walk budget at zero adjacency cost: yes (estimate 15681); adjacency: validated; measured adjacency cost: within the cap of 5436 per decision; connectivity link: offered
-/
#guard_msgs in
#connectivity_gate twoK4

set_option maxHeartbeats 100000 in
example : ¬ (twoK4).Connected := by decide

-- The 3-cube on `Finset (Fin 3)` through `⊆`/`card` (an expensive adjacency:
-- about 18050 per decision, so the estimate is 66414 for 33785 heartbeats).
/--
info: walk budget at zero adjacency cost: yes (estimate 3647); adjacency: validated; measured adjacency cost: within the cap of 27705 per decision; connectivity link: offered
-/
#guard_msgs in
#connectivity_gate (SimpleGraph.fromRel fun a b : Finset (Fin 3) => a ⊆ b ∧ a.card + 1 = b.card)

set_option maxHeartbeats 100000 in
example : ((SimpleGraph.fromRel fun a b : Finset (Fin 3) => a ⊆ b ∧ a.card + 1 = b.card)).Connected := by decide

-- `completeGraph (Fin 16)` (already compiled under the default budgets
-- above) with half of them:
set_option maxHeartbeats 100000 in
example : ((completeGraph (Fin 16))).Connected := by decide

-- A `fromEdgeSet` literal: each adjacency decision scans the literal, so the
-- 3-cube spelled this way (61840 heartbeats, against 16091 through `Nat.xor`)
-- is withheld although its shape is cheap — conservative.
/--
info: walk budget at zero adjacency cost: yes (estimate 3647); adjacency: validated; measured adjacency cost: above the cap of 27705 per decision; connectivity link: withheld
-/
#guard_msgs in
#connectivity_gate (SimpleGraph.fromEdgeSet {s(0, 1), s(0, 2), s(0, 4), s(1, 3), s(1, 5), s(2, 3),
  s(2, 6), s(3, 7), s(4, 5), s(4, 6), s(5, 7), s(6, 7)} : SimpleGraph (Fin 8))

end GraphScopeTests
