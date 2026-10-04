import Lean

/-! # Expr X-Ray: core data types

Pure data types shared by the analyzer, diff engine and renderer:
`XKind` (syntactic node kinds), `BinderRole` (how an application argument
is bound), `XRayConfig` and the `XNode` analysis tree itself.
Everything in this file is pure so it can be tested with `#guard`.
-/

namespace ExprXRay

/-- The syntactic kind of a `Lean.Expr` node, mirroring the `Expr` constructors. -/
inductive XKind where
  | const | app | lam | forallE | letE | fvar | mvar | sort | lit | proj | mdata | bvar
  deriving Repr, BEq, Inhabited, DecidableEq

/-- Short lowercase name of an `XKind`, used in text renderings. -/
def XKind.name : XKind → String
  | .const   => "const"
  | .app     => "app"
  | .lam     => "lam"
  | .forallE => "forallE"
  | .letE    => "letE"
  | .fvar    => "fvar"
  | .mvar    => "mvar"
  | .sort    => "sort"
  | .lit     => "lit"
  | .proj    => "proj"
  | .mdata   => "mdata"
  | .bvar    => "bvar"

/-- The role a node plays as an argument of its parent application.
`none` means the node is not an application argument (e.g. the root,
an application head, or a binder domain/body). -/
inductive BinderRole where
  | none | explicit | implicit | strictImplicit | instImplicit
  deriving Repr, BEq, Inhabited, DecidableEq

/-- Short tag for a `BinderRole`, used in text renderings. Empty for
`none`/`explicit` since those are the "default look" roles. -/
def BinderRole.tag : BinderRole → String
  | .none           => ""
  | .explicit       => ""
  | .implicit       => "{imp}"
  | .strictImplicit => "{strimp}"
  | .instImplicit   => "[inst]"

/-- `true` for the roles that default pretty-printing hides (implicit,
strict-implicit and instance-implicit arguments). -/
def BinderRole.isHidden : BinderRole → Bool
  | .implicit | .strictImplicit | .instImplicit => true
  | _ => false

/-- Convert a `Lean.BinderInfo` (of a function parameter) into the
`BinderRole` of the corresponding argument. -/
def roleOfBinderInfo : Lean.BinderInfo → BinderRole
  | .default        => .explicit
  | .implicit       => .implicit
  | .strictImplicit => .strictImplicit
  | .instImplicit   => .instImplicit

/-- Configuration for the analyzer. -/
structure XRayConfig where
  /-- Maximum tree depth; branches deeper than this are cut and flagged `elided`. -/
  maxDepth : Nat := 32
  /-- Maximum length (in characters) of the per-node pretty strings. -/
  ppMaxLength : Nat := 60
  deriving Repr, Inhabited

/-- Collapse newlines to spaces and truncate `s` to at most `limit`
characters, appending `…` when something was cut off. -/
def truncatePP (s : String) (limit : Nat := 60) : String :=
  let s := s.replace "\n" " "
  if s.length ≤ limit then s else (s.take limit).toString ++ "…"

/-- Index of the first character at which `a` and `b` differ — the length
of their longest common prefix (`min a.length b.length` when one is a
prefix of the other). -/
def firstDiffIdx (a b : String) : Nat :=
  go a.toList b.toList 0
where
  /-- Walk both character lists in lockstep, counting matching characters. -/
  go : List Char → List Char → Nat → Nat
    | x :: xs, y :: ys, i => if x == y then go xs ys (i + 1) else i
    | _, _, i => i

/-- Truncate the two sides of a mismatch for display (newlines collapsed
as in `truncatePP`). Left-anchored truncation is used when it keeps the
two sides distinguishable; when the two left-anchored truncations would
coincide even though the strings differ (a long common prefix), the
window is instead anchored shortly before the first differing character,
with `…` marking text cut on either side — so the printed pair always
shows a visible difference. Fully identical inputs (distinct expressions
whose pretty strings coincide) are truncated left-anchored. -/
def truncatePPPair (a b : String) (limit : Nat := 60) : String × String :=
  let a := a.replace "\n" " "
  let b := b.replace "\n" " "
  let ta := truncatePP a limit
  let tb := truncatePP b limit
  if ta != tb || a == b then (ta, tb)
  else
    -- keep a little context before the first differing character, but
    -- never so much that the difference falls outside the window
    let d := firstDiffIdx a b
    let start := d - min d (min 15 (limit / 4))
    (window a start limit, window b start limit)
where
  /-- Up to `limit` characters of `s` starting at character `start`, with
  `…` marking text cut on either side. -/
  window (s : String) (start limit : Nat) : String :=
    let pre := if start > 0 then "…" else ""
    let post := if start + limit < s.length then "…" else ""
    pre ++ String.ofList ((s.toList.drop start).take limit) ++ post

/-- A node of the analysis tree produced from a `Lean.Expr`. -/
structure XNode where
  /-- Syntactic kind of the underlying expression. -/
  kind : XKind
  /-- Short pretty-printed rendering of the underlying expression. -/
  pp : String
  /-- Pretty-printed inferred type, or `none` if `inferType` failed. -/
  type? : Option String := none
  /-- Role of this node as an argument of the parent application. -/
  role : BinderRole := .none
  /-- Universe level strings: the levels of a `const`, or the level of a `sort`. -/
  levels : List String := []
  /-- `true` if this node's head is a registered or known coercion function. -/
  isCoe : Bool := false
  /-- `true` for `mdata` wrapper nodes. -/
  isMData : Bool := false
  /-- `true` if this node differs from its counterpart in compare mode. -/
  highlighted : Bool := false
  /-- Children. For applications: the head function first, then all
  arguments in application-spine order. For binders: domain then body.
  For `let`: type, value, body. -/
  children : Array XNode := #[]
  /-- `true` if children exist in the expression but were cut off by `maxDepth`. -/
  elided : Bool := false
  deriving Inhabited

/-- Follow a path of child indices; `none` when an index is out of bounds. -/
partial def XNode.get? : XNode → List Nat → Option XNode
  | n, [] => some n
  | n, i :: rest => match n.children[i]? with
    | some c => c.get? rest
    | none => none

/-- Total number of nodes in the tree (the root counts as 1). -/
partial def XNode.size (n : XNode) : Nat :=
  1 + n.children.foldl (fun acc c => acc + c.size) 0

/-- Maximum depth of the tree (a leaf has depth 0). -/
partial def XNode.depth (n : XNode) : Nat :=
  n.children.foldl (fun acc c => Nat.max acc (c.depth + 1)) 0

/-- `true` if any node in the tree satisfies `p`. -/
partial def XNode.any (n : XNode) (p : XNode → Bool) : Bool :=
  p n || n.children.any (·.any p)

/-- Number of nodes in the tree satisfying `p`. -/
partial def XNode.count (n : XNode) (p : XNode → Bool) : Nat :=
  (if p n then 1 else 0) + n.children.foldl (fun acc c => acc + c.count p) 0

end ExprXRay
