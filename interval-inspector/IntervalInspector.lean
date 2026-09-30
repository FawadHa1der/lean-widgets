import IntervalInspector.Model
import IntervalInspector.OrderGraph
import IntervalInspector.Recognize
import IntervalInspector.Layout
import IntervalInspector.Render
import IntervalInspector.Suggest
import IntervalInspector.Widget
import IntervalInspector.Demo

/-! # Interval Inspector

Number-line interval inspector for the Lean 4 InfoView: draws interval goals and
hypotheses as a labeled number line and suggests applicable Mathlib lemmas. -/

/-- Package version. -/
def IntervalInspector.version : String := "0.1.0"
