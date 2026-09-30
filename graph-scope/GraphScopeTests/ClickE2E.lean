import Lean.Elab.Frontend
import GraphScopeTests.Helpers

/-! # End-to-end click-simulation tests

`InsertTests` pins what a click *would* insert; this file proves the whole
journey: a realistic **user file** (importing only what a real user has) is
compiled in-process through core's own frontend, the `#graph_scope` command's
*stored* panel props (`links` + `insertRange`) are read back out of the info
tree, the panel body is rendered with the exact `MakeEditLinkProps` builder the
RPC method uses, the resulting LSP edit is applied to the user file with core's
own UTF-16 position conversion, and the **edited file is recompiled** — a click
only counts as working when the file it produces is clean (zero errors, zero
sorries, the inserted `example` elaborated).

Layers:

* `applyLspEdit` — apply a `TextEdit`-style `(range, newText)` using
  `FileMap.lspPosToUtf8Pos` (LSP ranges are UTF-16 code units; byte or
  codepoint arithmetic is a bug), `#guard`-pinned on multibyte strings
  (`ℝ`, `⋖`, and the surrogate-pair emoji `🎉`);
* the nested compiler — `Parser.parseHeader` + `importModules` (over the
  ambient search path; initializer execution must be re-enabled, see
  `importEnv`) + core's `IO.processCommands`, collecting messages, command
  count and the `#graph_scope` widget props from the info trees;
* `#e2e_click_scenario` — per user file: base compile must be clean, then each
  requested click (edge / degree / connectivity) is simulated end to end, with
  the *fresh* insert range re-read from the recompiled file between clicks
  (exactly like the live panel, which recomputes after every edit);
* `#e2e_negative` — non-vacuity: a corrupted `newText`, a shifted range and a
  falsified claim must each make the recompile FAIL (pinned), and an
  intentional `sorry` must be detected by the sorry channel the happy paths
  assert on.

House rule inherited from the suite: the nested compiles run with **default
options** (default `maxHeartbeats`), so every `by decide` here proves itself
under the same budget a real user's file gets.
-/

namespace GraphScopeTests
namespace E2E

open Lean Elab GraphScope ProofWidgets

/-! ## `applyLspEdit`: LSP text edits over UTF-16 positions -/

/-- Apply a single `TextEdit`-style edit — replace `range` with `newText` — to
`src`.  LSP positions are `(line, UTF-16 code unit)` pairs; the conversion to
byte positions goes through core's own `FileMap.lspPosToUtf8Pos`, the same
function the real language server uses when it applies a `WorkspaceEdit`. -/
def applyLspEdit (src : String) (range : Lsp.Range) (newText : String) : String :=
  let fm := src.toFileMap
  let b := fm.lspPosToUtf8Pos range.start
  let e := fm.lspPosToUtf8Pos range.«end»
  String.Pos.Raw.extract src ⟨0⟩ b ++ newText ++ String.Pos.Raw.extract src e src.rawEndPos

-- ASCII control: insertion and replacement.
#guard applyLspEdit "abc\ndef\n"
    { start := { line := 1, character := 1 }, «end» := { line := 1, character := 1 } } "X"
  == "abc\ndXef\n"
#guard applyLspEdit "abc\ndef\n"
    { start := { line := 0, character := 1 }, «end» := { line := 0, character := 2 } } "Z"
  == "aZc\ndef\n"
-- `ℝ` and `⋖` are 3 UTF-8 bytes but ONE UTF-16 unit each: character 2 is
-- before the `x`.  A byte-offset implementation would land inside `ℝ`.
#guard applyLspEdit "ℝ⋖x\nrest"
    { start := { line := 0, character := 2 }, «end» := { line := 0, character := 2 } } "X"
  == "ℝ⋖Xx\nrest"
-- `🎉` is ONE codepoint but TWO UTF-16 units: character 3 is before the `b`.
-- A codepoint-offset implementation would insert after the `b` instead.
#guard applyLspEdit "a🎉b"
    { start := { line := 0, character := 3 }, «end» := { line := 0, character := 3 } } "X"
  == "a🎉Xb"
-- Replacement across multibyte text: characters 1–4 are `ℝ🎉` (1 + 2 units).
#guard applyLspEdit "aℝ🎉b"
    { start := { line := 0, character := 1 }, «end» := { line := 0, character := 4 } } "Z"
  == "aZb"
-- Emoji on an EARLIER line must not shift a later line's positions.
#guard applyLspEdit "🎉🎉\nℝx\n"
    { start := { line := 1, character := 1 }, «end» := { line := 1, character := 1 } } "Y"
  == "🎉🎉\nℝYx\n"
-- The panel's own shape: zero-width range at end of line, `"\n" ++ text`.
#guard applyLspEdit "cmd"
    { start := { line := 0, character := 3 }, «end» := { line := 0, character := 3 } }
    "\nexample"
  == "cmd\nexample"

/-! ## The nested compiler -/

/-- Import `imports` over the ambient search path for a nested in-process
compile.  The frontend disables initializer execution once the outer file's own
imports are loaded, and `importModules (loadExts := true)` refuses to run
without it, so it is re-enabled here; `withImporting` scopes the flags back off
afterwards (the same dance `Lean.Elab.runFrontend`'s incremental path does). -/
private unsafe def importEnvUnsafe (imports : Array Import) : IO Environment := do
  Lean.enableInitializersExecution
  Lean.withImporting <| importModules (loadExts := true) imports {} (trustLevel := 0)

@[implemented_by importEnvUnsafe]
private opaque importEnv (imports : Array Import) : IO Environment

/-- An imported environment tagged with the imports that built it, reused
across the compiles of one scenario (base file + one recompile per click) so
Mathlib's olean closure is loaded once per scenario, not once per click. -/
structure NestedEnv where
  /-- Modules of the user file's header, in order. -/
  imports : Array Name
  /-- The imported environment. -/
  env : Environment

/-- Build the environment for a user file from its own `import` header. -/
def NestedEnv.ofHeader (src : String) : IO NestedEnv := do
  let inputCtx := Parser.mkInputContext src "E2EUser.lean"
  let (header, _, msgs) ← Parser.parseHeader inputCtx
  unless msgs.toList.isEmpty do
    throw <| IO.userError "E2E: user-file header does not parse"
  let imports := headerToImports header
  return { imports := imports.map (·.module), env := ← importEnv imports }

/-- What one in-process compile of a user file produced. -/
structure Outcome where
  /-- Parsed top-level commands (includes the terminal end-of-input command). -/
  commands : Nat
  /-- First line of every error message, in order. -/
  errors : Array String
  /-- Number of messages mentioning `sorry` (the `declaration uses 'sorry'`
  channel). -/
  sorries : Nat
  /-- Stored props of every `#graph_scope` panel widget in the info trees. -/
  panels : Array Json

/-- All stored props of user widgets with the given javascript hash in an info
tree, in tree order. -/
private partial def widgetPropsIn (jsHash : UInt64) : InfoTree → List Json
  | .context _ t => widgetPropsIn jsHash t
  | .node i cs =>
    let here := match i with
      | .ofUserWidgetInfo wi =>
        if wi.javascriptHash == jsHash then [(wi.props.run {}).1] else []
      | _ => []
    here ++ cs.toList.flatMap (widgetPropsIn jsHash)
  | .hole _ => []

/-- Compile `src` as a standalone user file against `ne.env`: parse the header
(it must match the imports the environment was built from), elaborate every
command with default options and info trees enabled, and collect messages,
command count and the `#graph_scope` panel props. -/
def NestedEnv.compile (ne : NestedEnv) (src : String) : IO Outcome := do
  let inputCtx := Parser.mkInputContext src "E2EUser.lean"
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  unless (headerToImports header).map (·.module) == ne.imports do
    throw <| IO.userError s!"E2E: user file must import exactly {ne.imports}"
  let cmdState := Command.mkState ne.env messages {}
  let cmdState := { cmdState with infoState := { enabled := true } }
  let st ← IO.processCommands inputCtx parserState cmdState
  let mut errors := #[]
  let mut sorries := 0
  for m in st.commandState.messages.toList do
    let s ← m.data.toString
    if m.severity matches .error then
      errors := errors.push ((s.splitOn "\n").headD s)
    if (s.splitOn "sorry").length > 1 then
      sorries := sorries + 1
  let jsHash := hash GraphScopePanel.javascript
  let panels := st.commandState.infoState.trees.toList.flatMap (widgetPropsIn jsHash)
  return { commands := st.commands.size, errors, sorries, panels := panels.toArray }

/-! ## Decoding the stored panel props -/

/-- The slice of the stored `PanelProps` the click simulation needs. -/
structure Panel where
  /-- The extracted graph, as stored. -/
  d : GraphData
  /-- The gate-verified insertions, as stored. -/
  links : LinkInfo
  /-- The zero-width range at the command's end, as stored. -/
  insertRange : Lsp.Range

/-- Decode the stored props of one `#graph_scope` panel. -/
def decodePanel (j : Json) : Except String Panel := do
  return { d := ← fromJson? (← j.getObjVal? "d")
           links := ← fromJson? (← j.getObjVal? "links")
           insertRange := ← fromJson? (← j.getObjVal? "insertRange") }

/-- Every `MakeEditLink` payload in an `Html` tree, in tree order, decoded
through `MakeEditLinkProps`'s own `FromJson`: `(uri, range, newText)`. -/
partial def componentEditPayloads : Html → Except String (List (String × Lsp.Range × String))
  | .text _ => pure []
  | .element _ _ cs =>
    cs.foldlM (fun acc c => return acc ++ (← componentEditPayloads c)) []
  | .component _ _ props cs => do
    let props : MakeEditLinkProps ← fromJson? (props.run {}).1
    let edits : Array Lsp.TextEdit := props.edit.edits
    let some te := edits[0]?
      | throw "E2E: MakeEditLink component with an empty edit list"
    let rest ← cs.foldlM (fun acc c => return acc ++ (← componentEditPayloads c)) []
    return (props.edit.textDocument.uri, te.range, te.newText) :: rest

/-- The URI the simulated user file lives at. -/
def userUri : String := "file:///E2EUser.lean"

/-- The real edit payloads of a compiled user file's panel: the panel body is
rendered by the shared `renderPanelInteractive` with a `MakeEditLink` builder
over the user file's own `DocumentMeta` — the identical
`MakeEditLinkProps.ofReplaceRange` call `GraphScopePanel.rpc` makes — and the
`(uri, range, newText)` triples are decoded back out of the component props. -/
def panelEdits (src : String) (p : Panel) : Except String (List (String × Lsp.Range × String)) := do
  let docMeta : Lean.Server.DocumentMeta :=
    { uri := userUri, mod := `E2EUser, version := 1
      text := src.toFileMap, dependencyBuildMode := default }
  let mkLink : MkLink := fun newText title inner =>
    .ofComponent MakeEditLink
      { MakeEditLinkProps.ofReplaceRange docMeta p.insertRange newText
          with title? := some title }
      #[inner]
  componentEditPayloads <|
    renderPanelInteractive p.d (links := p.links) (mkLink := mkLink)

/-! ## The click simulation -/

/-- A clickable link kind of the panel. -/
inductive Kind
  /-- A drawn edge: inserts the adjacency fact. -/
  | edge
  /-- A drawn vertex: inserts the degree fact. -/
  | degree
  /-- The components stats line: inserts the (dis)connectivity fact. -/
  | connectivity
  deriving BEq

/-- Display label. -/
def Kind.label : Kind → String
  | .edge => "edge"
  | .degree => "degree"
  | .connectivity => "connectivity"

/-- Parse a kind name. -/
def Kind.ofString? : String → Option Kind
  | "edge" => some .edge
  | "degree" => some .degree
  | "connectivity" => some .connectivity
  | _ => none

/-- The panel-offered insertion text a click on the given kind uses: the first
edge link, the first degree link, or the connectivity link. -/
def pickText (l : LinkInfo) : Kind → Option String
  | .edge => l.edges[0]?.map (·.2.2)
  | .degree => l.degrees[0]?.map (·.2)
  | .connectivity => l.connected?

open Command in
/-- Compile `src` in-process and require a clean outcome with exactly one
`#graph_scope` panel; returns the outcome and the decoded panel. -/
def compileClean (ne : NestedEnv) (name src : String) (stage : String) :
    CommandElabM (Outcome × Panel) := do
  let out ← ne.compile src
  unless out.errors.isEmpty do
    throwError "[{name}] {stage}: nested compile has errors:\n  {"\n  ".intercalate out.errors.toList}"
  unless out.sorries == 0 do
    throwError "[{name}] {stage}: nested compile mentions sorry"
  unless out.panels.size == 1 do
    throwError "[{name}] {stage}: expected exactly 1 #graph_scope panel, got {out.panels.size}"
  match decodePanel out.panels[0]! with
  | .error e => throwError "[{name}] {stage}: cannot decode stored panel props: {e}"
  | .ok p => return (out, p)

open Command in
/-- `#e2e_click_scenario "name" "kind,kind,…" (final)? "<user file>"`: compile
the user file in-process (must be clean, one panel, no gate-failed labels),
then simulate each click end to end — real stored props, real `MakeEditLink`
payload, `applyLspEdit`, full recompile, which must be clean and one command
longer.  Between clicks the panel props are re-read from the *recompiled* file,
like the live panel.  With `final`, the final file content is logged (pin it
under `#guard_msgs` to see exactly what the user ends up with). -/
elab "#e2e_click_scenario " name:str ppSpace clicks:str ppSpace showFinal:(&"final" ppSpace)? src:str : command => do
  let name := name.getString
  let src := src.getString
  let kinds ← (clicks.getString.splitOn ",").mapM fun s =>
    match Kind.ofString? s with
    | some k => pure k
    | none => throwError "[{name}] unknown click kind {s}"
  let ne ← NestedEnv.ofHeader src
  let (out, p) ← compileClean ne name src "base"
  unless p.links.notInsertable.isEmpty do
    throwError "[{name}] base: gate-failed labels {p.links.notInsertable}"
  logInfo s!"[{name}] base: clean, {out.commands} commands, \
    links: {p.links.edges.size} edges / {p.links.degrees.size} degrees / \
    connectivity {if p.links.connected?.isSome then "yes" else "no"}"
  let mut cur := src
  let mut out := out
  let mut p := p
  for k in kinds do
    let some txt := pickText p.links k
      | throwError "[{name}] no {k.label} link is offered"
    let edits ← match panelEdits cur p with
      | .error e => throwError "[{name}] cannot decode panel edits: {e}"
      | .ok es => pure es
    let some (uri, range, newText) := edits.find? (fun (_, _, nt) => nt == "\n" ++ txt)
      | throwError "[{name}] no MakeEditLink component carries the {k.label} text"
    unless uri == userUri do
      throwError "[{name}] {k.label} edit targets {uri}, not the user file"
    unless range == p.insertRange do
      throwError "[{name}] {k.label} edit range differs from the stored insertRange"
    cur := applyLspEdit cur range newText
    let (out', p') ← compileClean ne name cur s!"after {k.label} click"
    unless out'.commands == out.commands + 1 do
      throwError "[{name}] {k.label} click: expected {out.commands + 1} commands, \
        got {out'.commands} — the inserted example did not elaborate as one new command"
    logInfo s!"[{name}] click {k.label}: inserted `{txt}` — recompiled clean"
    out := out'
    p := p'
  if showFinal.isSome then
    logInfo s!"[{name}] final file:\n{cur}"

open Command in
/-- `#e2e_negative "mode" "<user file>"`: non-vacuity checks — prove the
harness FAILS when it must.  Modes:

* `"corrupt-text"` — the real edge payload with its last character dropped
  must not recompile;
* `"shift-range"` — the real payload applied one UTF-16 unit early must not
  recompile;
* `"false-claim"` — the real degree payload with its degree value replaced by
  a wrong one must not recompile (`decide` refutes it);
* `"sorry-detect"` — the file (which must contain a `sorry`) compiles without
  errors but the sorry channel must report it.

Each mode logs the failure evidence for pinning under `#guard_msgs`. -/
elab "#e2e_negative " mode:str ppSpace src:str : command => do
  let mode := mode.getString
  let src := src.getString
  let ne ← NestedEnv.ofHeader src
  if mode == "sorry-detect" then
    let out ← ne.compile src
    unless out.errors.isEmpty do
      throwError "[{mode}] file has errors: {out.errors}"
    unless out.sorries > 0 do
      throwError "[{mode}] the sorry went UNDETECTED — happy-path sorry \
        assertions are vacuous"
    logInfo s!"[{mode}] detected {out.sorries} sorry message(s)"
    return
  let (_, p) ← compileClean ne mode src "base"
  let (kind, range, newText) ← match mode with
    | "corrupt-text" => do
      let some txt := pickText p.links .edge | throwError "[{mode}] no edge link"
      let corrupted := ("\n" ++ txt).replace ".Adj" ".Ajd"
      if corrupted == "\n" ++ txt then
        throwError "[{mode}] could not corrupt the edge text {txt}"
      pure ("edge", p.insertRange, corrupted)
    | "shift-range" => do
      let some txt := pickText p.links .edge | throwError "[{mode}] no edge link"
      let shift (pos : Lsp.Position) : Lsp.Position :=
        { pos with character := pos.character - 1 }
      pure ("edge", { start := shift p.insertRange.start
                      «end» := shift p.insertRange.«end» }, "\n" ++ txt)
    | "false-claim" => do
      let some txt := pickText p.links .degree | throwError "[{mode}] no degree link"
      let falsified := txt.replace "= 1 :=" "= 2 :="
      if falsified == txt then
        throwError "[{mode}] could not falsify the degree text {txt}"
      pure ("degree", p.insertRange, "\n" ++ falsified)
    | _ => throwError "[{mode}] unknown negative mode"
  let edited := applyLspEdit src range newText
  let out ← ne.compile edited
  if out.errors.isEmpty then
    throwError "[{mode}] the {kind} corruption recompiled CLEAN — the harness \
      cannot detect broken edits"
  logInfo s!"[{mode}] recompile failed as required; first error: \
    {out.errors[0]!}"

/-! ## The scenarios

Each user file imports ONLY `GraphScope` — in particular the `DecidableRel`
instances for `pathGraph` / `completeBipartiteGraph` must arrive with that
import (they live in `GraphScope.Demo`); these scenarios are the load-bearing
proof of that claim. -/

/--
info: [path5] base: clean, 3 commands, links: 4 edges / 5 degrees / connectivity yes
---
info: [path5] click edge: inserted `example : ((pathGraph 5)).Adj (0) (1) := by decide` — recompiled clean
---
info: [path5] click degree: inserted `example : ((pathGraph 5)).degree (0) = 1 := by decide` — recompiled clean
---
info: [path5] click connectivity: inserted `example : ((pathGraph 5)).Connected := by decide` — recompiled clean
---
info: [path5] final file:
import GraphScope

open SimpleGraph

#graph_scope (pathGraph 5)
example : ((pathGraph 5)).Connected := by decide
example : ((pathGraph 5)).degree (0) = 1 := by decide
example : ((pathGraph 5)).Adj (0) (1) := by decide
-/
#guard_msgs in
#e2e_click_scenario "path5" "edge,degree,connectivity" final
"import GraphScope

open SimpleGraph

#graph_scope (pathGraph 5)
"

/--
info: [cycle6] base: clean, 3 commands, links: 6 edges / 6 degrees / connectivity yes
---
info: [cycle6] click edge: inserted `example : ((cycleGraph 6)).Adj (0) (1) := by decide` — recompiled clean
---
info: [cycle6] click connectivity: inserted `example : ((cycleGraph 6)).Connected := by decide` — recompiled clean
-/
#guard_msgs in
#e2e_click_scenario "cycle6" "edge,connectivity"
"import GraphScope

open SimpleGraph

#graph_scope (cycleGraph 6)
"

/--
info: [fromRel-disconnected] base: clean, 5 commands, links: 4 edges / 6 degrees / connectivity yes
---
info: [fromRel-disconnected] click edge: inserted `example : (myGraph).Adj (0) (1) := by decide` — recompiled clean
---
info: [fromRel-disconnected] click degree: inserted `example : (myGraph).degree (0) = 1 := by decide` — recompiled clean
---
info: [fromRel-disconnected] click connectivity: inserted `example : ¬ (myGraph).Connected := by decide` — recompiled clean
---
info: [fromRel-disconnected] final file:
import GraphScope

open SimpleGraph

-- Two disjoint 3-paths 0-1-2 and 3-4-5.
def myGraph : SimpleGraph (Fin 6) :=
  SimpleGraph.fromRel fun a b => b.val = a.val + 1 ∧ a.val ≠ 2

instance : DecidableRel myGraph.Adj := by unfold myGraph; infer_instance

#graph_scope myGraph
example : ¬ (myGraph).Connected := by decide
example : (myGraph).degree (0) = 1 := by decide
example : (myGraph).Adj (0) (1) := by decide
-/
#guard_msgs in
#e2e_click_scenario "fromRel-disconnected" "edge,degree,connectivity" final
"import GraphScope

open SimpleGraph

-- Two disjoint 3-paths 0-1-2 and 3-4-5.
def myGraph : SimpleGraph (Fin 6) :=
  SimpleGraph.fromRel fun a b => b.val = a.val + 1 ∧ a.val ≠ 2

instance : DecidableRel myGraph.Adj := by unfold myGraph; infer_instance

#graph_scope myGraph
"

/--
info: [completeBipartite] base: clean, 3 commands, links: 4 edges / 4 degrees / connectivity yes
---
info: [completeBipartite] click edge: inserted `example : ((completeBipartiteGraph (Fin 2) (Fin 2))).Adj (Sum.inl 0) (Sum.inr 0) := by decide` — recompiled clean
---
info: [completeBipartite] click degree: inserted `example : ((completeBipartiteGraph (Fin 2) (Fin 2))).degree (Sum.inl 0) = 2 := by decide` — recompiled clean
---
info: [completeBipartite] click connectivity: inserted `example : ((completeBipartiteGraph (Fin 2) (Fin 2))).Connected := by decide` — recompiled clean
-/
#guard_msgs in
#e2e_click_scenario "completeBipartite" "edge,degree,connectivity"
"import GraphScope

open SimpleGraph

#graph_scope (completeBipartiteGraph (Fin 2) (Fin 2))
"

/--
info: [unicode] base: clean, 5 commands, links: 3 edges / 4 degrees / connectivity yes
---
info: [unicode] click edge: inserted `example : («γℝ🎀»).Adj (0) (1) := by decide` — recompiled clean
---
info: [unicode] click degree: inserted `example : («γℝ🎀»).degree (0) = 1 := by decide` — recompiled clean
---
info: [unicode] click connectivity: inserted `example : («γℝ🎀»).Connected := by decide` — recompiled clean
---
info: [unicode] final file:
import GraphScope

open SimpleGraph

-- ℝ⋖🎉 unicode-heavy prelude ℝ⋖🎉ℝ⋖🎉 — the def name below mixes BMP and
-- surrogate-pair characters, so the #graph_scope line contains multibyte
-- text BEFORE the insertion point: a UTF-16 bug shifts every click's edit.
def «γℝ🎀» : SimpleGraph (Fin 4) := pathGraph 4

instance : DecidableRel («γℝ🎀»).Adj := by unfold «γℝ🎀»; infer_instance

#graph_scope «γℝ🎀»
example : («γℝ🎀»).Connected := by decide
example : («γℝ🎀»).degree (0) = 1 := by decide
example : («γℝ🎀»).Adj (0) (1) := by decide
-/
#guard_msgs in
#e2e_click_scenario "unicode" "edge,degree,connectivity" final
"import GraphScope

open SimpleGraph

-- ℝ⋖🎉 unicode-heavy prelude ℝ⋖🎉ℝ⋖🎉 — the def name below mixes BMP and
-- surrogate-pair characters, so the #graph_scope line contains multibyte
-- text BEFORE the insertion point: a UTF-16 bug shifts every click's edit.
def «γℝ🎀» : SimpleGraph (Fin 4) := pathGraph 4

instance : DecidableRel («γℝ🎀»).Adj := by unfold «γℝ🎀»; infer_instance

#graph_scope «γℝ🎀»
"

/-! ## Non-vacuity: the harness must fail when it must -/

/--
info: [corrupt-text] recompile failed as required; first error: Invalid field `Ajd`: The environment does not contain `SimpleGraph.Ajd`, so it is not possible to project the field `Ajd` from an expression
-/
#guard_msgs in
#e2e_negative "corrupt-text"
"import GraphScope

open SimpleGraph

#graph_scope (pathGraph 5)
"

/--
info: [shift-range] recompile failed as required; first error: unexpected token 'example'; expected ')', ',' or ':'
-/
#guard_msgs in
#e2e_negative "shift-range"
"import GraphScope

open SimpleGraph

#graph_scope (pathGraph 5)
"

/--
info: [false-claim] recompile failed as required; first error: Tactic `decide` proved that the proposition
-/
#guard_msgs in
#e2e_negative "false-claim"
"import GraphScope

open SimpleGraph

#graph_scope (pathGraph 5)
"

/-- info: [sorry-detect] detected 1 sorry message(s) -/
#guard_msgs in
#e2e_negative "sorry-detect"
"import GraphScope

open SimpleGraph

example : (pathGraph 3).Connected := by sorry
"

end E2E
end GraphScopeTests
