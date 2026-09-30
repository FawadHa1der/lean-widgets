import IntervalInspector
import ExprXRay
import SimpLens
import GraphScope
import TreeScope
import HasseView
import DistLens
import ChartKit

/-! # Lean Widget Kit

One import for the whole InfoView widget suite:

* `#interval_inspect` / `interval_inspect?` — interval goals as number lines
  with verified Mathlib lemma suggestions;
* `#xray` / `#xray_diff` — elaborated-term inspection and defeq-aware diffing;
* `simp_lens` — simp filmstrips, minimal `simp only`, exclusion previews;
* `#graph_scope` — concrete `SimpleGraph`s with walk/highlight overlays;
* `#tree_scope` / `#tree_evolve` — trees and heaps with invariant overlays
  and evolution filmstrips;
* `#hasse` — layered Hasse diagrams with lattice verdicts and overlays;
* `#dist` / `#dist_film` / `#chain` — exact probability distributions with
  `pmf_num`-verified weights and finite Markov chains;
* `#chart` — verified-exact charting primitives over ℚ data.

Each widget also remains available as a standalone package; see the suite
README one directory up. -/

def LeanWidgetKit.version : String := "0.1.0"
