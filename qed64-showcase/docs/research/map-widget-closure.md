# Widget suite module closure vs. what QED64 serves (wasm64-4b025db7729c5f89, profiles core 649 + mathlib-essential 4354), Demo suitability, wasm hazards, and a minimal showcase snippet per package

## Facts
- QED64 serves exactly 5,003 modules: the core profile (649 Init.* modules) plus the mathlib-essential profile (4,354 modules). The served set is import-closed: every import listed in either manifest is itself served. The essential manifest's module set is identical to the kernel repo's essential-modules.txt, with zero symmetric difference. The `mathlib` snapshot is the `QED64.Essential` umbrella over exactly that list (Init not listed, it is in the closure).
  - EVIDENCE: /Users/fawadhaider/code/wasm64-lean-fable/qed64/public/profiles/index.json (core modules 649, essential 4354, runtime buildId wasm64-4b025db7729c5f89). Computed from content.modules of public/profiles/lean-core.manifest.json and public/profiles/mathlib-essential.manifest.json against /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0/mathlib/essential-modules.txt (4354 lines, diff 0). public/snapshots/index.json: mathlib.8df0689fbc323eab.snapz imports ["QED64.Essential"], runtime wasm64-4b025db7729c5f89, 1,127,272,685 bytes raw / 321,484,932 transfer. Umbrella generator: qed64/pipeline/artifacts/gen-umbrella.mjs:2-15 and :45-51.
- QED64 serves only these 10 ProofWidgets modules: Cancellable, Compat, Component.Basic, Component.FilterDetails, Component.MakeEditLink, Component.OfRpcMethod, Component.Panel.Basic, Component.RefreshComponent, Data.Html, Util. ProofWidgets.Component.HtmlDisplay is only in the unserved `extra` (mathlib-game-extra) list.
  - EVIDENCE: ProofWidgets.* keys of mathlib-essential.manifest.json. /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0/mathlib/extra-modules.txt:735-737 lists HtmlDisplay, PenroseDiagram and Presentation.Expr. essential-selection.json byTopLevel reports ProofWidgets: 10.
- Missing non-widget modules per package (full transitive closure of the package root, which imports its Demo): interval-inspector 1, expr-xray 2, simp-lens 1, graph-scope 36, tree-scope 3, hasse-view 1, dist-lens 573, chart-kit 1. The union across all eight is 609. Every package misses ProofWidgets.Component.HtmlDisplay. Without the Demo imports, graph-scope drops to 22. The other packages have the same count with or without Demo.
  - EVIDENCE: Computed by parsing import headers (including `module`, `public`/`meta import` and `import all`) of non-served modules only. Sources: /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0/mathlib/mathlib4 (commit 5ed2965, the same as widgets' .lake/packages/mathlib), its .lake/packages (proofwidgets 106ff4fa, batteries f2effa3d), and ~/.elan/toolchains/leanprover--lean4---v4.34.0/src/lean. Served modules are taken from the manifests. Script: /private/tmp/claude-501/-Users-fawadhaider-code-lean-questions/49e7f0e4-0411-414e-9d80-197cafce4da7/scratchpad/closure-agent-modlist/cl.py. Full lists: .../closure-agent-modlist/missing.json.
- expr-xray misses exactly ProofWidgets.Component.HtmlDisplay and ProofWidgets.Component.Panel.SelectionPanel. SelectionPanel is really used: `loc.saveExprWithCtx` is defined there, and its only import, Panel.Basic, is served.
  - EVIDENCE: widgets-v4.34/expr-xray/ExprXRay/Widget.lean:3 and :130. proofwidgets/ProofWidgets/Component/Panel/SelectionPanel.lean:1-10 (`public import ProofWidgets.Component.Panel.Basic`; `def Lean.SubExpr.GoalsLocation.saveExprWithCtx`).
- tree-scope misses ProofWidgets.Component.HtmlDisplay, Mathlib.Combinatorics.Enumerative.Catalan.Tree and Mathlib.Combinatorics.Enumerative.Catalan.Basic. The Catalan modules come in through TreeScope.Instances.MathlibTree (catalanGallery).
  - EVIDENCE: widgets-v4.34/tree-scope/TreeScope/Instances/MathlibTree.lean:4 and :106.
- graph-scope misses 36 modules. 28 are Mathlib.Combinatorics.SimpleGraph.*: Basic, Clique, Coloring.Vertex, Connectivity.{Connected,Finite,Subgraph}, Copy, CycleGraph, Dart, DeleteEdges, Finite, Hasse, Init, Maps, Metric, Operations, Paths, Prod, Subgraph, Sum, Walk.{Basic,Chord,Counting,Decomp,Maps,Operations,Subwalks,Traversal}. The other 8 are Algebra.BigOperators.Ring.Nat, Data.Fin.SuccPredOrder, Data.Finset.Pairwise, Data.FunLike.Fintype, Data.Setoid.Partition, Data.Sym.Card, Order.Partition.Finpartition and PW HtmlDisplay. The library alone (GraphScope.Widget/Gate/Extract) needs 22 of these. The 14 others come only from Demo's imports of SimpleGraph.Hasse (pathGraph) and SimpleGraph.CycleGraph (cycleGraph).
  - EVIDENCE: widgets-v4.34/graph-scope/GraphScope/Demo.lean:2-3; GraphScope/Extract.lean:2; GraphScope/Gate.lean:3. mathlib4/Mathlib/Combinatorics/SimpleGraph/Hasse.lean:108 (`def pathGraph`), CycleGraph.lean:29 (`def cycleGraph`), Basic.lean:156 and :332 (completeBipartiteGraph and completeGraph are already in Basic).
- dist-lens misses 573 modules: MeasureTheory 183, RingTheory 70, Analysis 62, Probability 61, Topology 55, Algebra 43, LinearAlgebra 40, FieldTheory 19, Order 15, Data 10, Control 4, GroupTheory 3, Dynamics 2, Tactic 2, Basic/Combinatorics/SetTheory 1 each, plus PW HtmlDisplay. The blow-up comes from Mathlib.Probability.Distributions.Bernoulli (485 missing), which PMF.Constructions imports at this pin. PMF.Monad alone would cost only 51.
  - EVIDENCE: Per-import closures computed with cl.py. PMF.Basic 50 (via MeasureTheory.Measure.Dirac.Basic), PMF.Monad 51, PMF.Constructions 492 (imports Distributions.Bernoulli 485), PMF.Binomial 570, Distributions.Uniform 493, PMF.Integrals 493. Direct imports are at widgets-v4.34/dist-lens/DistLens/Extract.lean:2-4 and Verify.lean:1-6.
- interval-inspector, simp-lens, hasse-view and chart-kit miss only ProofWidgets.Component.HtmlDisplay. All of their other direct imports are served. For interval-inspector that includes Mathlib.Basic.Real.Basic, Order.Interval.Set.LinearOrder, Tactic.Linarith, Tactic.Linter.UnusedTacticExtension, Lean.Expr.Rat and PW MakeEditLink/OfRpcMethod/Data.Html. For hasse-view it includes Data.Fintype.{Basic,Card,Prod,Powerset}, Finset.Sort, NumberTheory.Divisors, Order.Cover and Data.Quot.
  - EVIDENCE: Direct-import scan of non-Tests modules: interval-inspector/IntervalInspector/*.lean, hasse-view/HasseView/*.lean, simp-lens/SimpLens/*.lean (only `Lean` + HtmlDisplay), chart-kit/ChartKit/*.lean (only PW Data.Html + HtmlDisplay). Each was checked for membership in the manifests.
- Native64 oleans already exist for 170 of the 609 missing modules. HtmlDisplay plus 168 Mathlib modules (all in DistLens's closure) are in extra-tree, and HtmlDisplay is also in the kernel tree's proofwidgets build. That leaves 439 to compile: dist-lens 404, graph-scope 35, tree-scope 2 (Catalan), expr-xray 1 (SelectionPanel). The kernel tree's Mathlib build holds exactly 3,122 native64 oleans (2,390 essential + 732 extra) and none of the missing SimpleGraph/Catalan/Probability modules.
  - EVIDENCE: Olean header githash at byte offset 0x28 (32 bytes) is all-zero for native64 builds and '293d5d0c0c3f3dded4688b3ccd6a33939ac5102b' for official v4.34.0 builds (xxd of mathlib4/.lake/build/lib/lean/Mathlib/Data/Rat/Defs.olean vs widgets' .lake/packages/mathlib copy). Per-module existence checked under mathlib/extra-tree, mathlib4/.lake/build/lib/lean and mathlib4/.lake/packages/proofwidgets/.lake/build/lib/lean.
- The kernel tree's proofwidgets build directory mixes compilers: 13 native64 and 11 official-toolchain oleans. ProofWidgets/Component/Panel/SelectionPanel.olean there is an OFFICIAL build from Sep 15 (githash 293d5d0c…), so it cannot be used by QED64 and must be recompiled with native64. HtmlDisplay.olean there is native64 (Sep 21), the same 185,344-byte file as extra-tree's.
  - EVIDENCE: Header dump of /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0/mathlib/mathlib4/.lake/packages/proofwidgets/.lake/build/lib/lean/ProofWidgets/Component/Panel/SelectionPanel.olean (githash present, mtime Sep 15 10:12) vs Component/HtmlDisplay.olean (zero githash, Sep 21 13:59). Counted over that directory: official 11, native64 13.
- The ProofWidgets JS that `include_str` needs is committed at this pin: 24 tracked files under widget/js, including htmlDisplay.js, htmlDisplayPanel.js, presentSelection.js and makeEditLink.js. Building HtmlDisplay/SelectionPanel needs no npm step. The native64 HtmlDisplay.olean in extra-tree contains the embedded JS.
  - EVIDENCE: proofwidgets/ProofWidgets/Component/HtmlDisplay.lean:16 and :20, Panel/SelectionPanel.lean:51 (include_str of widget/js/*.js). `git ls-files widget/js | wc -l` = 24 in mathlib4/.lake/packages/proofwidgets. extra-tree HtmlDisplay.olean contains 'react' strings.
- Estimated payload of the missing modules (official-build sizes of olean+private+server+ir; native64 files of the same module are byte-identical in size where both exist, e.g. Rat/Defs 122,096 and HtmlDisplay 185,344): dist-lens 399.5 MB, graph-scope 40.4 MB, tree-scope 1.3 MB, each other package about 0.5 MB, union about 438 MB. The widgets' own oleans total about 40.4 MB: interval-inspector 7.5, tree-scope 6.6, dist-lens 6.5, graph-scope 4.7, hasse-view 4.7, expr-xray 3.7, simp-lens 3.7, chart-kit 3.0.
  - EVIDENCE: stat over widgets-v4.34/interval-inspector/.lake/packages/{mathlib,proofwidgets}/.lake/build/lib/lean and each widgets-v4.34/<pkg>/.lake/build/lib/lean (Tests excluded).
- Every package root imports its own Demo module. So `import <Pkg>` brings demo declarations into the user's environment, including global instances such as GraphScope.Demo's DecidableRel (pathGraph n).Adj and (completeBipartiteGraph V W).Adj. It also brings Demo-only Mathlib imports (graph-scope +14 modules; hasse-view's Fintype.Powerset/Finset.Sort/Divisors, which are served). lean-widget-kit imports all eight roots and therefore needs the full 609-module union.
  - EVIDENCE: IntervalInspector.lean:8, ExprXRay.lean:6, SimpLens.lean:7, GraphScope.lean:10, TreeScope.lean:12, HasseView.lean:8, DistLens.lean:6, ChartKit.lean:6. GraphScope/Demo.lean:37-43. lean-widget-kit/LeanWidgetKit.lean:1-8.
- How each package uses RPC: @[server_rpc_method] with mk_rpc_widget% panels appear in 5 packages: IntervalInspector (`interval_inspect?` tactic), ExprXRay (XRayPanel via with_panel_widgets), GraphScope (#graph_scope), HasseView (#hasse) and DistLens (#dist, #chain). Four of them also use RequestM.readDoc + MakeEditLink: IntervalInspector, GraphScope, HasseView and DistLens. Static HtmlDisplayPanel (savePanelWidgetInfo, no custom RPC method) backs #interval_inspect, #xray/#xray_diff, simp_lens, #tree_scope, #tree_evolve, #dist_film, #chart, the text-only/no-range fallbacks of #graph_scope/#hasse, and ProofWidgets #html (used in TreeScope's Demo). SimpLens also emits core TryThis suggestions.
  - EVIDENCE: IntervalInspector/Widget.lean:163-166, :186-222, :228-231. ExprXRay/Widget.lean:65-69, :146-186. GraphScope/Widget.lean:87-102, :196-203. HasseView/Widget.lean:94-104, :188-196. DistLens/Widget.lean:247-270, :310, :351, :485. TreeScope/Widget.lean:91, TreeScope/Evolve.lean:203. SimpLens/Tactic.lean:41, :80. ChartKit/Widget.lean:98.
- No widget library code uses extern C, IO.Process, the filesystem, environment variables, randomness, timers or explicit thread spawning. IO.FS appears only in showcase/probes/*.lean dump scripts, which are not shipped. There are also no @[extern] declarations in Mathlib, ProofWidgets or Batteries at this pin, and no precompileModules/extern_lib in any lakefile. Concurrency is limited to RequestM.asTask inside the five RPC methods.
  - EVIDENCE: Grep over widgets-v4.34/*/ (excluding .lake and Tests) for extern|IO.Process|IO.FS|readFile|writeFile|Task.|IO.asTask|IO.monoMs|IO.getEnv|IO.rand|initialize|IO.sleep: only showcase/probes/{dist-lens,chart-kit,simp-lens,interval-inspector,tree-scope,hasse-view,expr-xray,graph-scope}.lean hit IO.FS. Grep '@\[extern' over mathlib4/Mathlib, proofwidgets/ProofWidgets and batteries/Batteries: empty. lakefile.toml grep for precompile/extern: empty.
- Five packages compile and run user code at command time through `unsafe evalExpr`/`evalExpr'`: TreeScope, GraphScope, HasseView, DistLens and ChartKit. ProofWidgets `#html` also does this via Term.evalTerm. In QED64 this means the in-wasm compiler produces IR that the IR interpreter runs. The interpreter looks up native symbols only for core code; Mathlib and widget code have no native symbols. IntervalInspector, ExprXRay and SimpLens do not evaluate compiled code.
  - EVIDENCE: TreeScope/Widget.lean:68, Reflect.lean:93 and :98 (Float/Float32). GraphScope/Extract.lean:138, :149, :166, Gate.lean:64. HasseView/Extract.lean:151, :158, :170, :190, Gate.lean:81, :94. DistLens/Extract.lean:196, :200, :203, :325, :341. ChartKit/Widget.lean:69. proofwidgets HtmlDisplay.lean:52-54. qed64/docs/ARCHITECTURE.md:142-149 (the IR interpreter probes for native implementations; no Mathlib symbol exists in the binary).
- QED64 runtime facts that matter for the widgets. Tasks run on a fixed pthread pool of 24, and every ServerTask, including each in-flight request, is dedicated. Interpreted code runs on a 1 MB worker stack, so deep interpreted recursion is the practical ceiling. Float operations are core runtime functions (lean_float_*), which the core binary provides. SimpLens's IO.Refs are created at runtime, so the 'second copy of a native IO.Ref' hazard (which concerns missing export cells for core state) does not apply.
  - EVIDENCE: qed64/docs/ARCHITECTURE-REEVALUATION-2-2026-09-02.md:170 and :431 (PTHREAD_POOL_SIZE=24, dedicated ServerTasks). qed64/docs/HARDENING.md:239 (1 MB worker stack; missing cells give the interpreter its own copy of native state). SimpLens/Trace.lean:148-172 (IO.Ref created per call).
- The stock QED64 page's snapshot choice is driven by the header. It boots ['init','mathlib'] only when an import's root is in {Mathlib, Batteries, MIL, QED64}. It widens after a refusal only if EVERY missing module has one of those roots. So `import HasseView` or `import ProofWidgets.Component.HtmlDisplay` alone boots init-only and is never widened, which is why QED64.-rooted shims are needed for the stock-page overlay. The vendored-page option avoids this with its own ResidentPolicy.
  - EVIDENCE: qed64/frontend/src/resident-session.ts:74-78 (UMBRELLA_ROOTS, isUmbrellaModule, needsMathlib) and :85 (snapshotsForHeader). qed64/frontend/src/main.ts:377-386 (widenForMathlib requires missing.every(isUmbrellaModule)). ?snapshots= re-rooting: qed64/frontend/src/qed64-boot.ts:96-105.
- Demo suitability. Every Demo imports only its own package plus Mathlib, so all are self-contained, but they are long (120–171 lines). Command counts: ChartKit 7 #chart + 6 #guard + 1 #guard_msgs. DistLens 12 #dist/#dist_film/#chain + 17 `example … pmf_num` blocks (heavy). ExprXRay 16 #xray/#xray_diff + 2 with_panel_widgets proofs. GraphScope 16 #graph_scope + 4 local instances. HasseView 9 #hasse + about 12 local instances (Div12, Bowtie). IntervalInspector 15 #interval_inspect + 10 interval_inspect? tactic proofs + 4 #guard_msgs. SimpLens 16 simp_lens examples, all under #guard_msgs. TreeScope 16 #tree_scope/#tree_evolve + 4 #html.
  - EVIDENCE: Counted by grep over widgets-v4.34/*/*/Demo.lean. File lengths: IntervalInspector 167, ExprXRay 132, SimpLens 170, GraphScope 120, TreeScope 171, HasseView 153, DistLens 158, ChartKit 158.
- Command-time cost classes (reasoned from code; there are no browser timings anywhere). Light: ChartKit (one evalExpr per #chart), ExprXRay (analysis + isDefEq), IntervalInspector #interval_inspect (elab + synthInstance). Moderate: SimpLens (re-runs simp once per used lemma for exclusion previews unless `-previews`), TreeScope (evalExpr + reflection; #tree_evolve multiplies by frames), GraphScope (per vertex: parse + elab + compiled eval for the insertion gate). Moderate-heavy: HasseView (per candidate: elabString + synthInstance Decidable + evalExpr, i.e. an interpreted compile per cover edge, label and ⊥/⊤ fact). Heavy: the DistLens Demo's pmf_num examples (simp/norm_num over ℝ≥0∞). #dist itself does not run pmf_num; its suggestions are generated text.
  - EVIDENCE: SimpLens/Exclude.lean:86-107 and Tactic.lean:35-47. GraphScope/Gate.lean:77-100. HasseView/Gate.lean:84-94. DistLens/Widget.lean:110-131 (weightSuggestions builds strings) and Verify.lean:48-86 (pmf_num). TreeScope/Evolve.lean:189-204.
- Compact table. Missing = non-widget modules absent from QED64's 5,003 served modules (transitive closure of the package root). Native64 = how many of those already have native64 oleans in extra-tree.
| Pkg | Direct external imports (missing) | Missing | Native64 | Still to compile | RPC/EditLink | evalExpr | Demo heavy parts |
|---|---|---|---|---|---|---|---|
| interval-inspector | 14 (HtmlDisplay) | 1 | 1 | 0 | RPC+EditLink (tactic) | no | none |
| expr-xray | 5 (HtmlDisplay, Panel.SelectionPanel) | 2 | 1 | 1 | RPC panel | no | none |
| simp-lens | 2 (HtmlDisplay) | 1 | 1 | 0 | TryThis | no | previews re-run simp |
| graph-scope | 9 (HtmlDisplay, SG.Basic, SG.Connectivity.Finite, SG.CycleGraph*, SG.Hasse*) | 36 (22 w/o Demo) | 1 | 35 | RPC+EditLink | yes | gate per vertex |
| tree-scope | 7 (HtmlDisplay, Catalan.Tree) | 3 | 1 | 2 | none | yes | #tree_evolve frames |
| hasse-view | 13 (HtmlDisplay) | 1 | 1 | 0 | RPC+EditLink | yes | gate per candidate |
| dist-lens | 13 (HtmlDisplay, 4 Probability.*) | 573 | 169 | 404 | RPC+EditLink | yes | 17 pmf_num examples |
| chart-kit | 2 (HtmlDisplay) | 1 | 1 | 0 | none | yes | none |
| union | — | 609 | 170 | 439 | | | |
(* = only via Demo.lean)
  - EVIDENCE: Aggregated from the facts above (cl.py output and extra-tree existence checks).

## Recipes
### Reproduce the missing-module computation (read-only)
1. python3 /private/tmp/claude-501/-Users-fawadhaider-code-lean-questions/49e7f0e4-0411-414e-9d80-197cafce4da7/scratchpad/closure-agent-modlist/cl.py is a library. Load it with exec(open(...).read()) and call closure('<RootModule>').
1. It takes the served set from qed64/public/profiles/{lean-core,mathlib-essential}.manifest.json, parses headers of non-served modules from the kernel repo's mathlib4 tree + .lake/packages + the v4.34.0 elan toolchain src, and does not recurse into served modules (the served set is import-closed).
1. The result for all eight packages is in .../closure-agent-modlist/missing.json (union 609). Note: the shared scratchpad root has a different agent's closure.py and missing.json; use the closure-agent-modlist/ copies.
Evidence: Same counts as in facts: 1/2/1/36/3/1/573/1.

### Produce the QED64-usable delta + widget oleans (outline only; not run here, since long builds are excluded by this task)
1. Copy (do not modify) /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0/mathlib/mathlib4 into a widgets-owned workspace. Seed it with the native64 oleans already there (3,122 Mathlib modules in .lake/build, plus extra-tree), keeping the zero-githash headers.
1. Delete or quarantine the 11 official-githash ProofWidgets oleans in the copied proofwidgets build dir, notably Component/Panel/SelectionPanel.olean, so Lake cannot reuse them.
1. Inside Docker image qed64-toolchain:emsdk-6.0.5, use native64 lean from /Users/fawadhaider/code/wasm64-lean-kernel-build-v4.34.0/native/stage1/bin (kernel commit 8d91aadcda, the same gitRevision as the served packs' manifest content.lean.gitRevision '8d91aadcda8a'). Compile the 439 missing modules (dist-lens 404, graph-scope 35, Catalan 2, SelectionPanel 1). Then compile the 8 packages' non-Tests modules: 71 widget modules including roots and Demos.
1. Verify every produced .olean has 32 zero bytes at offset 0x28, and that .ir/.ir.sig/.olean.private/.olean.server siblings exist (the manifests list all five artifact kinds per module).
1. Phase 1 without dist-lens needs only 38 compiles (35 SimpleGraph-related + 2 Catalan + SelectionPanel) on top of reused HtmlDisplay. dist-lens adds 404 more modules (~400 MB raw).
Evidence: Olean header comparison, extra-tree contents and the per-package 'still to compile' counts in facts.

### Header shims so the stock page boots the overlay umbrella (Option 1 milestone)
1. Create QED64/Widgets/<Pkg>.lean files in the widgets workspace (not in the QED64 repo). Simplest form: `import <Pkg>`, the root, which includes Demo's Mathlib imports such as pathGraph/cycleGraph and Fintype.Powerset that the snippets rely on. A leaner form is `import <Pkg>.Widget` plus Demo's import lines (graph-scope then needs SimpleGraph.Hasse + CycleGraph explicitly; tree-scope also needs TreeScope.Evolve and Instances.*).
1. Bake the superset `mathlib` snapshot over QED64.Essential + the shims. Every snippet header must then be `import QED64.Widgets.<Pkg>` so that needsMathlib() is true (resident-session.ts:78) and widen applies (main.ts:382).
1. For the vendored page (Option 2), headers can stay `import <Pkg>` because the page supplies its own ResidentPolicy.snapshotsFor.
Evidence: resident-session.ts:74-85; main.ts:377-386.

### interval-inspector showcase snippet (from IntervalInspector/Demo.lean §1, §3, §5, §9)
1. import IntervalInspector   -- stock page: import QED64.Widgets.IntervalInspector

-- Two half-open bars meeting at 2; suggests Set.Ioc_union_Ioc_eq_Ioc.
#interval_inspect (Set.Ioc (1:ℝ) 2 ∪ Set.Ioc 2 3 = Set.Ioc 1 3)

-- Mismatch: [0,3] ⊄ [1,2] — the uncovered regions are shaded red.
#interval_inspect (Set.Icc (0:ℝ) 3 ⊆ Set.Icc 1 2)

-- Set-builder spelling recognised as Ico.
#interval_inspect ({x : ℝ | 0 ≤ x ∧ x < 1} ⊆ Set.Icc 0 1)

-- RPC panel: cursor on `interval_inspect?`; clicking a suggestion
-- replaces the tactic with it (MakeEditLink).
example {a b c : ℝ} (h₁ : a ≤ b) (h₂ : b ≤ c) :
    Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c := by
  interval_inspect?
  exact Set.Ioc_union_Ioc_eq_Ioc h₁ h₂
Evidence: Demo.lean:19, :24-27, :57, :110; Widget.lean:228-231.

### expr-xray showcase snippet (from ExprXRay/Demo.lean)
1. import ExprXRay   -- stock page: import QED64.Widgets.ExprXRay

-- Both sides print as `if 2 = 2 then 1 else 0`; the diff ranks the
-- Decidable instance argument as the top mismatch.
#xray_diff @ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0,
           @ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0

#xray (1 + 1 : Nat)
#xray ((3 : Nat) : Int)
#xray_diff @PUnit.{1}, @PUnit.{2}

-- RPC panel: cursor inside the proof; shift-click one subterm to x-ray it,
-- two to compare them.
theorem xray_panel_demo (n : Nat) :
    @ite Nat (n = n) (instDecidableEqNat n n) 1 0 =
    @ite Nat (n = n) (Classical.propDecidable (n = n)) 1 0 := by
  with_panel_widgets [ExprXRay.XRayPanel]
    simp
Evidence: Demo.lean:21-22, :72, :78, :98, :124-130; Widget.lean:184-186.

### simp-lens showcase snippet (from SimpLens/Demo.lean; #guard_msgs dropped)
1. import SimpLens   -- stock page: import QED64.Widgets.SimpLens

-- Cursor on any `simp_lens`: filmstrip of rewrites, minimal call,
-- exclusion previews, and a clickable `Try this: simp only [...]`.
example (n : Nat) : 0 + (n + 0 + 0) = n := by simp_lens

example (l : List Nat) : (l ++ []).map id = l.map id ++ [].map id := by simp_lens

-- The review scenario: a fat call; only two supplied lemmas fire.
set_option linter.unusedSimpArgs false in
example (n : Nat) (l : List Nat) : n + 0 = n ∧ l ++ [] = l := by
  simp_lens [Nat.add_zero, Nat.zero_add, List.append_nil, List.map_cons,
             Nat.mul_one, and_true]

-- Locations: one filmstrip section per location.
example (n : Nat) (h : n + 0 = 5) : n + 0 + 0 = 5 := by
  simp_lens at h ⊢
  exact h
Evidence: Demo.lean:32, :39, :66-75, :136-138.

### graph-scope showcase snippet (from GraphScope/Demo.lean)
1. import GraphScope   -- includes Demo's SimpleGraph.Hasse/CycleGraph imports

open SimpleGraph

-- pathGraph ships no DecidableRel; the idiomatic local fix (redundant if the
-- root GraphScope is imported: its Demo declares the same instance globally).
instance (n : ℕ) : DecidableRel (pathGraph n).Adj := fun _ _ =>
  decidable_of_iff _ pathGraph_adj.symm

-- Odd cycle: not bipartite, the stats show a witness. Click an edge, vertex
-- or the components line to insert a verified `example … := by decide`.
#graph_scope (cycleGraph 5)
#graph_scope (completeGraph (Fin 5))

def twoTriangles : SimpleGraph (Fin 6) :=
  SimpleGraph.fromRel fun a b =>
    (a, b) ∈ [((0 : Fin 6), (1 : Fin 6)), (1, 2), (0, 2), (3, 4), (4, 5), (3, 5)]
instance : DecidableRel twoTriangles.Adj := by unfold twoTriangles; infer_instance
#graph_scope twoTriangles

#graph_scope (pathGraph 5) walk [1, 2, 3] highlight [0, 4]
#graph_scope (cycleGraph 6) layout layered
1. Lean-closure variant (22 missing modules instead of 36): drop pathGraph and cycleGraph and keep completeGraph, ⊥, fromRel and fromEdgeSet, which are all in SimpleGraph.Basic.
Evidence: Demo.lean:37-38, :47-52, :71, :74, :105, :118; SimpleGraph/Basic.lean:156, :332.

### tree-scope showcase snippet (from TreeScope/Demo.lean)
1. import TreeScope   -- stock page: import QED64.Widgets.TreeScope

#tree_scope [10, 20, 30]

inductive Arith where
  | num (n : Nat)
  | add (a b : Arith)
  | mul (a b : Arith)

def sample : Arith :=
  .mul (.add (.num 1) (.mul (.num 2) (.num 3))) (.add (.num 4) (.num 5))
#tree_scope sample   -- term-structure reflection, no Repr needed

def rbSample : Lean.RBMap Nat String compare :=
  Lean.RBMap.ofList [(5, "e"), (2, "b"), (8, "h"), (1, "a"), (4, "d"),
                     (7, "g"), (3, "c"), (6, "f")]
#tree_scope rbSample   -- colours, bh= sublabels, invariants caption

#tree_evolve (Lean.RBMap.empty : Lean.RBMap Nat String compare) [
  (·.insert 1 "a"), (·.insert 2 "b"), (·.insert 3 "c"), (·.insert 4 "d"),
  (·.insert 5 "e"), (·.insert 6 "f")]

open TreeScope in
#html renderForest (BinTree.catalanGallery 4) (maxRowWidth := 900)
Evidence: Demo.lean:23, :46-60, :95-100, :111-113, :165; Render.lean:389 (TreeScope.renderForest); Instances/MathlibTree.lean:35 and :106 (TreeScope.BinTree.catalanGallery).

### hasse-view showcase snippet (from HasseView/Demo.lean)
1. import HasseView   -- root needed: Demo's Fintype.Powerset/Finset.Sort supply Finset instances

-- The powerset cube: click an insertable fact to insert a gate-verified
-- `example : … := by decide` after the command (RPC + MakeEditLink).
#hasse (Finset (Fin 3))
#hasse (Fin 5)
#hasse (Bool × Bool)
#hasse (Finset (Fin 3)) updown 1 highlight [0, 7]

-- A NON-lattice: 1 and 2 have upper bounds {3, 4} but no join.
def Bowtie := Fin 5
instance : DecidableEq Bowtie := inferInstanceAs (DecidableEq (Fin 5))
instance : Fintype Bowtie := inferInstanceAs (Fintype (Fin 5))
instance : Repr Bowtie := inferInstanceAs (Repr (Fin 5))
instance : LE Bowtie := ⟨fun a b => a = b ∨ a.val = 0 ∨ (a.val ≤ 2 ∧ 3 ≤ b.val)⟩
instance : DecidableLE Bowtie := fun a b =>
  decidable_of_iff (a = b ∨ a.val = 0 ∨ (a.val ≤ 2 ∧ 3 ≤ b.val)) Iff.rfl
instance : Preorder Bowtie where
  le_refl := by decide
  le_trans := by decide
instance (n : Nat) : OfNat Bowtie n := inferInstanceAs (OfNat (Fin 5) n)
#hasse Bowtie highlight [1, 2]
Evidence: Demo.lean:2-5, :48, :90, :96, :107-138, :150.

### dist-lens showcase snippet (from DistLens/Demo.lean; one pmf_num line kept)
1. import DistLens   -- stock page: import QED64.Widgets.DistLens (573-module delta)

open PMF
open scoped ENNReal NNReal
set_option linter.deprecated false   -- PMF.bernoulli/binomial deprecated at this pin

noncomputable def die : PMF (Fin 6) := uniformOfFintype (Fin 6)
#dist die   -- bars + click-to-insert verified weight goals (RPC + MakeEditLink)

noncomputable def twoDice : PMF ℕ :=
  die.bind fun a => die.map fun b => a.val + b.val
#dist twoDice
#dist_film twoDice

noncomputable def twoFlips : PMF (Fin 3) := binomial (1/2) (by norm_num) 2
#dist twoFlips

noncomputable def weather : Fin 2 → PMF (Fin 2) :=
  ![PMF.ofFintype ![3/4, 1/4] (by simp [Fin.sum_univ_succ]; ennreal_num),
    PMF.ofFintype ![1/2, 1/2] (by simp [Fin.sum_univ_succ]; ennreal_num)]
#chain weather init [0] steps 4

-- What a click inserts (the heaviest line: simp + norm_num over ℝ≥0∞):
example : twoDice 5 = 1/6 := by unfold twoDice die; pmf_num
Evidence: Demo.lean:18-21, :26-28, :40-47, :79-81, :113-118.

### chart-kit showcase snippet (from ChartKit/Demo.lean §1 and §5)
1. import ChartKit   -- stock page: import QED64.Widgets.ChartKit
open ChartKit

def diceWays (s : Nat) : Nat := 6 - ((s : Int) - 7).natAbs
def dicePmf : Array (Rat × Rat) :=
  (Array.range 11).map fun i =>
    let s : Nat := i + 2
    ((s : Rat), ((diceWays s : Nat) : Rat) / 36)
-- The chart IS the theorem's data: exact masses sum to 1.
#guard dicePmf.foldl (fun acc (_, p) => acc + p) 0 = 1

def diceChart : ChartSpec := {
  title? := some "Sum of two dice", xLabel := "sum", yLabel := "probability",
  series := #[{ name := "P(sum)", mark := .bar, data := dicePmf }] }
#chart diceChart

def weekChart : ChartSpec := {
  title? := some "Commits per weekday", yLabel := "commits",
  series := #[{ name := "commits", mark := .bar,
                data := #[(0, 12), (1, 17), (2, 8), (3, 21), (4, 5)] }],
  xTickLabels := #["Mon", "Tue", "Wed", "Thu", "Fri"],
  valueLabels := true, showLegend := false }
#chart weekChart
Evidence: Demo.lean:23-40, :108-119.


## Risks
- Stale official oleans. The kernel tree's proofwidgets build dir holds 11 official-toolchain oleans, including Panel/SelectionPanel.olean. A Lake-driven build over a copy of that tree may treat them as up to date and pack an olean QED64 cannot load. Check the zero githash at 0x28 for every artifact before baking.
- DistLens is the long pole: 573 missing modules (404 not yet built by native64, about 400 MB raw before snapshot overhead). The cause is Mathlib's PMF.Constructions → Probability.Distributions.Bernoulli import at 5ed2965, so the widget cannot avoid it without a Mathlib change. Phase 1 should probably be seven packages.
- Superset snapshot memory: QED64's stock page commits 2 GiB initial heap with the umbrella (resident-session.ts:87-94) and caps at 6 GiB (:99). A 609-module superset region on top of the current 1.13 GB `mathlib` region will exercise the grow path the code associates with renderer crashes.
- Interpreted recursion depth: all widget and Mathlib code runs in the IR interpreter on a 1 MB worker stack (HARDENING.md:239). Deep recursion that is fine natively can overflow here: TreeScope reflection (64-level cap, compaction past it), ExprXRay analyzeExpr on deep terms, HasseView/GraphScope gate loops. No browser measurement exists.
- Command latency: each evalExpr in QED64 compiles and then interprets. HasseView and GraphScope gates do one compile per candidate or vertex, so the full Demos may be slow in the browser. The DistLens Demo's 17 pmf_num examples are the heaviest. Use the trimmed snippets, not the full Demo files, as showcase content.
- `import <Pkg>` drags in that package's Demo: its declarations, global instances (e.g. GraphScope.Demo's DecidableRel instances) and, for graph-scope, 14 extra Mathlib modules. User snippets that redeclare the same instances are legal but redundant. Shims that import `<Pkg>.Widget` must then add Demo's Mathlib imports explicitly or snippets break (e.g. `#hasse (Finset (Fin 3))` needs Fintype.Powerset and Finset.Sort).
- Stock-page routing: a header without a Mathlib/Batteries/MIL/QED64 root boots init-only and is never widened (resident-session.ts:74-85, main.ts:382). ChartKit, ExprXRay and SimpLens (no Mathlib dependency) therefore still need a QED64.-rooted shim, or a page policy, to reach the overlay snapshot.
- Pairing: snapshots are binary-paired to runtime wasm64-4b025db7729c5f89, while the packs' manifests still name release …-wasm64-36a96239e08fd2e0 and gitRevision 8d91aadcda8a (packs unchanged across the promote). Widget oleans should come from the same 8d91aadcda native64 compiler, and the bake must target the served runtime id. Any kernel change invalidates the bake.
- Sizes are estimates taken from official-toolchain build outputs. Native64 sizes matched exactly for the two modules compared, but this was not verified across the whole delta.

## Open questions
- Do library-side @[server_rpc_method] + mk_rpc_widget% panels work when the module comes from a baked snapshot region rather than the buffer? Only the buffer-side case is evidenced (tests/adversarial/kernel-probes/rpc-attr.lean; 06 doc §1 update 'rpc says: 42'). This is experiment 1 in 06-qed64-showcase-options.md §5. I found no recorded library-RPC result in qed64/tests or work/.
- Can a `?snapshots=` overlay index register QED64.Widgets.* shims, or a new umbrella module name, so that the kernel's header resolver reports them as covered by the overlay `mathlib` region? The resolver logic is in kernel patch 0032 and was not examined here.
- Is the IR of the 439 newly compiled modules plus the widget modules carried into the snapshot by bake-snapshot.mjs from the lib tree (.ir/.ir.sig present)? evalExpr needs IR for every Mathlib definition it touches (Fintype instances, Nat.divisors, Rat arithmetic). Not verified.
- Native64 compile time and memory for the 404 DistLens-only modules (MeasureTheory/Probability heavy) inside the 8 GB Docker VM: unknown, no measurement exists.
- Browser timings for each snippet, especially HasseView's per-candidate gate, GraphScope's per-vertex gate, SimpLens previews and DistLens pmf_num, and whether any hits the 1 MB interpreted stack: unknown until a page runs them.
- Whether `Lean.RBMap` (used in the TreeScope snippet) emits deprecation warnings at v4.34.0 in QED64's buffer. PORT-NOTES report zero TreeScope changes and green tests, but warning output in a fresh buffer was not checked.
