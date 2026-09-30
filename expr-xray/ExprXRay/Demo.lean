import ExprXRay.Widget

/-! # Expr X-Ray: demos

Realistic examples that elaborate on every build. Open this file in
VS Code and place the cursor on a `#xray` / `#xray_diff` command (or
inside the tactic proofs at the bottom) to see the widget in the
InfoView. -/

namespace ExprXRay.Demo

open ExprXRay

/-! ## The motivating scenario: two different `Decidable` instances

`rw` fails with "motive is not type correct" when the two sides of an
equation carry different `Decidable` instances — invisible in default
pretty-printing, both sides print as `if 2 = 2 then 1 else 0`. The diff
surfaces the instance argument as the top-ranked mismatch. -/

#xray_diff @ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0,
           @ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0

/-! ## Defeq-aware diff: harmless vs blocking differences

Every mismatch is annotated with a definitional-equality verdict
(`≢` not defeq, `≈ʳ`/`≈ᵈ` defeq at reducible/default transparency), and
non-defeq mismatches are ranked before defeq ones. -/

/-- A `@[reducible]` wrapper: differs from `2` only syntactically. -/
@[reducible] def redTwo : Nat := 2

/-- A non-reducible wrapper: defeq to `2` only at default transparency. -/
def hiddenTwo : Nat := 2

-- Every mismatch is defeq: the summary says the discrepancy is syntactic
-- only (`exact` would succeed) — note the green ≈ʳ badge.
#xray_diff Nat.succ redTwo, Nat.succ (2 : Nat)

-- Same, but the wrapper only unfolds at default transparency (≈ᵈ).
#xray_diff Nat.succ hiddenTwo, Nat.succ (2 : Nat)

-- Re-ranking in action: the ite instances differ but are defeq (≈ᵈ,
-- harmless), while the explicit `then`-branches are NOT defeq — the
-- headline is the explicit argument that actually blocks `rw`, and the
-- defeq instance mismatch is demoted below it.
#xray_diff @ite Nat (1 = 1) (instDecidableEqNat 1 1) Nat.zero Nat.zero,
           @ite Nat (1 = 1) (Nat.decEq 1 1) (Nat.succ Nat.zero) Nat.zero

/-! ## Terms containing metavariables: an honest `undetermined` verdict

Elaborating `id` alone leaves fresh universe and type metavariables on
each side. The two sides are trivially unifiable, so the diff must not
claim the differences "block rw" — mismatches whose sides contain
metavariables get the `≟ₘ` *undetermined* badge (and wording) instead
of a false blocking verdict. -/

#xray_diff id, id

/-! ## Explicit arguments are numbered among what you wrote

The two visible operands of `+` sit at absolute positions #5 and #6 of
the elaborated `HAdd.hAdd` spine; the summaries say "explicit argument
#1/#2 of HAdd.hAdd" so the numbers map onto the source. Instance and
implicit sites keep the absolute position — that is the index you would
use in an `@`-application. -/

#xray_diff (fun x : Nat => x + 0), (fun x : Nat => 0 + x)

/-! ## Instance and implicit arguments hiding inside `1 + 1` -/

#xray (1 + 1 : Nat)

/-! ## A coercion chain: `Nat → Int`

The head is `Nat.cast`, flagged with a `↑coe` badge. -/

#xray ((3 : Nat) : Int)

/-- A tiny definition whose body mixes a coercion with arithmetic. -/
def natToIntTwice (n : Nat) : Int := (n : Int) + (n : Int)

#xray fun (n : Nat) => (n : Int) + (n : Int)

/-! ## Universe-polymorphic constants

With the `everything` preset (and in the `pp.universes` section) the
universe levels of `id`, `PUnit`, `ULift` become visible. -/

#xray @id.{2}

#xray (Type 1)

#xray fun (α : Type 3) (x : α) => @ULift.up.{5, 3} α x

/-! ## Universe-only difference: invisible without `pp.universes` -/

#xray_diff @PUnit.{1}, @PUnit.{2}

/-! ## Binders, let-bindings, projections -/

#xray fun (p : Nat × Int) => p.1

#xray let n : Nat := 3; n + n

#xray ∀ (n : Nat), n = n → True

/-! ## The InfoView panel

Place the cursor inside the proof below. With no selection the panel
x-rays the goal target; shift-click one subterm to inspect it, or two
subterms to compare them (e.g. compare the two `if` branches, whose
`Decidable` instances differ). -/

/-- Panel demo: place the cursor inside the proof and shift-click
subterms of the goal. -/
theorem demo_panel (n : Nat) :
    (if n = n then 1 else 0) + (if _h : n = n then 1 else 0) = 2 := by
  with_panel_widgets [XRayPanel]
    simp

/-- Fully explicit demo goal for panel comparison: the two sides use
different `Decidable` instances. -/
theorem demo_panel_instances (n : Nat) :
    @ite Nat (n = n) (instDecidableEqNat n n) 1 0 =
    @ite Nat (n = n) (Classical.propDecidable (n = n)) 1 0 := by
  with_panel_widgets [XRayPanel]
    -- Shift-click the two `if ...` sides and compare: the panel ranks
    -- the `Decidable` instance mismatch first.
    simp

end ExprXRay.Demo
