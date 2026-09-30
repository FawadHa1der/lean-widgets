# Expr X-Ray

An elaborated-expression inspector panel for the Lean 4 InfoView, built
with [ProofWidgets4](https://github.com/leanprover-community/ProofWidgets4)
(pure Lean, no custom JavaScript).

**The motivating scenario:** `rw` fails with *"motive is not type
correct"*. Both sides of your equation pretty-print identically — but the
elaborated terms carry **different `Decidable` instances** (say,
`instDecidableEqNat` on one side and `Classical.propDecidable` on the
other), invisible in default pretty-printing. Expr X-Ray makes exactly
this kind of hidden mismatch visible and ranks it first.

## What it does

- **Analyzer** — converts an elaborated `Expr` into an annotated tree:
  syntactic kind, truncated pretty string, inferred type (guarded, never
  fails), binder role of every application argument
  (explicit / implicit / strict-implicit / instance-implicit, classified
  via `Meta.getFunInfo`), universe levels on constants and sorts,
  coercion heads (`Meta.getCoeFnInfo?` + a known-heads list), `mdata`
  markers, and depth-limited construction with `elided` flags.
- **Diff engine** — walks two `Expr`s simultaneously (alpha-aware under
  binders via shared fresh fvars, `mdata`-transparent, mvars
  instantiated, descent bounded by a configurable depth cap — default
  128 — that degrades to a pinned `"subterm at the diff depth limit"`
  entry instead of blowing the recursion limit), classifies each
  mismatch (`differentConst` / `differentUniverse` /
  `instanceArgMismatch` / `implicitArgMismatch` / `explicitArgMismatch`
  / `binderMismatch` / `structural`), prunes ancestor-level entries
  subsumed by a deeper entry on the same spine (one changed leaf yields
  one difference site, not one entry per enclosing level), and ranks
  the rest: within each defeq group **instance arguments first**, then
  universes, then implicits, then the rest. Explicit-argument sites are
  numbered among the *explicit* arguments (`explicit argument #2 of
  HAdd.hAdd` for the second visible operand of `+`); instance/implicit
  sites keep the absolute spine position (the index you would use in an
  `@`-application). The two shown sides are truncated *around their
  first differing character* when they share a long prefix, so
  truncation never collapses two different strings into the same
  display (the delaborator's own deep-term elision can still make both
  sides print identically for ultra-deep subterms — see LIMITATIONS).
  Produces one-line summaries such as

  ```
  instance argument #3 of ite differs: instDecidableEqNat 2 2 vs Classical.propDecidable (2 = 2) (NOT defeq — this blocks rw)
  ```
- **Defeq-aware diff** — every recorded mismatch is additionally checked
  with `Meta.isDefEq` *in the local context of the mismatch site*, first
  at reducible transparency, then at default transparency
  (`defeqReducible` / `defeqDefault` / `notDefeq` / `checkFailed`). Each
  check is wrapped in `withoutModifyingState` + `withNewMCtxDepth`, so
  metavariable assignments made during unification can never leak
  (diffing is pure: rerunning it yields identical results). Sides that
  contain unassigned metavariables (routine after `apply`/`induction`,
  or when elaborating a bare `id`) are *never* sent to `isDefEq` —
  under `withNewMCtxDepth` they would come back "not defeq" even when
  trivially unifiable — and instead get the honest `undetermined`
  status: `(defeq undetermined — contains metavariables)`, badge `≟ₘ`.
  The annotation drives the ranking — everything **not certified**
  defeq (including failed and undetermined checks) before everything
  defeq, so a harmless syntactic difference never steals the headline
  from the mismatch that actually blocks `rw`/`exact` — and the
  summaries: each line carries its annotation, and when *every*
  mismatch is defeq the headline becomes

  ```
  N mismatches, all definitionally equal — the discrepancy is syntactic only (defeq-transparent tactics like exact will succeed; syntactic tactics like rw may still fail)
  ```
- **Renderer** — `ProofWidgets.Html` built from nested
  `<details>/<summary>` elements (native browser expand/collapse — no
  custom JS). Explicit arguments look normal; implicit arguments are
  dimmed; instance arguments are dimmed with an `[inst]` badge; coercion
  heads get a `↑coe` badge; universe levels render small after constant
  names. Compare mode shows both trees side by side with mismatching
  nodes highlighted and the ranked summary list on top.
- **pp.explicit section** — the expression printed with
  `pp.explicit := true` (and a second copy with `pp.universes := true`)
  as selectable text.

## What you actually see

Placing the cursor on a `#xray` command opens a widget panel in the
InfoView containing five collapsible sections:

1. **clean (explicit only)** *(open by default)* — the tree with all
   implicit and instance arguments filtered out,
2. **+implicit** — adds dimmed implicit arguments,
3. **+instances** — adds dimmed `[inst]`-badged instance arguments,
4. **everything (with universes)** — everything plus `.{u}` level
   suffixes,
5. **pp.explicit** — the fully explicit pretty-printed term as
   selectable text (plus a `pp.universes` copy).

Every tree node is a `<details>` disclosure triangle showing
`kind ‹pretty string› : type` with its badges; click to fold/unfold.
The four "presets" are four pre-filtered copies of the tree — there are
no interactive checkboxes (that would require custom JS, which is out of
scope by design).

`#xray_diff` (and two shift-click selections in the panel) shows a
ranked list of mismatch descriptions followed by the two trees side by
side; differing nodes carry a red-tinted background and a bold `≠` badge.
Every summary line starts with a defeq badge — red `≢` (not defeq),
`≟` (check failed) or `≟ₘ` (undetermined: a side contains
metavariables), green `≈ʳ`/`≈ᵈ` (defeq at reducible/default
transparency) — and when all mismatches are defeq a green banner states
that the discrepancy is syntactic only.

## Usage in VS Code

Open any file importing `ExprXRay` (e.g. `ExprXRay/Demo.lean`) with the
InfoView visible.

```lean
import ExprXRay
open ExprXRay

-- inspect one expression: cursor on the command
#xray (1 + 1 : Nat)

-- deterministic text dump additionally logged as an info message
#xray (text := true) ((3 : Nat) : Int)

-- compare two expressions
#xray_diff @ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0,
           @ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0

-- the InfoView panel inside a proof
example (n : Nat) : n = n := by
  with_panel_widgets [XRayPanel]
    rfl
```

Panel behavior (cursor inside the tactic block):

- **0 selections** → x-rays the main goal's target (term-mode goals are
  also supported);
- **1 shift-click selection** (in the goal or a hypothesis) → x-rays that
  subterm;
- **2 selections** → compare mode with the ranked mismatch list;
- more → a polite request to select fewer.

## Building and testing

```sh
lake build   # builds the library incl. Demo.lean (demos elaborate on every build)
lake test    # builds the test suite; any failing assertion fails the build
```

Toolchain: `leanprover/lean4:v4.32.2` (pinned in `lean-toolchain`),
ProofWidgets pinned in the lockfile. No npm/node required.

## Architecture

```
ExprXRay.lean              -- root: imports everything below
ExprXRay/
  Types.lean               -- XKind, BinderRole, XRayConfig, XNode (+ pure tree helpers)
  Analyze.lean             -- Expr → XNode in MetaM; coercion detection; pp.explicit strings
  Diff.lean                -- MismatchKind, Mismatch, DefeqStatus, checkDefeq, exprMatches,
                           --   diffExprs, defeq-aware ranking, summaries
  Render.lean              -- XNode → Html; presets; compare mode; Html.toStringCompact; XNode.toText
  Widget.lean              -- #xray / #xray_diff commands; XRayPanel (mk_rpc_widget% RPC panel)
  Demo.lean                -- realistic examples, incl. the motivating instance-mismatch pair
ExprXRayTests.lean         -- root: imports all test modules
ExprXRayTests/
  TestUtil.lean            -- elabT + throwing assert helpers
  TypesTests.lean          -- pure #guard tests
  AnalyzeTests.lean        -- roles, kinds, universes, coercions, depth limiting
  DiffTests.lean           -- ≥15 curated pairs, ranking, exact summaries, cross-consistency
  DefeqTests.lean          -- defeq statuses on curated pairs, re-ranking, purity, badges
  RenderTests.lean         -- serialized-Html assertions: badges, dimming, preset filtering
  WidgetTests.lean         -- message-exact #guard_msgs tests for the text modes
  EdgeTests.lean           -- mvars, Prop vs Type, deep chains vs the analyzer's
                           --   and the diff's depth guards (600-deep regression)
```

Paths: diff mismatch paths use `XNode` child numbering (application head
= child 0, argument *i* (1-based) = child *i*; binders: domain 0 /
body 1; `let`: type 0 / value 1 / body 2) except that `mdata` wrappers
contribute **no** step to diff paths; `markMismatches` re-inserts the
`mdata` hops when mapping paths back onto analysis trees.

## LIMITATIONS (honest)

- **No interactive view toggles.** The four presets are four statically
  rendered copies of the tree in separate `<details>` sections. A single
  tree with live checkboxes would need custom JavaScript, which this
  package deliberately avoids. For large expressions the panel is
  therefore up to 4× the tree size.
- **Instance-argument diffs are reported whole.** The diff engine does
  not descend *inside* a differing instance argument (the instance names
  are the story); other argument kinds are descended into. Ancestor
  entries subsumed by a deeper entry are pruned, but a mismatch that is
  localized at one site can still appear twice *at the same path*: once
  with its arg-level classification and once as its leaf-level
  `structural` refinement (e.g. `Nat.zero` vs `Nat.zero.succ` appears
  as `explicitArgMismatch` and as `structural`). Read the top-ranked
  entry.
- **Numerals hide instances.** Comparing `f 1` and `f 5` also reports
  `OfNat` instance mismatches inside the numeral elaborations
  (`instOfNatNat 1` vs `instOfNatNat 5`), which rank above the literal
  difference. This is technically correct but can surprise; it is pinned
  by tests as intended behavior.
- **`Expr.eqv`-level alpha care, custom comparator.** Equality inside
  the diff uses a custom `exprMatches` (alpha-aware, `mdata`-blind,
  binder-annotation-sensitive). It compares universe levels
  *syntactically*, so `Level` terms equal only up to normalization are
  still recorded as `differentUniverse` — but the defeq annotation
  redeems them: `isDefEq` normalizes levels, so such a mismatch is
  reported as defeq (e.g. `Sort (max 1 2)` vs `Sort 2`, pinned by test).
- **Defeq checks cost time and can time-out like any `isDefEq`.** Each
  mismatch triggers up to two `Meta.isDefEq` calls (reducible, then
  default transparency). On adversarial pairs these can be slow or hit
  `maxRecDepth`/heartbeats; such failures — including *runtime*
  exceptions, which need `tryCatchRuntimeEx` rather than a plain
  `try/catch` — are caught and reported as `checkFailed` (ranked with
  the blocking group), never propagated.
- **Mismatches involving metavariables are never certified either
  way.** `checkDefeq` refuses to consult `isDefEq` when a side contains
  unassigned mvars (the leak-proof wrapper would make every such answer
  a false "not defeq") and reports `undetermined`. The cost: a
  mvar-containing pair that genuinely is *not* unifiable is also only
  reported `undetermined`, not `NOT defeq`.
- **Diff descent is capped** at `diffExprs`' `maxDepth` (default 128,
  configurable per call). Deeper single differences are reported as one
  pinned `structural` entry with site `"subterm at the diff depth
  limit"` and status `checkFailed` instead of being localized further.
  Additionally, the internal alpha-aware comparator is fuel-bounded
  (256 levels, falling back to `Expr.eqv`): a binder-annotation-*only*
  difference nested deeper than the fuel may be missed, and pretty
  strings of extremely deep subterms may degrade to `⟨pp failed⟩` when
  the delaborator itself gives up. The diff-aware truncation window
  guarantees the *truncation* never hides the difference between two
  distinct pretty strings — but for ultra-deep subterms the
  delaborator's own deep-term elision (`⋯`) can make both sides'
  *full* pretty strings coincide, in which case the shown pair looks
  identical and only the site/path (and the companion depth-limit
  entry) localize the difference.
- **Cross-goal comparison is best-effort.** Comparing two panel
  selections from *different* goals/contexts diffs the raw second
  expression in the first selection's context; fvars from the other
  context may pretty-print as internal names. Same-goal comparisons are
  fully supported.
- **`getFunInfo` fallback.** If function information cannot be computed
  for an application head (rare, e.g. ill-typed terms), argument roles
  default to `explicit`.
- **Depth/size guards, not streaming.** Very large expressions are cut
  at `maxDepth` (default 32) with `elided` markers; there is no lazy
  loading of deeper nodes. `#xray` always uses the default config; use
  the `ExprXRay.analyzeExpr` API directly for custom depths.
- **Coercion detection is head-based.** Only heads registered via
  `@[coe]` or on a small known-heads list are flagged. Structure-eta
  coercions, `Sort`-coercions realized through other elaboration
  mechanisms, or user coercions not registered with `@[coe]` are not
  flagged.
- **The panel needs a ProofWidgets-aware InfoView** (VS Code extension /
  recent lean4 extension). The `(text := true)` modes exist precisely so
  behavior stays testable and usable without a UI.
- **No screenshots in this README** because none were taken; the
  descriptions above state exactly what is rendered.
