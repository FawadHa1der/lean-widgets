# `lean/` — showcase examples and their frozen goldens

Eight showcase documents, one per widget package, written to be pasted into (or
preloaded by the gallery into) QED64's editor, plus the expected InfoView
behaviour for each, computed natively on the stock Lean v4.34.0 toolchain.
Nothing here depends on, or writes to, the QED64 repo or the widget trees.

```
examples/<pkg>.lean      the document the user sees (≤ 60 lines)
examples/<pkg>.json      the example spec: cursors, clicks, selections, hovers, code actions (authored intent)
expect/<pkg>.json        the frozen golden in the package's PRIMARY env: what the InfoView must show / do (generated)
expect/w8/<pkg>.json     the same golden in env w8, for the 7 phase-1 packages (the phase-2 bake serves all eight)
expect/html/[w8/]<pkg>.json  the full RPC-encoded Html of every panel (refs normalized; for React-contract checks)
goldens/                 the generator and gates (see "How the goldens were produced")
../lean/expect/click-all/[w8/]<pkg>.json  every rendered link clicked on a fresh copy (see "Click-all")
```

Packages: `chart-kit`, `expr-xray`, `simp-lens`, `interval-inspector`, `graph-scope`,
`tree-scope`, `hasse-view` (phase 1, bake `widgets7`) and `dist-lens` (phase 2, `widgets8`).

## The example documents (`examples/<pkg>.lean`)

* **Header** is exactly two lines, `import Mathlib` / `import <Pkg>` (plan D2).
  On the QED64 page `Mathlib` is covered by the overlay region (QED64.Essential +
  the bake's package roots); in VS Code it is ordinary full Mathlib.
* **Header comment** (`/-! … -/`) tells the reader where to put the cursor and
  what to click.
* **Body** is wrapped in `namespace Showcase.<Pkg>` so nothing collides with the
  packages' own `<Pkg>.Demo` declarations, which are always in scope because
  every package root imports its Demo (covered-mode "already declared" notes).
* **Cheap to elaborate**: in the browser, non-core code runs in the IR
  interpreter on a ~1 MB stack.  The examples are trimmed versions of each
  package's `Demo.lean`; what was left out is listed in `examples/<pkg>.json`
  under `"dropped"` (heaviest first).
* **Zero errors and zero warnings** before any click (info messages such as
  SimpLens' `Try this:` are expected) **and after any single click of any
  rendered link** — not only the declared ones (the click-all gate, below).
  Where a link inherently leaves goals (IntervalInspector's `refine …` suggestions),
  the proof's last line closes the goal in both states, e.g.
  `all_goals first | exact Set.Ioc_union_Ioc_eq_Ioc h₁ h₂ | assumption`; that file
  turns off `linter.unreachableTactic` / `linter.unusedTactic`, which would otherwise
  flag whichever branch does not run (said so in a comment in the file).

## The example spec (`examples/<pkg>.json`)

```jsonc
{
  "package": "hasse-view", "title": "HasseView", "blurb": "…one line…",
  "header": ["import Mathlib", "import HasseView"],
  "cursors": [                       // where the test puts the cursor; one entry per panel to assert
    { "line": 17, "character": 0,    // 0-based LSP position (character in UTF-16 units)
      "command": "#hasse (Finset (Fin 3))",          // must occur on that line (drift guard)
      "expect": {                    // hand-written, partial expectations (all optional)
        "panelTitle": "HTML Display",                // static HtmlDisplayPanel summary text
        "svgTagCounts": { "rect": 8, "line": 12, "text": 16 },
        "texts": ["…"], "linkTexts": ["∅ ⋖ {0}"] } } ],
  "clicks": [
    { "cursorLine": 17,              // the cursor whose panel holds the link
      "linkText": "∅ ⋖ {0}",         // text of the link; SVG edge links have "" and are
      "linkTitle": "…",              //   identified by their `title` instead
      "kind": "makeEditLink",        // ProofWidgets MakeEditLink in a panel | "tryThis" (core textInsertionWidget "[apply]" in a message)
      "expectedEdit": { "range": {…}, "newText": "\nexample : … := by decide" },  // exact LSP TextEdit (UTF-16)
      "postClickDiagnostics": "clean" } ],   // "clean" = no error/warning anywhere after re-elaboration,
                                             // or a list of {severity, line?, contains?} designed messages
  "selections": [                    // shift-click in the goal view (InfoView selectedLocations)
    { "line": 45, "character": 2, "command": "interval_inspect?",
      "select": [ { "goal": 0, "hyp": "hx" } | { "goal": 0, "target": "<subterm text>", "occurrence": 0 } ],
      "expect": { "texts": ["…"] } } ],
  "hovers": [                        // hover a subterm inside a panel's InteractiveCode
    { "cursorLine": 15, "panel": 0, "code": 0, "tagText": "n", "expect": { "typeText": "ℕ" } } ],
  "codeActions": [                   // the lightbulb: textDocument/codeAction at (line, character)
    { "line": 15, "character": 46,   //   (+ codeAction/resolve for lazy actions)
      "sameEditAsClick": 0,          // an action's single edit must equal that click's rendered
                                     //   Try-this edit (and, superset env, its frozen expectedEdit)
      "expect": { "titles": ["Try this: simp only"] } } ],
  "dropped": ["…Demo items left out and why…"]
}
```

All positions are 0-based LSP positions; `character` is the first non-blank
column of the command line.  `expectedEdit` values are generated (they are the
exact payloads the server produced) and then frozen.

## The goldens (`expect/<pkg>.json`)

Per package: toolchain, environment (header resolution and LEAN_PATH), the
document's diagnostics, and

* `cursors[].panels[]` — one entry per panel widget `Lean.Widget.getWidgets`
  returns at that cursor: widget `id`; `kind` (`static` = ProofWidgets
  `HtmlDisplayPanel`, `rpc` = a `mk_rpc_widget%` panel with its `method`);
  the JS module check (`getWidgetSource` bytes/sha256, imports
  `@leanprover/infoview`); `tagCounts` (all elements) and `svgTagCounts`
  (elements inside `<svg>`); `components` (`MakeEditLink`, `InteractiveCode`, …);
  `texts` (non-blank text nodes, document order); `codeTexts` (text of each
  `InteractiveCode`); `linkTexts` and `links[]` (each MakeEditLink's text,
  `title`, exact edit `{range,newText}`, document version, `newSelection`);
  `htmlSha256` over the ref-normalized Html.
* `selections[]` — the same panel signature after shift-click selections
  (with the `selectedLocations` sent).
* `hovers[]` — the `infoToInteractive` type text of a hovered subterm.
* `clicks[]` — the link found, the exact edit, the post-click diagnostics of
  the re-elaborated document, and the verdict against `postClickDiagnostics`.
* `codeActions[]` — every action `textDocument/codeAction` returns at the
  declared position (title, kind, edits, whether it was resolved lazily) and
  whether it equals the declared click's edit.  SimpLens: all 6 positions offer
  exactly one `quickfix` titled `Try this: simp only […]` whose edit equals the
  `[apply]` link's edit (core `tryThisProvider`, `Lean/Meta/Tactic/TryThis.lean`).
* `declaredChecks[]` / `ok` — every expectation from the spec, checked.

### Environment-dependent fields (never compare these across runs/environments)

| field | why it differs |
|---|---|
| `cursors[].panels[].htmlSha256` of every panel holding a MakeEditLink (and `expect/html` for those panels) | the link's props embed `edit.textDocument.uri` and `.version` of the run's document (native: `file:///…/golden-run/<pkg>-superset/Showcase.lean`; browser: QED64's `file:///project/…`). Panels without links (chart-kit, expr-xray, simp-lens, tree-scope) hash identically across runs. |
| `links[].documentVersion`, `clicks[].documentVersionInEdit` | LSP document version at render time (1 natively; whatever the editor is at in the browser) |
| `selections[].selectedLocations[].mvarId` / `loc.hyp` fvarIds | native session ids (`_uniq.N`); a browser test must shift-click the DOM, not replay them |
| `codeActions[].actions[].documentVersion` | the versioned identifier of the code action's edit |
| `environment.leanPath`, `clicks[].editedFile`, `generatedAt`, `elaborationMs`, `reElaborationMs`, `rpcMs`, `totalMs` | paths and timings |

Everything else (tag multisets, texts, code texts, link texts/titles, edit
`range`+`newText`, `newSelection`, JS module sha256, click verdicts, diagnostics)
is environment-independent between w7 and w8 — checked by `summary.mjs`
(table "env-independent signature w7 == w8").

UX tests should compare the browser against these: SVG tag multiset and texts
for render assertions; for clicks, the text diff must equal `edit`
(range + newText; MakeEditLink's `textDocument.uri/version` legitimately differ
in the browser) and the post-click diagnostics must match.

## How the goldens were produced (`goldens/`)

* **`golden-env.sh build`** builds the browser-equivalent native environment.
  QED64 resolves `import Mathlib` / `import <Pkg>` as *covered* by the overlay
  snapshot, whose environment is QED64.Essential (the 4,354 served modules,
  `wasm64-lean-kernel-build-v4.34.0/mathlib/essential-modules.txt`) plus the
  bake's package roots.  We compile a **shadow `Mathlib.olean`** (an umbrella
  importing exactly that module list + the 7 phase-1 roots, `w7`; + DistLens,
  `w8`) with the stock v4.34.0 `lean`, place it first on `LEAN_PATH` next to an
  APFS clone (`cp -cR`) of the real `Mathlib/` subtree (Lean resolves a module
  root at the first search-path dir holding `Mathlib/` or `Mathlib.olean`), so
  the *unmodified* browser text resolves to the browser's module set.  All
  inputs are read-only uses of the widget trees' official-toolchain builds
  (Mathlib/deps 5ed2965 = the kernel's pin, every dependency rev equal);
  ProofWidgets is merged from the per-package partial builds (all overlapping
  `.olean/.ir` byte-identical).
* **`lsp-golden.mjs --pkg <pkg> [--mode superset|closure] [--env w7|w8]`** drives the stock
  `lean --server` over LSP exactly like the InfoView drives QED64's worker:
  `didOpen` → `textDocument/waitForDiagnostics` (+ empty `$/lean/fileProgress`)
  → `$/lean/rpc/connect` → per cursor `Lean.Widget.getWidgets`,
  `getInteractiveGoals`, `getInteractiveTermGoal`, `getWidgetSource`; static
  panels use `props.html`; `mk_rpc_widget%` panels are rendered by calling
  their own `@[server_rpc_method]` (name read from the widget JS) with the
  InfoView's panel props `{pos, goals, termGoal, selectedLocations, …stored
  props}` — including ProofWidgets' cancellable protocol
  (`ProofWidgets.checkRequest`).  Clicks: MakeEditLink edits come from the
  rendered Html (`props.edit.edits[0]`), Try-this edits from
  `getInteractiveDiagnostics` (`Lean.Meta.Hint.textInsertionWidget` props:
  `{range, newText: suggestion}`); the edit is applied UTF-16-correctly, sent
  as a full-text `didChange`, the new version's diagnostics are checked, and
  the document is reverted.  This is the native twin of the plan's E3
  `rpc-probe.mjs` (and of the packages' `*Tests/ClickE2E.lean`, which simulate
  the same click in-process from the stored props).  No lakefile is visible
  and `LAKE` points nowhere, so `LEAN_PATH` alone decides the imports.
  `--update-spec` (authoring only) resolves cursor lines and freezes
  `expectedEdit`.
* **`native-gate.sh <pkg> [file [tag]]`** is the CLI gate.  Default
  (`GATE_ENV=closure`): the `import Mathlib` line is blanked (kept as an empty
  line so line numbers do not move) and the file is compiled with
  `lake env lean` from the package's own built tree — proving every name is in
  the package closure, hence in the bake superset.  `GATE_ENV=superset`:
  unmodified text, plain `lean` with the golden-env `LEAN_PATH`
  (`GOLDEN_ENV=w7|w8`, default the package's primary env).
* **`click-all-cli.sh <pkg>`** (`GOLDEN_ENV` as above) compiles every edited
  file of a click-all run with the superset CLI gate (`CLICK_ALL_JOBS` in
  parallel, default 4) and requires agreement with the LSP verdict (`clean` ⇒
  rc 0 and 0 warnings) — an independent second opinion on the LSP run.
* **`run-all.sh`** runs, per package: closure CLI gate on the example (required);
  then for each env of the package (w7 and w8 for phase-1 packages, w8 only for
  dist-lens): superset CLI gate (required), the superset LSP golden (required;
  writes `expect/` or `expect/w8/`), every declared click's edited file through
  the superset CLI gate (required: rc 0 and no warnings for `clean`; primary env
  also through the closure CLI gate for information), the **click-all** LSP run
  (required: 0 broken) and, primary env, the click-all CLI cross-check
  (`click-all-cli.sh`: every click-all edited file through the superset CLI gate
  must agree with the LSP verdict); finally an LSP run in the closure
  environment (sensitivity).
  Results: `$W/goldens/run-all.tsv`; logs: `$W/logs/examples-*.log`, `$W/logs/clickall-*.log`.
* **`lsp-golden.mjs --click-all`** (the click-all gate).  Declared clicks cover
  only what the spec names; this mode clicks *everything*.  It probes
  `Lean.Widget.getWidgets` at the start of every whitespace-separated token of
  every line (plus the declared cursors; a few hundred probes per file), renders
  every distinct panel instance (static, or the `mk_rpc_widget%` method with the
  goals at that position) and every declared selection, collects every
  MakeEditLink in their Html and every core Try-this link in the document's
  interactive diagnostics, deduplicates by exact edit (range + newText), then for
  each link applies the edit UTF-16-correctly to a **fresh copy of the example**,
  sends it as a full-text `didChange`, waits for that version's diagnostics, and
  classifies: `clean` (no error/warning), `designed` (a declared click whose
  `postClickDiagnostics` lists exactly those messages), `broken` (anything else).
  Writes `lean/expect/click-all/[w8/]<pkg>.json` (every link: kind, text/title, edit,
  where it was rendered, classification, the errors/warnings, edited file);
  `summary.mjs` writes `lean/expect/click-all/summary.json`.
* **`summary.mjs`** prints the per-package table; **`crosscheck.mjs`** compares
  goldens with the widget suite's own probe dumps (`widgets-v4.34/showcase/dumps`).

### Environment sensitivity (why the goldens use the superset environment)

`run-all.sh` also renders every cursor in the closure-only environment
(`$W/goldens/<pkg>.closure.json`).  Comparing the uri-independent signature
(SVG tags, texts, link texts, edits): chart-kit, interval-inspector,
graph-scope, tree-scope, hasse-view and dist-lens are identical; two packages
are environment-sensitive, so the goldens must come from the superset:

* **expr-xray** — Mathlib's `ℕ`/`ℤ` notations replace `Nat`/`Int` in every
  type string, and `#xray_diff @PUnit.{1}, @PUnit.{2}` prints the levels
  (`PUnit.{1}`) in the superset.
* **simp-lens** — with Mathlib's default `simp` set the minimal call is
  `simp only [add_zero, zero_add]` (closure only: `Nat.add_zero, Nat.zero_add`);
  3 of the 6 Try-this edits differ.  Consequently the closure CLI gate of
  those post-click files fails by design (`add_zero` is a Mathlib name) and is
  reported as information; the superset CLI gate (the browser's environment) is
  the required one.  The hover type is `ℕ` (superset) vs `Nat` (closure).

`crosscheck.mjs` against the suite's own probe dumps (same inputs): ChartKit
dice/cdf/growth/week, IntervalInspector union/membership/ℕ-caveat and the
DistLens filmstrip are identical; the rest have identical SVG tag multisets and
differ only in text for explained reasons (`ℕ` vs `Nat`; DistLens qualifies
`unfold Showcase.DistLens.die` because the example lives in a namespace;
the hasse-view dump labels the cube's elements by index, the live panel by their `Repr` labels `∅`, `{0}`, …).

### Regenerating

```
lean/goldens/golden-env.sh build          # once (≈30 s; writes $W/golden-env)
lean/goldens/run-all.sh [pkg …]           # ≈ 2–4 min per package (both envs + click-all)
node lean/goldens/lsp-golden.mjs --pkg <pkg> --click-all [--env w8]   # one click-all run
node lean/goldens/summary.mjs             # tables + lean/expect/click-all/summary.json
node lean/goldens/crosscheck.mjs
```
Editing an example: run `python3 lean/goldens/mkspec.py relocate examples/<pkg>.json examples/<pkg>.lean`
then `node lean/goldens/lsp-golden.mjs --pkg <pkg> --update-spec` to refresh
line numbers and frozen edits, then `run-all.sh <pkg>`.  `--update-spec` only writes in the package's primary
env; the w8 golden of a phase-1 package must reproduce the same frozen edits.
