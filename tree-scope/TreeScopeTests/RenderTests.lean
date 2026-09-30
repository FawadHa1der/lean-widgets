import TreeScopeTests.Helpers

/-! # Render tests: substring assertions on the serialized SVG/HTML panel -/

namespace TreeScopeTests

open TreeScope TreeScope.TreeView TreeScope.Render

/-! ## `ratStr`: exact ℚ → decimal serialization -/

#guard ratStr 38 == "38"
#guard ratStr (mkRat 77 2) == "38.5"
#guard ratStr (mkRat 305 4) == "76.25"
#guard ratStr 0 == "0"
#guard ratStr (mkRat (-9) 4) == "-2.25"
#guard ratStr (mkRat 1 3) == "0.333333"   -- deterministic 6-digit truncation
#guard ratStr (mkRat 1 2) == "0.5"

/-! ## The tone → color table (every tone pinned) -/

#guard toneStroke .neutral == "var(--vscode-editor-foreground, #333333)"
#guard toneStroke .rbRed == "var(--vscode-charts-red, #e51400)"
#guard toneStroke .rbBlack == "var(--vscode-editor-foreground, #333333)"
#guard toneStroke .ok == "var(--vscode-charts-green, #388a34)"
#guard toneStroke .violation == "var(--vscode-charts-red, #e51400)"
#guard toneStroke .highlight == "var(--vscode-charts-purple, #b180d7)"
#guard toneStroke .added == "var(--vscode-charts-green, #388a34)"
-- rbBlack is the only filled node; its label is drawn in the background color.
#guard NodeTone.all.filter (fun t => toneFill t != bgColor) == #[.rbBlack]
#guard toneFill .rbBlack == fgColor
#guard toneText .rbBlack == bgColor
#guard toneText .neutral == fgColor
-- Rings: violation → red, added → green, nothing else.
#guard toneRing? .violation == some redColor
#guard toneRing? .added == some greenColor
#guard NodeTone.all.filter (fun t => (toneRing? t).isSome) == #[.violation, .added]

/-! ## A plain tree -/

/-- Root with two leaves (pinned layout: root (86, 18), leaves (38, 82), (134, 82)). -/
private def tB : TreeView := make "r" #[leaf "a", leaf "b"]

/-- Serialized panel of the plain 3-node tree. -/
private def pB : String := htmlToDebugString (renderPanel tB)

-- One rect per node, one edge per non-root node (edge count = node count - 1).
#guard countOccurrences pB "data-node=" == 3
#guard countOccurrences pB "data-edge=" == 2
#guard containsSubstr pB "data-node=\"r\""
#guard containsSubstr pB "data-edge=\"r.0\""
#guard containsSubstr pB "data-edge=\"r.1\""

-- Pinned geometry: viewport = bounds + 2·8 padding; root edge starts at its
-- bottom center (86, 36) and reaches the first child's top center (38, 64).
#guard containsSubstr pB "viewBox=\"0 0 188 116\""
#guard containsSubstr pB "x1=\"86\" y1=\"36\" x2=\"38\" y2=\"64\""

-- All-neutral tree: no legend, no rings, no badges, no collapsed stubs.
#guard countOccurrences pB "data-legend=" == 0
#guard countOccurrences pB "data-ring=" == 0
#guard countOccurrences pB "data-badges=" == 0
#guard countOccurrences pB "data-collapsed=" == 0

-- Theme-aware colors with fallbacks; stats line present.
#guard containsSubstr pB "var(--vscode-editor-foreground, #333333)"
#guard containsSubstr pB "var(--vscode-editor-background, #ffffff)"
#guard containsSubstr pB "var(--vscode-editorLineNumber-foreground, #888888)"
#guard countOccurrences pB "var(--vscode-" >= 8
#guard containsSubstr pB "tree: 3 nodes, depth 2"

-- Determinism: rendering twice yields the same bytes.
#guard pB == htmlToDebugString (renderPanel tB)

/-! ## An annotated tree: every tone, badges, sublabel, collapsed stub -/

/-- One child per non-neutral tone, plus a collapsed subtree hiding 2 nodes. -/
private def tA : TreeView :=
  make "root" (sublabel := "h=3") (children := #[
    leaf "r" |>.withTone .rbRed,
    leaf "b" |>.withTone .rbBlack,
    leaf "o" |>.withTone .ok,
    leaf "v" |>.withTone .violation |>.addBadge "dup",
    leaf "h" |>.withTone .highlight,
    leaf "n" |>.withTone .added,
    make "z" (collapsed := true) (children := #[leaf "z1", leaf "z2"])])

/-- Serialized panel of the annotated tree. -/
private def pA : String := htmlToDebugString (renderPanel tA)

-- 8 visible nodes (the 2 hidden ones are not drawn), 7 edges.
#guard countOccurrences pA "data-node=" == 8
#guard countOccurrences pA "data-edge=" == 7

-- Rings exactly for violation and added.
#guard countOccurrences pA "data-ring=" == 2
#guard containsSubstr pA "data-ring=\"violation\""
#guard containsSubstr pA "data-ring=\"added\""

-- The violation node gets an automatic ⚠ appended to its own badges.
#guard containsSubstr pA "data-badges=\"dup|⚠\""

-- Collapsed stub: dashed, tagged with the hidden count, labeled `+2 hidden`.
#guard containsSubstr pA "data-collapsed=\"2\""
#guard containsSubstr pA "strokeDasharray=\"4 2\""
#guard containsSubstr pA "+2 hidden"

-- Sublabel drawn as its own text line.
#guard containsSubstr pA ">h=3</text>"

-- Legend: exactly the six non-neutral tones, in fixed order.
#guard countOccurrences pA "data-legend=" == 6
#guard containsSubstr pA "data-legend=\"red\""
#guard containsSubstr pA "data-legend=\"black\""
#guard containsSubstr pA "data-legend=\"ok\""
#guard containsSubstr pA "data-legend=\"violation\""
#guard containsSubstr pA "data-legend=\"highlight\""
#guard containsSubstr pA "data-legend=\"added\""
#guard !containsSubstr pA "data-legend=\"neutral\""

-- Tone colors present: red, green, purple all used.
#guard containsSubstr pA "var(--vscode-charts-red, #e51400)"
#guard containsSubstr pA "var(--vscode-charts-green, #388a34)"
#guard containsSubstr pA "var(--vscode-charts-purple, #b180d7)"

-- Stats count the hidden nodes structurally.
#guard containsSubstr pA "tree: 10 nodes, depth 3"

/-! ## The invariant caption (stage 2)

`renderPanel` gained a caption row for trees carrying checked tones; the
plain tree `pB` is unchanged, the annotated tree `pA` (one violation node at
path `r.3` with a `dup` badge) now lists it. -/

#guard countOccurrences pB "data-caption=" == 0
#guard healthCaption? tB == none
#guard countOccurrences pA "data-caption=" == 1
#guard containsSubstr pA "data-caption=\"⚠ r.3 (dup)\""
#guard healthCaption? tA == some "⚠ r.3 (dup)"
#guard violationEntries tA == #["r.3 (dup)"]
-- Checked tones without violations caption as ok.
#guard healthCaption? (leaf "x" |>.withTone .rbBlack) == some "invariants ok"
#guard healthCaption? (leaf "x" |>.withTone .ok) == some "invariants ok"
-- `added`/`highlight` alone (diff frames on plain values) get no caption.
#guard healthCaption? (leaf "x" |>.withTone .added) == none
-- A violation node without badges captions as its bare path.
#guard healthCaption? (make "r" #[leaf "v" |>.withTone .violation]) == some "⚠ r.0"

-- A violation inside a *collapsed* subtree stays listed but is marked
-- `[hidden]` (the SVG only draws the collapsed stub); a visible violation
-- carries no marker.
#guard healthCaption?
    (make "r" #[make "c" #[leaf "v" |>.withTone .violation] (collapsed := true)])
  == some "⚠ r.0.0 [hidden]"
#guard healthCaption?
    (make "r" #[make "c" #[leaf "v" |>.withTone .violation]])
  == some "⚠ r.0.0"
-- Text mode appends exactly the caption line.
#guard textReport (leaf "x" |>.withTone .rbRed) == "tree: 1 nodes, depth 1\nx <red>\ninvariants ok"
#guard textReport (leaf "x") == "tree: 1 nodes, depth 1\nx"

/-! ## Edge count = visible node count - 1, across the whole family -/

#guard family.all fun t =>
  let s := htmlToDebugString (renderPanel t)
  countOccurrences s "data-edge=" + 1 == countOccurrences s "data-node="

/-! ## The grid renderer -/

/-- Serialized 3-tree forest (two rows; pinned grid offsets). -/
private def pF : String := htmlToDebugString (renderForest #[tB, tB, tB] (maxRowWidth := 400))

#guard countOccurrences pF "data-cell=" == 3
#guard containsSubstr pF "transform=\"translate(0 0)\" data-cell=\"0\""
#guard containsSubstr pF "transform=\"translate(196 0)\" data-cell=\"1\""
#guard containsSubstr pF "transform=\"translate(0 124)\" data-cell=\"2\""
-- Grid bounds drive the viewport (368 + 16, 224 + 16).
#guard containsSubstr pF "viewBox=\"0 0 384 240\""
-- Every tree body is drawn: 3 nodes per tree.
#guard countOccurrences pF "data-node=" == 9
#guard pF == htmlToDebugString (renderForest #[tB, tB, tB] (maxRowWidth := 400))

/-! ## The React style contract

The InfoView hands attributes to React as props, so a `style` value must be a
JSON *object* with camelCased properties — a CSS string crashes the panel at
runtime with React error #62.  `reactContractViolations` walks an `Html` tree
and reports every string-styled element (and any `class` attribute); the
guards below run it over the real top-level outputs the commands attach.
Before styles were built with `Render.css`, `renderPanel`'s root div and the
legend/caption/stats rows carried string styles, so the `renderPanel` guards
below (and the filmstrip one in EvolveTests) failed. -/

-- The checker itself: string styles and `class` are caught, object styles
-- and other string attributes pass, nesting is found and path-labeled.
#guard reactContractViolations (.element "div" #[("style", .str "color:red")] #[]) ==
  ["r<div>: style is not a Json object: \"color:red\""]
#guard reactContractViolations (.element "div" #[("class", .str "x")] #[]) ==
  ["r<div>: attribute 'class' (React expects className)"]
#guard reactContractViolations
    (.element "div" #[] #[.text "t", .element "span" #[("style", .str "a:b")] #[]]) ==
  ["r.1<span>: style is not a Json object: \"a:b\""]
#guard reactContractViolations
    (.element "div" #[("style", Render.css #[("color", "red")]), ("data-x", .str "y")] #[]) == []

-- Hyphenated SVG presentation attributes that React warns about ("Invalid DOM
-- property") are flagged with the camelCase spelling React wants — including
-- the font/text presentation attributes (`text-anchor`, `font-*`), which an
-- earlier round wrongly believed React whitelisted; the camelCase spellings
-- and `data-*` attributes pass.
#guard reactContractViolations (.element "rect" #[("stroke-width", .str "2")] #[]) ==
  ["r<rect>: hyphenated SVG attribute stroke-width — React wants camelCase strokeWidth"]
#guard reactContractViolations (.element "text" #[("text-anchor", .str "middle")] #[]) ==
  ["r<text>: hyphenated SVG attribute text-anchor — React wants camelCase textAnchor"]
#guard reactContractViolations (.element "text" #[("font-family", .str "monospace")] #[]) ==
  ["r<text>: hyphenated SVG attribute font-family — React wants camelCase fontFamily"]
#guard reactContractViolations (.element "text" #[("font-size", .str "11")] #[]) ==
  ["r<text>: hyphenated SVG attribute font-size — React wants camelCase fontSize"]
#guard reactContractViolations (.element "text" #[("font-weight", .str "bold")] #[]) ==
  ["r<text>: hyphenated SVG attribute font-weight — React wants camelCase fontWeight"]
#guard reactContractViolations
    (.element "text" #[("strokeWidth", .str "2"), ("textAnchor", .str "middle"),
      ("fontSize", .str "11"), ("data-foo", .str "bar")] #[]) == []

-- Every real top-level output is clean: single-tree panels (plain, fully
-- annotated, and the whole 12-tree layout family), the forest/gallery grid,
-- and the Catalan gallery at its demo width.
#guard reactContractViolations (renderPanel tB) == []
#guard reactContractViolations (renderPanel tA) == []
#guard family.all fun t => reactContractViolations (renderPanel t) == []
#guard reactContractViolations (renderForest #[tB, tA, tB] (maxRowWidth := 400)) == []

-- Object styles serialize as compressed JSON in the debug string; the old
-- CSS-string form is gone.
#guard containsSubstr pB "\"fontFamily\": \"sans-serif\"" ||
  containsSubstr pB "\"fontFamily\":\"sans-serif\""
#guard !containsSubstr pB "font-family:"

end TreeScopeTests
