import Lean.Elab.Frontend
import DistLensTests.Helpers
import DistLens

/-! # ClickE2E: end-to-end click-simulation tests

The suggestion links in the `#dist`/`#chain` panels claim: *clicking inserts
an `example` that compiles in **your** file*.  This module tests exactly
that claim, end to end, with no shortcuts:

1. realistic **user files** (source strings importing only `DistLens`, the
   way a real user would) are compiled by Lean's own frontend, *in this
   process* (`Lean.Elab.processHeader` + `Lean.Elab.IO.processCommands` —
   the same pipeline `lake env lean` runs);
2. the **real click payloads** are obtained through the very code path the
   panel uses: the command elaborator logs its stored `DistPanelProps` /
   `ChainPanelProps` behind the `distLens.debug.logPanelProps` option, and
   the edit is built by `DistLens.suggestionEditProps` — the *same function*
   `DistPanel.rpc` / `ChainPanel.rpc` call at render time;
3. the payload is applied with `applyLspEdit`, which delegates to the
   server's own `Lean.Server.replaceLspRange` (LSP ranges are **UTF-16 code
   unit** columns — byte or codepoint interpretations are bugs, and the
   fixtures below discriminate all three);
4. the edited file is recompiled and must be error-, warning- and
   sorry-free;
5. **negative controls**: a corrupted `newText` and a shifted range must
   make the recompile *fail* (pinned), proving the harness is not vacuous.

The user-file fixtures deliberately put multibyte characters (`𝕜`, ℝ, ⋖,
🎲) on and before the command line, at columns where the UTF-8 byte offset,
the codepoint index and the UTF-16 offset all differ.
-/

namespace DistLensTests.ClickE2E

open Lean Elab Server DistLens

/-! ## Substring helper -/

/-- Does `s` contain `pat` as a substring? -/
def hasSubstr (s pat : String) : Bool := (s.splitOn pat).length > 1

#guard hasSubstr "abcdef" "cde"
#guard !hasSubstr "abcdef" "cdf"
#guard hasSubstr "π ⋖ ℝ" "⋖"

/-! ## applyLspEdit: LSP edits via the server's own range arithmetic -/

/-- `Lsp.TextEditBatch` is a plain `def` for `Array Lsp.TextEdit`; convert
so array API (indexing, `qsort`) is available. -/
def editsOf (edit : Lsp.TextDocumentEdit) : Array Lsp.TextEdit := edit.edits

private instance : Inhabited Lsp.TextEdit :=
  ⟨{ range := ⟨⟨0, 0⟩, ⟨0, 0⟩⟩, newText := "" }⟩

/-- Apply a `TextDocumentEdit` to source text using the server's own
`Lean.Server.replaceLspRange` (UTF-16 code-unit columns).  Per the LSP spec
all ranges address the *original* document; the (non-overlapping) edits are
applied back to front so earlier positions stay valid. -/
def applyLspEdit (src : String) (edit : Lsp.TextDocumentEdit) : String := Id.run do
  let after (a b : Lsp.TextEdit) : Bool :=
    a.range.start.line > b.range.start.line ||
      (a.range.start.line == b.range.start.line &&
        a.range.start.character > b.range.start.character)
  let mut text := src.toFileMap
  for e in (editsOf edit).qsort after do
    text := Lean.Server.replaceLspRange text e.range e.newText
  return text.source

/-- A single-`TextEdit` document edit (test constructor). -/
def edit1 (range : Lsp.Range) (newText : String) : Lsp.TextDocumentEdit :=
  { textDocument := { uri := "file:///E2EUser.lean", version? := some 1 }
    edits := #[{ range, newText }] }

/-- Zero-width range at a position. -/
def at' (line character : Nat) : Lsp.Range := ⟨⟨line, character⟩, ⟨line, character⟩⟩

-- ASCII insertion and replacement.
#guard applyLspEdit "ab\ncd\n" (edit1 (at' 1 1) "X") = "ab\ncXd\n"
#guard applyLspEdit "ab\ncd\n" (edit1 ⟨⟨0, 1⟩, ⟨1, 1⟩⟩ "-") = "a-d\n"

-- Multibyte BMP characters: ℝ and ⋖ are 3 UTF-8 bytes but 1 UTF-16 unit.
-- Column 2 is after `⋖`; a byte reading of column 2 would land inside `ℝ`.
#guard applyLspEdit "ℝ⋖xy\n" (edit1 (at' 0 2) "|") = "ℝ⋖|xy\n"

-- Astral character: 🎲 is 2 UTF-16 units and 1 codepoint.  Column 4 is
-- after the second 🎲; a codepoint reading of 4 would land after `b`.
#guard applyLspEdit "🎲🎲ab\n" (edit1 (at' 0 4) "|") = "🎲🎲|ab\n"

-- 𝕜 (U+1D55C) is 2 UTF-16 units: column 3 on `𝕜x = y` is after `x`.
#guard applyLspEdit "𝕜x = y\n" (edit1 (at' 0 3) "Z") = "𝕜xZ = y\n"

-- Multiple edits address the original document and must be applied back to
-- front even when given front to back.
#guard applyLspEdit "abc\n"
  { textDocument := { uri := "file:///E2EUser.lean", version? := some 1 }
    edits := #[{ range := at' 0 1, newText := "X" },
               { range := at' 0 2, newText := "Y" }] } = "aXbYc\n"

-- Insertion at the very end of a line, with following lines preserved —
-- the exact shape of a suggestion click.
#guard applyLspEdit "#dist p\n\n-- next\n" (edit1 (at' 0 7) "\nexample") =
  "#dist p\nexample\n\n-- next\n"

/-! ## Deliberately wrong appliers

These implement the two classic encoding bugs.  The guards prove that on
the multibyte fixtures they produce *different* output than `applyLspEdit`,
i.e. the pinned fixtures above genuinely discriminate UTF-16 from bytes and
codepoints (an applier with either bug could not pass this file). -/

/-- WRONG on purpose: interprets `character` as a UTF-8 *byte* offset into
the line.  Single-edit only; test-only. -/
def applyEditBytewise (src : String) (edit : Lsp.TextDocumentEdit) : String := Id.run do
  let e := (editsOf edit)[0]!
  let bytes := src.toUTF8
  let byteOf (p : Lsp.Position) : Nat := Id.run do
    let mut line := 0
    let mut i := 0
    while line < p.line && i < bytes.size do
      if bytes[i]! == 10 then line := line + 1
      i := i + 1
    return i + p.character
  let b := byteOf e.range.start
  let en := byteOf e.range.end
  -- `fromUTF8?` + sentinel, NOT `fromUTF8!`: when the byte-interpreted
  -- offset splits a multibyte character the result is invalid UTF-8, and
  -- the bang variant would panic (stderr backtrace in the build log) while
  -- still returning a default.  The sentinel keeps the wrongness visible
  -- and the build log clean.
  return (String.fromUTF8?
      (bytes.extract 0 b ++ e.newText.toUTF8 ++ bytes.extract en bytes.size)).getD
    "<invalid UTF-8>"

/-- WRONG on purpose: interprets `character` as a *codepoint* index into
the line.  Single-edit only; test-only. -/
def applyEditCodepointwise (src : String) (edit : Lsp.TextDocumentEdit) : String := Id.run do
  let e := (editsOf edit)[0]!
  let fm := src.toFileMap
  let posOf (p : Lsp.Position) : String.Pos.Raw := Id.run do
    -- `FileMap.lineStart` takes a 1-based line; LSP positions are 0-based.
    let mut pos := fm.lineStart (p.line + 1)
    for _ in [0:p.character] do
      if pos < src.rawEndPos && pos.get src != '\n' then
        pos := pos.next src
    return pos
  let b := posOf e.range.start
  let en := posOf e.range.end
  return String.Pos.Raw.extract src 0 b ++ e.newText ++
    String.Pos.Raw.extract src en src.rawEndPos

-- Byte bug: column 3 of `ℝ⋖xy` lands after `ℝ` (byte 3) instead of after
-- `x` — visibly different output.
#guard applyEditBytewise "ℝ⋖xy\n" (edit1 (at' 0 3) "|") = "ℝ|⋖xy\n"
#guard applyLspEdit "ℝ⋖xy\n" (edit1 (at' 0 3) "|") = "ℝ⋖x|y\n"

-- Codepoint bug: column 4 of `🎲🎲ab` lands after `b` instead of after the
-- second 🎲.
#guard applyEditCodepointwise "🎲🎲ab\n" (edit1 (at' 0 4) "|") = "🎲🎲ab|\n"
#guard applyEditCodepointwise "🎲🎲ab\n" (edit1 (at' 0 4) "|") ≠
  applyLspEdit "🎲🎲ab\n" (edit1 (at' 0 4) "|")

-- Byte bug, mid-character split: byte column 1 of `ℝab` lands *inside* the
-- 3-byte `ℝ`; the sentinel (via `fromUTF8?`) keeps the wrongness visible
-- without `fromUTF8!`'s panic backtrace in the build log.
#guard applyEditBytewise "ℝab\n" (edit1 (at' 0 1) "|") = "<invalid UTF-8>"

-- Multi-line fixtures: the wrong appliers must still address the RIGHT
-- line (LSP lines are 0-based, `FileMap.lineStart` is 1-based — an
-- off-by-one would silently probe the wrong line).  On an ASCII line both
-- agree with `applyLspEdit`; on the astral line 1 the codepoint applier
-- exhibits exactly the codepoint bug, one line down.
#guard applyEditCodepointwise "ab\ncd\n" (edit1 (at' 1 1) "X") = "ab\ncXd\n"
#guard applyEditBytewise "ab\ncd\n" (edit1 (at' 1 1) "X") = "ab\ncXd\n"
#guard applyEditCodepointwise "ℝ⋖\n🎲🎲ab\n" (edit1 (at' 1 4) "|") = "ℝ⋖\n🎲🎲ab|\n"
#guard applyLspEdit "ℝ⋖\n🎲🎲ab\n" (edit1 (at' 1 4) "|") = "ℝ⋖\n🎲🎲|ab\n"

/-! ## The in-process frontend -/

private unsafe def enableInitializersExecutionUnsafe : IO Unit :=
  Lean.enableInitializersExecution

/-- Allow `importModules (loadExts := true)` in this process — required
before driving the frontend in-process; the language-server file worker
does exactly the same at startup.  (Safe interface to the `unsafe` core
flag setter; idempotent.) -/
@[implemented_by enableInitializersExecutionUnsafe]
private def enableInitializersExecutionSafe : IO Unit := pure ()

/-- Rendered messages of one in-process compile, split by severity. -/
structure CompileOutcome where
  errors : Array String := #[]
  warnings : Array String := #[]
  infos : Array String := #[]
  deriving Inhabited

/-- Fully clean: no errors, no warnings (a `sorry` would be a warning). -/
def CompileOutcome.clean (o : CompileOutcome) : Bool :=
  o.errors.isEmpty && o.warnings.isEmpty

/-- Any message mentioning `sorry` (belt and braces on top of `clean`). -/
def CompileOutcome.sorried (o : CompileOutcome) : Bool :=
  (o.errors ++ o.warnings).any (hasSubstr · "sorry")

/-- Compile a Lean source string with Lean's own frontend — header imports
resolved from the ambient search path (so `import DistLens` works because
this test module was built after the library), commands elaborated exactly
as `lake env lean` would.  Returns the message log, split by severity. -/
def compileString (input : String) (opts : Options := {})
    (fileName : String := "E2EUser.lean") : IO CompileOutcome := do
  enableInitializersExecutionSafe
  let opts := opts.setBool `Elab.async false
  let inputCtx := Parser.mkInputContext input fileName
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  let (env, messages) ← processHeader header opts messages inputCtx
    (mainModule := `E2EUser)
  let s ← Lean.Elab.IO.processCommands inputCtx parserState
    (Command.mkState env messages opts)
  let mut out : CompileOutcome := {}
  for m in s.commandState.messages.toList do
    let str ← m.data.toString
    match m.severity with
    | .error => out := { out with errors := out.errors.push str }
    | .warning => out := { out with warnings := out.warnings.push str }
    | .information => out := { out with infos := out.infos.push str }
  return out

/-! ## Assertion helpers (throwing, so `lake build` fails loudly) -/

/-- Assert `b`, failing with `label`. -/
def check (label : String) (b : Bool) : IO Unit := do
  unless b do throw <| IO.userError s!"ClickE2E FAILED: {label}"

/-- Assert string equality, printing both sides on mismatch. -/
def checkEq (label : String) (expected actual : String) : IO Unit := do
  unless expected == actual do
    throw <| IO.userError
      s!"ClickE2E FAILED: {label}\nexpected: {expected.quote}\nactual:   {actual.quote}"

/-- Assert a fully clean compile. -/
def checkClean (label : String) (o : CompileOutcome) : IO Unit := do
  check s!"{label}: expected clean compile, got errors {o.errors} \
    warnings {o.warnings}" (o.clean && !o.sorried)

/-- Assert the compile FAILED and some error mentions `pat`. -/
def checkFails (label : String) (o : CompileOutcome) (pat : String) : IO Unit := do
  check s!"{label}: expected a failing compile" !o.errors.isEmpty
  check s!"{label}: expected an error mentioning {pat.quote}, got {o.errors}"
    (o.errors.any (hasSubstr · pat))

/-! ## Payload capture: the real props, through the real code path -/

/-- The debug options that make the panel commands log their stored props. -/
def logOpts : Options := ({} : Options).setBool DistLens.logPropsOptName true

/-- Extract the `distLens.panelProps: <json>` payloads from a compile. -/
def propJsons (o : CompileOutcome) : IO (Array Json) := do
  let mut out := #[]
  for s in o.infos do
    if DistLens.panelPropsMarker.isPrefixOf s then
      match Json.parse (s.drop DistLens.panelPropsMarker.length).toString with
      | .ok j => out := out.push j
      | .error e => throw <| IO.userError s!"ClickE2E: bad props json: {e}"
  return out

/-- Decode the single stored props value of a one-command user file. -/
def theProps (α : Type) [FromJson α] (label : String) (o : CompileOutcome) :
    IO α := do
  let js ← propJsons o
  check s!"{label}: expected exactly one props payload, got {js.size}"
    (js.size == 1)
  match fromJson? js[0]! with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"ClickE2E: {label}: props decode: {e}"

/-- The `DocumentMeta` a test click runs against (version 42 — the edit
must come back stamped with it). -/
def testMeta (src : String) : DocumentMeta :=
  { uri := "file:///E2EUser.lean", mod := `E2EUser, version := 42
    text := src.toFileMap, dependencyBuildMode := .always }

/-- Simulate the click on suggestion `text`: build the edit through
`DistLens.suggestionEditProps` — the function the RPC render layer itself
uses — and return it together with the link's post-edit cursor. -/
def clickPayload (src : String) (insertRange : Lsp.Range) (text : String) :
    ProofWidgets.MakeEditLinkProps :=
  DistLens.suggestionEditProps (testMeta src) insertRange text

/-- Full click simulation: payload → `applyLspEdit` → recompiled outcome. -/
def clickAndRecompile (src : String) (insertRange : Lsp.Range) (text : String) :
    IO (String × CompileOutcome) := do
  let edited := applyLspEdit src (clickPayload src insertRange text).edit
  return (edited, ← compileString edited)

/-! ## React contract over the RPC render path

The interactive rows the RPC methods return are real `MakeEditLink`
components; the assembled panels must honor the React contract exactly like
their static (`.text`) counterparts checked in `ContractTests`. -/

#guard reactContractViolations (renderDistPanel DistLensTests.die6
  #["example : die 0 = 1/6 := by pmf_num"]
  (editLink (testMeta "#dist die\n") (at' 0 9))) = []

#guard reactContractViolations (renderChainPanel DistLensTests.weatherM ⟨#[]⟩
  #["example : ((PMF.ofFintype ![2/3, 1/3] (by simp [Fin.sum_univ_succ]; \
    ennreal_num)).bind weather) 0 = 2/3 := by unfold weather; pmf_num"]
  (editLink (testMeta "#chain weather\n") (at' 0 14))) = []

/-! ## Harness canary: the frontend detects success, failure and sorries -/

#eval show IO Unit from do
  let ok ← compileString "def probe1 : Nat := 1\ntheorem probe2 : probe1 = 1 := rfl\n"
  checkClean "canary: clean tiny file" ok
  check "canary: no props logged without the option" ((← propJsons ok).size == 0)
  let bad ← compileString "def probe1 : Nat := \"x\"\n"
  checkFails "canary: type error detected" bad "Nat"
  let sorried ← compileString "example : True := by sorry\n"
  check "canary: sorry detected" (!sorried.clean && sorried.sorried)

/-! ## User file 1: def-wrapped PMF, astral identifier, unicode ballast

`𝕜` is U+1D55C: on the `#dist 𝕜die` line the insertion column is 11 in
UTF-16 units, 10 in codepoints and 13 in UTF-8 bytes — the pinned insert
range and pinned edited file catch any wrong convention. -/

def uFile1 : String := String.intercalate "\n" [
  "import DistLens",
  "",
  "-- unicode ballast before the command: ∀ε>0, ℝ ⋖ 🎲 — bytes ≠ units",
  "noncomputable def 𝕜die : PMF (Fin 4) := PMF.uniformOfFintype (Fin 4)",
  "",
  "#dist 𝕜die",
  ""]

/-- The suggestion texts the `#dist 𝕜die` panel must offer. -/
def uFile1Suggestions : Array String :=
  (Array.range 4).map fun k =>
    s!"example : 𝕜die {k} = 1/4 := by unfold 𝕜die; pmf_num"

#eval show IO Unit from do
  let o ← compileString uFile1 (opts := logOpts)
  checkClean "uFile1 compiles" o
  let props ← theProps DistPanelProps "uFile1" o
  -- The insert range: zero-width, end of `#dist 𝕜die` = UTF-16 column 11.
  check "uFile1: insertRange is ⟨5,11⟩–⟨5,11⟩"
    (props.insertRange == at' 5 11)
  -- The real suggestions, byte for byte.
  checkEq "uFile1: suggestions" (toString uFile1Suggestions)
    (toString props.suggestions)
  -- The click payload is version-stamped (stale clicks must be rejected by
  -- the editor, not applied at drifted offsets).
  let payload := clickPayload uFile1 props.insertRange props.suggestions[0]!
  check "uFile1: edit is version-stamped"
    (payload.edit.textDocument.version? == some 42)
  check "uFile1: exactly one text edit"
    ((editsOf payload.edit).size == 1)
  -- Cursor sanity: the link moves the cursor to the end of the inserted
  -- example — next line, column = UTF-16 length of the suggestion.
  let sugLen := props.suggestions[0]!.foldl (init := 0)
    fun n c => n + c.utf16Size.toNat
  check "uFile1: cursor lands at end of inserted line"
    (payload.newSelection? == some (at' 6 sugLen))
  -- THE CLICK, suggestion 0: pinned resulting file, then recompile.
  let (edited, o₀) ← clickAndRecompile uFile1 props.insertRange props.suggestions[0]!
  checkEq "uFile1: edited file (pinned)"
    (String.intercalate "\n" [
      "import DistLens",
      "",
      "-- unicode ballast before the command: ∀ε>0, ℝ ⋖ 🎲 — bytes ≠ units",
      "noncomputable def 𝕜die : PMF (Fin 4) := PMF.uniformOfFintype (Fin 4)",
      "",
      "#dist 𝕜die",
      "example : 𝕜die 0 = 1/4 := by unfold 𝕜die; pmf_num",
      ""])
    edited
  checkClean "uFile1 + suggestion 0 recompiles" o₀
  -- THE CLICK, last suggestion.
  let (_, o₃) ← clickAndRecompile uFile1 props.insertRange props.suggestions[3]!
  checkClean "uFile1 + suggestion 3 recompiles" o₃
  -- NEGATIVE 1: corrupt the newText (false claim 1/4 → 1/3).  The recompile
  -- MUST fail, with pmf_num's pinned refusal — this proves the inserted
  -- example really elaborates (the harness is not vacuous).
  let corrupt := (clickPayload uFile1 props.insertRange
    (props.suggestions[0]!.replace "1/4" "1/3")).edit
  let oBad ← compileString (applyLspEdit uFile1 corrupt)
  checkFails "uFile1: corrupted newText must fail" oBad
    "ennreal_num: cannot close this ℝ≥0∞ goal"
  -- NEGATIVE 2: shift the range 2 UTF-16 units left (into `𝕜die`): the
  -- insertion splits the identifier and the recompile MUST fail.
  let shifted := (clickPayload uFile1 (at' 5 9) props.suggestions[0]!).edit
  let oShift ← compileString (applyLspEdit uFile1 shifted)
  checkFails "uFile1: shifted range must fail" oShift "𝕜d"
  -- NEGATIVE 3: a byte-offset applier visibly corrupts this file (column
  -- 11 in bytes splits `𝕜die` after `d`) and must not compile.
  let good := (clickPayload uFile1 props.insertRange props.suggestions[0]!).edit
  check "uFile1: bytewise applier corrupts the file"
    (applyEditBytewise uFile1 good != edited)
  let oByte ← compileString (applyEditBytewise uFile1 good)
  checkFails "uFile1: bytewise-applied edit must fail" oByte "𝕜d"

/-! ## User file 2: inline constructor term (no `unfold` prefix)

Also pins the `termText` parenthesization rule: the user's already
parenthesized term must NOT be wrapped in a second pair of parentheses. -/

def uFile2 : String := String.intercalate "\n" [
  "import DistLens",
  "",
  "#dist (PMF.uniformOfFintype (Fin 3))",
  ""]

#eval show IO Unit from do
  let o ← compileString uFile2 (opts := logOpts)
  checkClean "uFile2 compiles" o
  let props ← theProps DistPanelProps "uFile2" o
  check "uFile2: insertRange is ⟨2,36⟩" (props.insertRange == at' 2 36)
  checkEq "uFile2: suggestions (single parens)"
    (toString <| (Array.range 3).map fun k =>
      s!"example : (PMF.uniformOfFintype (Fin 3)) {k} = 1/3 := by pmf_num")
    (toString props.suggestions)
  let (_, o₁) ← clickAndRecompile uFile2 props.insertRange props.suggestions[1]!
  checkClean "uFile2 + suggestion 1 recompiles" o₁

/-! ## User file 3: `#chain` stationary-equation suggestions -/

def uFile3 : String := String.intercalate "\n" [
  "import DistLens",
  "",
  "noncomputable def weather : Fin 2 → PMF (Fin 2) :=",
  "  ![PMF.ofFintype ![3/4, 1/4] (by simp [Fin.sum_univ_succ]; ennreal_num),",
  "    PMF.ofFintype ![1/2, 1/2] (by simp [Fin.sum_univ_succ]; ennreal_num)]",
  "",
  "#chain weather",
  ""]

#eval show IO Unit from do
  let o ← compileString uFile3 (opts := logOpts)
  checkClean "uFile3 compiles" o
  let props ← theProps ChainPanelProps "uFile3" o
  check "uFile3: insertRange is ⟨6,14⟩" (props.insertRange == at' 6 14)
  checkEq "uFile3: stationary suggestions"
    (toString #[
      "example : ((PMF.ofFintype ![2/3, 1/3] (by simp [Fin.sum_univ_succ]; \
       ennreal_num)).bind weather) 0 = 2/3 := by unfold weather; pmf_num",
      "example : ((PMF.ofFintype ![2/3, 1/3] (by simp [Fin.sum_univ_succ]; \
       ennreal_num)).bind weather) 1 = 1/3 := by unfold weather; pmf_num"])
    (toString props.suggestions)
  -- The chain payload is uri- and version-stamped like the dist payload.
  let payload := clickPayload uFile3 props.insertRange props.suggestions[0]!
  check "uFile3: edit targets the document's uri"
    (payload.edit.textDocument.uri == "file:///E2EUser.lean")
  check "uFile3: edit is version-stamped"
    (payload.edit.textDocument.version? == some 42)
  for i in [0:props.suggestions.size] do
    let (_, oᵢ) ← clickAndRecompile uFile3 props.insertRange props.suggestions[i]!
    checkClean s!"uFile3 + stationary equation {i} recompiles" oᵢ
  -- NEGATIVE: corrupt the claimed stationary weight (RHS only — the π
  -- entries inside the `PMF.ofFintype` literal stay intact, so the side
  -- goal still closes and the failure is exactly the false equation).  The
  -- recompile MUST fail with pmf_num's pinned refusal, proving the
  -- stationary-equation kind is verified end to end, not vacuously.
  let corrupt := (clickPayload uFile3 props.insertRange
    (props.suggestions[0]!.replace "0 = 2/3 :=" "0 = 1/2 :=")).edit
  let oBad ← compileString (applyLspEdit uFile3 corrupt)
  checkFails "uFile3: corrupted stationary equation must fail" oBad
    "ennreal_num: cannot close this ℝ≥0∞ goal"

/-! ## User file 4: `Bool` carrier and the bernoulli residue weight

`P(false) = 1 − 2/3` exercises `pmf_num`'s ℝ≥0∞ truncated-subtraction
branch in a *user* file (the def needs the deprecation `set_option` at this
Mathlib pin, exactly as a real user would write it). -/

def uFile4 : String := String.intercalate "\n" [
  "import DistLens",
  "",
  "set_option linter.deprecated false",
  "",
  "noncomputable def coin : PMF Bool := PMF.bernoulli (2/3) (by norm_num [div_le_one])",
  "",
  "#dist coin",
  ""]

#eval show IO Unit from do
  let o ← compileString uFile4 (opts := logOpts)
  checkClean "uFile4 compiles" o
  let props ← theProps DistPanelProps "uFile4" o
  check "uFile4: insertRange is ⟨6,10⟩" (props.insertRange == at' 6 10)
  checkEq "uFile4: bool suggestions"
    (toString #["example : coin false = 1/3 := by unfold coin; pmf_num",
                "example : coin true = 2/3 := by unfold coin; pmf_num"])
    (toString props.suggestions)
  let (_, o₀) ← clickAndRecompile uFile4 props.insertRange props.suggestions[0]!
  checkClean "uFile4 + residue-weight suggestion recompiles" o₀

/-! ## User file 5: trailing comment on the command line (documented wart)

The insertion point is the end of the command *syntax*, which precedes any
trailing comment — so the comment ends up appended to the inserted example
line.  This still compiles (it is a line comment), but is a known cosmetic
wart, pinned here so any behavior change is noticed. -/

def uFile5 : String := String.intercalate "\n" [
  "import DistLens",
  "",
  "#dist (PMF.uniformOfFintype (Fin 2)) -- tail comment 🎲",
  ""]

#eval show IO Unit from do
  let o ← compileString uFile5 (opts := logOpts)
  checkClean "uFile5 compiles" o
  let props ← theProps DistPanelProps "uFile5" o
  check "uFile5: insertRange precedes the trailing comment"
    (props.insertRange == at' 2 36)
  let (edited, o₀) ← clickAndRecompile uFile5 props.insertRange props.suggestions[0]!
  checkEq "uFile5: edited file (pinned wart: comment trails the example)"
    (String.intercalate "\n" [
      "import DistLens",
      "",
      "#dist (PMF.uniformOfFintype (Fin 2))",
      "example : (PMF.uniformOfFintype (Fin 2)) 0 = 1/2 := by pmf_num -- tail comment 🎲",
      ""])
    edited
  checkClean "uFile5 + suggestion recompiles despite trailing comment" o₀

/-! ## User file 6: code after the command line

A real user's `#dist` rarely ends the file.  The insertion is a zero-width
edit at the end of the command, so everything below — blank line and later
theorem — must be preserved verbatim, end to end (the analogous claim was
only unit-tested on `applyLspEdit` above). -/

def uFile6 : String := String.intercalate "\n" [
  "import DistLens",
  "",
  "noncomputable def die : PMF (Fin 6) := PMF.uniformOfFintype (Fin 6)",
  "",
  "#dist die",
  "",
  "theorem afterTheCommand : 2 + 2 = 4 := rfl",
  ""]

#eval show IO Unit from do
  let o ← compileString uFile6 (opts := logOpts)
  checkClean "uFile6 compiles" o
  let props ← theProps DistPanelProps "uFile6" o
  check "uFile6: insertRange is ⟨4,9⟩" (props.insertRange == at' 4 9)
  check "uFile6: six suggestions" (props.suggestions.size == 6)
  let (edited, o₀) ← clickAndRecompile uFile6 props.insertRange props.suggestions[0]!
  checkEq "uFile6: edited file (pinned — following code preserved)"
    (String.intercalate "\n" [
      "import DistLens",
      "",
      "noncomputable def die : PMF (Fin 6) := PMF.uniformOfFintype (Fin 6)",
      "",
      "#dist die",
      "example : die 0 = 1/6 := by unfold die; pmf_num",
      "",
      "theorem afterTheCommand : 2 + 2 = 4 := rfl",
      ""])
    edited
  checkClean "uFile6 + suggestion recompiles with code below" o₀

/-! ## User file 7: opaque `Fintype` carrier — display-only, ZERO goal rows

`uniformOfFintype Ordering` draws (cardinality 3, `Repr` labels), but its
outcome labels are `Repr` display strings, not verified source terms, and
`pmf_num` cannot reduce `Fintype.card` of an arbitrary carrier — a clicked
example would fail (audit finding).  So the panel must offer **no**
suggestions (same standard as the subtype-mk refusal).  Both halves are
pinned: the suppression itself, and the *reason* — the would-be example
still fails to compile with `pmf_num`'s pinned refusal.  If the tactic ever
learns to close these goals, the second pin breaks and the suppression can
be revisited. -/

def uFile7 : String := String.intercalate "\n" [
  "import DistLens",
  "",
  "#dist (PMF.uniformOfFintype Ordering)",
  ""]

#eval show IO Unit from do
  let o ← compileString uFile7 (opts := logOpts)
  checkClean "uFile7 compiles" o
  let props ← theProps DistPanelProps "uFile7" o
  check "uFile7: insertRange is ⟨2,37⟩" (props.insertRange == at' 2 37)
  -- The display keeps working: three outcomes, `Repr` labels, exact ⅓s.
  checkEq "uFile7: opaque labels (display-only path intact)"
    (toString #["Ordering.lt", "Ordering.eq", "Ordering.gt"])
    (toString props.model.labels)
  check "uFile7: uniform weights" (props.model.weights == #[1/3, 1/3, 1/3])
  check "uFile7: no values for an opaque carrier" props.model.values?.isNone
  -- THE FIX, pinned: zero suggestion rows for the opaque carrier.
  check "uFile7: ZERO suggestions for the opaque carrier"
    (props.suggestions.isEmpty)
  -- WHY, pinned: the example a row would have inserted does NOT compile —
  -- `pmf_num` leaves the `Fintype.card Ordering` residue open.
  let (_, oBad) ← clickAndRecompile uFile7 props.insertRange
    "example : (PMF.uniformOfFintype Ordering) Ordering.lt = 1/3 := by pmf_num"
  checkFails "uFile7: the would-be opaque suggestion must still fail" oBad
    "ennreal_num: cannot close this ℝ≥0∞ goal"

end DistLensTests.ClickE2E
