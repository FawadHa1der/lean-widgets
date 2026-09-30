import DistLensTests.Helpers
import DistLens

/-! # Suggestion tests

Pins the suggestion strings the panels offer (pure generators) and then
**compiles the exact suggested text** for def-wrapped demo distributions —
including the `unfold` prefix computed by `collectUnfoldNames` — so a
clicked insertion is guaranteed to elaborate.
-/

namespace DistLensTests

open PMF DistLens DistLens.Demo
open scoped ENNReal

set_option linter.deprecated false

/-! ## Pure generators -/

def coinX : XDist :=
  { carrier := .bool, keys := #[0, 1], labels := #["false", "true"]
    weights := #[1/3, 2/3] }

#guard weightSuggestions "biasedCoin" "pmf_num" coinX =
  #["example : biasedCoin false = 1/3 := by pmf_num",
    "example : biasedCoin true = 2/3 := by pmf_num"]

-- Zero-weight outcomes get no suggestion.
#guard weightSuggestions "p" "pmf_num"
    { carrier := .fin 3, keys := #[0, 1, 2], labels := #["0", "1", "2"]
      weights := #[0, 1, 0] }
  = #["example : p 1 = 1 := by pmf_num"]

-- The unfold prefix is threaded through verbatim.
#guard weightSuggestions "die" "unfold die; pmf_num"
    { carrier := .fin 2, keys := #[0, 1], labels := #["0", "1"]
      weights := #[1/2, 1/2] }
  = #["example : die 0 = 1/2 := by unfold die; pmf_num",
      "example : die 1 = 1/2 := by unfold die; pmf_num"]

-- Opaque carriers are display-only: NO suggestion rows.  Their labels are
-- `Repr` display strings (not verified source terms) and `pmf_num` cannot
-- reduce `Fintype.card` of an arbitrary carrier, so an inserted example
-- would not compile (the ClickE2E suite pins the actual compile failure).
#guard weightSuggestions "(PMF.uniformOfFintype Ordering)" "pmf_num"
    { carrier := .opaqueTy "Ordering", keys := #[0, 1, 2]
      labels := #["Ordering.lt", "Ordering.eq", "Ordering.gt"]
      weights := #[1/3, 1/3, 1/3] }
  = #[]

-- The cap: at most `maxSuggestions` rows.
#guard (weightSuggestions "u" "pmf_num"
    { carrier := .fin 64
      keys := Array.range 64
      labels := (Array.range 64).map toString
      weights := (Array.range 64).map fun _ => 1/64 }).size = maxSuggestions

#guard stationaryPmfText #[2/3, 1/3] =
  "PMF.ofFintype ![2/3, 1/3] (by simp [Fin.sum_univ_succ]; ennreal_num)"

#guard stationarySuggestions "weather" "unfold weather; pmf_num" #[2/3, 1/3] =
  #["example : ((PMF.ofFintype ![2/3, 1/3] (by simp [Fin.sum_univ_succ]; \
     ennreal_num)).bind weather) 0 = 2/3 := by unfold weather; pmf_num",
    "example : ((PMF.ofFintype ![2/3, 1/3] (by simp [Fin.sum_univ_succ]; \
     ennreal_num)).bind weather) 1 = 1/3 := by unfold weather; pmf_num"]

#guard unfoldTactic #[] = "pmf_num"
#guard unfoldTactic #[`twoDice, `die] = "unfold twoDice die; pmf_num"

/-! ## termText parenthesization: `isParenWrapped`

A term the user already parenthesized must not be wrapped again; anything
that is not (at the character level) a single outer `(…)` group must be.
Misjudging is only ever allowed toward wrapping (redundant but safe). -/

#guard isParenWrapped "(uniformOfFintype (Fin 6))"
#guard isParenWrapped "((a))"
#guard isParenWrapped "(a (b c))"
#guard !isParenWrapped "a b"
#guard !isParenWrapped "(a) (b)"
#guard !isParenWrapped "(a)(b)"
#guard !isParenWrapped "(a"
#guard !isParenWrapped "a)"
#guard !isParenWrapped ""
#guard !isParenWrapped "()x"
-- Parens hidden in string literals bias toward `false` — the safe side.
#guard !isParenWrapped "(f \")\") (g)"

/-! ## collectUnfoldNames end-to-end -/

open Lean Elab in
/-- Test-only: log the unfold names collected for a term. -/
elab "#unfold_names " t:term : command => Command.runTermElabM fun _ => do
  let e ← Term.elabTerm t none
  Term.synthesizeSyntheticMVarsNoPostponing
  logInfo (toString (← collectUnfoldNames (← instantiateMVars e)))

/-- info: #[DistLens.Demo.die] -/
#guard_msgs in
#unfold_names die

/-- info: #[DistLens.Demo.twoDice, DistLens.Demo.die] -/
#guard_msgs in
#unfold_names twoDice

/-- info: #[DistLens.Demo.weather] -/
#guard_msgs in
#unfold_names weather

-- Inline constructor terms need no unfolds.
/-- info: #[] -/
#guard_msgs in
#unfold_names (uniformOfFintype (Fin 6))

/-! ## The suggested text compiles, verbatim

These are byte-for-byte the strings the `#dist die` / `#dist twoDice` /
`#chain weather` panels produce (fully qualified names, `unfold` prefix
included), pasted and compiled. -/

example : DistLens.Demo.die 0 = 1/6 := by unfold DistLens.Demo.die; pmf_num

example : DistLens.Demo.twoDice 5 = 1/6 := by
  unfold DistLens.Demo.twoDice DistLens.Demo.die; pmf_num

example : DistLens.Demo.biasedCoin false = 1/3 := by
  unfold DistLens.Demo.biasedCoin; pmf_num

example : DistLens.Demo.loadedDie 0 = 1/2 := by
  unfold DistLens.Demo.loadedDie; pmf_num

example : ((PMF.ofFintype ![2/3, 1/3]
    (by simp [Fin.sum_univ_succ]; ennreal_num)).bind DistLens.Demo.weather) 0
    = 2/3 := by
  unfold DistLens.Demo.weather; pmf_num

end DistLensTests
