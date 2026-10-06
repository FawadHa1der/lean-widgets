#!/usr/bin/env node
// build-gallery.mjs — generate the M2 gallery's data files (BUILD-PLAN §7.3):
//
//   gallery/examples.json  one entry per lean/examples/<pkg>.lean + <pkg>.json: the exact document text
//                          (byte-equal to the .lean file), title, blurb, header, package module, the first
//                          cursor (0-based LSP and 1-based Monaco), every cursor, and a "what to try" list
//                          derived from the spec's cursors / clicks / selections / hovers.
//   gallery/pin.json       the runtime pairing the gallery's JS preflight checks, derived from QED64.lock.json:
//                          buildId, QED64 commit/promote, Lean version — after checking that the pinned release
//                          bundle (release/<pin id>/dist/assets/*.js) names exactly that buildId (plan S0.5 #6).
//
// Gates (exit 1 on any failure): exactly the eight known packages; header == the document's first lines and
// names `import Mathlib` + `import <Pkg>` (plan D2); every cursor/selection command occurs on its line at its
// character (drift guard); every click/hover refers to an existing cursor line; the frozen golden
// lean/expect/<pkg>.json has exampleSha256 == sha256(text) (recorded, and required with --strict-goldens).
//
// Usage: node scripts/build-gallery.mjs [--check] [--strict-goldens]
//   --check  regenerate in memory and fail if gallery/examples.json or gallery/pin.json differ (stale)
// Output is deterministic (no timestamps), so --check is a byte comparison.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { abbrevTerm, cursorLabel } from './lib/term-labels.mjs';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const EX_DIR = path.join(SC, 'lean', 'examples');
const EXPECT_DIR = path.join(SC, 'lean', 'expect');
const OUT_DIR = path.join(SC, 'gallery');
const LOCK = path.join(SC, 'QED64.lock.json');
const args = new Set(process.argv.slice(2));
const CHECK = args.has('--check');
const STRICT_GOLDENS = args.has('--strict-goldens');

// Display order: phase 1 (bake widgets7) first, in the plan's W1–W7 order; DistLens (phase 2, widgets8) last.
const ORDER = ['chart-kit', 'hasse-view', 'interval-inspector', 'simp-lens', 'expr-xray', 'tree-scope', 'graph-scope', 'dist-lens'];
const PHASE2 = new Set(['dist-lens']); // plan D4
const THUMB_MAX = 60 * 1024;

const errors = [];
const warnings = [];
const fail = (m) => errors.push(m);
const sha256 = (b) => crypto.createHash('sha256').update(b).digest('hex');
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const oneLine = (s, max = 90) => { const t = String(s).replace(/\s*\n\s*/g, ' ').trim(); return t.length > max ? `${t.slice(0, max - 1)}…` : t; };
const ordinal = (n) => ['first', 'second', 'third', 'fourth', 'fifth'][n] || `#${n + 1}`;

// ---------- pin.json ----------
const lock = readJson(LOCK);
const BID = lock.qed64 && lock.qed64.buildId;
if (!/^wasm64-[0-9a-f]{16}$/.test(BID || '')) fail(`QED64.lock.json qed64.buildId ${BID} is not a wasm64 buildId`);
// the pin is keyed by QED64 commit (scripts/lib/pins.mjs): its release clone is release/<first 7 hex of the commit>
const PIN_ID = String(lock.qed64 && lock.qed64.commit).slice(0, 7);
if (!lock.release || lock.release.dir !== `release/${PIN_ID}`) fail(`QED64.lock.json release.dir ${lock.release && lock.release.dir} != release/${PIN_ID} (pins are keyed by commit)`);
const releaseDir = path.join(SC, 'release', PIN_ID);
const assetsDir = path.join(releaseDir, 'dist', 'assets');
const bundleIds = new Set();
let bundleFiles = 0;
if (fs.existsSync(assetsDir)) {
  for (const f of fs.readdirSync(assetsDir)) {
    if (!f.endsWith('.js')) continue;
    bundleFiles++;
    for (const m of fs.readFileSync(path.join(assetsDir, f), 'latin1').matchAll(/wasm64-[0-9a-f]{16}/g)) bundleIds.add(m[0]);
  }
  const ids = [...bundleIds].sort();
  if (!(ids.length === 1 && ids[0] === BID)) fail(`release bundle names buildIds [${ids.join(', ')}], want exactly ${BID} (${assetsDir})`);
} else fail(`release bundle missing: ${assetsDir} (run scripts/pin-qed64.mjs pin)`);
// QED64 embedding contract v1 (deps/qed64/docs/EMBEDDING.md §4): a dist built from a v1 page writes dist/qed64-build.json
// {schema 'qed64.build/v1', buildId, …, shell, apiRevision}. The gallery reads pin.json's apiRevision to decide its mode
// (V1 = apiRevision != null: the page API, embed mode, #code=; null = the legacy page: qed64.buffer seed, relay waits), so
// pins A–E (no such file) keep booting exactly as before. check-gallery.mjs #4 verifies both fields against that file.
let apiRevision = null; let shell = null;
const buildFile = path.join(releaseDir, 'dist', 'qed64-build.json');
if (fs.existsSync(buildFile)) {
  const b = readJson(buildFile);
  if (b.schema !== 'qed64.build/v1') fail(`${buildFile} schema ${b.schema}, want qed64.build/v1`);
  if (b.buildId !== BID) fail(`${buildFile} names buildId ${b.buildId}, want ${BID}`);
  if (b.commit && lock.qed64 && b.commit !== lock.qed64.commit) fail(`${buildFile} names commit ${b.commit}, lock ${lock.qed64.commit}`);
  apiRevision = typeof b.apiRevision === 'string' && b.apiRevision ? b.apiRevision : null;
  shell = typeof b.shell === 'string' && b.shell ? b.shell : null;
  if (apiRevision === null) warnings.push(`${buildFile} has no apiRevision: the gallery runs in legacy mode on this pin`);
}
let leanVersion = null;
const rtManifest = path.join(releaseDir, 'public', 'runtime', `runtime-manifest.${BID}.json`);
if (fs.existsSync(rtManifest)) {
  const m = readJson(rtManifest);
  if (m.buildId !== BID) fail(`${rtManifest} names ${m.buildId}, want ${BID}`);
  leanVersion = m.leanVersion || null;
} else warnings.push(`no ${rtManifest}; leanVersion unknown`);
const pin = {
  schema: 'qed64-showcase.gallery-pin/v1',
  derivedFrom: 'QED64.lock.json',
  lockSha256: sha256(fs.readFileSync(LOCK)),
  pin: PIN_ID,
  buildId: BID,
  bundleBuildIds: [...bundleIds].sort(),
  leanVersion,
  apiRevision, // release/<pin>/dist/qed64-build.json apiRevision (embedding contract v1), else null (legacy page)
  shell,       // its shell id ("shell-" + 16 hex over the dist listing), else null
  qed64: { commit: lock.qed64.commit, promote: lock.qed64.promote },
  widgetsSourceHash: lock.WIDGETS_SOURCE_HASH || null,
  mathlib: lock.toolchain && lock.toolchain.mathlib ? lock.toolchain.mathlib.commit || null : null,
  proofwidgets: lock.toolchain && lock.toolchain.mathlib ? lock.toolchain.mathlib.proofwidgets || null : null,
};

// ---------- examples.json ----------
const leanFiles = fs.readdirSync(EX_DIR).filter((f) => f.endsWith('.lean')).map((f) => f.slice(0, -5)).sort();
const specFiles = fs.readdirSync(EX_DIR).filter((f) => f.endsWith('.json')).map((f) => f.slice(0, -5)).sort();
const want = [...ORDER].sort();
if (JSON.stringify(leanFiles) !== JSON.stringify(want)) fail(`lean/examples/*.lean = [${leanFiles}], want [${want}]`);
if (JSON.stringify(specFiles) !== JSON.stringify(want)) fail(`lean/examples/*.json = [${specFiles}], want [${want}]`);

function lineAt(lines, line, character, command, where) {
  const l = lines[line];
  if (l === undefined) { fail(`${where}: line ${line} is past the end (${lines.length} lines)`); return; }
  if (!l.slice(character).startsWith(command)) fail(`${where}: line ${line} char ${character} reads ${JSON.stringify(l.slice(character, character + 40))}, spec command ${JSON.stringify(command)}`);
}

// ---------- golden-derived panel expectations ----------
// Every cursor hint must be checkable against a widget panel bound to the hint's own position, not just "something
// rendered somewhere". The frozen golden (lean/expect/w8/<pkg>.json, else lean/expect/<pkg>.json: the env the default
// overlay widgets8 serves) records, per cursor, the one panel the native server produced: its widget id, its
// "HTML Display" title (static #html-style panels) or none (mk_rpc_widget% panels rendering in the cursor's info
// block), its svg tag counts and its text leaves. expectPanel carries exactly those, plus up to two text leaves that
// occur in NO other cursor's panel of the same example, so a leftover panel from a previous cursor cannot satisfy it.
const DRAW_TAGS = ['svg', 'g', 'rect', 'line', 'circle', 'ellipse', 'polyline', 'polygon', 'path', 'text'];
const SHAPE_TAGS = ['rect', 'line', 'circle', 'ellipse', 'polyline', 'polygon', 'path'];
const norm = (s) => String(s).replace(/\s+/g, ' ').trim();
function loadGolden(id) {
  for (const [p, hp] of [[path.join(EXPECT_DIR, 'w8', `${id}.json`), path.join(EXPECT_DIR, 'html', 'w8', `${id}.json`)], [path.join(EXPECT_DIR, `${id}.json`), path.join(EXPECT_DIR, 'html', `${id}.json`)]]) {
    if (!fs.existsSync(p)) continue;
    const out = { file: path.relative(SC, p), g: readJson(p), vis: new Map(), selVis: new Map(), htmlFile: null };
    // What a card may quote must be what the panel RENDERS by default, not just what its DOM holds: the golden's
    // text leaves include text inside closed <details> (e.g. the X-Ray's "+implicit" rows, SimpLens's "h lands at:"
    // folds), which the user does not see until they expand it (UX suite W4/W5 hiddenCardClaims; bring-up audit 4).
    // The frozen Html of every panel (lean/expect/html[/w8]/<pkg>.json, written by lean/goldens/lsp-golden.mjs from
    // the same run) tells which leaves are visible: a leaf under a <details> without open=true is hidden unless it
    // sits in that details' own <summary>; display:none / visibility:hidden / hidden hide their subtree.
    if (fs.existsSync(hp)) {
      out.htmlFile = path.relative(SC, hp);
      for (const hpanel of readJson(hp).panels || []) {
        if (hpanel.index !== 0 || !hpanel.html) continue;
        if (hpanel.selection) out.selVis.set(`${hpanel.line}|${JSON.stringify(hpanel.selection)}`, htmlVisibility(hpanel.html));
        else if (!out.vis.has(hpanel.line)) out.vis.set(hpanel.line, htmlVisibility(hpanel.html));
      }
    }
    return out;
  }
  return null;
}
const squashWs = (s) => String(s).replace(/\s+/g, '');
/** Visible / hidden text of a frozen Html tree (see loadGolden). */
function htmlVisibility(html) {
  const vis = []; const hid = []; let hiddenComponents = 0;
  const attrsOf = (a) => Object.fromEntries((Array.isArray(a) ? a : []).filter((x) => Array.isArray(x)).map((x) => [x[0], x[1]]));
  const walk = (n, hidden) => {
    if (!n || typeof n !== 'object') return;
    if (typeof n.text === 'string') { (hidden ? hid : vis).push(n.text); return; }
    if (Array.isArray(n.element)) {
      const [tag, at, ch] = n.element; const a = attrsOf(at); const st = a.style && typeof a.style === 'object' ? a.style : {};
      const h = hidden || st.display === 'none' || st.visibility === 'hidden' || a.hidden === true;
      for (const c of ch || []) walk(c, h || (tag === 'details' && a.open !== true && !(c && Array.isArray(c.element) && c.element[0] === 'summary')));
      return;
    }
    if (Array.isArray(n.component)) { if (hidden) hiddenComponents++; for (const c of n.component[3] || []) walk(c, hidden); }
  };
  walk(html, false);
  return { visibleLeaves: new Set(vis.map(norm)), visible: squashWs(vis.join('')), hidden: squashWs(hid.join('')), hiddenComponents };
}
/** Is `t` rendered by default in a panel with visibility `v`? (null v: no Html recorded, nothing to say.) */
function renderedIn(v, t) {
  if (!v) return true;
  const s = squashWs(t);
  return v.visible.includes(s) || (!v.hidden.includes(s) && v.hiddenComponents === 0);
}
function panelExpectations(spec, golden) {
  const out = new Map();
  if (!golden) { fail(`${spec.package}: no golden: cursor hints cannot carry a panel expectation`); return out; }
  const byLine = new Map(golden.g.cursors.map((c) => [c.line, c]));
  const textsOf = (gc) => new Set(((gc && gc.panels && gc.panels[0] && gc.panels[0].texts) || []).map(norm));
  for (const c of spec.cursors) {
    const gc = byLine.get(c.line);
    const where = `${spec.package} cursor L${c.line + 1} (${golden.file})`;
    if (!gc || gc.character !== c.character || gc.command !== c.command) { fail(`${where}: golden has no cursor at ${c.line}:${c.character} for ${JSON.stringify(c.command)}`); continue; }
    if (!Array.isArray(gc.panels) || gc.panels.length !== 1) { fail(`${where}: golden has ${gc.panels ? gc.panels.length : 0} panels, want exactly 1`); continue; }
    const p = gc.panels[0];
    if (p.error) { fail(`${where}: golden panel error ${p.error}`); continue; }
    const others = new Set();
    for (const o of golden.g.cursors) if (o.line !== c.line) for (const t of textsOf(o)) others.add(t);
    const leaves = [...new Set((p.texts || []).map(norm))];
    const v = golden.vis.get(c.line) || null;
    if (!v) fail(`${where}: no frozen Html for this panel (${golden.htmlFile || 'lean/expect/html missing'}): cannot tell which texts it renders`);
    // only leaves the panel renders by default (a closed <details> hides its body until the user expands it)
    const cand = leaves.filter((t) => t.length >= 4 && t.length <= 80 && /\p{L}/u.test(t) && !others.has(t) && ![...others].some((o) => o.includes(t)) && (!v || v.visibleLeaves.has(t)));
    // captions ("tree: 4 nodes, depth 4", "mismatches (2, ranked)") read best: prefer leaves with a space or a colon
    const rank = (t) => (/:/.test(t) ? 0 : / /.test(t) ? 1 : 2);
    const pick = cand.map((t, i) => ({ t, i })).sort((a, b) => rank(a.t) - rank(b.t) || a.i - b.i).slice(0, 2).map((x) => x.t);
    const svg = {};
    for (const k of DRAW_TAGS) if (p.svgTagCounts && p.svgTagCounts[k]) svg[k] = p.svgTagCounts[k];
    if (!pick.length && !Object.keys(svg).some((k) => SHAPE_TAGS.includes(k))) { fail(`${where}: golden panel has neither a distinctive text leaf nor svg shapes; nothing position-specific to check`); continue; }
    out.set(c.line, {
      at: { lineNumber: c.line + 1, character: c.character },
      widget: p.id, kind: p.kind, panelTitle: p.panelTitle || null,
      svgTagCounts: svg, texts: pick, golden: golden.file,
      vis: v, // build-time only (claimTexts); not serialised
    });
  }
  return out;
}
const shortWidget = (id) => String(id || '').split('.').pop();
// Card claims quote texts whole (never truncated): at most CLAIM_MAX characters each.
const CLAIM_MAX = 80;
function describePanel(e, claims) {
  const where = e.panelTitle ? `An “${e.panelTitle}” panel` : `The ${shortWidget(e.widget)} widget`;
  const shapes = SHAPE_TAGS.concat(['text']).filter((k) => e.svgTagCounts[k]).map((k) => `${e.svgTagCounts[k]} ${k}`);
  const parts = [];
  // The card says "draws a diagram" in plain words; the exact element counts stay in expectPanel.svgTagCounts, which
  // the bring-up (hints.mjs) and the UX widget tests check against the golden.
  if (shapes.length) parts.push(`draws ${e.svgTagCounts.svg > 1 ? `${e.svgTagCounts.svg} diagrams` : 'a diagram'}`);
  if (claims.length) parts.push(`shows ${claims.map((t) => `“${t}”`).join(', ')}`);
  return `${where} ${parts.join(' and ')}.`;
}
/**
 * The texts a cursor card quotes: specific, whole, and all checked by hints.mjs. Spec texts come first when they are
 * strong: 6..CLAIM_MAX characters, quoted by no other cursor of the example (a panel title like “Simp Lens” is
 * not), and either a phrase (a space or a colon) or a qualified / lemma / hyphenated name (a '.', '_' or '-', e.g.
 * Set.mem_Icc, red-red). Then
 * the golden texts unique to this position (expectPanel.texts) that fit. Single generic words (“mul”, “Decidable”)
 * and long texts that a card would truncate are never quoted, though they are still checked.
 */
function claimTexts(specTexts, ep, otherSpecTexts) {
  const fits = (t) => t.length >= 6 && t.length <= CLAIM_MAX && !/\n/.test(t) && !t.includes("…"); // a leaf the widget itself elided reads as a truncated claim
  const strong = (t) => fits(t) && !otherSpecTexts.has(t) && (/[ :]/.test(t) || /[._-]/.test(t));
  const out = [];
  const shown = (t) => renderedIn(ep && ep.vis, t); // never quote what the panel does not render by default
  for (const t of specTexts.map(norm)) if (strong(t) && shown(t) && !out.includes(t)) out.push(t);
  // a type leaf (": HAdd ℕ ℕ ℕ") is quoted without its leading colon; the quote stays a substring of the checked leaf
  for (const t of ((ep && ep.texts) || []).map((x) => norm(x).replace(/^:\s+/, ''))) if (fits(t) && /\p{L}/u.test(t) && shown(t) && !out.some((o) => o.includes(t) || t.includes(o))) out.push(t);
  return out.slice(0, 2);
}
// ---------- golden-derived selection expectations ----------
// A select hint's claim must hold only AFTER the shift-click(s): build-gallery checks each spec text against the
// frozen golden of that exact selection (lean/expect[/w8]/<pkg>.json selections[], the panel the native server
// produced for those selectedLocations) and against the golden of the same position WITHOUT a selection (the cursor
// entry). Texts are matched like the native harness joins them (leaves concatenated) with all whitespace removed,
// so a run of leaves ("clean (explicit only)" + "app " + "if n = n then 1 else 0" + " : ℕ" = the x-ray's root row)
// counts. `appear` = the spec texts present with the selection and absent without it; the build fails if a spec
// text is missing from the selection golden, or if `appear` is empty (the claim would not depend on the selection).
const squash = (s) => String(s).replace(/\s+/g, '');
const goldenJoined = (panels) => squash((panels || []).flatMap((p) => [...(p.texts || []), ...(p.codeTexts || [])]).join(''));
function selectExpectation(spec, s, golden, idx) {
  const where = `${spec.package} selection #${idx} L${s.line + 1}`;
  if (!golden) { fail(`${where}: no golden`); return null; }
  const gs = (golden.g.selections || []).find((x) => x.line === s.line && x.character === s.character && JSON.stringify(x.select) === JSON.stringify(s.select));
  if (!gs) { fail(`${where}: golden ${golden.file} has no selection ${JSON.stringify(s.select)}`); return null; }
  if (!Array.isArray(gs.panels) || !gs.panels.length || gs.panels.some((p) => p.error)) { fail(`${where}: golden selection panel missing or errored`); return null; }
  const gc = (golden.g.cursors || []).find((c) => c.line === s.line && c.character === s.character);
  if (!gc) { fail(`${where}: golden has no no-selection cursor at ${s.line}:${s.character} to compare against`); return null; }
  const withSel = goldenJoined(gs.panels); const without = goldenJoined(gc.panels);
  const texts = ((s.expect && s.expect.texts) || []).map(norm);
  if (!texts.length) { fail(`${where}: spec selection has no expect.texts`); return null; }
  for (const t of texts) if (!withSel.includes(squash(t))) fail(`${where}: ${JSON.stringify(t)} is not in the golden selection panel (${golden.file})`);
  const appear = texts.filter((t) => !without.includes(squash(t)));
  if (!appear.length) { fail(`${where}: every claimed text ${JSON.stringify(texts)} is already in the panel without a selection (vacuous claim)`); return null; }
  return { at: { lineNumber: s.line + 1, character: s.character }, widget: gs.panels[0].id, texts, appear, squash: true, picks: s.select.length, golden: golden.file };
}

function hintsFor(spec, lines, golden) {
  // Each hint carries what the card SAYS (label, detail) and what a test needs to CHECK it (expect*), both derived
  // from the same spec entry, so tests/ux/bringup/hints.mjs verifies exactly the claims the card makes.
  const hints = [];
  const pos = (line, character) => ({ line, character, lineNumber: line + 1, column: character + 1 });
  const cursorByLine = new Map(spec.cursors.map((c) => [c.line, c]));
  const quote = (ts, n = 2, w = 40) => ts.slice(0, n).map((t) => `“${oneLine(t, w)}”`).join(', ');
  const panels = panelExpectations(spec, golden);
  const specTextCount = new Map();
  for (const c of spec.cursors) for (const t of new Set(((c.expect && c.expect.texts) || []).map(norm))) specTextCount.set(t, (specTextCount.get(t) || 0) + 1);
  const sharedSpecTexts = new Set([...specTextCount].filter(([, n]) => n > 1).map(([t]) => t));
  // 1. cursors: what each panel shows. expectTexts are the spec's frozen claims (if any); expectPanel is always
  // present and is checked too: the info block at exactly this position holds this widget's panel.
  for (const c of spec.cursors) {
    const e = c.expect || {};
    const texts = Array.isArray(e.texts) ? e.texts.slice(0, 2) : [];
    const ep = panels.get(c.line) || null;
    if (ep && e.panelTitle && e.panelTitle !== ep.panelTitle) fail(`${spec.package} cursor L${c.line + 1}: spec panelTitle ${e.panelTitle} != golden ${ep.panelTitle}`);
    // a missing expectPanel already failed the build (panelExpectations)
    const claims = claimTexts(texts, ep, sharedSpecTexts);
    // the spec's own texts are checked in the rendered panel (bring-up hints.mjs reads what is rendered): each must be
    for (const t of texts) if (ep && !renderedIn(ep.vis, t)) fail(`${spec.package} cursor L${c.line + 1}: spec text ${JSON.stringify(t)} is not rendered by default (inside a closed <details>, ${golden.htmlFile})`);
    const what = ep ? describePanel(ep, claims) : `The panel shows ${quote(texts)}.`;
    const { vis: _vis, ...epOut } = ep || {};
    hints.push({ kind: 'cursor', label: cursorLabel(lines, c), detail: what, claimTexts: claims, expectTexts: texts, expectPanel: ep ? epOut : ep, ...pos(c.line, c.character) });
  }
  // 2. selections: shift-click in the goal view
  (spec.selections || []).forEach((s, si) => {
    const parts = s.select.map((x, i) => (x.hyp ? `hypothesis ${x.hyp}`
      : i > 0 && s.select[i - 1].target === x.target ? `its ${ordinal(x.occurrence || 0)} occurrence`
        : `the ${ordinal(x.occurrence || 0)} \`${oneLine(x.target, 32)}\``));
    const e = s.expect || {};
    const texts = Array.isArray(e.texts) ? e.texts.slice(0, 2) : [];
    lineAt(lines, s.line, s.character, s.command, `${spec.package} selection`);
    const sp = selectExpectation(spec, s, golden, si);
    // the card quotes only what the selection makes appear (whole), then the spec's note on what it means
    const sv = golden ? golden.selVis.get(`${s.line}|${JSON.stringify(s.select)}`) || null : null;
    if (golden && !sv) fail(`${spec.package} selection #${si}: no frozen Html for the selection panel (${golden.htmlFile || 'lean/expect/html missing'})`);
    const hiddenSel = sp ? sp.appear.filter((t) => !renderedIn(sv, t)) : [];
    if (hiddenSel.length) fail(`${spec.package} selection #${si}: ${JSON.stringify(hiddenSel)} would appear only inside a closed <details>`);
    const shown = sp ? sp.appear.filter((t) => t.length <= 80 && renderedIn(sv, t)) : [];
    const claim = shown.length ? `; the panel then shows ${shown.map((t) => `“${t}”`).join(' and ')}${e.note ? ` (${e.note})` : ''}` : '';
    hints.push({
      kind: 'select',
      label: `Shift-click ${parts.join(' then ')} (line ${s.line + 1})`,
      detail: `Cursor on \`${s.command}\`, then shift-click ${parts.join(', then ')} in the goal view${claim}.`,
      claimTexts: shown, expectTexts: texts, expectSelect: s.select, expectSelectPanel: sp,
      ...pos(s.line, s.character),
    });
  });
  // 3. clicks: MakeEditLink in a panel, or core Try-this [apply] in a message
  for (const k of spec.clicks || []) {
    const c = cursorByLine.get(k.cursorLine);
    if (!c) { fail(`${spec.package} click ${JSON.stringify(k.linkText || k.linkTitle)}: no cursor on line ${k.cursorLine}`); continue; }
    const ed = k.expectedEdit || {};
    const r = ed.range;
    const newText = (ed.newText || '').trim();
    const isInsert = r && r.start.line === r.end.line && r.start.character === r.end.character;
    const old = r && !isInsert && r.start.line === r.end.line ? (lines[r.start.line] || '').slice(r.start.character, r.end.character) : null;
    // The card shows the WHOLE edit (bring-up audit 5 minor: a mid-term "…" hid what the click inserts); only
    // whitespace is collapsed. The longest edit (dist-lens, 151 chars) still fits the card's wrapping detail line.
    const effect = isInsert ? `inserts \`${oneLine(newText, Infinity)}\` on a new line after the command`
      : `replaces \`${oneLine(old || 'the call', Infinity)}\` with \`${oneLine(newText, Infinity)}\``;
    // What the clicked element IS, named from the edit it makes (bring-up audit 5 minor: “Click “0”” did not say that
    // 0 is a vertex of the drawing): GraphScope's vertex links insert `….degree (v) = d`, its edge links `….Adj (a) (b)`.
    const vtx = /\.degree \((.+?)\) = /.exec(newText);
    const edge = /\.Adj \((.+?)\) \((.+?)\) :=/.exec(newText);
    const where = `(line ${k.cursorLine + 1})`;
    let label; let how;
    if (k.kind === 'tryThis') { label = `Apply the “Try this” on line ${k.cursorLine + 1}`; how = 'Click [apply] in the message'; }
    else if (!k.linkText && edge) { label = `Click the edge ${edge[1]}–${edge[2]} in the drawing ${where}`; how = `Click the line between vertices ${edge[1]} and ${edge[2]}`; }
    else if (k.linkText && vtx && k.linkText === vtx[1]) { label = `Click vertex ${vtx[1]} in the drawing ${where}`; how = `Click the vertex labelled ${vtx[1]} (its circle or number)`; }
    else if (k.linkText) { label = `Click “${abbrevTerm(k.linkText)}” in the panel ${where}`; how = 'Click the link in the panel'; }
    else { label = `Click the edge ${oneLine((k.linkTitle || '').replace(/^insert:\s*example\s*:\s*/, '').replace(/\s*:=.*$/, ''), 36)} in the drawing ${where}`; how = 'Click that edge in the drawing'; }
    hints.push({
      kind: 'click', clickKind: k.kind, label,
      detail: oneLine(`${how}: it ${effect}${k.postClickDiagnostics === 'clean' ? '; the file re-checks with no errors' : ''}.`, Infinity),
      expectClick: { linkText: k.linkText || '', linkTitle: k.linkTitle || null, kind: k.kind, newText: ed.newText || '', range: r || null },
      ...pos(c.line, c.character),
    });
  }
  // 4. hovers inside a panel's InteractiveCode
  // The popup is checked inside the InfoView's hover tooltip (.tooltip .tooltip-code-content), which must be absent
  // before the hover; its text "<expr> : <type>" comes from the frozen golden hover (lean/expect[/w8]/<pkg>.json
  // hovers[]: codeText = the panel code element hovered, exprExplicitText, typeText), and the spec's typeText must
  // agree with it.
  for (const h of spec.hovers || []) {
    const c = cursorByLine.get(h.cursorLine);
    if (!c) { fail(`${spec.package} hover: no cursor on line ${h.cursorLine}`); continue; }
    const gh = golden && (golden.g.hovers || []).find((x) => x.cursorLine === h.cursorLine && x.panel === h.panel && x.code === h.code && x.tagText === h.tagText);
    if (!gh) { fail(`${spec.package} hover ${JSON.stringify(h.tagText)} L${h.cursorLine + 1}: no golden hover in ${golden ? golden.file : 'no golden'}`); continue; }
    const typeText = (h.expect && h.expect.typeText) || null;
    if (!typeText || gh.typeText !== typeText) { fail(`${spec.package} hover ${JSON.stringify(h.tagText)}: spec typeText ${JSON.stringify(typeText)} != golden ${JSON.stringify(gh.typeText)}`); continue; }
    const popup = `${gh.exprExplicitText} : ${gh.typeText}`;
    hints.push({
      kind: 'hover', label: `Hover \`${h.tagText}\` in the panel (line ${h.cursorLine + 1})`,
      detail: oneLine(`Hover \`${h.tagText}\` in the panel's \`${gh.codeText}\`: a popup shows its type, \`${popup}\`.`, 160),
      claimTexts: [popup],
      expectHover: { tagText: h.tagText, codeText: gh.codeText, codeIndex: h.code, exprText: gh.exprExplicitText, typeText: gh.typeText, popupText: popup, golden: golden.file },
      ...pos(c.line, c.character),
    });
  }
  // Order: where to start (the first cursor), then the interactive things (select / click / hover), then the
  // remaining cursors. The gallery shows the first few and folds the rest.
  const firstCursor = hints.filter((h) => h.kind === 'cursor').slice(0, 1);
  const interactive = hints.filter((h) => h.kind !== 'cursor');
  const restCursors = hints.filter((h) => h.kind === 'cursor').slice(1);
  return [...firstCursor, ...interactive, ...restCursors];
}

const examples = [];
for (const id of ORDER) {
  const leanPath = path.join(EX_DIR, `${id}.lean`);
  const specPath = path.join(EX_DIR, `${id}.json`);
  if (!fs.existsSync(leanPath) || !fs.existsSync(specPath)) { fail(`${id}: missing ${fs.existsSync(leanPath) ? specPath : leanPath}`); continue; }
  const bytes = fs.readFileSync(leanPath);
  const text = bytes.toString('utf8');
  if (Buffer.compare(Buffer.from(text, 'utf8'), bytes) !== 0) fail(`${id}: ${leanPath} is not valid UTF-8`);
  if (text.includes('\r')) fail(`${id}: CRLF line endings`);
  const spec = readJson(specPath);
  const lines = text.split('\n');
  if (spec.package !== id) fail(`${id}: spec.package = ${spec.package}`);
  for (const k of ['title', 'blurb']) if (typeof spec[k] !== 'string' || !spec[k].trim()) fail(`${id}: spec.${k} missing`);
  if (!Array.isArray(spec.header) || spec.header.length !== 2 || spec.header[0] !== 'import Mathlib') fail(`${id}: header ${JSON.stringify(spec.header)} (want ["import Mathlib", "import <Pkg>"], plan D2)`);
  else spec.header.forEach((h, i) => { if (lines[i] !== h) fail(`${id}: line ${i} ${JSON.stringify(lines[i])} != header ${JSON.stringify(h)}`); });
  const module = spec.header && moduleOf(spec.header[1]);
  if (!module) fail(`${id}: cannot read the package module from ${JSON.stringify(spec.header && spec.header[1])}`);
  if (!Array.isArray(spec.cursors) || spec.cursors.length === 0) { fail(`${id}: no cursors`); continue; }
  for (const c of spec.cursors) lineAt(lines, c.line, c.character, c.command, `${id} cursor`);
  const textSha256 = sha256(bytes);
  const gold = loadGolden(id);
  if (gold && gold.g.exampleSha256 !== textSha256) fail(`${id}: ${gold.file} exampleSha256 does not match the example: its panels cannot back the card hints (regenerate the golden)`);
  const hints = hintsFor(spec, lines, gold);
  // golden linkage
  let golden = { present: false };
  const gp = path.join(EXPECT_DIR, `${id}.json`);
  if (fs.existsSync(gp)) {
    const g = readJson(gp);
    golden = { present: true, ok: g.ok === true, mode: g.mode || null, exampleSha256Matches: g.exampleSha256 === textSha256, failures: Array.isArray(g.failures) ? g.failures.length : null };
    if (!golden.exampleSha256Matches) (STRICT_GOLDENS ? fail : (m) => warnings.push(m))(`${id}: lean/expect/${id}.json exampleSha256 ${String(g.exampleSha256).slice(0, 12)}… != example ${textSha256.slice(0, 12)}… (golden is stale)`);
    if (!golden.ok) (STRICT_GOLDENS ? fail : (m) => warnings.push(m))(`${id}: golden ok=${g.ok}`);
  } else (STRICT_GOLDENS ? fail : (m) => warnings.push(m))(`${id}: no golden ${gp}`);
  const first = spec.cursors[0];
  // card thumbnail: gallery/thumbs/<id>.png, made from the real rendered panel by tests/ux/bringup/widgets.mjs --thumbs
  let thumb = null;
  const tp = path.join(OUT_DIR, 'thumbs', `${id}.png`);
  if (fs.existsSync(tp)) {
    const b = fs.readFileSync(tp);
    if (b.length < 24 || b.toString('latin1', 1, 4) !== 'PNG') fail(`${id}: ${tp} is not a PNG`);
    else {
      // fit: 'contain' for a letterboxed whole drawing (tests/ux/bringup/widgets.mjs writes thumbs/thumbs.json), else 'cover'
      let mode = null; try { mode = (JSON.parse(fs.readFileSync(path.join(OUT_DIR, 'thumbs', 'thumbs.json'), 'utf8'))[id] || {}).mode || null; } catch { mode = null; }
      thumb = { src: `thumbs/${id}.png`, width: b.readUInt32BE(16), height: b.readUInt32BE(20), bytes: b.length, sha256: sha256(b).slice(0, 16), fit: mode === 'letterbox' ? 'contain' : 'cover' };
      if (b.length > THUMB_MAX) fail(`${id}: thumbnail ${b.length} bytes > ${THUMB_MAX}`);
      if (thumb.width !== 480) fail(`${id}: thumbnail width ${thumb.width}, want 480`);
    }
  } else warnings.push(`${id}: no thumbnail gallery/thumbs/${id}.png (run tests/ux/bringup/widgets.mjs --thumbs)`);
  examples.push({
    id,
    title: spec.title,
    blurb: spec.blurb,
    module,
    phase: PHASE2.has(id) ? 2 : 1,
    header: spec.header,
    text,
    textSha256,
    lineCount: lines.length - (text.endsWith('\n') ? 1 : 0),
    firstCursor: { line: first.line, character: first.character, lineNumber: first.line + 1, column: first.character + 1, command: first.command },
    cursors: spec.cursors.map((c) => ({ line: c.line, character: c.character, command: c.command })),
    tryThis: hints,
    counts: { cursors: spec.cursors.length, clicks: (spec.clicks || []).length, selections: (spec.selections || []).length, hovers: (spec.hovers || []).length },
    golden,
    thumb,
  });
}
function moduleOf(line) { const m = /^\s*import\s+([A-Za-z_«][\w.«»']*)\s*$/.exec(line || ''); return m ? m[1] : null; }

const out = {
  schema: 'qed64-showcase.gallery-examples/v1',
  generator: 'scripts/build-gallery.mjs',
  source: 'lean/examples/*.lean + *.json',
  count: examples.length,
  examples,
};

for (const w of warnings) console.log(`warn  ${w}`);
if (errors.length) { for (const e of errors) console.log(`FAIL  ${e}`); console.log(`build-gallery: ${errors.length} error(s)`); process.exit(1); }

const files = { 'examples.json': `${JSON.stringify(out, null, 2)}\n`, 'pin.json': `${JSON.stringify(pin, null, 2)}\n` };
let stale = 0;
for (const [name, body] of Object.entries(files)) {
  const p = path.join(OUT_DIR, name);
  if (CHECK) {
    const cur = fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : null;
    if (cur !== body) { stale++; console.log(`STALE ${path.relative(SC, p)} (rerun node scripts/build-gallery.mjs)`); }
    else console.log(`ok    ${path.relative(SC, p)} up to date (${Buffer.byteLength(body)} bytes, sha256 ${sha256(body).slice(0, 16)})`);
  } else {
    fs.writeFileSync(p, body);
    console.log(`wrote ${path.relative(SC, p)} (${Buffer.byteLength(body)} bytes, sha256 ${sha256(body).slice(0, 16)})`);
  }
}
for (const e of examples)
  console.log(`ok    ${e.id.padEnd(19)} ${e.title.padEnd(19)} phase ${e.phase} module ${e.module.padEnd(17)} ${String(e.lineCount).padStart(3)} lines  first cursor L${e.firstCursor.lineNumber}:${e.firstCursor.column}  ${e.tryThis.length} hints  thumb ${e.thumb ? `${e.thumb.width}x${e.thumb.height} ${e.thumb.bytes} B` : 'none'}  golden ${e.golden.present ? (e.golden.ok && e.golden.exampleSha256Matches ? 'ok' : 'STALE') : 'none'}`);
console.log(`pin   buildId ${pin.buildId} (bundle ${pin.bundleBuildIds.join(',')} in ${bundleFiles} js files) lean ${pin.leanVersion} qed64 ${String(pin.qed64.commit).slice(0, 12)} api ${pin.apiRevision ?? 'none (legacy page)'} shell ${pin.shell ?? '-'}`);
console.log(`BUILD-GALLERY ${CHECK ? (stale ? 'STALE' : 'CHECK OK') : 'OK'} ${examples.length} examples`);
process.exit(stale ? 1 : 0);
