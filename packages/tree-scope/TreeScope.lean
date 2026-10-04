import TreeScope.Model
import TreeScope.Layout
import TreeScope.Render
import TreeScope.Reflect
import TreeScope.ToTreeView
import TreeScope.Instances.RB
import TreeScope.Instances.Heap
import TreeScope.Instances.MathlibTree
import TreeScope.Instances.StdTreeMap
import TreeScope.Widget
import TreeScope.Evolve
import TreeScope.Demo

/-! # TreeScope

A universal tree/heap visualizer for the Lean InfoView: `#tree_scope value`
renders any concrete inductive value — via its semantic `ToTreeView` instance
when one exists (red–black maps, binomial heaps, binary trees, `Std.TreeMap`,
with invariant checking), falling back to the constructor-tree reflection.
`#tree_evolve init [op, …]` renders a step-by-step filmstrip with diff
badging.
-/

def TreeScope.version : String := "0.2.0"
