// Shared plumbing for the M2 gallery bring-up runs (tests/ux/bringup/*.mjs).
// Always run through scripts/with-browser-lock.sh (one browser on the host at a time).
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { browserLockFile } from '../../../scripts/lib/browser-lock.mjs';

export const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
export const ORIGIN = process.env.ORIGIN || 'http://localhost:5190';
export const OUT = path.join(SC, 'out', 'ux', 'bringup');
export const SEL = (await import(path.join(SC, 'scripts/lib/pins.mjs'))).loadSelectors(); // "@qed64-main-bundle" -> the active pin's bundle
// GALLERY_DIR (mutation runs, tests/ux/bringup/mutants.sh): read the hints from the same mutated copy serve.mjs serves
export const EXAMPLES = JSON.parse(fs.readFileSync(path.join(process.env.GALLERY_DIR || path.join(SC, 'gallery'), 'examples.json'), 'utf8')).examples;
export const SPECS = Object.fromEntries(EXAMPLES.map((e) => [e.id, JSON.parse(fs.readFileSync(path.join(SC, 'lean/examples', `${e.id}.json`), 'utf8'))]));
export const LAUNCH_ARGS = ['--enable-features=SharedArrayBuffer']; // tests/experiments/lib.mjs, buffer-probe.cjs:14
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
fs.mkdirSync(OUT, { recursive: true });

export function lockHeld() {
  const p = browserLockFile();
  if (!fs.existsSync(p)) throw new Error(`run me through scripts/with-browser-lock.sh (the host browser lock ${p} is absent)`);
  return fs.readFileSync(p, 'utf8').trim();
}

/** Sample chromeRss() every intervalMs into an array (and the console stream via w.mark if given). */
export function rssSampler(intervalMs = 1000, t0 = Date.now()) {
  const samples = []; let peak = { totalGiB: 0, maxRendererGiB: 0 };
  const h = setInterval(() => { const r = chromeRss(); samples.push({ t: Date.now() - t0, ...r }); if (r.totalGiB > peak.totalGiB) peak = { ...r, t: Date.now() - t0 }; }, intervalMs);
  return { samples, get peak() { return peak; }, stop: () => clearInterval(h) };
}

/** Renderer/GPU/browser RSS of the headless shell, GiB, summed and per-type (ps rss is KiB). */
export function chromeRss() {
  const ps = spawnSync('ps', ['-axo', 'rss=,command='], { encoding: 'utf8' }).stdout || '';
  const out = { totalGiB: 0, rendererGiB: 0, maxRendererGiB: 0, procs: 0 };
  for (const l of ps.split('\n')) {
    if (!/chrome-headless-shell|Chromium|chrome/.test(l) || !/ms-playwright/.test(l)) continue;
    const kb = Number(l.trim().split(/\s+/)[0]) || 0; const g = kb / 1048576;
    out.totalGiB += g; out.procs++;
    if (/--type=renderer/.test(l)) { out.rendererGiB += g; out.maxRendererGiB = Math.max(out.maxRendererGiB, g); }
  }
  for (const k of ['totalGiB', 'rendererGiB', 'maxRendererGiB']) out[k] = +out[k].toFixed(2);
  return out;
}

export async function launch(opts = {}) {
  lockHeld();
  return chromium.launch({ args: LAUNCH_ARGS, ...opts });
}

/**
 * Every console message and page error of a page, from all frames and workers, with where it came from.
 * Classification happens later (classifyConsole), so the raw record is never filtered here.
 */
export function watchConsole(page, t0 = Date.now(), streamTo = null) {
  const w = { messages: [], pageErrors: [], crashed: false };
  const sink = streamTo ? fs.openSync(path.join(OUT, streamTo), 'w') : null;
  const emit = (kind, rec) => { if (sink !== null) { try { fs.writeSync(sink, `${JSON.stringify({ kind, ...rec })}\n`); } catch { /* ignore */ } } };
  page.on('console', (m) => {
    let loc = null; try { loc = m.location(); } catch { /* ignore */ }
    let worker = null; try { worker = m.worker() ? m.worker().url() : null; } catch { /* ignore */ }
    const rec = { t: Date.now() - t0, wall: Date.now(), type: m.type(), text: m.text().slice(0, 600), url: loc && loc.url ? loc.url.replace(ORIGIN, '') : null, line: loc ? loc.lineNumber : null, worker: worker ? worker.replace(ORIGIN, '') : null };
    w.messages.push(rec); emit('console', rec);
  });
  page.on('pageerror', (e) => { const rec = { t: Date.now() - t0, wall: Date.now(), message: String(e && e.message || e).slice(0, 400), name: e && e.name, stack: String(e && e.stack || '').split('\n').slice(0, 8).join('\n') }; w.pageErrors.push(rec); emit('pageerror', rec); });
  page.on('crash', () => { w.crashed = true; emit('crash', { t: Date.now() - t0, rss: chromeRss() }); });
  w.workers = [];
  page.on('worker', (wk) => { const rec = { t: Date.now() - t0, url: wk.url().replace(ORIGIN, '').slice(0, 200) }; w.workers.push(rec); emit('worker', rec); wk.on('close', () => emit('worker-close', { t: Date.now() - t0, url: rec.url })); });
  w.mark = (label, extra = {}) => emit('mark', { t: Date.now() - t0, label, ...extra });
  // page loads, for the per-load limits of the console allowlist: the top page and the QED64 page (depth 0 / 1) count
  // a document request each (a same-document hash / history navigation is not a load); the InfoView webview is an
  // `about:srcdoc` document two levels further down (QED64 page > #infoview iframe (about:blank) > srcdoc webview,
  // seen in widgets-after-audit3.console.jsonl), so each navigation of a depth >= 2 frame to about:srcdoc counts.
  // Every frame navigation is also streamed for the record.
  w.loads = { top: 0, qed64: 0, infoview: 0 };
  const depth = (f) => { let d = 0; for (let p = f.parentFrame(); p; p = p.parentFrame()) d++; return d; };
  const kindOf = (f) => (!f ? null : ['top', 'qed64', 'infoview-host'][depth(f)] || 'infoview');
  page.on('request', (rq) => {
    try {
      if (!rq.isNavigationRequest() || rq.resourceType() !== 'document') return;
      const k = kindOf(rq.frame()); if (k !== 'top' && k !== 'qed64') return;
      w.loads[k]++; emit('load', { t: Date.now() - t0, frame: k, url: rq.url().replace(ORIGIN, '').slice(0, 200) });
    } catch { /* ignore */ }
  });
  page.on('framenavigated', (f) => {
    const k = kindOf(f); const u = f.url();
    emit('navigated', { t: Date.now() - t0, frame: k, url: u.replace(ORIGIN, '').slice(0, 200) });
    if (depth(f) >= 2 && u === 'about:srcdoc') { w.loads.infoview++; emit('load', { t: Date.now() - t0, frame: 'infoview', url: u }); }
  });
  return w;
}

import { classifyConsole as classifyConsoleWith, consoleLine } from './console.mjs';
import { TAP_SRC } from '../lib/lsp-tap.mjs';
/**
 * The UX suite's LSP tap (tests/ux/lib/lsp-tap.mjs) in every QED64 page document of `ctx`: returns the live array
 * of its reports ({kind:'errorReply', code, recvWall, …}). Pass it to classifyConsole({reports}) so each allowlisted
 * empty console.error is paired with its own LSP -32800 reply (bring-up audit 5 minor). Call before the first goto.
 */
export async function installTap(ctx) {
  const reports = [];
  await ctx.exposeBinding('__uxReport', (src, o) => { reports.push({ ...o, recvWall: Date.now() }); });
  await ctx.addInitScript({ content: TAP_SRC });
  return reports;
}
export { consoleLine, classifyConsoleWith };
/** classifyConsole(watch, allow = selectors.json consoleAllowlist, {scenarios}) — see console.mjs. */
export const classifyConsole = (watch, allow = SEL.consoleAllowlist, opts = {}) => classifyConsoleWith(watch, allow, opts);
/** Tap-report summary for the JSON record: error replies by code. */
export const tapSummary = (reports) => reports.reduce((a, r) => { const k = r.kind === 'errorReply' ? `errorReply ${r.code}` : r.kind; a[k] = (a[k] || 0) + 1; return a; }, {});

/** The gallery's API (window.__showcase) on the top page. */
export const api = {
  status: (page) => page.evaluate(() => window.__showcase && window.__showcase.status()),
  bridge: (page) => page.evaluate(() => window.__showcase && window.__showcase.bridgeStats()),
  text: (page) => page.evaluate(() => window.__showcase && window.__showcase.currentText()),
  select: (page, id) => page.evaluate((i) => window.__showcase.select(i).then((s) => ({ ok: true, s }), (e) => ({ ok: false, code: e && e.code, message: String(e && e.message || e) })), id),
};
/** Evaluate inside the QED64 page window (the iframe), from the gallery. */
export const inPage = (page, fn, arg) => page.evaluate(([src, a]) => {
  const w = document.getElementById('qed64-frame').contentWindow;
  // eslint-disable-next-line no-new-func
  return new w.Function('arg', `return (${src})(arg);`)(a);
}, [fn.toString(), arg === undefined ? null : arg]);

export const qedFrame = (page) => page.frameLocator('#qed64-frame');
export const infoview = (page) => page.frameLocator('#qed64-frame').frameLocator(SEL.infoview.frame);
export async function waitGalleryReady(page, { timeoutMs = 400000 } = {}) {
  const t0 = Date.now();
  for (;;) {
    const s = await api.status(page).catch(() => null);
    if (s && (s.phase === 'ready' || s.phase === 'refused' || s.phase === 'error')) return { s, ms: Date.now() - t0 };
    if (Date.now() - t0 > timeoutMs) return { s, ms: Date.now() - t0, timedOut: true };
    await sleep(250);
  }
}

/** InfoView text (innerText of the body), '' if not reachable. */
export async function ivText(page) {
  return (await infoview(page).locator('body').innerText({ timeout: 5000 }).catch(() => '')) || '';
}
/** §8.1 settled: no updating (gold) summary and no "Error updating". */
export async function ivSettled(page, { timeoutMs = 60000 } = {}) {
  const iv = infoview(page); const t0 = Date.now();
  for (;;) {
    const gold = await iv.locator(SEL.infoview.updatingSummary).count().catch(() => 1);
    const err = await iv.locator(SEL.infoview.errorDiv, { hasText: 'Error updating' }).count().catch(() => 0);
    if (!gold && !err) return true;
    if (Date.now() - t0 > timeoutMs) return false;
    await sleep(200);
  }
}

export function writeJson(name, obj) {
  const p = path.join(OUT, name);
  fs.writeFileSync(p, `${JSON.stringify(obj, null, 2)}\n`);
  console.log(`wrote ${path.relative(SC, p)}`);
  return p;
}

/** Wait for a condition evaluated in Node (async fn); returns value or null on timeout. */
export async function until(fn, { timeoutMs = 30000, intervalMs = 200 } = {}) {
  const t0 = Date.now();
  for (;;) {
    const v = await fn().catch(() => null);
    if (v) return v;
    if (Date.now() - t0 > timeoutMs) return null;
    await sleep(intervalMs);
  }
}

/**
 * The widget panel bound to a position (examples.json tryThis[].expectPanel, derived from the frozen golden by
 * scripts/build-gallery.mjs). Checks, inside the InfoView:
 *   1. the cursor's info block is the one for exactly this position: a <details> (not under a Messages section)
 *      whose summary reads `<file>.lean:<lineNumber>:<character>`; no other position's block counts;
 *   2. in that block, the panel: the nested <details> titled `panelTitle` ("HTML Display") for static panels, or the
 *      block itself (minus any Messages / "HTML Display" sub-sections) for mk_rpc_widget% panels (panelTitle null);
 *      an rpc expectation also fails if the block holds no rpc output at all;
 *   3. the panel's svg tag counts equal svgTagCounts exactly — over the whole DRAW_TAGS set (svg, g, rect, line,
 *      circle, ellipse, polyline, polygon, path, text) plus any other key the expectation names, a kind missing from
 *      the expectation counting as 0, so a panel that draws an extra kind of shape fails; svgTagCounts null = svg not
 *      compared (selection checks) — and each of `texts` (+ `extraTexts`) occurs in it. With `squash`, texts are
 *      matched with all whitespace removed on both sides (a run of consecutive text leaves, e.g. a section caption
 *      followed by the first tree row, is then matchable however the DOM splits it into text nodes).
 * The matched panel is tagged data-bringup-panel (for screenshots). Returns {ok, reason, at, heads, panelTitle,
 * svgTags, missingTexts, svgDiff, graphicTop, text, rect, selectedCount (shift-click selections in the block)}.
 */
export const DRAW_TAGS = ['svg', 'g', 'rect', 'line', 'circle', 'ellipse', 'polyline', 'polygon', 'path', 'text'];
export async function checkPanel(page, exp, { extraTexts = [], squash = false } = {}) {
  return infoview(page).locator('body').evaluate((b, a) => {
    const { exp, extraTexts, squash, DRAW_TAGS, selSel } = a;
    const norm = (s) => String(s).replace(/\s+/g, ' ').trim();
    const cmp = squash ? (s) => String(s).replace(/\s+/g, '') : norm;
    const sumOf = (d) => { const s = d.querySelector(':scope > summary'); return s ? norm(s.textContent) : ''; };
    const isMsg = (d) => /^(All )?Messages/.test(sumOf(d));
    const underMsg = (el, stop) => { for (let p = el.parentElement; p && p !== stop; p = p.parentElement) if (p.tagName === 'DETAILS' && isMsg(p)) return true; return false; };
    for (const el of b.querySelectorAll('[data-bringup-panel]')) el.removeAttribute('data-bringup-panel');
    const posRe = /^[\w.\-/ ]+\.lean:(\d+):(\d+)/;
    const blocks = [...b.querySelectorAll('details')].filter((d) => posRe.test(sumOf(d)) && !underMsg(d, b));
    const heads = blocks.map((d) => sumOf(d).match(posRe)[0]);
    const want = `:${exp.at.lineNumber}:${exp.at.character}`;
    const block = blocks.find((d) => { const m = sumOf(d).match(posRe); return m && `:${m[1]}:${m[2]}` === want; });
    const res = { ok: false, at: want, heads, panelTitle: null, svgTags: {}, missingTexts: [], svgDiff: {}, selectedCount: null };
    if (!block) { res.reason = `no info block at ${want} (blocks: ${heads.join(', ') || 'none'})`; return res; }
    res.selectedCount = block.querySelectorAll(selSel).length;
    // own content of an element, excluding Messages sections (and, for rpc panels, HTML Display sub-panels)
    const own = (root, skipHtml) => (el) => { for (let p = el; p && p !== root; p = p.parentElement) if (p.tagName === 'DETAILS' && (isMsg(p) || (skipHtml && sumOf(p).startsWith('HTML Display')))) return false; return true; };
    const textOf = (root, keep) => {
      // the panel's own text: every text node that `keep`s, minus the panel's own summary row (joined like textContent)
      const sm = root.querySelector(':scope > summary');
      // only RENDERED text (what a user reads; UX suite W4/W5 hiddenCardClaims, bring-up audit 4 major): a text node
      // under a closed <details> is hidden unless it sits in that details' own <summary>, and display:none hides too
      const rendered = (el) => {
        for (let p = el; p && p !== root.parentElement; p = p.parentElement) {
          if (p.tagName === 'DETAILS' && !p.open) { const s2 = p.querySelector(':scope > summary'); if (!(s2 && s2.contains(el))) return false; }
          if (getComputedStyle(p).display === 'none') return false;
        }
        return true;
      };
      const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT); let out = ''; let n;
      while ((n = w.nextNode())) { const pe = n.parentElement; if (!pe || (sm && sm.contains(pe)) || !keep(pe) || !rendered(pe)) continue; out += n.nodeValue; }
      return norm(out);
    };
    const measure = (panel, keep) => {
      const tags = {};
      for (const el of panel.querySelectorAll('svg, svg *')) { if (!keep(el)) continue; const t = el.tagName.toLowerCase(); tags[t] = (tags[t] || 0) + 1; }
      return { tags, text: textOf(panel, keep) };
    };
    let candidates;
    if (exp.panelTitle) candidates = [...block.querySelectorAll('details')].filter((d) => sumOf(d) === exp.panelTitle && !underMsg(d, block)).map((d) => ({ el: d, keep: own(d, false) }));
    else candidates = [{ el: block, keep: own(block, true) }];
    const want2 = [...(exp.texts || []), ...extraTexts];
    let best = null;
    for (const c of candidates) {
      const m = measure(c.el, c.keep);
      const hay = cmp(m.text);
      const missingTexts = want2.filter((t) => !hay.includes(cmp(t)));
      const svgDiff = {};
      if (exp.svgTagCounts) for (const k of new Set([...DRAW_TAGS, ...Object.keys(exp.svgTagCounts)])) if ((m.tags[k] || 0) !== (exp.svgTagCounts[k] || 0)) svgDiff[k] = { want: exp.svgTagCounts[k] || 0, got: m.tags[k] || 0 };
      const r = { el: c.el, keep: c.keep, m, missingTexts, svgDiff, score: missingTexts.length + Object.keys(svgDiff).length };
      if (!best || r.score < best.score) best = r;
    }
    if (!best) { res.reason = `info block ${want} has no “${exp.panelTitle}” panel`; return res; }
    const el = best.el;
    el.setAttribute('data-bringup-panel', '1');
    const r = el.getBoundingClientRect();
    // where the drawing starts: the topmost painted svg shape, else the first table, else the first content block;
    // never above the bottom of the panel's own summary row (so the thumbnail never shows a sliced summary)
    const sm = el.querySelector(':scope > summary');
    const floor = sm ? sm.getBoundingClientRect().bottom + 1 : r.y;
    const g = el.querySelector('svg, table');
    let gTop = null; let gBox = null;
    if (g && g.tagName.toLowerCase() === 'svg') {
      // the whole drawing: the union of every painted shape (thumbnails letterbox it, bring-up audit 5 minor)
      // over EVERY svg of the panel (dist-lens draws its bars and its CDF in two svgs), Messages sections excluded
      for (const n of el.querySelectorAll('svg rect, svg line, svg path, svg text, svg circle, svg ellipse, svg polyline, svg polygon')) {
        if (!best.keep(n)) continue; // the panel's own shapes (no Messages, no nested HTML Display of an rpc block)
        const nr = n.getBoundingClientRect(); if (!(nr.height > 0 || nr.width > 0)) continue;
        gTop = gTop === null ? nr.y : Math.min(gTop, nr.y);
        gBox = gBox ? { l: Math.min(gBox.l, nr.left), t: Math.min(gBox.t, nr.top), r: Math.max(gBox.r, nr.right), b: Math.max(gBox.b, nr.bottom) } : { l: nr.left, t: nr.top, r: nr.right, b: nr.bottom };
      }
      if (gTop !== null) gTop -= 6;
    } else if (g) gTop = g.getBoundingClientRect().y - 6;
    if (gTop === null) { const first = [...el.children].find((c) => c.tagName !== 'SUMMARY' && c.getBoundingClientRect().height > 0); gTop = first ? first.getBoundingClientRect().y : floor; }
    Object.assign(res, {
      ok: best.score === 0, reason: best.score ? `panel mismatch: missing ${JSON.stringify(best.missingTexts)} svg ${JSON.stringify(best.svgDiff)}` : null,
      panelTitle: exp.panelTitle ? sumOf(el) : null, svgTags: best.m.tags, missingTexts: best.missingTexts, svgDiff: best.svgDiff,
      graphicTop: Math.max(0, Math.max(gTop, floor) - r.y),
      // the drawing's box relative to the panel (padded 8 px, clamped to the panel), null if the panel has no svg
      graphicBox: gBox ? (() => { const P = 8; const x0 = Math.max(0, gBox.l - r.x - P), y0 = Math.max(0, Math.max(gBox.t - P, floor) - r.y), x1 = Math.min(r.width, gBox.r - r.x + P), y1 = Math.min(r.height, gBox.b - r.y + P); return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0), overflowX: gBox.r > r.right + 1 || gBox.l < r.left - 1 }; })() : null,
      rect: { x: r.x, y: r.y, w: r.width, h: r.height }, text: best.m.text.slice(0, 2000),
      links: [...el.querySelectorAll('a')].map((x) => norm(x.textContent || x.getAttribute('title') || '')).filter(Boolean).slice(0, 80),
    });
    // an rpc expectation must not be satisfied by an empty block (e.g. only goals): require svg shapes or texts
    if (!exp.panelTitle && !(exp.texts || []).length && !Object.keys(exp.svgTagCounts || {}).length) { res.ok = false; res.reason = 'empty rpc expectation'; }
    return res;
  }, { exp, extraTexts, squash, DRAW_TAGS, selSel: SEL.infoview.selectedSubterm }).catch((e) => ({ ok: false, reason: `evaluate failed: ${e.message.slice(0, 200)}` }));
}
