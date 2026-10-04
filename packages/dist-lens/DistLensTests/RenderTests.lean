import DistLensTests.Helpers

/-! # Render tests

Byte-exact pins of the SVG/HTML output (via the deterministic
`htmlToDebugString` serializer) plus the exact-ℚ geometry helpers.
-/

namespace DistLensTests

open DistLens

/-! ## Geometry -/

#guard Render.barPx 1 = 120
#guard Render.barPx 0 = 0
#guard Render.barPx (1/2) = 60
#guard Render.barPx (1/3) = 40
#guard Render.barPx (1/6) = 20
-- Non-dyadic fractions floor.
#guard Render.barPx (1/7) = 17
-- Out-of-range weights clamp instead of overflowing the chart.
#guard Render.barPx 2 = 120
#guard Render.barPx (-1/2) = 0
#guard Render.chartWidth 6 = 284
#guard Render.chartWidth 2 = 108

-- Chain layout: state 0 at 12 o'clock, deterministic rounding.
#guard Render.chainPos 2 0 = (150, 40)
#guard Render.chainPos 2 1 = (150, 260)
#guard Render.chainPos 4 1 = (260, 150)
#guard Render.chainPos 4 3 = (40, 150)

/-! ## Bar chart -/

#guard htmlToDebugString (Render.barChart coin) =
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"108\" height=\"152\" \
   viewBox=\"0 0 108 152\">\
   <line x1=\"10\" y1=\"134\" x2=\"98\" y2=\"134\" \
   stroke=\"var(--vscode-descriptionForeground, #717171)\" strokeWidth=\"1\"></line>\
   <rect x=\"17\" y=\"94\" width=\"30\" height=\"40\" \
   fill=\"var(--vscode-charts-blue, #3794ff)\" data-bar=\"0\" data-weight=\"1/3\"></rect>\
   <text x=\"32\" y=\"91\" fill=\"var(--vscode-editor-foreground, #333333)\" \
   fontSize=\"10\" textAnchor=\"middle\" fontFamily=\"monospace\">1/3</text>\
   <text x=\"32\" y=\"147\" fill=\"var(--vscode-descriptionForeground, #717171)\" \
   fontSize=\"10\" textAnchor=\"middle\" fontFamily=\"monospace\">false</text>\
   <rect x=\"61\" y=\"54\" width=\"30\" height=\"80\" \
   fill=\"var(--vscode-charts-blue, #3794ff)\" data-bar=\"1\" data-weight=\"2/3\"></rect>\
   <text x=\"76\" y=\"51\" fill=\"var(--vscode-editor-foreground, #333333)\" \
   fontSize=\"10\" textAnchor=\"middle\" fontFamily=\"monospace\">2/3</text>\
   <text x=\"76\" y=\"147\" fill=\"var(--vscode-descriptionForeground, #717171)\" \
   fontSize=\"10\" textAnchor=\"middle\" fontFamily=\"monospace\">true</text></svg>"

-- A diff mark recolors exactly the marked bar.
#guard ((htmlToDebugString (Render.barChart coin #[false, true])).splitOn
    "var(--vscode-charts-orange, #d18616)").length = 2
#guard ((htmlToDebugString (Render.barChart coin #[false, false])).splitOn
    "var(--vscode-charts-orange, #d18616)").length = 1

/-! ## CDF staircase -/

#guard htmlToDebugString (Render.cdfChart coin) =
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"108\" height=\"94\" \
   viewBox=\"0 0 108 94\">\
   <line x1=\"10\" y1=\"8\" x2=\"98\" y2=\"8\" \
   stroke=\"var(--vscode-descriptionForeground, #717171)\" strokeWidth=\"1\" \
   strokeDasharray=\"3 3\"></line>\
   <polyline points=\"10,88 10,88 10,62 54,62 54,62 54,8 98,8\" fill=\"none\" \
   stroke=\"var(--vscode-charts-purple, #b180d7)\" strokeWidth=\"2\" \
   data-cdf=\"1/3 1\"></polyline>\
   <text x=\"96\" y=\"5\" fill=\"var(--vscode-descriptionForeground, #717171)\" \
   fontSize=\"9\" textAnchor=\"end\" fontFamily=\"monospace\">cdf</text></svg>"

/-! ## Chain graph -/

-- Structural pins on the weather-chain SVG: every state, self-loop and
-- cross edge is present exactly once with its exact probability label.
def weatherSvg : String := htmlToDebugString (Render.chainGraph weatherM)

#guard (weatherSvg.splitOn "data-state=").length = 3
#guard (weatherSvg.splitOn "data-loop=\"0\"").length = 2
#guard (weatherSvg.splitOn "data-loop=\"1\"").length = 2
#guard (weatherSvg.splitOn "data-edge=\"0-1\"").length = 2
#guard (weatherSvg.splitOn "data-edge=\"1-0\"").length = 2
#guard (weatherSvg.splitOn ">3/4</text>").length = 2
#guard (weatherSvg.splitOn ">1/4</text>").length = 2
-- Zero-probability transitions draw nothing: identity chain has no cross edges.
#guard ((htmlToDebugString (Render.chainGraph identityM)).splitOn
    "data-edge=").length = 1

/-! ## Panel structure -/

def die6Panel : String :=
  htmlToDebugString (renderDistPanel die6
    #["example : die 0 = 1/6 := by pmf_num"])

-- Header, six bars, the CDF, both moment tiles and the suggestion row.
#guard (die6Panel.splitOn "dist: 6 outcomes over Fin 6").length = 2
#guard (die6Panel.splitOn "<rect").length = 7
#guard (die6Panel.splitOn "data-cdf=").length = 2
#guard (die6Panel.splitOn "E[X] = 5/2").length = 2
#guard (die6Panel.splitOn "Var[X] = 35/12").length = 2
#guard (die6Panel.splitOn "verified weight goals").length = 2
#guard (die6Panel.splitOn "example : die 0 = 1/6 := by pmf_num").length = 2
-- No warnings on a healthy model.
#guard (die6Panel.splitOn "warning:").length = 1

-- The film panel badges changed outcomes and captions the change count.
def filmPanel : String := htmlToDebugString (renderFilmPanel
  ⟨#[("source", coin), ("result", { coin with weights := #[1/2, 1/2] })]⟩)

#guard (filmPanel.splitOn "source").length = 2
#guard (filmPanel.splitOn "result (2 changed)").length = 2
#guard (filmPanel.splitOn "var(--vscode-charts-orange, #d18616)").length = 3

-- The chain panel: graph + unique-π bars + suggestions; non-unique chains
-- get the honest caption and no π bars.
def chainPanel : String := htmlToDebugString (renderChainPanel weatherM
  ⟨#[]⟩ #["example : s := by pmf_num"])

#guard (chainPanel.splitOn "chain: 2 states").length = 2
#guard (chainPanel.splitOn "stationary: unique").length = 2
#guard (chainPanel.splitOn "data-weight=\"2/3\"").length = 2
#guard (chainPanel.splitOn "verify the stationary equations").length = 2

def idPanel : String := htmlToDebugString (renderChainPanel identityM)
#guard (idPanel.splitOn "non-unique (reducible chain").length = 2
#guard (idPanel.splitOn "data-bar=").length = 1

end DistLensTests
