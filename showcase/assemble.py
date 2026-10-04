#!/usr/bin/env python3
"""Assemble the widget-suite showcase site from panel dumps.

Produces site/index.html (production React — the public gallery) and
site/verify.html (development React — the strict harness: any React error or
warning fails the page, shown in the title and the verdict table).

Both pages render the SAME dumped Html trees through the same createElement
conversion the InfoView uses, so the showcase is itself the verification.
"""
import json, os, glob, html

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.join(HERE, 'site')
os.makedirs(SITE, exist_ok=True)

PACKAGES = {
  'interval-inspector': {
    'title': 'Interval Inspector',
    'commands': '#interval_inspect · interval_inspect? (tactic)',
    'tagline': 'Interval goals as a number line — with proof-verified Mathlib lemma suggestions, side conditions checked against your hypotheses, and click-to-insert in tactic mode.',
  },
  'expr-xray': {
    'title': 'Expr X-Ray',
    'commands': '#xray · #xray_diff · shift-click panel',
    'tagline': 'Elaborated-term inspection with binder roles, universes and coercions — and a defeq-aware diff that ranks the mismatch that actually blocks rw first.',
  },
  'simp-lens': {
    'title': 'Simp Lens',
    'commands': 'simp_lens (drop-in simp, at h ⊢ * supported)',
    'tagline': 'A filmstrip of every rewrite, the minimal Try-this simp only, and per-lemma exclusion previews — with executed equivalence guarantees.',
  },
  'graph-scope': {
    'title': 'Graph Scope',
    'commands': '#graph_scope · walk/highlight/layout clauses · click-to-insert',
    'tagline': 'Concrete SimpleGraphs evaluated through their own instances: layouts, stats, validated bipartition evidence — and clickable edges/vertices inserting compiled adjacency, degree and connectivity facts.',
  },
  'tree-scope': {
    'title': 'Tree Scope',
    'commands': '#tree_scope · #tree_evolve',
    'tagline': 'Universal tree & heap visualizer: red-black trees in their true colors with invariant-violation overlays, binomial-heap forests, evolution filmstrips, and constructor reflection for any inductive value.',
  },
  'hasse-view': {
    'title': 'Hasse View',
    'commands': '#hasse · highlight/updown clauses · click-to-insert',
    'tagline': 'Layered Hasse diagrams for finite orders: lattice verdicts with concrete witnesses, validity warnings for non-partial-orders — and clickable cover edges inserting compiled ⋖ facts.',
  },
  'dist-lens': {
    'title': 'Dist Lens',
    'commands': '#dist · #dist_film · #chain',
    'tagline': 'Exact probability: ℚ-precise bars, CDFs and moments, bind filmstrips, Markov chains with exact stationary distributions — every weight one click from a compiled pmf_num proof.',
  },
  'chart-kit': {
    'title': 'Chart Kit',
    'commands': '#chart · ChartSpec → Html library',
    'tagline': 'Verified-exact charting primitives: bar/line/step/scatter over exact ℚ data, ℚ-only tick math, bit-exact Float decoding.',
  },
}

dumps = []
for f in sorted(glob.glob(os.path.join(HERE, 'dumps', '*.json'))):
    with open(f) as fh:
        dumps.append(json.load(fh))

def read(p):
    with open(os.path.join(HERE, p)) as fh:
        return fh.read().replace('</script>', '<\\/script>')

COMMON_JS = r"""
const results = [];
let current = null;
const origError = console.error.bind(console);
const origWarn = console.warn.bind(console);
console.error = (...a) => { if (current) current.errors.push(a.map(String).join(' ').slice(0, 400)); origError(...a); };
console.warn  = (...a) => { if (current) current.warnings.push(a.map(String).join(' ').slice(0, 400)); origWarn(...a); };
class Boundary extends React.Component {
  constructor(p) { super(p); this.state = { failed: false }; }
  static getDerivedStateFromError() { return { failed: true }; }
  componentDidCatch(err) { if (current) current.thrown = String(err).slice(0, 400); }
  render() { return this.state.failed ? React.createElement('div', {style:{color:'red'}}, 'RENDER FAILED') : this.props.children; }
}
function toElement(node, key) {
  if (node.t === 'text') return node.s;
  if (node.t === 'el') {
    const props = { key };
    for (const [k, v] of node.attrs) props[k] = v;
    return React.createElement(node.tag, props, ...node.children.map((c, i) => toElement(c, i)));
  }
  return React.createElement('span', { key, 'data-component': node.name, title: 'InfoView runtime component (interactive in VS Code)', style: { outline: '1px dashed #b9a', borderRadius: '3px' } },
    ...node.children.map((c, i) => toElement(c, i)));
}
function renderAll(showBadPanels) {
  for (const dump of DUMPS) {
    const stage = document.getElementById('stage-' + dump.package);
    if (!stage) continue;
    for (const entry of dump.entries) {
      current = { pkg: dump.package, name: entry.name, errors: [], warnings: [], thrown: null };
      const box = document.createElement('div'); box.className = 'tree-box';
      const h = document.createElement('h4'); h.textContent = entry.name; box.appendChild(h);
      const mount = document.createElement('div'); mount.className = 'mount'; box.appendChild(mount);
      stage.appendChild(box);
      try {
        ReactDOM.flushSync(() => ReactDOM.createRoot(mount).render(React.createElement(Boundary, null, toElement(entry.tree, 0))));
      } catch (e) { current.thrown = String(e).slice(0, 400); }
      results.push(current);
      current = null;
    }
  }
  const bad = results.filter(r => r.thrown || r.errors.length);
  const warned = results.filter(r => !r.thrown && !r.errors.length && r.warnings.length);
  window.__RESULTS = results;
  return { bad, warned, total: results.length };
}
"""

CSS = """
:root { --fg: #24292f; --muted: #57606a; --border: #d0d7de; --bg: #ffffff; --accent: #6639ba; }
* { box-sizing: border-box; }
body { font-family: -apple-system, 'Segoe UI', sans-serif; margin: 0; color: var(--fg); background: var(--bg); }
header { padding: 40px 6vw 24px; border-bottom: 1px solid var(--border); }
header h1 { margin: 0 0 8px; font-size: 28px; }
header p { color: var(--muted); max-width: 72ch; margin: 4px 0; }
.badge { display: inline-block; padding: 2px 10px; border: 1px solid var(--border); border-radius: 12px; font-size: 12px; color: var(--muted); margin-right: 6px; }
#verdict { font-weight: 600; }
nav { padding: 12px 6vw; border-bottom: 1px solid var(--border); position: sticky; top: 0; background: var(--bg); z-index: 2; overflow-x: auto; white-space: nowrap; }
nav a { margin-right: 14px; color: var(--accent); text-decoration: none; font-size: 14px; }
section.pkg { padding: 28px 6vw; border-bottom: 1px solid var(--border); }
section.pkg h2 { margin: 0 0 2px; font-size: 22px; }
.cmds { font-family: ui-monospace, monospace; font-size: 13px; color: var(--accent); margin: 2px 0 6px; }
.tagline { color: var(--muted); max-width: 80ch; margin: 0 0 14px; }
.stage { display: flex; flex-wrap: wrap; gap: 14px; }
.tree-box { border: 1px solid var(--border); border-radius: 8px; padding: 10px; max-width: 100%; overflow-x: auto; }
.tree-box h4 { margin: 0 0 8px; font-size: 12px; color: var(--muted); font-family: ui-monospace, monospace; font-weight: 500; }
table.verdicts { border-collapse: collapse; margin: 16px 6vw 40px; }
table.verdicts td, table.verdicts th { border: 1px solid var(--border); padding: 4px 10px; font-size: 13px; text-align: left; }
tr.ok { background: #ecfdf0; } tr.error { background: #ffebe9; } tr.warn { background: #fff8c5; }
footer { padding: 24px 6vw 48px; color: var(--muted); font-size: 13px; }
"""

def page(react_files, verify_mode):
    dumps_by_pkg = {d['package']: d for d in dumps}
    sections = []
    nav = []
    for key, meta in PACKAGES.items():
        if key not in dumps_by_pkg: continue
        n = len(dumps_by_pkg[key]['entries'])
        nav.append(f'<a href="#{key}">{html.escape(meta["title"])}</a>')
        sections.append(f'''<section class="pkg" id="{key}">
<h2>{html.escape(meta['title'])}</h2>
<div class="cmds">{html.escape(meta['commands'])}</div>
<p class="tagline">{html.escape(meta['tagline'])} <span class="badge">{n} panels</span></p>
<div class="stage" id="stage-{key}"></div>
</section>''')
    verdict_js = (
      "document.getElementById('verdict').textContent = "
      "`${r.total - r.bad.length - r.warned.length}/${r.total} panels verified clean` + "
      "(r.bad.length || r.warned.length ? ` — ${r.bad.length} errors, ${r.warned.length} warnings (see table)` : ' — zero React errors or warnings');"
      "document.title = (r.bad.length ? 'VERIFY FAILED: ' + r.bad.length + ' errors' : 'VERIFIED: ' + r.total + ' panels clean');"
      if verify_mode else
      "document.getElementById('verdict').textContent = `${r.total} live panels rendered`;"
    )
    table_js = ""
    if verify_mode:
        table_js = r"""
const tb = document.getElementById('vbody');
for (const r of results) {
  const tr = document.createElement('tr');
  const bad = r.thrown || r.errors.length; const warned = !bad && r.warnings.length;
  tr.className = bad ? 'error' : warned ? 'warn' : 'ok';
  tr.innerHTML = `<td>${r.pkg}</td><td>${r.name}</td><td>${bad ? 'ERROR' : warned ? 'WARN' : 'OK'}</td><td>${((r.thrown || r.errors[0] || r.warnings[0] || '')+'').replace(/</g,'&lt;').slice(0,300)}</td>`;
  tb.appendChild(tr);
}"""
    verify_table = ('<table class="verdicts"><thead><tr><th>package</th><th>panel</th><th>status</th><th>detail</th></tr></thead>'
                    '<tbody id="vbody"></tbody></table>') if verify_mode else ''
    mode_note = ('Strict verification build: React 18 <b>development</b> bundle; any React error or warning fails the page.'
                 if verify_mode else
                 'Every panel below is the real <code>Html</code> tree the Lean InfoView receives, rendered through the same React conversion the InfoView uses. Dashed outlines mark runtime components (clickable/hoverable in VS Code).')
    other = ('<a href="index.html">← showcase</a>' if verify_mode else '<a href="verify.html">verification build →</a>')
    return f'''<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lean InfoView Widget Suite</title>
<style>{CSS}</style>
<script>{read('vendor/' + react_files[0])}</script>
<script>{read('vendor/' + react_files[1])}</script>
</head><body>
<header>
<h1>Lean InfoView Widget Suite</h1>
<p>Eight ProofWidgets-based visualization packages for Lean 4 &amp; Mathlib — intervals, expressions, simp calls, graphs, trees &amp; heaps, Hasse diagrams, exact probability, and verified charts.</p>
<p>{mode_note}</p>
<p><span class="badge" id="verdict">rendering…</span><span class="badge">{other}</span></p>
</header>
<nav>{''.join(nav)}</nav>
{''.join(sections)}
{verify_table}
<footer>Generated by showcase/assemble.py from headless panel dumps · Lean toolchain v4.34.0 · React 18.3.1</footer>
<script>
const DUMPS = {json.dumps(dumps)};
{COMMON_JS}
const r = renderAll();
{verdict_js}
{table_js}
</script>
</body></html>'''

open(os.path.join(SITE, 'index.html'), 'w').write(page(('react.production.min.js', 'react-dom.production.min.js'), False))
open(os.path.join(SITE, 'verify.html'), 'w').write(page(('react.development.js', 'react-dom.development.js'), True))
total = sum(len(d['entries']) for d in dumps)
print(f"site/index.html + site/verify.html written: {len(dumps)} packages, {total} panels")
