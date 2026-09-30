import HasseViewTests.Helpers

/-! # Model tests

Hand-computed pins over the pure test posets: covers (counts AND specific
pairs), minimal/maximal/bot/top, atoms/coatoms, height, ranks, layers,
lattice verdicts with pinned join/meet spot-checks and the EXACT non-lattice
witness pair, upsets/downsets, and the validity checkers on crafted broken
tables.
-/

namespace HasseViewTests

open HasseView PosetData

/-! ## Covers — the mathematical heart, tested hard -/

-- The chain on 5 elements has exactly the 4 consecutive covers.
#guard (chainP 5).coverPairs == #[(0, 1), (1, 2), (2, 3), (3, 4)]
#guard (chainP 5).coverCount == 4
-- Non-consecutive comparabilities are NOT covers.
#guard (chainP 5).coversB 0 2 == false
#guard (chainP 5).coversB 0 4 == false
#guard (chainP 5).ltB 0 2 == true
-- The antichain has no covers at all.
#guard (antichainP 4).coverPairs == #[]
-- The 3-cube has exactly 12 cover edges: single-bit insertions.
#guard (cubeP 3).coverCount == 12
#guard (cubeP 3).coverPairs ==
  #[(0, 1), (0, 2), (0, 4), (1, 3), (1, 5), (2, 3), (2, 6),
    (3, 7), (4, 5), (4, 6), (5, 7), (6, 7)]
-- ∅ ⋖ {0} but not ∅ ⋖ {0, 1} (the singleton is strictly between).
#guard (cubeP 3).coversB 0 3 == false
#guard (cubeP 3).ltB 0 3 == true
-- Diamond: bottom covers the two middles, both covered by the top.
#guard diamondP.coverPairs == #[(0, 1), (0, 2), (1, 3), (2, 3)]
-- Bowtie: 6 covers, no edge between the incomparable pairs.
#guard bowtieP.coverPairs == #[(0, 1), (0, 2), (1, 3), (1, 4), (2, 3), (2, 4)]
#guard bowtieP.ltB 1 2 == false && bowtieP.ltB 2 1 == false
#guard bowtieP.ltB 3 4 == false && bowtieP.ltB 4 3 == false
-- Divisor lattice of 12: the 7 divisibility covers (1⋖2, 1⋖3, 2⋖4, 2⋖6,
-- 3⋖6, 4⋖12, 6⋖12) — note 1⋖4 fails (2 in between) and 2⋖12 fails.
#guard divisor12P.coverPairs ==
  #[(0, 1), (0, 2), (1, 3), (1, 4), (2, 4), (3, 5), (4, 5)]
#guard divisor12P.coversB 0 3 == false  -- 1 ⋖ 4 fails: 2 lies between
#guard divisor12P.coversB 1 5 == false  -- 2 ⋖ 12 fails: 4 and 6 between
#guard divisor12P.ltB 1 2 == false      -- 2 ∤ 3: incomparable
#guard divisor12P.ltB 2 3 == false && divisor12P.ltB 3 2 == false -- 3 vs 4

/-! ## Minimal / maximal / bot / top -/

#guard (chainP 5).minimals == #[0] && (chainP 5).maximals == #[4]
#guard (chainP 5).bot? == some 0 && (chainP 5).top? == some 4
#guard (antichainP 3).minimals == #[0, 1, 2]
#guard (antichainP 3).maximals == #[0, 1, 2]
-- No bot/top in a nontrivial antichain (no unique extreme).
#guard (antichainP 3).bot? == none && (antichainP 3).top? == none
-- The 1-element antichain: its point is everything at once.
#guard (antichainP 1).bot? == some 0 && (antichainP 1).top? == some 0
#guard (cubeP 3).bot? == some 0 && (cubeP 3).top? == some 7
#guard bowtieP.bot? == some 0 && bowtieP.top? == none
#guard bowtieP.minimals == #[0] && bowtieP.maximals == #[3, 4]
#guard divisor12P.bot? == some 0 && divisor12P.top? == some 5
-- Empty poset: no extremes.
#guard (chainP 0).bot? == none && (chainP 0).top? == none

/-! ## Atoms / coatoms -/

-- Cube: atoms are the singletons (indices 1, 2, 4), coatoms the 2-sets.
#guard (cubeP 3).atoms == #[1, 2, 4]
#guard (cubeP 3).coatoms == #[3, 5, 6]
#guard (chainP 5).atoms == #[1] && (chainP 5).coatoms == #[3]
-- 2-chain: the single cover edge makes 1 an atom AND 0 a coatom.
#guard (chainP 2).atoms == #[1] && (chainP 2).coatoms == #[0]
-- 1-element poset: bot exists but covers nothing.
#guard (chainP 1).atoms == #[] && (chainP 1).coatoms == #[]
-- Bowtie: atoms below the missing top; no coatoms without a top.
#guard bowtieP.atoms == #[1, 2] && bowtieP.coatoms == #[]
-- Divisors of 12: atoms are the primes 2, 3; coatoms are 4, 6.
#guard divisor12P.atoms == #[1, 2]
#guard divisor12P.coatoms == #[3, 4]

/-! ## Height, ranks, layers -/

#guard (chainP 5).height == 4 && (chainP 5).ranks == #[0, 1, 2, 3, 4]
#guard (antichainP 4).height == 0 && (antichainP 4).ranks == #[0, 0, 0, 0]
-- Cube ranks = popcount (number of elements in the subset).
#guard (cubeP 3).ranks == #[0, 1, 1, 2, 1, 2, 2, 3]
#guard (cubeP 3).height == 3
#guard bowtieP.ranks == #[0, 1, 1, 2, 2] && bowtieP.height == 2
#guard divisor12P.ranks == #[0, 1, 1, 2, 2, 3] && divisor12P.height == 3
#guard (chainP 0).height == 0
-- Layers list ascending indices per rank.
#guard (cubeP 3).layer 0 == #[0]
#guard (cubeP 3).layer 1 == #[1, 2, 4]
#guard (cubeP 3).layer 2 == #[3, 5, 6]
#guard (cubeP 3).layer 3 == #[7]
#guard (cubeP 3).maxLayerSize == 3
#guard (chainP 5).maxLayerSize == 1
#guard (antichainP 4).maxLayerSize == 4
#guard bowtieP.maxLayerSize == 2

/-! ## Lattice analysis -/

-- The cube is a lattice; joins are bit-or, meets bit-and — spot-checked.
#guard (cubeP 3).latticeVerdict == .lattice
#guard (cubeP 3).joinOf? 1 2 == some 3    -- {0} ∨ {1} = {0, 1}
#guard (cubeP 3).joinOf? 1 6 == some 7    -- {0} ∨ {1, 2} = ⊤
#guard (cubeP 3).meetOf? 3 5 == some 1    -- {0, 1} ∧ {0, 2} = {0}
#guard (cubeP 3).meetOf? 1 2 == some 0    -- {0} ∧ {1} = ∅
#guard (cubeP 3).joinOf? 5 5 == some 5    -- idempotence
#guard (chainP 5).latticeVerdict == .lattice
#guard (chainP 5).joinOf? 1 3 == some 3 && (chainP 5).meetOf? 1 3 == some 1
-- Divisors of 12: join = lcm, meet = gcd — spot-checked on indices.
#guard divisor12P.latticeVerdict == .lattice
#guard divisor12P.joinOf? 3 4 == some 5   -- lcm(4, 6) = 12
#guard divisor12P.meetOf? 3 4 == some 1   -- gcd(4, 6) = 2
#guard divisor12P.joinOf? 1 2 == some 4   -- lcm(2, 3) = 6
-- Bowtie: NOT a lattice, with the EXACT witness pair (1, 2) pinned.
#guard bowtieP.latticeVerdict == .noJoin 1 2
#guard bowtieP.isLattice == false
#guard bowtieP.joinOf? 1 2 == none
#guard bowtieP.upperBounds 1 2 == #[3, 4]  -- two minimal upper bounds
#guard bowtieP.meetOf? 3 4 == none         -- the dual failure exists too…
-- …but the scan hits the join failure of (1, 2) first.
-- Antichain of 2: no join either — witness is the first pair.
#guard (antichainP 2).latticeVerdict == .noJoin 0 1
-- Trivial cases are lattices.
#guard (chainP 0).latticeVerdict == .lattice
#guard (chainP 1).latticeVerdict == .lattice

/-! ## Upsets / downsets -/

#guard (cubeP 3).upset 1 == #[1, 3, 5, 7]     -- supersets of {0}
#guard (cubeP 3).downset 1 == #[0, 1]         -- subsets of {0}
#guard (cubeP 3).upset 0 == #[0, 1, 2, 3, 4, 5, 6, 7]
#guard (cubeP 3).downset 7 == #[0, 1, 2, 3, 4, 5, 6, 7]
#guard (chainP 5).upset 2 == #[2, 3, 4] && (chainP 5).downset 2 == #[0, 1, 2]
#guard bowtieP.upset 1 == #[1, 3, 4]
#guard bowtieP.downset 3 == #[0, 1, 2, 3]

/-! ## Validity checkers on crafted broken tables (≥ 4 violations) -/

#guard notReflP.reflexivityViolations == #[0]
#guard notReflP.isValidPoset == false
#guard notAntisymP.antisymmetryViolations == #[(0, 1)]
#guard notAntisymP.isValidPoset == false
#guard notTransP.transitivityViolations == #[(0, 1, 2)]
#guard notTransP.isValidPoset == false
-- The everything-wrong table: all three checkers fire with exact evidence.
#guard brokenP.reflexivityViolations == #[2]
#guard brokenP.antisymmetryViolations == #[(0, 1)]
#guard brokenP.transitivityViolations == #[(0, 1, 2)]
#guard brokenP.isValidPoset == false
-- The strict order quotients the 2-cycle away instead of looping.
#guard notAntisymP.ltB 0 1 == false && notAntisymP.ltB 1 0 == false
#guard notAntisymP.coverPairs == #[]
-- All real test posets ARE valid.
#guard (chainP 5).isValidPoset && (antichainP 4).isValidPoset
#guard (cubeP 3).isValidPoset && diamondP.isValidPoset
#guard bowtieP.isValidPoset && divisor12P.isValidPoset

/-! ## Structural sanity -/

#guard (chainP 5).wellFormed && (cubeP 3).wellFormed && bowtieP.wellFormed
#guard (chainP 0).wellFormed && (chainP 0).n == 0
-- `ofTable` normalizes ragged input to n × n.
#guard (PosetData.ofTable 3 #[#[true], #[]] #["a"]).wellFormed
#guard (PosetData.ofTable 3 #[#[true], #[]] #["a"]).labels == #["a", "1", "2"]
#guard (PosetData.ofTable 3 #[#[true], #[]]).leB 0 0 == true
#guard (PosetData.ofTable 3 #[#[true], #[]]).leB 1 1 == false
-- Out-of-range queries are quietly false / defaults.
#guard (chainP 3).leB 5 0 == false && (chainP 3).leB 0 5 == false
#guard (chainP 3).label 7 == "7"
#guard (chainP 3).rank 9 == 0

end HasseViewTests
