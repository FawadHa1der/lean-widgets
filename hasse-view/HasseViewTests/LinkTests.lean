import HasseViewTests.Helpers
import HasseView.Demo

/-! # Click-to-insert link tests

The insertable-examples feature, audited end to end:

* **byte-exact pins of the pure text builders** (`coverProp`, `botProp`,
  `topProp`, `noJoinProp`, `noMeetProp`, `exampleText`, `insertionText`);
* **the exact generated texts COMPILE** for every link kind over the demo
  data — statically below (readable) and mechanically via
  `#compile_insertions`, which runs the real extraction + gate pipeline,
  asserts how many candidates were verified, then parses and elaborates
  every offered insertion text as a command (the house rule enforced: a
  suggestion that does not provably hold may never be offered — and one
  that is offered must compile);
* **round-trip gate unit tests**, positive (`Fin`/`Bool`/`Finset`/`Bowtie`
  labels) and negative (labels that parse to a *different* element, labels
  with proof holes such as the subtype `⟨4, _⟩` shape, labels that are not
  element syntax at all, out-of-range indices);
* **statement gate unit tests**, positive and negative (false statements,
  non-`Prop`s, undecidable statements, `Classical`-noncomputable
  instances);
* **`#links_report` pins** of the full gate verdict — including `Div12`,
  whose `Repr` labels are rejected wholesale (the plain-text fallback);
* **serializer pins of the panel**: `MakeEditLink` component nodes carrying
  the expected `newText` when the gate passes, plain text plus muted note
  when it fails, and byte-identity of the link-free panel with the
  pre-link `renderPanel`.
-/

namespace HasseViewTests

open HasseView Lean Elab Command

/-! ## Pure text builders, byte-exact -/

#guard coverProp "(Fin 5)" "1" "2" == "(1 : (Fin 5)) ⋖ 2"
#guard coverProp "(Finset (Fin 3))" "∅" "{2}" == "(∅ : (Finset (Fin 3))) ⋖ {2}"
#guard botProp "(Fin 3)" "0" == "∀ x : (Fin 3), (0 : (Fin 3)) ≤ x"
#guard topProp "(Fin 3)" "2" == "∀ x : (Fin 3), x ≤ (2 : (Fin 3))"
#guard noJoinProp "Bowtie" "1" "2" ==
  "¬ ∃ m : Bowtie, ((1 : Bowtie) ≤ m ∧ (2 : Bowtie) ≤ m) ∧ \
   ∀ u : Bowtie, ((1 : Bowtie) ≤ u ∧ (2 : Bowtie) ≤ u) → m ≤ u"
#guard noMeetProp "Bowtie" "3" "4" ==
  "¬ ∃ m : Bowtie, (m ≤ (3 : Bowtie) ∧ m ≤ (4 : Bowtie)) ∧ \
   ∀ l : Bowtie, (l ≤ (3 : Bowtie) ∧ l ≤ (4 : Bowtie)) → l ≤ m"
#guard exampleText "True" == "example : True := by decide"
#guard insertionText "True" == "\nexample : True := by decide"

/-! ## The cover-verification cap (pure mirror of the gate's check) -/

#guard coversLinkable (cubeP 3)          -- 12 covers ≤ 32
#guard coversLinkable (cubeP 4)          -- exactly 32 covers
#guard !coversLinkable (cubeP 5)         -- 80 covers > 32
#guard (cubeP 5).coverCount == 80

/-! ## `PanelLinks` helpers -/

#guard PanelLinks.empty.isEmpty
#guard PanelLinks.empty.size == 0
#guard !fin3Links.isEmpty
#guard fin3Links.size == 4
#guard rejectedLinks.size == 3

/-! ## The exact generated texts compile (static, representative)

These are literally the builders' outputs for the demo data (pinned above),
written out so a reader can see the inserted examples type-check.  The
`#compile_insertions` commands below cover *every* offered text
mechanically. -/

open HasseView.Demo

-- Cover edges, one per demo type (⋖ closes by `decide` thanks to
-- `HasseView.instDecidableRelCovByOfFintype`).
example : (1 : (Fin 5)) ⋖ 2 := by decide
example : ({0} : (Finset (Fin 3))) ⋖ {0, 1} := by decide
example : (∅ : (Finset (Fin 3))) ⋖ {2} := by decide
example : ((false, false) : (Bool × Bool)) ⋖ (false, true) := by decide
example : (1 : Bowtie) ⋖ 3 := by decide

-- ⊥/⊤ badge facts, phrased without OrderBot/OrderTop.
example : ∀ x : (Finset (Fin 3)), (∅ : (Finset (Fin 3))) ≤ x := by decide
example : ∀ x : (Finset (Fin 3)), x ≤ ({0, 1, 2} : (Finset (Fin 3))) := by decide
example : ∀ x : Bowtie, (0 : Bowtie) ≤ x := by decide

-- The non-lattice witness fact for the bowtie (no Set-based IsLUB).
example : ¬ ∃ m : Bowtie, ((1 : Bowtie) ≤ m ∧ (2 : Bowtie) ≤ m) ∧
    ∀ u : Bowtie, ((1 : Bowtie) ≤ u ∧ (2 : Bowtie) ≤ u) → m ≤ u := by decide

-- Its noMeet dual (3, 4 have no meet), pinning the dual builder's shape.
example : ¬ ∃ m : Bowtie, (m ≤ (3 : Bowtie) ∧ m ≤ (4 : Bowtie)) ∧
    ∀ l : Bowtie, (l ≤ (3 : Bowtie) ∧ l ≤ (4 : Bowtie)) → l ≤ m := by decide

-- Honesty sanity: a NON-cover does not decide to true (so the gate's
-- statement check can genuinely fail on wrong pairs).
example : ¬ ((∅ : Finset (Fin 3)) ⋖ {0, 1}) := by decide

/-! ## Gate assertion commands -/

/-- `#assert_label_roundtrips V "l" i`: build fails unless label `l`
parses, elaborates at `V`, and equals element `i` of the enumeration. -/
elab "#assert_label_roundtrips " t:term:max l:str i:num : command =>
  liftTermElabM do
    let V ← Term.elabTerm t none
    Term.synthesizeSyntheticMVarsNoPostponing
    let V ← Lean.instantiateMVars V
    let finInst ← synthOrExplain (← Lean.Meta.mkAppM ``Fintype #[V])
    let deqInst ← synthOrExplain (← Lean.Meta.mkAppM ``DecidableEq #[V])
    unless ← labelRoundTrips V finInst deqInst l.getString i.getNat do
      throwError "expected label {l.getString} to round-trip to element {i.getNat}"

/-- `#assert_label_rejected V "l" i`: build fails unless the gate REJECTS. -/
elab "#assert_label_rejected " t:term:max l:str i:num : command =>
  liftTermElabM do
    let V ← Term.elabTerm t none
    Term.synthesizeSyntheticMVarsNoPostponing
    let V ← Lean.instantiateMVars V
    let finInst ← synthOrExplain (← Lean.Meta.mkAppM ``Fintype #[V])
    let deqInst ← synthOrExplain (← Lean.Meta.mkAppM ``DecidableEq #[V])
    if ← labelRoundTrips V finInst deqInst l.getString i.getNat then
      throwError "expected label {l.getString} to be rejected for element {i.getNat}"

/-- `#assert_stmt_holds "p"`: build fails unless the statement gate verifies
`p` (elaborates at `Prop`, computable `Decidable`, evaluates `true`). -/
elab "#assert_stmt_holds " s:str : command =>
  liftTermElabM do
    unless ← statementHolds s.getString do
      throwError "expected statement to verify: {s.getString}"

/-- `#assert_stmt_rejected "p"`: build fails unless the statement gate
rejects `p`. -/
elab "#assert_stmt_rejected " s:str : command =>
  liftTermElabM do
    if ← statementHolds s.getString then
      throwError "expected statement to be rejected: {s.getString}"

/-! ## Round-trip gate: positives -/

#assert_label_roundtrips (Fin 5) "3" 3
#assert_label_roundtrips Bool "true" 0   -- Bool.fintype enumerates {true, false}
#assert_label_roundtrips Bool "false" 1
#assert_label_roundtrips (Finset (Fin 3)) "∅" 0        -- bitmask order
#assert_label_roundtrips (Finset (Fin 3)) "{0, 1}" 3   -- bits 0+1 = index 3
#assert_label_roundtrips Bowtie "4" 4                  -- via the OfNat demo instance

/-! ## Round-trip gate: negatives -/

-- Parses and elaborates fine — but to a DIFFERENT element than the drawn
-- one.  This is exactly the compiling-but-wrong case the gate exists for.
#assert_label_rejected (Fin 5) "0" 1
#assert_label_rejected (Finset (Fin 3)) "{0}" 2        -- {0} is index 1, not 2

-- Proof holes: the anonymous-constructor shapes a default subtype `Repr`
-- would print.  They elaborate with a metavariable, never silently.
#assert_label_rejected (Fin 5) "⟨4, _⟩" 4
#assert_label_rejected Div12 "⟨4, _⟩" 3

-- Not valid element syntax at all (Div12 has no OfNat: its `Repr` labels
-- are numerals that do not elaborate — the demo's plain-text fallback).
#assert_label_rejected Div12 "4" 3
#assert_label_rejected (Fin 5) "]junk[" 0

-- Out-of-range index is never equal to anything.
#assert_label_rejected (Fin 5) "4" 9

/-! ## Statement gate: positives -/

#assert_stmt_holds "(1 : Fin 5) ⋖ 2"
#assert_stmt_holds "∀ x : Bool, (false : Bool) ≤ x"
#assert_stmt_holds "¬ ∃ m : Bowtie, ((1 : Bowtie) ≤ m ∧ (2 : Bowtie) ≤ m) ∧ \
  ∀ u : Bowtie, ((1 : Bowtie) ≤ u ∧ (2 : Bowtie) ≤ u) → m ≤ u"

/-! ## Statement gate: negatives -/

#assert_stmt_rejected "(0 : Fin 5) ⋖ 2"                 -- false (not a cover)
#assert_stmt_rejected "∀ x : Fin 5, (1 : Fin 5) ≤ x"    -- false (1 is not ⊥)
#assert_stmt_rejected "1 + 1"                           -- not a Prop
#assert_stmt_rejected "∀ n : Nat, n = n"                -- no computable Decidable
-- With Classical open, a Decidable instance DOES synthesize — a
-- noncomputable one, which the gate must reject rather than trust.
open scoped Classical in
#assert_stmt_rejected "∀ n : Nat, n = n"

/-! ## The real pipeline: reports and compiled insertions -/

/-- One report line per candidate (`inserts:` when verified, the note when
not). -/
def factReport (kind : String) (f : InsertableFact) : String :=
  match f.newText? with
  | some t => s!"{kind} {f.display} inserts: {t.trimAscii.toString}"
  | none => s!"{kind} {f.display} — {f.note?.getD "(no note)"}"

/-- Deterministic multi-line report of all candidates of a `PanelLinks`. -/
def linksReport (l : PanelLinks) : String :=
  let lines := l.covers.map (factReport "cover" ·)
    ++ (l.bot?.map (factReport "⊥" ·)).toArray
    ++ (l.top?.map (factReport "⊤" ·)).toArray
    ++ (l.witness?.map (factReport "witness" ·)).toArray
  if lines.isEmpty then "no candidates" else "\n".intercalate lines.toList

/-- Run the real extraction + link gate on `V` (with the user-syntax rule
the command applies) and return the candidates.  Uses the command's own
`userSyntaxString` so these compiled-insertion tests always verify the exact
rule `#hasse` applies (auditor finding: a private re-implementation here could
drift from the command silently). -/
def elabLinks (t : Syntax.Term) : CommandElabM PanelLinks := do
  let tyStr := userSyntaxString t
  liftTermElabM do
    let V ← Term.elabTerm t none
    Term.synthesizeSyntheticMVarsNoPostponing
    let V ← Lean.instantiateMVars V
    let d ← extractPosetData V
    buildLinks V tyStr d

/-- `#links_report V`: log the gate verdict for every candidate (pinned by
`#guard_msgs`). -/
elab "#links_report " t:term:max : command => do
  logInfo (linksReport (← elabLinks t))

/-- `#compile_insertions V expecting n`: run the real pipeline, assert that
exactly `n` candidates were verified, then parse and elaborate every offered
insertion text as a command — an offered example that does not compile (or
does not prove) fails the build. -/
elab "#compile_insertions " t:term:max " expecting " n:num : command => do
  let links ← elabLinks t
  let texts := (links.covers ++ links.bot?.toArray ++ links.top?.toArray
    ++ links.witness?.toArray).filterMap (·.newText?)
  unless texts.size == n.getNat do
    throwError "expected {n.getNat} verified insertions, got {texts.size}:\n{linksReport links}"
  for txt in texts do
    match Parser.runParserCategory (← getEnv) `command txt.trimAscii.toString with
    | .error e => throwError "generated text failed to parse: {e}\n{txt}"
    | .ok stx => elabCommand stx

/--
info: cover 0 ⋖ 1 inserts: example : (0 : (Fin 3)) ⋖ 1 := by decide
cover 1 ⋖ 2 inserts: example : (1 : (Fin 3)) ⋖ 2 := by decide
⊥ ∀ x, 0 ≤ x inserts: example : ∀ x : (Fin 3), (0 : (Fin 3)) ≤ x := by decide
⊤ ∀ x, x ≤ 2 inserts: example : ∀ x : (Fin 3), x ≤ (2 : (Fin 3)) := by decide
-/
#guard_msgs in
#links_report (Fin 3)

-- Div12: the round-trip gate rejects every label (no `OfNat Div12`), so
-- every candidate is the plain-text fallback with the honest note.
/--
info: cover 1 ⋖ 2 — (not insertable: label is not valid syntax for the element)
cover 1 ⋖ 3 — (not insertable: label is not valid syntax for the element)
cover 2 ⋖ 4 — (not insertable: label is not valid syntax for the element)
cover 2 ⋖ 6 — (not insertable: label is not valid syntax for the element)
cover 3 ⋖ 6 — (not insertable: label is not valid syntax for the element)
cover 4 ⋖ 12 — (not insertable: label is not valid syntax for the element)
cover 6 ⋖ 12 — (not insertable: label is not valid syntax for the element)
⊥ ∀ x, 1 ≤ x — (not insertable: label is not valid syntax for the element)
⊤ ∀ x, x ≤ 12 — (not insertable: label is not valid syntax for the element)
-/
#guard_msgs in
#links_report Div12

-- The bowtie: covers + ⊥ + the concrete no-join witness (no ⊤, no coatoms).
/--
info: cover 0 ⋖ 1 inserts: example : (0 : Bowtie) ⋖ 1 := by decide
cover 0 ⋖ 2 inserts: example : (0 : Bowtie) ⋖ 2 := by decide
cover 1 ⋖ 3 inserts: example : (1 : Bowtie) ⋖ 3 := by decide
cover 1 ⋖ 4 inserts: example : (1 : Bowtie) ⋖ 4 := by decide
cover 2 ⋖ 3 inserts: example : (2 : Bowtie) ⋖ 3 := by decide
cover 2 ⋖ 4 inserts: example : (2 : Bowtie) ⋖ 4 := by decide
⊥ ∀ x, 0 ≤ x inserts: example : ∀ x : Bowtie, (0 : Bowtie) ≤ x := by decide
witness no join of 1, 2 inserts: example : ¬ ∃ m : Bowtie, ((1 : Bowtie) ≤ m ∧ (2 : Bowtie) ≤ m) ∧ ∀ u : Bowtie, ((1 : Bowtie) ≤ u ∧ (2 : Bowtie) ≤ u) → m ≤ u := by decide
-/
#guard_msgs in
#links_report Bowtie

-- Every offered text over every demo type compiles (and the counts pin the
-- gate's acceptance exactly).
#compile_insertions (Fin 5) expecting 6
#compile_insertions (Finset (Fin 3)) expecting 14
#compile_insertions (Bool × Bool) expecting 6
#compile_insertions Bowtie expecting 8
#compile_insertions Div12 expecting 0

/-! ## Serializer pins of the panel

`editLink` is the exact renderer the RPC method uses; with the stand-in
document metadata it serializes headlessly. -/

private def linkedPanelStr : String :=
  htmlToDebugString (renderPanelWith (chainP 3) (links := fin3Links)
    (mkLink := editLink testDocMeta testInsertRange))

-- One MakeEditLink component per verified candidate.
#guard countOccurrences linkedPanelStr "<component:" == 4
-- The components carry the exact insertion texts…
#guard containsSubstr linkedPanelStr "example : (0 : (Fin 3)) ⋖ 1 := by decide"
#guard containsSubstr linkedPanelStr "example : (1 : (Fin 3)) ⋖ 2 := by decide"
#guard containsSubstr linkedPanelStr
  "example : ∀ x : (Fin 3), (0 : (Fin 3)) ≤ x := by decide"
#guard containsSubstr linkedPanelStr
  "example : ∀ x : (Fin 3), x ≤ (2 : (Fin 3)) := by decide"
-- …against the right document and the zero-width insertion range.
#guard containsSubstr linkedPanelStr "file:///Demo.lean"
#guard containsSubstr linkedPanelStr "\"version\":7"
#guard containsSubstr linkedPanelStr
  "\"range\":{\"end\":{\"character\":0,\"line\":5},\"start\":{\"character\":0,\"line\":5}}"
-- The section title and per-kind markers render.
#guard containsSubstr linkedPanelStr "Insertable examples"
#guard countOccurrences linkedPanelStr ">cover</span>" == 2

private def rejectedPanelStr : String :=
  htmlToDebugString (renderPanelWith (chainP 3) (links := rejectedLinks)
    (mkLink := editLink testDocMeta testInsertRange))

-- Gate failures render as plain text: no components, honest notes.
#guard countOccurrences rejectedPanelStr "<component:" == 0
#guard containsSubstr rejectedPanelStr
  "(not insertable: label is not valid syntax for the element)"
#guard containsSubstr rejectedPanelStr
  "(not insertable: could not verify the statement)"

-- With no candidates the panel is byte-identical to the pre-link panel —
-- and the plain-link renderer shows the same body minus clickability.
#guard htmlToDebugString (renderPanelWith (cubeP 3))
  == htmlToDebugString (renderPanel (cubeP 3))
#guard htmlToDebugString
    (renderPanelWith (cubeP 3) (highlight? := some #[0, 7]) (updown? := some 1))
  == htmlToDebugString (renderPanel (cubeP 3) (highlight? := some #[0, 7]) (updown? := some 1))
#guard (linksSection .empty plainLink).isNone
#guard countOccurrences
  (htmlToDebugString (renderPanelWith (chainP 3) (links := fin3Links))) "<component:" == 0
#guard containsSubstr
  (htmlToDebugString (renderPanelWith (chainP 3) (links := fin3Links))) "0 ⋖ 1"

end HasseViewTests
