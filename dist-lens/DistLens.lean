import DistLens.Model
import DistLens.Verify
import DistLens.Extract
import DistLens.Render
import DistLens.Widget
import DistLens.Demo

/-! # DistLens

Exact probability-distribution visualizer for the Lean 4 InfoView: the
`#dist` / `#dist_film` / `#chain` commands extract finite,
rational-parameter `PMF` terms into exact ℚ weight vectors, render them as
themed SVG (bars, CDF, moments, filmstrips, transition graphs), and offer
machine-checked weight goals via the shipped `pmf_num` tactic. -/

/-- Package version. -/
def DistLens.version : String := "0.1.0"
