import SimpLens
import SimpLensTests.Helpers

/-!
# Showcase probe: simp-lens

Dumps the exact top-level panel `Html` the `simp_lens` tactic saves —
`renderPanel` (filmstrip + minimal call + exclusion previews + diagnostics),
`renderPanelFallback` (the degraded heartbeat-budget panel), and
`renderPanelAt` (per-location sections) — for the representative traced runs,
serialized to `../showcase/dumps/simp-lens.json` for the showcase site's
React verification harness.

Each `#probe_dump_lens` / `#probe_dump_lens_at` command below parses its goal
with the REAL surface syntax (so binder and hypothesis names stay
unhygienic, exactly as in a user file) and appends one entry to the dump —
`#probe_dump_init` resets the file first, so one full run of this probe
regenerates the dump from scratch.

Run from the package directory (exactly how `showcase/build.sh` invokes it):

    cd widgets/simp-lens && lake env lean "../showcase/probes/simp-lens.lean"

MUST stay in sync with the package's React-contract tests
(`SimpLensTests/ContractTests.lean`): the entries dumped here are the panels
those tests run `reactContractViolations` over (built by the same
`withRun`/`withRunAt` helpers) — if a panel is added there, add its dump
here.
-/

open Lean Meta Elab Command Term ProofWidgets SimpLens SimpLensTests

/-- Serialize `Html` to the showcase dump schema: elements as
`{tag, t: "el", children, attrs}`, text as `{t: "text", s}`, components as
`{t: "comp", props, name, children}`.  NOTE: at this ProofWidgets pin,
`Html.component` props are `LazyEncodable Json = StateM RpcObjectStore Json`;
they are materialized with a fresh store via `(props.run {}).1`. -/
private partial def probeHtmlJson : Html → Json
  | .element tag attrs children =>
    Json.mkObj [
      ("tag", Json.str tag),
      ("t", Json.str "el"),
      ("children", Json.arr (children.map probeHtmlJson)),
      ("attrs", Json.arr (attrs.map fun (k, v) => Json.arr #[Json.str k, v]))]
  | .text s => Json.mkObj [("t", Json.str "text"), ("s", Json.str s)]
  | .component _ exp props children =>
    Json.mkObj [
      ("t", Json.str "comp"),
      ("props", (props.run {}).1),
      ("name", Json.str exp),
      ("children", Json.arr (children.map probeHtmlJson))]

private def probeEntry (name : String) (h : Html) : Json :=
  Json.mkObj [("tree", probeHtmlJson h), ("name", Json.str name)]

private def probeDump (pkg : String) (entries : Array Json) : Json :=
  Json.mkObj [("package", Json.str pkg), ("entries", Json.arr entries)]

private def dumpPath : System.FilePath := "../showcase/dumps/simp-lens.json"

/-- Append one entry to the dump file (read–modify–write, so the probe's
commands can accumulate entries without cross-command state). -/
private def appendEntry (name : String) (h : Html) : IO Unit := do
  let s ← IO.FS.readFile dumpPath
  match Json.parse s with
  | .error e => throw (IO.userError s!"simp-lens probe: cannot re-parse dump: {e}")
  | .ok j =>
    match j.getObjValAs? (Array Json) "entries" with
    | .error e => throw (IO.userError s!"simp-lens probe: bad dump shape: {e}")
    | .ok entries =>
      IO.FS.writeFile dumpPath
        (probeDump "simp-lens" (entries.push (probeEntry name h))).pretty

/-- Reset the dump file to an empty entry list. -/
elab "#probe_dump_init" : command => do
  IO.FS.writeFile dumpPath (probeDump "simp-lens" #[]).pretty

/-- `#probe_dump_lens "name" ("fallbackName")? goal …clauses` — run the traced
target-only pipeline (same as `#lens_react_contract`) and dump the real
`renderPanel` output; with a second string, also dump the degraded
`renderPanelFallback` panel for the same run. -/
elab "#probe_dump_lens " name:str fb:(str)? t:term ex:(lensWith)? hy:(lensHyps)? : command => do
  withRun t ex hy fun r => do
    let suggestion ← minimalSimpOnlyString r.res.usedTheorems
    let report ← excludeEach r.goalBefore r.ctx r.simprocs none r.res
    let html ← renderPanel r.film suggestion report r.res.diag r.res.goal?.isNone
    appendEntry name.getString html
    if let some fbName := fb then
      let fbHtml ← renderPanelFallback r.film.length suggestion report
        r.res.diag r.res.goal?.isNone
      appendEntry fbName.getString fbHtml

/-- `#probe_dump_lens_at "name" goal …clauses at …` — run the traced
multi-location pipeline (same as `#lens_at_react_contract`) and dump the real
`renderPanelAt` output. -/
elab "#probe_dump_lens_at " name:str t:term ex:(lensWith)? hy:(lensHyps)?
    la:(lensAt)? : command => do
  withRunAt t ex hy la fun r => do
    let suggestion ← minimalSimpOnlyStringAt r
    let report ← excludeEachAt r.goalBefore r.ctx r.simprocs none r.res
      r.simplifyTarget r.fvarIdsToSimp
    let html ← renderPanelAt r.res.films suggestion report r.res.diag
      r.res.goal?.isNone
    appendEntry name.getString html

-- hypothesis binders are referenced by the location clauses, not the body
-- (same convention as the contract tests)
set_option linter.unusedVariables false

#probe_dump_init

-- Multi-frame filmstrip with badges, arrows and exclusion-preview rows, plus
-- the degraded fallback panel for the same run.
#probe_dump_lens "target_arith_multi_frame" "target_arith_fallback"
  ∀ n : Nat, n + 0 + 0 = n

-- Closed-goal panel (✓ outcome span) with a hypothesis lemma badge.
#probe_dump_lens "target_closed_hyp_lemma" ∀ (n : Nat) (h : n = 5), n + 0 = 5 hyps [h]

-- Empty filmstrip ("no steps" note path).
#probe_dump_lens "target_empty_film" (True : Prop)

-- Diagnostics section enabled (tried/used rows).
set_option diagnostics true in
#probe_dump_lens "target_arith_diagnostics" ∀ n : Nat, n + 0 + 0 = n

-- Multi-location panel: per-location sections at a hypothesis and the target.
#probe_dump_lens_at "at_h_target_sections" ∀ (n : Nat) (h : n + 0 = 5), n = 5 ∧ True at h ⊢

-- Wildcard locations.
#probe_dump_lens_at "at_wildcard" ∀ (p q : Prop) (h₁ : p ∧ True) (h₂ : q ∨ False), p ∧ q at *
