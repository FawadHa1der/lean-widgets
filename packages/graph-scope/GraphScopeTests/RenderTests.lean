import GraphScopeTests.Helpers

/-! # Render tests: substring assertions on the serialized SVG/HTML panel -/

namespace GraphScopeTests

open GraphScope

/-- Serialized panel of the 4-path, no overlays. -/
private def p4 : String := htmlToDebugString (renderPanel (path 4))

/-- Serialized panel of the 4-path with a walk overlay `0 → 1 → 2`. -/
private def p4walk : String :=
  htmlToDebugString (renderPanel (path 4) (walk? := some #[0, 1, 2]))

/-- Serialized panel of the 4-path with vertices 0 and 3 highlighted. -/
private def p4hi : String :=
  htmlToDebugString (renderPanel (path 4) (highlight? := some #[0, 3]))

/-! ## Plain rendering -/

-- One circle per vertex, one line per edge (tagged with data attributes).
#guard countOccurrences p4 "data-vertex=" == 4
#guard countOccurrences p4 "data-edge=" == 3
#guard containsSubstr p4 "data-edge=\"0-1\""
#guard containsSubstr p4 "data-edge=\"2-3\""
#guard !containsSubstr p4 "data-edge=\"0-2\""

-- The 4-path is a tree, so `.auto` picks the layered layout: vertex 0 (the
-- BFS root) is drawn at the pinned top-of-column position with its label.
#guard containsSubstr p4 "cx=\"180\" cy=\"75\" r=\"13\""
#guard containsSubstr p4 ">3</text>"

-- `layout circle` forces the classic circular layout (vertex 0 at 12 o'clock)…
#guard containsSubstr
  (htmlToDebugString (renderPanel (path 4) (mode := .circle)))
  "cx=\"180\" cy=\"40\" r=\"13\""
-- …and non-forests get it automatically (`.auto`).
#guard containsSubstr
  (htmlToDebugString (renderPanel (cycle 5)))
  "cx=\"180\" cy=\"40\" r=\"13\""
-- `.layered` can also be forced for a cyclic graph.
#guard containsSubstr
  (htmlToDebugString (renderPanel (cycle 5) (mode := .layered)))
  "cx=\"180\" cy=\"110\" r=\"13\""

-- Theme-aware colors: every color is a VS Code variable with fallback.
#guard containsSubstr p4 "var(--vscode-editor-foreground, #333333)"
#guard containsSubstr p4 "var(--vscode-editor-background, #ffffff)"
#guard containsSubstr p4 "var(--vscode-editorLineNumber-foreground, #888888)"
#guard !containsSubstr p4 "var(--vscode-charts-orange"   -- no walk ⇒ no walk color
#guard !containsSubstr p4 "var(--vscode-charts-purple"   -- no highlight ⇒ no ring color

-- Fixed viewport.
#guard containsSubstr p4 "viewBox=\"0 0 360 360\""

-- Stats block contents.
#guard containsSubstr p4 "graph: 4 vertices, 3 edges"
#guard containsSubstr p4 "degrees: 1 2 2 1 (min 1, max 2)"
#guard containsSubstr p4 "components: 1 (connected)"
#guard containsSubstr p4 "bipartite: yes (parts: {0, 2} / {1, 3})"

-- No overlay artifacts without overlays.
#guard countOccurrences p4 "data-step=" == 0
#guard countOccurrences p4 "data-ring=" == 0

-- Determinism: rendering twice yields the same bytes.
#guard p4 == htmlToDebugString (renderPanel (path 4))

/-! ## Walk overlay -/

-- Step numbers 1 and 2 exactly (walk of 2 steps).
#guard countOccurrences p4walk "data-step=" == 2
#guard containsSubstr p4walk "data-step=\"1\""
#guard containsSubstr p4walk "data-step=\"2\""
#guard !containsSubstr p4walk "data-step=\"3\""

-- Exactly the two traversed edges are emphasized.
#guard countOccurrences p4walk "strokeWidth=\"3\"" == 2
#guard countOccurrences p4walk "var(--vscode-charts-orange, #d18616)" >= 2

-- Legend line in the stats block.
#guard containsSubstr p4walk "walk: 0 → 1 → 2 (2 steps)"

-- No highlight rings from a walk.
#guard countOccurrences p4walk "data-ring=" == 0

/-! ## Highlight overlay -/

-- Rings exactly for the highlighted vertices.
#guard countOccurrences p4hi "data-ring=" == 2
#guard containsSubstr p4hi "data-ring=\"0\""
#guard containsSubstr p4hi "data-ring=\"3\""
#guard !containsSubstr p4hi "data-ring=\"1\""
#guard containsSubstr p4hi "r=\"19\""
#guard containsSubstr p4hi "var(--vscode-charts-purple, #b180d7)"
#guard containsSubstr p4hi "highlight: 0, 3"

-- Highlight indices are deduplicated in the rendering.
#guard countOccurrences
  (htmlToDebugString (renderPanel (path 4) (highlight? := some #[2, 2, 2])))
  "data-ring=" == 1

/-! ## Corner cases -/

-- The empty graph renders a panel with no vertices, no edges.
#guard countOccurrences (htmlToDebugString (renderPanel (empty 0))) "data-vertex=" == 0
#guard containsSubstr (htmlToDebugString (renderPanel (empty 0))) "graph: 0 vertices, 0 edges"

-- Isolated vertices show up in the stats block.
#guard containsSubstr (htmlToDebugString (renderPanel (empty 2))) "isolated: 0, 1"

-- Custom labels (as extraction produces for non-`Fin` vertex types) are drawn.
#guard containsSubstr
  (htmlToDebugString (renderPanel (GraphData.ofEdges 2 #[(0, 1)] #["inl 0", "inr 0"])))
  ">inr 0</text>"

/-! ## Label-aware vertex sizing and halo -/

/-- K₂,₃ as extraction labels it (`Repr` of `Fin 2 ⊕ Fin 3`). -/
private def k23labeled : GraphData :=
  GraphData.ofEdges 5 #[(0, 2), (0, 3), (0, 4), (1, 2), (1, 3), (1, 4)]
    #["Sum.inl 0", "Sum.inl 1", "Sum.inr 0", "Sum.inr 1", "Sum.inr 2"]

-- 9-char labels grow the vertex circles from 13 to 35 px…
#guard Render.vertexRadius k23labeled == 35
#guard countOccurrences (htmlToDebugString (renderPanel k23labeled)) "r=\"35\"" == 5
-- …while short default labels keep the classic 13.
#guard Render.vertexRadius (path 4) == 13
#guard Render.vertexRadius (GraphData.ofEdges 64 #[]) == 13   -- "63" is 2 chars
-- The radius is capped at 40, however long the label.
#guard Render.vertexRadius
  (GraphData.ofEdges 2 #[(0, 1)] #["a very long label indeed!!", "b"]) == 40

-- Highlight rings track the vertex radius (r + 6).
#guard containsSubstr
  (htmlToDebugString (renderPanel k23labeled (highlight? := some #[0])))
  "r=\"41\""
#guard containsSubstr p4hi "r=\"19\""

-- Vertex labels carry a background-colored halo so they stay legible over
-- edge lines.
#guard countOccurrences p4 "paintOrder=\"stroke\"" == 4
#guard containsSubstr p4
  "stroke=\"var(--vscode-editor-background, #ffffff)\" strokeWidth=\"4\" paintOrder=\"stroke\""

/-! ## The serializer itself -/

#guard htmlToDebugString (.text "hi") == "hi"
#guard htmlToDebugString (Render.el "b" #[("k", "v")] #[.text "x"]) == "<b k=\"v\">x</b>"
#guard htmlToDebugString (Render.el "a" #[] #[Render.el "b" #[]]) == "<a><b></b></a>"

end GraphScopeTests
