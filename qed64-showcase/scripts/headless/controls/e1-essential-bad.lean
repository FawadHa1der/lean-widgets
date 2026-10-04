import Mathlib

/-! E1 negative control: same header, one designed error (line 7). -/

namespace Showcase.Control

theorem wrong : (2 : ℕ) + 2 = 5 := by norm_num

end Showcase.Control
