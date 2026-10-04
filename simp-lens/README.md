# Simp Lens

A `simp`-call inspector for the Lean 4 InfoView: a **filmstrip of every
rewrite** a `simp` call performs (with full `at h` / `at h ⊢` / `at *`
location support, one filmstrip section per location), a **minimal
`simp only [...]` generator** with a one-click `Try this:` suggestion, and
**exclusion previews** showing where the goal lands when each used lemma is
removed.

Motivating scenario: review asks you to squeeze `simp` into `simp only [...]`.
Replace `simp` with `simp_lens`, look at which lemmas actually fired (in
order, with before/after for each rewrite), and click the suggestion to insert
the minimal call.

Built for `leanprover/lean4:v4.34.0` with
[ProofWidgets4](https://github.com/leanprover-community/ProofWidgets4)
(rev `106ff4fa`, pure-Lean `Html` DSL — no npm/JS build). Ported from the
v4.32.2 original; see `PORT-NOTES.md` for the (small) diff.

## What you actually see

Put the cursor on a `simp_lens` call in VS Code. The InfoView shows:

* the usual messages panel with a clickable **`Try this: simp only [...]`**
  suggestion (also available as a code action / lightbulb); clicking it
  replaces the `simp_lens` call in the file with the minimal call — for
  location calls the clause is preserved verbatim (`simp only [...] at h ⊢`),
  exactly like `simp?`, and the lemma list is the union over all locations;
* a collapsible **Simp Lens** panel (a `<details>` block rendered by
  `ProofWidgets.HtmlDisplayPanel`) containing:
  * a header line — total rewrite count and a ✓ when the goal was closed;
  * the **minimal call** as text;
  * the filmstrip — for location calls **one section per location** (headed
    `at h` / `at ⊢`, with a per-section rewrite count and a
    `✓ closes the goal` marker on the location that closed the goal, e.g. a
    hypothesis that simplified to `False`); target-only calls keep the
    original sectionless layout;
  * one **numbered frame per rewrite** inside each section: a badge with the
    lemma / simproc / hypothesis that fired, the simplifier phase
    (`pre`/`post`), a `(+n side-condition lemmas)` marker when discharging was
    involved, and the rewritten **subterm** before → after. The expressions
    are rendered with `Widget.ppExprTagged` + `InteractiveCode`, so hovering
    shows types and go-to-definition works. Very long films render the first
    100 frames and summarize the rest in a note (the trace itself is
    complete). A location that changed with no lemma-driven rewrite (pure
    beta/zeta/eta/proj reduction) is labeled **"definitional reductions
    only"** — the header never claims a bare "0 rewrites" for a run that
    visibly moved the goal;
  * **Exclusion previews** in nested `<details>` rows: for each used lemma
    (capped at 12, truncation noted), where the re-run *at the same locations*
    lands when that lemma is erased from the simp set, marked `● essential`
    (landing changes) or `○ redundant` (same landing — the default simp set
    had another route). The reported landing state is the target's when the
    target is among the locations, otherwise the first hypothesis the original
    run changed (the row label says which). A re-run that blows its heartbeat
    sub-budget shows as `⏱ timed out` ("preview unavailable — the call may be
    much slower, or diverge, without this lemma"; usually the sign of a
    normalization workhorse), a re-run that fails outright as `⚠ errored` —
    neither ever fails the tactic. Previews can be skipped entirely with
    `simp_lens -previews`;
  * a **Diagnostics** section (tried vs. used counts per lemma) — only when
    the run happened under `set_option diagnostics true`.

There are no screenshots in this repo; the description above is exactly what
`SimpLens/Demo.lean` produces.

## Usage

```lean
import SimpLens

example (n : Nat) (l : List Nat) : n + 0 = n ∧ l ++ [] = l := by
  simp_lens [Nat.add_zero, Nat.zero_add, List.append_nil, List.map_cons,
             Nat.mul_one, and_true]
  -- InfoView: filmstrip; message: Try this: simp only [Nat.add_zero, List.append_nil, and_self]
```

`simp_lens` accepts the same syntax as `simp`, **including locations**:

```lean
simp_lens                                -- plain (goal target)
simp_lens [foo, ← bar, -baz, h, *]       -- lemma lists, reversed lemmas, erasure, hyps, star
simp_lens only [foo]                     -- only-mode
simp_lens (failIfUnchanged := false)     -- any simp config
simp_lens (disch := assumption)          -- custom discharger
simp_lens at h                           -- a hypothesis
simp_lens at h₁ h₂ ⊢                     -- several hypotheses and/or the target
simp_lens at *                           -- all non-dependent prop hypotheses + target
simp_lens only [foo] at h                -- everything combines
simp_lens -previews                      -- skip exclusion previews (near-1x cost;
                                         -- also: (previews := false))
```

It performs the simplification *identically* to `simp` (see Architecture):
same rewrites and resulting hypotheses/goal at every location, hypotheses
that simplify to `False` close the goal, progress at *any* location counts,
it fails with the byte-identical `` `simp` made no progress `` error when
no location changes, and supplied-but-unused lemmas get the same
`linter.unusedSimpArgs` warning (with the same `[apply] simp` hint — the
linter's one-click fix rewrites the call as the equivalent plain `simp`; on
v4.32.2 the same hint rendered as a strike-through diff) plain `simp`
emits.

### Cost containment

The traced run executes under the ambient heartbeat budget, exactly like
`simp` — if `simp` would time out, so does `simp_lens`, with the same error.
Everything `simp_lens` *adds* is **heartbeat-neutral**: exclusion previews,
the suggestion, and the panel rendering restore the global heartbeat counter
afterwards and cannot trip the surrounding command's budget, so `simp_lens`
succeeds wherever `simp` does (pinned by twin tests at deliberately tight
`maxHeartbeats`, including a slow-discharger scenario). Each exclusion
preview additionally runs under its own sub-budget derived from the traced
run's measured cost — removing a lemma can change the complexity class of
the re-run, and heartbeat exceptions are *runtime* exceptions that a plain
`catch` would rethrow, so previews contain them via `tryCatchRuntimeEx` and
report a `⏱ timed out` row instead of failing the tactic. Wall-clock
overhead of the previews remains (up to 12 budgeted re-runs); `-previews`
removes it.

## Building & testing

```sh
lake build   # library + demos (demos elaborate on every build)
lake test    # builds the SimpLensTests test driver; any assertion failure fails the build
```

The tests are compile-time assertions: `#guard` for pure functions,
`#guard_msgs` for exact tactic messages, and custom `#lens_*` / `#lens_at_*`
commands that run the pipeline and `throwError` on any mismatch (exact
used-lemma lists, per-location step counts and films, per-frame origin +
before/after strings, landing goals *and hypotheses*, generated `simp only`
text with location clauses, equivalence against real `simp` execution —
including full local-context comparison for location runs — exclusion
landings, contained preview statuses under explicit heartbeat sub-budgets,
timeout-parity twins at deliberately tight `maxHeartbeats`, definitional-only
detection, render frame-cap truncation, diagnostics counters, and
chain-consistency invariants).

Assertion census (lines starting with a `#guard` / `#guard_msgs` / `#lens_*` /
`#e2e_*` command across `SimpLens*/` and the two root modules): **404** —
identical to the v4.32.2 original. The `#e2e_*` commands in
`SimpLensTests/ClickE2E.lean` each run several internal checks (the
recompile-and-diff harness), so the effective check count is higher.

## Architecture

```
SimpLens/
  Trace.lean     -- tracing engine: wraps Simp.Methods (pre/post/dpre/dpost);
                 -- records one TraceStep (origins, subterm before/after,
                 -- phase, discharge depth, location tag) per successful
                 -- rewrite; traceSimpTarget = simpTarget with wrapped
                 -- methods; traceSimpGoal = a statement-by-statement mirror
                 -- of core Meta.simpGoal (the `simp at ...` engine) with
                 -- per-location step capture
  Film.lean      -- Frame/Film: ordered depth-0 steps + programmatically
                 -- checkable chain-consistency invariants; LocFilm = one
                 -- filmstrip section per location
  Minimize.lean  -- UsedSimps -> minimal `simp only [...]`; reuses core's
                 -- Lean.Elab.Tactic.mkSimpOnly (the `simp?` machinery, which
                 -- preserves location clauses); OriginClass classifies
                 -- representability of each origin
  Exclude.lean   -- re-run the same simp (at the same locations) with one
                 -- origin erased (SimpTheoremsArray.eraseTheorem /
                 -- SimprocsArray.erase), on a fresh copy of the goal;
                 -- capped at 12 previews, each contained via
                 -- tryCatchRuntimeEx under its own heartbeat sub-budget
                 -- (PreviewStatus: ok / errored / timedOut) and the whole
                 -- phase heartbeat-neutral (withHeartbeatsNeutral)
  Render.lean    -- ProofWidgets Html filmstrip (JSX DSL, InteractiveCode),
                 -- one section per location
  Tactic.lean    -- `simp_lens` tactic: rebuilds a genuine `simp` syntax tree
                 -- (location clause included), feeds it to core
                 -- mkSimpContext, resolves locations like core simpLocation,
                 -- runs the traced simp, emits the TryThis suggestion,
                 -- attaches the panel widget
  Demo.lean      -- realistic examples, pinned with #guard_msgs
SimpLensTests/   -- Helpers (assertion commands) + Film/Trace/Minimize/
                 -- Equiv/Exclude/Tactic/Location test modules
```

### How tracing attributes origins (the interesting bit)

Core `simp` calls `recordSimpTheorem` exactly when a rewrite succeeds,
inserting into the insertion-ordered, **idempotent** `State.usedTheorems`
map. A plain diff would therefore miss repeated firings of the same lemma.
The tracer *resets* `usedTheorems` to `{}` around each wrapped
`pre`/`post`/`dpre`/`dpost` call and merges the fresh entries back in order
afterwards. Because insertion is idempotent and order-preserving, the final
map is provably identical to an un-instrumented run (asserted by the
equivalence tests), while the fresh part yields the exact origins that fired
during that one step — side-condition (discharge) lemmas first, the principal
rewrite last.

Behavioral identity with `simp` comes from reuse, not reimplementation: the
tactic rebuilds a genuine `simp` syntax tree from its arguments (location
clause included) and hands it to core's `mkSimpContext`; locations resolve
exactly like core `simpLocation` (`getFVarIds` for named hypotheses,
`getNondepPropHyps` for `*`); the run itself is core's `Simp.mainCore` with
the default methods wrapped (the wrapper only observes and forwards), driven
by a statement-by-statement mirror of core `Meta.simpGoal` — same per-
hypothesis simp-set erasure, same `Simp.Stats` threading across locations
(union used set, fresh cache per location), same replace/assert/clear
hypothesis logic, same goal-closing on `False` hypotheses; suggestions come
from core's `mkSimpOnly`.

## LIMITATIONS (honest)

* **`simp_all` is not wrapped.** `simp_all` is separate tactic syntax with
  different semantics (hypotheses feed each other's simp sets, iterated to a
  fixpoint) — a `simp_all`-shaped call is a parse error for `simp_lens`, not
  silent misbehavior. In particular `simp_lens at *` has plain `simp at *`
  semantics, *not* `simp_all`'s: a goal `simp_all` closes can still be
  "no progress" for `simp_lens at *` (this parity is pinned by twin tests).
* **Frames show the rewritten subterm, not the whole goal.** `simp` rewrites
  bottom-up inside congruence closures; the whole goal does not exist as a
  term when an inner rewrite fires, so per-step whole-goal states cannot be
  captured at the `Methods` level without replaying rewrites. Each frame
  shows the exact subterm before/after; the panel header shows the final
  outcome. (Whole-goal intermediates were a spec nice-to-have; not done.)
* **Definitional reductions have no frames.** Beta/zeta/eta/proj steps are
  performed by `simp` without any lemma or simproc origin, so the tracer has
  nothing to attribute them to; a location changed purely by such steps shows
  an explicit "definitional reductions only" note (header, section label, and
  film body) rather than frames. The generated `simp only [...]` still
  replays the run faithfully — `simp only` performs the same reductions.
* **Filmstrip rendering is capped at 100 frames per section.** Interactive
  expression rendering of a huge film can cost more than the traced run
  itself; the tail is summarized in a note. If rendering still blows the
  (fresh) budget — a single frame can hold an arbitrarily large term — the
  panel degrades to a filmstrip-less fallback (header, minimal call,
  previews, diagnostics) instead of failing the tactic.
* **Cached rewrites don't repeat.** `simp` caches simplification results per
  subterm; if the same subterm occurs twice, the second occurrence reuses the
  cache and produces no new frame. The filmstrip shows rewrite
  *computations*, which is what `simp` actually did.
* **Steps during failed discharges are recorded** (at `depth > 0`). Depth-0
  frames are never rolled back by simp, but deep steps may belong to a
  discharge attempt that ultimately failed. The filmstrip only shows depth-0
  frames; deep steps are kept in `Film.allSteps` for inspection.
* **Exclusion previews are per-single-lemma** and capped at 12 (re-running
  simp once per used lemma). "Redundant" means the default simp set found
  another route to the same landing goal — it does *not* mean the lemma can
  be dropped from the generated `simp only [...]`, which contains only what
  actually fired.
* **A `⏱ timed out` preview row is a budget verdict, not a proof of
  divergence.** The sub-budget is a small multiple of the traced run's
  measured cost (plus a floor); a re-run that legitimately needs much more
  than that reports as timed out even though it would eventually finish.
  `errored` vs `timedOut` follows `Exception.isRuntime`, so a
  recursion-depth blowup also reports as `timedOut`.
* **Exclusion previews watch one location.** The re-runs happen at all the
  original locations, but the reported landing state is a single expression:
  the target's when the target is among the locations, otherwise the first
  hypothesis the original run changed. A lemma whose exclusion only affects a
  *different* hypothesis still flips the essential marker only if the watched
  landing changes.
* **Exclusion previews re-run with the same discharger as the original call.**
  The `simp_lens` tactic threads its `(disch := ...)` through to every
  exclusion re-run; the lower-level test helper `runExclusion` takes the
  discharger as an explicit parameter instead of defaulting it.
* **`.other` origins** (internal machinery, e.g. from `simp_all`-style
  constructions) cannot be represented in `simp only [...]`; they are
  classified `unrepresentable` and skipped by core's `mkSimpOnly` — same
  behavior as `simp?`.
* **Suggestion text mirrors `simp?`**, including its quirks: builtin closers
  (`eq_self`, `iff_self`) are omitted, equational lemmas are collapsed to
  their definition name, and local hypotheses appear after global lemmas.
* The **diagnostics section** is empty unless `set_option diagnostics true`
  is active — the counters live behind core's `isDiagnosticsEnabled` check.
* `simp_lens` adds **wall-clock** overhead over `simp` (trace recording + up
  to 12 budgeted simp re-runs for exclusion previews) — though never
  *heartbeat* overhead: everything beyond the traced run is
  heartbeat-neutral, so `simp_lens` succeeds wherever `simp` does. Use
  `simp_lens -previews` for near-1x cost, and it is an inspection tool
  either way; the suggestion it inserts is a plain `simp only [...]` with
  zero overhead.
