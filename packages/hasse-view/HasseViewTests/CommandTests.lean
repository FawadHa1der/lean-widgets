import HasseViewTests.Helpers
import HasseView.Demo

/-! # `#hasse` command tests

Message-exact `#guard_msgs` pins of the deterministic `(text := true)` mode —
extraction through real Mathlib order/`Fintype` instances — plus every
user-facing error message.  The cover counts in each pin are hand-verified:
chain `Fin 5`: 4 covers; the 3-cube `Finset (Fin 3)`: 12; `Bool × Bool`: 4;
divisors of 12: 7; the bowtie: 6.
-/

namespace HasseViewTests

open HasseView.Demo

/-! ## Concrete orders -/

/--
info: poset: 5 elements, 4 cover edges
rank 4: 4
rank 3: 3
rank 2: 2
rank 1: 1
rank 0: 0
⊥ = 0, ⊤ = 4
atoms: 1
coatoms: 3
lattice ✓
height: 4 (longest chain: 5 elements)
antichain width ≥ 1 (largest rank layer; exact width not computed)
-/
#guard_msgs in
#hasse (text := true) (Fin 5)

/--
info: poset: 2 elements, 1 cover edge
rank 1: true
rank 0: false
⊥ = false, ⊤ = true
atoms: true
coatoms: false
lattice ✓
height: 1 (longest chain: 2 elements)
antichain width ≥ 1 (largest rank layer; exact width not computed)
-/
#guard_msgs in
#hasse (text := true) Bool

/--
info: poset: 4 elements, 4 cover edges
rank 2: (true, true)
rank 1: (true, false), (false, true)
rank 0: (false, false)
⊥ = (false, false), ⊤ = (true, true)
atoms: (true, false), (false, true)
coatoms: (true, false), (false, true)
lattice ✓
height: 2 (longest chain: 3 elements)
antichain width ≥ 2 (largest rank layer; exact width not computed)
-/
#guard_msgs in
#hasse (text := true) (Bool × Bool)

-- THE showcase: the powerset cube (8 elements, 12 covers, hand-verified:
-- one cover per single-element insertion, 8·3/2 = 12).
/--
info: poset: 8 elements, 12 cover edges
rank 3: {0, 1, 2}
rank 2: {0, 1}, {0, 2}, {1, 2}
rank 1: {0}, {1}, {2}
rank 0: ∅
⊥ = ∅, ⊤ = {0, 1, 2}
atoms: {0}, {1}, {2}
coatoms: {0, 1}, {0, 2}, {1, 2}
lattice ✓
height: 3 (longest chain: 4 elements)
antichain width ≥ 3 (largest rank layer; exact width not computed)
-/
#guard_msgs in
#hasse (text := true) (Finset (Fin 3))

-- Divisors of 12 (7 covers: 1⋖2, 1⋖3, 2⋖4, 2⋖6, 3⋖6, 4⋖12, 6⋖12).
/--
info: poset: 6 elements, 7 cover edges
rank 3: 12
rank 2: 4, 6
rank 1: 2, 3
rank 0: 1
⊥ = 1, ⊤ = 12
atoms: 2, 3
coatoms: 4, 6
lattice ✓
height: 3 (longest chain: 4 elements)
antichain width ≥ 2 (largest rank layer; exact width not computed)
-/
#guard_msgs in
#hasse (text := true) Div12

-- The bowtie: NOT a lattice, concrete witness pair in the caption; no top,
-- so no coatoms line.
/--
info: poset: 5 elements, 6 cover edges
rank 2: 3, 4
rank 1: 1, 2
rank 0: 0
⊥ = 0, ⊤ = (none)
atoms: 1, 2
not a lattice: 1, 2 have no join
height: 2 (longest chain: 3 elements)
antichain width ≥ 2 (largest rank layer; exact width not computed)
-/
#guard_msgs in
#hasse (text := true) Bowtie

/-! ## Overlays (and clause order) -/

/--
info: poset: 4 elements, 4 cover edges
rank 2: {0, 1}
rank 1: {0}, {1}
rank 0: ∅
⊥ = ∅, ⊤ = {0, 1}
atoms: {0}, {1}
coatoms: {0}, {1}
lattice ✓
height: 2 (longest chain: 3 elements)
antichain width ≥ 2 (largest rank layer; exact width not computed)
upset of {0}: {0}, {0, 1}
downset of {0}: ∅, {0}
-/
#guard_msgs in
#hasse (text := true) (Finset (Fin 2)) updown 1

/--
info: poset: 3 elements, 2 cover edges
rank 2: 2
rank 1: 1
rank 0: 0
⊥ = 0, ⊤ = 2
atoms: 1
coatoms: 1
lattice ✓
height: 2 (longest chain: 3 elements)
antichain width ≥ 1 (largest rank layer; exact width not computed)
highlight: 0, 2
-/
#guard_msgs in
#hasse (text := true) (Fin 3) highlight [0, 2]

-- Both clauses, in either order — identical output.
/--
info: poset: 3 elements, 2 cover edges
rank 2: 2
rank 1: 1
rank 0: 0
⊥ = 0, ⊤ = 2
atoms: 1
coatoms: 1
lattice ✓
height: 2 (longest chain: 3 elements)
antichain width ≥ 1 (largest rank layer; exact width not computed)
highlight: 0
upset of 1: 1, 2
downset of 1: 0, 1
-/
#guard_msgs in
#hasse (text := true) (Fin 3) highlight [0] updown 1

/--
info: poset: 3 elements, 2 cover edges
rank 2: 2
rank 1: 1
rank 0: 0
⊥ = 0, ⊤ = 2
atoms: 1
coatoms: 1
lattice ✓
height: 2 (longest chain: 3 elements)
antichain width ≥ 1 (largest rank layer; exact width not computed)
highlight: 0
upset of 1: 1, 2
downset of 1: 0, 1
-/
#guard_msgs in
#hasse (text := true) (Fin 3) updown 1 highlight [0]

-- Panel mode elaborates cleanly (no messages; the widget is attached).
#guard_msgs in
#hasse (Fin 3)

#guard_msgs in
#hasse (Finset (Fin 2)) updown 1 highlight [0]

#guard_msgs in
#hasse (Finset (Fin 2)) highlight [0] updown 1

/-! ## Error cases -/

/--
error: #hasse: expected a type, but `42` has type `ℕ` — #hasse draws the order of a finite type V, e.g. `#hasse (Fin 4)`
-/
#guard_msgs in
#hasse (text := true) (42 : Nat)

/--
error: #hasse: `True` is a proposition, not a type — #hasse draws the order of a finite *type* V
-/
#guard_msgs in
#hasse (text := true) True

/--
error: #hasse: cannot synthesize `Fintype ℕ` — #hasse needs [Fintype V], [DecidableEq V], [LE V] and a decidable order (DecidableLE V, equivalently DecidableRel (· ≤ ·)) to evaluate the poset
-/
#guard_msgs in
#hasse (text := true) ℕ

/-- A three-element type deliberately *without* `LE` (but with hand-built
`Fintype` and derived `DecidableEq`), to pin the `LE` branch. -/
inductive NoLe where
  | a | b | c
  deriving DecidableEq

instance : Fintype NoLe where
  elems := ⟨[NoLe.a, NoLe.b, NoLe.c], by simp⟩
  complete x := by cases x <;> simp

/--
error: #hasse: cannot synthesize `LE NoLe` — #hasse needs [Fintype V], [DecidableEq V], [LE V] and a decidable order (DecidableLE V, equivalently DecidableRel (· ≤ ·)) to evaluate the poset
-/
#guard_msgs in
#hasse (text := true) NoLe

/-- A type whose order is genuinely undecidable-looking (a `∀` over `ℕ`),
to pin the `DecidableLE` branch and the classical bypass below. -/
def NoDecLe := Fin 3

instance : DecidableEq NoDecLe := inferInstanceAs (DecidableEq (Fin 3))
instance : Fintype NoDecLe := inferInstanceAs (Fintype (Fin 3))
instance : LE NoDecLe := ⟨fun a b => ∀ n : ℕ, n = n → a.val ≤ b.val⟩

/--
error: #hasse: cannot synthesize `DecidableLE NoDecLe` — #hasse needs [Fintype V], [DecidableEq V], [LE V] and a decidable order (DecidableLE V, equivalently DecidableRel (· ≤ ·)) to evaluate the poset
-/
#guard_msgs in
#hasse (text := true) NoDecLe

-- With `open scoped Classical` the same order *synthesizes* a `DecidableLE`
-- instance — a noncomputable one.  It is rejected with a curated error
-- naming the culprit, not a raw compiler error.
/--
error: #hasse: the instance synthesized for `DecidableLE NoDecLe` is noncomputable (it uses `Classical.propDecidable`) — #hasse evaluates the order with compiled code, so it needs computable instances; define one by hand (`decidable_of_iff` is the idiomatic fix, see HasseView/Demo.lean)
-/
#guard_msgs in
open scoped Classical in
#hasse (text := true) NoDecLe

/-- A type whose only `Fintype` instance is `noncomputable`, to pin the
noncomputable-instance error on the `Fintype` branch. -/
def OpaqueFin3 := Fin 3

/-- The noncomputable `Fintype` instance for `OpaqueFin3`. -/
noncomputable instance ncFintype : Fintype OpaqueFin3 :=
  inferInstanceAs (Fintype (Fin 3))

/--
error: #hasse: the instance synthesized for `Fintype OpaqueFin3` is noncomputable (it uses `HasseViewTests.ncFintype`) — #hasse evaluates the order with compiled code, so it needs computable instances; define one by hand (`decidable_of_iff` is the idiomatic fix, see HasseView/Demo.lean)
-/
#guard_msgs in
#hasse (text := true) OpaqueFin3

-- The cap is checked BEFORE any ≤ is evaluated, and names the actual card.
/--
error: #hasse: the poset has 65 elements, more than the limit of 64 — #hasse refuses to draw it
-/
#guard_msgs in
#hasse (text := true) (Fin 65)

/--
error: #hasse: the type still contains metavariables (`_`) — fill in the underscores so the poset is fully determined
-/
#guard_msgs in
#hasse (text := true) _

/--
error: #hasse: invalid highlight — highlighted element 9 is out of range (the poset has 3 elements)
-/
#guard_msgs in
#hasse (text := true) (Fin 3) highlight [9]

/--
error: #hasse: invalid updown — updown element 7 is out of range (the poset has 3 elements)
-/
#guard_msgs in
#hasse (text := true) (Fin 3) updown 7

-- Duplicate clauses are rejected before anything is extracted or rendered.
/--
error: #hasse: duplicate `highlight` clause
-/
#guard_msgs in
#hasse (text := true) (Fin 3) highlight [0] highlight [1]

/--
error: #hasse: duplicate `updown` clause
-/
#guard_msgs in
#hasse (text := true) (Fin 3) updown 0 highlight [1] updown 2

end HasseViewTests
