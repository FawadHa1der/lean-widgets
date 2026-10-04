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
  two disjoint K₅s, `pathGraph 16`, `cycleGraph 24`) — all must be refused;
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
to exhaust the elaborator (recursion depth or heartbeats). -/

-- Connected side: diameter ≤ 4 and n ≤ 16.
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

-- Disconnected side: max degree ≤ 2 and n ≤ 12 (verified by compiling).
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

end GraphScopeTests
