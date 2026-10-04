import ExprXRay

/-! # Test utilities

Small assertion helpers that `throwError` on mismatch, so a failing check
inside `#eval show TermElabM Unit from ...` fails the build (`lake test`). -/

namespace ExprXRayTests

open Lean Elab Term Meta ExprXRay

/-! ## React style-contract checker (permanent)

The InfoView passes `ProofWidgets.Html` element attributes straight through
as React props. React requires the `style` prop to be a JSON *object* with
camelCased property names — a raw CSS string (e.g.
`"font-family:monospace"`) crashes the entire panel at runtime with minified
React error #62, and compile-time tests never run React, so the only way to
catch a regression in the suite is to walk the produced `Html`. The checker
lives in the test helper (not the lib) because it is test infrastructure:
the lib's rendering contract is *checked* by it, not implemented with it. -/

/-- Walk an `Html` tree and return one path-labeled entry for every element
whose `"style"` attribute value is NOT a `Json.obj` (the React error #62
shape), plus every attribute literally named `"class"` (React requires
`className`). An empty result means the tree satisfies the React contract.
Recurses into both element and component children. -/
partial def reactContractViolations (h : ProofWidgets.Html) : List String :=
  go "" h
where
  /-- Worker carrying the `path/tag[idx]` label of the current node. -/
  go (path : String) : ProofWidgets.Html → List String
    | .text _ => []
    | .element tag attrs children =>
      let here := s!"{path}/{tag}"
      let attrIssues := attrs.toList.filterMap fun (k, v) =>
        if k == "style" then
          match v with
          | .obj _ => Option.none
          | _ => some s!"{here}: style attribute is not a JSON object \
                   (React error #62): {v.compress}"
        else if k == "class" then
          some s!"{here}: attribute \"class\" — React requires \"className\""
        else Option.none
      let childIssues :=
        (children.mapIdx fun i c => go s!"{here}[{i}]" c).foldl (· ++ ·) []
      attrIssues ++ childIssues
    | .component _ exp _ children =>
      (children.mapIdx fun i c => go s!"{path}/component:{exp}[{i}]" c).foldl (· ++ ·) []

/-- Elaborate a term for testing: elaborate, synthesize synthetic mvars,
instantiate. Mirrors what `#xray` does. -/
def elabT (stx : Term) : TermElabM Expr := do
  let e ← Term.elabTerm stx none
  Term.synthesizeSyntheticMVarsNoPostponing
  instantiateMVars e

/-- Assert that `b` is true, failing elaboration with `label` otherwise. -/
def assertTrue (label : String) (b : Bool) : TermElabM Unit := do
  unless b do
    throwError "ASSERT FAILED [{label}]: expected true"

/-- Assert that `b` is false. -/
def assertFalse (label : String) (b : Bool) : TermElabM Unit := do
  if b then
    throwError "ASSERT FAILED [{label}]: expected false"

/-- Assert equality of two `Repr`-able values. -/
def assertEq [BEq α] [Repr α] (label : String) (actual expected : α) : TermElabM Unit := do
  unless actual == expected do
    throwError "ASSERT FAILED [{label}]: got {repr actual}, expected {repr expected}"

/-- Assert that `haystack` contains `needle` as a substring. -/
def assertContains (label : String) (haystack needle : String) : TermElabM Unit := do
  unless (haystack.splitOn needle).length > 1 do
    throwError "ASSERT FAILED [{label}]: {repr needle} not found in {repr haystack}"

/-- Assert that `haystack` does NOT contain `needle` as a substring. -/
def assertNotContains (label : String) (haystack needle : String) : TermElabM Unit := do
  if (haystack.splitOn needle).length > 1 then
    throwError "ASSERT FAILED [{label}]: {repr needle} unexpectedly found in {repr haystack}"

/-- Fetch the node at `path` or fail with `label`. -/
def nodeAt (label : String) (n : XNode) (path : List Nat) : TermElabM XNode := do
  match n.get? path with
  | some c => return c
  | none => throwError "ASSERT FAILED [{label}]: no node at path {path}"

/-- Analyze the elaboration of `stx`. -/
def analyzeT (stx : Term) (cfg : XRayConfig := {}) : TermElabM XNode := do
  analyzeExpr (← elabT stx) cfg

/-- Diff the elaborations of two terms. -/
def diffT (a b : Term) : TermElabM (Array Mismatch) := do
  diffExprs (← elabT a) (← elabT b)

end ExprXRayTests
