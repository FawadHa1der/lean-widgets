import SimpLensTests.Helpers

/-!
# SimpLensTests.ContractTests — React style-contract tests

The InfoView passes `Html` attributes directly as React props; `style` must
be a JSON object with camelCased keys — a CSS string crashes the panel at
runtime with React error #62, which no compile-time test can see. These run
`reactContractViolations` over the REAL top-level panel outputs the
`simp_lens` tactic produces (`renderPanel`, `renderPanelFallback`,
`renderPanelAt`), so any future string-style regression anywhere in
`SimpLens.Render` fails `lake build`/`lake test`.
-/

namespace SimpLensTests.ContractTests

open Lean SimpLensTests

/-! ## Checker sanity -/

-- a raw CSS-string style — the exact live-bug shape — IS flagged...
#guard !(reactContractViolations
    (.element "div" #[("style", Json.str "font-family:monospace;color:red")]
      #[.text "x"])).isEmpty
-- ...including when nested below clean elements...
#guard (reactContractViolations
    (.element "div" #[]
      #[.element "span" #[("style", Json.str "color:red")] #[]])).length == 1
-- ...a `class` attribute is flagged (React requires `className`)...
#guard !(reactContractViolations (.element "span" #[("class", Json.str "pill")] #[])).isEmpty
-- ...and object styles / style-free trees are clean.
#guard reactContractViolations
    (.element "div" #[("style", Json.mkObj [("fontFamily", "monospace")])] #[.text "x"]) == []
#guard reactContractViolations (.element "ul" #[] #[.element "li" #[] #[.text "a"]]) == []

/-! ## Real panel outputs -/

-- hypothesis binders are referenced by the location clauses, not the body
-- (same convention as LocationTests)
set_option linter.unusedVariables false

-- multi-frame filmstrip with badges, arrows and exclusion-preview rows;
-- also checks the degraded fallback panel for the same run
#lens_react_contract ∀ n : Nat, n + 0 + 0 = n

-- closed-goal panel (✓ outcome span) with a hypothesis lemma badge
#lens_react_contract ∀ (n : Nat) (h : n = 5), n + 0 = 5 hyps [h]

-- empty filmstrip ("no steps" note path)
#lens_react_contract (True : Prop)

-- diagnostics section enabled (tried/used rows)
set_option diagnostics true in
#lens_react_contract ∀ n : Nat, n + 0 + 0 = n

-- multi-location panel: per-location sections at a hypothesis and the target
#lens_at_react_contract ∀ (n : Nat) (h : n + 0 = 5), n = 5 ∧ True at h ⊢

-- wildcard locations
#lens_at_react_contract ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at *

end SimpLensTests.ContractTests
