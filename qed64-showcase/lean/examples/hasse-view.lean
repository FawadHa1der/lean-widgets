import Mathlib
import HasseView

/-! # HasseView: Hasse diagrams of finite orders, with insertable facts
Cursor on a `#hasse` line: the panel draws the cover relation of a finite
order (ranks bottom to top) with a caption: ⊥/⊤, atoms, height, and whether
it is a lattice — or a concrete pair with no join when it is not.
Below the caption, "insertable examples" are links: a COVER edge inserts
`example : (a : α) ⋖ b := by decide`, the ⊥ / ⊤ badges insert `∀ x, ⊥ ≤ x`
facts, and a non-lattice's WITNESS inserts the no-join statement — each on a
new line after the command, gate-checked before it is offered.
`updown i` shades the up-set/down-set of element i; `highlight [...]` rings
elements (indices follow the `Fintype` enumeration). -/

namespace Showcase.HasseView

-- The powerset cube: 8 subsets, 12 cover edges, a lattice of height 3.
#hasse (Finset (Fin 3))

-- A chain, and a product order (the 2-cube).
#hasse (Fin 4)
#hasse (Bool × Bool)

-- Up-set/down-set of {0} (index 1), with ∅ and {0,1,2} ringed.
#hasse (Finset (Fin 3)) updown 1 highlight [0, 7]

/-- The bowtie from HasseView's demo module: `0` below `1, 2`, both below
`3, 4` — so `1, 2` have upper bounds `3, 4` but no least one (no join). -/
abbrev Bowtie := _root_.HasseView.Demo.Bowtie

-- A NON-lattice: the caption names the pair; click the witness to insert it.
#hasse Bowtie highlight [1, 2]

end Showcase.HasseView
