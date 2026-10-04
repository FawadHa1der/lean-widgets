import ChartKit

/-! # ChartKit test helpers

Pure, deterministic inspectors over `ProofWidgets.Html` trees (element/attr
counting and lookup in document order) plus the small shared specs the render
and contract tests pin.  Everything is `#guard`-friendly.
-/

namespace ChartKitTests

open ChartKit ProofWidgets

/-- All elements of the tree in document order, as `(tag, attrs)` pairs
(attribute values kept as raw `Json`). -/
partial def allElems (h : Html) : Array (String × Array (String × Lean.Json)) :=
  match h with
  | .text _ => #[]
  | .element tag attrs cs =>
    #[(tag, attrs)] ++ cs.foldl (fun acc c => acc ++ allElems c) #[]
  | .component _ _ _ cs => cs.foldl (fun acc c => acc ++ allElems c) #[]

/-- The string value of attribute `k`, if present as a `Json.str`. -/
def attr? (attrs : Array (String × Lean.Json)) (k : String) : Option String :=
  attrs.findSome? fun (k', v) =>
    if k' == k then match v with | .str s => some s | _ => none else none

/-- Number of elements with the given tag. -/
def countTag (h : Html) (tag : String) : Nat :=
  (allElems h).filter (·.1 == tag) |>.size

/-- Number of elements carrying attribute `k` with string value `v`. -/
def countAttrVal (h : Html) (k v : String) : Nat :=
  (allElems h).filter (fun (_, attrs) => attr? attrs k == some v) |>.size

/-- The attributes of the first element (document order) carrying attribute
`k` with string value `v`. -/
def firstWith? (h : Html) (k v : String) :
    Option (Array (String × Lean.Json)) :=
  ((allElems h).find? fun (_, attrs) => attr? attrs k == some v).map (·.2)

/-- The string values of attribute `k` over all elements, document order. -/
def attrVals (h : Html) (k : String) : Array String :=
  (allElems h).filterMap fun (_, attrs) => attr? attrs k

/-- All text nodes of the tree, document order. -/
partial def allText (h : Html) : Array String :=
  match h with
  | .text s => #[s]
  | .element _ _ cs => cs.foldl (fun acc c => acc ++ allText c) #[]
  | .component _ _ _ cs => cs.foldl (fun acc c => acc ++ allText c) #[]

/-- Unwrap an `Except`, defaulting on error (for pins that already know the
call succeeds; failures then show up as wrong pinned values). -/
def okD [Inhabited α] (e : Except String α) : α :=
  match e with
  | .ok a => a
  | .error _ => default

/-- The error message of an `Except`, or `"(no error)"`. -/
def errD (e : Except String α) : String :=
  match e with
  | .ok _ => "(no error)"
  | .error s => s

/-! ## Shared specs -/

/-- Three-point line chart on a 200×150 canvas (legend on by default). -/
def lineSpec : ChartSpec := {
  series := #[{ name := "f", mark := .line, data := #[(0, 0), (1, 1), (2, 4)] }],
  width := 200, height := 150 }

/-- The same three points as bars (y axis therefore includes 0). -/
def barSpec : ChartSpec := {
  series := #[{ name := "f", mark := .bar, data := #[(0, 2), (1, 1), (2, 4)] }],
  width := 200, height := 150 }

/-- The same three points as a staircase. -/
def stepSpec : ChartSpec := {
  series := #[{ name := "f", mark := .step, data := #[(0, 0), (1, 1), (2, 4)] }],
  width := 200, height := 150 }

/-- The same three points as a scatter. -/
def scatterSpec : ChartSpec := {
  series := #[{ name := "f", mark := .scatter, data := #[(0, 0), (1, 1), (2, 4)] }],
  width := 200, height := 150 }

/-- A categorical two-bar chart with value labels. -/
def catSpec : ChartSpec := {
  series := #[{ name := "n", mark := .bar, data := #[(0, 3), (1, 1)] }],
  xTickLabels := #["a", "b"],
  valueLabels := true,
  width := 200, height := 150 }

/-- Seven one-point series — exercises full palette cycling (7 > 6 colors). -/
def paletteSpec : ChartSpec := {
  series := (Array.range 7).map fun i =>
    { name := s!"s{i}", mark := .scatter,
      data := #[(((i : Nat) : Rat), ((i : Nat) : Rat))] } }

/-- A titled, fully-labeled two-series chart (line + bar). -/
def fullSpec : ChartSpec := {
  title? := some "Full",
  xLabel := "xs", yLabel := "ys",
  series := #[
    { name := "l", mark := .line, data := #[(0, 0), (1, 1)] },
    { name := "b", mark := .bar, data := #[(0, 1), (1, 2)] }],
  valueLabels := true }

end ChartKitTests
