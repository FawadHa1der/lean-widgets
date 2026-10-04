import DistLensTests.Helpers

/-! # Invariant self-check tests

Crafted bad models make every checker fire with its exact message — these
overlays are DistLens's extractor-bug alarm, so each specific violation
line is pinned.
-/

namespace DistLensTests

open DistLens

-- Every violation of the deliberately broken model, in order.
#guard badModel.invariantViolations =
  #["internal: 2 labels but 3 weights",
    "internal: weight -1/3 at outcome 1 is negative",
    "internal: total mass is 7/6, not 1"]

-- Value-array length mismatch.
#guard (DistModel.invariantViolations
    { carrier := "Fin 2", labels := #["0", "1"], weights := #[1/2, 1/2]
      values? := some #[0] })
  = #["internal: 1 values but 2 weights"]

-- Mass deficit (not just excess) is flagged with the actual total.
#guard (DistModel.invariantViolations
    { carrier := "Fin 2", labels := #["0", "1"], weights := #[1/3, 1/3] })
  = #["internal: total mass is 2/3, not 1"]

-- The empty model: mass 0 ≠ 1.
#guard (DistModel.invariantViolations
    { carrier := "Fin 0", labels := #[], weights := #[] })
  = #["internal: total mass is 0, not 1"]

-- Healthy models are silent (extractor outputs must always look like this).
#guard die6.invariantViolations = #[]
#guard coin.invariantViolations = #[]
#guard weatherM.invariantViolations = #[]

-- Chain checkers (badChain also pinned in ChainMathTests): a chain whose
-- row is a valid distribution but has the wrong length is flagged twice.
#guard (ChainModel.invariantViolations
    { n := 2, matrix := #[#[1/2, 1/2], #[1]] })
  = #["internal: row 1 has 1 entries, expected 2"]

-- The negative-entry message includes the exact position.
#guard (ChainModel.invariantViolations
    { n := 1, matrix := #[#[-1]] })
  = #["internal: entry -1 at (0, 0) is negative",
      "internal: row 0 sums to -1, not 1"]

end DistLensTests
