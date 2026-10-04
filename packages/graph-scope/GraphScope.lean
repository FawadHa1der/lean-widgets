import GraphScope.Model
import GraphScope.Algo
import GraphScope.Layout
import GraphScope.Layered
import GraphScope.Render
import GraphScope.Insert
import GraphScope.Extract
import GraphScope.Gate
import GraphScope.Widget
import GraphScope.Demo

/-! # GraphScope

Proof-state-integrated `SimpleGraph` visualizer for the Lean 4 InfoView: the
`#graph_scope` command evaluates a concrete `SimpleGraph` through its
`Decidable` instances and draws it — layered layout for forests, circular
otherwise, degree/component/bipartiteness stats, walk and highlight
overlays. -/

/-- Package version. -/
def GraphScope.version : String := "0.1.0"
