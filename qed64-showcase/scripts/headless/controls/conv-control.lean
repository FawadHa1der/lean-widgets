import Mathlib.Tactic.Widget.Conv

example (a b c : Nat) : a + (b + c) = (c + b) + a := by
  conv?
  omega
