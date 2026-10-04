import SimpLens.Film
import SimpLens.Minimize
import SimpLens.Exclude
import ProofWidgets.Component.HtmlDisplay

/-!
# SimpLens.Render — filmstrip HTML for the InfoView

Renders a traced `simp` run as a `ProofWidgets.Html` tree:
* header with the minimal `simp only [...]` call,
* numbered frames with a lemma badge and interactive before/after expressions
  (`InteractiveCode` over `Widget.ppExprTagged`, so hover types and
  go-to-definition work),
* exclusion previews inside `<details>` sections,
* a diagnostics line (tried vs. used counts) when diagnostics are enabled.
-/

namespace SimpLens

open Lean Meta Simp Server ProofWidgets
open scoped ProofWidgets.Jsx

/-- Short display label for an origin (used on lemma badges). -/
def originBadgeText (o : Origin) : MetaM String := do
  match o with
  | .decl n _ inv => return (if inv then "← " else "") ++ toString n
  | .fvar fvarId =>
    match (← getLCtx).find? fvarId with
    | some ldecl => return toString ldecl.userName
    | none => return "‹local›"
  | .stx _ ref => return toString ref.prettyPrint
  | .other n => return toString n

/-- Interactive rendering of an expression (hover/go-to-def enabled). -/
def exprHtml (e : Expr) : MetaM Html := do
  return <InteractiveCode fmt={← Widget.ppExprTagged e} />

/-- Gray monospace pill used for lemma badges. -/
def badge (text : String) : Html :=
  <span style={json% {
      background: "var(--vscode-badge-background, #4d4d4d)",
      color: "var(--vscode-badge-foreground, #ffffff)",
      borderRadius: "8px",
      padding: "1px 7px",
      fontFamily: "monospace",
      fontSize: "0.85em",
      marginRight: "6px"}}>{.text text}</span>

/-- Render one frame: number, lemma badge(s), before → after. -/
def frameHtml (fr : Frame) : MetaM Html := do
  let mainBadge := badge (← originBadgeText fr.step.principal)
  let sideCount := fr.step.origins.size - 1
  let side : Array Html :=
    if sideCount > 0 then
      #[<span style={json% {opacity: "0.7", fontSize: "0.8em"}}>
          {.text s!"(+{sideCount} side-condition lemma{if sideCount == 1 then "" else "s"})"}
        </span>]
    else #[]
  let before ← exprHtml fr.step.before
  let after ← exprHtml fr.step.after
  return <div style={json% {
      padding: "4px 6px",
      borderLeft: "2px solid var(--vscode-textLink-foreground, #3794ff)",
      marginBottom: "4px"}}>
    <div>
      <span style={json% {fontWeight: "bold", marginRight: "6px"}}>{.text s!"{fr.index + 1}."}</span>
      {mainBadge}
      <span style={json% {opacity: "0.6", fontSize: "0.8em", marginRight: "6px"}}>
        {.text fr.step.phase.label}
      </span>
      {...side}
    </div>
    <div style={json% {paddingLeft: "18px"}}>
      {before}
      <span style={json% {margin: "0 8px", opacity: "0.7"}}>{.text "→"}</span>
      {after}
    </div>
  </div>

/-- Render the exclusion previews as `<details>` rows. Failed re-runs get a
distinct marker naming the cause: a timed-out preview (`⏱`) usually means the
excluded lemma is what keeps the call fast, an errored one (`⚠`) that the
re-run failed outright; neither ever fails the tactic. -/
def exclusionsHtml (report : ExclusionReport) : MetaM Html := do
  if report.disabled then
    return <div style={json% {opacity: "0.6", fontSize: "0.85em"}}>
      {.text "Exclusion previews disabled (-previews)."}
    </div>
  if report.outcomes.isEmpty then
    return <span />
  let landsLabel := match report.watch? with
    | none => "lands at: "
    | some h => s!"{h} lands at: "
  let rows ← report.outcomes.mapM fun oc => do
    let name ← originBadgeText oc.origin
    let landing : Html :=
      match oc.status with
      | .timedOut => .text "preview unavailable — re-run timed out (the call may be much slower, or diverge, without this lemma)"
      | .errored => .text "preview unavailable — re-run errored"
      | .ok =>
        match oc.landingGoal? with
        | none => .text "goal still closed"
        | some g => <code style={json% {whiteSpace: "pre-wrap"}}>{.text g}</code>
    let marker : Html :=
      match oc.status with
      | .timedOut =>
        <span style={json% {color: "var(--vscode-charts-orange, #d18616)"}}>{.text "⏱ timed out "}</span>
      | .errored =>
        <span style={json% {color: "var(--vscode-errorForeground, #f48771)"}}>{.text "⚠ errored "}</span>
      | .ok =>
        if oc.essential then
          <span style={json% {color: "var(--vscode-errorForeground, #f48771)"}}>{.text "● essential "}</span>
        else
          <span style={json% {opacity: "0.6"}}>{.text "○ redundant "}</span>
    return <details style={json% {marginLeft: "8px"}}>
      <summary>{marker}{.text s!"without "}{badge name}</summary>
      <div style={json% {paddingLeft: "20px"}}>{.text landsLabel}{landing}</div>
    </details>
  let note : Array Html :=
    if report.truncated then
      #[<div style={json% {opacity: "0.6", fontSize: "0.85em"}}>
          {.text s!"(previews truncated to the first {maxExclusions} used lemmas)"}
        </div>]
    else #[]
  return <details>
    <summary><b>Exclusion previews</b> {.text s!"({report.outcomes.size})"}</summary>
    <div>{...rows}{...note}</div>
  </details>

/-- Render the diagnostics sidebar (tried vs. used counts). Empty unless the
run was executed with `set_option diagnostics true`. -/
def diagnosticsHtml (diag : Simp.Diagnostics) : MetaM Html := do
  let entries := diag.triedThmCounter.toList
  if entries.isEmpty then
    return <span />
  let rows ← entries.toArray.mapM fun (o, tried) => do
    let used := diag.usedThmCounter.find? o |>.getD 0
    let name ← originBadgeText o
    return <li>{badge name}{.text s!"tried {tried}, used {used}"}</li>
  return <details>
    <summary><b>Diagnostics</b> {.text s!"({entries.length} lemmas tried)"}</summary>
    <ul style={json% {margin: "2px 0"}}>{...rows}</ul>
  </details>

/-- The note shown for a location whose film is empty: an honest
"definitional reductions only" explanation when the location did change
(beta/zeta/eta/proj steps have no lemma origin the tracer could record), the
generic no-steps note otherwise. -/
def emptyFilmNote (changed : Bool) : String :=
  if changed then
    "No lemma-driven rewrites — the change was purely definitional (beta/zeta/eta/proj reductions, which have no lemma origin to record)."
  else
    "No rewrite steps were recorded."

/-- Cap on the number of frames *rendered* per filmstrip section. Interactive
expression rendering (delaboration) of a huge film can cost more heartbeats
than the traced run itself (measured on a ~900-frame `List.range` goal), so
the tail is summarized in a note instead. The trace data itself is complete —
only the HTML is truncated. -/
def maxRenderedFrames : Nat := 100

/-- The frames of one film as a block (or a "no steps" note; `changed` selects
the honest note when the location changed by definitional reductions only).
Renders at most `maxRenderedFrames` frames, summarizing the rest in a note. -/
def framesBlockHtml (film : Film) (changed : Bool) : MetaM Html := do
  let shown := film.frames.take maxRenderedFrames
  let frames ← shown.mapM frameHtml
  if frames.isEmpty then
    return <div style={json% {opacity: "0.7"}}>{.text (emptyFilmNote changed)}</div>
  else
    let hidden := film.frames.size - shown.size
    let note : Array Html :=
      if hidden > 0 then
        #[<div style={json% {opacity: "0.6", fontSize: "0.85em"}}>
            {.text s!"(+{hidden} more rewrite{if hidden == 1 then "" else "s"} not rendered — filmstrip capped at {maxRenderedFrames} frames)"}
          </div>]
      else #[]
    return <div>{...frames}{...note}</div>

/-- Render one filmstrip section of a multi-location run: an `at <loc>`
header, then the location's frames in the standard frame design. -/
def locFilmHtml (lf : LocFilm) : MetaM Html := do
  let closed : Array Html :=
    if lf.closedGoal then
      #[<span style={json% {color: "var(--vscode-testing-iconPassed, #73c991)"}}>
          {.text " ✓ closes the goal"}
        </span>]
    else #[]
  let countLabel :=
    if lf.definitionalOnly then " — definitional reductions only"
    else s!" — {lf.film.length} rewrite{if lf.film.length == 1 then "" else "s"}"
  return <div style={json% {marginBottom: "6px"}}>
    <div style={json% {marginBottom: "2px"}}>
      <b>{.text s!"at {lf.loc.label}"}</b>
      <span style={json% {opacity: "0.6", fontSize: "0.85em"}}>
        {.text countLabel}
      </span>
      {...closed}
    </div>
    <div style={json% {paddingLeft: "8px"}}>{← framesBlockHtml lf.film lf.changed}</div>
  </div>

/-- Render the full Simp Lens panel for a traced multi-location run: one
filmstrip section per location (a single target-only section keeps the
original sectionless layout). -/
def renderPanelAt (films : Array LocFilm) (suggestion : String) (report : ExclusionReport)
    (diag : Simp.Diagnostics) (closedGoal : Bool) : MetaM Html := do
  let totalRewrites := films.foldl (· + ·.film.length) 0
  let filmsBlock : Html ←
    if h : films.size = 1 then
      if films[0].loc == .target then
        -- target-only: the original, sectionless layout
        framesBlockHtml films[0].film films[0].changed
      else
        -- NB `pure`, not `return`: a do-notation `return` here would exit the
        -- whole function, silently dropping the header, minimal-call row,
        -- exclusion previews and diagnostics from every location panel (a
        -- real bug caught by browser-side React verification of the output).
        pure <div>{...(← films.mapM locFilmHtml)}</div>
    else
      pure <div>{...(← films.mapM locFilmHtml)}</div>
  let outcome : Html :=
    if closedGoal then
      <span style={json% {color: "var(--vscode-testing-iconPassed, #73c991)"}}>
        {.text " ✓ goal closed"}
      </span>
    else
      <span />
  -- never claim "0 rewrites" as the whole story when a location did change:
  -- simp also makes progress via origin-less definitional reductions
  let headerCount :=
    if totalRewrites == 0 && films.any (·.changed) then
      " — 0 rewrites (definitional reductions only)"
    else
      s!" — {totalRewrites} rewrite{if totalRewrites == 1 then "" else "s"}"
  return <details «open»={true}>
    <summary>
      <b>Simp Lens</b>
      {.text headerCount}
      {outcome}
    </summary>
    <div style={json% {padding: "4px"}}>
      <div style={json% {marginBottom: "6px"}}>
        <b>minimal call: </b>
        <code>{.text suggestion}</code>
      </div>
      {filmsBlock}
      {← exclusionsHtml report}
      {← diagnosticsHtml diag}
    </div>
  </details>

/-- Degraded panel used when interactive filmstrip rendering itself blows the
heartbeat budget (a single frame can hold an arbitrarily large expression):
header, minimal call, exclusion previews and diagnostics — everything except
the interactive frames, which are replaced by an honest note. Contains no
expression rendering, so it cannot blow up in turn. -/
def renderPanelFallback (totalRewrites : Nat) (suggestion : String)
    (report : ExclusionReport) (diag : Simp.Diagnostics) (closedGoal : Bool) :
    MetaM Html := do
  let outcome : Html :=
    if closedGoal then
      <span style={json% {color: "var(--vscode-testing-iconPassed, #73c991)"}}>
        {.text " ✓ goal closed"}
      </span>
    else
      <span />
  return <details «open»={true}>
    <summary>
      <b>Simp Lens</b>
      {.text s!" — {totalRewrites} rewrite{if totalRewrites == 1 then "" else "s"}"}
      {outcome}
    </summary>
    <div style={json% {padding: "4px"}}>
      <div style={json% {marginBottom: "6px"}}>
        <b>minimal call: </b>
        <code>{.text suggestion}</code>
      </div>
      <div style={json% {opacity: "0.7"}}>
        {.text "Filmstrip omitted — rendering the rewritten subterms exceeded the command's heartbeat budget."}
      </div>
      {← exclusionsHtml report}
      {← diagnosticsHtml diag}
    </div>
  </details>

/-- Render the full Simp Lens panel for a target-only traced run. `changed`
is whether the target changed (a closed goal counts as changed). -/
def renderPanel (film : Film) (suggestion : String) (report : ExclusionReport)
    (diag : Simp.Diagnostics) (closedGoal : Bool) (changed : Bool := true) : MetaM Html :=
  renderPanelAt #[{ loc := .target, film, closedGoal, changed }] suggestion report diag closedGoal

end SimpLens
