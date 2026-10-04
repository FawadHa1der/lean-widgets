# DistLens

Exact probability-distribution visualizer for the Lean 4 InfoView — plus
**verified weight goals** and finite Markov chains (**ChainScope**).

`#dist p` evaluates nothing numerically (PMF applications are noncomputable
in Mathlib — `#eval` provably fails): instead it **matches** the term
against a whitelist of `PMF` constructors, computes the exact ℚ weight
vector Lean-side, draws it, and offers every displayed weight back to you as
a machine-checkable goal `example : p x = a/b := by pmf_num`, using the
`pmf_num` tactic shipped in this package.  The picture and the proof come
from independent routes, and the test suite compiles the proofs for every
demo distribution.

```lean
import DistLens
open PMF
set_option linter.deprecated false   -- PMF.bernoulli/binomial are deprecated upstream

noncomputable def die : PMF (Fin 6) := uniformOfFintype (Fin 6)
noncomputable def twoDice : PMF ℕ := die.bind fun a => die.map fun b => a.val + b.val

#dist die                    -- bars + CDF + E/Var + insertable verified goals
#dist (text := true) die     -- deterministic ASCII report (what the tests pin)
#dist twoDice                -- the 1/36 … 6/36 … 1/36 triangle, exact
#dist_film twoDice           -- filmstrip: source, six branches, convolved result

-- what the panel's link inserts (the unfold prefix is generated for you):
example : twoDice 5 = 1/6 := by unfold twoDice die; pmf_num
```

```lean
-- ChainScope: finite Markov chains as `Fin n → PMF (Fin n)`
noncomputable def weather : Fin 2 → PMF (Fin 2) :=
  ![PMF.ofFintype ![3/4, 1/4] (by simp [Fin.sum_univ_succ]; ennreal_num),
    PMF.ofFintype ![1/2, 1/2] (by simp [Fin.sum_univ_succ]; ennreal_num)]

#chain weather                     -- transition graph + exact stationary π = (2/3, 1/3)
#chain weather init [0] steps 4    -- exact power-iteration filmstrip

-- the panel's per-state stationary equations, verified:
example : ((PMF.ofFintype ![2/3, 1/3]
    (by simp [Fin.sum_univ_succ]; ennreal_num)).bind weather) 0 = 2/3 := by
  unfold weather; pmf_num
```

## Commands

| Command | What it does |
|---|---|
| `#dist p` | Bar chart with exact fraction labels, CDF staircase, `E[X]`/`Var[X]` tiles, invariant warnings, insertable verified weight goals. |
| `#dist (text := true) p` | Deterministic ASCII report (outcomes, weights, CDF, moments, warnings). |
| `#dist_film p` | For `p = q.bind f`: filmstrip of `q`, each `f a` (captioned with its mixing weight), and the convolved result with diff badges. |
| `#chain step` | Circular transition graph with exact edge labels; stationary `π P = π, Σπ = 1` solved by exact ℚ Gaussian elimination — unique π drawn as bars with insertable per-state verification examples; reducible chains reported as non-unique, **never** silently resolved. |
| `#chain step init [i] steps k` | Adds an exact power-iteration filmstrip from the point mass at `i` (or `steps k` alone: from uniform), diff-badged per step. |

The term argument parses at `term:max`: write `#dist (uniformOfFintype (Fin 6))`.

## What is supported (the whitelist)

`PMF.pure`, `PMF.bind`, `PMF.map`, `uniformOfFintype`, `uniformOfFinset`
(literal `{a, b, …}` finsets), `bernoulli` (rational-literal `p`),
`binomial` (literal `p`, `n`), `ofFintype` with `![…]` literal weight
vectors — nested arbitrarily up to depth 8, with ≤ 64 outcomes.  User
`def`s wrapping these unfold automatically.  Outcome-level work (`pure`,
`bind`/`map` sources and targets, goal keys) is supported over `Fin n`,
`Bool` and `ℕ`; `uniformOfFintype` over any other `Fintype` carrier is
displayed (cardinality + `Repr` labels via compiled evaluation, GraphScope
style) but is display-only: refused as a `bind`/`map` source, and no
insertable weight goals (see Limitations).

Everything else is an **honest refusal** naming the exact reason: symbolic
parameters, non-literal containers, `normalize`/`filter`/`bindOnSupport`,
monadic `do`/`>>=` spellings, subtype-`mk`-producing maps, carriers beyond
the list, caps exceeded (with actual sizes).

## The `pmf_num` / `ennreal_num` tactics

`pmf_num` proves concrete weight equalities `p x = (a/b : ℝ≥0∞)` for the
whitelisted shapes: `simp` with the PMF application lemma set
(`bind_apply`, `map_apply`, `pure_apply`, `bernoulli_apply`,
`uniformOfFintype_apply`, `uniformOfFinset_apply`, `binomial_apply`,
`ofFintype_apply`, `tsum_fintype`, `tsum_bool`, `Fin.sum_univ_succ`,
`Matrix.cons_val*`; since the v4.34.0 port this `simp` step runs under a
scoped `backward.isDefEq.respectTransparency.types false`, because the
option's new default — `true` since Lean v4.33.0 — stops
`uniformOfFinset_apply` from unifying its `hs : s.Nonempty` argument with the
natural `⟨1, by simp⟩` spelling, whose type `∃ x, x ∈ s` only reaches
`Finset.Nonempty` by unfolding a `def`), then `ennreal_num` closes the ground
ℝ≥0∞ residue:
`done` | `norm_num` | the `ENNReal.toReal_eq_toReal_iff'` + `finiteness`
bridge into ℝ | the `ENNReal.sub_eq_of_eq_add` branch for `bernoulli`'s
truncated `1 − p`.  There is **no** ENNReal `norm_num` extension in Mathlib;
the `toReal` bridge is what makes goals like `6⁻¹ + 6⁻¹ + 6⁻¹ = 2⁻¹` close.
False claims **fail** with a deterministic message (pinned by tests).
`ennreal_num` is exposed separately — it also discharges `ofFintype`'s
sum-to-1 side goal after `simp [Fin.sum_univ_succ]`.

## Architecture

| File | Layer |
|---|---|
| `DistLens/Model.lean` | Pure ℚ: `DistModel` (weights/CDF/moments/support), invariant self-checks, `FilmModel` diff marks, `ChainModel`, exact Gauss–Jordan `rref` + `stationary` (unique / non-unique / inconsistent), power iteration, convolution / pushforward / binomial combinators. |
| `DistLens/Verify.lean` | The `ennreal_num` and `pmf_num` tactics (the probe-validated recipe). |
| `DistLens/Extract.lean` | The impure layer: whitelist `Expr` matcher → `XDist`/`ChainModel`; ℚ parameter parsing (`OfNat`/`HDiv`/`Inv`/`Nat.cast`/literal-`cond` shapes); outcome keying through compiled `evalExpr` on ℕ/Bool bridges; opaque-carrier labels via `Repr`; caps checked before evaluation; honest refusals. |
| `DistLens/Render.lean` | Pure renderers: ASCII reports, SVG bar chart / CDF / chain graph (exact ℚ geometry; the only floats are the circle layout's `sin`/`cos`, rounded immediately — GraphScope's audited pattern), panels; `css` helper, `reactContractViolations`, `htmlToDebugString`. |
| `DistLens/Widget.lean` | The three commands; suggestion strings; RPC panels (`DistPanel`/`ChainPanel`): the command stores plain-data props (model + verified suggestion texts + zero-width insert range), and the `server_rpc_method` wraps them in `MakeEditLink`s at render time with the authoritative document uri/version from `RequestM.readDoc`. |
| `DistLens/Demo.lean` | All scenarios, elaborated on every build, each panel's suggested examples compiled. |

Every displayed model passes `invariantViolations` (Σ = 1, weights ≥ 0,
array shapes) — violations render as an explicit warning overlay flagging an
*extractor bug*, never dropped.  Chains additionally self-check row sums,
and an inconsistent stationary system (impossible for a genuine stochastic
matrix) is reported as `extraction bug!`.

## Limitations — read this

* **Whitelist matching is syntactic.**  A `PMF` built any other way —
  `normalize`, `filter`, `bindOnSupport`, `seq`, monadic `do`/`>>=`/`<$>`
  notation, an opaque lemma-produced term — is refused, even when it is
  mathematically a distribution DistLens could draw.  Spell it with the
  whitelisted constructors.
* **Symbolic anything is refused.**  Parameters, finset/vector contents and
  carriers must be literals.  This is by design (exactness over guessing),
  but it means no `p : ℝ≥0` variables, even with hypotheses fixing them.
* **`bind`/`map` targets must be `Fin n`, `Bool` or `ℕ`.**  Subtype-mk
  images (`fun a => (⟨…, proof⟩ : Fin k)`) are refused *because the probe
  evidence shows `pmf_num`'s `simp` recipe hits `maxRecDepth` on them* — the
  picture would advertise a proof action that breaks.  Use `.val` arithmetic
  into ℕ.
* **`ofFintype` weight functions must be `![…]` literals.**  A lambda
  weight function (`fun i => if i = 0 then …`) is refused: `whnf` on
  ℝ≥0∞-valued applications unfolds into `WithTop` match trees rather than
  literals (probe-verified), and DistLens does not guess.
* **Refusal messages can name internals.**  `resolveHead` unfolds
  non-whitelisted heads before giving up, so `#dist` on `normalize …`
  reports the unfolded `@Subtype.mk` head rather than the name you typed.
  Deterministic (and pinned by tests), but not pretty.
* **Suggested examples reference your names.**  The inserted example needs
  `pmf_num` in scope (`import DistLens`).  For `def`-wrapped distributions
  the suggestion automatically prefixes `unfold` with every user-defined
  `PMF`-valued constant discovered in the term's definition closure (e.g.
  `by unfold twoDice die; pmf_num`, fully qualified) — the test suite
  compiles the generated text verbatim; a `PMF`-valued definition hidden
  purely inside a *proof* argument would still be missed.
* **Opaque `Fintype` carriers are display-only — no goal rows.**
  `uniformOfFintype` over a carrier beyond `Fin`/`Bool`/`ℕ` still draws
  (cardinality + `Repr` labels), but offers **no** insertable weight goals:
  the labels are `Repr` display strings, not verified source terms, and
  `pmf_num` cannot reduce `Fintype.card` of an arbitrary carrier — the
  would-be `#dist (PMF.uniformOfFintype Ordering)` example fails with
  `ennreal_num: cannot close this ℝ≥0∞ goal ⊢ ↑(Fintype.card Ordering) = 3`.
  A row would advertise a proof action that breaks, exactly the subtype-mk
  situation, so it is suppressed.  `ClickE2E` pins both the suppression and
  the still-failing would-be example (so the suppression is revisited if
  `pmf_num` ever learns these goals).
* **Click-to-insert edits are version-stamped.**  The MakeEditLink edit is
  built at *render* time by the panel's RPC method from the server's own
  `DocumentMeta`, so it names the authoritative URI and the current document
  version.  A click racing a keystroke (stored insertion range predating an
  edit above the command) is therefore rejected by the editor rather than
  applied at drifted offsets — re-elaboration refreshes the panel; the
  suggestion text is always shown and can be copied.
* **Deprecated upstream API.**  `PMF.bernoulli` and `PMF.binomial` (and
  their `_apply` lemmas) are deprecated at this pin (since 2026-04-07,
  still present and functional at Mathlib `v4.34.0`) in favor of the
  Measure-valued `ProbabilityTheory.bernoulliMeasure`/`binomial`
  (`bernoulliMeasure_apply`, `binomial_real_singleton`), which need
  `MeasurableSet` side goals and a different lemma set — not covered here.
  Uses need `set_option linter.deprecated false`.  If a later Mathlib removes
  the `PMF` versions, the two whitelist entries and the two simp-set lemmas
  go with them; everything else in DistLens is unaffected.
* **Markov chains are widget-side mathematics.**  Mathlib (at this pin) has
  *no* finite-chain theory: no stationary distributions, no
  Perron–Frobenius, no row-stochastic matrices, and `Kernel` never meets
  `PMF`.  The stationary π is computed by this package's own exact Gaussian
  elimination and verified only as per-state PMF weight equalities
  `(π.bind step) y = π y`; nothing connects it to `Kernel.Invariant`.
  Non-uniqueness is detected as solution-space dimension > 1 — DistLens does
  not decompose reducible chains into classes.
* **Caps.**  ≤ 64 outcomes, `bind` depth ≤ 8, chains ≤ 16 states,
  power filmstrips ≤ 16 steps, ≤ 12 suggestion rows.  A `bind` with a large
  support extracts one branch per support outcome; a slow user function
  inside `map`/`bind` runs compiled at elaboration time (interruptible
  between outcomes via `Core.checkSystem`, unbounded within one call).
* **Expectation/variance are over the canonical value map** (`Fin`/`ℕ`:
  the value; `Bool`: 0/1).  Opaque carriers get no E/Var (stated in the
  panel).  The `E`/`Var` tiles are ℚ computations from the extracted
  weights; only the *weights* have `pmf_num` goals (an `∫ … ∂p.toMeasure`
  route exists — see `PMF.integral_eq_sum` — but DistLens does not generate
  those goals).
* **No event-probability chips**: probabilities of composite events
  (`p.toOuterMeasure {0, 1, 2}`) are not displayed or given goals; the
  per-outcome weights (and CDF) are the unit of display and verification
  (the `PMF.toOuterMeasure_apply_finset` route exists for future work).

## Versions

Pinned to `leanprover/lean4:v4.34.0` with Mathlib `v4.34.0` (ProofWidgets
rev `106ff4fa` through Mathlib's manifest; never `lake update`).  Ported from
the `v4.32.2` original with a single source change (the scoped
`respectTransparency.types` option inside `pmf_num`, above); the test suite
is byte-identical to the original and all green.  **Forward risk:** that fix
relies on a `backward.*` compatibility option (still registered, default
`true`, at v4.34.1 and v4.35.0-rc3); upstream eventually deletes `backward.*`
options, and when this one goes `pmf_num` will fail with an unknown-option
error and need a permanent fix (e.g. a `Finset.Nonempty`-typed proof
spelling in the emitted suggestion, or a `Nonempty`-unfolding simp lemma).
See `PORT-NOTES.md`, gotcha 8.  `PORT-NOTES.md` records
the port, the pin evidence and the assertion census.

## Tests

`lake test` (driver `DistLensTests`): 345 compile-time assertions (census,
counting only lines that *start* with the command: 44 `#guard_msgs` blocks
+ 205 `#guard`s + 44 compiled `example`s in `DistLensTests/`, plus the 52
`check`/`checkEq`/`checkClean`/`checkFails` calls (23 / 8 / 15 / 6) the
eight `ClickE2E` `#eval` suites run; the 17 `example`s and 12
panel commands of `DistLens/Demo.lean` elaborate on every `lake build` on
top of that) — extraction
`#guard_msgs` pins for every constructor and refusal, pure-math `#guard`s
(two-dice triangle, `E = 7/2`,`Var = 35/12` pips die, Gaussian elimination
with hand-computed π, reducible/inconsistent detection), 38 compiled
`pmf_num`/`ennreal_num` examples plus pinned failures on false claims,
byte-exact SVG serializations, React-contract checks over every panel, and
invariant-checker alarms on crafted bad models.

`DistLensTests/ClickE2E.lean` additionally simulates the suggestion clicks
end to end: realistic user files (importing only `DistLens`) are compiled
in-process by Lean's own frontend; the real panel props are captured through
the command's debug hook; the edit is built by `suggestionEditProps` (the
function the RPC method itself uses), applied with the language server's own
`replaceLspRange` (UTF-16 pinned against byte/codepoint misreadings, astral
`𝕜` identifiers included), and the edited file is recompiled and must be
error-, warning- and sorry-free.  Both link kinds get negative controls
(corrupted `newText` for weight *and* stationary suggestions, shifted range,
byte-offset applier) that must fail their recompiles; a code-after-the-command
fixture pins that the insertion preserves everything below it; a
trailing-comment fixture pins the one cosmetic wart (the comment ends up
after the inserted example on its line); and an opaque-carrier fixture
(`uniformOfFintype Ordering`) pins that the panel offers **zero** suggestion
rows there — together with the reason: the would-be example still fails to
recompile with `pmf_num`'s pinned refusal.
