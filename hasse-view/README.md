# HasseView

`#hasse V` draws the **Hasse diagram** of a finite ordered type `V` in the
Lean 4 InfoView (answering the Mathlib Zulip request for a Hasse-diagram
widget open since January 2022): elements layered by rank with minimal
elements at the **bottom** (the classical convention), cover edges pointing
upward, `⊥`/`⊤` and atom/coatom badges, and a caption with the lattice
verdict (with a concrete witness pair when negative), the height, an
antichain-width lower bound, and honest warnings whenever the extracted
relation is not actually a partial order — plus **click-to-insert example
links** (see Interactivity below) for the cover edges, the `⊥`/`⊤` facts,
and the non-lattice witness.

```lean
import HasseView

#hasse (Finset (Fin 3))          -- the powerset cube under ⊆ (needs
                                 -- Mathlib.Data.Fintype.Powerset; import
                                 -- Mathlib.Data.Finset.Sort for {0, 1} labels)
#hasse (Fin 5)                   -- a chain
#hasse (Bool × Bool)             -- componentwise product order
#hasse (text := true) (Fin 5)    -- deterministic ASCII report instead of HTML

#hasse (Finset (Fin 3)) updown 1        -- shade ↑{0} and ↓{0}, emphasize {0}
#hasse (Fin 5) highlight [0, 4]         -- rings on elements 0 and 4
#hasse (Fin 5) highlight [0] updown 2   -- clauses in either order
```

Requirements on `V`: `[Fintype V]`, `[DecidableEq V]`, `[LE V]`, and a
computable `[DecidableLE V]` (in v4.34.0 `DecidableLE` is a reducible
abbreviation of `DecidableRel (· ≤ ·)`, so either spelling of the instance
works).  Missing or `noncomputable` instances (including the
`Classical.propDecidable` fallback under `open scoped Classical`) are
rejected with errors naming the exact instance; `HasseView/Demo.lean` shows
the idiomatic local-instance fixes (`decidable_of_iff` for a hand-written
order, `Fintype.subtype`/`inferInstanceAs` for a subtype such as the
divisors of 12 under divisibility).

Overlay clauses take **element indices** — positions in the `Fintype`
enumeration, shown implicitly by the drawing order (for `Fin n` the elements
themselves; for `Finset (Fin k)` bitmask order, e.g. index 5 = `{0, 2}`).

## Interactivity: click-to-insert examples

The panel is no longer display-only: it uses ProofWidgets' **`MakeEditLink`**
component (its bundled JavaScript ships with ProofWidgets; this package still
writes none of its own).  Below the caption, an *insertable examples* section
lists one candidate per link kind; clicking a link inserts a self-contained
example on a **new line after the `#hasse` command** (a zero-width edit — it
never replaces anything you wrote) and moves the cursor to its end:

* **cover edges** — `example : (a : V) ⋖ b := by decide`, one per drawn
  edge.  `⋖` closes by `decide` thanks to
  `HasseView.instDecidableRelCovByOfFintype` (`Preorder` + `DecidableLE` +
  `Fintype`, exported by this package — Mathlib's pin only has the `Bool`
  instance); requiring a `Preorder` makes `<` lawfully the strict part of
  `≤`, which is exactly the relation the diagram draws.
* **`⊥`/`⊤` badges** — `example : ∀ x : V, b ≤ x := by decide` (dual for
  `⊤`), deliberately phrased *without* `OrderBot`/`OrderTop` (the type may
  lack those instances; the table-derived bottom is just an element).
* **non-lattice witness** — the caption's witness pair as a concrete
  no-join (or no-meet) fact, spelled with decidable quantifiers over `V`
  (never `Set`-based `IsLUB`, which `decide` cannot evaluate).

`V` is spelled in inserted text exactly as you wrote it in the command.

**The round-trip honesty gate** (`HasseView/Gate.lean`): a candidate becomes
a link only when, at elaboration time, (1) every `Repr`-made element label
**parses, elaborates at `V`, and is `DecidableEq`-equal to the enumerated
element it labels** — a label that parses to a *different* value would
produce a compiling-but-wrong example, so it is rejected — and (2) the exact
statement to be inserted **evaluates to `true`** through a synthesizable,
computable `Decidable` instance.  Candidates that fail render as plain text
with a muted note (e.g. `(not insertable: label is not valid syntax for the
element)`); the `Div12` demo shows this fallback live (its numeral labels
have no `OfNat Div12`).  Cover links are attempted only up to 32 edges
(each verification is a compiled evaluation).

**How links get document context**: `MakeEditLink` needs the file's
uri/version, which only the language server knows.  The command stores plain
props (poset, overlays, gate-verified texts, insertion range) via
`savePanelWidgetInfo`; the `HassePanel.rpc` method (`mk_rpc_widget%`) reads
the authoritative `DocumentMeta` in `RequestM` at render time and wraps the
stored texts in `MakeEditLink`s.  The panel body itself is the pure
`renderPanelWith`, so the compile-time suite serializes the real panel —
component nodes, edit texts and fallbacks — without a live server.

## Architecture

| Module | Contents |
| --- | --- |
| `HasseView/Model.lean` | Pure `PosetData` (`n`, full `≤` table, labels) and everything computed from it: strict order, **covering relation**, minimal/maximal, `bot?`/`top?`, atoms/coatoms, ranks/height (longest cover-chain), rank layers with `maxLayerSize` as an antichain lower bound, lattice analysis (`joinOf?`/`meetOf?`, verdict with concrete witness pair), upsets/downsets, and validity checkers (reflexivity/antisymmetry/transitivity with counterexamples). All `#guard`-testable. |
| `HasseView/Extract.lean` | The only impure layer: elaborates the type, synthesizes the four instances (curated errors; noncomputable instances rejected), enforces the 64-element cap **before** evaluating any `≤`, self-checks the enumeration for duplicates, evaluates the table row by row with `Core.checkSystem` between rows, labels via `Repr` (index fallback). |
| `HasseView/Layout.lean` | Exact-ℚ layered layout: one row per rank, even spacing in enumeration order, all coordinates integer-valued `Rat`s, byte-deterministic. Layout `y` grows with rank; the renderer flips it so rank 0 is at the bottom. |
| `HasseView/Render.lean` | Theme-aware SVG (rounded labeled boxes, upward cover edges, badges, highlight rings, upset/downset shading), caption block, deterministic `textReport`, `htmlToDebugString` (components serialize with their props JSON), `reactContractViolations`, `css` (React style objects — never CSS strings). |
| `HasseView/Links.lean` | Pure link layer: `InsertableFact`/`PanelLinks`, the statement/text builders (`coverProp`, `botProp`, `topProp`, `noJoinProp`, `noMeetProp`, `insertionText`), the `⋖` decidability instance, and `renderPanelWith` — the panel body parameterized over the link renderer (plain for tests/headless, `MakeEditLink` for the RPC panel). |
| `HasseView/Gate.lean` | The analysis-time honesty gate: `labelRoundTrips` (parse → elaborate → `DecidableEq`-equal to the enumerated element, via the extractor's `evalExpr` bridge), `statementHolds` (elaborate at `Prop`, synthesize a computable `Decidable`, evaluate `true`), `buildLinks`. Silent on failure (plain-text fallback), state-isolated, interrupts propagate. |
| `HasseView/Widget.lean` | The `#hasse` command: `(text := true)` mode, `highlight [..]` / `updown i` clauses in any order (duplicates rejected); stores `HassePanelProps` via `savePanelWidgetInfo` and renders through the `HassePanel.rpc` method (`mk_rpc_widget%`), which adds `MakeEditLink` document context at render time. |
| `HasseView/Demo.lean` | The powerset cube, divisors of 12 (local instances; the gate's plain-text fallback demo), `Fin 5`, `Bool × Bool`, the non-lattice bowtie (witness caption; `Preorder`/`OfNat` instances so its cover links verify), overlay demos. |
| `HasseViewTests/` | 463 compile-time assertions (plus 11 statically compiled generated-example texts): hand-computed pins (covers, ranks, lattice verdicts, layout coordinates, byte-exact text reports, SVG fragments), crafted invalid tables, React-contract checks over every real panel (links included), `#guard_msgs` pins of every user-facing message, cross-implementation property checks (`#assert_poset_invariants`, `#assert_extracts_to`), and the link audit: byte-exact builder pins, round-trip/statement gate unit tests (positive and negative), `#links_report` pins of the full gate verdict, `#compile_insertions` (every offered insertion text is parsed and elaborated — an offered example that does not prove fails the build), and serializer pins of `MakeEditLink` component nodes with their exact edit texts. `ClickE2E.lean` adds 114 end-to-end click-simulation assertions: realistic user files are compiled **in-process through Lean's own frontend**, the stored `HassePanelProps` payload (insertion range + verified texts) is read back from the info tree, the click is applied with the language server's own `replaceLspRange` (UTF-16 pins with `ℝ`/`⋖`/emoji/surrogate-pair type names), and the edited file is recompiled and must produce zero messages — with negative tests (corrupted `newText`, shifted range) proving the harness fails loudly. |

## Design decisions

* **Strict order** is taken as `a ≤ b ∧ ¬ b ≤ a` (the strict part). For a
  genuine poset this is the usual `<`; for a non-antisymmetric preorder it
  quotients 2-cycles away so covers/ranks stay well-defined **while the
  caption warns** — a preorder is reported, never silently drawn wrong.
* **Height** counts *cover steps*: a 5-element chain has height 4 (the
  caption also states the chain length in elements).
* **Rank** = longest cover-path from a minimal element, computed by bounded
  relaxation (terminates even on adversarially invalid tables).
* The lattice verdict scans pairs `i < j` in lexicographic order, join
  before meet, and reports the **first** failure with the actual pair — the
  bowtie demo prints `not a lattice: 1, 2 have no join`.

## Limitations (honest)

* **Hard cap of 64 elements**, enforced before any `≤` evaluation. Beyond
  the cap the command refuses (the analysis is `O(n³)` per transitivity
  check and cover computation).
* **A single `≤` decision is unbounded user code.** Interrupt checks run
  only *between* table rows; one pathological `Decidable` instance can
  still stall a row.
* **Antichain width is only a lower bound** (the largest rank layer). The
  exact width is a Dilworth/matching computation and is not implemented;
  the caption says exactly that.
* **No barycenter refinement**: rows are laid out in plain enumeration
  order, so wide posets can show more edge crossings than necessary.
* **Cover edges are straight lines.** A cover may span several ranks
  (`a ⋖ b` with `rank b > rank a + 1` happens, e.g. `b` also covers a long
  chain), and such a line can pass through boxes of intermediate rows.
  No edge routing is attempted.
* **Node boxes have fixed width (84 px).** Long `Repr` labels (e.g.
  `(false, false)`) can overflow the box; the label halo keeps them
  legible, but they are not truncated or measured.
* **Element indices come from the `Fintype.elems` enumeration.** They are
  deterministic but instance-defined (bitmask order for `Finset (Fin n)`,
  ascending for `Nat.divisors`-based subtypes); overlays address elements
  by these indices, not by terms.
* **Equivalent elements of a preorder are not merged**: a 2-cycle renders
  as two incomparable-looking boxes plus an antisymmetry warning.
* Colors use VS Code CSS variables with fixed fallbacks; other InfoView
  hosts get the fallback palette.
* Labels rely on a computable `Repr`; without one, elements are labeled by
  index (`Finset` labels additionally need `Mathlib.Data.Finset.Sort` in
  scope at the `#hasse` call site — otherwise you get index labels).
* **Link verification runs compiled code; the inserted `by decide` runs in
  the kernel.** For lawful instances these agree; a pathological instance
  (e.g. well-founded recursion the kernel will not reduce) could make an
  inserted example fail to *compile* — visibly — but the gate guarantees it
  can never state a falsehood. The demo types are all compile-verified in
  the suite.
* **Cover links stop at 32 edges** (each candidate costs one compiled
  evaluation at elaboration time); beyond that, cover candidates carry an
  honest "(not insertable: too many cover edges to verify)" note. `⊥`/`⊤`
  and witness links are unaffected.
* **Links live in the caption's "insertable examples" list, not on the SVG
  geometry itself.** Wrapping SVG `<line>` elements in `MakeEditLink`
  anchors is untested territory in the InfoView's React/SVG namespace
  handling, and thin lines make poor click targets; the list keeps every
  candidate visible, clickable and testable.
* The inserted example's `by decide` needs `HasseView` imported at the
  insertion site (for `instDecidableRelCovByOfFintype`) — true by
  construction wherever `#hasse` elaborates.

## Verifying

```sh
lake build   # library + demos (every #hasse in Demo.lean elaborates)
lake test    # 463 compile-time assertions (incl. the ClickE2E click simulation)
```

Pinned toolchain: `leanprover/lean4:v4.34.0` with Mathlib `v4.34.0`
(`5ed29652`) and the ProofWidgets rev from Mathlib's manifest (`106ff4fa`);
see `PORT-NOTES.md` for the port from v4.32.2.

Assertion census (how the 463 is counted): lines starting with `#guard`,
`#guard_msgs`, `#assert_*` or `#compile_insertions` in `HasseViewTests/` and
`HasseViewTests.lean`, excluding `ClickE2E.lean` — 282 + 29 + 33 + 5 = 349 —
plus `ClickE2E.lean`'s 114: its 12 `#guard` lines, the 98 `check`/`checkEqStr`
calls its two `#eval` suites execute, and 4 `let some … | throw` payload
assertions. The 11 `example : … := by decide` lines in `LinkTests.lean` (the
statically written-out insertion texts) and the 3 `#links_report` commands
(each already counted through its `#guard_msgs` pin) are not double-counted.

Known cosmetic warts of inserted examples (pinned by `ClickE2E`, all
compile): a parenthesized `#hasse (T)` argument reproduces its parens in the
ascriptions (`(∅ : (Finset (Fin 3)))` — the verbatim-user-syntax contract);
the witness example is one long line; a trailing comment on the `#hasse`
line ends up trailing the inserted example (the command's range ends before
the comment), where it remains a harmless comment; and sequential clicks all
insert at the same zero-width command-end position, so examples appear in
reverse click order (the newest directly under the command).
