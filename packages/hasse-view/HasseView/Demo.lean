import HasseView.Widget
import Mathlib.Data.Fintype.Prod
import Mathlib.Data.Fintype.Powerset
import Mathlib.Data.Finset.Sort
import Mathlib.NumberTheory.Divisors

/-! # HasseView demos

Open this file in the editor and put the cursor on any `#hasse` line to see
the rendered Hasse diagram in the InfoView.

Below the caption, the panel lists **insertable examples**: clicking one
inserts a gate-verified `example : … := by decide` on a new line after the
`#hasse` command (cover edges as `a ⋖ b`, the ⊥/⊤ facts as instance-free
`∀`-statements, and — for non-lattices — the concrete no-join witness).
Candidates whose `Repr` labels are not valid element syntax are shown as
plain text with a "(not insertable: …)" note instead; `Div12` below
demonstrates exactly that fallback.

What each type needs — and where a local instance is the idiomatic fix:

* `Finset (Fin n)` under `⊆` works out of the box: `Fintype` from
  `Mathlib.Data.Fintype.Powerset`, `Finset.instDecidableLE` for the order,
  and `Repr` labels (`∅`, `{0, 1}`, …) from `Mathlib.Data.Finset.Sort`;
* `Fin n` and `Bool` are `LinearOrder`s / core types with everything built
  in; `Bool × Bool` gets the componentwise product order and per-pair
  decidability from `Mathlib.Order.Basic` + core `Bool` instances;
* divisibility on a subtype (`Div12` below) has NO ready-made `Fintype` or
  order instances — the local instances show the idiomatic setup
  (`Fintype.subtype` over `Nat.divisors`, `LE` by `·.val ∣ ·.val`,
  decidability by `inferInstanceAs` from `Nat.decidable_dvd`);
* a custom order on a type synonym (`Bowtie` below) keeps the synonym's
  borrowed `Fintype`/`DecidableEq`/`Repr` via `inferInstanceAs` and makes
  the hand-written `≤` decidable with `decidable_of_iff` — the same idiom
  GraphScope's demos use for adjacency.
-/

namespace HasseView.Demo

/-! ## The powerset cube — THE showcase

All subsets of `\{0, 1, 2}` under inclusion: 8 elements, 12 cover edges,
`⊥ = ∅`, `⊤ = \{0, 1, 2}`, atoms = singletons, coatoms = 2-element sets, a
lattice of height 3.  Element indices follow the `Fintype` enumeration,
which for `Finset (Fin 3)` is bitmask order (`i` has bit `b` set iff `b` is
in the subset). -/

#hasse (Finset (Fin 3))

/-! ## Divisors of 12 under divisibility

`\{1, 2, 3, 4, 6, 12}` with `d ≤ e ↔ d ∣ e`: the classic divisor lattice.
No instance exists off the shelf, so the subtype carries local ones. -/

/-- The divisors of 12, as a subtype of `ℕ`. -/
def Div12 := {d : ℕ // d ∣ 12}

instance : DecidableEq Div12 := inferInstanceAs (DecidableEq {d : ℕ // d ∣ 12})

/-- Enumerate `Div12` via the `Nat.divisors 12` finset (ascending: 1, 2, 3,
4, 6, 12 — this is the enumeration order the widget indexes by). -/
instance : Fintype Div12 :=
  .subtype (Nat.divisors 12) (fun d => by simp [Nat.mem_divisors])

/-- Order `Div12` by divisibility — NOT by the numeric order the subtype
would inherit from `ℕ`.

Note on the insertable-examples panel: `Div12`'s `Repr` labels (`4`, `6`, …)
are *not* valid `Div12` syntax — a bare numeral needs an `OfNat Div12 n`
instance, which deliberately does not exist (and the underlying subtype's
`⟨4, _⟩` anonymous-constructor form carries a proof hole).  The round-trip
gate therefore rejects every candidate, and the panel shows them all as
plain text with the "(not insertable: label is not valid syntax for the
element)" note — the honest fallback, demonstrated live by `#hasse Div12`
below and pinned by the `#links_report Div12` test. -/
instance : LE Div12 := ⟨fun a b => a.val ∣ b.val⟩

instance : DecidableLE Div12 :=
  fun a b => inferInstanceAs (Decidable (a.val ∣ b.val))

/-- Label each divisor by its numeral. -/
instance : Repr Div12 := ⟨fun d _ => repr d.val⟩

#hasse Div12

/-! ## A chain: `Fin 5`

A linear order is the degenerate Hasse diagram: one element per rank. -/

#hasse (Fin 5)

/-! ## A product order: `Bool × Bool`

Componentwise `≤` on pairs — the 2-cube (a 4-element Boolean lattice). -/

#hasse (Bool × Bool)

/-! ## A NON-lattice: the bowtie

`0` at the bottom; `1` and `2` in the middle; `3` and `4` both above `1`
and `2`.  The pair `1, 2` has upper bounds `\{3, 4}` but no LEAST one
(`3` and `4` are incomparable), so no join exists — the caption names the
concrete witness pair. -/

/-- A type synonym for `Fin 5` carrying the bowtie order (the synonym keeps
`Fin 5`'s `Fintype`/`DecidableEq`/`Repr` but replaces the linear order). -/
def Bowtie := Fin 5

instance : DecidableEq Bowtie := inferInstanceAs (DecidableEq (Fin 5))
instance : Fintype Bowtie := inferInstanceAs (Fintype (Fin 5))
instance : Repr Bowtie := inferInstanceAs (Repr (Fin 5))

/-- The bowtie order: `a ≤ b` iff `a = b`, or `a = 0`, or `a ∈ {1, 2}` (any
value `≤ 2`, but `0` is already covered) with `b ∈ {3, 4}`. -/
instance : LE Bowtie := ⟨fun a b => a = b ∨ a.val = 0 ∨ (a.val ≤ 2 ∧ 3 ≤ b.val)⟩

/-- The hand-written order is decidable by `decidable_of_iff` — the
idiomatic local-instance fix whenever a custom `≤` has no instance. -/
instance : DecidableLE Bowtie := fun a b =>
  decidable_of_iff (a = b ∨ a.val = 0 ∨ (a.val ≤ 2 ∧ 3 ≤ b.val)) Iff.rfl

/-- A `Preorder` so the panel's cover-edge links can offer `a ⋖ b` facts:
`HasseView.instDecidableRelCovByOfFintype` (which closes the inserted
`by decide` proofs) needs `Preorder` + `DecidableLE` + `Fintype`, ensuring
`<` is lawfully the strict part of `≤` — exactly the relation the diagram
draws.  Both axioms are decidable, so `by decide` proves them. -/
instance : Preorder Bowtie where
  le_refl := by decide
  le_trans := by decide

/-- Numeral syntax for `Bowtie` elements (borrowed from `Fin 5`), so the
`Repr` labels `0, …, 4` round-trip through the link gate: `(3 : Bowtie)` is
element 3 of the enumeration.  Without this the labels would not be valid
`Bowtie` syntax and the candidates would honestly fall back to plain text
(as `Div12`'s do). -/
instance (n : Nat) : OfNat Bowtie n := inferInstanceAs (OfNat (Fin 5) n)

#hasse Bowtie

/-! ## Overlays -/

-- Upset/downset shading: element 1 of the cube is `{0}`; its upset (the 4
-- supersets) shades green upward, its downset (`∅` and itself) blue below.
#hasse (Finset (Fin 3)) updown 1

-- Highlight rings on the two middle elements of the bowtie.
#hasse Bowtie highlight [1, 2]

-- Both overlays at once — the clauses may come in either order.
#hasse (Finset (Fin 3)) updown 1 highlight [0, 7]
#hasse (Finset (Fin 3)) highlight [0, 7] updown 1

end HasseView.Demo
