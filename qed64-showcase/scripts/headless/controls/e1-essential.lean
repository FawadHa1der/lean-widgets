import Mathlib

/-! E1 control: a browser-shaped document (`import Mathlib`) whose header the
E1 driver replaces with the stock bake key `import QED64.Essential`. -/

namespace Showcase.Control

example (a b : ℝ) : a + b = b + a := add_comm a b

theorem two_add_two : (2 : ℕ) + 2 = 4 := by norm_num

example (s : Finset ℕ) : s ⊆ s := Finset.Subset.refl s

#eval (List.range 5).map (· ^ 2)

end Showcase.Control
