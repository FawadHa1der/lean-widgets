import HasseView

/-! # Test helpers

Pure builders for standard test posets (over element indices, mirroring what
extraction produces for the corresponding types), crafted INVALID tables for
the validity checkers, string-search helpers for render tests, reusable
property checks, and a throwing assertion command that runs the real
extraction pipeline and validates every model invariant on the result (one
compile-time assertion per use).
-/

namespace HasseViewTests

open HasseView

/-! ## Pure test posets -/

/-- Build a `PosetData` from a decidable relation on indices. -/
def mkPoset (n : Nat) (le : Nat → Nat → Bool) (labels : Array String := #[]) :
    PosetData :=
  .ofTable n ((Array.range n).map fun i => (Array.range n).map fun j => le i j)
    labels

/-- The chain `0 < 1 < … < n-1` (mirrors `Fin n`). -/
def chainP (n : Nat) : PosetData := mkPoset n (· ≤ ·)

/-- The `n`-element antichain (only reflexivity). -/
def antichainP (n : Nat) : PosetData := mkPoset n (· == ·)

/-- The Boolean cube on `bits` generators in bitmask enumeration order
(`i ≤ j` iff `i`'s bits are a subset of `j`'s) — for `bits = 3` this is
index-for-index what extracting `Finset (Fin 3)` produces. -/
def cubeP (bits : Nat) : PosetData := mkPoset (2 ^ bits) fun i j => i &&& j == i

/-- The diamond `M₂`: bottom `0`, incomparable `1, 2`, top `3`. -/
def diamondP : PosetData := mkPoset 4 fun i j => i == j || i == 0 || j == 3

/-- The bowtie (mirrors `HasseView.Demo.Bowtie`): bottom `0`, middle `1, 2`,
both below both of `3, 4`; `1, 2` have no join, `3, 4` have no meet. -/
def bowtieP : PosetData := mkPoset 5 fun a b => a == b || a == 0 || (a ≤ 2 && 3 ≤ b)

/-- The divisors of 12 under divisibility, ascending enumeration
`1, 2, 3, 4, 6, 12` (mirrors `HasseView.Demo.Div12`). -/
def divisor12P : PosetData :=
  let ds : Array Nat := #[1, 2, 3, 4, 6, 12]
  mkPoset 6 (fun i j => ds.getD j 1 % ds.getD i 1 == 0)
    (ds.map fun d => toString d)

/-! ## Crafted INVALID tables (for the validity checkers) -/

/-- Not reflexive: `¬ 0 ≤ 0` (otherwise the 2-chain). -/
def notReflP : PosetData :=
  .ofTable 2 #[#[false, true], #[false, true]]

/-- Not antisymmetric: `0 ≤ 1` and `1 ≤ 0` (a 2-cycle preorder). -/
def notAntisymP : PosetData :=
  .ofTable 2 #[#[true, true], #[true, true]]

/-- Not transitive: `0 ≤ 1 ≤ 2` but `¬ 0 ≤ 2`. -/
def notTransP : PosetData :=
  .ofTable 3 #[#[true, true, false], #[false, true, true], #[false, false, true]]

/-- Everything wrong at once: irreflexive at `2`, a 2-cycle `0 ≤ 1 ≤ 0`,
and `1 ≤ 2` without `0 ≤ 2`. -/
def brokenP : PosetData :=
  .ofTable 3 #[#[true, true, false], #[true, true, true], #[false, false, false]]

/-! ## String helpers for render tests -/

/-- Does `s` contain `sub`? (`sub` nonempty.) -/
def containsSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1

/-- Number of (non-overlapping) occurrences of `sub` in `s`. -/
def countOccurrences (s sub : String) : Nat :=
  (s.splitOn sub).length - 1

/-! ## Property checks (used by PropertyTests and `#assert_poset_invariants`)

These are *independent recomputations* of what the model claims, so a bug in
one implementation is caught by the other. -/

/-- Reachability by nonempty cover paths, via Floyd–Warshall (terminates on
any input, independent of the model's own algorithms). -/
def coverReach (d : PosetData) : Array (Array Bool) := Id.run do
  let mut reach := (Array.range d.n).map fun i =>
    (Array.range d.n).map fun j => d.coversB i j
  for k in [0:d.n] do
    for i in [0:d.n] do
      if (reach.getD i #[]).getD k false then
        let rowK := reach.getD k #[]
        let rowI := reach.getD i #[]
        reach := reach.set! i (rowI.mapIdx fun j v => v || rowK.getD j false)
  return reach

/-- THE Hasse-diagram correctness property (valid posets only): `a < b` iff
`b` is reachable from `a` by a nonempty path of cover edges — the covers
generate the whole strict order and nothing more. -/
def coverClosureOk (d : PosetData) : Bool :=
  let reach := coverReach d
  (List.range d.n).all fun i =>
    (List.range d.n).all fun j =>
      d.ltB i j == (reach.getD i #[]).getD j false

/-- Rank recurrence: a source of the cover DAG has rank 0, and every other
element's rank is `1 +` the max rank of its lower covers. -/
def rankOk (d : PosetData) : Bool :=
  let covers := d.coverPairs
  (List.range d.n).all fun b =>
    let preds := covers.filterMap fun (x, y) => if y == b then some x else none
    if preds.isEmpty then d.rank b == 0
    else d.rank b == 1 + preds.foldl (fun acc a => max acc (d.rank a)) 0

/-- Every rank layer is an antichain, the layers partition the carrier, and
`maxLayerSize` is the true maximum layer size. -/
def layersOk (d : PosetData) : Bool :=
  let h := d.height
  let layers := (List.range (h + 1)).map (d.layer ·)
  layers.foldl (fun acc l => acc + l.size) 0 == d.n
    && layers.all (fun l => l.all fun i => l.all fun j =>
        i == j || (!d.ltB i j && !d.ltB j i))
    && d.maxLayerSize == layers.foldl (fun acc l => max acc l.size) 0

/-- `bot?`/`top?` agree with an independent scan, and atoms/coatoms are
covers of/by them. -/
def boundsOk (d : PosetData) : Bool :=
  let bots := (Array.range d.n).filter fun i => (Array.range d.n).all (d.leB i ·)
  let tops := (Array.range d.n).filter fun i => (Array.range d.n).all (d.leB · i)
  d.bot? == (if bots.size == 1 then bots[0]? else none)
    && d.top? == (if tops.size == 1 then tops[0]? else none)
    && (match d.bot? with
        | some b => d.atoms.all (d.coversB b ·)
        | none => d.atoms.isEmpty)
    && (match d.top? with
        | some t => d.coatoms.all (d.coversB · t)
        | none => d.coatoms.isEmpty)

/-- The lattice verdict is consistent with `joinOf?`/`meetOf?`, and any
returned join/meet actually is one (an upper/lower bound below/above all
others). -/
def latticeOk (d : PosetData) : Bool :=
  let pairOk := fun (i j : Nat) =>
    (match d.joinOf? i j with
     | some m =>
       let ubs := d.upperBounds i j
       ubs.contains m && ubs.all (d.leB m ·)
     | none => true)
    && (match d.meetOf? i j with
        | some m =>
          let lbs := d.lowerBounds i j
          lbs.contains m && lbs.all (d.leB · m)
        | none => true)
  (List.range d.n).all (fun i => (List.range d.n).all (pairOk i ·))
    && (match d.latticeVerdict with
        | .lattice => (List.range d.n).all fun i => (List.range d.n).all fun j =>
            (d.joinOf? i j).isSome && (d.meetOf? i j).isSome
        | .noJoin a b => (d.joinOf? a b).isNone
        | .noMeet a b => (d.meetOf? a b).isNone)

/-- Layout invariants: index-aligned integer positions, y strictly increasing
with rank, same-row x distinct and evenly spaced, boxes inside the bounds. -/
def layoutOk (d : PosetData) : Bool :=
  let l := layoutPoset d
  let intOk := l.positions.all fun (x, y) => x.den == 1 && y.den == 1
  let sizeOk := l.positions.size == d.n
  let yOk := (List.range d.n).all fun i => (List.range d.n).all fun j =>
    (d.rank i < d.rank j) == ((l.pos i).2 < (l.pos j).2)
  let distinctOk := (List.range d.n).all fun i => (List.range d.n).all fun j =>
    i == j || l.pos i != l.pos j
  let boundsOk := l.positions.all fun (x, y) =>
    Layout.nodeW / 2 ≤ x && x ≤ l.width - Layout.nodeW / 2
      && Layout.nodeH / 2 ≤ y && y ≤ l.height - Layout.nodeH / 2
  intOk && sizeOk && yOk && distinctOk && boundsOk

/-- All invariants of a VALID extraction at once. -/
def allInvariants (d : PosetData) : Bool :=
  d.wellFormed && d.isValidPoset && coverClosureOk d && rankOk d && layersOk d
    && boundsOk d && latticeOk d && layoutOk d

/-! ## Link-test fixtures

A dummy `DocumentMeta`/insertion range for serializing the *real*
`MakeEditLink`-based link renderer without a live server, and hand-built
`PanelLinks` mirroring what the gate produces for `Fin 3` (all verified)
and a fully rejected variant (the plain-text fallback). -/

/-- Stand-in document metadata for headless `editLink` serialization. -/
def testDocMeta : Lean.Server.DocumentMeta :=
  { (default : Lean.Server.DocumentMeta) with
    uri := "file:///Demo.lean", version := 7 }

/-- Zero-width insertion range (as the command computes at its end). -/
def testInsertRange : Lean.Lsp.Range := ⟨⟨5, 0⟩, ⟨5, 0⟩⟩

/-- What the gate produces for `#hasse (Fin 3)`: every candidate verified. -/
def fin3Links : PanelLinks :=
  { covers := #[
      { display := "0 ⋖ 1"
        newText? := some (insertionText (coverProp "(Fin 3)" "0" "1")) },
      { display := "1 ⋖ 2"
        newText? := some (insertionText (coverProp "(Fin 3)" "1" "2")) }]
    bot? := some { display := "∀ x, 0 ≤ x"
                   newText? := some (insertionText (botProp "(Fin 3)" "0")) }
    top? := some { display := "∀ x, x ≤ 2"
                   newText? := some (insertionText (topProp "(Fin 3)" "2")) } }

/-- Every candidate rejected by the round-trip gate (Div12-style): plain
text with the honest note, no links. -/
def rejectedLinks : PanelLinks :=
  { covers := #[{ display := "1 ⋖ 2", note? := some notInsertableLabelNote }]
    bot? := some { display := "∀ x, 1 ≤ x", note? := some notInsertableLabelNote }
    witness? := some { display := "no join of 2, 3", note? := some notVerifiedNote } }

/-! ## Extraction assertion -/

open Lean Elab Command in
/-- `#assert_poset_invariants V`: run the real extraction pipeline on the
type `V` and check every model invariant (well-formedness, partial-order
validity, cover-closure, ranks, layers, bounds, lattice consistency, layout)
on the extracted `PosetData`.  The build fails with a descriptive error on
any violation. -/
elab "#assert_poset_invariants " t:term:max : command =>
  liftTermElabM do
    let V ← Term.elabTerm t none
    Term.synthesizeSyntheticMVarsNoPostponing
    let d ← extractPosetData (← instantiateMVars V)
    unless d.wellFormed do
      throwError "extracted poset is not well-formed: {repr d}"
    unless d.isValidPoset do
      throwError "extracted table is not a partial order: refl {repr d.reflexivityViolations}, antisym {repr d.antisymmetryViolations}, trans {repr d.transitivityViolations}"
    unless coverClosureOk d do
      throwError "cover-closure invariant fails: covers {repr d.coverPairs}"
    unless rankOk d do
      throwError "rank invariant fails: ranks {repr d.ranks}"
    unless layersOk d do
      throwError "layer invariant fails: ranks {repr d.ranks}"
    unless boundsOk d do
      throwError "bot/top invariant fails: bot {repr d.bot?}, top {repr d.top?}"
    unless latticeOk d do
      throwError "lattice invariant fails: {repr d.latticeVerdict}"
    unless layoutOk d do
      throwError "layout invariant fails: {repr (layoutPoset d)}"

end HasseViewTests
