import SimpLensTests.Helpers

/-!
# Equivalence tests — THE core value guarantee

For every goal, `#lens_equiv` asserts three facts (see its docstring):
1. the traced run lands exactly where plain, untraced `simp` lands;
2. traced and plain runs use identical theorem lists (order included);
3. the *generated minimal `simp only [...]`*, executed as a real tactic,
   lands exactly where plain `simp` lands.

A minimizer that drops a needed lemma, adds a wrong one, or a tracer that
perturbs simp's behavior in any way fails these.
-/

namespace SimpLensTests.Equiv

set_option linter.unusedVariables false

-- goals simp closes
#lens_equiv ∀ n : Nat, 0 + n = n
#lens_equiv ∀ n : Nat, n + 0 + 0 = n
#lens_equiv ∀ l : List Nat, l ++ [] = l
#lens_equiv ∀ a b : Nat, (if true then a else b) = a
#lens_equiv ∀ a b : Nat, (if false then a else b) = b
#lens_equiv ∀ p : Prop, (p ∧ True) ∨ False ↔ p
#lens_equiv ∀ p q : Prop, p ∧ q → q ∧ p ∧ True → p ∧ q
#lens_equiv ∀ (l : List Nat), (l ++ []).length = l.length
#lens_equiv ∀ (l : List Nat), (l ++ []).map (fun x => x + 0) = l
#lens_equiv ∀ (n : Nat), (n + 0) * 1 = n
#lens_equiv ∀ (b : Bool), (b && true) = b
#lens_equiv True

-- goals simp only partially simplifies (specific landing goals compared)
#lens_equiv ∀ n : Nat, n + 0 = 5
#lens_equiv ∀ (f : Nat → Nat) (n : Nat), f (n + 0) = 7
#lens_equiv ∀ p : Prop, ¬(p ∨ False)
#lens_equiv ∀ (l : List Nat), (l ++ []).reverse = l
#lens_equiv ∀ (n m : Nat), n + 0 = m + 0

-- goals simp cannot touch at all (empty minimal call must also no-op)
#lens_equiv ∀ p : Prop, p → p

-- with local hypotheses in the simp set (fvar origins through the minimizer)
#lens_equiv ∀ (n : Nat) (h : n = 5), n + 0 = 5 hyps [h]
#lens_equiv ∀ (a b : Nat) (h1 : a = 1) (h2 : b = 2), a + b = 1 + 2 hyps [h1, h2]
#lens_equiv ∀ (p : Prop) (hp : p), p ∧ True hyps [hp]

-- with extra global lemmas
#lens_equiv ∀ (a b : Nat), a + b + 0 = b + a with [Nat.add_comm]
#lens_equiv ∀ (n : Nat), 1 * (n + 0) = n with [Nat.one_mul]

end SimpLensTests.Equiv
