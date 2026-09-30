import Lean.Elab.Frontend
import HasseViewTests.Helpers
import HasseView.Demo

/-! # ClickE2E: end-to-end click-simulation tests

Does clicking an insertable-example link produce **genuinely usable code in a
real user file**?  This module answers by simulation with no shortcuts:

1. **Real user files** are compiled *in-process* through Lean's own frontend
   (`Parser.parseHeader` → `Elab.processHeader` → `Elab.IO.processCommands`
   — header imports included, resolved via the ambient search path).
2. The **real edit payload** is read back from the compiled file's info tree:
   the `HassePanelProps` stored by `savePanelWidgetInfo` (insertion range +
   gate-verified `newText`s) — exactly what the RPC method wraps in
   `MakeEditLink` and the InfoView sends back as a `TextDocumentEdit`.
3. The **click** is simulated by `applyLspEdit`, a thin wrapper over the
   language server's own `Lean.Server.replaceLspRange` — LSP ranges are
   **UTF-16 code units**, and the unit tests below pin that byte- or
   codepoint-based interpretations would produce different (wrong) results.
4. The **edited file is recompiled** and must produce ZERO messages: no
   errors, no `sorry` warnings, nothing.  Negative tests prove non-vacuity:
   a corrupted `newText` or a shifted range makes the recompile fail loudly.

One feasibility note (probed before this module was written): the outer
compiler disables initializer execution after its own imports
(`withImporting` resets the flag), so the nested `importModules` needs
`enableInitializersExecution` re-enabled — the same call core's
`runFrontend` makes on its incremental-reuse path.

What this simulation still cannot cover: the JavaScript side of
`MakeEditLink` (bundled with ProofWidgets, pinned by the serializer tests in
`LinkTests`) and VS Code's `applyWorkspaceEdit` itself.  Everything between
the stored props and the recompiled buffer is exercised for real.
-/

namespace HasseViewTests.E2E

open Lean Elab HasseView

/-! ## applyLspEdit: the simulated click

`Lean.Server.replaceLspRange` is the function the language server itself
uses to apply LSP document changes, so the simulation applies edits with the
server's exact UTF-16 semantics rather than a re-implementation. -/

/-- Apply a `TextDocumentEdit`-style `(range, newText)` edit to a source
string.  LSP positions are (line, UTF-16 code unit) pairs. -/
def applyLspEdit (src : String) (r : Lsp.Range) (newText : String) : String :=
  (Lean.Server.replaceLspRange src.toFileMap r newText).source

-- Multibyte pins: `ℝ` is 3 UTF-8 bytes but ONE UTF-16 unit — a byte-offset
-- interpretation of `character` would land inside the character.
#guard applyLspEdit "aℝb" ⟨⟨0, 2⟩, ⟨0, 2⟩⟩ "X" == "aℝXb"
#guard applyLspEdit "aℝb" ⟨⟨0, 1⟩, ⟨0, 2⟩⟩ "X" == "aXb"
-- `😀` is ONE codepoint but TWO UTF-16 units — a codepoint interpretation
-- would place the edit after `b` instead of after the emoji.
#guard applyLspEdit "a😀b" ⟨⟨0, 3⟩, ⟨0, 3⟩⟩ "X" == "a😀Xb"
#guard applyLspEdit "a😀b" ⟨⟨0, 1⟩, ⟨0, 1⟩⟩ "X" == "aX😀b"
-- `⋖` (the cover glyph every inserted example contains) is 1 UTF-16 unit.
#guard applyLspEdit "x ⋖ y\nz" ⟨⟨0, 2⟩, ⟨0, 3⟩⟩ "≤" == "x ≤ y\nz"
-- Unicode-heavy line BEFORE the edit must not shift an edit on a later line.
#guard applyLspEdit "ℝ😀⋖\nabc" ⟨⟨1, 1⟩, ⟨1, 2⟩⟩ "X" == "ℝ😀⋖\naXc"
-- Zero-width insertion at the exact end of a line ending in an emoji.
#guard applyLspEdit "-- ∀ε😀\n#x" ⟨⟨0, 7⟩, ⟨0, 7⟩⟩ "!" == "-- ∀ε😀!\n#x"

/-! ## Cursor sanity: where `MakeEditLink` puts the cursor after the click

`editLink` builds `MakeEditLinkProps.ofReplaceRange` with no explicit
selection, so the component moves the cursor to `range.start.advance
newText` — UTF-16-aware.  Every insertion text starts with `"\n"`, so the
cursor must land at the END of the inserted example line with the previous
line's column forgotten (the blank-line/newline reset). -/

#guard (Lsp.Position.advance ⟨6, 9⟩
    ("\nexample : (0 : 𝓑) ⋖ 1 := by decide").toRawSubstring)
  == ⟨7, 35⟩   -- hand-counted UTF-16: 𝓑 = 2 units, ⋖ = 1
#guard
  let txt := "\nexample : ∀ x : Bowtie, (0 : Bowtie) ≤ x := by decide"
  Lsp.Position.advance ⟨5, 13⟩ txt.toRawSubstring
    == ⟨6, "example : ∀ x : Bowtie, (0 : Bowtie) ≤ x := by decide".utf16Length⟩

-- The full props the panel builds for a click: the edit carries exactly
-- (insertRange, newText) and the cursor selection collapses to the end of
-- the inserted line.
#guard
  let txt := insertionText (coverProp "𝓑" "0" "1")
  let props := ProofWidgets.MakeEditLinkProps.ofReplaceRange testDocMeta
    ⟨⟨6, 9⟩, ⟨6, 9⟩⟩ txt
  let edits : Array Lsp.TextEdit := props.edit.edits
  edits.size == 1
    && (match edits[0]? with
        | some e => e.range == (⟨⟨6, 9⟩, ⟨6, 9⟩⟩ : Lsp.Range) && e.newText == txt
        | none => false)
    && props.newSelection? == some ⟨⟨7, 35⟩, ⟨7, 35⟩⟩

/-! ## The in-process frontend harness -/

/-- Import the header of `src` once (edited variants of a user file share a
byte-identical header, so the resulting environment is reused across the
variants of one file). -/
unsafe def importEnvFor (src fileName : String) : IO Environment := do
  -- The outer compiler ran its own imports with `withImporting`, which
  -- resets the initializer-execution flag; nested `importModules
  -- (loadExts := true)` needs it back on (same as core `runFrontend`'s
  -- incremental path).
  enableInitializersExecution
  let inputCtx := Parser.mkInputContext src fileName
  let (header, _, messages) ← Parser.parseHeader inputCtx
  let (env, messages) ← Elab.processHeader header {} messages inputCtx
  if messages.hasErrors then
    let rendered ← messages.toList.mapM (·.data.toString)
    throw <| IO.Error.userError s!"E2E: header import failed for {fileName}: {rendered}"
  return env

/-- Everything a recompile of a (possibly edited) user file yields. -/
structure Compiled where
  /-- Rendered messages of severity `error`. -/
  errors : Array String
  /-- Total message count of ANY severity (`sorry` shows up as a warning, so
  the happy-path assertion `numMessages == 0` also excludes it). -/
  numMessages : Nat
  /-- Stored props (JSON) of every `HassePanel` widget in the info tree. -/
  panels : Array Json

/-- Collect the props JSON of every stored `HassePanel` widget. -/
partial def hassePanels : InfoTree → Array Json
  | .context _ t => hassePanels t
  | .node i cs =>
    let here := match i with
      | .ofUserWidgetInfo wi =>
        if wi.id == ``HasseView.HassePanel then #[(wi.props.run {}).1] else #[]
      | _ => #[]
    cs.foldl (fun acc t => acc ++ hassePanels t) here
  | .hole _ => #[]

/-- Compile the body of `src` against the (header-)imported `env`: parse the
header for the parser state, elaborate every command through
`Elab.IO.processCommands`, and collect messages + stored panel props. -/
def compileBody (env : Environment) (src fileName : String) : IO Compiled := do
  let inputCtx := Parser.mkInputContext src fileName
  let (_, parserState, messages) ← Parser.parseHeader inputCtx
  let s ← Elab.IO.processCommands inputCtx parserState
    (Command.mkState env messages {})
  let msgs := s.commandState.messages.toList
  let mut errors := #[]
  for m in msgs do
    if m.severity matches .error then
      errors := errors.push (← m.data.toString)
  let panels := s.commandState.infoState.trees.toArray.flatMap hassePanels
  return { errors, numMessages := msgs.length, panels }

/-- One E2E assertion: fail the build (the surrounding `#eval` errors) with a
descriptive message unless `cond` holds. -/
def check (cond : Bool) (what : String) : IO Unit := do
  unless cond do
    throw <| IO.Error.userError s!"E2E assertion failed: {what}"

/-- String-equality assertion that shows both sides on failure. -/
def checkEqStr (actual expected what : String) : IO Unit := do
  unless actual == expected do
    throw <| IO.Error.userError
      s!"E2E assertion failed: {what}\n--- actual ---\n{actual}\n--- expected ---\n{expected}"

/-- Decode the stored props — the exact payload the RPC panel receives. -/
def decodeProps (j : Json) : IO HassePanelProps :=
  match fromJson? j with
  | .ok p => pure p
  | .error e => throw <| IO.Error.userError s!"E2E: stored props failed to decode: {e}"

/-- The verified insertion texts of a `PanelLinks`, in panel order. -/
def verifiedTexts (l : PanelLinks) : Array String :=
  (l.covers ++ l.bot?.toArray ++ l.top?.toArray ++ l.witness?.toArray).filterMap
    (·.newText?)

/-- Independent, byte-anchored recomputation of what a click must produce:
`src` with `txt` spliced in at the end of the (unique) `#hasse` command line.
If `applyLspEdit` misplaces the edit by even one UTF-16 unit, the comparison
against this fails. -/
def expectInsertAfter (src cmdLine txt : String) : String :=
  src.replace (cmdLine ++ "\n") (cmdLine ++ txt ++ "\n")

/-- Compile the ORIGINAL user file, assert it is clean, and return its
stored panel props (asserting there is exactly one panel whose insertion
range is the pinned zero-width point). -/
def baseline (env : Environment) (src fileName : String) (insertPos : Lsp.Position) :
    IO HassePanelProps := do
  let c ← compileBody env src fileName
  check c.errors.isEmpty s!"{fileName}: baseline compiles without errors: {c.errors}"
  check (c.numMessages == 0) s!"{fileName}: baseline produces no messages at all"
  check (c.panels.size == 1) s!"{fileName}: exactly one stored HassePanel, got {c.panels.size}"
  let props ← decodeProps c.panels[0]!
  check (props.insertRange == ⟨insertPos, insertPos⟩)
    s!"{fileName}: insertion range is zero-width at the pinned command end \
      (got {props.insertRange.start}-{props.insertRange.«end»}, expected {insertPos})"
  return props

/-- Simulate ONE click: assert the candidate is a verified link, apply its
real `newText` at the real stored range, pin the edited file byte-exactly,
recompile, and assert the result is completely clean and still stores a
panel with an unchanged insertion range (which is what justifies clicking
several links in sequence).  Returns the recompiled file's props. -/
def click (env : Environment) (src fileName : String) (props : HassePanelProps)
    (fact : InsertableFact) (expectedEdited : String) : IO HassePanelProps := do
  let some txt := fact.newText?
    | throw <| IO.Error.userError s!"E2E: candidate `{fact.display}` is not insertable \
        ({fact.note?.getD "no note"})"
  check (txt.startsWith "\n") s!"{fileName}: `{fact.display}` newText starts with a newline"
  let edited := applyLspEdit src props.insertRange txt
  checkEqStr edited expectedEdited s!"{fileName}: edited file after clicking `{fact.display}`"
  let c ← compileBody env edited s!"{fileName}·edited"
  check c.errors.isEmpty
    s!"{fileName}: file compiles after clicking `{fact.display}`: {c.errors}"
  check (c.numMessages == 0)
    s!"{fileName}: no messages (no sorries, no warnings) after clicking `{fact.display}`"
  check (c.panels.size == 1) s!"{fileName}: panel still stored after clicking `{fact.display}`"
  let props' ← decodeProps c.panels[0]!
  check (props'.insertRange == props.insertRange)
    s!"{fileName}: insertion range unchanged after clicking `{fact.display}` \
      (a later click lands at the same command end)"
  return props'

/-- Click EVERY verified link (justified by the range-stability assertion of
`click`: each insertion leaves the command's end untouched), recompile once,
and assert the result is clean and contains every inserted example. -/
def clickAll (env : Environment) (src fileName : String) (props : HassePanelProps)
    (expectedCount : Nat) : IO Unit := do
  let texts := verifiedTexts props.links
  check (texts.size == expectedCount)
    s!"{fileName}: {expectedCount} verified insertions, got {texts.size}"
  let edited := texts.foldl (fun acc t => applyLspEdit acc props.insertRange t) src
  let c ← compileBody env edited s!"{fileName}·all"
  check c.errors.isEmpty s!"{fileName}: all {texts.size} insertions compile together: {c.errors}"
  check (c.numMessages == 0) s!"{fileName}: no messages after inserting all examples"
  for t in texts do
    check (containsSubstr edited (t.drop 1).toString)
      s!"{fileName}: click-all file contains inserted example {(t.drop 1).toString}"

/-- NEGATIVE: a corrupted `newText` (or a range shifted into the command)
must make the recompile FAIL — this proves the harness cannot pass
vacuously.  `expectErrSubstr` pins part of the expected error text. -/
def mustFail (env : Environment) (src fileName : String) (r : Lsp.Range)
    (txt : String) (expectErrSubstr : String) : IO Unit := do
  let edited := applyLspEdit src r txt
  let c ← compileBody env edited fileName
  check (!c.errors.isEmpty) s!"{fileName}: broken edit must fail to compile"
  check (c.errors.any (containsSubstr · expectErrSubstr))
    s!"{fileName}: expected an error mentioning `{expectErrSubstr}`, got {c.errors}"

/-! ## User file 1: the powerset cube

A realistic scratch file: the user imports the package plus the Mathlib
modules they would naturally have for `Finset (Fin 3)` exploration
(`Powerset` for the `Fintype`, `Sort` for the `{0, 1}`-style labels). -/

def cubeCmd : String := "#hasse (Finset (Fin 3))"

def cubeSrc : String :=
  "import HasseView\n\
   import Mathlib.Data.Fintype.Powerset\n\
   import Mathlib.Data.Finset.Sort\n\
   \n\
   -- scratch: the subset order on `Finset (Fin 3)`\n"
  ++ cubeCmd ++ "\n"

-- The command line occurs exactly once, so `expectInsertAfter` is anchored.
#guard countOccurrences cubeSrc (cubeCmd ++ "\n") == 1

unsafe def cubeSuite : IO Unit := do
  let env ← importEnvFor cubeSrc "CubeUser.lean"
  -- `#hasse (Finset (Fin 3))` ends at UTF-16 column 23 of (0-based) line 5.
  let props ← baseline env cubeSrc "CubeUser.lean" ⟨5, 23⟩
  -- The gate verdict in a USER file matches the suite's `#compile_insertions
  -- (Finset (Fin 3)) expecting 14` pin: 12 covers + ⊥ + ⊤, no witness.
  check (props.links.covers.size == 12) "cube: 12 cover candidates"
  check (props.links.witness?.isNone) "cube: no witness candidate (it is a lattice)"
  let some bot := props.links.bot? | throw <| .userError "cube: missing ⊥ candidate"
  let some top := props.links.top? | throw <| .userError "cube: missing ⊤ candidate"
  let cover0 := props.links.covers[0]!
  -- The stored payloads are byte-identical to the pure builders' outputs —
  -- the same code path `buildLinks` used to make them (drift check).
  check (cover0.newText? == some (insertionText (coverProp "(Finset (Fin 3))" "∅" "{0}")))
    "cube: covers[0] payload equals the pure builder output"
  check (bot.newText? == some (insertionText (botProp "(Finset (Fin 3))" "∅")))
    "cube: ⊥ payload equals the pure builder output"
  check (top.newText? == some (insertionText (topProp "(Finset (Fin 3))" "{0, 1, 2}")))
    "cube: ⊤ payload equals the pure builder output"
  -- THE CLICKS: cover edge, ⊥ fact, ⊤ fact.
  let mkExpected (txt : String) := expectInsertAfter cubeSrc cubeCmd txt
  let _ ← click env cubeSrc "CubeUser.lean" props cover0
    (mkExpected "\nexample : (∅ : (Finset (Fin 3))) ⋖ {0} := by decide")
  let _ ← click env cubeSrc "CubeUser.lean" props bot
    (mkExpected "\nexample : ∀ x : (Finset (Fin 3)), (∅ : (Finset (Fin 3))) ≤ x := by decide")
  let _ ← click env cubeSrc "CubeUser.lean" props top
    (mkExpected "\nexample : ∀ x : (Finset (Fin 3)), x ≤ ({0, 1, 2} : (Finset (Fin 3))) := by decide")
  -- Click EVERYTHING (14 verified links).
  clickAll env cubeSrc "CubeUser.lean" props 14
  -- NEGATIVES: corrupting the payload or shifting the range breaks the file.
  let txt0 := cover0.newText?.get!
  let corrupt := txt0.replace "decide" "dceide"
  check (corrupt != txt0) "cube: corruption actually changed the text"
  mustFail env cubeSrc "CubeCorrupt.lean" props.insertRange corrupt "unknown tactic"
  -- One UTF-16 unit left of the command end: the example splices into the
  -- command's closing parens.
  mustFail env cubeSrc "CubeShifted.lean" ⟨⟨5, 22⟩, ⟨5, 22⟩⟩ txt0 ")"

#eval cubeSuite

/-! ## User file 2: the bowtie behind a unicode wall

Unicode-heavy lines BEFORE the command (a doc comment full of multibyte
math and an emoji) and — crucially — a surrogate-pair character **on the
command line itself, before the insertion point**: the user names the type
`𝓑` (U+1D4D1: 2 UTF-16 units, 1 codepoint, 4 UTF-8 bytes).  The pinned
insertion column 9 (`"#hasse " = 7` + `𝓑 = 2`) is correct ONLY in UTF-16:
a codepoint interpretation gives 8, a byte interpretation 11 — either bug
shifts the edit visibly and fails the byte-exact pins below. -/

def uniCmd : String := "#hasse 𝓑"

def uniSrc : String :=
  "import HasseView\n\
   \n\
   /-! Scratch notes: ℝ≥0, α ⊓ β, ∀ ε > 0, ∃ δ 😀 — unicode ballast. -/\n\
   \n\
   abbrev 𝓑 := HasseView.Demo.Bowtie\n\
   \n"
  ++ uniCmd ++ "\n"

#guard countOccurrences uniSrc (uniCmd ++ "\n") == 1

/-- The cover click on the unicode file, pinned as a full literal (not via
`expectInsertAfter`) so at least one expected file is written out in full. -/
def uniCoverEdited : String :=
  "import HasseView\n\
   \n\
   /-! Scratch notes: ℝ≥0, α ⊓ β, ∀ ε > 0, ∃ δ 😀 — unicode ballast. -/\n\
   \n\
   abbrev 𝓑 := HasseView.Demo.Bowtie\n\
   \n\
   #hasse 𝓑\n\
   example : (0 : 𝓑) ⋖ 1 := by decide\n"

unsafe def uniSuite : IO Unit := do
  let env ← importEnvFor uniSrc "UniUser.lean"
  let props ← baseline env uniSrc "UniUser.lean" ⟨6, 9⟩
  -- Bowtie behind the abbrev: 6 covers + ⊥ + no-join witness, no ⊤.
  check (props.links.covers.size == 6) "uni: 6 cover candidates"
  check (props.links.top?.isNone) "uni: no ⊤ candidate (the bowtie has no top)"
  let some bot := props.links.bot? | throw <| .userError "uni: missing ⊥ candidate"
  let some wit := props.links.witness? | throw <| .userError "uni: missing witness candidate"
  let cover0 := props.links.covers[0]!
  -- Payloads use the user's own `𝓑` spelling, via the pure builders.
  check (cover0.newText? == some (insertionText (coverProp "𝓑" "0" "1")))
    "uni: covers[0] payload equals the pure builder output (with the user's 𝓑)"
  check (wit.newText? == some (insertionText (noJoinProp "𝓑" "1" "2")))
    "uni: witness payload equals the pure builder output (no-join, quantifier form)"
  -- THE CLICKS: cover (full-literal pin), ⊥, and the non-lattice witness.
  let _ ← click env uniSrc "UniUser.lean" props cover0 uniCoverEdited
  let _ ← click env uniSrc "UniUser.lean" props bot
    (expectInsertAfter uniSrc uniCmd
      "\nexample : ∀ x : 𝓑, (0 : 𝓑) ≤ x := by decide")
  let _ ← click env uniSrc "UniUser.lean" props wit
    (expectInsertAfter uniSrc uniCmd
      ("\nexample : ¬ ∃ m : 𝓑, ((1 : 𝓑) ≤ m ∧ (2 : 𝓑) ≤ m) ∧ \
        ∀ u : 𝓑, ((1 : 𝓑) ≤ u ∧ (2 : 𝓑) ≤ u) → m ≤ u := by decide"))
  -- Click everything (6 covers + ⊥ + witness = 8).
  clickAll env uniSrc "UniUser.lean" props 8
  -- NEGATIVE: two UTF-16 units left = before `𝓑`, splicing the example
  -- between `#hasse ` and its type argument.
  mustFail env uniSrc "UniShifted.lean" ⟨⟨6, 7⟩, ⟨6, 7⟩⟩ cover0.newText?.get! "example"
  -- User file 2b (same header, same env): a trailing comment on the command
  -- line.  The command's range ends BEFORE the comment, so the click drags
  -- the comment onto the inserted example's line — still compiles (the
  -- comment stays a trailing comment), pinned here as a documented wart.
  let tSrc := "import HasseView\n\nopen HasseView.Demo\n\n#hasse Bowtie -- next: the ⋖ facts\n"
  let tProps ← baseline env tSrc "TrailUser.lean" ⟨4, 13⟩
  let tCover := tProps.links.covers[0]!
  let _ ← click env tSrc "TrailUser.lean" tProps tCover
    ("import HasseView\n\nopen HasseView.Demo\n\n#hasse Bowtie\n\
      example : (0 : Bowtie) ⋖ 1 := by decide -- next: the ⋖ facts\n")
  return ()

#eval uniSuite

end HasseViewTests.E2E
