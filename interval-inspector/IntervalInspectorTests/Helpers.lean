import IntervalInspector

/-! # Test helpers

Throwing assertion commands (each use is one compile-time assertion: the build fails
on any mismatch, with an error message showing expected vs. actual) and shared pure
constructors for building model values in tests.

The assertion commands elaborate their term with `runTermElabM` — the same
section-`variable`-aware entry point `#interval_inspect` uses — so tests can pin the
section-variable behavior (`section variable (a b : ℝ) (h : a ≤ b) …`), including
section hypotheses feeding `factsFromLCtx`.
-/

namespace IntervalInspectorTests

open Lean Elab Command Term Meta IntervalInspector

/-- Elaborate a term (peeling `∀`/`fun` binders) and recognize its shape. -/
def elabShape (t : Syntax.Term) : TermElabM (Option RecognizedStmt) := do
  let e ← Term.elabTerm t none
  Term.synthesizeSyntheticMVarsNoPostponing
  recognizeWithBindersM? (← instantiateMVars e)

/-- Elaborate a term and run the full analysis pipeline (recognition, binder-fact
harvesting, instance availability, order graph, layout, suggestions) — the same
path the command and panel use. -/
def elabAnalysis (t : Syntax.Term) : TermElabM (Option IntervalInspector.Analysis) := do
  let e ← Term.elabTerm t none
  Term.synthesizeSyntheticMVarsNoPostponing
  analyzeWithLCtx? (← instantiateMVars e)

/-- `#assert_shape e => "dbg"`: assert that `e` is recognized and its
`Shape.debugString` is exactly `dbg`. -/
elab "#assert_shape " t:term " => " s:str : command =>
  runTermElabM fun _ => do
    match ← elabShape t with
    | some r =>
      unless r.shape.debugString == s.getString do
        throwError "shape mismatch:\n  expected: {s.getString}\n  actual:   {r.shape.debugString}"
    | none => throwError "expected shape {s.getString}, but recognition returned none"

/-- `#assert_no_shape e`: assert that recognition returns `none` for `e`. -/
elab "#assert_no_shape " t:term : command =>
  runTermElabM fun _ => do
    if let some r ← elabShape t then
      throwError "expected none, but recognized: {r.shape.debugString}"

/-- `#assert_atoms e => "a, b=2"`: assert the recognized shape's atom list —
each atom rendered as `pp` or `pp={literal value}` — joined by `", "`. -/
elab "#assert_atoms " t:term " => " s:str : command =>
  runTermElabM fun _ => do
    match ← elabShape t with
    | some r =>
      let strs := r.shape.atoms.map fun a =>
        match a.val? with
        | some v => s!"{a.pp}={v}"
        | none => a.pp
      let actual := String.intercalate ", " strs.toList
      unless actual == s.getString do
        throwError "atoms mismatch:\n  expected: {s.getString}\n  actual:   {actual}"
    | none => throwError "expected a shape, but recognition returned none"

/-- `#assert_facts e => "a ≤ b; c < d"`: assert the ordering facts harvested from
`e`'s binders (each rendered `lhs ≤/</= rhs`), joined by `"; "`. -/
elab "#assert_facts " t:term " => " s:str : command =>
  runTermElabM fun _ => do
    match ← elabShape t with
    | some r =>
      let strs := r.facts.map fun f =>
        match f.rel with
        | .le => s!"{f.lhs} ≤ {f.rhs}"
        | .lt => s!"{f.lhs} < {f.rhs}"
        | .eq => s!"{f.lhs} = {f.rhs}"
      let actual := String.intercalate "; " strs.toList
      unless actual == s.getString do
        throwError "facts mismatch:\n  expected: {s.getString}\n  actual:   {actual}"
    | none => throwError "expected a shape, but recognition returned none"

/-- `#assert_suggests e => "Set.foo, Set.bar"`: assert exactly which table entries
fire on the recognized shape (integration of recognition + suggestion matching;
instance availability is deliberately ignored here — see `#assert_reports`). -/
elab "#assert_suggests " t:term " => " s:str : command =>
  runTermElabM fun _ => do
    match ← elabShape t with
    | some r =>
      let actual := String.intercalate ", " (firingLemmas r.shape).toList
      unless actual == s.getString do
        throwError "suggestions mismatch:\n  expected: {s.getString}\n  actual:   {actual}"
    | none => throwError "expected a shape, but recognition returned none"

/-- `#assert_insts e => "LinearOrder DenselyOrdered"`: assert exactly which order
typeclasses recognition found available for `e`'s element type (space-separated,
fixed order, `-` when none). -/
elab "#assert_insts " t:term " => " s:str : command =>
  runTermElabM fun _ => do
    match ← elabShape t with
    | some r =>
      let names := (#[(r.inst.partialOrder, "PartialOrder"), (r.inst.linearOrder, "LinearOrder"),
        (r.inst.lattice, "Lattice"), (r.inst.denselyOrdered, "DenselyOrdered"),
        (r.inst.noMinOrder, "NoMinOrder"), (r.inst.noMaxOrder, "NoMaxOrder")].filterMap
          fun (b, n) => if b then some n else none)
      let actual := if names.isEmpty then "-" else String.intercalate " " names.toList
      unless actual == s.getString do
        throwError "insts mismatch:\n  expected: {s.getString}\n  actual:   {actual}"
    | none => throwError "expected a shape, but recognition returned none"

/-- `#assert_reports e => "report₁ | report₂"`: assert the full analysis-pipeline
suggestion reports (`Suggestion.report`, which includes side-condition readiness and
missing-instance markers), each suffixed ` [ALL-READY]` when ready, joined by
`" | "`.  This is the end-to-end pin: recognition + binder facts + transitive order
graph + instance gating. -/
elab "#assert_reports " t:term " => " s:str : command =>
  runTermElabM fun _ => do
    match ← elabAnalysis t with
    | some a =>
      let strs := a.suggestions.map fun sg =>
        sg.report ++ (if sg.ready then " [ALL-READY]" else "")
      let actual := String.intercalate " | " strs.toList
      unless actual == s.getString do
        throwError "reports mismatch:\n  expected: {s.getString}\n  actual:   {actual}"
    | none => throwError "expected a shape, but recognition returned none"

/-- `#assert_suppressed e => "note₁ | note₂"`: assert the instance-suppression notes
of the analysis (`-` when none). -/
elab "#assert_suppressed " t:term " => " s:str : command =>
  runTermElabM fun _ => do
    match ← elabAnalysis t with
    | some a =>
      let actual := if a.suppressed.isEmpty then "-"
        else String.intercalate " | " a.suppressed.toList
      unless actual == s.getString do
        throwError "suppressed mismatch:\n  expected: {s.getString}\n  actual:   {actual}"
    | none => throwError "expected a shape, but recognition returned none"

/-- `#assert_unknown_pairs e => "(a, b); (c, d)"`: assert the order graph's unknown
pairs after the full pipeline (`-` when none). -/
elab "#assert_unknown_pairs " t:term " => " s:str : command =>
  runTermElabM fun _ => do
    match ← elabAnalysis t with
    | some a =>
      let strs := a.graph.unknownPairs.map fun (x, y) => s!"({x}, {y})"
      let actual := if strs.isEmpty then "-" else String.intercalate "; " strs.toList
      unless actual == s.getString do
        throwError "unknown-pairs mismatch:\n  expected: {s.getString}\n  actual:   {actual}"
    | none => throwError "expected a shape, but recognition returned none"

/-- Serialized SVG of the full analysis of `t` (same call the panel makes,
including instance availability). -/
def elabSvg (t : Syntax.Term) : TermElabM String := do
  match ← elabAnalysis t with
  | some a => return htmlToDebugString (renderShapeSvg a.shape a.graph a.layout a.inst)
  | none => throwError "expected a shape, but recognition returned none"

/-- `#assert_svg_has e => "substr"`: assert the end-to-end rendered SVG contains the
substring. -/
elab "#assert_svg_has " t:term " => " s:str : command =>
  runTermElabM fun _ => do
    let svg ← elabSvg t
    unless strContains svg s.getString do
      throwError "svg does not contain {s.getString}:\n{svg}"

/-- `#assert_svg_lacks e => "substr"`: assert the end-to-end rendered SVG does *not*
contain the substring. -/
elab "#assert_svg_lacks " t:term " => " s:str : command =>
  runTermElabM fun _ => do
    let svg ← elabSvg t
    if strContains svg s.getString then
      throwError "svg unexpectedly contains {s.getString}:\n{svg}"

/-- `#assert_react_contract e`: run the full pipeline on `e` and assert that the
panel `Html` the `#interval_inspect` command builds (`inspectorHtml … plainTactic`)
has no React-contract violations (`reactContractViolations`): every `style`
attribute is a JSON object (a CSS string crashes the InfoView with React
error #62), no attribute is literally named `class`, and no attribute uses a
hyphenated SVG spelling React warns about (`stroke-width` & co.). -/
elab "#assert_react_contract " t:term : command =>
  runTermElabM fun _ => do
    match ← elabAnalysis t with
    | some a =>
      let vs := reactContractViolations (inspectorHtml a plainTactic)
      unless vs.isEmpty do
        throwError "React contract violations:\n{String.intercalate "\n" vs}"
    | none => throwError "expected a shape, but recognition returned none"

/-! ## Pure model constructors -/

/-- Symbolic endpoint. -/
def ep (s : String) : Endpoint := { pp := s }

/-- Literal endpoint with value. -/
def epv (s : String) (v : Rat) : Endpoint := { pp := s, val? := some v }

/-- Double-ended leaf tree with symbolic endpoints. -/
def de (k : IntervalKind) (a b : String) : Tree :=
  .leaf { kind := k, lo? := some (ep a), hi? := some (ep b) }

/-- Double-ended leaf tree with literal endpoints. -/
def dev (k : IntervalKind) (a : String) (va : Rat) (b : String) (vb : Rat) : Tree :=
  .leaf { kind := k, lo? := some (epv a va), hi? := some (epv b vb) }

/-- Double-ended leaf tree recognized from set-builder notation (symbolic endpoints). -/
def deSB (k : IntervalKind) (a b : String) : Tree :=
  .leaf { kind := k, lo? := some (ep a), hi? := some (ep b), fromSetBuilder := true }

/-- Double-ended leaf tree recognized from set-builder notation (literal endpoints). -/
def devSB (k : IntervalKind) (a : String) (va : Rat) (b : String) (vb : Rat) : Tree :=
  .leaf { kind := k, lo? := some (epv a va), hi? := some (epv b vb), fromSetBuilder := true }

/-- Left-bounded ray leaf (`Ici`/`Ioi`). -/
def rayLo (k : IntervalKind) (a : String) : Tree := .leaf { kind := k, lo? := some (ep a) }

/-- Right-bounded ray leaf (`Iic`/`Iio`). -/
def rayHi (k : IntervalKind) (b : String) : Tree := .leaf { kind := k, hi? := some (ep b) }

/-- `Set.univ` leaf. -/
def univT : Tree := .leaf { kind := .univ }

/-- `∅` leaf. -/
def emptyT : Tree := .leaf { kind := .empty }

/-- `{a}` leaf. -/
def singT (a : String) : Tree :=
  .leaf { kind := .singleton, lo? := some (ep a), hi? := some (ep a) }

/-- Order graph from symbolic atoms and facts. -/
def graphOf (atoms : List String) (facts : List OrderFact) : OrderGraph :=
  OrderGraph.build (atoms.toArray.map fun a => (a, none)) facts.toArray

/-- Order graph from valued atoms and facts. -/
def graphOfV (atoms : List (String × Option Rat)) (facts : List OrderFact) : OrderGraph :=
  OrderGraph.build atoms.toArray facts.toArray

/-- `a ≤ b` fact. -/
def fLe (a b : String) : OrderFact := { lhs := a, rhs := b, rel := .le }
/-- `a < b` fact. -/
def fLt (a b : String) : OrderFact := { lhs := a, rhs := b, rel := .lt }
/-- `a = b` fact. -/
def fEq (a b : String) : OrderFact := { lhs := a, rhs := b, rel := .eq }

end IntervalInspectorTests
