import Lean.Elab.Frontend
import IntervalInspectorTests.Helpers

/-! # End-to-end click-simulation tests for `interval_inspect?` suggestion links

The InfoView panel renders each suggestion as a `MakeEditLink` that replaces the
`interval_inspect?` tactic call with the suggestion's tactic text.  These tests
simulate the click all the way through **user files**:

1. compile a realistic user source *string* with the real Lean frontend, in-process
   (header parse → `processHeader` imports → `processCommands`);
2. read the **stored panel props** out of the resulting info tree — the same
   `replaceRange` json the InfoView sends back to `IntervalInspectorPanel.rpc` —
   and recompute the suggestion list exactly the way the RPC method does (first
   goal, sanitized local context, `analyzeWithLCtx?`);
3. build the edit payload with the *real* prop builder the panel uses
   (`MakeEditLinkProps.ofReplaceRange`), apply it to the source with Lean's own
   UTF-16 position conversion (`FileMap.lspPosToUtf8Pos` — LSP ranges are UTF-16
   code units, not bytes, not codepoints);
4. recompile the edited file and pin the outcome: clean compile with the goal
   closed for `exact`/`rw`-style suggestions, or the **exact** designed
   unsolved-goals message for `refine … ?_` suggestions (the side-condition badges
   told the user which goals would remain).

Negative tests corrupt the payload (wrong `newText`, shifted range) and require the
edited file to *fail* to compile — proving the happy-path assertions are not
vacuous.  Pure `#guard`s pin `applyLspEdit` on multibyte strings (`ℝ`, `⋖`, `😀`)
against byte-offset misinterpretation.
-/

namespace IntervalInspectorTests.ClickE2E

open Lean Elab ProofWidgets IntervalInspector

/-- `Lean.enableInitializersExecution` is `unsafe`, but it only flips the
process-global initializers flag; core itself re-enables it mid-process in
`runFrontend`'s incremental-load path.  Nested `importModules (loadExts := true)`
(here: importing the user file's header) requires it.  Since Lean v4.34 the core
function lives in `BaseIO` (it cannot fail), and `implemented_by` requires the
types to agree exactly. -/
@[implemented_by Lean.enableInitializersExecution]
opaque enableInitializersExecutionSafe : BaseIO Unit

/-! ## UTF-16-correct edit application -/

/-- Splice `newText` over the byte range `[b, e)` of `src`. -/
def spliceUtf8 (src : String) (b e : String.Pos.Raw) (newText : String) : String :=
  (src.toRawSubstring.extract 0 b).toString ++ newText
    ++ (src.toRawSubstring.extract e ⟨src.utf8ByteSize⟩).toString

/-- Apply a single LSP text edit to a source string.  LSP `Range`s count UTF-16
code units; conversion to byte positions goes through Lean's own
`FileMap.lspPosToUtf8Pos`. -/
def applyLspEdit (src : String) (range : Lsp.Range) (newText : String) : String :=
  let fm := FileMap.ofString src
  spliceUtf8 src (fm.lspPosToUtf8Pos range.start) (fm.lspPosToUtf8Pos range.end) newText

/-- The *bug* the UTF-16 tests must catch: interpreting `Lsp.Position.character`
as a **byte** offset within the line.  Only used to pin that it disagrees with
`applyLspEdit` on multibyte lines (and agrees on pure-ASCII ones). -/
def applyEditNaiveBytes (src : String) (range : Lsp.Range) (newText : String) : String :=
  let lineStartByte (line : Nat) : Nat := Id.run do
    let bytes := src.toUTF8
    let mut i := 0
    let mut ln := 0
    while ln < line && i < bytes.size do
      if bytes[i]! == 10 then ln := ln + 1
      i := i + 1
    return i
  spliceUtf8 src ⟨lineStartByte range.start.line + range.start.character⟩
    ⟨lineStartByte range.end.line + range.end.character⟩ newText

/-- The *other* bug the UTF-16 tests must catch: interpreting
`Lsp.Position.character` as a **codepoint** offset within the line.  Codepoints
agree with UTF-16 units on BMP-only text (`ℝ`, `⋖`, `≤` are 1 unit each) but
disagree on astral characters (`😀` is 2 UTF-16 units, 1 codepoint). -/
def applyEditNaiveCodepoints (src : String) (range : Lsp.Range) (newText : String) : String :=
  let cps := src.toList
  let idxOf (p : Lsp.Position) : Nat := Id.run do
    let mut i := 0
    let mut ln := 0
    while ln < p.line && i < cps.length do
      if cps[i]! == '\n' then ln := ln + 1
      i := i + 1
    return i + p.character
  String.ofList (cps.take (idxOf range.start)) ++ newText
    ++ String.ofList (cps.drop (idxOf range.end))

/-! ### `applyLspEdit` unit pins on multibyte strings

`ℝ` (U+211D) and `⋖` (U+22D6) are 1 UTF-16 unit / 3 UTF-8 bytes; `😀` (U+1F600)
is 2 UTF-16 units / 4 UTF-8 bytes.  In `"ℝ⋖😀x"` the `x` is at UTF-16 units
`[4, 5)` but bytes `[10, 11)` and codepoints `[3, 4)` — the three interpretations
give three different edits. -/

#guard applyLspEdit "ℝ⋖😀x" ⟨⟨0, 4⟩, ⟨0, 5⟩⟩ "Y" == "ℝ⋖😀Y"
#guard applyLspEdit "ℝ⋖😀x" ⟨⟨0, 0⟩, ⟨0, 1⟩⟩ "Q" == "Q⋖😀x"
-- insertion (empty range) right after the emoji
#guard applyLspEdit "aℝ😀b\ncd" ⟨⟨0, 4⟩, ⟨0, 4⟩⟩ "!" == "aℝ😀!b\ncd"
-- deletion of a multibyte span
#guard applyLspEdit "aℝ😀b" ⟨⟨0, 1⟩, ⟨0, 4⟩⟩ "" == "ab"
-- replacement spanning a newline, with unicode before the edit on the first line
#guard applyLspEdit "≤≤\nxy\nz" ⟨⟨0, 1⟩, ⟨1, 1⟩⟩ "-" == "≤-y\nz"
-- unicode-heavy *earlier lines* must not shift a later line's edit
#guard applyLspEdit "😀😀😀\nabc" ⟨⟨1, 1⟩, ⟨1, 2⟩⟩ "B" == "😀😀😀\naBc"
-- the byte misinterpretation agrees on ASCII …
#guard applyEditNaiveBytes "abc\ndef" ⟨⟨1, 0⟩, ⟨1, 1⟩⟩ "D" ==
       applyLspEdit "abc\ndef" ⟨⟨1, 0⟩, ⟨1, 1⟩⟩ "D"
-- … and disagrees on the multibyte line (this is the bug class the E2E scenarios
-- below would catch: their pinned edited files contain multibyte text *before*
-- the replace range).
#guard applyEditNaiveBytes "ℝ⋖😀x" ⟨⟨0, 4⟩, ⟨0, 5⟩⟩ "Y" !=
       applyLspEdit "ℝ⋖😀x" ⟨⟨0, 4⟩, ⟨0, 5⟩⟩ "Y"
-- the codepoint misinterpretation agrees on BMP-only unicode (`ℝ⋖` are 1 UTF-16
-- unit each) …
#guard applyEditNaiveCodepoints "ℝ⋖x\nab" ⟨⟨0, 2⟩, ⟨1, 1⟩⟩ "-" ==
       applyLspEdit "ℝ⋖x\nab" ⟨⟨0, 2⟩, ⟨1, 1⟩⟩ "-"
-- … and disagrees once an astral character (surrogate pair: `😀` = 2 UTF-16
-- units, 1 codepoint) precedes the edit on the same line: it grabs the `x` one
-- position too far right.
#guard applyEditNaiveCodepoints "ℝ⋖😀x" ⟨⟨0, 4⟩, ⟨0, 5⟩⟩ "Y" == "ℝ⋖😀xY" -- wrong!
#guard applyEditNaiveCodepoints "ℝ⋖😀x" ⟨⟨0, 4⟩, ⟨0, 5⟩⟩ "Y" !=
       applyLspEdit "ℝ⋖😀x" ⟨⟨0, 4⟩, ⟨0, 5⟩⟩ "Y"

/-! ## In-process frontend compilation of user-file strings -/

/-- Outcome of compiling one user-file string with the real frontend. -/
structure CompileResult where
  /-- Final environment (used to check the user's declaration landed, sorry-free). -/
  env : Environment
  /-- All diagnostics, rendered. -/
  messages : List (MessageSeverity × Position × String)
  /-- Info trees of all commands (they hold the stored panel-widget props). -/
  trees : List InfoTree

/-- Compile a Lean source string with the full frontend: header parse, real
`importModules` on the header's imports (resolved through the ambient search
path), then command elaboration.  This is the same pipeline
`Lean.Elab.runFrontend` drives for a file on disk. -/
def compileUser (src : String) (fileName : String := "UserFile.lean") : IO CompileResult := do
  enableInitializersExecutionSafe
  let inputCtx := Parser.mkInputContext src fileName
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  let (env, messages) ← Elab.processHeader header {} messages inputCtx
  -- `IO.processCommands` re-collects messages from command snapshots only, so
  -- surface header-stage errors (e.g. a failed import) here.
  if messages.hasErrors then
    let msgs ← messages.toList.mapM fun m => do
      return (m.severity, m.pos, (← m.data.toString))
    return { env, messages := msgs, trees := [] }
  let s ← Elab.IO.processCommands inputCtx parserState (Command.mkState env messages {})
  let msgs ← s.commandState.messages.toList.mapM fun m => do
    return (m.severity, m.pos, (← m.data.toString))
  return { env := s.commandState.env, messages := msgs
           trees := s.commandState.infoState.trees.toList }

/-- Errors only, rendered `line:column text`, joined by `\n===\n`. -/
def CompileResult.errorReport (r : CompileResult) : String :=
  let errs := r.messages.filterMap fun (sev, p, s) =>
    if sev matches .error then some s!"{p.line}:{p.column} {s}" else none
  String.intercalate "\n===\n" errs

def CompileResult.hasErrors (r : CompileResult) : Bool :=
  r.messages.any fun (sev, _, _) => sev matches .error

def CompileResult.hasSorryMessage (r : CompileResult) : Bool :=
  r.messages.any fun (_, _, s) => strContains s "sorry"

/-- Is `decl` present in the final environment with a sorry-free value?  This is
the "the inserted declaration elaborated and the goal is closed" check. -/
def CompileResult.declClean (r : CompileResult) (decl : Name) : Bool :=
  match r.env.find? decl with
  | some ci => match ci.value? (allowOpaque := true) with
    | some v => !v.hasSorry
    | none => false
  | none => false

/-! ## Extracting the real click payload -/

/-- The panel-widget instances stored while compiling: `(javascriptHash, props)`
with the lazily-encoded props forced to `Json`.  For `interval_inspect?` the props
are exactly `{ replaceRange : Lsp.Range }` — what the InfoView round-trips back to
`IntervalInspectorPanel.rpc` as `InspectorParams.replaceRange`. -/
def CompileResult.panelProps (r : CompileResult) : List (UInt64 × Json) :=
  r.trees.flatMap fun t => t.deepestNodes fun _ i _ =>
    match i with
    | .ofUserWidgetInfo wi => some (wi.javascriptHash, (wi.props.run {}).1)
    | _ => none

/-- Suggestion lists computed the way `IntervalInspectorPanel.rpc` computes them:
for each `interval_inspect?` tactic node, take the first goal, sanitize the local
context, and run `analyzeWithLCtx?` on the goal type. -/
def CompileResult.panelSuggestions (r : CompileResult) : IO (List (Array Suggestion)) := do
  let nodes := r.trees.flatMap fun t => t.deepestNodes fun ctx i _ =>
    match i with
    | .ofTacticInfo ti =>
      if ti.stx.getKind == ``IntervalInspector.intervalInspectTac then some (ctx, ti) else none
    | _ => none
  nodes.mapM fun (ctx, ti) => do
    let ctx' := { ctx with mctx := ti.mctxBefore }
    ctx'.runMetaM {} do
      let some g := ti.goalsBefore.head? | return #[]
      let md ← g.getDecl
      let lctx := md.lctx.sanitizeNames.run' { options := (← getOptions) }
      Meta.withLCtx lctx md.localInstances do
        let some a ← analyzeWithLCtx? md.type | return #[]
        return a.suggestions

/-- Everything one simulated click produces. -/
structure ClickResult where
  /-- The clicked link's inserted text (from the real `MakeEditLinkProps`). -/
  newText : String
  /-- The user file after applying the edit. -/
  edited : String
  /-- Where the editor puts the cursor after the edit (collapsed selection). -/
  newSelection? : Option Lsp.Range
  /-- Result of recompiling the edited file. -/
  post : CompileResult

/-- Simulate clicking the suggestion whose `lemmaName` is `pick` (the
`pickIdx`-th such suggestion) in the panel attached to the single
`interval_inspect?` call of `src`:

* compile `src`, read the stored panel props (checking the widget hash is the
  inspector panel's), parse `replaceRange` out of them;
* recompute the suggestion list the RPC way and select the picked one;
* build the edit with `MakeEditLinkProps.ofReplaceRange` (the code path the panel
  itself uses), apply it with `applyLspEdit`, recompile.

`mutateText`/`shiftChars` deliberately corrupt the payload *after* it is built —
used by the negative tests only. -/
def runClick (src : String) (pick : String) (pickIdx : Nat)
    (mutateText : String → String := id) (shiftChars : Nat := 0) : IO ClickResult := do
  let res ← compileUser src
  let props := res.panelProps
  let expectedHash := hash IntervalInspectorPanel.javascript
  unless props.length == 1 do
    throw <| IO.userError s!"expected exactly 1 stored panel widget, got {props.length}"
  let (h, propsJson) := props.head!
  unless h == expectedHash do
    throw <| IO.userError "stored widget hash is not the inspector panel's"
  let .ok rangeJson := propsJson.getObjVal? "replaceRange"
    | throw <| IO.userError s!"stored props have no replaceRange: {propsJson.compress}"
  let .ok (replaceRange : Lsp.Range) := fromJson? rangeJson
    | throw <| IO.userError s!"replaceRange does not parse as Lsp.Range: {rangeJson.compress}"
  let suggs ← res.panelSuggestions
  unless suggs.length == 1 do
    throw <| IO.userError s!"expected exactly 1 interval_inspect? tactic node, got {suggs.length}"
  let some sug := (suggs.head!.filter (·.lemmaName == pick))[pickIdx]?
    | throw <| IO.userError
        s!"no suggestion {pick}[{pickIdx}]; offered: {suggs.head!.map (·.lemmaName)}"
  -- The real prop builder the panel uses (`.ofReplaceRange doc.meta range tac`).
  -- The `DocumentMeta` is fabricated (uri/version); range and newText — the parts
  -- the edit application depends on — are the genuine payload.
  let docMeta : Server.DocumentMeta :=
    { uri := "file:///E2E/UserFile.lean", mod := `UserFile, version := 1
      text := FileMap.ofString src, dependencyBuildMode := .always }
  let mel := MakeEditLinkProps.ofReplaceRange docMeta replaceRange sug.tactic
  unless mel.edit.textDocument.uri == docMeta.uri do
    throw <| IO.userError "edit targets a different document"
  let edits : Array Lsp.TextEdit := mel.edit.edits
  unless edits.size == 1 do
    throw <| IO.userError s!"expected exactly 1 text edit, got {edits.size}"
  let some te := edits[0]? | throw <| IO.userError "no text edit"
  let shift (p : Lsp.Position) : Lsp.Position := { p with character := p.character + shiftChars }
  let range : Lsp.Range := ⟨shift te.range.start, shift te.range.end⟩
  let newText := mutateText te.newText
  let edited := applyLspEdit src range newText
  let post ← compileUser edited
  return { newText := te.newText, edited, newSelection? := mel.newSelection?, post }

/-- Render a collapsed selection as `"line:character"` (0-based LSP coordinates). -/
def selReport (sel? : Option Lsp.Range) : String :=
  match sel? with
  | none => "-"
  | some r =>
    if r.start == r.end then s!"{r.start.line}:{r.start.character}"
    else s!"{r.start.line}:{r.start.character}-{r.end.line}:{r.end.character}"

/-! ## Assertion commands (each use is one build-failing assertion) -/

open Command in
/-- Shared driver: run the click, then check the requested pins. -/
def assertClick (src pick : String) (pickIdx : Nat)
    (tacPin? afterPin? errPin? selPin? : Option String)
    (decl? : Option Name) : CommandElabM Unit := do
  let r ← runClick src pick pickIdx
  if let some tacPin := tacPin? then
    unless r.newText == tacPin do
      throwError "inserted tactic mismatch:\n  expected: {tacPin}\n  actual:   {r.newText}"
  if let some afterPin := afterPin? then
    unless r.edited == afterPin do
      throwError "edited file mismatch:\n--- expected ---\n{afterPin}\n--- actual ---\n{r.edited}"
  if let some selPin := selPin? then
    unless selReport r.newSelection? == selPin do
      throwError "cursor mismatch:\n  expected: {selPin}\n  actual:   {selReport r.newSelection?}"
  match errPin? with
  | some errPin =>
    unless r.post.errorReport == errPin do
      throwError "post-edit errors mismatch:\n--- expected ---\n{errPin}\n--- actual ---\n{r.post.errorReport}"
  | none =>
    if r.post.hasErrors then
      throwError "edited file does not compile:\n{r.post.errorReport}"
    if r.post.hasSorryMessage then
      throwError "edited file mentions sorry"
    if let some decl := decl? then
      unless r.post.declClean decl do
        throwError "declaration {decl} missing or contains sorry after the edit"

/-- `#assert_click_closes decl "lemma" idx? "src" => "tac" "sel"?`: clicking the
suggestion inserts exactly `tac`, the edited file compiles with zero errors and no
sorries, and `decl` elaborated sorry-free (goal closed).  Optional trailing pin:
the post-edit cursor position `"line:char"` (0-based, UTF-16). -/
elab "#assert_click_closes " decl:ident pick:str idx:(num)? src:str " => " tac:str sel:(str)? : command => do
  assertClick src.getString pick.getString ((idx.map (·.getNat)).getD 0)
    (some tac.getString) none none (sel.map (·.getString)) (some decl.getId)

/-- `#assert_click_goals decl "lemma" idx? "src" => "tac" "errors" "sel"?`: clicking
inserts exactly `tac` and the edited file errors with **exactly** the pinned
unsolved-goals report — the designed contract for `refine … ?_` suggestions whose
side conditions the badges displayed. -/
elab "#assert_click_goals " decl:ident pick:str idx:(num)? src:str " => " tac:str err:str sel:(str)? : command => do
  let _ := decl  -- named for readability of the test site
  assertClick src.getString pick.getString ((idx.map (·.getNat)).getD 0)
    (some tac.getString) none (some err.getString) (sel.map (·.getString)) none

/-- `#assert_click_file decl "lemma" idx? "src" => "after" "sel"?`: pin the **entire
edited file** (this is what catches UTF-16 range bugs on unicode-heavy lines), and
require it to compile cleanly with `decl` sorry-free. -/
elab "#assert_click_file " decl:ident pick:str idx:(num)? src:str " => " after:str sel:(str)? : command => do
  assertClick src.getString pick.getString ((idx.map (·.getNat)).getD 0)
    none (some after.getString) none (sel.map (·.getString)) (some decl.getId)

/-- `#assert_click_broken "mode" "lemma" idx? "src"`: corrupt the real payload
(`"corrupt-newtext"` misspells the tactic text; `"shift-range"` moves the range one
UTF-16 unit right) and require the edited file to **fail** to compile — the
happy-path assertions above are not vacuous. -/
elab "#assert_click_broken " mode:str pick:str idx:(num)? src:str : command => do
  let m := mode.getString
  let mutateText : String → String :=
    if m == "corrupt-newtext" then
      fun t => t.replace "exact" "exagt" |>.replace "refine" "refinne"
    else id
  let shiftChars := if m == "shift-range" then 1 else 0
  unless m == "corrupt-newtext" || m == "shift-range" do
    throwError "unknown mode {m}"
  let r ← runClick src.getString pick.getString ((idx.map (·.getNat)).getD 0)
    (mutateText := mutateText) (shiftChars := shiftChars)
  if m == "corrupt-newtext" && mutateText r.newText == r.newText then
    throwError "corruption was a no-op; pick a scenario whose tactic contains exact/refine"
  unless r.post.hasErrors do
    throwError "corrupted click payload ({m}) still compiled — the harness is vacuous:\n{r.edited}"

/-! ## The user files

Realistic sources: they import only the package's public library plus the Mathlib
module a user working over `ℝ` naturally has.  LSP coordinates are UTF-16, so the
pinned `replaceRange`s/cursors below silently depend on correct unit counting —
and E1 places `ℝ ≤ ⊆ ∅ — 😀 ⟨⟩` (3- and 4-byte UTF-8, incl. a surrogate-pair
emoji) *before* the tactic call, both on earlier lines and **on the same line**:
a byte- or codepoint-offset bug shifts the edit into the middle of the comment. -/

def userHeader : String := "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\n"

/-! ### E1 — `exact` suggestion, unicode-heavy file (kind: cross-kind inclusion) -/

#assert_click_file clickS1 "Set.Ioo_subset_Icc_self"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\n/-! ℝ≤⊆∅ unicode ballast — 😀 emoji and ⟨brackets⟩ before the theorem. -/\n\ntheorem clickS1 {a b : ℝ} : Set.Ioo a b ⊆ Set.Icc a b := by /- 😀ℝ≤ -/ interval_inspect?\n"
  =>
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\n/-! ℝ≤⊆∅ unicode ballast — 😀 emoji and ⟨brackets⟩ before the theorem. -/\n\ntheorem clickS1 {a b : ℝ} : Set.Ioo a b ⊆ Set.Icc a b := by /- 😀ℝ≤ -/ exact Set.Ioo_subset_Icc_self\n"
  "5:100"

/-! ### E2 — the motivating union join, ALL-READY: hypotheses make both side
conditions ready, and clicking still (by design) leaves them as `refine` goals —
pinned exactly, hypotheses visible in context.  The badges showed `a ≤ b ✓ ready`,
`b ≤ c ✓ ready`; the user closes the two goals with `exact h₁`/`exact h₂`. -/

#assert_click_goals clickS2 "Set.Ioc_union_Ioc_eq_Ioc"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS2 {a b c : ℝ} (h₁ : a ≤ b) (h₂ : b ≤ c) :\n    Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c := by\n  interval_inspect?\n"
  =>
  "refine Set.Ioc_union_Ioc_eq_Ioc ?_ ?_"
  "5:47 unsolved goals\ncase refine_1\na b c : ℝ\nh₁ : a ≤ b\nh₂ : b ≤ c\n⊢ a ≤ b\n\ncase refine_2\na b c : ℝ\nh₁ : a ≤ b\nh₂ : b ≤ c\n⊢ b ≤ c"
  "5:39"

/-- The completed proof the panel walks the user toward (edit + discharging the
two ready side conditions with the hypotheses the badges pointed at). -/
example {a b c : ℝ} (h₁ : a ≤ b) (h₂ : b ≤ c) :
    Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c := by
  refine Set.Ioc_union_Ioc_eq_Ioc ?_ ?_
  · exact h₁
  · exact h₂

/-! ### E3 — same union join with **missing** side conditions (no hypotheses):
identical insertion, and the leftover goals are exactly the conditions the badges
flagged `✗ missing`. -/

#assert_click_goals clickS3 "Set.Ioc_union_Ioc_eq_Ioc"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS3 {a b c : ℝ} : Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c := by\n  interval_inspect?\n"
  =>
  "refine Set.Ioc_union_Ioc_eq_Ioc ?_ ?_"
  "4:73 unsolved goals\ncase refine_1\na b c : ℝ\n⊢ a ≤ b\n\ncase refine_2\na b c : ℝ\n⊢ b ≤ c"
  "4:39"

/-! ### E4 — membership unfolding (`refine Set.mem_Ioc.mpr ⟨?_, ?_⟩`; the inserted
text itself contains multibyte `⟨⟩`, exercising the UTF-16 cursor advance). -/

#assert_click_goals clickS4 "Set.mem_Ioc"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS4 {x a b : ℝ} (h₁ : a < x) (h₂ : x ≤ b) : x ∈ Set.Ioc a b := by\n  interval_inspect?\n"
  =>
  "refine Set.mem_Ioc.mpr ⟨?_, ?_⟩"
  "4:75 unsolved goals\ncase refine_1\nx a b : ℝ\nh₁ : a < x\nh₂ : x ≤ b\n⊢ a < x\n\ncase refine_2\nx a b : ℝ\nh₁ : a < x\nh₂ : x ≤ b\n⊢ x ≤ b"
  "4:33"

/-! ### E5 — whole-line cover, `exact` with no side conditions: goal closed. -/

#assert_click_closes clickS5 "Set.Iic_union_Ici"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS5 (c : ℝ) : Set.Iic c ∪ Set.Ici c = Set.univ := by\n  interval_inspect?\n"
  =>
  "exact Set.Iic_union_Ici"
  "4:25"

/-! ### E6 — intersection normal form, `rw` suggestion: the rewrite's `rfl`
closes the goal when the target is stated in `⊔`/`⊓` form. -/

#assert_click_closes clickS6 "Set.Ioc_inter_Ioc"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS6 {a b c d : ℝ} :\n    Set.Ioc a b ∩ Set.Ioc c d = Set.Ioc (a ⊔ c) (b ⊓ d) := by\n  interval_inspect?\n"
  =>
  "rw [Set.Ioc_inter_Ioc]"
  "5:24"

/-! ### E7 — `≠ ∅` via composed `refine (Set.nonempty_Icc.mpr ?_).ne_empty`
(parenthesized composite; single leftover goal, no case label). -/

#assert_click_goals clickS7 "Set.Nonempty.ne_empty"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS7 {a b : ℝ} (h : a ≤ b) : Set.Icc a b ≠ ∅ := by\n  interval_inspect?\n"
  =>
  "refine (Set.nonempty_Icc.mpr ?_).ne_empty"
  "4:59 unsolved goals\na b : ℝ\nh : a ≤ b\n⊢ a ≤ b"
  "4:43"

/-! ### E8 — fallback suggestion (membership in a union: no table entry): the
labeled heuristic `constructor <;> simp_all` closes the goal in a file whose
hypotheses supply the bounds.  Known wart, accepted: Mathlib's `<;>` linter warns
in the edited file when `constructor` happens to produce a single goal (warning
only — the file compiles and the proof is closed). -/

#assert_click_closes clickS8 "(fallback)"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS8 {x a b c : ℝ} (h₁ : a ≤ x) (h₂ : x ≤ b) :\n    x ∈ Set.Icc a b ∪ Set.Ioc b c := by\n  interval_inspect?\n"
  =>
  "constructor <;> simp_all"
  "5:26"

/-! ### E9 — reversed emptiness `∅ = Icc a b`: the `.symm`-wrapped composite. -/

#assert_click_goals clickS9 "Eq.symm"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS9 {a b : ℝ} (h : b < a) : (∅ : Set ℝ) = Set.Icc a b := by\n  interval_inspect?\n"
  =>
  "refine (Set.Icc_eq_empty (not_le.mpr ?_)).symm"
  "4:69 unsolved goals\na b : ℝ\nh : b < a\n⊢ b < a"
  "4:48"

/-! ### E10 — a panel offering **two** suggestions (`Ioc a b = ∅` matches both the
direct and the `_iff` emptiness entries): clicking each one produces its own
insertion, same leftover goal. -/

#assert_click_goals clickS10 "Set.Ioc_eq_empty"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS10 {a b : ℝ} (h : b ≤ a) : Set.Ioc a b = ∅ := by\n  interval_inspect?\n"
  =>
  "refine Set.Ioc_eq_empty (not_lt.mpr ?_)"
  "4:60 unsolved goals\na b : ℝ\nh : b ≤ a\n⊢ b ≤ a"
  "4:41"

#assert_click_goals clickS10 "Set.Ioc_eq_empty_iff"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS10 {a b : ℝ} (h : b ≤ a) : Set.Ioc a b = ∅ := by\n  interval_inspect?\n"
  =>
  "refine Set.Ioc_eq_empty_iff.mpr (not_lt.mpr ?_)"
  "4:60 unsolved goals\na b : ℝ\nh : b ≤ a\n⊢ b ≤ a"
  "4:49"

/-! ### E11 — same-kind inclusion monotonicity (`refine Set.Icc_subset_Icc ?_ ?_`):
two endpoint side conditions, both ready from hypotheses; the leftover goals are
exactly the monotonicity conditions the badges displayed. -/

#assert_click_goals clickS11 "Set.Icc_subset_Icc"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS11 {a b c d : ℝ} (h₁ : c ≤ a) (h₂ : b ≤ d) :\n    Set.Icc a b ⊆ Set.Icc c d := by\n  interval_inspect?\n"
  =>
  "refine Set.Icc_subset_Icc ?_ ?_"
  "5:33 unsolved goals\ncase refine_1\na b c d : ℝ\nh₁ : c ≤ a\nh₂ : b ≤ d\n⊢ c ≤ a\n\ncase refine_2\na b c d : ℝ\nh₁ : c ≤ a\nh₂ : b ≤ d\n⊢ b ≤ d"
  "5:33"

/-! ### E12 — ray membership unfolding (`refine Set.mem_Ici.mpr ?_`): single
leftover goal, no case label. -/

#assert_click_goals clickS12 "Set.mem_Ici"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS12 {x a : ℝ} (h : a ≤ x) : x ∈ Set.Ici a := by\n  interval_inspect?\n"
  =>
  "refine Set.mem_Ici.mpr ?_"
  "4:58 unsolved goals\nx a : ℝ\nh : a ≤ x\n⊢ a ≤ x"
  "4:27"

/-! ### E13 — nonemptiness (`refine Set.nonempty_Icc.mpr ?_`): the leftover goal
is the endpoint order condition. -/

#assert_click_goals clickS13 "Set.nonempty_Icc"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickS13 {a b : ℝ} (h : a ≤ b) : (Set.Icc a b).Nonempty := by\n  interval_inspect?\n"
  =>
  "refine Set.nonempty_Icc.mpr ?_"
  "4:67 unsolved goals\na b : ℝ\nh : a ≤ b\n⊢ a ≤ b"
  "4:32"

/-! ## Negative controls — the harness must fail on corrupted payloads -/

-- Misspelled tactic text (exact → exagt) must not compile.
#assert_click_broken "corrupt-newtext" "Set.Iic_union_Ici"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\ntheorem clickN1 (c : ℝ) : Set.Iic c ∪ Set.Ici c = Set.univ := by\n  interval_inspect?\n"

-- Replace range shifted one UTF-16 unit right — on the unicode-ballast file — must
-- not compile (the stray `i` of `interval_inspect?` survives in front of the edit).
#assert_click_broken "shift-range" "Set.Ioo_subset_Icc_self"
  "import IntervalInspector\nimport Mathlib.Basic.Real.Basic\n\n/-! ℝ≤⊆∅ unicode ballast — 😀 emoji and ⟨brackets⟩ before the theorem. -/\n\ntheorem clickN2 {a b : ℝ} : Set.Ioo a b ⊆ Set.Icc a b := by /- 😀ℝ≤ -/ interval_inspect?\n"

end IntervalInspectorTests.ClickE2E
