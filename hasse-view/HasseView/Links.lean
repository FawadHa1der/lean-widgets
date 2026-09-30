import HasseView.Render
import Mathlib.Order.Cover
import Mathlib.Data.Fintype.Basic

/-! # HasseView: click-to-insert link model (pure layer)

Data and text builders for the panel's **insertable examples**: clicking a
link in the InfoView inserts a self-contained `example : … := by decide` on a
new line after the `#hasse` command.  Everything in this file is pure and
`#guard`-testable; the analysis-time verification gate that decides *which*
candidates become links lives in `HasseView/Gate.lean`, and the document
plumbing (`MakeEditLink`, RPC) in `HasseView/Widget.lean`.

## The honesty contract

A link may only be offered for a statement that has been **verified at
analysis time** (see `HasseView/Gate.lean`): the element labels must
round-trip (parse → elaborate → equal the drawn element) and the full
statement must evaluate to `true` through its own `Decidable` instances.
Candidates that fail the gate render as plain text with a muted note — never
as a link.  The builders below therefore only *format* texts; they promise
nothing about truth.

## Link kinds

* **cover edges** — `example : (a : V) ⋖ b := by decide` for each drawn
  cover edge `a ⋖ b`;
* **⊥/⊤ badges** — `example : ∀ x : V, b ≤ x := by decide` (dual for `⊤`),
  deliberately phrased *without* `OrderBot`/`OrderTop` (the type may lack
  those instances; the table-derived bottom is just an element);
* **non-lattice witness** — the concrete no-join (or no-meet) fact for the
  caption's witness pair, spelled decidably with quantifiers over `V`
  (never with `Set`-based `IsLUB`, which `decide` cannot touch).

`V`'s syntax in every inserted text is the user's *original* type syntax
from the `#hasse` command, verbatim.

## The `⋖` decidability instance

Mathlib (v4.32.2 pin) only makes `· ⋖ ·` decidable for `Bool`;
`CovBy` is a plain (non-reducible) def, so `by decide` cannot see through it
without help.  `instDecidableRelCovByOfFintype` below makes `a ⋖ b`
decidable for every finite preorder with decidable `≤` — this is what lets
the inserted cover examples close with `by decide` in any file that imports
`HasseView`.  A `Preorder` (not just `LT`) is required so that `<` is
lawfully the strict part of `≤` (`lt_iff_le_not_ge`), which is exactly the
strict order the diagram is drawn from (`PosetData.ltB`).
-/

namespace HasseView

open ProofWidgets

/-- `a ⋖ b` is decidable over a finite preorder with decidable `≤`.
Unfolds `CovBy` definitionally (`Iff.rfl`) and decides the inner `<` via
`lt_iff_le_not_ge`, so kernel `decide` reduces it without any axioms.
This is the instance that closes the inserted cover examples. -/
instance instDecidableRelCovByOfFintype {V : Type*}
    [Preorder V] [DecidableLE V] [Fintype V] :
    DecidableRel (· ⋖ · : V → V → Prop) := fun a b =>
  haveI : DecidableRel (· < · : V → V → Prop) := fun x y =>
    decidable_of_iff (x ≤ y ∧ ¬ y ≤ x) lt_iff_le_not_ge.symm
  decidable_of_iff (a < b ∧ ∀ c : V, a < c → ¬ c < b) Iff.rfl

/-! ## The link model -/

/-- One candidate insertable fact.  `newText? = some t` means the candidate
passed the analysis-time verification gate and clicking inserts `t`;
`newText? = none` means it failed and renders as plain text with `note?`
explaining why. -/
structure InsertableFact where
  /-- Short display text of the fact (shown as the link/plain text). -/
  display : String
  /-- The verified insertion text (starts with `"\n"`: the example goes on a
  new line after the command).  `none` = not insertable. -/
  newText? : Option String := none
  /-- Why the candidate is not insertable (muted note next to the plain
  text). -/
  note? : Option String := none
  deriving Lean.ToJson, Lean.FromJson, Repr, BEq, Inhabited

/-- All insertable-example candidates of one panel.  `covers` is parallel to
`PosetData.coverPairs` (same order); the options are absent when the poset
has no bottom/top/witness — or when link building was skipped entirely
(`PanelLinks.empty`), in which case the panel shows no examples section. -/
structure PanelLinks where
  /-- One candidate per cover edge, in `coverPairs` order. -/
  covers : Array InsertableFact := #[]
  /-- The `⊥` badge candidate (`∀ x, b ≤ x`), when a bottom exists. -/
  bot? : Option InsertableFact := none
  /-- The `⊤` badge candidate (`∀ x, x ≤ t`), when a top exists. -/
  top? : Option InsertableFact := none
  /-- The non-lattice witness candidate, when the verdict is negative. -/
  witness? : Option InsertableFact := none
  deriving Lean.ToJson, Lean.FromJson, Repr, BEq, Inhabited

/-- No candidates at all: the panel renders exactly as the link-free panel. -/
def PanelLinks.empty : PanelLinks := {}

/-- Is there nothing to show (no candidates of any kind)? -/
def PanelLinks.isEmpty (l : PanelLinks) : Bool :=
  l.covers.isEmpty && l.bot?.isNone && l.top?.isNone && l.witness?.isNone

/-- Total number of candidates (insertable or not). -/
def PanelLinks.size (l : PanelLinks) : Nat :=
  l.covers.size + l.bot?.toArray.size + l.top?.toArray.size
    + l.witness?.toArray.size

/-! ## Statement/text builders (pure formatting; truth is the gate's job)

Each `…Prop` builder returns the proposition text; `exampleText` wraps it in
a self-contained `example : … := by decide`, and `insertionText` prefixes
the newline that puts it on its own line after the command.  The first
occurrence of every element label is type-ascribed to the user's original
type syntax, so the inserted example elaborates standalone. -/

/-- `({a} : {ty}) ⋖ {b}` — the cover-edge statement. -/
def coverProp (ty a b : String) : String :=
  s!"({a} : {ty}) ⋖ {b}"

/-- `∀ x : {ty}, ({b} : {ty}) ≤ x` — the bottom-element statement (phrased
without `OrderBot`; the table-derived bottom is just an element). -/
def botProp (ty b : String) : String :=
  s!"∀ x : {ty}, ({b} : {ty}) ≤ x"

/-- `∀ x : {ty}, x ≤ ({t} : {ty})` — the top-element statement. -/
def topProp (ty t : String) : String :=
  s!"∀ x : {ty}, x ≤ ({t} : {ty})"

/-- The concrete no-join fact for witness pair `a, b`: no common upper bound
is below all common upper bounds.  Spelled with quantifiers over `{ty}` so
`decide` can evaluate it (never with `Set`-based `IsLUB`). -/
def noJoinProp (ty a b : String) : String :=
  s!"¬ ∃ m : {ty}, (({a} : {ty}) ≤ m ∧ ({b} : {ty}) ≤ m) ∧ \
     ∀ u : {ty}, (({a} : {ty}) ≤ u ∧ ({b} : {ty}) ≤ u) → m ≤ u"

/-- The concrete no-meet fact for witness pair `a, b` (dual of
`noJoinProp`). -/
def noMeetProp (ty a b : String) : String :=
  s!"¬ ∃ m : {ty}, (m ≤ ({a} : {ty}) ∧ m ≤ ({b} : {ty})) ∧ \
     ∀ l : {ty}, (l ≤ ({a} : {ty}) ∧ l ≤ ({b} : {ty})) → l ≤ m"

/-- Wrap a proposition text in a self-contained example. -/
def exampleText (prop : String) : String :=
  s!"example : {prop} := by decide"

/-- The full insertion text: the example on a new line after the command. -/
def insertionText (prop : String) : String :=
  "\n" ++ exampleText prop

/-- The task-mandated note for labels that are not valid element syntax. -/
def notInsertableLabelNote : String :=
  "(not insertable: label is not valid syntax for the element)"

/-- The note for statements the gate could not verify (missing instances,
undecidable spelling, or the statement evaluating false). -/
def notVerifiedNote : String :=
  "(not insertable: could not verify the statement)"

/-- The note used when there are more cover edges than the gate will verify. -/
def tooManyCoversNote : String :=
  "(not insertable: too many cover edges to verify)"

/-- Verification cap: cover links are only attempted when the diagram has at
most this many cover edges (each candidate costs one compiled evaluation at
analysis time). -/
def maxLinkedCovers : Nat := 32

/-- Are cover links worth attempting for this poset?  (Pure mirror of the
cap check the gate applies.) -/
def coversLinkable (d : PosetData) : Bool :=
  d.coverCount ≤ maxLinkedCovers

/-! ## Panel assembly (pure; parameterized over the link renderer)

`mkLink display newText` produces the clickable element for a verified
candidate — the RPC layer passes a `MakeEditLink`-based renderer, tests and
headless dumps pass `plainLink`.  Everything else renders identically, so
the compile-time suite covers the real panel body without a live server. -/

/-- Non-clickable rendering of a verified candidate (tests/headless). -/
def plainLink (display : String) (_newText : String) : Html :=
  Render.el "code" #[] #[.text display]

/-- Render one candidate as a list item: a link (via `mkLink`) when
verified, otherwise plain text plus the muted note. -/
def insertableItem (kind : String) (f : InsertableFact)
    (mkLink : String → String → Html) : Html :=
  let head : Html := .element "span"
    #[("style", Render.css #[("color", Render.mutedColor), ("marginRight", "6px")])]
    #[.text kind]
  let rest : Array Html :=
    match f.newText? with
    | some t => #[head, mkLink f.display t]
    | none =>
      #[head, Render.el "code" #[] #[.text f.display],
        .element "span"
          #[("style", Render.css #[("color", Render.mutedColor), ("marginLeft", "6px")])]
          #[.text (f.note?.getD notVerifiedNote)]]
  .element "li" #[("style", Render.css #[("margin", "2px 0")])] rest

/-- The "insertable examples" caption section: one item per candidate, or
`none` when there are no candidates at all (so the link-free panel is
byte-identical to the pre-link panel). -/
def linksSection (links : PanelLinks) (mkLink : String → String → Html) :
    Option Html := Id.run do
  if links.isEmpty then
    return none
  let mut items : Array Html := #[]
  for f in links.covers do
    items := items.push (insertableItem "cover" f mkLink)
  if let some f := links.bot? then
    items := items.push (insertableItem "⊥" f mkLink)
  if let some f := links.top? then
    items := items.push (insertableItem "⊤" f mkLink)
  if let some f := links.witness? then
    items := items.push (insertableItem "witness" f mkLink)
  let title : Html := .element "div"
    #[("style", Render.css #[("fontWeight", "bold"), ("marginTop", "6px")])]
    #[.text "Insertable examples (click to insert after the command)"]
  return some <| .element "div"
    #[("style", Render.css #[("fontFamily", "monospace"), ("fontSize", "12px")])]
    #[title,
      .element "ul"
        #[("style", Render.css
            #[("margin", "4px 0 4px 16px"), ("padding", "0"), ("listStyle", "disc")])]
        items]

/-- The full interactive panel: SVG + caption exactly as `renderPanel`, plus
the insertable-examples section when there are candidates.  With
`PanelLinks.empty` this is byte-identical to `renderPanel` (pinned by
tests). -/
def renderPanelWith (d : PosetData) (highlight? : Option (Array Nat) := none)
    (updown? : Option Nat := none) (links : PanelLinks := .empty)
    (mkLink : String → String → Html := plainLink) : Html :=
  let l := layoutPoset d
  let base : Array Html :=
    #[Render.hasseSvg d l highlight? updown?,
      Render.captionBlock d highlight? updown?]
  Html.element "div"
    #[("style", Render.css #[("fontFamily", "sans-serif"), ("color", Render.fgColor)])]
    (base ++ (linksSection links mkLink).toArray)

end HasseView
