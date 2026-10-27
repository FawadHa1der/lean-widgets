# GraphScope ports: Lean v4.32.2 → v4.34.0 → v4.35.0 (QED64 pairing)

This tree is now on `leanprover/lean4:v4.35.0` / Mathlib `v4.35.0`.  The
v4.34.0 → v4.35.0 record (including its post-audit fixes) comes first; the
original v4.32.2 → v4.34.0 record follows it, unchanged except that its
"This tree" line is marked as historical (it describes the tree as it was at
the end of that port).

## Lean 4.34.0 → 4.35.0 (2026-10-25)

Result: `lake build` exit 0 (after `rm -rf .lake/build`, i.e. every package
module rebuilt on v4.35.0) and `lake test` exit 0, including `ClickE2E`
(nested `importModules` + `enableInitializersExecution`, 5 click scenarios and
4 non-vacuity checks, unchanged).  One real behaviour change surfaced, in
Mathlib, not in GraphScope: `hasse α` (and so `pathGraph n`) now has a
`DecidableRel` instance, which broke the two tests that used `hasse (Fin 4)` as
the "no `DecidableRel` instance" example.  The port itself changed no library
code; the post-audit fixes below did: round 1 (`GraphScope/Gate.lean`: the
adjacency-cost guard for Mathlib's new quantifying instances) and round 2
(`GraphScope/Insert.lean`, `GraphScope/Gate.lean`: the connectivity cost
model), after the re-audit showed that the connectivity link's shape budget
was unsound with *any* instance — the 4-cube's example exceeds the default
`maxHeartbeats` with a cheap closed adjacency — a defect that very likely
predates this port (see round 2).

### Post-audit fixes (2026-10-25)

An adversarial audit of the port reported one major and five minor findings.
All are addressed.  No assertion or expected output was changed or removed;
assertions were only added (some test comments and docstrings were reworded).

| # | Finding | Fix |
|---|---|---|
| 1 (major) | On 4.35, Mathlib's new instances make `#graph_scope (hasse α)` render, and `Insert.connectivityInsertable` (diameter ≤ 4 && n ≤ 16, validated only with non-quantifying instances) offered a `by decide` connectivity link that does **not** compile for `hasse (Finset (Fin 4))` (16 vertices, diameter 4: `(deterministic) timeout at whnf, maximum number of heartbeats (200000)`; the audit's probes). The README advertised `hasse α` as working out of the box. *(Corrected in round 2: this fix misdiagnosed the cause. `hasse (Finset (Fin 4))` is the 4-cube, and the 4-cube's connectivity example exceeds the budget with any adjacency instance — 328678 heartbeats with a cheap `Nat.xor` relation; the shape budget itself was unsound, very likely since v4.34 or earlier. The guard below stays, since quantifying instances do raise the cost of every adjacency decision, but the budget was replaced by a walk-work cost model in round 2, fix R2-1.)* | **Library:** new adjacency-cost guard in `GraphScope/Gate.lean` (`quantifyingDecidableConsts`, `AdjCost`, `adjacencyCost`, `graphAdjacencyCost?`). `computeInsertions` offers the connectivity link only if the shape budget allows it **and** the graph's own synthesized `DecidableRel g.Adj` instance is in the validated class: a breadth-first search over the instance term and, transitively, the bodies of the definitions it names finds none of `Fintype.decidableForallFintype`, `Fintype.decidableExistsFintype`, core's `Nat.decidableForallFin` / `decidableExistsFin` / `decidableBallLT` / `decidableExistsLT` / `decidableExistsLT'`, `Fintype.instDecidableRelCovByOfDecidableLT`, `Fintype.instDecidableRelWCovByOfDecidableLE`, `SimpleGraph.instDecidableRelAdjHasseOfFintypeOfDecidableLT`, `SimpleGraph.instDecidableRelFinAdjPathGraph` (double-backtick names: an upstream rename breaks the build). Conservative: a hit, or a closure above 20000 constants, withholds the link; the shape budget is checked first so graphs outside it pay nothing. Edge and vertex links are unchanged. Chosen over compiling the connectivity example at panel time (exact, but it would add up to a full heartbeat budget — ~13 s for `hasse (Finset (Fin 4))`, more in QED64's wasm runtime — to every interactive `#graph_scope`, and under the language server's `Elab.async` an `example`'s errors arrive in a snapshot task rather than the message log) and over a size bound for Hasse diagrams (no validated cost model: the cost also scales with the element type's `<`). **Tests** (`InsertTests`, new section "The adjacency-cost guard (v4.35.0 post-audit)"): a `#connectivity_gate g` command that logs the shape verdict, the adjacency verdict (with the constant found) and whether `computeInsertions` offers the link, and fails if they disagree; 17 pins — 8 validated graphs keep their link (`pathGraph 5`, `cycleGraph 6`, `completeGraph (Fin 16)`, `completeBipartiteGraph (Fin 2) (Fin 3)`, `twoTriangles`, `fromEdgeSet`, `⊥ : SimpleGraph (Fin 12)`, `twoPaths10`), `pathGraph 16` is refused by shape alone, and `hasse (Finset (Fin 4))` (the regression), `hasse (Finset (Fin 3))`, `hasse (Fin 4)`, `pathGraph 5` with Demo's instance erased, `fromRel (· ⋖ ·)`, `fromRel (· ⩿ ·)`, a user `def` wrapping `hasse (Finset (Fin 4))` with its own `unfold; infer_instance` instance, and a user `∃ c : Fin 5` relation are withheld; plus `#assert_insertions_compile` on `hasse (Fin 4)` (full texts: 3 edges + 4 degrees compiled, connectivity no), `hasse (Finset (Fin 3))` and `hasse (Finset (Fin 4))` (0 insertions, connectivity no: `Finset` has no `Repr` in that import closure); and a new module `GraphScopeTests/HasseLinkTests.lean` that imports `Mathlib.Data.Finset.Sort` (as `import Mathlib` does, e.g. QED64's showcase) so `Finset` vertices get literal labels, with 4 `#assert_insertions_compile` pins compiling *every* offered text for `hasse (Finset (Fin 2))` (8), `hasse (Finset (Fin 3))` (20), the audit's `hasse (Finset (Fin 4))` (48: 32 edges, 16 degrees; connectivity no) and `hasse (Fin 64)` at the vertex cap (127). **Docs:** README (connectivity-budget bullet, the "out of the box" paragraph, limitations), `Demo.lean` docstrings. |
| 2 (minor) | Stale ClickE2E comment: the scenarios were called the load-bearing proof that the `pathGraph`/`completeBipartiteGraph` instances arrive with `import GraphScope`; on 4.35 Mathlib's own `pathGraph` instance satisfies the `pathGraph` scenarios. Same staleness in the README's scoping-caveat example. | ClickE2E comment rewritten: load-bearing for `completeBipartiteGraph`; for `pathGraph` the selection is pinned by InsertTests' `#synth` pin and, since fix 1, by the `path5`/`unicode` scenarios' `connectivity yes` (Mathlib's instance would have the link withheld). README's scoping caveat now uses `completeBipartiteGraph` as its example. |
| 3 (minor) | Overstated justification for the `#synth` pin ("budget figures and click-E2E pins are only meaningful if Demo's instance is selected"): with Mathlib's instance every other test still passed (audit mutation M1). | InsertTests section docstring and the Changes row below reworded: the pin guards which evaluation path `decide` takes; at demo sizes both instances decide every offered example; since fix 1 the selection is also behavioural (verified by re-running M1, see the transcript). |
| 4 (minor) | Gotcha 1 did not name the new global instances. | Gotcha 1 now names `Fintype.instDecidableRelCovByOfDecidableLT` / `Fintype.instDecidableRelWCovByOfDecidableLE` (`Mathlib/Data/Fintype/Defs.lean:261-266`, same PR #40728) and the removal of `Bool.instDecidableRelWCovBy` / `Bool.instDecidableRelCovBy` from `Mathlib/Order/Cover.lean`, and their cost consequence. |
| 5 (minor) | Stale H1 title and "This tree: v4.34.0" statement. | Title now covers both ports; a preamble says which record is current; the old record's "This tree" line is marked historical. |
| 6 (minor, advisory) | CommandTests: the comment claimed that with the instance erased "the environment is exactly the pre-v4.35 one"; the erasure depends on an auto-generated Mathlib name. | Comment softened (other v4.35 instances remain in scope, they just do not apply to that goal; a rename fails loudly). Added two pins on a test-local `def hasseNoInst : SimpleGraph (Fin 4) := hasse (Fin 4)` without an instance — the missing-`DecidableRel` and the noncomputable (`open scoped Classical`) errors — which cover the same `synthOrExplain` branches with no upstream name. The erasure pins stay (unchanged expected messages). |

#### Post-audit measurements

Scratch probes (`lake env lean`, through the lock, lane
`port435-fix-graph-scope-buildtest`, step 0), each `example … := by decide`
elaborated with `Elab.async false` under the default `maxHeartbeats 200000`;
figures are heartbeats in `maxHeartbeats` units and wall time.

| Example | Result |
|---|---|
| validated class, connectivity: `completeGraph (Fin 16)` / `(Fin 10)` / `pathGraph 5` / `cycleGraph 6` / `completeBipartiteGraph (Fin 2) (Fin 3)` / `star5` / `¬ twoTriangles` / `¬ ⊥ (Fin 12)` / `¬ twoPaths10` | all OK: 34126 (1.7 s) / 9455 / 2878 / 5130 / 2646 / 3180 / 4059 / 315 / 8793 |
| quantifying class, connectivity (now withheld): `hasse (Fin 4)` / `hasse (Fin 5)` / `hasse Bool` / `hasse (Finset (Fin 2))` / `hasse (Finset (Fin 3))` / Mathlib-instance `pathGraph 5` / `fromRel (· ⋖ ·)` on `Fin 4` | OK: 1990 / 4763 / 261 / 3931 / **63429 (3.0 s)** / 4785 / 2008; `hasse (Finset (Fin 4))`: timeout at 200000 (the audit's probe) |
| quantifying class, edge / degree (still offered) | `hasse (Fin 64)`: Adj ≤ 348, degree ≤ 1637; with `Finset` labels: `hasse (Finset (Fin 4))` Adj ≤ 800, degree ≤ 2416; `hasse (Finset (Fin 5))` ≤ 1502 / 5487; `hasse (Finset (Fin 6))` (64 vertices) 2903 / 12316 |
| `adjacencyCost` itself | ≤ 1 ms on every graph probed; closures of 14–380 constants; the hit, when there is one, is found within the first 4–37 |

The detector prototype in the probe (the library's breadth-first search and
target list) classified 18 graphs as validated (`pathGraph 5` and `pathGraph 16` with Demo's
instance, `cycleGraph 5/6`, `completeGraph (Fin 5)/(Fin 16)`, `⊥` on `Fin 4` /
`Fin 12` / a subtype, `twoTriangles`, `star5`, `fromEdgeSet`,
`completeBipartiteGraph`, `twoPaths10`, a user `def` wrapping `pathGraph 4`,
`⊤` on `Fin 2 → Bool` / `Finset (Fin 3)` / `Bool`) as validated and 10
quantifying ones (`hasse` on `Fin 4` / `Fin 64` / `Bool` / `Finset (Fin 3)` /
`Finset (Fin 4)`, Mathlib's `pathGraph` instance, `fromRel (· ⋖ ·)`,
`fromRel (· ⩿ ·)`, a user `def` wrapping `hasse (Finset (Fin 4))`, a user
`∃ c : Fin 5` relation) as quantifying — no false positive on the validated
set, including `⊤` over a function type (whose `DecidableEq` quantifies over
`Fin 2` through a `Finset`-bounded `∀`, not a target).  With only the two
`Fintype` quantifiers and the named instances, the `∃ c : Fin 5` relation was
missed (core decides it with `Nat.decidableExistsFin`), which is why the core
bounded-`Nat` quantifiers are on the list.

#### Post-audit verification transcript

| Lane | Command | Final lines |
|---|---|---|
| `port435-fix-graph-scope-probe` | `lake env lean` on two scratch probes (pre-fix oleans) | instance names, the `hasseNoInst` error texts, detector verdicts; the cost section did not run (a `String.take` → `String.Slice` type error in the probe helper, v4.35) |
| `port435-fix-graph-scope-buildtest` step 0 | the same probes, fixed | the measurements above |
| … step 1 / 1b | `lake build`; `lake build GraphScopeTests.CommandTests GraphScopeTests.InsertTests` | `Build completed successfully (1070 jobs).` / `Build completed successfully (1072 jobs).` |
| … step 2 | audit mutation M1 re-run (Demo's `pathGraph` instance at `priority := low`), `lake build GraphScopeTests.InsertTests` | fails as it should, now in **5** pins instead of 1: `#assert_insertions_compile (pathGraph 3)` (connectivity line gone, `connectivity: no`), `(counts := true) (pathGraph 5)` (`compiled 9 insertions … connectivity: no`), the `#synth` pin (`SimpleGraph.instDecidableRelFinAdjPathGraph 5`), `#connectivity_gate (pathGraph 5)` and `(pathGraph 16)` (`quantifies (SimpleGraph.instDecidableRelFinAdjPathGraph)`); `Demo.lean` restored byte-identical (`cmp`) |
| … steps 3 / 4 | `lake build`; `lake test` | `Build completed successfully (1070 jobs).`; `✔ [1080/1081] Built GraphScopeTests.ClickE2E (19s)` / `✔ [1081/1081] Built GraphScopeTests (959ms)`, exit 0 |
| `port435-fix-graph-scope-buildtest2` (final tree, after adding `HasseLinkTests`) | `lake build`; `lake test` | `✔ [1069/1070] Built GraphScope (837ms)` / `Build completed successfully (1070 jobs).` BUILD_EXIT=0; `✔ [1083/1085] Built GraphScopeTests.ClickE2E (16s)` / `⚠ [1084/1085] Built GraphScopeTests.HasseLinkTests (10s)` / `✔ [1085/1085] Built GraphScopeTests (871ms)` TEST_EXIT=0, `browser-lock: command exited rc=0` |

Warnings in the final run: the Lake module-system warnings only (gotcha 3),
now **7**: `Extract` ×2, `Gate` ×2 (its new `Mathlib.Combinatorics.SimpleGraph.Hasse`
import), `Demo` ×2, and `HasseLinkTests` ×1 (`Mathlib.Data.Finset.Sort`).

### Post-audit fixes, round 2 (2026-10-26)

The re-audit of round 1 failed the package on one major and three minor
findings.  All are addressed.

| # | Finding | Fix |
|---|---|---|
| R2-1 (major) | The round-1 fix misdiagnosed the round-1 major finding.  The v4.34 shape budget (`connectivityInsertable`: connected ⇒ `diameter ≤ 4 && n ≤ 16`) is unsound at its corner whatever the adjacency instance: the 4-cube with a cheap closed adjacency (`fromRel` with `Nat.xor` on `Fin 16`, re-audit's `q4fin`) and its `Finset (Fin 4)` `⊆`/`card` spelling were classified `validated` / offered, and `example : (q4fin).Connected := by decide` exceeds `maxHeartbeats 200000` (324048 and 822363 heartbeats).  The docs (Gate.lean, README, gotcha 1, round-1 row 1) blamed the quantifying instance. Very likely pre-existing (see "Connectivity cost model" below), not a port regression. | **Library** (`GraphScope/Insert.lean`, `GraphScope/Gate.lean`): the shape budget is replaced by a walk-work cost model with a measured adjacency cost (design, coefficients and evidence in "Connectivity cost model" below). `Insert.walkWork` counts Mathlib's walk enumeration exactly; `GraphScope.adjacencyCostOf?` measures one adjacency decision of the graph's own instance at panel time; `Insert.connectivityVerdict` combines them into a heartbeat estimate (an upper envelope of the 250-graph calibration sweep) that must stay within `connectivityHeartbeatBudget = 100000`, half the default `maxHeartbeats`; `GraphScope.connectivityCheck` adds the round-1 adjacency-cost guard (kept: the estimate was calibrated only with non-quantifying instances) and `computeInsertions` uses it. The v4.34 recursion-depth domain (connected: diameter ≤ 4, n ≤ 16; disconnected: n ≤ 12) is kept, plus a recursion-depth estimate (`Insert.recursionEstimate ≤ 500`: K₁₀ with a 3-vertex tail, inside the old budget, fails on `maxRecDepth`); the disconnected `maxDegree ≤ 2` proxy is replaced by the estimate. Validated on 300 graphs (250 calibration + 50 out of sample): every one of the 156 offered examples compiles, measured ≤ estimate ≤ 100000 (worst: `K₆` with a 3-vertex tail, 83742 of its estimate 99490). **Tests**: new InsertTests section "The connectivity cost model (v4.35.0 post-audit, round 2)" (exact `walkWork` counts, estimates and recursion estimates, the cap arithmetic, the old budget's counterexamples refused, `#connectivity_gate` and `#assert_insertions_compile` on the re-audit's `q4fin` and its `Finset` spelling, the most expensive offered examples compiled under `maxHeartbeats 100000`, `#adjacency_cost` band and repeatability pins on the measurement), and a `HasseLinkTests` pin compiling every link of the `Finset (Fin 4)` `⊆`/`card` 4-cube (48, connectivity no). `#connectivity_gate` now reports the walk budget at zero adjacency cost, the guard, and whether the measured adjacency cost is within the cap the budget allows, so its 17 round-1 pins changed their expected text (documented under "Golden / expected-output changes"); every verdict (offered / withheld) is unchanged. **Docs:** Gate.lean, Insert.lean, README (cost-model bullet, limitations), gotcha 1, round-1 row 1. |
| R2-2 (minor) | No pin had `Fintype.decidableForallFintype` / `Fintype.decidableExistsFintype` as the nearest deny-list hit (mutation M3 survived). | Three new `#connectivity_gate` pins whose nearest hit is one of the two entries: `fromRel fun a b : Bool × Bool => ∀ c : Bool × Bool, c = c ∧ a.1 = b.1` → `quantifies (Fintype.decidableForallFintype)`, `fromRel fun a b : Fin 2 × Fin 3 => ∃ c : Fin 2 × Fin 3, c ≠ a ∧ c ≠ b ∧ a.1 = b.1` → `quantifies (Fintype.decidableExistsFintype)` (both inside the walk budget, so the entry alone decides that the link is withheld), and the re-audit's `Finset (Fin 4)` covering relation with a `Finset`-bounded `∀` → `quantifies (Fintype.decidableForallFintype)` (the 4-cube again). Re-ran M3: all three pins fail, see the mutation table. |
| R2-3 (minor) | The `.unknown` branch (closure over `adjCostSearchLimit`) was never exercised (mutation M2 survived). | `adjacencyCost`, `graphAdjacencyCost?` and `computeInsertions` take the search limit as a parameter (default `adjCostSearchLimit`, so the panel is unchanged); `#connectivity_gate` takes an optional `(limit := k)`. New pins: `#connectivity_gate (limit := 1) (pathGraph 5)` → `adjacency: unknown; connectivity link: withheld` (the same graph is `validated` / offered with the default limit), `#guard AdjCost.validated.connectivityOk == true`, `#guard AdjCost.unknown.connectivityOk == false`, `#guard (AdjCost.quantifies …).connectivityOk == false`, `#guard adjCostSearchLimit == 20000`. Re-ran M2: caught, see the mutation table. |
| R2-4 (minor) | Docs overstated the guard's conservatism: "a hit inside a proof term embedded in a definition counts too", but tactic proofs are abstracted into auxiliary theorems the search does not unfold (re-audit ProbeD: a `by decide` over `Fin 5` inside an instance body stays `validated`). | Reworded in `Gate.lean` ("The adjacency-cost guard") and the README's deny-list limitation: a quantifier inside a proof counts only where the proof term is inlined in a definition's value; tactic proofs in an instance body are abstracted into auxiliary theorems, which the search does not unfold (sound, since `decide` never evaluates a proof). |

#### Connectivity cost model (round 2)

**What `decide` does.**  `Mathlib.Combinatorics.SimpleGraph.Connectivity.Finite`
decides `G.Connected` as `Preconnected ∧ univ.Nonempty`, `Preconnected` as
`∀ u v, G.Reachable u v` over the `Fintype` enumeration (in order, stopping
at the first unreachable pair), and `G.Reachable u v` as `∃ k : Fin (card V),
(G.finsetWalkLength k u v).Nonempty` (ascending `k`, stopping at
`k = dist u v`).  `finsetWalkLength k u v` (`Walk/Counting.lean`) builds every
walk of length `k` out of `u`: an inner node filters `univ` for its neighbours
(`n` adjacency decisions) and deduplicates its children's walks
(`Finset.biUnion`), a leaf decides `w = v`.  None of this changed between
Mathlib v4.34.0 and v4.35.0 (`git diff v4.34.0 v4.35.0` of
`Connectivity/Finite.lean`, `Walk/Counting.lean`, `Data/Finset/Union.lean`:
imports only), and `GraphScope/Insert.lean` was byte-identical to
`qed64-pin-i` before this round, so the unsound budget almost certainly
predates the 4.35 port (it was not re-measured on 4.34: that toolchain's
tree no longer exists here).

**The model.**  `Insert.walkWork d` simulates that order on the drawn graph
and counts walk sets tested (`sets`), inner walk-tree nodes (`inner`) and
leaves (`leaves`); walk counts come from `walkCountsFrom` (vector iteration
over the adjacency lists), so the counts are exact: they equal the
calibration probe's independent matrix-power simulation on all 250
calibration graphs, and six of them are pinned.  `GraphScope.adjacencyCostOf?` measures `k`,
the raw heartbeats of one adjacency decision: `whnf` (default transparency,
exactly what `decide` runs) of `decide (∀ a b : V, ¬ (G.Adj a b ∧ False))`
from an empty `MetaM` cache, divided by the `n²` decisions, rounded up, and
capped at `Insert.maxAdjacencyCost?` (the largest `k` the budget allows), so
the measurement never costs more than the example would be allowed to.  The
estimate is

    est = (1000 + k) · (71 · n · inner + 187 · leaves + 291 · sets) / 100000 + 170

i.e. `(1 + k/1000) · (0.71 · n·inner + 1.87 · leaves + 2.91 · sets) + 170`
heartbeats, and the link is offered iff the recursion-depth domain holds
(connected: diameter ≤ 4, n ≤ 16; disconnected: n ≤ 12; unchanged from
v4.34), `Insert.recursionEstimate ≤ 500` (see "Recursion depth" below) and
`est ≤ 100000` (half the default `maxHeartbeats 200000`), on top of the
round-1 adjacency-cost guard.

**Calibration.**  Fitted on the round-2 calibration sweep below (250 graphs,
`n ≤ 16`; each the exact offered text `Insert.connectedExampleText` /
`notConnectedExampleText`, elaborated with `Elab.async false` under
`maxHeartbeats 400000`, heartbeats from `IO.getNumHeartbeats` around the
command — the `#count_heartbeats in` method; `k` measured in a separate
probe).  A least-squares fit of the shape-only model
`a·n·inner + b·leaves + c·sets + d·dedup` left the spellings 2.2–4.5× apart
(the 3-cube: 16091 through `Nat.xor`, 33784 through `Finset` `⊆`/`card`,
35539 through a `List` literal, 61840 through a `fromEdgeSet` literal), so a
GraphData-only bound either loses `completeGraph (Fin 16)` (34124, pinned by
the suite since v4.32) or offers literal spellings that blow the budget.
Multiplying by `1 + k/1000` with `k` measured removes most of that spread.
The coefficients are the solution of the linear program "minimise the sum of
`est/measured` over the sweep's graphs measured ≤ 150000, subject to
`est ≥ measured` on every graph that compiled", rounded up (LP optimum
`0.7026, 1.8666, 2.9096, 162.6`; the dedup term came out at 0).  The
binding graphs (estimate = measurement) are `twoTriangles`, `K5` plus an
isolated vertex, `⊤ : SimpleGraph Bool` and `pathGraph 4`;
over the 262 graphs of both sweeps that compiled and have an estimate, it
is 1.006–15.3× the measurement (1.006: `K5` plus an isolated vertex; 15.3:
the 16-vertex star as a `fromEdgeSet` literal — conservative for long
literals).

**How far off can it be out of sample?**  Leave-one-family-out
cross-validation of the same LP on the calibration sweep (refit without the
family — paths, cycles, complete graphs, … — then compare on it): the worst
measured/estimate ratio is 1.068 (`K5` plus an isolated vertex, 20345 vs
19058) for every graph above 1000 heartbeats, 1.54 only for the 2-vertex
`⊤ : SimpleGraph Bool` (232 vs 151, where the constant dominates).  So the
factor-2 margin of the budget is far above the observed out-of-family error.

**What the v4.34 shape budget got wrong (calibration sweep).**  Of the 250
graphs, the shape budget offered 172 (with a validated instance).  Twelve of
those examples do **not** compile under the default budget: the 4-cube in
both spellings (328678; > 400000), the 4×4 torus (= the 4-cube, 321107),
`C16(1, 2)` / `(1, 3)` / `(1, 5)` / `(1, 7)` / `(1, 8)` / `(1, 2, 3)` /
`(1, 2, 4)` (219649–425853), the 16-vertex barbell (387329), and K₁₀ with
a 3-vertex tail (diameter 4: maximum recursion depth).  Twenty-two more
compiled only above half the budget (100000–200000: `K4,12` … `K8,8`,
`GP(7,1)`, `GP(8,2)`, `GP(8,3)`, five 16-vertex circulants, `C14(1, 2, 3)`,
`C15(1, 4)`, the 3×5 torus, `(cycleGraph 16)ᶜ`, the 3×3 grid as a
`fromEdgeSet` literal, and four disconnected 12-vertex graphs inside the old
`maxDegree ≤ 2` rule: `2C6`, `3C4`, `4C3`, `C11 + K1`).  The new model
withholds all 34 (39 counting the validation graphs: `lolli K7+3` / `K8+3`,
`lolli K10+2`, `modClasses 12 4`, and the 12-leaf broom with a 3-vertex
tail, which fails on recursion depth).  The price of the margin: 24 graphs
that the v4.34 budget offered and whose example compiles below 100000 are
withheld now, because their estimate exceeds the budget (`K3,13`,
`GP(6,1)`, `GP(7,2)`, `GP(7,3)`, `C12(1, 2)` / `(1, 3)` / `(1, 5)`,
`C14(1, 4)`, `spider 7`, `wheel 16`, the 12-vertex barbell, the 16-vertex
double star, `⊤` on `Fin 4 → Bool`, `P11 + K1`, `divG 16`, the 20-pair
`List` literal `list20` on 10 vertices, the 10-leaf broom with a 3-vertex
tail, the 15-vertex caterpillar and the five `fromEdgeSet` literals with
8–16 edges; the double star, `divG 16` and that broom also exceed the
recursion bound) or, for the 13-leaf broom with a 2-vertex tail, its
recursion estimate alone (501).  None
of them is in the v4.34 suite: every connectivity link the suite pinned is
still offered.  Four graphs are newly offered — disconnected ones with
maximum degree 3–4, which the old `maxDegree ≤ 2` rule refused (`2K4` in two
spellings, `K4 + 4K1`, `K5 + K1`; 20345–65320 heartbeats).

**Why one input is measured (a deliberate extension of the requested
GraphData-only model).**  The walk work comes from the `GraphData` alone, as
asked, but no GraphData-only coefficient set is both sound and useful: the
upper envelope over all spellings of the sweep needs coefficients
4.3 · n·inner + 34.6 · leaves (fitted by the same LP), which withholds
`completeGraph (Fin 16)` (estimate 150141, measured 34124) and 44 other
graphs that compile below 100000; the envelope over the cheap spellings
only (closed arithmetic, Mathlib's instances) is unsound for literals — the
3×3 grid as a `fromEdgeSet` literal is 4.4× its cheap fit, which at the
budget means ~440000 heartbeats.  The literal spellings are exactly what
the README advertises (`fromEdgeSet {s(0, 1), …}`) and what QED64's showcase
uses (`twoTriangles`, a `List` literal), so the cost of one adjacency
decision is measured instead of assumed.  Two rejected measurement variants,
for the record: a per-unit model with separately measured adjacency and
vertex-equality costs (fit spread 0.56–2.8×), and scaling by the measured
cost of one walk-tree level (`∀ u, ¬ (G.finsetWalkLength 1 u u).Nonempty`;
spread 0.32–1.7×, and `LocallyFinite` did not synthesize for `fromEdgeSet`
literals).

**Recursion depth.**  `decide` can also exhaust `maxRecDepth` (512 by
default), and in the sweep that happens before the heartbeat limit on 12
graphs: `pathGraph 15` / `16`, `pathR 16`, the lollipops K₈ + 4, K₁₀ + 3 and
K₁₂ + 4, and six 16-vertex disconnected graphs; all but K₁₀ + 3 (diameter 4,
n = 13 — inside the old shape budget, which offered it) are outside the
domain, and the validation sweep added one more inside it, the 12-leaf broom
with a 3-vertex tail (n = 16, diameter 4: recursion failure after 37947
heartbeats, estimate 156290).  Lane `fix2-graph-scope-minrec` bisected the
smallest `maxRecDepth` under which the offered text compiles for 58 graphs
(the examples elaborated nested inside a probe command, so the figures are
a little above what a top-level example needs): 133 (`pathGraph 3`) up to
409 for the offered ones (`K1,15`, `K2,14`; `K16` 391,
`(⊤ : SimpleGraph (Finset (Fin 4)))` 399), 440–498 for in-domain graphs over
the heartbeat budget (`P11 + K1`, `2C6`, `C11 + K1`, `(cycleGraph 16)ᶜ`),
479 / 575 for K₈ + 3 / K₁₀ + 3.  The need grows with `n` (the enumerations
are reduced with nested matches) and with the degrees along the longest
walk (each child of a walk-tree node nests one level while its walk set is
concatenated), so `Insert.recursionEstimate` =
`13.85 · n + 11.53 · L + 6.5 · W + 37.5` (`L` the longest walk length
enumerated, `W` the heaviest such walk weighted by degree) is the LP upper
envelope of those 58 points, rounded up (no point above it; the tight ones,
within one level, are `cycleGraph 6`, `twoTriangles`, `GP(6,2)` and K₁₀ + 3),
and the link needs it to be
at most `connectivityRecursionBudget = 500`.  Unlike heartbeats the counter
is deterministic, so the margin is smaller than for heartbeats; on the
offered graphs the estimate is 51–483 (bisected needs among them:
133–409).  Out of sample it refuses the failing broom (584) and its 2-vertex-tail sibling
(501, which happened to compile), and keeps every other offered graph of
the validation sweep; the only graph the recursion bound withholds that the
heartbeat estimate alone would offer is that sibling (`broom 13 2`, 59019
heartbeats).  `maxRecDepth 256` (half the default) is *not* enough for the
larger offered examples (`completeGraph (Fin 16)`, `K₇,₇`, `twoK4` fail at
256), so the suite's half-budget compile checks halve `maxHeartbeats` only.

#### Calibration and validation sweep (round 2)

Every row is one graph; the heartbeats are those of the exact text the panel
offers (`example : (g).Connected := by decide`, or its `¬` form), elaborated
under `maxHeartbeats 400000` with `Elab.async false` and counted with
`IO.getNumHeartbeats` around the command, as `#count_heartbeats in` does
(cross-checked: `#count_heartbeats in` reports the same figures within a few
heartbeats, see the transcript).  Set `cal` = calibration sweep (the LP was
fitted on these; measured in lane `fix2-graph-scope-sweep1`, offered ones
re-measured on the final tree), `val` = validation graphs added afterwards
(out of sample; lane `fix2-graph-scope-sweep2`).  The verdicts (`k`,
estimate, "now") are the final model's (lane `fix2-graph-scope-insert4`,
`Sweep3.lean`).  Columns: `n`, diameter,
max degree Δ, connected?; `rec.` = `Insert.recursionEstimate`; the
estimate at zero adjacency cost (`out: …` = outside the domain, including the
recursion bound); the adjacency-cost guard (`val` = validated, `q: c` =
quantifies through `c`); `k` = measured raw heartbeats per adjacency
decision and the estimate at `k` (both in parentheses when the final model
withholds the link); the measured heartbeats (`> 400000 (timeout)`, or `recdepth at h`
= maximum recursion depth after `h` heartbeats); whether the v4.34 shape
budget offers the link (computed from `n`, diameter and Δ for every row; it
had no adjacency guard), and whether the final tree offers it.

<details>
<summary>The sweep (300 rows)</summary>

| # | graph | set | n | diam | Δ | conn | rec. | est. at k=0 | guard | k | estimate | heartbeats | v4.34 | now |
|---:|---|---|---:|---:|---:|---|---:|---:|---|---:|---:|---:|---|---|
| 1 | pathGraph 1 | cal | 1 | 0 | 0 | yes | 51 | 174 | val | 6395 | 205 | 77 | offered | **offered** |
| 2 | pathGraph 2 | cal | 2 | 1 | 1 | yes | 89 | 201 | val | 3887 | 324 | 224 | offered | **offered** |
| 3 | pathGraph 3 | cal | 3 | 2 | 2 | yes | 134 | 280 | val | 3224 | 634 | 573 | offered | **offered** |
| 4 | pathGraph 4 | cal | 4 | 3 | 2 | yes | 179 | 472 | val | 2939 | 1360 | 1349 | offered | **offered** |
| 5 | pathGraph 5 | cal | 5 | 4 | 2 | yes | 217 | 919 | val | 2789 | 3009 | 2879 | offered | **offered** |
| 6 | pathGraph 6 | cal | 6 | 5 | 2 | yes | 256 | out: diameter 5 > 4 | val | (2698) | (6633) | 5950 | withheld | withheld |
| 7 | pathGraph 7 | cal | 7 | 6 | 2 | yes | 294 | out: diameter 6 > 4 | val | (2638) | (14450) | 11826 | withheld | withheld |
| 8 | pathGraph 8 | cal | 8 | 7 | 2 | yes | 333 | out: diameter 7 > 4 | val | (2599) | (31047) | 23389 | withheld | withheld |
| 9 | pathGraph 9 | cal | 9 | 8 | 2 | yes | 371 | out: diameter 8 > 4 | val | (2569) | (65756) | 45374 | withheld | withheld |
| 10 | pathGraph 10 | cal | 10 | 9 | 2 | yes | 409 | out: diameter 9 > 4 | val | (2548) | (137822) | 88831 | withheld | withheld |
| 11 | pathGraph 11 | cal | 11 | 10 | 2 | yes | 448 | out: diameter 10 > 4 | val | (2532) | (286154) | 173189 | withheld | withheld |
| 12 | pathGraph 12 | cal | 12 | 11 | 2 | yes | 486 | out: diameter 11 > 4 | val | (2520) | (590639) | 342233 | withheld | withheld |
| 13 | pathGraph 13 | cal | 13 | 12 | 2 | yes | 524 | out: diameter 12 > 4 | val | (2509) | (1211834) | > 400005 (timeout) | withheld | withheld |
| 14 | pathGraph 14 | cal | 14 | 13 | 2 | yes | 563 | out: diameter 13 > 4 | val | (2501) | (2480542) | > 400005 (timeout) | withheld | withheld |
| 15 | pathGraph 15 | cal | 15 | 14 | 2 | yes | 601 | out: diameter 14 > 4 | val | (2494) | (5060866) | recdepth at 175341 | withheld | withheld |
| 16 | pathGraph 16 | cal | 16 | 15 | 2 | yes | 640 | out: diameter 15 > 4 | val | (2487) | (10313529) | recdepth at 125054 | withheld | withheld |
| 17 | pathR 5 | cal | 5 | 4 | 2 | yes | 217 | 919 | val | 3434 | 3493 | 3002 | offered | **offered** |
| 18 | pathR 8 | cal | 8 | 7 | 2 | yes | 333 | out: diameter 7 > 4 | val | (3283) | (36915) | 25278 | withheld | withheld |
| 19 | pathR 11 | cal | 11 | 10 | 2 | yes | 448 | out: diameter 10 > 4 | val | (3230) | (342670) | 193335 | withheld | withheld |
| 20 | pathR 12 | cal | 12 | 11 | 2 | yes | 486 | out: diameter 11 > 4 | val | (3218) | (707726) | 386649 | withheld | withheld |
| 21 | pathR 16 | cal | 16 | 15 | 2 | yes | 640 | out: diameter 15 > 4 | val | (3188) | (12386848) | recdepth at 148448 | withheld | withheld |
| 22 | cycleGraph 3 | cal | 3 | 1 | 2 | yes | 116 | 265 | val | 4853 | 730 | 521 | offered | **offered** |
| 23 | cycleGraph 4 | cal | 4 | 2 | 2 | yes | 154 | 436 | val | 4500 | 1633 | 1416 | offered | **offered** |
| 24 | cycleGraph 5 | cal | 5 | 2 | 2 | yes | 168 | 703 | val | 4318 | 3009 | 2299 | offered | **offered** |
| 25 | cycleGraph 6 | cal | 6 | 3 | 2 | yes | 207 | 1372 | val | 4214 | 6440 | 5132 | offered | **offered** |
| 26 | cycleGraph 7 | cal | 7 | 3 | 2 | yes | 221 | 2337 | val | 4147 | 11328 | 7686 | offered | **offered** |
| 27 | cycleGraph 8 | cal | 8 | 4 | 2 | yes | 259 | 4590 | val | 4103 | 22730 | 15650 | offered | **offered** |
| 28 | cycleGraph 9 | cal | 9 | 4 | 2 | yes | 273 | 7662 | val | 4073 | 38177 | 22194 | offered | **offered** |
| 29 | cycleGraph 10 | cal | 10 | 5 | 2 | yes | 311 | out: diameter 5 > 4 | val | (4047) | (72446) | 42983 | withheld | withheld |
| 30 | cycleGraph 11 | cal | 11 | 5 | 2 | yes | 325 | out: diameter 5 > 4 | val | (4029) | (117038) | 58650 | withheld | withheld |
| 31 | cycleGraph 12 | cal | 12 | 6 | 2 | yes | 363 | out: diameter 6 > 4 | val | (4012) | (212686) | 111311 | withheld | withheld |
| 32 | cycleGraph 13 | cal | 13 | 6 | 2 | yes | 377 | out: diameter 6 > 4 | val | (3999) | (333208) | 147978 | withheld | withheld |
| 33 | cycleGraph 14 | cal | 14 | 7 | 2 | yes | 416 | out: diameter 7 > 4 | val | (3988) | (586129) | 278962 | withheld | withheld |
| 34 | cycleGraph 15 | cal | 15 | 7 | 2 | yes | 429 | out: diameter 7 > 4 | val | (3980) | (897169) | 363283 | withheld | withheld |
| 35 | cycleGraph 16 | cal | 16 | 8 | 2 | yes | 468 | out: diameter 8 > 4 | val | (3973) | (1540146) | > 400005 (timeout) | withheld | withheld |
| 36 | cycR 8 | cal | 8 | 4 | 2 | yes | 259 | 4590 | val | 3311 | 19228 | 14063 | offered | **offered** |
| 37 | cycR 12 | cal | 12 | 6 | 2 | yes | 363 | out: diameter 6 > 4 | val | (3239) | (179910) | 96164 | withheld | withheld |
| 38 | cycR 16 | cal | 16 | 8 | 2 | yes | 468 | out: diameter 8 > 4 | val | (3206) | (1302631) | 571919 | withheld | withheld |
| 39 | K1 | cal | 1 | 0 | 0 | yes | 51 | 174 | val | 5986 | 203 | 83 | offered | **offered** |
| 40 | K2 | cal | 2 | 1 | 1 | yes | 89 | 201 | val | 3662 | 316 | 229 | offered | **offered** |
| 41 | K3 | cal | 3 | 1 | 2 | yes | 116 | 265 | val | 3064 | 558 | 499 | offered | **offered** |
| 42 | K4 | cal | 4 | 1 | 3 | yes | 143 | 382 | val | 2809 | 980 | 944 | offered | **offered** |
| 43 | K5 | cal | 5 | 1 | 4 | yes | 170 | 568 | val | 2669 | 1631 | 1599 | offered | **offered** |
| 44 | K6 | cal | 6 | 1 | 5 | yes | 197 | 837 | val | 2587 | 2564 | 2505 | offered | **offered** |
| 45 | K8 | cal | 8 | 1 | 7 | yes | 250 | 1690 | val | 2494 | 5480 | 5233 | offered | **offered** |
| 46 | K10 | cal | 10 | 1 | 9 | yes | 304 | 3063 | val | 2449 | 10150 | 9457 | offered | **offered** |
| 47 | K12 | cal | 12 | 1 | 11 | yes | 358 | 5082 | val | 2421 | 16975 | 15493 | offered | **offered** |
| 48 | K14 | cal | 14 | 1 | 13 | yes | 411 | 7870 | val | 2402 | 26365 | 23620 | offered | **offered** |
| 49 | K16 | cal | 16 | 1 | 15 | yes | 465 | 11550 | val | 2389 | 38738 | 34128 | offered | **offered** |
| 50 | K1,15 | cal | 16 | 2 | 15 | yes | 483 | 16932 | val | 3263 | 71629 | 45466 | offered | **offered** |
| 51 | K2,14 | cal | 16 | 2 | 14 | yes | 477 | 23102 | val | 3259 | 97838 | 70085 | offered | **offered** |
| 52 | K3,13 | cal | 16 | 2 | 13 | yes | 470 | 27335 | val | (3234) | (115188) | 89256 | offered | withheld |
| 53 | K4,12 | cal | 16 | 2 | 12 | yes | 464 | 30125 | val | (3231) | (126911) | 104299 | offered | withheld |
| 54 | K5,11 | cal | 16 | 2 | 11 | yes | 457 | 31876 | val | (3229) | (134257) | 115619 | offered | withheld |
| 55 | K6,10 | cal | 16 | 2 | 10 | yes | 451 | 32903 | val | (3229) | (138599) | 123471 | offered | withheld |
| 56 | K7,9 | cal | 16 | 2 | 9 | yes | 444 | 33429 | val | (3230) | (140857) | 128133 | offered | withheld |
| 57 | K8,8 | cal | 16 | 2 | 8 | yes | 438 | 33589 | val | (3212) | (140934) | 129613 | offered | withheld |
| 58 | K2,2 | cal | 4 | 2 | 2 | yes | 154 | 436 | val | 6806 | 2246 | 1440 | offered | **offered** |
| 59 | K2,3 | cal | 5 | 2 | 3 | yes | 181 | 713 | val | 5768 | 3850 | 2648 | offered | **offered** |
| 60 | K3,3 | cal | 6 | 2 | 3 | yes | 202 | 1166 | val | 5012 | 6163 | 4612 | offered | **offered** |
| 61 | K4,4 | cal | 8 | 2 | 4 | yes | 249 | 2845 | val | 4245 | 14202 | 11518 | offered | **offered** |
| 62 | K5,5 | cal | 10 | 2 | 5 | yes | 296 | 6080 | val | 3825 | 28689 | 24427 | offered | **offered** |
| 63 | K6,6 | cal | 12 | 2 | 6 | yes | 343 | 11640 | val | 3556 | 52428 | 46062 | offered | **offered** |
| 64 | K7,7 | cal | 14 | 2 | 7 | yes | 390 | 20449 | val | 3371 | 88809 | 79788 | offered | **offered** |
| 65 | K3,5 | cal | 8 | 2 | 5 | yes | 255 | 2813 | val | 4286 | 14143 | 11110 | offered | **offered** |
| 66 | K4,8 | cal | 12 | 2 | 8 | yes | 356 | 11256 | val | 3580 | 50945 | 42455 | offered | **offered** |
| 67 | K2,8 | cal | 10 | 2 | 8 | yes | 316 | 5312 | val | 3857 | 25145 | 18414 | offered | **offered** |
| 68 | K1,7 | cal | 8 | 2 | 7 | yes | 268 | 2289 | val | 4287 | 11374 | 7233 | offered | **offered** |
| 69 | K1,10 | cal | 11 | 2 | 10 | yes | 349 | 5652 | val | 3712 | 26002 | 16682 | offered | **offered** |
| 70 | starR 8 | cal | 8 | 2 | 7 | yes | 268 | 2289 | val | 3203 | 9077 | 6633 | offered | **offered** |
| 71 | starR 12 | cal | 12 | 2 | 11 | yes | 376 | 7276 | val | 3140 | 29592 | 19108 | offered | **offered** |
| 72 | starR 16 | cal | 16 | 2 | 15 | yes | 483 | 16932 | val | 3111 | 69081 | 40949 | offered | **offered** |
| 73 | star5 | cal | 6 | 2 | 5 | yes | 215 | 1066 | val | 3268 | 3995 | 3182 | offered | **offered** |
| 74 | Q2 xor | cal | 4 | 2 | 2 | yes | 154 | 436 | val | 4134 | 1535 | 1385 | offered | **offered** |
| 75 | Q3 xor | cal | 8 | 3 | 3 | yes | 260 | 3647 | val | 4171 | 18153 | 16091 | offered | **offered** |
| 76 | Q4 xor | cal | 16 | 4 | 4 | yes | 435 | 74436 | val | (4223) | (388062) | 328678 | offered | withheld |
| 77 | Q2 Finset | cal | 4 | 2 | 2 | yes | 154 | 436 | val | 19585 | 5645 | 2458 | offered | **offered** |
| 78 | Q3 Finset | cal | 8 | 3 | 3 | yes | 260 | 3647 | val | 18049 | 66417 | 33784 | offered | **offered** |
| 79 | Q4 Finset | cal | 16 | 4 | 4 | yes | 435 | 74436 | val | (17822) | (1398009) | > 400007 (timeout) | offered | withheld |
| 80 | GP(3,1) | cal | 6 | 2 | 3 | yes | 202 | 1166 | val | 4620 | 5772 | 4362 | offered | **offered** |
| 81 | GP(4,1) | cal | 8 | 3 | 3 | yes | 260 | 3647 | val | 4579 | 19572 | 16871 | offered | **offered** |
| 82 | GP(5,1) | cal | 10 | 3 | 3 | yes | 288 | 7856 | val | 4550 | 42828 | 27486 | offered | **offered** |
| 83 | GP(5,2) | cal | 10 | 2 | 3 | yes | 257 | 4942 | val | 4551 | 26660 | 14516 | offered | **offered** |
| 84 | GP(6,1) | cal | 12 | 4 | 3 | yes | 347 | 22096 | val | (4526) | (121333) | 86312 | offered | withheld |
| 85 | GP(6,2) | cal | 12 | 4 | 3 | yes | 347 | 17155 | val | 4532 | 94131 | 58651 | offered | **offered** |
| 86 | GP(7,1) | cal | 14 | 4 | 3 | yes | 375 | 43592 | val | (4521) | (239903) | 129016 | offered | withheld |
| 87 | GP(7,2) | cal | 14 | 3 | 3 | yes | 343 | 23023 | val | (4521) | (126343) | 58893 | offered | withheld |
| 88 | GP(7,3) | cal | 14 | 3 | 3 | yes | 343 | 23023 | val | (4522) | (126366) | 58887 | offered | withheld |
| 89 | GP(8,1) | cal | 16 | 5 | 3 | yes | 433 | out: diameter 5 > 4 | val | (4526) | (621953) | 385198 | withheld | withheld |
| 90 | GP(8,2) | cal | 16 | 4 | 3 | yes | 402 | 54202 | val | (4524) | (298645) | 151568 | offered | withheld |
| 91 | GP(8,3) | cal | 16 | 4 | 3 | yes | 402 | 47723 | val | (4523) | (262808) | 147749 | offered | withheld |
| 92 | C16(1, 2) | cal | 16 | 4 | 4 | yes | 435 | >132304 | val | (5112) | (807775) | 411022 | offered | withheld |
| 93 | C16(1, 3) | cal | 16 | 4 | 4 | yes | 435 | 74436 | val | (5108) | (453788) | 371972 | offered | withheld |
| 94 | C16(1, 4) | cal | 16 | 3 | 4 | yes | 397 | 45502 | val | (5107) | (277013) | 137536 | offered | withheld |
| 95 | C16(1, 5) | cal | 16 | 4 | 4 | yes | 435 | 74436 | val | (5109) | (453862) | 372006 | offered | withheld |
| 96 | C16(1, 6) | cal | 16 | 3 | 4 | yes | 397 | 39723 | val | (5110) | (241843) | 125578 | offered | withheld |
| 97 | C16(1, 7) | cal | 16 | 4 | 4 | yes | 435 | >103370 | val | (5113) | (631033) | 425853 | offered | withheld |
| 98 | C16(1, 8) | cal | 16 | 4 | 3 | yes | 402 | 83379 | val | (5107) | (508331) | 219649 | offered | withheld |
| 99 | C16(2, 3) | cal | 16 | 3 | 4 | yes | 397 | 39723 | val | (5109) | (241803) | 125497 | offered | withheld |
| 100 | C16(1, 2, 3) | cal | 16 | 3 | 6 | yes | 449 | 72050 | val | (5633) | (476951) | 264407 | offered | withheld |
| 101 | C16(1, 2, 4) | cal | 16 | 3 | 6 | yes | 449 | 57725 | val | (5633) | (381933) | 255418 | offered | withheld |
| 102 | C16(1, 2, 3, 4) | cal | 16 | 2 | 8 | yes | 438 | 33589 | val | (6116) | (237985) | 104705 | offered | withheld |
| 103 | C16(1, 3, 5, 7) | cal | 16 | 2 | 8 | yes | 438 | 33589 | val | (6116) | (237985) | 137126 | offered | withheld |
| 104 | C12(1, 5) | cal | 12 | 3 | 4 | yes | 342 | 16926 | val | (5071) | (101900) | 72609 | offered | withheld |
| 105 | C12(1, 2) | cal | 12 | 3 | 4 | yes | 342 | 20544 | val | (5070) | (123845) | 69840 | offered | withheld |
| 106 | C12(1, 3) | cal | 12 | 3 | 4 | yes | 342 | 16926 | val | (5070) | (101883) | 75240 | offered | withheld |
| 107 | C13(1, 5) | cal | 13 | 2 | 4 | yes | 318 | 12252 | val | 5087 | 73715 | 35030 | offered | **offered** |
| 108 | C13(1, 3, 4) | cal | 13 | 2 | 6 | yes | 357 | 15139 | val | 5578 | 98639 | 50008 | offered | **offered** |
| 109 | C14(1, 4) | cal | 14 | 3 | 4 | yes | 369 | 19844 | val | (5088) | (119947) | 79488 | offered | withheld |
| 110 | C14(1, 2, 3) | cal | 14 | 3 | 6 | yes | 421 | 30868 | val | (5592) | (202534) | 161899 | offered | withheld |
| 111 | C15(1, 4) | cal | 15 | 3 | 4 | yes | 383 | 28963 | val | (5098) | (175750) | 103274 | offered | withheld |
| 112 | C10(1, 2) | cal | 10 | 3 | 4 | yes | 314 | 8355 | val | 5064 | 49806 | 39656 | offered | **offered** |
| 113 | C10(1, 3) | cal | 10 | 3 | 4 | yes | 314 | 8355 | val | 5063 | 49798 | 48059 | offered | **offered** |
| 114 | C8(1, 2) | cal | 8 | 2 | 4 | yes | 249 | 2845 | val | 5041 | 16331 | 10633 | offered | **offered** |
| 115 | C9(1, 3) | cal | 9 | 2 | 4 | yes | 263 | 4097 | val | 5054 | 23946 | 15030 | offered | **offered** |
| 116 | C11(1, 2) | cal | 11 | 3 | 4 | yes | 328 | 13799 | val | 5072 | 82929 | 54023 | offered | **offered** |
| 117 | grid 2x2 | cal | 4 | 2 | 2 | yes | 154 | 436 | val | 4189 | 1550 | 1394 | offered | **offered** |
| 118 | grid 2x3 | cal | 6 | 3 | 3 | yes | 233 | 1358 | val | 3991 | 6101 | 5282 | offered | **offered** |
| 119 | grid 2x4 | cal | 8 | 4 | 3 | yes | 291 | 4510 | val | 3920 | 21525 | 17329 | offered | **offered** |
| 120 | grid 2x5 | cal | 10 | 5 | 3 | yes | 350 | out: diameter 5 > 4 | val | (3878) | (71348) | 51717 | withheld | withheld |
| 121 | grid 2x6 | cal | 12 | 6 | 3 | yes | 409 | out: diameter 6 > 4 | val | (3848) | (228662) | 154370 | withheld | withheld |
| 122 | grid 2x7 | cal | 14 | 7 | 3 | yes | 468 | out: diameter 7 > 4 | val | (3830) | (720096) | 460661 | withheld | withheld |
| 123 | grid 2x8 | cal | 16 | 8 | 3 | yes | 526 | out: diameter 8 > 4 | val | (3823) | (2247359) | > 400006 (timeout) | withheld | withheld |
| 124 | grid 3x3 | cal | 9 | 4 | 4 | yes | 325 | 6572 | val | 3899 | 31535 | 24343 | offered | **offered** |
| 125 | grid 3x4 | cal | 12 | 5 | 4 | yes | 417 | out: diameter 5 > 4 | val | (3849) | (132248) | 94167 | withheld | withheld |
| 126 | grid 3x5 | cal | 15 | 6 | 4 | yes | 496 | out: diameter 6 > 4 | val | (3826) | (507685) | 330794 | withheld | withheld |
| 127 | grid 4x4 | cal | 16 | 6 | 4 | yes | 510 | out: diameter 6 > 4 | val | (3824) | (616493) | 420589 | withheld | withheld |
| 128 | torus 3x3 | cal | 9 | 2 | 4 | yes | 263 | 4097 | val | 4182 | 20521 | 13428 | offered | **offered** |
| 129 | torus 3x4 | cal | 12 | 3 | 4 | yes | 342 | 16926 | val | 4138 | 86266 | 58620 | offered | **offered** |
| 130 | torus 3x5 | cal | 15 | 3 | 4 | yes | 383 | 39350 | val | (4114) | (200538) | 101362 | offered | withheld |
| 131 | torus 4x4 | cal | 16 | 4 | 4 | yes | 435 | 74436 | val | (4110) | (379670) | 321107 | offered | withheld |
| 132 | torus 2x8 | cal | 16 | 5 | 3 | yes | 433 | out: diameter 5 > 4 | val | (4133) | (577733) | 351505 | withheld | withheld |
| 133 | heap 7 | cal | 7 | 4 | 3 | yes | 265 | 2780 | val | 3529 | 11994 | 8403 | offered | **offered** |
| 134 | heap 10 | cal | 10 | 5 | 3 | yes | 350 | out: diameter 5 > 4 | val | (3461) | (55486) | 31056 | withheld | withheld |
| 135 | heap 12 | cal | 12 | 6 | 3 | yes | 409 | out: diameter 6 > 4 | val | (3433) | (137618) | 70770 | withheld | withheld |
| 136 | heap 15 | cal | 15 | 6 | 3 | yes | 450 | out: diameter 6 > 4 | val | (3409) | (405593) | 161427 | withheld | withheld |
| 137 | heap 16 | cal | 16 | 7 | 3 | yes | 495 | out: diameter 7 > 4 | val | (3405) | (594856) | 246748 | withheld | withheld |
| 138 | spider 3 | cal | 7 | 4 | 3 | yes | 265 | 2549 | val | 4144 | 12409 | 8180 | offered | **offered** |
| 139 | spider 5 | cal | 11 | 4 | 5 | yes | 359 | 10945 | val | 4066 | 54756 | 27500 | offered | **offered** |
| 140 | spider 7 | cal | 15 | 4 | 7 | yes | 453 | 30479 | val | (4034) | (152748) | 62900 | offered | withheld |
| 141 | wheel 6 | cal | 6 | 2 | 5 | yes | 228 | 1149 | val | 4175 | 5238 | 4051 | offered | **offered** |
| 142 | wheel 8 | cal | 8 | 2 | 7 | yes | 281 | 2721 | val | 4166 | 13352 | 8775 | offered | **offered** |
| 143 | wheel 12 | cal | 12 | 2 | 11 | yes | 389 | 9324 | val | 4159 | 47399 | 25374 | offered | **offered** |
| 144 | wheel 16 | cal | 16 | 2 | 15 | yes | 496 | 22273 | val | (4168) | (114398) | 53415 | offered | withheld |
| 145 | windmill 7 | cal | 7 | 2 | 6 | yes | 248 | 1723 | val | 3669 | 7424 | 5278 | offered | **offered** |
| 146 | windmill 11 | cal | 11 | 2 | 10 | yes | 355 | 6390 | val | 3592 | 28736 | 17171 | offered | **offered** |
| 147 | windmill 15 | cal | 15 | 2 | 14 | yes | 463 | 16075 | val | 3557 | 72652 | 38630 | offered | **offered** |
| 148 | lolli K5+1 | cal | 6 | 2 | 5 | yes | 234 | 1070 | val | 3778 | 4470 | 3627 | offered | **offered** |
| 149 | lolli K5+2 | cal | 7 | 3 | 5 | yes | 286 | 2847 | val | 3787 | 12987 | 10745 | offered | **offered** |
| 150 | lolli K5+3 | cal | 8 | 4 | 5 | yes | 343 | 9729 | val | 3793 | 45988 | 37866 | offered | **offered** |
| 151 | lolli K5+4 | cal | 9 | 5 | 5 | yes | 395 | out: diameter 5 > 4 | val | (3794) | (179950) | 148832 | withheld | withheld |
| 152 | lolli K5+5 | cal | 10 | 6 | 5 | yes | 453 | out: diameter 6 > 4 | val | (3794) | (737117) | > 400006 (timeout) | withheld | withheld |
| 153 | lolli K4+4 | cal | 8 | 5 | 4 | yes | 342 | out: diameter 5 > 4 | val | (3841) | (60953) | 47620 | withheld | withheld |
| 154 | lolli K8+4 | cal | 12 | 5 | 8 | yes | 553 | out: diameter 5 > 4 | val | (3693) | (2630679) | recdepth at 157182 | withheld | withheld |
| 155 | lolli K10+3 | cal | 13 | 4 | 10 | yes | 575 | out: recursion estimate 575 > 500 | val | (3634) | (1107587) | recdepth at 52658 | offered | withheld |
| 156 | lolli K12+4 | cal | 16 | 5 | 12 | yes | 765 | out: diameter 5 > 4 | val | (3618) | (30389702) | recdepth at 12336 | withheld | withheld |
| 157 | barbell 3 | cal | 6 | 3 | 3 | yes | 233 | 1596 | val | 4190 | 7571 | 5532 | offered | **offered** |
| 158 | barbell 4 | cal | 8 | 3 | 4 | yes | 286 | 5289 | val | 4099 | 26274 | 16830 | offered | **offered** |
| 159 | barbell 5 | cal | 10 | 3 | 5 | yes | 340 | 15142 | val | 4044 | 75688 | 43447 | offered | **offered** |
| 160 | barbell 6 | cal | 12 | 3 | 6 | yes | 394 | 37406 | val | (3998) | (186278) | 98926 | offered | withheld |
| 161 | barbell 8 | cal | 16 | 3 | 8 | yes | 501 | out: recursion estimate 501 > 500 | val | (3963) | (804504) | 387329 | offered | withheld |
| 162 | dstar 8 | cal | 8 | 3 | 4 | yes | 286 | 3091 | val | 4252 | 15511 | 9684 | offered | **offered** |
| 163 | dstar 12 | cal | 12 | 3 | 6 | yes | 394 | 11349 | val | 4176 | 58036 | 29183 | offered | **offered** |
| 164 | dstar 16 | cal | 16 | 3 | 8 | yes | 501 | out: recursion estimate 501 > 500 | val | (4145) | (151830) | 64241 | offered | withheld |
| 165 | compl C8 | cal | 8 | 2 | 5 | yes | 268 | 2820 | val | 4720 | 15330 | 11451 | offered | **offered** |
| 166 | compl C12 | cal | 12 | 2 | 9 | yes | 402 | 10338 | val | 4714 | 58273 | 44253 | offered | **offered** |
| 167 | compl C16 | cal | 16 | 2 | 13 | yes | 535 | out: recursion estimate 535 > 500 | val | (4721) | (147647) | 112773 | offered | withheld |
| 168 | compl P6 | cal | 6 | 2 | 4 | yes | 221 | 1157 | val | 3453 | 4569 | 4134 | offered | **offered** |
| 169 | top Finset(Fin 4) | cal | 16 | 1 | 15 | yes | 465 | 11550 | val | 7710 | 99293 | 46047 | offered | **offered** |
| 170 | top Fin4->Bool | cal | 16 | 1 | 15 | yes | 465 | 11550 | val | (10253) | (128234) | 74612 | offered | withheld |
| 171 | top Fin2xFin8 | cal | 16 | 1 | 15 | yes | 465 | 11550 | val | 3677 | 53396 | 36874 | offered | **offered** |
| 172 | K(Fin2+Fin3) | cal | 5 | 1 | 4 | yes | 170 | 568 | val | 6258 | 3060 | 1809 | offered | **offered** |
| 173 | top Bool | cal | 2 | 1 | 1 | yes | 89 | 201 | val | 1203 | 239 | 232 | offered | **offered** |
| 174 | fromEdgeSet P3 | cal | 3 | 2 | 2 | yes | 134 | 280 | val | 11854 | 1584 | 783 | offered | **offered** |
| 175 | unicode | cal | 4 | 3 | 2 | yes | 179 | 472 | val | 3063 | 1398 | 1357 | offered | **offered** |
| 176 | bot Fin1 | cal | 1 | 0 | 0 | yes | 51 | 174 | val | 5547 | 201 | 88 | offered | **offered** |
| 177 | c8list | cal | 8 | 4 | 2 | yes | 259 | 4590 | val | 10280 | 50038 | 32221 | offered | **offered** |
| 178 | q3list | cal | 8 | 3 | 3 | yes | 260 | 3647 | val | 12987 | 48813 | 35534 | offered | **offered** |
| 179 | petersenList | cal | 10 | 2 | 3 | yes | 257 | 4942 | val | 15717 | 79946 | 26866 | offered | **offered** |
| 180 | fromEdgeSet C8 | cal | 8 | 4 | 2 | yes | 259 | 4590 | val | (34939) | (159054) | 52908 | offered | withheld |
| 181 | fromEdgeSet Q3 | cal | 8 | 3 | 3 | yes | 260 | 3647 | val | (47826) | (169975) | 61840 | offered | withheld |
| 182 | fromEdgeSet petersen | cal | 10 | 2 | 3 | yes | 257 | 4942 | val | (61254) | (297258) | 43087 | offered | withheld |
| 183 | fromEdgeSet star16 | cal | 16 | 2 | 15 | yes | 483 | 16932 | val | (66465) | (1131070) | 74125 | offered | withheld |
| 184 | fromEdgeSet K4,4 | cal | 8 | 2 | 4 | yes | 249 | 2845 | val | (58466) | (159262) | 33616 | offered | withheld |
| 185 | fromEdgeSet heap15 | cal | 15 | 6 | 3 | yes | 450 | out: diameter 6 > 4 | val | (62210) | (5812559) | > 400010 (timeout) | withheld | withheld |
| 186 | fromEdgeSet grid3x3 | cal | 9 | 4 | 4 | yes | 325 | 6572 | val | (49689) | (324698) | 102730 | offered | withheld |
| 187 | bot Fin2 | cal | 2 | 0 | 0 | no | 76 | 183 | val | 3186 | 228 | 127 | offered | **offered** |
| 188 | bot Fin3 | cal | 3 | 0 | 0 | no | 102 | 189 | val | 2610 | 240 | 146 | offered | **offered** |
| 189 | bot Fin4 | cal | 4 | 0 | 0 | no | 127 | 196 | val | 2356 | 259 | 165 | offered | **offered** |
| 190 | bot Fin8 | cal | 8 | 0 | 0 | no | 229 | 239 | val | 2038 | 381 | 241 | offered | **offered** |
| 191 | bot Fin12 | cal | 12 | 0 | 0 | no | 330 | 305 | val | 1959 | 570 | 317 | offered | **offered** |
| 192 | bot Fin13 | cal | 13 | 0 | 0 | no | 355 | out: disconnected with 13 vertices > 12 | val | (1949) | (627) | 337 | withheld | withheld |
| 193 | bot Fin16 | cal | 16 | 0 | 0 | no | 432 | out: disconnected with 16 vertices > 12 | val | (1929) | (824) | 394 | withheld | withheld |
| 194 | bot subtype | cal | 2 | 0 | 0 | no | 76 | 183 | val | 15064 | 393 | 187 | offered | **offered** |
| 195 | twoTriangles | cal | 6 | 1 | 2 | no | 256 | 584 | val | 8479 | 4096 | 4061 | offered | **offered** |
| 196 | twoPaths10 | cal | 10 | 4 | 2 | no | 403 | 2815 | val | 3386 | 11771 | 8820 | offered | **offered** |
| 197 | myGraph | cal | 6 | 2 | 2 | no | 236 | 359 | val | 3504 | 1022 | 789 | offered | **offered** |
| 198 | 2K3 | cal | 6 | 1 | 2 | no | 256 | 584 | val | 3387 | 1987 | 1772 | offered | **offered** |
| 199 | 2K4 | cal | 8 | 1 | 3 | no | 385 | 15681 | val | 3306 | 66960 | 64446 | withheld | **offered** |
| 200 | 2K5 | cal | 10 | 1 | 4 | no | 539 | out: recursion estimate 539 > 500 | val | (3264) | (6314813) | > 400006 (timeout) | withheld | withheld |
| 201 | 2K6 | cal | 12 | 1 | 5 | no | 720 | out: recursion estimate 720 > 500 | val | (3236) | (1034180454) | > 400006 (timeout) | withheld | withheld |
| 202 | 2K8 | cal | 16 | 1 | 7 | no | 1160 | out: disconnected with 16 vertices > 12 | val | (3203) | (87609150062742) | recdepth at 140701 | withheld | withheld |
| 203 | 3K3 | cal | 9 | 1 | 2 | no | 371 | 4399 | val | 3286 | 18299 | 15395 | offered | **offered** |
| 204 | 3K4 | cal | 12 | 1 | 3 | no | 564 | out: recursion estimate 564 > 500 | val | (3241) | (6908409) | > 400006 (timeout) | withheld | withheld |
| 205 | 3K5 | cal | 15 | 1 | 4 | no | 796 | out: disconnected with 15 vertices > 12 | val | (3213) | (8172772154) | > 400006 (timeout) | withheld | withheld |
| 206 | 4K4 | cal | 16 | 1 | 3 | no | 744 | out: disconnected with 16 vertices > 12 | val | (3211) | (684293575) | > 400006 (timeout) | withheld | withheld |
| 207 | 5K3 | cal | 15 | 1 | 2 | no | 601 | out: disconnected with 15 vertices > 12 | val | (3218) | (1730291) | > 400006 (timeout) | withheld | withheld |
| 208 | 2K2 | cal | 4 | 1 | 1 | no | 153 | 223 | val | 3597 | 415 | 292 | offered | **offered** |
| 209 | 3K2 | cal | 6 | 1 | 1 | no | 217 | 281 | val | 3389 | 657 | 459 | offered | **offered** |
| 210 | 4K2 | cal | 8 | 1 | 1 | no | 281 | 387 | val | 3311 | 1106 | 680 | offered | **offered** |
| 211 | 6K2 | cal | 12 | 1 | 1 | no | 408 | 812 | val | 3244 | 2896 | 1287 | offered | **offered** |
| 212 | 8K2 | cal | 16 | 1 | 1 | no | 536 | out: disconnected with 16 vertices > 12 | val | (3215) | (6346) | 2125 | withheld | withheld |
| 213 | 2C3 | cal | 6 | 1 | 2 | no | 256 | 584 | val | 3741 | 2133 | 1903 | offered | **offered** |
| 214 | 2C4 | cal | 8 | 2 | 2 | no | 333 | 2156 | val | 3657 | 9421 | 8259 | offered | **offered** |
| 215 | 2C5 | cal | 10 | 2 | 2 | no | 409 | 9446 | val | 3613 | 42963 | 36168 | offered | **offered** |
| 216 | 2C6 | cal | 12 | 3 | 2 | no | 486 | 42939 | val | (3576) | (195883) | 160229 | offered | withheld |
| 217 | 2C8 | cal | 16 | 4 | 2 | no | 640 | out: disconnected with 16 vertices > 12 | val | (3551) | (3949413) | > 400006 (timeout) | withheld | withheld |
| 218 | 3C4 | cal | 12 | 2 | 2 | no | 486 | 42750 | val | (3548) | (193825) | 158194 | offered | withheld |
| 219 | 3C5 | cal | 15 | 2 | 2 | no | 601 | out: disconnected with 15 vertices > 12 | val | (3526) | (1857208) | > 400006 (timeout) | withheld | withheld |
| 220 | 4C4 | cal | 16 | 2 | 2 | no | 640 | out: disconnected with 16 vertices > 12 | val | (3507) | (3907786) | > 400006 (timeout) | withheld | withheld |
| 221 | 4C3 | cal | 12 | 1 | 2 | no | 486 | 42694 | val | (3533) | (192933) | 157211 | offered | withheld |
| 222 | 5C3 | cal | 15 | 1 | 2 | no | 601 | out: disconnected with 15 vertices > 12 | val | (3503) | (1847191) | > 400006 (timeout) | withheld | withheld |
| 223 | 2P6 | cal | 12 | 5 | 2 | no | 480 | 10703 | val | 3489 | 47453 | 35382 | offered | **offered** |
| 224 | 2P8 | cal | 16 | 7 | 2 | no | 633 | out: disconnected with 16 vertices > 12 | val | (3452) | (795850) | recdepth at 244191 | withheld | withheld |
| 225 | 3P4 | cal | 12 | 3 | 2 | no | 480 | 6134 | val | 3488 | 26940 | 18863 | offered | **offered** |
| 226 | 3P5 | cal | 15 | 4 | 2 | no | 595 | out: disconnected with 15 vertices > 12 | val | (3457) | (236501) | 167023 | withheld | withheld |
| 227 | 4P4 | cal | 16 | 3 | 2 | no | 633 | out: disconnected with 16 vertices > 12 | val | (3452) | (233226) | 153451 | withheld | withheld |
| 228 | 5P3 | cal | 15 | 2 | 2 | no | 549 | out: disconnected with 15 vertices > 12 | val | (3458) | (44753) | 25059 | withheld | withheld |
| 229 | 8P2 | cal | 16 | 1 | 1 | no | 536 | out: disconnected with 16 vertices > 12 | val | (3452) | (6693) | 2282 | withheld | withheld |
| 230 | P11+1K1 | cal | 12 | 10 | 2 | no | 480 | 24757 | val | (3425) | (108970) | 58158 | offered | withheld |
| 231 | P5+7K1 | cal | 12 | 4 | 2 | no | 480 | 8829 | val | 3428 | 38514 | 28369 | offered | **offered** |
| 232 | P15+1K1 | cal | 16 | 14 | 2 | no | 633 | out: disconnected with 16 vertices > 12 | val | (3399) | (1776901) | recdepth at 135461 | withheld | withheld |
| 233 | P8+8K1 | cal | 16 | 7 | 2 | no | 633 | out: disconnected with 16 vertices > 12 | val | (3399) | (786378) | recdepth at 240320 | withheld | withheld |
| 234 | P3+13K1 | cal | 16 | 2 | 2 | no | 588 | out: disconnected with 16 vertices > 12 | val | (3399) | (67020) | 37487 | withheld | withheld |
| 235 | K1+P11 | cal | 12 | 10 | 2 | no | 330 | 305 | val | 3420 | 767 | 337 | offered | **offered** |
| 236 | K1+P15 | cal | 16 | 14 | 2 | no | 432 | out: disconnected with 16 vertices > 12 | val | (3396) | (1152) | 424 | withheld | withheld |
| 237 | C11+1K1 | cal | 12 | 5 | 2 | no | 486 | 44902 | val | (3624) | (207015) | 169483 | offered | withheld |
| 238 | C15+1K1 | cal | 16 | 7 | 2 | no | 640 | out: disconnected with 16 vertices > 12 | val | (3610) | (4054953) | recdepth at 284655 | withheld | withheld |
| 239 | C8+8K1 | cal | 16 | 4 | 2 | no | 640 | out: disconnected with 16 vertices > 12 | val | (3424) | (3839206) | > 400006 (timeout) | withheld | withheld |
| 240 | C3+13K1 | cal | 16 | 1 | 2 | no | 640 | out: disconnected with 16 vertices > 12 | val | (3330) | (3754034) | > 400006 (timeout) | withheld | withheld |
| 241 | C5+3K1 | cal | 8 | 2 | 2 | no | 333 | 2201 | val | 3573 | 9458 | 8363 | offered | **offered** |
| 242 | K1+C11 | cal | 12 | 5 | 2 | no | 330 | 305 | val | 3955 | 840 | 338 | offered | **offered** |
| 243 | K1+C15 | cal | 16 | 7 | 2 | no | 432 | out: disconnected with 16 vertices > 12 | val | (3961) | (1279) | 425 | withheld | withheld |
| 244 | K5+1K1 | cal | 6 | 1 | 4 | no | 334 | 4752 | val | 3429 | 20464 | 20345 | withheld | **offered** |
| 245 | K4+4K1 | cal | 8 | 1 | 3 | no | 385 | 15681 | val | 3349 | 67627 | 65320 | withheld | **offered** |
| 246 | K5+11K1 | cal | 16 | 1 | 4 | no | 848 | out: disconnected with 16 vertices > 12 | val | (3244) | (34369607821) | > 400006 (timeout) | withheld | withheld |
| 247 | K3+13K1 | cal | 16 | 1 | 2 | no | 640 | out: disconnected with 16 vertices > 12 | val | (3244) | (3679476) | > 400006 (timeout) | withheld | withheld |
| 248 | K8+8K1 | cal | 16 | 1 | 7 | no | 1160 | out: disconnected with 16 vertices > 12 | val | (3244) | (88463771797827) | recdepth at 142808 | withheld | withheld |
| 249 | K2+14K1 | cal | 16 | 1 | 1 | no | 536 | out: disconnected with 16 vertices > 12 | val | (3243) | (6387) | 2156 | withheld | withheld |
| 250 | 2Q3 | cal | 16 | 3 | 3 | no | 744 | out: disconnected with 16 vertices > 12 | val | (3700) | (763759395) | > 400006 (timeout) | withheld | withheld |
| 251 | rook3 | val | 9 | 2 | 4 | yes | 263 | 4097 | val | 5754 | 26695 | 13906 | offered | **offered** |
| 252 | prismB4 | val | 8 | 3 | 3 | yes | 260 | 3647 | val | 6674 | 26858 | 17299 | offered | **offered** |
| 253 | cubeFn2 | val | 4 | 2 | 2 | yes | 154 | 436 | val | 18203 | 5277 | 2707 | offered | **offered** |
| 254 | cubeFn3 | val | 8 | 3 | 3 | yes | 260 | 3647 | val | 16693 | 61702 | 38739 | offered | **offered** |
| 255 | compB3 | val | 8 | 2 | 7 | yes | 307 | 2758 | val | 18131 | 49690 | 17420 | offered | **offered** |
| 256 | kneserish (16, disc) | val | 16 | 1 | 1 | no | 536 | out: disconnected with 16 vertices > 12 | val | (10750) | (17142) | 3230 | withheld | withheld |
| 257 | mulMod 10 7 3 | val | 10 | 2 | 2 | no | 377 | 1278 | val | 3707 | 5386 | 3759 | offered | **offered** |
| 258 | mulMod 12 5 1 | val | 12 | 2 | 3 | no | 564 | out: recursion estimate 564 > 500 | val | (3685) | (7631444) | > 400006 (timeout) | withheld | withheld |
| 259 | mulMod 14 6 2 | val | 14 | 2 | 6 | no | 901 | out: disconnected with 14 vertices > 12 | val | (3675) | (639521330) | > 400006 (timeout) | withheld | withheld |
| 260 | mulMod 16 5 0 | val | 16 | 2 | 3 | no | 744 | out: disconnected with 16 vertices > 12 | val | (3669) | (758718872) | > 400006 (timeout) | withheld | withheld |
| 261 | divG 8 | val | 8 | 2 | 7 | yes | 288 | 2590 | val | 3541 | 11162 | 7919 | offered | **offered** |
| 262 | divG 12 | val | 12 | 2 | 11 | yes | 408 | 9468 | val | 3480 | 41827 | 25736 | offered | **offered** |
| 263 | divG 16 | val | 16 | 2 | 15 | yes | 529 | out: recursion estimate 529 > 500 | val | (3451) | (105663) | 57733 | offered | withheld |
| 264 | ladder 3 | val | 6 | 3 | 3 | yes | 233 | 1358 | val | 3863 | 5949 | 5203 | offered | **offered** |
| 265 | ladder 4 | val | 8 | 4 | 3 | yes | 291 | 4510 | val | 3817 | 21078 | 17024 | offered | **offered** |
| 266 | ladder 5 | val | 10 | 5 | 3 | yes | 350 | out: diameter 5 > 4 | val | (3792) | (70093) | 50655 | withheld | withheld |
| 267 | modClasses 9 3 | val | 9 | 1 | 2 | no | 371 | 4364 | val | 3267 | 18067 | 15174 | offered | **offered** |
| 268 | modClasses 12 4 | val | 12 | 1 | 2 | no | 486 | 42654 | val | (3220) | (179454) | 139709 | offered | withheld |
| 269 | modClasses 12 6 | val | 12 | 1 | 1 | no | 408 | 794 | val | 3226 | 2808 | 1224 | offered | **offered** |
| 270 | modClasses 10 5 | val | 10 | 1 | 1 | no | 344 | 542 | val | 3252 | 1752 | 897 | offered | **offered** |
| 271 | list20 | val | 10 | 2 | 5 | yes | 296 | 5623 | val | (18975) | (109107) | 37314 | offered | withheld |
| 272 | top Fin3xFin3 | val | 9 | 1 | 8 | yes | 277 | 2303 | val | 4563 | 12040 | 7719 | offered | **offered** |
| 273 | top Fin2+Fin4 | val | 6 | 1 | 5 | yes | 197 | 837 | val | 5597 | 4574 | 2836 | offered | **offered** |
| 274 | top subtype10 | val | 5 | 1 | 4 | yes | 170 | 568 | val | 6952 | 3337 | 1836 | offered | **offered** |
| 275 | top Fin2->Fin3 | val | 9 | 1 | 8 | yes | 277 | 2303 | val | 10144 | 23950 | 13585 | offered | **offered** |
| 276 | fromEdgeSet C5 | val | 5 | 2 | 2 | yes | 168 | 703 | val | 22327 | 12624 | 4051 | offered | **offered** |
| 277 | fromEdgeSet K4 | val | 4 | 1 | 3 | yes | 143 | 382 | val | 22579 | 5187 | 1460 | offered | **offered** |
| 278 | fromEdgeSet star6 | val | 6 | 2 | 5 | yes | 215 | 1066 | val | 23061 | 21735 | 4784 | offered | **offered** |
| 279 | fromEdgeSet 2P3 | val | 6 | 2 | 2 | no | 236 | 359 | val | 19539 | 4056 | 1994 | offered | **offered** |
| 280 | twoK4 (suite) | val | 8 | 1 | 3 | no | 385 | 15681 | val | 3090 | 63610 | 61632 | withheld | **offered** |
| 281 | K7,7 (suite) | val | 14 | 2 | 7 | yes | 390 | 20449 | val | 3371 | 88809 | 79786 | offered | **offered** |
| 282 | Q3 Finset (suite) | val | 8 | 3 | 3 | yes | 260 | 3647 | val | 18048 | 66414 | 33785 | offered | **offered** |
| 283 | cycleGraph 5 compl | val | 5 | 2 | 2 | yes | 168 | 703 | val | 4750 | 3239 | 2332 | offered | **offered** |
| 284 | hasse Fin4 (guarded) | val | 4 | 3 | 2 | yes | 179 | 472 | q: SimpleGraph.instDecidableRelAdjHasseOfFintypeOfDecidableLT | (7917) | (2865) | 1993 | offered | withheld |
| 285 | broom 6 3 | val | 10 | 4 | 7 | yes | 384 | 7714 | val | 3868 | 36897 | 23363 | offered | **offered** |
| 286 | broom 8 3 | val | 12 | 4 | 9 | yes | 451 | 13535 | val | 3828 | 64699 | 39340 | offered | **offered** |
| 287 | broom 10 3 | val | 14 | 4 | 11 | yes | 518 | out: recursion estimate 518 > 500 | val | (3800) | (103788) | 61349 | offered | withheld |
| 288 | broom 12 3 | val | 16 | 4 | 13 | yes | 584 | out: recursion estimate 584 > 500 | val | (3785) | (156290) | recdepth at 37947 | offered | withheld |
| 289 | broom 12 2 | val | 15 | 3 | 13 | yes | 474 | 16795 | val | 3781 | 79657 | 49436 | offered | **offered** |
| 290 | broom 13 2 | val | 16 | 3 | 14 | yes | 501 | out: recursion estimate 501 > 500 | val | (3776) | (96339) | 59019 | offered | withheld |
| 291 | broom 14 1 | val | 16 | 2 | 15 | yes | 483 | 16932 | val | 3764 | 80027 | 41547 | offered | **offered** |
| 292 | caterpillar 2 | val | 9 | 4 | 4 | yes | 325 | 5521 | val | 3992 | 26884 | 16134 | offered | **offered** |
| 293 | caterpillar 3 | val | 12 | 4 | 5 | yes | 399 | 14946 | val | 3906 | 72661 | 36538 | offered | **offered** |
| 294 | caterpillar 4 | val | 15 | 4 | 6 | yes | 473 | 32924 | val | (3857) | (159257) | 69474 | offered | withheld |
| 295 | lolli K6+3 | val | 9 | 4 | 6 | yes | 390 | 21083 | val | 3749 | 99490 | 83742 | offered | **offered** |
| 296 | lolli K7+3 | val | 10 | 4 | 7 | yes | 436 | 42610 | val | (3705) | (199853) | 171535 | offered | withheld |
| 297 | lolli K8+3 | val | 11 | 4 | 8 | yes | 482 | 80337 | val | (3678) | (375193) | 326554 | offered | withheld |
| 298 | lolli K6+2 | val | 8 | 3 | 6 | yes | 325 | 4966 | val | 3736 | 22885 | 19061 | offered | **offered** |
| 299 | lolli K8+2 | val | 10 | 3 | 8 | yes | 405 | 13154 | val | 3665 | 60742 | 50908 | offered | **offered** |
| 300 | lolli K10+2 | val | 12 | 3 | 10 | yes | 485 | 29613 | val | (3610) | (135902) | 114848 | offered | withheld |

</details>

#### Round-2 expected-output changes (documented)

* The 17 round-1 `#connectivity_gate` pins: the message format changed
  because the shape budget it reported no longer exists.  Old:
  `shape budget: yes; adjacency: validated; connectivity link: offered`.
  New: `walk budget at zero adjacency cost: yes (estimate 919); adjacency:
  validated; measured adjacency cost: within the cap of 132196 per decision;
  connectivity link: offered` (that one is `pathGraph 5`).  For every one of
  the 17 graphs the adjacency verdict and the offered / withheld verdict are
  unchanged; the new fields pin the walk-work estimate at zero cost and where
  the measured cost falls relative to the cap (both deterministic: the
  measured cost itself varies by a few raw heartbeats between runs — 2789,
  2790, 2791, 2773 for `pathGraph 5` — so it is pinned within a band by
  `#adjacency_cost` instead).
* No other expected output changed.  The pure `connectivityInsertable` pins
  (`path 4` … `empty 0`, `lollipop10`, `twoK5`) keep their values under the
  new model at the reference cost `cheapAdjacencyCost` (`star 16`: estimate
  67221 ≤ 100000, recursion estimate 483 ≤ 500; `complete 16`: 45691 and
  465); every `#assert_insertions_compile` table and every ClickE2E
  transcript stand.  The graphs whose connectivity links QED64's showcase
  expectations record (`cycleGraph 5`, `completeGraph (Fin 4)`, its own
  `twoTriangles`, `pathGraph 5`, `cycleGraph 6`) are all small and still
  offered by the package's suite pins or the sweep (the showcase itself was
  not re-run here: no browsers in this round).

#### Round-2 verification transcript

All through the shared lock (`BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock`,
lanes `fix2-graph-scope-*`, one lake invocation at a time, stdin from
`/dev/null`); probe sources and logs in the session scratchpad
(`…/scratchpad/gs-fix2/`).

| Lane | Command | Result |
|---|---|---|
| `fix2-graph-scope-smoke` | `lake env lean Smoke.lean` (sweep harness, 8 graphs) | `K16` 34126 heartbeats (= the re-audit's `#count_heartbeats` figure), Petersen 14515, Q3 16090; rc 0 |
| `fix2-graph-scope-sweep1` | `lake env lean Sweep.lean` (calibration sweep, 250 graphs, cap 400000) | 250 `SWEEP` rows in 22m33s; rc 1 by design (the over-budget examples are logged errors: timeouts and recursion-depth failures) |
| `fix2-graph-scope-build1` | `lake build` (first cost-model draft) | `Build completed successfully (1070 jobs).` |
| `fix2-graph-scope-unit` | `lake env lean Unit.lean` (adjacency / equality cost probes, 250 graphs) | 250 `UNIT` rows, 13.7 s; rc 0 |
| `fix2-graph-scope-unit2` | `lake env lean Unit2.lean` (walk-level probe, rejected variant) | 244 rows; 6 `fromEdgeSet` literals: `failed to synthesize … LocallyFinite`; rc 1 |
| `fix2-graph-scope-insert1` / `-insert2` | `lake build GraphScopeTests.InsertTests` | first: a field-notation error in the new `#connectivity_gate` (fixed); second: only the expected `#guard_msgs` mismatches of the reformatted pins, and `maximum recursion depth` in three examples compiled under `maxRecDepth 256` (see "Recursion depth") |
| `fix2-graph-scope-minrec` | `lake env lean MinRec.lean` (smallest `maxRecDepth` under which each of 58 offered texts compiles, bisected) | 58 `MINREC` rows in 31 min; rc 0 (see "Recursion depth") |
| `fix2-graph-scope-insert3` | `lake build GraphScopeTests.InsertTests GraphScopeTests.HasseLinkTests` | the measured adjacency costs differ from the previous run by a few raw heartbeats (2791 → 2790, 5770 → 5768, 11859 → 11855; a second measurement in one command: 2789 → 2773), so exact measured costs cannot be pinned: pins switched to "within the cap" plus a band (`#adjacency_cost`) |
| `fix2-graph-scope-sweep2` | `lake build GraphScope`, then `lake env lean Sweep2.lean` (validation sweep on the final heartbeat model: the 250 calibration graphs with every offered example re-measured, plus 51 out-of-sample graphs always measured, plus four `#count_heartbeats in` cross-checks) | `Build completed successfully (1070 jobs).`; 300 `SWEEP2` rows (the `Sum`-typed `sumG` probe graph had no `DecidableRel` instance); `#count_heartbeats in`: `Used 34128 heartbeats` (`completeGraph (Fin 16)`; the sweep's own measurement 34124), `Used 328717` (the 4-cube, 328678), `Used 79781` (`K₇,₇`, 79784–79788), `Used 4062` (`¬ twoTriangles`, 4062); rc 1 by design (over-budget examples) |
| `fix2-graph-scope-adjrec` | `lake env lean AdjRec.lean` (smallest `maxRecDepth` of the adjacency-cost proposition, 58 graphs) | 58 rows; not predictive of the example's need (used only to rule that out) |
| `fix2-graph-scope-insert4` / `-insert5` | `lake build GraphScopeTests.InsertTests GraphScopeTests.HasseLinkTests`, then `lake env lean Sweep3.lean` (verdicts of the final model incl. `recursionEstimate`, no measurement) | first: a missing `Bool` annotation in `#adjacency_cost` (fixed); 300 `SWEEP3` rows; second: `Build completed successfully (1075 jobs).` |
| `fix2-graph-scope-mutations` (+ `-mutation-m11`) | `mutate.py`: one mutation at a time, `lake build GraphScopeTests.InsertTests GraphScopeTests.HasseLinkTests`, file restored and checked by SHA-256 | see the mutation table below: all 8 caught |
| `fix2-graph-scope-final` (final tree, `MIN_FREE_GB=20`) | `lake build`; `lake test` | `✔ [1069/1070] Built GraphScope (893ms)` / `Build completed successfully (1070 jobs).` BUILD_EXIT=0; `✔ [1082/1085] Built GraphScopeTests.InsertTests (15s)` / `✔ [1083/1085] Built GraphScopeTests.ClickE2E (20s)` / `⚠ [1084/1085] Built GraphScopeTests.HasseLinkTests (11s)` / `✔ [1085/1085] Built GraphScopeTests (979ms)` TEST_EXIT=0, `browser-lock: command exited rc=0` |
| `fix2-graph-scope-final3` / `-final5` (after comment/docstring corrections only: the broom's leaf count in an `Insert.lean` docstring, four test comments) | `lake build`; `lake build` of every test module except `ClickE2E` (`MIN_FREE_GB=10`: the `ClickE2E` lane needs 20 GiB and the host had 17–18) | final5: `Build completed successfully (1070 jobs).` BUILD_EXIT=0; `✔ [1082/1083] Built GraphScopeTests.InsertTests (11s)` / `⚠ [1083/1083] Built GraphScopeTests.HasseLinkTests (11s)` / `Build completed successfully (1083 jobs).` exit 0 |
| `fix2-graph-scope-final4` / `-final6` | `lake test` on the final tree (`MIN_FREE_GB=20`) | not run: the lock's memory cooldown waited 10–20 min with 14.9–18.6 GiB reclaimable (need 20) and was stopped.  The last full `lake test` is `fix2-graph-scope-final` above; since then only comments and one docstring changed, and every module except `ClickE2E` (source unchanged since round 1) was rebuilt green in `-final5` |

Warnings in the final run: the 7 Lake module-system warnings only (gotcha 3),
unchanged from round 1.

**Mutations** (each applied alone, `lake build GraphScopeTests.InsertTests
GraphScopeTests.HasseLinkTests`, then the file restored byte-identical):

| Mutation | Result |
|---|---|
| M2 (re-audit): `AdjCost.unknown` offers the link | caught: the `(limit := 1)` gate pin and `#guard AdjCost.unknown.connectivityOk == false` |
| M3 (re-audit): `Fintype.decidableForallFintype` / `decidableExistsFintype` dropped from the deny-list | caught: the three new deny-list pins (`Bool × Bool` ∀, `Fin 2 × Fin 3` ∃, `Finset (Fin 4)` ∀) |
| M7: the measured adjacency cost ignored (0) | caught: the `q4fin` and `Finset (Fin 4)` 4-cube gate pins, the `fromEdgeSet` 3-cube pin, and `#assert_insertions_compile q4fin` (the offered example then times out: `(deterministic) timeout at whnf … 200000`) |
| M8: the heartbeat estimate ignored (the v4.34 shape budget) | caught: 7 `#guard` pins of `connectivityVerdict` / `connectivityInsertable` |
| M9: the walk count does not stop at the first unreachable pair | caught: 10 pins (`walkWork twoPaths`, `walkWork (empty 12)`, disconnected gate pins, …) |
| M10: the `n · inner` term dropped from the estimate | caught: 37 error lines (every estimate pin) |
| M11: the adjacency cost measured without resetting the `MetaM` cache | first run: **survived** (the measurement restores the saved cache afterwards, so its own entries never leak into the next one); `#adjacency_cost` now warms the cache with the measured reduction before its second measurement, and the re-run is caught (3 pins) |
| M12: the recursion estimate ignored | caught: the broom `connectivityVerdict` pin |

### Pins (set by the harness, not touched here)

| What | Value |
|---|---|
| `lean-toolchain` | `leanprover/lean4:v4.35.0` (was `v4.34.0`) |
| `lakefile.toml` | mathlib `rev = "v4.35.0"` (was `"v4.34.0"`) = `56a005855ea17e0b0958f73ec801ae140b0a1679` |
| `lake-manifest.json` (the one harness `lake update`) | mathlib `56a00585`, proofwidgets `df72b022` (transitive via Mathlib; this package does not require it directly), batteries `66e46918`, aesop `4a174c49`, Qq `dce0ad79`, plausible `dfa4f381`, importGraph `a41f0e9a`, LeanSearchClient `d6b4c7be`, Cli `c24fe607` — equal to Mathlib v4.35.0's own manifest |
| `lake exe cache get` | 9031 Mathlib files already cached/decompressed, nothing downloaded |

### Changes

| File | What | Why |
|---|---|---|
| `GraphScopeTests/CommandTests.lean` (the `hasse (Fin 4)` block, `NoDeq`/`OpaqueFin3` neighbours untouched) | (a) New pin: `#graph_scope (text := true) (hasse (Fin 4))` now renders (`info: graph: 4 vertices, 3 edges …`, the same text as the `pathGraph 4` pin at the top of the file). (b) The two existing error pins — missing `DecidableRel` and noncomputable `Classical.propDecidable` `DecidableRel` — keep their graph and their expected messages byte-for-byte; their command is now prefixed with `attribute [-instance] SimpleGraph.instDecidableRelAdjHasseOfFintypeOfDecidableLT in` (scoped to that one command). (c) New pin: with `open scoped Classical` and the Mathlib instance available, the graph renders (the low-priority classical fallback does not hijack synthesis, so GraphScope does not falsely reject). Comments updated accordingly. | Forced. Mathlib v4.35.0 (mathlib4 #40728, commit `1afbf2aa632`, "more properties of Hasse graphs of linear orders") added `instance [Fintype α] [DecidableLT α] : DecidableRel (hasse α).Adj` (`Mathlib/Combinatorics/SimpleGraph/Hasse.lean:49`) and `instance (n : ℕ) : DecidableRel (pathGraph n).Adj` (`:161`). On the first 4.35 `lake test` both pins failed with `- error: … cannot synthesize …` / `- error: … is noncomputable …` → `+ info: graph: 4 vertices, 3 edges …`. These were the **only** tests of the `DecidableRel` branch of `synthOrExplain` (the `Fintype` / `DecidableEq` branches have their own pins), so simply re-pinning them to the new `info:` would have dropped that coverage. Erasing the one new instance for the single command recreates exactly the 4.34 environment the tests were written for (the `Demo` instance is keyed to `pathGraph`, so nothing else applies to `hasse (Fin 4)`), and the out-of-the-box 4.35 behaviour is pinned separately by (a) and (c). Verified that the erasure is scoped: a `#synth` after the command finds the Mathlib instance again. |
| `GraphScopeTests/InsertTests.lean` (end of file) | New section "`pathGraph` instance selection (v4.35.0 port)": `#guard_msgs in set_option pp.fullNames true in #synth DecidableRel (pathGraph 5).Adj` pinned to `info: GraphScope.Demo.instDecidableRelFinAdjPathGraph_graphScope 5`. | New test (allowed). Since Mathlib now has its own `pathGraph` instance (deciding `⋖` by quantifying over `Fin n`), the pin guards which evaluation path every `pathGraph` example takes: `GraphScope.Demo`'s `decidable_of_iff` instance (one comparison per adjacency), which is still the one synthesized (declared later, same priority). *(Corrected after the audit: at demo sizes both instances decide every offered example, so before the adjacency-cost guard this pin was the only test to notice a selection change — audit mutation M1; since the guard, the selection also decides whether `pathGraph` gets a connectivity link, and M1 fails 5 pins, see the post-audit transcript.)* `pp.fullNames` (display-only, one command) makes the namespace visible — without it the file's `open GraphScope.Demo` prints the bare `instDecidableRelFinAdjPathGraph_graphScope 5`. |
| `GraphScope/Demo.lean` | Doc comments only (module docstring bullet and the `pathGraph` instance docstring): no longer claim that `pathGraph` / `CovBy` has no decidability instance; say that Mathlib v4.35.0 ships one and that the local one, declared later, is the one picked. Same instances, same auto-generated names, same `#graph_scope` demo commands (they shift down 4 lines). | The old text became false on Mathlib v4.35.0. No code change: the clean rebuild produces the same demo panels and every insertion pin is unchanged. |
| `README.md` | Build/test section → Lean v4.35.0 / Mathlib v4.35.0 / ProofWidgets `df72b022`; assertion count 426 → 429 (both places); the "works out of the box" paragraph now mentions Mathlib's new `hasse`/`pathGraph` instances. | Version/count bookkeeping; same factual fix as `Demo.lean`. *(Post-audit: that paragraph overstated it — it called `hasse α` working out of the box while its connectivity link did not compile; rewritten with fix 1, count 429 → 455; round 2: the connectivity cost-model bullet and limitations, count 455 → 513.)* |
| `PORT-NOTES.md` | This section. | — |

### Golden / expected-output changes

**None of the v4.34 expected outputs changed** — in the port, after the
post-audit fixes (the adjacency-cost guard classifies every graph the suite
pinned before as validated, so all their insertion tables and ClickE2E
transcripts stand), and after round 2 (the cost model offers every
connectivity link the v4.34 suite pinned).  Round 2 did change the expected
text of the 17 `#connectivity_gate` pins added in round 1, because the
command now reports the cost model instead of the removed shape budget; see
"Round-2 expected-output changes".  Every pre-existing
`#guard_msgs` docstring, `#guard` value, text-mode report, insertion table,
ClickE2E transcript (incl. the pinned Lean error texts `Invalid field \`Ajd\`…`,
`unexpected token 'example'; expected ')', ',' or ':'`, `Tactic \`decide\`
proved that the proposition`) and the `info: true` pin of
`backward.isDefEq.respectTransparency.types` passes verbatim on v4.35.0.

The rejected alternative, for the record: re-pinning CommandTests' two
`hasse (Fin 4)` docstrings from `error: #graph_scope: cannot synthesize
\`DecidableRel (hasse (Fin 4)).Adj\` …` / `error: … is noncomputable (it uses
\`Classical.propDecidable\`) …` to the new `info: graph: 4 vertices, 3 edges …`
would describe correct 4.35 behaviour, but it would no longer be "the same
check" (the error branch would go untested), so the new behaviour got new pins
instead (see Changes).  New pins: two `info: graph: 4 vertices, 3 edges / edges:
0-1 1-2 2-3 / degrees: 1 2 2 1 (min 1, max 2) / components: 1 (connected) /
bipartite: yes (parts: {0, 2} / {1, 3})` and one `info:
GraphScope.Demo.instDecidableRelFinAdjPathGraph_graphScope 5`, each verified by
running.

### Deviations

* `attribute [-instance] SimpleGraph.instDecidableRelAdjHasseOfFintypeOfDecidableLT in`
  on two test commands (CommandTests).  Like a scoped `set_option … in`, it
  affects one command only; it does not silence anything — it restores the
  precondition (no computable instance) under which the unchanged error
  messages are produced by the unchanged GraphScope code path.
* `set_option pp.fullNames true in` on the one new `#synth` pin (display only).
* Doc-only edit in a library file (`GraphScope/Demo.lean`), see Changes.
* Post-audit (not a port deviation, a fix): library code in
  `GraphScope/Gate.lean` (adjacency-cost guard, one new import), doc comments
  in `GraphScope/Demo.lean` and `GraphScopeTests/ClickE2E.lean`, one new test
  module (`GraphScopeTests/HasseLinkTests.lean`, registered in
  `GraphScopeTests.lean`); tests only added.
* Post-audit round 2 (a fix): library code in `GraphScope/Insert.lean` (the
  connectivity cost model replaces the shape budget; `connectivityInsertable`
  gains an optional `adjCost` argument) and `GraphScope/Gate.lean` (measured
  adjacency cost, `connectivityCheck`, the `adjacencyCost` search limit as a
  parameter); doc comments in `GraphScope/Demo.lean`.  Tests: assertions
  added; the 17 round-1 `#connectivity_gate` expected texts changed with the
  command's output format (see the round-2 expected-output changes; every
  verdict unchanged).  Four plain `example … := by decide` compile checks run
  under a scoped `set_option maxHeartbeats 100000 in` — *half* the default,
  i.e. stricter, to prove the cost model's margin.

No test deleted, weakened, skipped or commented out; no `sorry`; no file-scope
or global option; no `module` conversion; `lake update` / `cache get` not
re-run; `lakefile.toml`, `lean-toolchain`, `lake-manifest.json` not edited.

### Counts

Same method as below (line-leading `#guard`, `#guard_msgs`,
`#assert_graph_invariants`, `#assert_gate` in `GraphScopeTests/*.lean`;
"before" read with `git show qed64-pin-i:…`).

| File | v4.34.0 (`qed64-pin-i`) | v4.35.0 port | v4.35.0 post-audit | v4.35.0 round 2 |
|---|---:|---:|---:|---:|
| AlgoTests | 72 | 72 | 72 | 72 |
| ClickE2E | 16 | 16 | 16 | 16 |
| CommandTests | 43 | **45** (+2 new `#guard_msgs`) | **47** (+2: `hasseNoInst`) | 47 |
| ContractTests | 20 | 20 | 20 | 20 |
| HasseLinkTests | — | — | **4** (new module) | **5** (+1 `#assert_insertions_compile`: the `Finset (Fin 4)` `⊆`/`card` 4-cube) |
| InsertTests | 95 | **96** (+1 new `#guard_msgs`) | **116** (+17 `#connectivity_gate`, +3 `#assert_insertions_compile`) | **173** (+43 `#guard`: cost model, recursion estimate, cap arithmetic, `AdjCost` verdicts; +14 `#guard_msgs`: 10 `#connectivity_gate`, 3 `#adjacency_cost`, 1 `#assert_insertions_compile`) |
| LayoutTests | 35 | 35 | 35 | 35 |
| ModelTests | 35 | 35 | 35 | 35 |
| OverlayTests | 24 | 24 | 24 | 24 |
| PropertyTests | 31 | 31 | 31 | 31 |
| RenderTests | 55 | 55 | 55 | 55 |
| **Total** | **426** | **429** | **455** | **513** |

By kind: `#guard` 327 → 327 → 327 → 370, `#guard_msgs` 70 → 73 → 99 → 114,
`#assert_graph_invariants` 11 → 11 → 11 → 11, `#assert_gate` 18 → 18 → 18
→ 18.  Not counted by the method: `#assert_insertions_compile` 13 → 13 → 20
→ 22, `#connectivity_gate` 17 → 27 and the new `#adjacency_cost` (3), all
under `#guard_msgs` and so inside the counts; the four round-2
`set_option maxHeartbeats 100000 in example … := by decide` compile checks
(not counted: no `#guard` prefix); the root `#guard GraphScope.version =
"0.1.0"` in `GraphScopeTests.lean`; and ClickE2E's 5 `#e2e_click_scenario` +
4 `#e2e_negative` commands (all under `#guard_msgs`, so inside the 16).
Re-counted mechanically on the final tree
(`grep -cE '^(#guard( |$)|#guard_msgs|#assert_graph_invariants|#assert_gate)'`
per file).

### 4.35 gotchas

1. **Mathlib #40728: `hasse` and `pathGraph` are decidable now.**
   `SimpleGraph.instDecidableRelAdjHasseOfFintypeOfDecidableLT` (for
   `[Preorder α] [Fintype α] [DecidableLT α]`, via `decidable_of_iff' _
   hasse_adj`, i.e. `CovBy` decided by quantifying over `α`) and
   `SimpleGraph.instDecidableRelFinAdjPathGraph` (`inferInstanceAs` the former),
   built on two new **global** instances in `Mathlib/Data/Fintype/Defs.lean:261-266`
   (same PR): `Fintype.instDecidableRelCovByOfDecidableLT` (`[Fintype α] [LT α]
   [DecidableLT α] : DecidableRel CovBy`, as `a < b ∧ ∀ ⦃c⦄, a < c → ¬c < b`)
   and `Fintype.instDecidableRelWCovByOfDecidableLE` (`[Fintype α] [Preorder α]
   [DecidableLE α] : DecidableRel WCovBy`), both through
   `Fintype.decidableForallFintype`; `Mathlib/Order/Cover.lean` dropped the
   then-redundant `Bool.instDecidableRelWCovBy` / `Bool.instDecidableRelCovBy`.
   So any `⋖` / `⩿` on a `Fintype` is decidable now, not only `hasse`, and
   always by a pass over the whole type: one adjacency of `hasse α` costs
   `|α|` comparisons.  That raises the cost of every adjacency decision in
   `by decide` proofs (GraphScope's adjacency-cost guard withholds the
   connectivity link for such instances, post-audit fix 1), but it is *not*
   what made the audit's `hasse (Finset (Fin 4))` connectivity example time
   out: that graph is the 4-cube, whose walk enumeration exceeds
   `maxHeartbeats 200000` with any adjacency instance (328678 heartbeats with
   a `Nat.xor` relation on `Fin 16`) — a hole in GraphScope's v4.34 shape
   budget, fixed in round 2 (fix R2-1).  *(Corrected in round 2: this item
   used to say the quantifying instance "is what broke GraphScope's
   connectivity budget".)*
   Anything that used `hasse`/`pathGraph` as an example of a *missing*
   instance flips from error to success; a local `decidable_of_iff` instance
   for `pathGraph` (GraphScope's, and any QED64 snippet that copies it) still
   compiles and, being declared later at the same priority, still wins.  The
   same PR deprecates `pathGraph_connected` (alias of
   `connected_pathGraph_add_one`, since 2026-10-01) and adds `connected_pathGraph :
   (pathGraph n).Connected ↔ n ≠ 0`; GraphScope uses neither.
2. **Scoped instance erasure works for imported Mathlib instances** in a
   non-`module` file: `attribute [-instance] Foo in <cmd>` removes it for that
   command only (verified with a `#synth` afterwards).  It is the minimal way
   to keep a "missing instance" test meaningful when upstream adds the
   instance.
3. **The "imports … designed for use with the module system; consider adding
   `module`" warning comes from Lake, not from the elaborator**
   (`Lake/Build/Module.lean:424`, emitted while computing a non-`module`
   file's imports).  Here: 5 warnings in the port, on the 3 library files that
   import Mathlib directly (`Extract` ×2, `Gate` ×1, `Demo` ×2), replayed on
   every later build; 7 after the post-audit fixes (`Gate` ×2 with its new
   `Hasse` import, and `HasseLinkTests` ×1).  The port's statement that test
   modules get none now holds for every test module except `HasseLinkTests`,
   the one that imports Mathlib directly.  Because it is not a Lean message it never reaches `#guard_msgs`, and
   ClickE2E's in-process user-file compiles (`IO.processCommands`) never see it
   (they also only count errors and `sorry` messages).
4. **New core `isDefEq` knobs:** v4.35.0 adds
   `backward.isDefEq.throwOnStuckAfterApp` (default `false`) and
   `backward.isDefEq.respectTransparency.instanceSearchTypes` (default `true`,
   instance-metavariable assignments type-checked at instance transparency
   during TC search, lean4#9077); `respectTransparency.types` stays `true`
   (InsertTests' pin still `info: true`).  None of them affected the `decide`
   examples through `Demo`'s instances.
5. **ClickE2E's nested compiler needed nothing.**  `Lean.enableInitializersExecution`
   (`BaseIO Unit`), `Lean.withImporting`, `importModules (loadExts := true) …
   (trustLevel := 0)`, `Parser.parseHeader` / `headerToImports`,
   `Command.mkState`, `IO.processCommands`, `String.toFileMap` under `open Lean`,
   `FileMap.lspPosToUtf8Pos` and `MakeEditLinkProps.ofReplaceRange` behave as on
   v4.34.0; the suite takes ~17 s.

### Verification transcript

All runs through the shared lock:
`BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=10 LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200 bash ".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh" <lane> bash -c 'cd ".../packages/graph-scope" && <cmd>'`.

| Lane | Command | Final lines |
|---|---|---|
| (harness) `port435-build-graph-scope` | `lake build` | `Build completed successfully (1070 jobs).` rc=0 |
| `port435-graph-scope-test1` | `lake test` (unmodified tests) | `error: GraphScopeTests/CommandTests.lean:292:0` and `:301:0` `❌️ Docstring on #guard_msgs does not match` (see Changes); every other module incl. `ClickE2E` (19 s) built; `error: build failed`, rc=1 |
| `port435-graph-scope-probe`, `-probe2` | `lake env lean <scratch probe>` | instance names, scoped erasure reproduces both old messages, `#synth` picks the `Demo` instance for `pathGraph` |
| `port435-graph-scope-test2` | `lake test` | only the new `#synth` pin mismatched (bare name under `open GraphScope.Demo`) → `pp.fullNames` added |
| `port435-graph-scope-cleanbuild` | `rm -rf .lake/build && lake build` | `✔ [1069/1070] Built GraphScope (927ms)` / `Build completed successfully (1070 jobs).` / `browser-lock: command exited rc=0` |
| `port435-graph-scope-test-final` | `lake test` | `✔ [1080/1081] Built GraphScopeTests.ClickE2E (17s)` / `✔ [1081/1081] Built GraphScopeTests (959ms)` / `browser-lock: command exited rc=0` |

Warnings in the final runs: exactly the 5 Lake module-system warnings
(gotcha 3); none from Lean.

---

*The v4.32.2 → v4.34.0 port record follows, unchanged except for the
"historical" marker on its "This tree" line.*

Reference (read-only): `../../widgets/graph-scope` (toolchain `leanprover/lean4:v4.32.2`,
Mathlib `v4.32.2`).  This tree (at the end of that port; historical, see the
top of this file): `leanprover/lean4:v4.34.0`, Mathlib `v4.34.0` (lockfile
`lake-manifest.json`, Mathlib oleans from `lake exe cache get`).

Result: `lake build` exit 0 and `lake test` exit 0 after a clean rebuild of the
package's own modules (`rm -rf .lake/build`), with **zero warnings** — no
deprecated lemma, module or API is used anywhere in the package, so no
`set_option` scoping for deprecations was needed.

## Changes

| File | What | Why |
|---|---|---|
| `lean-toolchain`, `lakefile.toml` | `v4.32.2` → `v4.34.0` (toolchain and Mathlib rev) | Pre-staged by the harness; not touched by the port agents. |
| `GraphScopeTests/InsertTests.lean` (`testDocMeta`) | `text := "".toFileMap` → `text := Lean.FileMap.ofString ""` | Forced. v4.34.0 moved `String.toFileMap` into the `Lean` namespace (`Lean.String.toFileMap`, `src/lean/Lean/Data/Position.lean:122`, a thin wrapper over `Lean.FileMap.ofString`). The test file does not `open Lean` at that point, so field notation `"".toFileMap` now fails with `Invalid field toFileMap: The environment does not contain String.toFileMap` (verified on this toolchain). Same `FileMap` value either way. |
| `GraphScopeTests/InsertTests.lean` (end of file) | New section "Toolchain transparency defaults (v4.34.0 port)": one `#guard_msgs` pin that `backward.isDefEq.respectTransparency.types` is `true` under this file's effective options, plus four `#guard_msgs in example … := by decide` checks (`pathGraph 5` adjacency and degree, `completeBipartiteGraph (Fin 2) (Fin 3)` adjacency and degree) that must decide under the toolchain **defaults**, with no `set_option … respectTransparency … false` anywhere in the package. | New tests (allowed). Started by the interrupted agent; this is the package's most exposed surface for the 4.34 transparency change (see gotchas): the click-to-insert feature promises that every offered `by decide` example compiles in a user file that only imports `GraphScope`, and those examples go through `Demo.lean`'s `decidable_of_iff` instances. |
| `GraphScopeTests/InsertTests.lean` (header) | Added `import Lean.Meta.ExprDefEq` with an explanatory comment. | Fixes the interrupted agent's breakage (`Unknown identifier Meta.backward.isDefEq.respectTransparency.types.get`). The constant exists (`opaque Lean.Meta.backward.isDefEq.respectTransparency.types : Lean.Option Bool`, registered in `Lean/Meta/ExprDefEq.lean` inside `namespace Lean.Meta`), but on v4.34.0 core, Mathlib and ProofWidgets are all `module` files, so a non-`module` file only sees their *public* import closure, and `Lean.Meta.ExprDefEq` is not publicly re-exported along the Mathlib/ProofWidgets path (while e.g. `Lean.maxRecDepth` from `Lean.Data.Options` is). Verified: same `#check` fails after `import GraphScopeTests.Helpers` and succeeds after adding `import Lean.Meta.ExprDefEq`. Test-only import; the library is unchanged. |
| `README.md` | Toolchain line → v4.34.0 / Mathlib v4.34.0 with a pointer to this file; assertion count 422 → 426 in both places. | Version/count bookkeeping (see Counts). |

No library file (`GraphScope/*.lean`, `GraphScope.lean`) changed: the whole
`SimpleGraph` surface the package uses (`Mathlib.Combinatorics.SimpleGraph.Basic`,
`.Hasse`, `.CycleGraph`, `.Connectivity.Finite`, `Mathlib.Data.Quot`) is still
canonical on Mathlib v4.34.0 (none of those files carries `deprecated_module`;
the Aug-2026 shims live under `SimpleGraph/Walks/*`, `Coloring*`,
`Connectivity/WalkCounting|WalkDecomp`, `EdgeLabeling`, `ConcreteColorings`,
which GraphScope never imported).  `evalExpr`, the `Decidable` instances for
`pathGraph` / `completeBipartiteGraph`, `MakeEditLink` / `mk_rpc_widget%` and the
Layered layout all compile and test unchanged.

## Pin updates

None.  Every `#guard_msgs` docstring, `#guard` value, text-mode report, error
message and insertion-suggestion table from the reference passes verbatim on
v4.34.0 (including the `Fintype Bool` enumeration order, the `Repr (Subtype p)`
label shape, the `decide` budget replicas and the exact noncomputable-instance
error texts).  The only new pins are the ones in the new test section above
(`info: true` for the option default, and "no messages" for the four `decide`
examples), each verified by running.

## Deviations

None.  No test was deleted, weakened or commented out; no feature was dropped;
no `sorry`; no global option/linter suppression; `lake update` was not re-run
and `lakefile.toml` / `lean-toolchain` were not edited.

Minor bookkeeping note (not a port deviation): the reference README states
"422 compile-time assertion commands", but the README's own counting method
(below) yields **421** on the reference sources — the reference README was
already off by one.  The ported README now states the verified figure.

## Counts

Method (from the README): line-leading `#guard`, `#guard_msgs`,
`#assert_graph_invariants` and `#assert_gate` commands in `GraphScopeTests/*.lean`
(`grep -cE '^(#guard|#guard_msgs|#assert_graph_invariants|#assert_gate)\b'`).

| File | reference v4.32.2 | ported v4.34.0 |
|---|---:|---:|
| AlgoTests | 72 | 72 |
| ClickE2E | 16 | 16 |
| CommandTests | 43 | 43 |
| ContractTests | 20 | 20 |
| InsertTests | 90 | **95** (+5 new, see Changes) |
| LayoutTests | 35 | 35 |
| ModelTests | 35 | 35 |
| OverlayTests | 24 | 24 |
| PropertyTests | 31 | 31 |
| RenderTests | 55 | 55 |
| **Total** | **421** (README said 422) | **426** |

By kind (reference): 327 `#guard`, 65 `#guard_msgs`, 11 `#assert_graph_invariants`,
18 `#assert_gate`.  Ported: 327 / 70 / 11 / 18.  Not counted by the method but
also unchanged: 13 `#assert_insertions_compile` (each compiles every generated
insertion text), 54 `#graph_scope` commands under `#guard_msgs`, and the
ClickE2E subprocess scenarios.

## 4.34 gotchas worth knowing for QED64

1. **`backward.isDefEq.respectTransparency.types` now defaults to `true`.**
   v4.32.2 registered it with `defValue := false -- TODO: replace with true
   after we fix stage0`; v4.34.0 ships `true` (`Lean/Meta/ExprDefEq.lean:57`).
   `backward.isDefEq.respectTransparency` itself was already `true` on both.
   Effect: when a metavariable is assigned, its type is compared with the
   term's type at *implicit* transparency instead of being bumped to
   `.default`, so instances/definitions that used to unfold during that check
   no longer do unless they are `[implicit_reducible]`.  For GraphScope this
   did **not** bite: `Demo.lean`'s `decidable_of_iff` instances for
   `pathGraph` and `completeBipartiteGraph` still let `by decide` prove
   adjacency, degree and connectivity facts under the defaults (pinned in
   `InsertTests.lean`).  The QED64 owner's observation that `deriving Fintype`
   needs `set_option backward.isDefEq.respectTransparency false in` is not
   exercised here — this package has no `deriving Fintype` (only `Repr`, `BEq`,
   `Inhabited`, `ToJson`, `FromJson`, `RpcEncodable`).  If a QED64 showcase
   file does derive `Fintype`, scope the option to that declaration rather than
   the file.
2. **Module system visibility.** Core, Mathlib and ProofWidgets are now
   `module` files.  A plain (non-`module`) file that imports them sees only
   their *public* import closure.  Concretely: `Lean.Meta.backward.isDefEq.*`
   (and other `Lean.Meta` internals) were not visible after `import Mathlib…`
   / `import ProofWidgets…` and needed an explicit `import Lean.Meta.ExprDefEq`
   (or `import Lean`).  If a QED64 playground snippet references a Lean-internal
   constant and gets `Unknown identifier` despite importing Mathlib, add the
   defining module's import — the olean is already loaded, only its names
   are hidden.  Note that the *option names* still work in `set_option`
   (options are looked up in the runtime registry, `Lean.getOptionDecl`),
   only the constants are hidden.
3. **`String.toFileMap` → `Lean.String.toFileMap`** (`Lean/Data/Position.lean`).
   Field notation on a `String` no longer finds it without `open Lean`; use
   `Lean.FileMap.ofString` or open the namespace.  Relevant to any widget code
   that fabricates a `DocumentMeta` for tests.
4. **Mathlib SimpleGraph reorganisation is benign for these imports.**  The
   modules GraphScope uses (`SimpleGraph.Basic`, `.Hasse`, `.CycleGraph`,
   `.Connectivity.Finite`) are canonical on v4.34.0; the `deprecated_module`
   shims are the `Walks/*`, `Coloring*`, `Connectivity/WalkCounting`,
   `Connectivity/WalkDecomp`, `EdgeLabeling` and `ConcreteColorings` files.
   A clean rebuild produced no deprecation warnings, so no `set_option
   linter.deprecated` scoping was needed.
5. **Nothing else moved.**  `Lean.Meta.evalExpr` (`safety := .unsafe`),
   `Lean.Core.checkSystem`, `Lean.Parser.runParserCategory`,
   `String.Pos.Raw.extract`, `MakeEditLinkProps.ofReplaceRange`,
   `mk_rpc_widget%`, `RequestM.readDoc` and ProofWidgets' `Html` all have the
   same signatures the v4.32.2 package relied on; `Fintype Bool` still
   enumerates `true` first and core's `Repr (Subtype p)` still prints the bare
   value — both are pinned by tests that stayed green.
