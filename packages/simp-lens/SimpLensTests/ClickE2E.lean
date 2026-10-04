import SimpLens

/-!
# ClickE2E — end-to-end click-simulation tests for the `Try this:` suggestion

`simp_lens` emits a core `TryThis` suggestion (replace the `simp_lens` call
with the minimal `simp only [...] (at ...)`). The suggestion *text* is
replay-equivalence-tested elsewhere; this module tests the missing piece: the
FILE-LEVEL edit a real click performs in a real user file.

The harness compiles a user source *string* through the real frontend
(`Parser.parseHeader` → `Elab.processHeader` → `Elab.IO.processCommands`,
info trees enabled), extracts the **exact LSP edit payload** the click/code
action applies — the `Lsp.TextEdit` stored in the `TryThisInfo` info leaf,
the very value `tryThisProvider` wraps in `WorkspaceEdit.ofTextEdit` — applies
it with Lean's own UTF-16 position conversion (`FileMap.lspRangeToUtf8Range`),
recompiles the edited file, and asserts the outcome:

* happy path: the edited file produces **zero** messages of any severity, no
  `sorry`, the declaration elaborated, and no leftover `simp_lens` token;
* intentionally-open-goal path: the edited file fails with the byte-identical
  pinned `unsolved goals` error the original `simp_lens` file fails with;
* negative controls: a corrupted `newText`, a shifted range, and an identity
  replacement each MUST make the harness fail (pinned failure text), proving
  the checks are not vacuous.

LSP ranges are in UTF-16 code units; `applyLspEdit` is unit-tested below on
multibyte sources (ℝ, ⋖, 😀) with pinned before/after strings that a
byte-offset or codepoint-offset implementation would get wrong, and the user
files include multibyte characters on the `simp_lens` line itself so a UTF-16
bug shifts the applied edit visibly (the recompile then fails).
-/

namespace SimpLensTests.ClickE2E

open Lean Elab Command Meta.Tactic.TryThis

/-! ## The LSP edit application (UTF-16-correct by construction) -/

/-- Apply a `TextDocumentEdit`-style `(range, newText)` to a source string.
The range is interpreted exactly as the LSP spec demands — line + UTF-16 code
unit column — by delegating to Lean's own `FileMap.lspRangeToUtf8Range`. -/
def applyLspEdit (source : String) (edit : Lsp.TextEdit) : String :=
  let map := FileMap.ofString source
  let r := map.lspRangeToUtf8Range edit.range
  String.Pos.Raw.extract source 0 r.start ++ edit.newText ++
    String.Pos.Raw.extract source r.stop source.rawEndPos

/-- Build an `Lsp.TextEdit` from raw line/UTF-16-column coordinates. -/
def mkEdit (sl sc el ec : Nat) (newText : String) : Lsp.TextEdit :=
  { range := ⟨⟨sl, sc⟩, ⟨el, ec⟩⟩, newText }

/-! ### `applyLspEdit` unit tests (pinned, multibyte)

`ℝ` is 3 UTF-8 bytes / 1 UTF-16 unit; `⋖` is 3 bytes / 1 unit; `😀` is
4 bytes / 2 UTF-16 units / 1 codepoint. Each pinned result below is wrong
under a byte-offset reading, and the emoji cases are wrong under a
codepoint-offset reading too. -/

-- ASCII sanity: replace "bc" in the middle
#guard applyLspEdit "abcd" (mkEdit 0 1 0 3 "XY") == "aXYd"
-- ℝ before the edit on the same line (byte offset would point inside `ℝ`)
#guard applyLspEdit "hℝx = y" (mkEdit 0 2 0 3 "Z") == "hℝZ = y"
-- ⋖ twice on the line; replace the `y` between them
#guard applyLspEdit "x ⋖ y ⋖ z" (mkEdit 0 4 0 5 "w") == "x ⋖ w ⋖ z"
-- 😀 = 2 UTF-16 units: col 3 is `b` (a codepoint reading says `c`)
#guard applyLspEdit "a😀bc" (mkEdit 0 3 0 4 "Z") == "a😀Zc"
-- pure insertion (empty range) after the emoji
#guard applyLspEdit "a😀bc" (mkEdit 0 3 0 3 "+") == "a😀+bc"
-- multi-line: unicode on line 0 must not shift a line-1 edit
#guard applyLspEdit "ℝ ⋖ 😀\nfoo bar\n" (mkEdit 1 4 1 7 "baz") == "ℝ ⋖ 😀\nfoo baz\n"
-- multi-line newText spliced into a one-line range
#guard applyLspEdit "aℝb\n" (mkEdit 0 2 0 3 "c,\n  d") == "aℝc,\n  d\n"
-- range spanning a newline collapses onto one line
#guard applyLspEdit "aℝ\n😀b\n" (mkEdit 0 1 1 2 "-") == "a-b\n"

/-! ## The in-process frontend -/

/-- Nested `importModules (loadExts := true)` (used by the in-process
frontend below) requires initializer execution to be enabled in this
process. -/
private unsafe def enableInitializersExecutionUnsafe : IO Unit :=
  Lean.enableInitializersExecution
@[implemented_by enableInitializersExecutionUnsafe]
private opaque enableInitializersExecutionSafe : IO Unit

/-- Outcome of compiling one user file through the real frontend. -/
structure CompileResult where
  /-- Final environment (contains the user file's declarations). -/
  env : Environment
  /-- All header-elaboration messages (import failures land here — the
  command-processing message collection *drops* them, so they must be
  checked separately). -/
  headerMessages : List Message
  /-- All command messages (errors, warnings, `Try this:` infos, …). -/
  messages : List Message
  /-- Every `TryThisInfo` LSP edit found in the info trees — the exact
  payloads the click / code action applies, extracted the same way core's
  `tryThisProvider` does. -/
  edits : Array Lsp.TextEdit

/-- Compile a full user source string (header included) through the real
frontend with info trees enabled, and collect the `TryThisInfo` edits. -/
def compileUser (source : String) : IO CompileResult := do
  enableInitializersExecutionSafe
  let inputCtx := Parser.mkInputContext source "E2EUserFile.lean"
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  let (env, headerMessages) ← Elab.processHeader header {} messages inputCtx
  let cmdState := Command.mkState env headerMessages {}
  let cmdState := { cmdState with infoState := { cmdState.infoState with enabled := true } }
  let s ← Elab.IO.processCommands inputCtx parserState cmdState
  let mut edits : Array Lsp.TextEdit := #[]
  for tree in s.commandState.infoState.trees do
    -- exactly `tryThisProvider`'s extraction: a `TryThisInfo` custom info
    -- leaf holds the ready-made `Lsp.TextEdit`
    edits := edits ++ tree.foldInfo (init := #[]) fun _ctx info acc =>
      match info with
      | .ofCustomInfo { stx := _, value } =>
        match value.get? TryThisInfo with
        | some tti => acc.push tti.edit
        | none => acc
      | _ => acc
  return { env := s.commandState.env
           headerMessages := headerMessages.toList
           messages := s.commandState.messages.toList
           edits }

/-- Render a message list for failure output. -/
def dumpMessages (msgs : List Message) : IO String := do
  let mut out := ""
  for m in msgs do
    out := out ++ s!"\n[{m.severity.toString}] {(← m.data.toString).trimAscii.toString}"
  return out

/-- Throw unless the header elaborated cleanly (a failed `import` otherwise
degrades every downstream check into parse noise). -/
def checkHeaderClean (r : CompileResult) : CommandElabM Unit := do
  unless r.headerMessages.isEmpty do
    throwError "E2E: header messages (import failure?):{← dumpMessages r.headerMessages}"

/-- Throw unless `s` contains no `simp_lens` token. -/
def checkNoLeftoverSimpLens (edited : String) : CommandElabM Unit := do
  unless (edited.splitOn "simp_lens").length == 1 do
    throwError "E2E: leftover simp_lens token in edited file:\n{edited}"

/-- Throw unless the edited user file is *perfectly* green: no messages of
any severity (no errors, no `sorry` warnings, no linter noise, no leftover
suggestions) and the expected declaration present in the environment. -/
def checkEditedGreen (edited : String) (decl : Name) : CommandElabM Unit := do
  let r ← compileUser edited
  checkHeaderClean r
  unless r.messages.isEmpty do
    throwError "E2E: edited file has messages:{← dumpMessages r.messages}\n--- edited file ---\n{edited}"
  unless r.env.contains decl do
    throwError "E2E: edited file did not elaborate declaration '{decl}'"

/-- Compile the original user file, check it is realistic (header clean, no
errors, declaration present) and yield its unique `TryThis` click edit. -/
def theClick (source : String) (decl : Name) : CommandElabM Lsp.TextEdit := do
  let r ← compileUser source
  checkHeaderClean r
  let errors := r.messages.filter (·.severity matches .error)
  unless errors.isEmpty do
    throwError "E2E: original file has errors:{← dumpMessages errors}"
  unless r.env.contains decl do
    throwError "E2E: original file did not elaborate declaration '{decl}'"
  let #[edit] := r.edits
    | throwError "E2E: expected exactly one TryThis edit, found {r.edits.size}"
  return edit

/-- Throw unless the click edit's `newText` is exactly the pinned string. -/
def checkNewTextPin (edit : Lsp.TextEdit) (expected : String) : CommandElabM Unit := do
  unless edit.newText == expected do
    throwError "E2E: newText mismatch\n  actual:   {repr edit.newText}\n  expected: {repr expected}"

/--
`#e2e_click decl => "newText" in "source"` — the full happy-path click:

1. compile `source`; it must be error-free, elaborate `decl`, and carry
   exactly one `TryThis` click edit;
2. the edit's `newText` must be exactly the pinned string;
3. apply the edit with `applyLspEdit`; the edited file must contain no
   `simp_lens` token;
4. recompile the edited file; it must produce **zero** messages (no errors,
   no sorries, no warnings, no infos) and still elaborate `decl`.
-/
elab "#e2e_click " decl:ident " => " expectedNewText:str " in " src:str : command => do
  let source := src.getString
  let edit ← theClick source decl.getId
  checkNewTextPin edit expectedNewText.getString
  let edited := applyLspEdit source edit
  checkNoLeftoverSimpLens edited
  checkEditedGreen edited decl.getId

/--
`#e2e_click_open decl => "newText" error "err" in "source"` — the
intentionally-open-goal click: `simp_lens` (and hence the suggested
`simp only`) does not close the goal, so *both* the original and the edited
file must fail with exactly the pinned `unsolved goals` error — the edit may
not turn a clean failure into elaboration garbage.
-/
elab "#e2e_click_open " decl:ident " => " expectedNewText:str " error " err:str
    " in " src:str : command => do
  let source := src.getString
  let expectedErr := err.getString.trimAscii.toString
  let checkSoleError (r : CompileResult) (which : String) : CommandElabM Unit := do
    let errors := r.messages.filter (·.severity matches .error)
    let [e] := errors
      | throwError "E2E: {which} file: expected exactly one error, got:{← dumpMessages errors}"
    let actual := (← e.data.toString).trimAscii.toString
    unless actual == expectedErr do
      throwError "E2E: {which} file error mismatch\n  actual:   {repr actual}\n  expected: {repr expectedErr}"
  let r ← compileUser source
  checkHeaderClean r
  checkSoleError r "original"
  -- the (sorried-on-error) declaration must still be the one named in the test
  unless r.env.contains decl.getId do
    throwError "E2E: original file did not produce declaration '{decl.getId}'"
  let #[edit] := r.edits
    | throwError "E2E: expected exactly one TryThis edit, found {r.edits.size}"
  checkNewTextPin edit expectedNewText.getString
  let edited := applyLspEdit source edit
  checkNoLeftoverSimpLens edited
  let r' ← compileUser edited
  checkHeaderClean r'
  checkSoleError r' "edited"
  -- the pinned error must be the *only* message: the suggestion info is gone
  -- and nothing else may appear
  unless r'.messages.length == 1 do
    throwError "E2E: edited file has extra messages:{← dumpMessages r'.messages}"
  -- ignore r/r' decl presence: a sorried decl is still added on error

/--
`#e2e_click_warn decl => "newText" warning_contains "s1", "s2" in "source"` —
happy-path click whose edited file compiles *with exactly one pinned
warning* (and nothing else). This documents a known, core-`simp?`-parity
wart: `mkSimpOnly` lists the used lemmas of the traced run, but replaying
`simp only [...]` can apply them in a different order and leave one unused,
tripping `linter.unusedSimpArgs`. Core's own `simp?` produces the
byte-identical suggestion with the byte-identical follow-up warning (verified
against v4.32.2), so the package intentionally inherits it.
-/
elab "#e2e_click_warn " decl:ident " => " expectedNewText:str
    " warning_contains " needles:str,+ " in " src:str : command => do
  let source := src.getString
  let edit ← theClick source decl.getId
  checkNewTextPin edit expectedNewText.getString
  let edited := applyLspEdit source edit
  checkNoLeftoverSimpLens edited
  let r ← compileUser edited
  checkHeaderClean r
  let [w] := r.messages
    | throwError "E2E: edited file: expected exactly one (warning) message, got:{← dumpMessages r.messages}"
  unless w.severity matches .warning do
    throwError "E2E: edited file: expected a warning, got:{← dumpMessages [w]}"
  let text ← w.data.toString
  for needle in needles.getElems do
    unless (text.splitOn needle.getString).length > 1 do
      throwError "E2E: edited file warning does not mention {repr needle.getString}:\n{text}"
  unless r.env.contains decl.getId do
    throwError "E2E: edited file did not elaborate declaration '{decl.getId}'"

/-! ## Negative controls — the harness MUST fail on corrupted edits -/

/-- Run `k`, assert it throws, and assert the failure text contains the
pinned `marker` (so the *right* check fired, not incidental noise). -/
def mustFail (what marker : String) (k : CommandElabM Unit) : CommandElabM Unit := do
  let failure? ←
    try k; pure none
    catch e => pure (some (← e.toMessageData.toString))
  match failure? with
  | none =>
    throwError "NEGATIVE {what}: harness accepted a corrupted edit — checks are vacuous"
  | some msg =>
    unless (msg.splitOn marker).length > 1 do
      throwError "NEGATIVE {what}: harness failed for the wrong reason:\n{msg}"

/-- `#e2e_negative decl in "source"` — three corruption controls on a known
happy-path file, each pinned to the check that must catch it:

* `newText` corrupted to reference an unknown lemma → the edited-file
  recompile must report messages (`edited file has messages`);
* range start shifted one UTF-16 unit right → the splice leaves a stray
  prefix character, the recompile must fail (`edited file has messages`);
* `newText` replaced by `simp_lens` itself → the leftover-token check must
  fire (`leftover simp_lens`);
* the pinned expectation corrupted (extra lemma appended) → the pin check
  must fire (`newText mismatch`) — this is the exact failure mode a drifted
  suggestion builder would produce, and the check every `#e2e_click` relies
  on first.
-/
elab "#e2e_negative " decl:ident " in " src:str : command => do
  let source := src.getString
  let edit ← theClick source decl.getId
  -- 1. corrupted newText
  mustFail "corrupt-newText" "edited file has messages" do
    let bad := { edit with newText := "simp only [thisLemmaDoesNotExist_xyz]" }
    let edited := applyLspEdit source bad
    checkNoLeftoverSimpLens edited
    checkEditedGreen edited decl.getId
  -- 2. shifted range (one UTF-16 unit to the right)
  mustFail "shifted-range" "edited file has messages" do
    let r := edit.range
    let bad := { edit with
      range := { r with start := { r.start with character := r.start.character + 1 } } }
    let edited := applyLspEdit source bad
    checkNoLeftoverSimpLens edited
    checkEditedGreen edited decl.getId
  -- 3. identity-ish corruption: the simp_lens token survives
  mustFail "leftover-token" "leftover simp_lens" do
    let bad := { edit with newText := "simp_lens" }
    let edited := applyLspEdit source bad
    checkNoLeftoverSimpLens edited
    checkEditedGreen edited decl.getId
  -- 4. corrupted pin: comparing the true payload against a wrong expectation
  -- must trip the pin check itself (non-vacuity of `checkNewTextPin`)
  mustFail "corrupt-pin" "newText mismatch" do
    checkNewTextPin edit (edit.newText ++ ", thisLemmaDoesNotExist_xyz]")

/-! ## The user files — one per link kind

Realistic sources importing only the package's public lib. Multibyte
characters sit on the `simp_lens` line itself (F7 aggressively so), making
any UTF-16 range bug shift the splice into a non-compiling file. -/

-- Kind 1: target-only `simp_lens`
#e2e_click target_only => "simp only [Nat.add_zero]" in
"import SimpLens

theorem target_only (n : Nat) : n + 0 + 0 = n := by simp_lens
"

-- Kind 2: hypothesis + target location (`at h ⊢`), suggestion preserves the
-- location clause; proof continues after the click with the same `exact`
#e2e_click at_hyp_target => "simp only [and_true, true_and] at h ⊢" in
"import SimpLens

theorem at_hyp_target (p q : Prop) (h : (p ∧ True) → q) : (True ∧ p) → q := by
  simp_lens at h ⊢
  exact h
"

-- Kind 3: wildcard location (`at *`)
#e2e_click at_star => "simp only [and_true, true_and] at *" in
"import SimpLens

theorem at_star (p : Prop) (h : p ∧ True) : True ∧ p := by
  simp_lens at *
  exact h
"

-- Kind 4: hypothesis-lemma call (`simp_lens [h]`) — the local hypothesis
-- survives into the suggestion by user-facing name, and the edited file is
-- perfectly green
#e2e_click hyp_lemma => "simp only [h]" in
"import SimpLens

theorem hyp_lemma (n m : Nat) (h : n = m) : n = m := by simp_lens [h]
"

-- Kind 4b (pinned wart, core-`simp?` parity): the traced run fires
-- `Nat.add_left_cancel_iff` before `h`, but the replayed `simp only` applies
-- `h` first, leaving the congruence lemma unused → `linter.unusedSimpArgs`
-- warns on the clicked-in code. Core `simp? [h]` emits the byte-identical
-- suggestion with the identical follow-up warning, so this is inherited
-- behavior, pinned here. Bonus coverage: the pinned newText is LINE-WRAPPED
-- (core TryThis wraps at input width 100 counting from the call's column,
-- 2-space continuation) and the wrapped splice must still parse and
-- elaborate (`simp`'s lemma list is `withoutPosition`).
#e2e_click_warn hyp_lemma_wrapped => "simp only [h,\n  Nat.add_left_cancel_iff]"
    warning_contains "This simp argument is unused:", "Nat.add_left_cancel_iff" in
"import SimpLens

theorem hyp_lemma_wrapped (n m : Nat) (h : n = m) : n + 1 = m + 1 := by simp_lens [h]
"

-- Kind 5: config-carrying call — the config clause survives verbatim in
-- core `simp (cfg) only [...]` order and the edited file still compiles
#e2e_click with_config => "simp (maxSteps := 500) only [Nat.add_zero]" in
"import SimpLens

theorem with_config (n : Nat) : n + 0 + 0 = n := by simp_lens (maxSteps := 500)
"

-- Kind 5b: the simp_lens-only `-previews` flag must NOT leak into the
-- suggestion (a leaked flag would make the edited `simp only` fail to
-- elaborate — `Simp.Config` has no `previews` field)
#e2e_click no_previews => "simp only [Nat.add_zero]" in
"import SimpLens

theorem no_previews (n : Nat) : n + 0 = n := by simp_lens -previews
"

-- Kind 1 under unicode pressure: multibyte idents (ε, _hℝ), a docstring
-- with ℝ ⋖ 😀, and an emoji block comment BEFORE `simp_lens` on the same
-- line — a byte- or codepoint-offset bug shifts the splice mid-token
#e2e_click uni₁ => "simp only [Nat.zero_add]" in
"import SimpLens

/-- Unicode: ℝ ⋖ 😀 in the docstring. -/
theorem uni₁ (ε : Nat) (_hℝ : ε + 0 = ε) : (0 : Nat) + ε = ε := by /- 🎯 ⋖ ℝ -/ simp_lens
"

-- Kind 6: indented tactic block on its own line (blank-line/indent sanity:
-- the splice replaces exactly the token at column 2, no stray lines)
#e2e_click indented => "simp only [List.append_nil]" in
"import SimpLens

theorem indented (l : List Nat) : (l ++ []) ++ [] = l := by
  simp_lens
"

-- Intentionally-open goal: `simp_lens` (and the suggested `simp only`)
-- leaves `p` open; both sides must fail with exactly this pinned error
#e2e_click_open open_goal => "simp only [true_and]" error
"unsolved goals
p : Prop
h : p
⊢ p" in
"import SimpLens

theorem open_goal (p : Prop) (h : p) : True ∧ p := by simp_lens
"

-- Negative controls (non-vacuity) on the Kind 1 file
#e2e_negative target_only in
"import SimpLens

theorem target_only (n : Nat) : n + 0 + 0 = n := by simp_lens
"

end SimpLensTests.ClickE2E

