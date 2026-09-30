import SimpLensTests.Helpers

/-!
# Minimizer tests — generated `simp only [...]` text and origin classification

`#lens_min` pins the exact generated call; `#lens_classify` pins how each used
origin is classified for representability (including the fvar path through
the minimizer).
-/

namespace SimpLensTests.Minimize

set_option linter.unusedVariables false

-- ## exact generated calls (note: builtins eq_self/iff_self are filtered out)
#lens_min ∀ n : Nat, 0 + n = n => "simp only [Nat.zero_add]"
#lens_min ∀ n : Nat, n + 0 + 0 = n => "simp only [Nat.add_zero]"
#lens_min ∀ l : List Nat, l ++ [] = l => "simp only [List.append_nil]"
#lens_min ∀ p : Prop, (p ∧ True) ∨ False ↔ p => "simp only [and_true, or_false]"
#lens_min ∀ a b : Nat, (if true then a else b) = a => "simp only [↓reduceIte]"
#lens_min ∀ p : Prop, p → p => "simp only"

-- ## a local hypothesis flows through the minimizer by user-facing name
#lens_min ∀ (n : Nat) (h : n = 5), n + 0 = 5 hyps [h] => "simp only [Nat.add_zero, h]"

-- ## two hypotheses, order of first use
#lens_min ∀ (a b : Nat) (h1 : a = 1) (h2 : b = 2), a + b = 1 + 2 hyps [h1, h2] =>
  "simp only [Nat.reduceAdd, h1, h2]"

-- ## non-simp global lemma included by name
#lens_min ∀ (a b : Nat), a + b + 0 = b + a with [Nat.add_comm] =>
  "simp only [Nat.add_zero, Nat.add_comm, Nat.add_left_cancel_iff]"

-- ## origin classification, in used-order
#lens_classify ∀ n : Nat, 0 + n = n =>
  ["global lemma Nat.zero_add", "global lemma eq_self"]
#lens_classify ∀ a b : Nat, (if true then a else b) = a =>
  ["global lemma eq_self", "simproc reduceIte"]
#lens_classify ∀ (n : Nat) (h : n = 5), n + 0 = 5 hyps [h] =>
  ["local hypothesis h", "global lemma Nat.add_zero", "global lemma eq_self"]

end SimpLensTests.Minimize
