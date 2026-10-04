import Mathlib
import ExprXRay

/-! # Expr X-Ray: the hidden structure of a term
Cursor on `#xray e`: an "HTML Display" panel shows `e` as a tree of
`kind ‹pretty› : type` nodes (click a ▸ to fold/unfold) with badges for
instance/implicit arguments, coercions and universes, in five presets.
Cursor on `#xray_diff a, b`: a ranked list of mismatches, each with a defeq
badge (`≢` blocks `rw`, `≈ʳ`/`≈ᵈ` is harmless), then both trees side by side.
In the proof at the bottom, put the cursor on `simp`: the X-Ray panel shows
the goal; shift-click one subterm to x-ray it, or two to compare them. -/

namespace Showcase.ExprXRay

-- Both sides print as `if 2 = 2 then 1 else 0`; the diff ranks the
-- `Decidable` instance argument as the top mismatch.
#xray_diff @ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0,
           @ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0

-- Instance and implicit arguments hiding inside `1 + 1`.
#xray (1 + 1 : Nat)

-- A coercion: the head is `Nat.cast`, flagged `↑coe`.
#xray ((3 : Nat) : Int)

/-- A reducible wrapper: differs from `2` only syntactically. -/
@[reducible] def redTwo : Nat := 2

-- Every mismatch is defeq: a green "syntactic only" banner.
#xray_diff Nat.succ redTwo, Nat.succ (2 : Nat)

-- A universe-only difference, invisible without `pp.universes`.
#xray_diff @PUnit.{1}, @PUnit.{2}

-- The panel: shift-click the two `if …` sides of the goal to compare them.
theorem xray_panel (n : Nat) :
    @ite Nat (n = n) (instDecidableEqNat n n) 1 0 =
    @ite Nat (n = n) (Classical.propDecidable (n = n)) 1 0 := by
  with_panel_widgets [ExprXRay.XRayPanel]
    simp

end Showcase.ExprXRay
