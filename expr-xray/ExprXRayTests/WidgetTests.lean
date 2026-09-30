import ExprXRay
import ExprXRayTests.TestUtil

/-! # Tests for `ExprXRay.Widget`

Message-exact `#guard_msgs` tests pinning the deterministic text mode of
`#xray` and `#xray_diff`, plus checks of the `Html`-producing entry
points used by the InfoView panel. -/

namespace ExprXRayTests.WidgetTests

open Lean Elab Term ExprXRay ExprXRayTests ProofWidgets

/-! ## `#xray (text := true)`: message-exact tests -/

/--
info: app «id 5» : Nat
  const «@id».{1} : {α : Type} → α → α
  const «Nat» : Type {imp}
  app «5» : Nat
    const «@OfNat.ofNat».{0} : {α : Type} → (x : Nat) → [self : OfNat α x] → α
    const «Nat» : Type {imp}
    lit «5» : Nat
    app «instOfNatNat 5» : OfNat Nat 5 [inst]
      const «instOfNatNat» : (n : Nat) → OfNat Nat n
      lit «5» : Nat
-/
#guard_msgs in
#xray (text := true) @id Nat 5

/--
info: app «↑3» : Int ↑coe
  const «@Nat.cast».{0} : {R : Type} → [NatCast R] → Nat → R ↑coe
  const «Int» : Type {imp}
  const «instNatCastInt» : NatCast Int [inst]
  app «3» : Nat
    const «@OfNat.ofNat».{0} : {α : Type} → (x : Nat) → [self : OfNat α x] → α
    const «Nat» : Type {imp}
    lit «3» : Nat
    app «instOfNatNat 3» : OfNat Nat 3 [inst]
      const «instOfNatNat» : (n : Nat) → OfNat Nat n
      lit «3» : Nat
-/
#guard_msgs in
#xray (text := true) ((3 : Nat) : Int)

/--
info: sort «Prop».{0} : Type
-/
#guard_msgs in
#xray (text := true) (Prop)

/--
info: app «Nat.zero.succ» : Nat
  const «Nat.succ» : Nat → Nat
  const «Nat.zero» : Nat
-/
#guard_msgs in
#xray (text := true) Nat.succ Nat.zero

/-! ## `#xray_diff (text := true)`: message-exact tests -/

/--
info: instance argument #3 of ite differs: instDecidableEqNat 2 2 vs Classical.propDecidable (2 = 2) (NOT defeq — this blocks rw)
-/
#guard_msgs in
#xray_diff (text := true) @ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0,
                          @ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0

/--
info: no structural differences found
-/
#guard_msgs in
#xray_diff (text := true) (1 + 1 : Nat), (1 + 1 : Nat)

-- note the plural verb: "universe levels ... differ"
/--
info: universe levels of PUnit differ: [1] vs [2] (NOT defeq — this blocks rw)
-/
#guard_msgs in
#xray_diff (text := true) @PUnit.{1}, @PUnit.{2}

-- REGRESSION (bughunt2): the two visible operands of `+` are numbered
-- among the explicit arguments (#1/#2), not by their absolute positions
-- (#5/#6) in the elaborated HAdd.hAdd spine
/--
info: explicit argument #1 of HAdd.hAdd differs: x vs 0 (NOT defeq — this blocks rw)
explicit argument #2 of HAdd.hAdd differs: 0 vs x (NOT defeq — this blocks rw)
structural difference: x vs 0 (NOT defeq — this blocks rw)
structural difference: 0 vs x (NOT defeq — this blocks rw)
-/
#guard_msgs in
#xray_diff (text := true) (fun x : Nat => x + 0), (fun x : Nat => 0 + x)

-- non-text mode emits NO messages at all (widget only)
#guard_msgs in
#xray @id Nat 5

#guard_msgs in
#xray_diff @PUnit.{1}, @PUnit.{2}

/-! ## Html entry points used by the panel -/

#eval show TermElabM Unit from do
  -- xrayHtml output embeds all preset sections for a real expression
  let e ← elabT (← `((1 + 1 : Nat)))
  let out := Html.toStringCompact (← xrayHtml e)
  assertContains "xrayHtml: clean section" out "clean (explicit only)"
  assertContains "xrayHtml: pp.explicit content" out "@HAdd.hAdd"
  -- the pp.universes variant shows explicit levels
  assertContains "xrayHtml: pp.universes content" out "@HAdd.hAdd.{0, 0, 0}"

#eval show TermElabM Unit from do
  -- xrayCompareHtml embeds the ranked summary
  let a ← elabT (← `(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
  let b ← elabT (← `(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0))
  let out := Html.toStringCompact (← xrayCompareHtml a b)
  assertContains "xrayCompareHtml: summary" out "instance argument #3 of ite differs"
  assertContains "xrayCompareHtml: flex" out "\"display\":\"flex\""

#eval show TermElabM Unit from do
  -- xrayText/xrayCompareText agree with what the commands log
  let e ← elabT (← `((Prop : Type)))
  assertEq "xrayText: Prop" (← xrayText e) "sort «Prop».{0} : Type"
  let a ← elabT (← `(@PUnit.{1}))
  let b ← elabT (← `(@PUnit.{2}))
  assertEq "xrayCompareText: PUnit"
    (← xrayCompareText a b)
    "universe levels of PUnit differ: [1] vs [2] (NOT defeq — this blocks rw)"
  assertEq "xrayCompareText: equal sides"
    (← xrayCompareText a a) "no structural differences found"

end ExprXRayTests.WidgetTests
