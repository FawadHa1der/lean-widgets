import DistLens
import DistLensTests.Helpers

/-!
# Showcase probe: dist-lens

Dumps the exact top-level panel `Html` the `#dist` / `#dist_film` / `#chain`
commands attach: real `extractDist` / `extractBindFilm` / `extractChain` runs
over the demo distributions (re-defined here at the root namespace so
suggestion texts read `unfold die` exactly as in a user file), with the same
suggestion/filmstrip assembly the command elaborators perform, plus the
`badModel` warnings panel and the non-unique identity chain from the test
fixtures — serialized to `../showcase/dumps/dist-lens.json` for the showcase
site's React verification harness.  Extraction runs in `TermElabM` inside
`#eval`.

Run from the package directory (exactly how `showcase/build.sh` invokes it):

    cd widgets/dist-lens && lake env lean "../showcase/probes/dist-lens.lean"

MUST stay in sync with the package's React-contract tests
(`DistLensTests/ContractTests.lean`): the entries dumped here are the
`renderDistPanel`/`renderFilmPanel`/`renderChainPanel` outputs those tests
run `reactContractViolations` over — if a panel is added there, add its dump
here.
-/

open Lean Meta Elab Term ProofWidgets DistLens DistLensTests PMF
open scoped ENNReal NNReal

-- `PMF.bernoulli`/`PMF.binomial` are deprecated at this Mathlib pin but fully
-- functional — same opt-out as `DistLens/Demo.lean`.
set_option linter.deprecated false

/-- A fair six-sided die (`DistLens.Demo.die`, re-rooted for short names). -/
noncomputable def die : PMF (Fin 6) := uniformOfFintype (Fin 6)

/-- Sum of two independent fair-die indices (`DistLens.Demo.twoDice`). -/
noncomputable def twoDice : PMF ℕ :=
  die.bind fun a => die.map fun b => a.val + b.val

/-- A biased coin: `P(true) = 2/3` (`DistLens.Demo.biasedCoin`). -/
noncomputable def biasedCoin : PMF Bool :=
  bernoulli (2/3) (by norm_num [div_le_one])

/-- The 2-state weather chain (`DistLens.Demo.weather`). -/
noncomputable def weather : Fin 2 → PMF (Fin 2) :=
  ![PMF.ofFintype ![3/4, 1/4] (by simp [Fin.sum_univ_succ]; ennreal_num),
    PMF.ofFintype ![1/2, 1/2] (by simp [Fin.sum_univ_succ]; ennreal_num)]

/-- The lazy triangle walk (`DistLens.Demo.triangle`). -/
noncomputable def triangle : Fin 3 → PMF (Fin 3) :=
  ![PMF.ofFintype ![1/2, 1/3, 1/6] (by simp [Fin.sum_univ_succ]; ennreal_num),
    PMF.ofFintype ![1/6, 1/2, 1/3] (by simp [Fin.sum_univ_succ]; ennreal_num),
    PMF.ofFintype ![1/3, 1/6, 1/2] (by simp [Fin.sum_univ_succ]; ennreal_num)]

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

/-- Real `#dist` pipeline to the static panel: extraction, unfold-tactic
discovery, weight suggestions, render (the link-free `renderDistPanel` body
the RPC panel also renders). -/
private def distEntry (name srcTxt : String) (t : Syntax.Term) : TermElabM Json := do
  let e ← elabDistTerm t
  checkIsPMF "#dist" e
  let d ← extractDist "#dist" e
  let tac := unfoldTactic (← collectUnfoldNames e)
  pure (probeEntry name (renderDistPanel d.toModel (weightSuggestions srcTxt tac d)))

/-- Real `#chain` pipeline to the static panel, with the command's own
power-iteration filmstrip assembly for the given `init [i]` / `steps k`
clauses. -/
private def chainEntry (name srcTxt : String) (t : Syntax.Term)
    (init? : Option Nat := none) (steps? : Option Nat := none) : TermElabM Json := do
  let e ← elabDistTerm t
  let c ← extractChain "#chain" e
  let tac := unfoldTactic (← collectUnfoldNames e)
  let film : FilmModel :=
    if init?.isSome || steps?.isSome then
      let π₀ := match init? with
        | some i => c.pointMass i
        | none => c.uniformInit
      let k := steps?.getD 4
      let frames := c.powerFrames π₀ k
      let toDist (w : Array Rat) : DistModel :=
        { carrier := s!"Fin {c.n}"
          labels := (Array.range c.n).map toString
          weights := w }
      ⟨(Array.range frames.size).map fun i => (s!"step {i}", toDist frames[i]!)⟩
    else ⟨#[]⟩
  let suggestions := match c.stationary with
    | .unique π => stationarySuggestions srcTxt tac π
    | _ => #[]
  pure (probeEntry name (renderChainPanel c film suggestions))

#eval show TermElabM Unit from do
  let mut entries : Array Json := #[]
  -- `#dist` panels: bar chart + CDF + moments + verified weight goals.
  entries := entries.push (← distEntry "die6_dist_panel" "die" (← `(die)))
  entries := entries.push
    (← distEntry "two_dice_bind_result_panel" "twoDice" (← `(twoDice)))
  entries := entries.push
    (← distEntry "bernoulli_coin_panel" "biasedCoin" (← `(biasedCoin)))
  -- `#chain` panels: transition graph + stationary π + power filmstrips
  -- (`init [0] steps 4`, matching the demo commands).
  entries := entries.push (← chainEntry "weather_chain_panel" "weather"
    (← `(weather)) (init? := some 0) (steps? := some 4))
  entries := entries.push (← chainEntry "triangle_chain_power_panel" "triangle"
    (← `(triangle)) (init? := some 0) (steps? := some 4))
  -- A reducible chain: reported as non-unique, no suggestions (pure fixture —
  -- identical to extracting `fun i => PMF.pure i`).
  entries := entries.push
    (probeEntry "identity_chain_nonunique_panel" (renderChainPanel identityM))
  -- `#dist_film`: the bind filmstrip of the two-dice showpiece.
  let e ← elabDistTerm (← `(twoDice))
  checkIsPMF "#dist_film" e
  let film ← extractBindFilm "#dist_film" e
  entries := entries.push
    (probeEntry "two_dice_bind_filmstrip" (renderFilmPanel (filmOfBind film)))
  -- A violating model still renders (warnings shown) — the test fixture.
  entries := entries.push
    (probeEntry "bad_model_warnings_panel" (renderDistPanel badModel))
  IO.FS.writeFile "../showcase/dumps/dist-lens.json"
    (probeDump "dist-lens" entries).pretty
