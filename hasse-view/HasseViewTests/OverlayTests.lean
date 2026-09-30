import HasseViewTests.Helpers

/-! # Overlay tests

Upset/downset membership pinned on the cube, the updown/highlight legend
lines, overlay markers in the serialized SVG, and out-of-range validation
errors.
-/

namespace HasseViewTests

open HasseView Render

/-! ## Upset/downset on the cube (indices are bitmasks; 1 = the subset {0}) -/

-- The upset of {0} is exactly its 4 supersets…
#guard (cubeP 3).upset 1 == #[1, 3, 5, 7]
-- …and its downset is ∅ and itself.
#guard (cubeP 3).downset 1 == #[0, 1]
-- A coatom's upset is itself and ⊤.
#guard (cubeP 3).upset 6 == #[6, 7]
-- Legend lines carry labels (here: default index labels).
#guard updownLines (cubeP 3) 1 ==
  #["upset of 1: 1, 3, 5, 7", "downset of 1: 0, 1"]
#guard updownLines divisor12P 1 ==
  #["upset of 2: 2, 4, 6, 12", "downset of 2: 1, 2"]
#guard highlightLine #[0, 2] == "highlight: 0, 2"

/-! ## Overlay markers in the SVG -/

private def cubeUpdownSvg : String :=
  htmlToDebugString (hasseSvg (cubeP 3) (layoutPoset (cubeP 3)) (updown? := some 1))

-- Shaded boxes: upset {3, 5, 7} + downset {0} (the focus box 1 itself is
-- emphasized, not shaded).
#guard countOccurrences cubeUpdownSvg "fillOpacity=" == 4
#guard countOccurrences cubeUpdownSvg "strokeWidth=\"3\"" == 1
-- Without the overlay: no shading, no emphasis.
#guard countOccurrences (htmlToDebugString
  (hasseSvg (cubeP 3) (layoutPoset (cubeP 3)))) "fillOpacity=" == 0

private def chain3HighlightSvg : String :=
  htmlToDebugString
    (hasseSvg (chainP 3) (layoutPoset (chainP 3)) (highlight? := some #[0, 2]))

#guard countOccurrences chain3HighlightSvg "data-ring=" == 2
#guard containsSubstr chain3HighlightSvg "data-ring=\"0\""
#guard containsSubstr chain3HighlightSvg "data-ring=\"2\""
-- Duplicate highlight indices draw a single ring.
#guard countOccurrences (htmlToDebugString
  (hasseSvg (chainP 3) (layoutPoset (chainP 3)) (highlight? := some #[2, 2])))
  "data-ring=" == 1

/-! ## Text report with overlays -/

#guard textReport (chainP 3) (highlight? := some #[0, 2]) (updown? := some 1) ==
  textReport (chainP 3) ++
    "\nhighlight: 0, 2\nupset of 1: 1, 2\ndownset of 1: 0, 1"

/-! ## Out-of-range validation (what the command checks before rendering) -/

#guard (chainP 3).highlightError? #[0, 2] == none
#guard (chainP 3).highlightError? #[9] ==
  some "highlighted element 9 is out of range (the poset has 3 elements)"
-- The FIRST offender is named.
#guard (chainP 3).highlightError? #[1, 7, 9] ==
  some "highlighted element 7 is out of range (the poset has 3 elements)"
#guard (chainP 3).updownError? 2 == none
#guard (chainP 3).updownError? 7 ==
  some "updown element 7 is out of range (the poset has 3 elements)"
#guard (chainP 0).updownError? 0 ==
  some "updown element 0 is out of range (the poset has 0 elements)"

end HasseViewTests
