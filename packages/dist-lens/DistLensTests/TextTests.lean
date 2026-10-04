import DistLensTests.Helpers

/-! # Text-mode tests

Byte-exact pins of the pure ASCII reports (the same strings the
`(text := true)` command modes log — those are pinned end-to-end in
`ExtractTests`; here the renderers are tested directly on models, including
crafted invalid ones that never occur through the extractor).
-/

namespace DistLensTests

open DistLens

#guard Render.headerLine die6 = "dist: 6 outcomes over Fin 6"
-- Singular noun for one outcome.
#guard Render.headerLine
  { carrier := "ℕ", labels := #["5"], weights := #[1] }
  = "dist: 1 outcome over ℕ"

#guard Render.ratsLine #[1/6, 1/3, 1/2] = "1/6 1/3 1/2"
#guard Render.ratsLine #[] = ""

#guard Render.momentsLine? die6 = some "moments: E[X] = 5/2, Var[X] = 35/12"
-- No canonical value map ⇒ no moments line.
#guard Render.momentsLine?
  { carrier := "V", labels := #["a"], weights := #[1] } = none

#guard Render.textReport die6 =
  "dist: 6 outcomes over Fin 6\n\
   outcomes: 0 1 2 3 4 5\n\
   weights: 1/6 1/6 1/6 1/6 1/6 1/6\n\
   cdf: 1/6 1/3 1/2 2/3 5/6 1\n\
   moments: E[X] = 5/2, Var[X] = 35/12"

#guard Render.textReport coin =
  "dist: 2 outcomes over Bool\n\
   outcomes: false true\n\
   weights: 1/3 2/3\n\
   cdf: 1/3 1\n\
   moments: E[X] = 2/3, Var[X] = 2/9"

-- A broken model's report carries the warning overlay lines.
#guard Render.textReport badModel =
  "dist: 3 outcomes over Fin 3\n\
   outcomes: 0 1\n\
   weights: 1/2 -1/3 1\n\
   cdf: 1/2 1/6 7/6\n\
   moments: E[X] = 5/3, Var[X] = 8/9\n\
   warning: internal: 2 labels but 3 weights\n\
   warning: internal: weight -1/3 at outcome 1 is negative\n\
   warning: internal: total mass is 7/6, not 1"

#guard Render.filmTextReport
    ⟨#[("source", coin), ("result", { coin with weights := #[1/2, 1/2] })]⟩ =
  "== source\n\
   dist: 2 outcomes over Bool\n\
   outcomes: false true\n\
   weights: 1/3 2/3\n\
   cdf: 1/3 1\n\
   moments: E[X] = 2/3, Var[X] = 2/9\n\
   == result\n\
   dist: 2 outcomes over Bool\n\
   outcomes: false true\n\
   weights: 1/2 1/2\n\
   cdf: 1/2 1\n\
   moments: E[X] = 1/2, Var[X] = 1/4"

#guard Render.stationaryLine (.unique #[1/2, 1/2]) = "stationary: unique"
#guard Render.stationaryLine .nonUnique
  = "stationary: non-unique (reducible chain — the solution space has \
     dimension > 1; DistLens picks no representative)"
#guard Render.stationaryLine .inconsistent
  = "stationary: inconsistent (extraction bug!)"

#guard Render.chainTextReport weatherM =
  "chain: 2 states\n\
   row 0: 3/4 1/4\n\
   row 1: 1/2 1/2\n\
   stationary: unique\n\
   π: 2/3 1/3"

#guard Render.chainTextReport weatherM (weatherM.powerFrames #[1, 0] 2) =
  "chain: 2 states\n\
   row 0: 3/4 1/4\n\
   row 1: 1/2 1/2\n\
   stationary: unique\n\
   π: 2/3 1/3\n\
   step 0: 1 0\n\
   step 1: 3/4 1/4\n\
   step 2: 11/16 5/16"

-- A broken (non-stochastic) chain: the stationary system is inconsistent —
-- flagged as an extraction bug, alongside the row warnings.
#guard badChain.stationary = .inconsistent
#guard Render.chainTextReport badChain =
  "chain: 2 states\n\
   row 0: 1 1/4\n\
   row 1: -1/2 3/2\n\
   stationary: inconsistent (extraction bug!)\n\
   warning: internal: row 0 sums to 5/4, not 1\n\
   warning: internal: entry -1/2 at (1, 0) is negative"

#guard Render.warningLines #["a", "b"] = #["warning: a", "warning: b"]

end DistLensTests
