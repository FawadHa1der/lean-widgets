import HasseViewTests.Helpers
import HasseView.Demo

/-! # Property tests

The reusable invariant checkers from `Helpers` over every pure test poset,
and `#assert_poset_invariants` — the REAL extraction pipeline followed by
every invariant — over every demo type.  A bug in cover computation, rank
assignment, bounds, lattice analysis or layout fails the build here even if
no hand-written pin happens to cover it.
-/

namespace HasseViewTests

open HasseView

/-! ## Pure posets -/

#guard allInvariants (chainP 0)
#guard allInvariants (chainP 1)
#guard allInvariants (chainP 2)
#guard allInvariants (chainP 5)
#guard allInvariants (antichainP 1)
#guard allInvariants (antichainP 4)
#guard allInvariants (cubeP 1)
#guard allInvariants (cubeP 2)
#guard allInvariants (cubeP 3)
#guard allInvariants (cubeP 4)
#guard allInvariants diamondP
#guard allInvariants bowtieP
#guard allInvariants divisor12P

-- The cover-closure checker is not vacuous: it FAILS on a table whose
-- "covers" cannot regenerate the order (a non-transitive chain: 0 ≤ 1 ≤ 2
-- without 0 ≤ 2 makes 0⋖1, 1⋖2 reach 0 < 2, which the table denies).
#guard coverClosureOk notTransP == false

-- Invalid tables still satisfy the *structural* checkers that don't assume
-- validity (they must never crash or loop).
#guard notAntisymP.wellFormed && rankOk notAntisymP && layoutOk notAntisymP
#guard brokenP.wellFormed && layoutOk brokenP

/-! ## Real extractions (full pipeline + all invariants, one per line) -/

#assert_poset_invariants Bool
#assert_poset_invariants (Fin 1)
#assert_poset_invariants (Fin 5)
#assert_poset_invariants (Bool × Bool)
#assert_poset_invariants (Finset (Fin 2))
#assert_poset_invariants (Finset (Fin 3))
#assert_poset_invariants HasseView.Demo.Div12
#assert_poset_invariants HasseView.Demo.Bowtie

/-! ## Extraction agrees with the pure mirrors (byte-for-byte) -/

open Lean Elab Command in
/-- `#assert_extracts_to V p`: extraction of `V` yields exactly the
`PosetData` denoted by the pure term `p` (labels included). -/
elab "#assert_extracts_to " t:term:max p:term : command => do
  let expected ← liftTermElabM do
    let pe ← Term.elabTerm p (some (Lean.mkConst ``HasseView.PosetData))
    Term.synthesizeSyntheticMVarsNoPostponing
    unsafe Meta.evalExpr PosetData (Lean.mkConst ``HasseView.PosetData)
      (← instantiateMVars pe)
  let d ← liftTermElabM do
    let V ← Term.elabTerm t none
    Term.synthesizeSyntheticMVarsNoPostponing
    extractPosetData (← instantiateMVars V)
  unless d == expected do
    throwError "extraction mismatch:\nextracted {repr d}\nexpected {repr expected}"

-- `Fin 5` is the 5-chain with numeral labels.
#assert_extracts_to (Fin 5) (mkPoset 5 (· ≤ ·) #["0", "1", "2", "3", "4"])
-- `Finset (Fin 3)` is the bitmask cube — table AND enumeration order.
#assert_extracts_to (Finset (Fin 3))
  (mkPoset 8 (fun i j => i &&& j == i)
    #["∅", "{0}", "{1}", "{0, 1}", "{2}", "{0, 2}", "{1, 2}", "{0, 1, 2}"])
-- The bowtie demo type matches its pure mirror (labels are Fin numerals).
#assert_extracts_to HasseView.Demo.Bowtie
  (mkPoset 5 (fun a b => a == b || a == 0 || (a ≤ 2 && 3 ≤ b))
    #["0", "1", "2", "3", "4"])
-- The divisor demo matches its pure mirror (numeral labels, ascending).
#assert_extracts_to HasseView.Demo.Div12
  (mkPoset 6
    (fun i j =>
      let ds : Array Nat := #[1, 2, 3, 4, 6, 12]
      ds.getD j 1 % ds.getD i 1 == 0)
    #["1", "2", "3", "4", "6", "12"])

end HasseViewTests
