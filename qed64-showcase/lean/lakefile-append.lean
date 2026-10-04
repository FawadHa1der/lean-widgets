-- qed64-showcase: widget libraries (appended to the CLONE's lakefile only; BUILD-PLAN.md §4 B4).
-- Sources are the read-only export work/widgets-src, mounted at /work/mathlib4/widgets.
-- Default options on purpose: the widget packages' own lakefiles set no leanOptions.
-- The *Tests libraries are deliberately absent (ClickE2E calls processHeader).
lean_lib ChartKit where srcDir := "widgets/chart-kit"
lean_lib ExprXRay where srcDir := "widgets/expr-xray"
lean_lib GraphScope where srcDir := "widgets/graph-scope"
lean_lib HasseView where srcDir := "widgets/hasse-view"
lean_lib IntervalInspector where srcDir := "widgets/interval-inspector"
lean_lib SimpLens where srcDir := "widgets/simp-lens"
lean_lib TreeScope where srcDir := "widgets/tree-scope"
lean_lib DistLens where srcDir := "widgets/dist-lens"
lean_lib LeanWidgetKit where srcDir := "widgets/lean-widget-kit"
