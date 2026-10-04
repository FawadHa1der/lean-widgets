import HasseView.Model
import HasseView.Extract
import HasseView.Layout
import HasseView.Render
import HasseView.Links
import HasseView.Gate
import HasseView.Widget
import HasseView.Demo

/-! # HasseView

`#hasse V` draws the Hasse diagram of a finite ordered type `V` in the
InfoView: layered by rank (minimal elements at the bottom), cover edges,
⊥/⊤ and atom/coatom badges, lattice verdict with concrete witness,
upset/downset shading and highlights.  See `HasseView/Widget.lean` for the
command and `HasseView/Demo.lean` for worked examples.
-/

/-- Package version. -/
def HasseView.version : String := "0.1.0"
