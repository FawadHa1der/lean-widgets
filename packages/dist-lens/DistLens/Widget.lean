import DistLens.Extract
import DistLens.Render
import DistLens.Verify
import ProofWidgets.Component.HtmlDisplay
import ProofWidgets.Component.OfRpcMethod
import ProofWidgets.Component.MakeEditLink

/-! # DistLens: the `#dist`, `#dist_film` and `#chain` commands

```
#dist p                     -- bar chart + CDF + moments + verified-goal links
#dist (text := true) p      -- deterministic ASCII report (pinned by tests)
#dist_film p                -- bind filmstrip: source, branches, result
#dist_film (text := true) p
#chain step                 -- transition graph + stationary π + goal links
#chain (text := true) step
#chain step init [i] steps k    -- power-iteration filmstrip from state i
#chain step steps k             -- … from the uniform distribution
```

`#dist p` extracts the finite, rational-parameter distribution `p : PMF α`
(whitelisted constructors only — see `DistLens/Extract.lean` for the exact
contract and refusals), computes its exact ℚ weights Lean-side, and renders
bars, CDF, expectation/variance and one **verified weight goal** per support
outcome: an `example : p x = w := by pmf_num` line that inserts into the
file via a MakeEditLink click (and compiles — the test suite proves the
recipe on every demo distribution).  Opaque `Fintype` carriers (anything
beyond `Fin`/`Bool`/`ℕ`) are display-only: no goal rows, because the
inserted example provably would not compile (see `weightSuggestions`).

`#chain step` extracts `step : Fin n → PMF (Fin n)` into an exact ℚ
stochastic matrix, draws the transition graph, solves `π P = π`, `Σ π = 1`
by exact Gaussian elimination (reporting non-uniqueness honestly), and
offers per-state stationary equations as insertable `pmf_num` examples.

The term parses at `term:max` precedence, so applications need parentheses:
`#dist (uniformOfFintype (Fin 6))`.

## How the links get document context

`MakeEditLink` needs a `Lsp.TextDocumentEdit` naming the file's uri and
version — data only the language *server* has (a command elaborates against
source text; the LSP document version is not part of the elaboration
context, and a hand-built versionless edit would silently apply at stale
offsets after any keystroke).  So the commands follow the proven RPC-panel
pattern (cf. hasse-view / graph-scope / interval-inspector): they store
plain-data props (the pure model, the verified suggestion texts, and the
zero-width insertion range at the command's end) via `savePanelWidgetInfo`,
and the `DistPanel.rpc` / `ChainPanel.rpc` methods — running in `RequestM`
at render time, where `RequestM.readDoc` provides the authoritative
`DocumentMeta` — wrap the stored texts in `MakeEditLink` components whose
edits are stamped with the *current* uri and version (a stale click is then
rejected by the editor instead of corrupting the file).  All verification
already happened at command time; the RPC layer only adds document
plumbing, and the panel bodies are the pure `renderDistPanel` /
`renderChainPanel`, directly callable by tests.
-/

namespace DistLens

open Lean Meta Server Elab Command ProofWidgets

/-- Cap on the number of suggestion rows a panel displays. -/
def maxSuggestions : Nat := 12

/-- Cap on `#chain … steps k`. -/
def maxPowerSteps : Nat := 16

/-! ## Suggestion text -/

/-- Is `s` (at the character level) a single outer `(…)` group — first char
`(`, last char `)`, and the depth never returns to 0 strictly inside?  Then
wrapping it in another pair of parentheses would be redundant.  Parentheses
inside string literals can only bias this check toward `false` (extra
wrapping, which is always safe), never toward a wrong `true`. -/
def isParenWrapped (s : String) : Bool := Id.run do
  let cs := s.toList.toArray
  if cs.size < 2 || cs[0]! != '(' || cs[cs.size - 1]! != ')' then
    return false
  let mut depth := 0
  for i in [0:cs.size] do
    let c := cs[i]!
    if c == '(' then
      depth := depth + 1
    else if c == ')' then
      if depth == 0 then return false
      depth := depth - 1
      if depth == 0 && i != cs.size - 1 then return false
  return depth == 0

/-- The source text of the user's term: the original source substring
*without leading/trailing trivia* when available (exactly as typed — but
never a trailing comment, which `Syntax.reprint` would include and which
would comment out the rest of an inserted example!), then reprinted syntax,
then a pretty-printed fallback; parenthesized (unless it is a single token
or already a single `(…)` group) so it can be applied. -/
def termText (t : Syntax) (fallback : String) : String :=
  let s := ((t.getSubstring? (withLeading := false) (withTrailing := false)).map
      (·.toString)).getD
    ((t.reprint.map (·.trimAscii.toString)).getD fallback)
  if s.any (· == ' ') && !isParenWrapped s then s!"({s})" else s

/-- The outcome literal inserted into a goal for key `k` (`Bool` keys become
`false`/`true`, `Fin`/`ℕ` keys a numeral).  Opaque carriers never reach this
function — their suggestion rows are suppressed (see `weightSuggestions`). -/
def keyLit (c : Carrier) (k : Nat) : String :=
  match c with
  | .bool => if k == 0 then "false" else "true"
  | _ => toString k

/-- The verified-weight-goal suggestions for a distribution: one
`example : p x = w := by <tac>` per *support* outcome, capped at
`maxSuggestions`.  `tac` is `pmf_num`, prefixed with the `unfold` of any
user definitions the goal needs (see `unfoldTactic`).

Opaque carriers get **no** rows: their outcome labels are `Repr` output (or
bare indices when no computable `Repr` exists) — display strings, not
verified source terms — and `pmf_num` cannot reduce `Fintype.card` of an
arbitrary carrier, so the inserted example would not compile (probed:
`uniformOfFintype Ordering` leaves `↑(Fintype.card Ordering) = 3` open;
pinned by ClickE2E).  Same standard as the subtype-mk refusal: no clickable
action whose advertised proof breaks. -/
def weightSuggestions (srcTxt tac : String) (d : XDist) : Array String := Id.run do
  if let .opaqueTy _ := d.carrier then return #[]
  let mut out : Array String := #[]
  for i in [0:d.keys.size] do
    if d.weights[i]! > 0 && out.size < maxSuggestions then
      let x := keyLit d.carrier d.keys[i]!
      out := out.push
        s!"example : {srcTxt} {x} = {ratStr d.weights[i]!} := by {tac}"
  return out

/-- The inline `PMF.ofFintype ![…]` spelling of a stationary vector, with
its sum-to-1 side goal discharged by the shipped tactics. -/
def stationaryPmfText (π : Array Rat) : String :=
  let entries := ", ".intercalate (π.toList.map ratStr)
  s!"PMF.ofFintype ![{entries}] (by simp [Fin.sum_univ_succ]; ennreal_num)"

/-- The stationary-equation suggestions for a chain with unique `π`: one
`example : ((π_pmf).bind step) y = π_y := by <tac>` per state. -/
def stationarySuggestions (srcTxt tac : String) (π : Array Rat) : Array String :=
  (Array.range π.size).map fun y =>
    s!"example : (({stationaryPmfText π}).bind {srcTxt}) {y} = \
      {ratStr π[y]!} := by {tac}"

/-- Collect the user-defined `PMF`-valued constants a goal about `e` would
need to `unfold` before `pmf_num` can see the whitelisted constructors:
starting from `e`'s constants, every definition outside the extraction
whitelist whose (telescoped) result type is `PMF`-headed is collected, and
its *own* definition body is scanned too (so `twoDice` pulls in `die`).
Discovery order = head first, then dependencies — the order `unfold`
needs. -/
def collectUnfoldNames (e : Expr) : MetaM (Array Name) := do
  let env ← getEnv
  let mut out : Array Name := #[]
  let mut queue : Array Name := e.getUsedConstants
  let mut seen : Array Name := #[]
  let mut fuel := 64
  while queue.size > 0 do
    if fuel == 0 then break
    fuel := fuel - 1
    let c := queue.back!
    queue := queue.pop
    if seen.contains c then continue
    seen := seen.push c
    if whitelistHeads.contains c then continue
    let some info := env.find? c | continue
    let some val := info.value? | continue
    let isPMFValued ← forallTelescope info.type fun _ body => do
      match ← whnfUntil body ``PMF with
      | some b => pure (b.isAppOfArity ``PMF 1)
      | none => pure false
    unless isPMFValued do continue
    out := out.push c
    queue := queue ++ val.getUsedConstants
  return out

/-- The suggestion tactic text: plain `pmf_num`, or
`unfold a b; pmf_num` when the goal mentions user `PMF` definitions. -/
def unfoldTactic (names : Array Name) : String :=
  if names.isEmpty then "pmf_num"
  else "unfold " ++ " ".intercalate (names.toList.map toString) ++ "; pmf_num"

/-! ## Panel props and the RPC render layer -/

/-- JSON encoding of an exact rational, `{num, den}` — needed to ship the
pure models through `RpcEncodable` panel props. -/
scoped instance : ToJson Rat :=
  ⟨fun q => Json.mkObj [("num", toJson q.num), ("den", toJson q.den)]⟩

/-- Inverse of the `{num, den}` encoding (normalizing via `mkRat`). -/
scoped instance : FromJson Rat := ⟨fun j => do
  let num : Int ← j.getObjValAs? Int "num"
  let den : Nat ← j.getObjValAs? Nat "den"
  return mkRat num den⟩

deriving instance ToJson, FromJson for DistModel
deriving instance ToJson, FromJson for FilmModel
deriving instance ToJson, FromJson for ChainModel

/-- Props of the interactive `#dist` panel: everything the render needs, as
plain data.  Stored by the command via `savePanelWidgetInfo`; the document
context (uri/version) is added at render time by `DistPanel.rpc`. -/
structure DistPanelProps where
  /-- Zero-width range at the end of the `#dist` command — the insertion
  point (every `newText` starts with `"\n"`, so nothing the user wrote is
  ever replaced). -/
  insertRange : Lsp.Range
  /-- The extracted distribution, as a pure model. -/
  model : DistModel
  /-- The verified-weight-goal suggestion texts. -/
  suggestions : Array String := #[]
  deriving ToJson, FromJson, Server.RpcEncodable

/-- Props of the interactive `#chain` panel (see `DistPanelProps`). -/
structure ChainPanelProps where
  /-- Zero-width insertion point at the end of the `#chain` command. -/
  insertRange : Lsp.Range
  /-- The extracted chain, as a pure model. -/
  chain : ChainModel
  /-- The optional power-iteration filmstrip. -/
  film : FilmModel := ⟨#[]⟩
  /-- The stationary-equation suggestion texts (unique-π chains only). -/
  suggestions : Array String := #[]
  deriving ToJson, FromJson, Server.RpcEncodable

/-- The exact `MakeEditLink` props a suggestion click uses: insert `text` on
a fresh line at the zero-width `insertRange`, stamped with the document's
current uri *and version* (so a stale click is rejected by the editor, not
applied at drifted offsets).  Single source of truth — the RPC render layer
and the ClickE2E tests both go through this function. -/
def suggestionEditProps (doc : Server.DocumentMeta) (insertRange : Lsp.Range)
    (text : String) : MakeEditLinkProps :=
  { MakeEditLinkProps.ofReplaceRange doc insertRange ("\n" ++ text) with
    title? := some "insert this example" }

/-- The insert-on-click suggestion row: a `MakeEditLink` wrapping
`suggestionEditProps`. -/
def editLink (doc : Server.DocumentMeta) (insertRange : Lsp.Range)
    (text : String) : Html :=
  .ofComponent MakeEditLink (suggestionEditProps doc insertRange text)
    #[.text text]

/-- RPC method behind the interactive `#dist` panel: reads the
authoritative document metadata and renders the pure panel body with
clickable `MakeEditLink`s for the verified suggestions. -/
@[server_rpc_method]
def DistPanel.rpc (props : DistPanelProps) : RequestM (RequestTask Html) :=
  RequestM.asTask do
    let doc ← RequestM.readDoc
    return renderDistPanel props.model props.suggestions
      (editLink doc.meta props.insertRange)

/-- The interactive `#dist` panel component. -/
@[widget_module]
def DistPanel : Component DistPanelProps :=
  mk_rpc_widget% DistPanel.rpc

/-- RPC method behind the interactive `#chain` panel. -/
@[server_rpc_method]
def ChainPanel.rpc (props : ChainPanelProps) : RequestM (RequestTask Html) :=
  RequestM.asTask do
    let doc ← RequestM.readDoc
    return renderChainPanel props.chain props.film props.suggestions
      (editLink doc.meta props.insertRange)

/-- The interactive `#chain` panel component. -/
@[widget_module]
def ChainPanel : Component ChainPanelProps :=
  mk_rpc_widget% ChainPanel.rpc

/-! ## Command plumbing -/

/-- Debug option name (deliberately unregistered — set it programmatically,
e.g. by the ClickE2E harness driving the frontend in-process): when true,
the panel commands log their stored props as
`distLens.panelProps: <json>` info lines, exposing the exact insertion
payloads for end-to-end testing. -/
def logPropsOptName : Name := `distLens.debug.logPanelProps

/-- The marker prefixing every props debug log line. -/
def panelPropsMarker : String := "distLens.panelProps: "

/-- Log `props` behind `logPropsOptName` (see there). -/
def logPanelProps {α : Type} [ToJson α] (props : α) : CommandElabM Unit := do
  if (← getOptions).getBool logPropsOptName then
    logInfo s!"{panelPropsMarker}{(toJson props).compress}"

/-- Elaborate the command's term argument. -/
def elabDistTerm (t : Syntax.Term) : TermElabM Expr := do
  let e ← Term.elabTerm t none
  Term.synthesizeSyntheticMVarsNoPostponing
  instantiateMVars e

/-- Check that `e : PMF α` (up to reducing the type *until* the `PMF` head —
`whnf` alone would unfold the `PMF` def itself), with a `cmd`-branded error
otherwise. -/
def checkIsPMF (cmd : String) (e : Expr) : MetaM Unit := do
  let ty ← inferType e
  let ok ← do
    match ← whnfUntil ty ``PMF with
    | some ty' => pure (ty'.isAppOfArity ``PMF 1)
    | none => pure false
  unless ok do
    throwError "{cmd}: expected a term of type `PMF α`, but \
      `{← ppOneLine e}` has type `{← ppOneLine ty}`"

/-- Attach an HTML panel to the command syntax. -/
def savePanel (stx : Syntax) (ht : Html) : CommandElabM Unit := do
  liftCoreM <| Widget.savePanelWidgetInfo
    (hash HtmlDisplayPanel.javascript)
    (return json% { html: $(← rpcEncode ht) })
    stx

/-! ## `#dist` -/

/-- `#dist p` renders the finite, rational-parameter distribution `p : PMF α`
in the InfoView: exact-ℚ bar chart, CDF staircase, expectation/variance, and
one insertable verified weight goal (`example : p x = w := by pmf_num`) per
support outcome (`Fin`/`Bool`/`ℕ` carriers; opaque `Fintype` carriers are
display-only).  `#dist (text := true) p` logs a deterministic ASCII report
instead.  Whitelisted constructors only; everything else is refused with an
honest error (see `DistLens/Extract.lean`). -/
syntax (name := distCmd)
  "#dist" (atomic("(" &"text" " := " &"true" ")"))? term:max : command

open Command in
@[command_elab distCmd]
def elabDistCmd : CommandElab := fun stx => do
  match stx with
  | `(#dist $t:term) => go stx t false
  | `(#dist (text := true) $t:term) => go stx t true
  | _ => throwUnsupportedSyntax
where
  go (stx : Syntax) (t : Syntax.Term) (textMode : Bool) : CommandElabM Unit := do
    let (d, srcTxt, tac) ← liftTermElabM do
      let e ← elabDistTerm t
      checkIsPMF "#dist" e
      let d ← extractDist "#dist" e
      pure (d, termText t (← ppOneLine e), unfoldTactic (← collectUnfoldNames e))
    if textMode then
      logInfo (Render.textReport d.toModel)
    else
      let suggestions := weightSuggestions srcTxt tac d
      match (← getFileMap).lspRangeOfStx? stx with
      | some cmdRange =>
        let props : DistPanelProps :=
          { insertRange := ⟨cmdRange.end, cmdRange.end⟩
            model := d.toModel, suggestions }
        logPanelProps props
        liftCoreM <| Widget.savePanelWidgetInfo
          (hash DistPanel.javascript) (rpcEncode props) stx
      | none =>
        -- Synthetic syntax without positions (e.g. macro-generated): fall
        -- back to the link-free static panel rather than dropping it.
        savePanel stx (renderDistPanel d.toModel suggestions)

/-! ## `#dist_film` -/

/-- `#dist_film p` renders a `PMF.bind` term as a filmstrip: the source
distribution, one frame per source outcome (the conditional distribution it
binds to, captioned with its mixing weight), and the convolved result with
diff badges on outcomes that are new or changed vs the source.
`#dist_film (text := true) p` logs the deterministic ASCII filmstrip.
Terms that do not resolve to `PMF.bind` are refused honestly. -/
syntax (name := distFilmCmd)
  "#dist_film" (atomic("(" &"text" " := " &"true" ")"))? term:max : command

/-- Build the pure filmstrip from an extracted bind. -/
def filmOfBind (film : BindFilm) : FilmModel := Id.run do
  let mut frames : Array (String × DistModel) :=
    #[("source", film.source.toModel)]
  for i in [0:film.branches.size] do
    let (label, branch) := film.branches[i]!
    let w := match film.source.labels.findIdx? (· == label) with
      | some j => film.source.weights[j]!
      | none => 0
    frames := frames.push
      (s!"branch {label} (weight {ratStr w})", branch.toModel)
  frames := frames.push ("result", film.result.toModel)
  return ⟨frames⟩

open Command in
@[command_elab distFilmCmd]
def elabDistFilmCmd : CommandElab := fun stx => do
  match stx with
  | `(#dist_film $t:term) => go stx t false
  | `(#dist_film (text := true) $t:term) => go stx t true
  | _ => throwUnsupportedSyntax
where
  go (stx : Syntax) (t : Syntax.Term) (textMode : Bool) : CommandElabM Unit := do
    let film ← liftTermElabM do
      let e ← elabDistTerm t
      checkIsPMF "#dist_film" e
      extractBindFilm "#dist_film" e
    let fm := filmOfBind film
    if textMode then
      logInfo (Render.filmTextReport fm)
    else
      savePanel stx (renderFilmPanel fm)

/-! ## `#chain` -/

/-- Power-iteration clause: `init [i]` (point mass at state `i`; default is
the uniform distribution). -/
syntax chainInitClause := &"init" "[" num "]"

/-- Power-iteration clause: `steps k` (number of exact power steps). -/
syntax chainStepsClause := &"steps" num

/-- Any `#chain` clause. -/
syntax chainClause := chainInitClause <|> chainStepsClause

/-- `#chain step` renders `step : Fin n → PMF (Fin n)` in the InfoView:
circular transition graph with exact edge probabilities, the stationary
distribution `π P = π, Σ π = 1` solved exactly (unique π drawn as bars with
insertable per-state verification examples; reducible chains reported as
non-unique, never silently resolved), plus an optional exact power-iteration
filmstrip via `init [i]` / `steps k` clauses.  `(text := true)` logs the
deterministic ASCII report. -/
syntax (name := chainCmd)
  "#chain" (atomic("(" &"text" " := " &"true" ")"))? term:max
    (chainClause)* : command

open Command in
@[command_elab chainCmd]
def elabChainCmd : CommandElab := fun stx => do
  match stx with
  | `(#chain $t:term $cs:chainClause*) => go stx t false cs
  | `(#chain (text := true) $t:term $cs:chainClause*) => go stx t true cs
  | _ => throwUnsupportedSyntax
where
  go (stx : Syntax) (t : Syntax.Term) (textMode : Bool)
      (cs : Array (TSyntax ``chainClause)) : CommandElabM Unit := do
    let mut init? : Option Nat := none
    let mut steps? : Option Nat := none
    for c in cs do
      match c with
      | `(chainClause| init [$i:num]) =>
        if init?.isSome then
          throwErrorAt c "#chain: duplicate `init` clause"
        init? := some i.getNat
      | `(chainClause| steps $k:num) =>
        if steps?.isSome then
          throwErrorAt c "#chain: duplicate `steps` clause"
        steps? := some k.getNat
      | _ => throwUnsupportedSyntax
    let (c, srcTxt, tac) ← liftTermElabM do
      let e ← elabDistTerm t
      let c ← extractChain "#chain" e
      pure (c, termText t (← ppOneLine e), unfoldTactic (← collectUnfoldNames e))
    if let some i := init? then
      if i ≥ c.n then
        throwError "#chain: initial state {i} is out of range for {c.n} states"
    if let some k := steps? then
      if k > maxPowerSteps then
        throwError "#chain: {k} steps exceed the limit of {maxPowerSteps}"
    let film : FilmModel ←
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
        pure ⟨(Array.range frames.size).map fun i =>
          (s!"step {i}", toDist frames[i]!)⟩
      else
        pure ⟨#[]⟩
    if textMode then
      logInfo (Render.chainTextReport c (film.frames.map (·.2.weights)))
    else
      let suggestions := match c.stationary with
        | .unique π => stationarySuggestions srcTxt tac π
        | _ => #[]
      match (← getFileMap).lspRangeOfStx? stx with
      | some cmdRange =>
        let props : ChainPanelProps :=
          { insertRange := ⟨cmdRange.end, cmdRange.end⟩
            chain := c, film, suggestions }
        logPanelProps props
        liftCoreM <| Widget.savePanelWidgetInfo
          (hash ChainPanel.javascript) (rpcEncode props) stx
      | none =>
        savePanel stx (renderChainPanel c film suggestions)

end DistLens
