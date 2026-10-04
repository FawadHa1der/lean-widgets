/-! # TreeScope: the pure tree model

`TreeView` is the pure, fully-evaluated rose tree that every downstream
TreeScope module (layout, rendering, the `#tree_scope` command) operates on.
Each node carries display data only — a label, an optional sublabel, badges, a
semantic `NodeTone`, and a `collapsed` flag — so the model is completely
independent of where the tree came from (reflection of a concrete value in
stage 1; the semantic typeclass in stage 2).

Everything in this module is a total, `#guard`-testable pure function:
`size`/`depth`, preorder paths, path-based access and modification, mapping
utilities, and a byte-for-byte deterministic ASCII rendering used by
`#tree_scope (text := true)`.
-/

namespace TreeScope

/-- Semantic tone of a node, mapped to a themed color by the renderer and to a
`<marker>` suffix by the ASCII rendering. -/
inductive NodeTone where
  /-- Default: plain node. -/
  | neutral
  /-- Red node of a red–black tree. -/
  | rbRed
  /-- Black node of a red–black tree (rendered filled). -/
  | rbBlack
  /-- A node satisfying a checked invariant. -/
  | ok
  /-- A node violating an invariant (rendered with a red ring and a `⚠` badge). -/
  | violation
  /-- A node singled out for attention. -/
  | highlight
  /-- A newly added node (rendered with a green ring). -/
  | added
  deriving Repr, BEq, DecidableEq, Inhabited

/-- Marker used by the ASCII rendering for non-neutral tones (also the legend
name in the SVG rendering).  `neutral` has no marker. -/
def NodeTone.name : NodeTone → String
  | .neutral => "neutral"
  | .rbRed => "red"
  | .rbBlack => "black"
  | .ok => "ok"
  | .violation => "violation"
  | .highlight => "highlight"
  | .added => "added"

/-- All tones in a fixed order (legend order, tone-collection order). -/
def NodeTone.all : Array NodeTone :=
  #[.neutral, .rbRed, .rbBlack, .ok, .violation, .highlight, .added]

/-- A rose tree of display nodes: label, optional sublabel (e.g. `"bh=2"` or a
rank), badges, a semantic tone, a collapsed flag, and the children.

A `collapsed` node still *contains* its children structurally (`size`, `depth`,
`preorderPaths` see them), but layout and rendering treat it as a stub leaf
with a hidden-descendant count. -/
inductive TreeView where
  /-- Build a node from all six fields (prefer `TreeView.make` / `TreeView.leaf`). -/
  | mk (label : String) (sublabel : Option String) (badges : Array String)
      (tone : NodeTone) (collapsed : Bool) (children : Array TreeView)
  deriving Repr, BEq, Inhabited

namespace TreeView

/-! ## Accessors -/

/-- Main label of the root node. -/
def label : TreeView → String
  | .mk l _ _ _ _ _ => l

/-- Optional sublabel of the root node. -/
def sublabel : TreeView → Option String
  | .mk _ s _ _ _ _ => s

/-- Badges of the root node. -/
def badges : TreeView → Array String
  | .mk _ _ b _ _ _ => b

/-- Tone of the root node. -/
def tone : TreeView → NodeTone
  | .mk _ _ _ t _ _ => t

/-- Is the root node collapsed? -/
def collapsed : TreeView → Bool
  | .mk _ _ _ _ c _ => c

/-- Children of the root node. -/
def children : TreeView → Array TreeView
  | .mk _ _ _ _ _ cs => cs

/-! ## Constructors -/

/-- Node with the given label and children; all annotations default. -/
def make (label : String) (children : Array TreeView := #[])
    (sublabel : Option String := none) (badges : Array String := #[])
    (tone : NodeTone := .neutral) (collapsed : Bool := false) : TreeView :=
  .mk label sublabel badges tone collapsed children

/-- A childless node with the given label. -/
def leaf (label : String) : TreeView := make label

/-! ## Annotation utilities (functional updates of the root node) -/

/-- Replace the root label. -/
def withLabel (l : String) : TreeView → TreeView
  | .mk _ s b t c cs => .mk l s b t c cs

/-- Set the root sublabel. -/
def withSublabel (s : String) : TreeView → TreeView
  | .mk l _ b t c cs => .mk l (some s) b t c cs

/-- Set the root tone. -/
def withTone (t : NodeTone) : TreeView → TreeView
  | .mk l s b _ c cs => .mk l s b t c cs

/-- Append one badge to the root node. -/
def addBadge (badge : String) : TreeView → TreeView
  | .mk l s b t c cs => .mk l s (b.push badge) t c cs

/-- Set the root collapsed flag. -/
def withCollapsed (c : Bool) : TreeView → TreeView
  | .mk l s b t _ cs => .mk l s b t c cs

/-- Replace the children array. -/
def withChildren (cs : Array TreeView) : TreeView → TreeView
  | .mk l s b t c _ => .mk l s b t c cs

/-! ## Measures -/

/-- Total number of nodes, *including* descendants of collapsed nodes. -/
def size : TreeView → Nat
  | .mk _ _ _ _ _ cs => 1 + cs.attach.foldl (fun acc ⟨c, _⟩ => acc + c.size) 0

/-- Height in levels (a single node has depth 1), *including* descendants of
collapsed nodes. -/
def depth : TreeView → Nat
  | .mk _ _ _ _ _ cs => 1 + cs.attach.foldl (fun acc ⟨c, _⟩ => Nat.max acc c.depth) 0

/-- Number of hidden descendants when this node is rendered collapsed. -/
def hiddenCount (t : TreeView) : Nat := t.size - 1

/-! ## Paths

A *path* addresses a node by the child indices taken from the root: `#[]` is
the root, `#[1, 0]` is the first child of the root's second child. -/

/-- All node paths in preorder (root first, then each child subtree in order).
Includes descendants of collapsed nodes (paths are structural). -/
def preorderPaths (t : TreeView) : Array (Array Nat) :=
  go t #[]
where
  /-- Paths of the subtree at `path`, in preorder. -/
  go : TreeView → Array Nat → Array (Array Nat)
    | .mk _ _ _ _ _ cs, path =>
      (cs.attach.foldl
        (fun (acc, i) ⟨c, _⟩ => (acc ++ go c (path.push i), i + 1))
        (#[path], 0)).1

/-- The subtree rooted at `path`, if the path is valid. -/
def get? (t : TreeView) (path : Array Nat) : Option TreeView :=
  path.foldl (fun acc i => acc.bind fun s => s.children[i]?) (some t)

/-- Apply `f` to the subtree rooted at `path`; the tree is unchanged when the
path is invalid. -/
def modifyAt (t : TreeView) (path : Array Nat) (f : TreeView → TreeView) : TreeView :=
  go t path.toList
where
  /-- List-path recursion (structural on the path). -/
  go : TreeView → List Nat → TreeView
    | t, [] => f t
    | .mk l s b tn c cs, i :: rest =>
      if h : i < cs.size then .mk l s b tn c (cs.set i (go cs[i] rest))
      else .mk l s b tn c cs

/-- Collapse the node at `path`. -/
def collapseAt (t : TreeView) (path : Array Nat) : TreeView :=
  t.modifyAt path (·.withCollapsed true)

/-! ## Mapping -/

/-- Apply `f` to the *data* of every node (top-down).  `f` receives each node
with its children hidden (replaced by `#[]`) and only its returned label,
sublabel, badges, tone and collapsed flag are kept — the tree *shape* cannot
change, which keeps the recursion total. -/
def mapNodes (f : TreeView → TreeView) : TreeView → TreeView
  | .mk l s b tn c cs =>
    let d := f (.mk l s b tn c #[])
    .mk d.label d.sublabel d.badges d.tone d.collapsed
      (cs.attach.map fun ⟨x, _⟩ => x.mapNodes f)

/-- Apply `f` to every label in the tree. -/
def mapLabels (f : String → String) (t : TreeView) : TreeView :=
  t.mapNodes fun n => n.withLabel (f n.label)

/-- Does any node in the tree have tone `tn`? -/
def hasTone (t : TreeView) (tn : NodeTone) : Bool :=
  go t
where
  /-- Recursive search. -/
  go : TreeView → Bool
    | .mk _ _ _ t' _ cs => t' == tn || cs.attach.any fun ⟨c, _⟩ => go c

/-! ## ASCII rendering

One line per visible node, indented two spaces per level:

```
label · sublabel [badge1|badge2] <tone> (+N hidden)
```

Every part after the label is optional: `" · sublabel"` when a sublabel is
set, `" [a|b]"` when badges exist, `" <tone>"` for non-neutral tones, and
`" (+N hidden)"` on collapsed nodes (whose children are not printed).  The
output is a byte-for-byte deterministic function of the tree. -/

/-- The single rendered line for a node (no indentation). -/
def nodeLine (t : TreeView) : String :=
  t.label
    ++ (match t.sublabel with | some s => s!" · {s}" | none => "")
    ++ (if t.badges.isEmpty then ""
        else " [" ++ "|".intercalate t.badges.toList ++ "]")
    ++ (if t.tone == .neutral then "" else s!" <{t.tone.name}>")
    ++ (if t.collapsed then s!" (+{t.hiddenCount} hidden)" else "")

/-- Deterministic multi-line ASCII rendering (see the section docstring). -/
def ascii (t : TreeView) : String :=
  "\n".intercalate (go t 0).toList
where
  /-- Lines of the subtree at indent level `d`. -/
  go : TreeView → Nat → Array String
    | t@(.mk _ _ _ _ c cs), d =>
      let line := String.join (List.replicate d "  ") ++ t.nodeLine
      if c then #[line]
      else cs.attach.foldl (fun acc ⟨x, _⟩ => acc ++ go x (d + 1)) #[line]

end TreeView

end TreeScope
