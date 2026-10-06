// gallery.js — the M2 gallery wrapper (BUILD-PLAN §7.3; stage A X3/X4/X5).
//
// The right pane is the STOCK QED64 page, same origin, iframed at /?snapshots=snapshots/<overlay>. Nothing in
// QED64 is changed; everything here drives the page through what it already exposes:
//   globalThis.qed64 = { artifacts, relay, ui, status: () => relay.status(), get editor() }  (bundle, main.ts:403-410)
//   localStorage['qed64.buffer'] is the page's boot document (main.ts:335-342).
//
// Boot:  browser capability check (lib.js checkCapabilities: crossOriginIsolated, SharedArrayBuffer, WebAssembly Memory64,
//        navigator.deviceMemory where exposed; a failure shows a card and nothing boots) → data (pin.json, examples.json) → JS pairing preflight (lib.js) → seed qed64.buffer (saving the user's
//        own buffer under qed64-showcase:saved) → iframe src → install the RPC bridge on the page window as soon as
//        the page document commits → wait for qed64.status().phase === 'ready' (with our text) → cursor + focus.
// Switch: editor.getModel().setValue(text) → wait for 'ready' at a newer version with relay.lastText === text →
//        cursor. A newer selection supersedes an in-flight wait (switch storms settle on the last one).
// ?overlay=<dir> (default widgets8, fallback widgets7)   ?mem=<GiB> (X5 memory knob, see memBoot)
// ?liveness=auto|observe|off (the L7 liveness probe, see PROBE_AFTER_MS)
// #<pkg> deep links.   window.__showcase = { select, reset, restoreSaved, status, bridgeStats, currentText, examples, liveness,
// offer, acceptOffer } for Playwright (contract: tests/ux/selectors.json showcaseApi, version 9).
//
// TWO MODES, decided from gallery/pin.json (scripts/build-gallery.mjs reads release/<pin>/dist/qed64-build.json), except
// when the local server serves ANOTHER pin's release than pin.json describes (X-Showcase-Pin; a staged pin served by
// SHOWCASE_PIN=<id>): then from that release's own revision (servedBuild: serve.mjs's X-Showcase-Api header on the pin.json
// response; only without it, the release's /qed64-build.json, 404 = legacy):
//   * V1 (apiRevision != null; QED64 embedding contract v1, deps/qed64/docs/EMBEDDING.md): the frame is
//     /?embed=1&snapshots=snapshots/<overlay>[&memory=<GiB>]#code=<example>. The gallery drives the page ONLY through the
//     frozen globalThis.qed64.api it receives in the 'qed64:frame-api' CustomEvent on this window (fallback: a polled
//     pageWin().qed64.api when Object.isFrozen), never through qed64.relay / qed64.ui / qed64.status() / qed64.editor /
//     qed64.buffer / the page's #boot DOM / any __qed64* name (§9: internal). Waits stay polling-based on api.status()
//     (synchronous, valid before boot) so Superseded and the progress-aware boot timeout keep working; progress and
//     liveness come from the api's events (boot, status, document, fileProgress, diagnostics, liveness, reboot, death,
//     offer). The RPC bridge stands down (capabilities.editorRpc + widgetSourceCache), the liveness probe stands down
//     (status().liveness: QED64's own), ?mem= becomes &memory=, persistence is the 'document' event into our own key
//     (qed64-showcase:document), and a reload we did not start is adopted by calling api.setDocument SYNCHRONOUSLY in the
//     frame-api handler (the page gives an embedder 5 s from module start, §3.1). The one internal dependency left is the
//     narrow-screen stacking <style> (applyStack / applyPageStyle: runtime styling of the page document; layout= is v1.1),
//     which never throws and never fails a boot when the ids are missing.
//   * legacy (apiRevision == null; pins A–E): exactly the flow described above (qed64.buffer seed, relay waits, the
//     bridge, the hover/main-loop liveness probe, the ?mem session wrap). Byte-for-byte the previous behaviour.
// Every helper below (api(), apiStatus(), qStatus(), docText(), editorText(), placeCursor(), restartLean(), …) branches on
// S.v1 at the lowest level, so the control flow above them (driver, waits, cards, keyboard, test API) is shared.
import * as L from './lib.js';

const $ = (id) => document.getElementById(id);
const E = {
  list: $('card-list'), tpl: $('card-template'), select: $('example-select'), mobileBlurb: $('mobile-blurb'),
  mobileHints: $('mobile-hints'), mobileHintList: $('mobile-hint-list'), frame: $('qed64-frame'),
  statusLine: $('status-line'), statusText: $('status-text'), live: $('live-region'),
  reset: $('reset-btn'), copy: $('copy-btn'), copyLabel: $('copy-label'),
  notice: $('notice'), noticeText: $('notice-text'), noticeClose: $('notice-close'), noticeAction: $('notice-action'),
  veil: $('stage-veil'), veilText: $('veil-text'),
  err: $('error-card'), errTitle: $('error-title'), errDetail: $('error-detail'), errChecks: $('error-checks'),
  errTech: $('error-tech'), errRaw: $('error-raw'), errRetry: $('error-retry'), errStock: $('error-stock'), errDismiss: $('error-dismiss'),
  errReset: $('error-reset'), errNote: $('error-note'),
  pinBadge: $('pin-badge'), overlayBadge: $('overlay-badge'), restore: $('restore-btn'), restorePick: $('restore-pick'),
};

const params = new URLSearchParams(location.search);
const SWITCH_TIMEOUT_MS = 330000;  // DistLens elaboration budget 300 s (plan §8.2) + slack
const HOOK_TIMEOUT_MS = 120000;    // the page publishes globalThis.qed64 right after the relay is constructed
// Stall watchdog (UX audit blocker, QED64 limitation L7): QED64's whole Lean runtime can freeze in 'elaborating' (every
// pthread stops; out/ux/auditor-full: v60 'elaborating', relay 'serving', no death, no LSP message for 120 s; root cause in
// out/hang/ROOT-CAUSE.md). The relay's heartbeat comes from the worker's JS thread, which stays alive, so QED64 never
// notices. Since the liveness probe below restarts a frozen runtime after ~20 s, this card is its fallback. It watches
// for ELABORATION progress (a $/lean/fileProgress or publishDiagnostics message, or a new phase/version/session)
// while QED64 reports 'elaborating' on a serving relay, and after STALL_MS without any offers "Restart Lean" (a
// relay restart: a fresh worker on the same text). No example needs more than ~2.5 s per command (C20), so 45 s of
// silence is not normal work; "Keep waiting" re-arms it. ?stall=<seconds> (>= 5) overrides it (tests).
const STALL_MS = (() => { const v = Number(params.get('stall')); return Number.isFinite(v) && v >= 5 ? Math.round(v * 1000) : 45000; })();
// Liveness probe with automatic restart (L7 mitigation on the current runtime; docs/NEXT-STEPS.md §1, out/hang/ROOT-CAUSE.md
// V7/W7). While QED64 reports 'elaborating' on a serving relay and no progress has been seen for PROBE_AFTER_MS, the gallery
// sends `textDocument/hover` for the open document at 0:0 through the relay, with a STRING id ("showcase-live-<n>", which
// cannot collide with the client's numeric ids) and full params (a Lean FileWorker request without params ends in "Got
// invalid JSON-RPC message" and kills the worker). The reply is swallowed in the relay.toClient tap. A hover answer needs
// a Lean task thread and a proxied fd_write, exactly the path that dies in L7; it is answered while elaboration is busy
// elsewhere (UX suite C22). An answer (or any progress) means alive: re-arm. PROBE_MISSES consecutive probes unanswered
// within PROBE_TIMEOUT_MS each means wedged: restart with the session's own snapshots (the text is kept) and show a small
// notice. At most one automatic restart per RESTART_GAP_MS; after that, and whenever the restart itself fails, the 45 s
// card is the fallback. ?liveness=observe detects and records but never restarts (hang hunts); ?liveness=off disables it.
// ?probe=<s> / ?probeTimeout=<s> / ?restartGap=<s> override the timings (tests). Test API: __showcase.liveness(mode).
const knob = (k, d, min) => { if (!params.has(k)) return d; const v = Number(params.get(k)); return Number.isFinite(v) && v >= min ? Math.round(v * 1000) : d; };
const LIVE_MODES = ['auto', 'observe', 'off'];
const PROBE_AFTER_MS = knob('probe', 10000, 1);
const PROBE_TIMEOUT_MS = knob('probeTimeout', 5000, 0.5);
const RESTART_GAP_MS = knob('restartGap', 120000, 1);
// First boot on a slow link (last-mile lane defect, out/ux/last-mile/RESULTS.md (4)): a first visit downloads ~710 MB and
// at 10 Mbit/s QED64 is ready after ~577 s, so a fixed 360 s budget stranded a healthy visitor on "This is taking too long"
// (and a later 'ready' never closed it). The boot wait is therefore PROGRESS-AWARE (bootProgress below): the budget is
// re-armed by every sign of progress the gallery can see from the same origin (new download bytes reported to the page's
// status sink qed64.ui, a new boot-stage label, a new QED64 phase/relay/session/version, a page resource from a URL not seen before), and the
// error card shows only after BOOT_TIMEOUT_MS AND BOOT_STALL_MS without any progress (a true stall). While bytes still
// arrive, a non-blocking notice says "Still downloading: <QED64's step> — X MB of Y so far" instead (QED64's own step
// label and figures, the ones its boot card shows; they count prepared bytes, not network bytes): from BOOT_TIMEOUT_MS on, and from
// BOOT_NOTICE_MS on once QED64's own boot overlay is gone (the stock page removes it 120 s after its editor opens, long
// before a slow download ends). If the card was shown and QED64 later reaches 'ready' on the same page, the card closes
// and the normal flow continues (cursor, panel; status().boot.recovered). ?bootTimeout / ?bootStall / ?bootNotice =<s>
// override the timings (tests).
const BOOT_TIMEOUT_MS = knob('bootTimeout', 360000, 0.1); // cold boot of a 1.2–1.6 GB region, plan C1 budget 180 s locally, ×2
const BOOT_STALL_MS = knob('bootStall', 240000, 0.1);     // no progress at all for this long (after BOOT_TIMEOUT_MS) = a true stall
const BOOT_NOTICE_MS = knob('bootNotice', 120000, 0.1);   // the early notice once QED64's own boot overlay is gone
const BOOT_RECENT_MS = Math.min(30000, BOOT_STALL_MS);    // "bytes still arrive" = new bytes within this window
const PROBE_MISSES = 2;
const PROBE_PREFIX = 'showcase-live-';
// QED64's OWN liveness (QED64 9fdf9b8, its kernel-0035 runtime, HARDENING #52; the L7 fix). Its worker serves the
// runtime mailbox every 1 s (a lost wakeup is "rescued" and counted), probes the FileWorker after 6 s without any server
// frame, logs a stall when that probe stays unanswered 12 s, and 4 s later kills the session (died "wedged"); the relay then
// reboots (status().relay 'rebooting', rebootReason 'wedged', the page's pill "the checker stopped responding — restarting")
// and replays the text. Feature detection: status().liveness ({probes, answered, stalls, resumed, rescues}) is present. On
// such a page the gallery DEFERS: its own probe becomes a slower fallback that starts only after PROBE_DEFER_MS without
// progress (past QED64's worst-case window: 6 + 12 + 4 s, each up to one 1 s tick late, about 25 s), never acts while QED64
// reports a stall in its grace window (stalls > resumed), and QED64's own rescues, stalls and "wedged" reboots are observed
// and reported (status().liveness.qed64, events qed64-*) with a notice. The 45 s card is unchanged. ?probeDefer=<s>.
// PROOF OF LIFE besides a hover answer (final audit, major): a hover waits for a free Lean task thread, so when the pool is
// saturated by parallel proofs (24 parallel `sleep` theorems: pool {unused 0, running 27}) the hover goes unanswered while
// Lean is healthy. A probe that times out therefore counts as MISSED only if, since the first probe of the sequence, the
// page has seen no server frame of any kind (the relay.toClient tap) AND, on a QED64 page with its own liveness, QED64's
// own probe (an unknown method the FileWorker's main loop answers at once, without a pool thread) was not answered within
// LIFE_LOOKBACK_MS (one probe window, 2 x 5 s) before that first probe or at any time since. Otherwise the probe is settled as 'alive' (event alive,
// via frame | qed64-answered) and the probe re-arms. QED64 probes after 6 s without a frame, so a live Lean side answers
// one about every 6-10 s. A real L7 stops both (no frames, QED64's probe unanswered: QED64 stalls, and we defer to it).
// A page WITHOUT QED64's liveness (pin 1859b83, kernel 0034, no #52 worker) has the frame signal and one more: a LATE but
// real answer from Lean to one of our own probes (a hover that waited for a free task thread past PROBE_TIMEOUT_MS) proves
// the Lean side alive just as well as a frame (multi-pin lane, the critic's minor): it is recorded (lastLateAnswerAt) and a
// probe sequence that saw one settles 'alive' via 'late-answer' instead of declaring the session wedged. Only a
// non-error reply counts (an error reply may be a restart's failInFlight; QED64-synthesized ones never count). A pool
// saturated for longer than the whole sequence (2 x 5 s) with no frame and no late answer can still look wedged there
// (documented in gallery/README.md, L7); on a page WITH QED64's liveness its probe answers cover that case.
// Only frames that come FROM LEAN count (close-out 3, audit minor): QED64's JS layer, which stays alive during an L7
// freeze, synthesizes some frames itself, and those prove nothing about the Lean side. They are counted separately
// (status().liveness.syntheticFrames) and never settle a probe 'alive' or answer it (see qed64Synthetic).
// MAIN-LOOP PROBE (hardening lane, 2026-10-02; the fix for pin 1859b83's UX C22 (3)): with every hover probe the gallery
// also sends a request the FileWorker's MAIN LOOP answers at once, without a pool thread: an unknown method WITH params
// (MAIN_METHOD, string id "showcase-main-<n>"). Lean's FileWorker.handleRequest finds no handler for it and replies
// MethodNotFound (-32601) synchronously from the main loop (Lean 4.34 FileWorker.lean emitRequestResponse, the
// Except.error branch), through the normal output path; without params the FileWorker would die ("Got invalid JSON-RPC
// message"). This is the same kind of request QED64's own liveness writes ($/qed64/liveness, lean.worker.js), so on a
// page WITHOUT QED64's liveness a pool saturated by parallel proofs (the hover waits ~55 s for a free task thread) still
// gets a prompt proof of life, and the gallery never restarts a healthy session. A real L7 freeze stops it too (the main
// loop's reply needs the same proxied output path, and its channel send touches the task manager). The reply is swallowed
// by the relay.toClient tap like the hover's; replies QED64's JS layer makes (failInFlight on a restart or death, the
// halted relay) are not answers (qed64Synthetic). The hover stays the second signal.
const MAIN_PREFIX = 'showcase-main-';
const MAIN_METHOD = '$/showcase/liveness';
const PROBE_DEFER_MS = knob('probeDefer', 30000, 1);
const LIFE_LOOKBACK_MS = PROBE_MISSES * PROBE_TIMEOUT_MS; // 10 s at the defaults (scales with ?probeTimeout in tests)
// The 45 s card's wording (final audit, minor): when Lean gave a sign of life (a probe answer, a server frame, a QED64
// probe answer) within ALIVE_RECENT_MS, the card says "Lean is still working" (a long
// command), not "stopped making progress"; it re-words itself if that changes while it is up. Same buttons either way.
const ALIVE_RECENT_MS = 4 * PROBE_TIMEOUT_MS; // 20 s at the defaults (scales with ?probeTimeout in tests)
const QED64_LIVE_KEYS = ['probes', 'answered', 'stalls', 'resumed', 'rescues'];
/** A frame QED64's JS layer made itself, not the Lean FileWorker (deps/qed64 at the pin): the front door's
 *  ContentModified (-32801) replies to completions it fails fast (lsp-front-door.js:288), the relay's -32603 halted
 *  replies (lsp-relay.ts:112) and failInFlight's -32603 / -32900 replies (lsp-relay.ts:212) — all error replies whose
 *  message starts 'QED64:' — and the relay's halted note (a publishDiagnostics whose every diagnostic has source 'QED64',
 *  lsp-relay.ts haltedNote). The worker's own initialize / shutdown answers come only at a session's start or end. */
function qed64Synthetic(m) {
  if (!m) return false;
  if (m.method === undefined && m.error && typeof m.error.message === 'string' && m.error.message.startsWith('QED64:')) return true;
  if (m.method === 'textDocument/publishDiagnostics') {
    const d = m.params && m.params.diagnostics;
    return Array.isArray(d) && d.length > 0 && d.every((x) => x && x.source === 'QED64');
  }
  return false;
}

class Superseded extends Error { constructor() { super('superseded by a newer selection'); this.code = 'SUPERSEDED'; } }
class GalleryError extends Error {
  constructor(kind, title, detail, extra = {}) { super(`${title}: ${detail}`); this.kind = kind; this.title = title; this.detail = detail; Object.assign(this, extra); }
}

const S = {
  pin: null, examples: [], byId: new Map(), exampleTexts: new Set(),
  v1: false,              // the page carries an apiRevision (pin.json; the SERVED release's own when serve.mjs serves another pin): drive it through globalThis.qed64.api
  // where the mode came from: 'served' (X-Showcase-Api of the served release, else its /qed64-build.json; 404 = a legacy page) or 'pin.json'
  modeSource: null, servedRevision: null,
  navigating: false,      // between our own `iframe.src = …` and the page's hook: a frame-api event then is OURS, not a reload
  // the page API of the CURRENT frame document (V1): obj = the frozen api, via = how we got it, counts = events seen
  // doc = the frame document that published obj: api() is null while another document is in the frame (a reload before its module ran)
  api: { obj: null, doc: null, via: null, t: null, revision: null, capabilities: null, missing: [], embed: false, docs: 0, adopted: 0, adoptSet: null, counts: {}, lastOffer: null, deaths: 0 },
  // the document as the 'document' event reports it (V1): the relay forwarded this text; persisted = our own key holds it
  // lastText = the newest forwarded text IN MEMORY (an adopted reload re-seeds it first: a failed write or another tab's key never replaces it)
  // held = {at, error}: a boot could not keep the text it displaced (seedBuffer threw, e.g. QuotaExceededError), so our key,
  // the only stored copy of the user's text, is NOT written again in this tab (holdDocument); memory (lastText) still follows
  // unsaved = {text, error, at}: a text that existed ONLY in this tab's memory (not in our key) and that a boot could not keep
  // (seedBuffer); the notice offers to copy it, the next boot retries keeping it, and leaving the page asks first
  // holdTimer: while held, the one pending retry of a write the HOLD_RETRY_MS rate limit skipped (persistDocument)
  doc: { version: null, length: null, lastEventAt: null, persisted: false, lastWriteAt: -Infinity, writes: 0, timer: null, holdTimer: null, pendingText: null, lastText: null, lastWritten: null, error: null, held: null, unsaved: null },
  requestedOverlay: params.get('overlay') || null,
  mem: { ...L.parseMem(params.get('mem')), applied: null, sessions: [], light: null, wrapped: false, telemetry: null },
  overlay: null, choice: null, availability: null,
  current: null,          // the example the user selected (UI)
  shownId: null,          // the example whose text the worker has checked
  phase: 'starting',      // starting | preflight | booting | switching | ready | refused | halted | error
  error: null, notice: null,
  booted: false, everReady: false, bootDoc: null,
  wanted: null, token: 0, waiters: [], driving: false,
  op: { label: 'starting', t0: performance.now(), doneMs: null },
  bootMs: null, lastSwitchMs: null,
  bridge: { installs: [], docs: new WeakSet(), watching: false, stoodDown: false, capabilityMismatch: null, lateWanted: null },
  lastStatus: null, seed: null,
  adopting: false, custom: false, edited: false,
  selLog: [],             // every selection and how it settled (test API: a UI storm's outcomes, C4)
  stall: { thresholdMs: STALL_MS, active: false, key: null, lastProgressAt: 0, tapped: null, progressMsgs: 0, shown: 0, restarts: 0, events: [], source: 'relay-tap' },
  // boot progress (slow links; see BOOT_TIMEOUT_MS): what the gallery saw QED64 do while it waited for the first 'ready'
  boot: {
    timeoutMs: BOOT_TIMEOUT_MS, stallMs: BOOT_STALL_MS, noticeMs: BOOT_NOTICE_MS,
    waiting: null, t0: 0, lastProgressAt: 0, lastBytesAt: -Infinity, bytes: 0, hw: new Map(), labels: new Set(), keys: new Set(), resources: 0, resourceUrls: new Set(),
    // bytes: the sum of the per-step high-water marks QED64 reported (prepared bytes, not network bytes)
    current: null, label: null, ui: null, uiCalls: 0, uiWrapped: [], sources: { bytes: 0, label: 0, status: 0, resource: 0 },
    noticeShown: 0, stalls: 0, recovered: 0, late: null, events: [], source: 'ui-tap', apiBootEvents: 0,
  },
  live: {
    mode: LIVE_MODES.includes(params.get('liveness')) ? params.get('liveness') : 'auto',
    probeAfterMs: PROBE_AFTER_MS, probeTimeoutMs: PROBE_TIMEOUT_MS, restartGapMs: RESTART_GAP_MS, misses: 0, key: null,
    seq: 0, sent: 0, answered: 0, missed: 0, late: 0, wedged: 0, wedgedActive: false, restarts: 0, rateLimited: 0, restartFailed: 0,
    outstanding: null, armAt: 0, lastAnswerMs: null, maxAnswerMs: null, lastAutoRestartAt: -Infinity, unavailable: null, events: [],
    probeDeferMs: PROBE_DEFER_MS, deferred: 0,
    // proof of life besides a hover answer (see LIFE_LOOKBACK_MS): server frames seen by the tap, probes settled 'alive'
    frames: 0, lastFrameAt: -Infinity, syntheticFrames: 0, syntheticReplies: 0, seqStart: 0, alive: 0, aliveVia: { frame: 0, 'qed64-answered': 0, 'late-answer': 0, 'main-loop': 0 }, lastAliveAt: -Infinity,
    lastLateAnswerAt: -Infinity, lateAnswers: 0, probeSentAt: new Map(), // hover probe id -> sent time (the last 20; a late reply's elapsed ms)
    // the main-loop probe (see MAIN_METHOD): sent with every hover probe; any reply from Lean is proof of life
    main: { sent: 0, answered: 0, synthetic: 0, lastAnsweredAt: -Infinity, lastMs: null, maxMs: null, sentAt: new Map() },
    // QED64's own liveness, as observed (see PROBE_DEFER_MS): builtIn once status().liveness has been seen on this page
    qed64: { builtIn: false, detectedAt: null, session: null, servingSession: null, counters: null, totals: { probes: 0, answered: 0, stalls: 0, resumed: 0, rescues: 0 }, lastAnsweredAt: -Infinity, wedgedReboots: 0, rebooting: false, lastReboot: null,
      // V1: the api's liveness projection (EMBEDDING.md §2.2 LivenessInfo), mirrored on every monitor tick
      api: false, stalled: null, lastAnswerAgoMs: null, lastFrameAgoMs: null, probeAfterMs: null, wedgeAfterMs: null, graceMs: null },
  },
};

// ---------------------------------------------------------------- small helpers
const now = () => performance.now();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fmtS = (ms) => (ms == null ? '–' : ms < 10000 ? `${(ms / 1000).toFixed(1)} s` : `${Math.round(ms / 1000)} s`);
const fmtMB = (b) => (b >= 1e9 ? `${(b / 1e9).toFixed(2)} GB` : `${Math.round(b / 1e6)} MB`);
function announce(msg) { E.live.textContent = ''; setTimeout(() => { E.live.textContent = msg; }, 30); }
function frameWin() { try { return E.frame.contentWindow || null; } catch { return null; } }
/** The QED64 page window, only once the page document (not the initial about:blank) has committed. */
function pageWin() {
  const w = frameWin(); if (!w) return null;
  try { const href = w.location.href; if (!href || href === 'about:blank' || !href.startsWith(`${location.origin}/`)) return null; } catch { return null; }
  return w;
}
/** LEGACY ONLY: the page's internal globalThis.qed64 (relay, ui, editor, status()); null in V1 mode (EMBEDDING.md §9). */
function qed() { if (S.v1) return null; const w = pageWin(); try { return w && w.qed64 && typeof w.qed64.status === 'function' ? w.qed64 : null; } catch { return null; } }
/** V1: the frozen page API of the current frame document (EMBEDDING.md §2.1), once a page document is committed; else null.
 *  Bound to the document that published it: the frame's WindowProxy outlives a reload, so while a reloaded document has not
 *  run its module yet (the bundle still loading, or failing to) the previous, unloaded page's api must not answer for it. */
function api() {
  if (!S.v1 || !S.api.obj) return null;
  const w = pageWin(); if (!w) return null;
  try { return w.document === S.api.doc ? S.api.obj : null; } catch { return null; }
}
/** V1: api.status() — synchronous, never throws in the page, valid before boot (§2.2 ApiStatus). */
function apiStatus() { const a = api(); if (!a) return null; try { return a.status(); } catch { return null; } }
/** The page's status in either mode: ApiStatus (V1) or qed64.status() (legacy); the fields the gallery reads are the same. */
function qStatus() { if (S.v1) return apiStatus(); const q = qed(); if (!q) return null; try { return q.status(); } catch { return null; } }
/** LEGACY ONLY: Monaco's editor (qed64.editor is internal); null in V1 mode, where the api moves the cursor and the text. */
function editor() { if (S.v1) return null; const q = qed(); try { return q ? q.editor || null : null; } catch { return null; } }
/** The text the checker works on: V1 api.getDocument().text (the editor's buffer); legacy relay.lastText (what the relay forwarded). */
function docText() {
  if (S.v1) { const a = api(); try { const d = a ? a.getDocument() : null; return d ? d.text : null; } catch { return null; } }
  try { const q = qed(); return q && q.relay ? q.relay.lastText : null; } catch { return null; }
}
/** The editor buffer's text: V1 api.getDocument().text; legacy model.getValue(). */
function editorText() {
  if (S.v1) return docText();
  const ed = editor(); try { return ed && ed.getModel() ? ed.getModel().getValue() : null; } catch { return null; }
}
/** Is there an editor to drive (cursor, text)? V1: the api reports a document; legacy: qed64.editor exists. */
function editorPresent() { return S.v1 ? docText() !== null : !!editor(); }
/** The identity of the current frame document: V1 the api object (one per page document); legacy the page's document. */
function bootToken() { if (S.v1) return api(); const pw = pageWin(); try { return pw && pw.document || null; } catch { return null; } }
function setOp(label) { S.op = { label, t0: now(), doneMs: null }; }
function finishOp() { S.op.doneMs = now() - S.op.t0; return S.op.doneMs; }

// ---------------------------------------------------------------- V1: the page API (EMBEDDING.md §2) and its events
// The page defines globalThis.qed64.api synchronously at module start and, framed same-origin, dispatches
// CustomEvent 'qed64:frame-api' {detail: {api, frame}} on window.parent at that moment: before the boot document is read
// (§2.1, §3.1). We accept only detail.frame === the iframe's contentWindow. Fallback: the 250 ms monitor and the hook wait
// poll pageWin().qed64.api and accept it when Object.isFrozen (a v1 api is frozen; the legacy page has no .api).
window.addEventListener('qed64:frame-api', (ev) => {
  let d = null; try { d = ev && ev.detail; } catch { d = null; }
  if (!d || !d.api) return;
  let mine = false; try { mine = d.frame === frameWin(); } catch { mine = false; }
  if (!mine) return;
  onApi(d.api, 'frame-api');
});
function pollApi() {
  if (!S.v1) return;
  const w = pageWin(); let a = null; try { a = w && w.qed64 ? w.qed64.api : null; } catch { a = null; }
  if (a && a !== S.api.obj) { let frozen = false; try { frozen = Object.isFrozen(a); } catch { frozen = false; } if (frozen) onApi(a, 'poll'); }
}
/** A page API arrived for the current frame document (one per document). Returns true when it was adopted. */
function onApi(a, via) {
  if (!S.v1 || !a || typeof a !== 'object' || a === S.api.obj) return false;
  let ok = false; try { ok = Object.isFrozen(a) && typeof a.status === 'function' && typeof a.setDocument === 'function'; } catch { ok = false; }
  if (!ok) return false;
  const A = S.api; const prev = A.obj;
  let pdoc = null; try { const w = pageWin(); pdoc = w ? w.document : null; } catch { pdoc = null; }
  A.obj = a; A.doc = pdoc; A.via = via; A.t = Math.round(now()); A.docs++; A.counts = {}; A.lastOffer = null;
  try { A.revision = a.revision ?? null; A.capabilities = a.capabilities ? { ...a.capabilities } : null; } catch { A.revision = null; A.capabilities = null; }
  let search = ''; try { search = frameWin().location.search; } catch { search = ''; }
  A.embed = /[?&]embed=1(?:&|$)/.test(search);
  // QED64's own liveness is a capability (§1.2, §2.1): builtIn/api follow capabilities.liveness. The gallery's probe has no
  // transport in V1 either way (relay.fromClient is internal, §9), so it stands down; without the capability it is
  // reported as 'unavailable' (liveSnapshot) and the 45 s card is the only fallback.
  const L1 = S.live.qed64; const hasLive = !!(A.capabilities && A.capabilities.liveness); L1.builtIn = hasLive; L1.api = hasLive;
  if (!L1.detectedAt) { L1.detectedAt = A.t; liveEvent({ source: 'qed64-detected', via: 'api', liveness: hasLive, capabilities: A.capabilities }); }
  subscribeApi(a);
  // the frame's own pagehide (an embedder may add listeners to the framed window, §9): flush a throttled 'document' text
  // before the next document's frame-api reads it (the gallery window gets no pagehide when only the frame reloads)
  try { const fw = frameWin(); if (fw && typeof fw.addEventListener === 'function') fw.addEventListener('pagehide', flushDocument); } catch { /* ignore */ }
  if (!S.navigating && (prev || S.booted)) {
    // A frame document the gallery did not navigate to (the page's own Reload button, a user reload of the frame). In embed
    // mode the page boots the EMPTY document unless an embedder's setDocument arrives within 5 s of module start (§3.1),
    // and this handler runs at that very moment (before the boot document is read), so the call is made HERE,
    // synchronously: the document the relay last forwarded on this gallery (our own key, 'document' events), else the
    // current example. adoptReload() then follows the page as before (the text may hold the user's edits: never overwrite).
    // The NEWEST forwarded text wins: a 'document' text still waiting in persistDocument's 1 s throttle is flushed and used
    // (the previous frame's pagehide normally flushed it already; this is the belt to that brace).
    // In-memory first (S.doc.lastText: the newest text THIS gallery saw forwarded, kept even when its write failed, e.g. a
    // quota error on a multi-MB document or blocked storage), the key only as a cross-load fallback (it is shared by every
    // gallery tab of the origin, so another tab's text must never replace ours).
    const pending = S.doc.pendingText; if (pending !== null) persistDocument(pending, { force: true });
    const ex = S.byId.get(S.current);
    const mem = S.doc.lastText ?? pending; const saved = mem ?? savedDocument(); const text = saved ?? (ex ? ex.text : null);
    A.adopted++;
    if (text !== null) {
      try { const p = a.setDocument(text); if (p && typeof p.catch === 'function') p.catch(() => {}); A.adoptSet = { t: A.t, length: text.length, from: saved !== null ? 'saved' : 'example', via: mem !== null ? 'memory' : saved !== null ? 'storage' : 'example' }; }
      catch (e) { A.adoptSet = { t: A.t, error: String(e && e.message || e).slice(0, 200) }; }
    } else A.adoptSet = { t: A.t, from: null, skipped: 'no text' };
    if (S.booted) adoptReload();
  }
  return true;
}
/** Subscribe to the api's events (§2.4). Listeners never throw into the page; every payload is a fresh copy already. */
function subscribeApi(a) {
  const C = S.api.counts;
  const on = (type, fn) => { try { a.on(type, (p) => { C[type] = (C[type] || 0) + 1; try { fn(p); } catch { /* never break the page */ } }); } catch { /* no events capability */ } };
  on('document', (p) => { const D = S.doc; D.version = p.version ?? null; D.length = p.length ?? (typeof p.text === 'string' ? p.text.length : null); D.lastEventAt = now(); if (typeof p.text === 'string') persistDocument(p.text); });
  on('boot', apiBoot);
  on('status', (p) => { const B = S.boot; const k = `${p.phase}|${p.relay}|${p.session}|${p.version}`; if (!B.keys.has(k) && B.keys.size < 200) { B.keys.add(k); if (B.waiting) bootMark('status'); } });
  // elaboration progress and proof of life (replaces the relay.toClient tap): the Lean side sent a frame
  on('fileProgress', () => { S.stall.lastProgressAt = now(); S.stall.progressMsgs++; S.live.frames++; S.live.lastFrameAt = now(); });
  on('diagnostics', (p) => {
    if (p && p.origin === 'qed64') { S.live.syntheticFrames++; return; } // the page's own notes (the halted note): no proof of life, no progress
    S.stall.lastProgressAt = now(); S.stall.progressMsgs++; S.live.frames++; S.live.lastFrameAt = now();
  });
  on('liveness', (p) => {
    const Q = S.live.qed64; const k = p && p.kind;
    if (k === 'answered') { Q.totals.answered++; Q.lastAnsweredAt = now(); }
    else if (k === 'stall') { Q.totals.stalls++; liveEvent({ source: 'qed64-stall', session: p.session }); }
    else if (k === 'resumed') { Q.totals.resumed++; liveEvent({ source: 'qed64-resumed', session: p.session }); }
    else if (k === 'rescue') { Q.totals.rescues++; liveEvent({ source: 'qed64-rescue', session: p.session }); }
  });
  on('reboot', (p) => {
    const Q = S.live.qed64;
    liveEvent({ source: 'qed64-reboot', reason: p.reason, from: p.fromSession, to: p.toSession });
    if (p.reason === 'wedged') {
      Q.wedgedReboots++;
      const stNow = apiStatus() || S.lastStatus; // synchronous: the monitor's 250 ms-old reading may predate the death
      Q.lastReboot = { t: Math.round(now()), from: p.fromSession, to: p.toSession, reason: p.reason, version: stNow ? stNow.version : null, lastDeath: stNow ? stNow.lastDeath || null : null, counters: null };
      liveEvent({ source: 'qed64-wedged', from: p.fromSession, session: p.toSession });
      showNotice('Lean stopped responding; QED64 is restarting it. Your text is kept.', { transient: true });
      announce('Lean stopped responding. QED64 is restarting it; your text is kept.');
    }
  });
  on('death', (p) => { S.api.deaths++; liveEvent({ source: 'qed64-death', kind: p.kind, reason: p.reason, message: String(p.message || '').slice(0, 200), cause: p.cause || null, seq: p.seq, session: p.session, willReboot: p.willReboot, halted: p.halted }); });
  on('offer', (p) => { S.api.lastOffer = p ? { ...p, t: Math.round(now()) } : null; });
}
/** A 'boot' event (§2.4): the structured progress that replaces the qed64.ui wrap (bytes per stage|subject|total at their high-water mark, new labels). */
function apiBoot(p) {
  const B = S.boot; B.apiBootEvents++;
  if (typeof p.label === 'string' && p.label) {
    B.label = p.label;
    if (!B.labels.has(p.label) && B.labels.size < 200) { B.labels.add(p.label); if (B.waiting) bootMark('label'); }
  }
  if (p.unit === 'bytes' && Number.isFinite(p.loaded)) {
    const key = `${p.stage || ''}|${p.subject || ''}|${Number.isFinite(p.total) ? p.total : ''}`;
    const hw = B.hw.get(key) || 0;
    if (p.loaded > hw && (B.hw.has(key) || B.hw.size < 200)) { B.hw.set(key, p.loaded); B.bytes += p.loaded - hw; B.lastBytesAt = now(); if (B.waiting) bootMark('bytes'); }
    B.current = { label: typeof p.label === 'string' ? p.label : null, loaded: p.loaded, total: Number.isFinite(p.total) && p.total > 0 ? p.total : null };
  }
  if (p.failed) bootEvent({ source: 'api-boot-failed', stage: p.stage || null, message: p.message || null, error: p.error || null });
}
// Persistence in V1 (embed mode gives the gallery ownership, §3): every 'document' event (what the relay forwarded) goes to our
// own key, at most once per second (the last text wins on pagehide). The adopted reload above re-seeds the page from it.
const HOLD_RETRY_MS = 5000; // a held tab retries keeping the stored text at most this often (persistDocument; S.doc.holdTimer)
function persistDocument(text, { force = false } = {}) {
  const D = S.doc; D.pendingText = text; D.lastText = text;
  const write = () => {
    if (D.timer) { clearTimeout(D.timer); D.timer = null; }
    if (D.pendingText === null) return;
    const wait = D.held ? HOLD_RETRY_MS - (now() - (D.held.retriedAt ?? D.held.at)) : 0;
    if (D.held && wait <= 0) {
      // self-healing: storage may have been freed since. Keep the STORED text first (its own write); success releases the hold
      // and this write proceeds, so the edits of a held tab reach the key without a boot
      D.held.retriedAt = Math.round(now());
      if (keepDisplaced(savedDocument(), D.pendingText, null).action !== 'failed') { D.held = null; D.error = null; storageNotice(); }
    } else if (D.held && !D.holdTimer) {
      // rate-limited: ONE timer retries when the window ends, with the newest text then (an edit inside the window is not lost)
      D.holdTimer = setTimeout(() => { D.holdTimer = null; if (D.held) persistDocument(D.lastText, { force: true }); }, wait);
    }
    if (D.held) { D.persisted = false; D.lastWriteAt = now(); D.pendingText = null; return; } // memory only: the key keeps the displaced text
    try { localStorage.setItem(L.DOCUMENT_KEY, D.pendingText); D.persisted = true; D.writes++; D.error = null; D.lastWritten = D.pendingText; } catch (e) { D.persisted = false; D.error = String(e && e.message || e).slice(0, 200); }
    D.lastWriteAt = now(); D.pendingText = null;
  };
  if (force || now() - D.lastWriteAt >= 1000) { write(); return; }
  if (!D.timer) D.timer = setTimeout(write, Math.max(10, 1000 - (now() - D.lastWriteAt)));
}
/**
 * V1: a boot could not keep the text our key holds (seedBuffer: the save plan's write threw, e.g. a storage quota error on a
 * large document). Our key then holds the ONLY stored copy of that text, so it is not overwritten: the example lives in memory
 * only (S.doc.lastText, which an adopted reload reads first), every later write in this tab is skipped (persistDocument), and
 * the next boot's seedBuffer retries keeping the STORED text and, separately, this tab's own newer text; a boot that keeps the
 * stored text releases the hold, and so does a later write (persistDocument retries every HOLD_RETRY_MS: freed storage heals
 * the tab without a boot). Leaving the page while a held tab's own edits exist only in memory asks first (beforeunload). Only a key text is ever held: blocked storage (nothing stored) and a text that lived only in
 * memory are not (seedBuffer: S.doc.unsaved).
 */
function holdDocument(text, error) {
  const D = S.doc;
  if (D.timer) { clearTimeout(D.timer); D.timer = null; }
  D.held = { at: Math.round(now()), error: String(error).slice(0, 200) };
  D.lastText = text; D.pendingText = null; D.persisted = false;
  D.error = `held: the displaced document could not be kept (${D.held.error}); ${L.DOCUMENT_KEY} still holds it`.slice(0, 300);
}
/** True while leaving the page would lose a text that is in no storage key: an unsaved text, or edits made in a held tab. */
function textAtRisk() {
  const D = S.doc;
  if (!S.v1) return false;
  if (D.unsaved) return true;
  if (!D.held || typeof D.lastText !== 'string' || D.lastText === savedDocument()) return false;
  try { return L.planSave({ prev: D.lastText, seedText: null, saved: null, history: [], exampleTexts: S.exampleTexts }).action !== 'none'; } catch { return false; }
}
window.addEventListener('beforeunload', (ev) => { if (!textAtRisk()) return; ev.preventDefault(); ev.returnValue = ''; });
/** V1: the notice for a held document and/or an unsaved text (every claim matches where the text really is). */
function storageNotice() {
  const D = S.doc; const parts = [];
  if (D.held) parts.push(`Your previous document could not be saved (${D.held.error}). It is still in this browser's storage under ${L.DOCUMENT_KEY}, and this tab will not overwrite it. Until storage is freed, edits in this tab are kept only in memory, and leaving or reloading the page would lose them; once you free some storage, your next edit is saved as usual.`);
  if (D.unsaved) {
    const n = D.unsaved.text.split('\n').length - (D.unsaved.text.endsWith('\n') ? 1 : 0);
    parts.push(`Your previous text (${n} line${n === 1 ? '' : 's'}) could not be saved (${D.unsaved.error}) and is in no storage: it is kept only in this tab's memory. Copy it before you leave the page.`);
  }
  if (parts.length) showNotice(parts.join(' '), { kind: 'storage', action: D.unsaved ? { label: 'Copy it', run: copyUnsaved } : null });
  else if (S.noticeKind === 'storage') hideNotice();
}
async function copyUnsaved() {
  const u = S.doc.unsaved; if (!u) return;
  let ok = false;
  try { await navigator.clipboard.writeText(u.text); ok = true; } catch {
    const ta = document.createElement('textarea'); ta.value = u.text; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.append(ta); ta.select();
    try { ok = document.execCommand('copy'); } catch { ok = false; }
    ta.remove();
  }
  u.copied = ok;
  if (S.noticeKind === 'storage') E.noticeAction.textContent = ok ? 'Copied ✓' : 'Copy failed';
  announce(ok ? 'Your previous text was copied to the clipboard.' : 'Copy failed.');
}
function flushDocument() { if (S.doc.pendingText !== null) persistDocument(S.doc.pendingText, { force: true }); }
window.addEventListener('pagehide', flushDocument);
function savedDocument() { try { const t = localStorage.getItem(L.DOCUMENT_KEY); return typeof t === 'string' ? t : null; } catch { return null; } }
/** Wait for a page-API promise while a newer selection may supersede it (polling checkWanted every 50 ms) and bounded by timeoutMs. */
function raced(p, w, timeoutMs, label) {
  return new Promise((resolve, reject) => {
    let done = false; const t0 = now();
    const fin = (f, v) => { if (done) return; done = true; clearInterval(h); f(v); };
    const h = setInterval(() => {
      try { checkWanted(w); } catch (e) { fin(reject, e); return; }
      if (now() - t0 > timeoutMs) { const e = new Error(`timed out after ${Math.round(timeoutMs / 1000)} s waiting for ${label}`); e.code = 'TIMEOUT'; fin(reject, e); }
    }, 50);
    Promise.resolve(p).then((v) => fin(resolve, v), (e) => fin(reject, e));
  });
}
/** V1: the bridge's fate at the hook (contract item 7). Both capabilities true (pin F): stand down. Else install it late, trimmed to what is missing. */
function bridgeDecision(a) {
  let c = null; try { c = a.capabilities || null; } catch { c = null; }
  const have = { editorRpc: !!(c && c.editorRpc), widgetSourceCache: !!(c && c.widgetSourceCache) };
  if (have.editorRpc && have.widgetSourceCache) { S.bridge.stoodDown = true; S.bridge.lateWanted = null; return; }
  S.bridge.stoodDown = false;
  if (have.editorRpc) {
    // editorRpc means HARDENING #56: the InfoView's RPC crosses the iframe as start/await/cancelClientRequest (§2.5), and the
    // bridge's D3 coalescing matches only the pre-#56 sendClientRequest: installed, it would repair nothing while claiming to.
    // No repair is possible from the embedder here; say so and leave the page as it is.
    S.bridge.capabilityMismatch = { ...have, repair: 'unavailable', t: Math.round(now()) };
    S.bridge.lateWanted = null;
    console.warn('[showcase] QED64 page API has editorRpc but lacks widgetSourceCache: the InfoView widget-source repair cannot attach to this page (its RPC names changed with editorRpc); not installing it');
    return;
  }
  S.bridge.capabilityMismatch = { ...have, repair: 'late', t: Math.round(now()) };
  S.bridge.lateWanted = { edits: true, dedupe: !have.widgetSourceCache };
  console.warn(`[showcase] QED64 page API lacks ${['editorRpc', !have.widgetSourceCache && 'widgetSourceCache'].filter(Boolean).join(' and ')}: installing the InfoView repair late (edits true, dedupe ${!have.widgetSourceCache})`);
  ensureBridge('capability');
}
/** V1 (§1.2: feature-detect by capabilities): what the gallery cannot work without. documents (setDocument/getDocument),
 *  events ('document' persistence, boot progress, the stall watchdog's sources), embedMode (?embed=1: the gallery owns the
 *  document and qed64.buffer stays the visitor's), restart (Reset on a halted or stalled checker, widening). A page that
 *  lacks one gets the hard "could not start" card instead of a silently degraded gallery. */
const REQUIRED_CAPABILITIES = ['documents', 'events', 'embedMode', 'restart'];
function requireCapabilities(a) {
  let c = null; try { c = a.capabilities || null; } catch { c = null; }
  const missing = REQUIRED_CAPABILITIES.filter((k) => !(c && c[k] === true));
  S.api.missing = missing;
  if (missing.length) throw new GalleryError('boot', 'This QED64 build lacks the embedding features the gallery needs', `Its page API (revision ${S.api.revision ?? '?'}) is missing the capabilities ${missing.join(', ')}.`);
}

// ---------------------------------------------------------------- the RPC bridge (stage A X4: D1 abortSignal, D2 applyEdit)
// When: as early as possible after each navigation of the iframe commits. Why that is early enough: the bridge only
// rewrites messages the InfoView iframe (#infoview iframe, created by lean4monaco inside the page) posts to the page
// window. That iframe exists only after the page's module script has run (deferred: after the page document is
// parsed), the editor has started and the LSP session has booted (seconds). A widget RPC additionally needs the
// cursor on a widget, which the gallery sets only after 'ready'. We poll every 4 ms from the moment we set src and
// install at the first tick that sees the committed page document (readyState normally 'loading', before the
// module script runs); the frame's 'load' event, every status tick and every cursor placement re-check it. The
// install is idempotent (window.__showcaseBridge guard) and recorded per document, with the readyState it saw.
// V1 (contract item 7): NOT installed — the page repairs D1/D2 natively (capabilities.editorRpc, HARDENING #56) and coalesces
// getWidgetSource itself (capabilities.widgetSourceCache, §2.5) — unless bridgeDecision() found a capability missing.
function ensureBridge(reason) {
  if (S.v1 && !S.bridge.lateWanted) return null;
  const w = pageWin(); if (!w) return null;
  let doc; try { doc = w.document; } catch { return null; }
  if (!doc) return null;
  if (S.bridge.docs.has(doc) && w.__showcaseBridge) return w.__showcaseBridge;
  if (typeof window.installQed64Bridge !== 'function') return null;
  const had = !!w.__showcaseBridge;
  const stats = window.installQed64Bridge(w, S.v1 ? S.bridge.lateWanted : undefined);
  S.bridge.docs.add(doc);
  // A navigation we did not start (the page's own Reload button, a user reload of the frame) replaces this
  // document; its pagehide is our earliest signal, so start polling for the next commit right there.
  try { w.addEventListener('pagehide', () => setTimeout(() => watchBridge(), 0)); } catch { /* ignore */ }
  let hook = false; try { hook = !!w.qed64; } catch { /* ignore */ }
  S.bridge.installs.push({ t: Math.round(now()), reason, readyState: doc.readyState, qed64Present: hook, alreadyInstalled: had, href: (() => { try { return w.location.pathname + w.location.search; } catch { return null; } })() });
  // Installed after the page's module script ran (globalThis.qed64 already there): the page's own message listener
  // was registered first and still runs, so applyEdit links throw `unsupported` and replies are duplicated
  // (out/ux/bringup/console-a.json, mode parent-late). Say so; Reset/Retry re-navigates and installs in time.
  if (hook && !had && !S.v1) { // V1: inherent (the api exists at module start); bridgeDecision() already warned
    S.bridge.late = (S.bridge.late || 0) + 1;
    console.warn('[showcase] InfoView repair installed late (qed64 already running): reload the example if links misbehave');
    showNotice('The InfoView repair attached late on this page load; if a widget link does nothing, reload the page.', { transient: true });
  }
  return stats;
}
function watchBridge(maxMs = HOOK_TIMEOUT_MS) {
  if (S.v1) return; // no bridge to race the page's module script with; the frame-api event announces each document
  const t0 = now(); const gen = (S.bridge.watchGen = (S.bridge.watchGen || 0) + 1);
  S.bridge.polling = true; // while the 4 ms commit poll runs it owns the install (the 250 ms monitor defers to it)
  const tick = () => {
    if (gen !== S.bridge.watchGen) return;
    if (ensureBridge('commit-poll')) { S.bridge.polling = false; return; }
    if (now() - t0 < maxMs) setTimeout(tick, 4); else S.bridge.polling = false;
  };
  tick();
}
E.frame.addEventListener('load', () => {
  ensureBridge('load');
  pollApi();
  // a navigation we did not start (e.g. the page's own "Reload" button): adopt the new document (V1: the frame-api
  // handler normally adopted it already, at module start, and S.booted is false by now)
  const tok = bootToken();
  if (S.booted && tok && S.bootDoc && tok !== S.bootDoc) adoptReload();
});

// ---------------------------------------------------------------- rendering
function chipFor(ex) {
  const isCur = ex.id === S.current;
  if (isCur) {
    if (S.phase === 'error') return ['error', 'error'];
    if (S.phase === 'halted') return ['error', 'halted'];
    if (S.phase === 'refused' && S.shownId === ex.id) return ['refused', 'refused'];
    if ((S.phase === 'ready') && S.shownId === ex.id) return S.edited ? ['edited', 'edited'] : ['live', 'live'];
    if (['preflight', 'booting', 'switching', 'starting'].includes(S.phase)) return ['loading', S.phase === 'preflight' ? 'checking…' : 'loading…'];
  }
  if (S.availability) {
    const a = S.availability[ex.id];
    if (a === false) return ['missing', `not in ${S.overlay}`];
    if (a === true) return ['available', 'available'];
  }
  return ['unknown', '…']; // before the snapshot preflight has said which examples this overlay carries
}
function renderChips() {
  for (const ex of S.examples) {
    const chip = ex.el && ex.el.querySelector('.chip'); if (!chip) continue;
    const [state, text] = chipFor(ex);
    if (chip.dataset.state !== state) chip.dataset.state = state;
    if (chip.textContent !== text) chip.textContent = text;
    const opt = E.select.querySelector(`option[value="${ex.id}"]`);
    if (opt) { const t = `${ex.title}${state === 'missing' ? ` (${text})` : ''}`; if (opt.textContent !== t) opt.textContent = t; }
  }
}
function hintButton(ex, h) {
  const li = document.createElement('li');
  const b = document.createElement('button');
  b.type = 'button'; b.className = 'hint';
  b.setAttribute('aria-label', `${h.label}. ${h.detail} Moves the editor cursor to line ${h.lineNumber}.`);
  const k = document.createElement('span'); k.className = 'hint-kind'; k.textContent = h.kind === 'cursor' ? 'cursor' : h.kind === 'select' ? 'select' : h.kind === 'hover' ? 'hover' : 'click';
  const t = document.createElement('span'); t.textContent = h.label;
  const d = document.createElement('span'); d.className = 'hint-detail'; d.textContent = h.detail;
  b.append(k, t, d);
  b.addEventListener('click', () => gotoHint(ex.id, h));
  li.append(b);
  return li;
}
const HINTS_FOLDED = 4;
function renderHints(ex, ul, all) {
  ul.replaceChildren(...(all ? ex.tryThis : ex.tryThis.slice(0, HINTS_FOLDED)).map((h) => hintButton(ex, h)));
}
function renderRail() {
  E.list.replaceChildren();
  E.select.replaceChildren();
  for (const ex of S.examples) {
    const li = E.tpl.content.firstElementChild.cloneNode(true);
    li.dataset.id = ex.id;
    const main = li.querySelector('.card-main');
    main.id = `card-${ex.id}`;
    main.dataset.id = ex.id;
    li.querySelector('.card-title').textContent = ex.title;
    const img = li.querySelector('.card-thumb');
    if (img && ex.thumb) {
      img.src = ex.thumb.src; img.width = ex.thumb.width; img.height = ex.thumb.height; img.dataset.fit = ex.thumb.fit || 'cover';
      img.alt = ''; // decorative: the title and blurb carry the meaning
      img.hidden = false;
      img.addEventListener('error', () => { img.hidden = true; });
    }
    const blurb = li.querySelector('.card-blurb'); blurb.textContent = ex.blurb; blurb.id = `blurb-${ex.id}`;
    main.setAttribute('aria-describedby', blurb.id);
    li.querySelector('.card-more').textContent = `${ex.tryThis.length} things to try`;
    const hintsBox = li.querySelector('.card-hints');
    hintsBox.setAttribute('aria-label', `Things to try in ${ex.title}`);
    const ul = hintsBox.querySelector('.hint-list');
    const toggle = hintsBox.querySelector('.hints-toggle');
    let expanded = false;
    renderHints(ex, ul, false);
    if (ex.tryThis.length > HINTS_FOLDED) {
      toggle.hidden = false;
      const label = () => { toggle.textContent = expanded ? 'Show fewer' : `Show all ${ex.tryThis.length}`; toggle.setAttribute('aria-expanded', String(expanded)); };
      label();
      toggle.addEventListener('click', () => { expanded = !expanded; renderHints(ex, ul, expanded); label(); });
    }
    main.addEventListener('click', () => choose(ex.id, { source: 'rail' }));
    E.list.append(li);
    ex.el = li;
    const opt = document.createElement('option'); opt.value = ex.id; opt.textContent = ex.title; E.select.append(opt);
  }
  setRoving(S.examples[0] && S.examples[0].id);
  renderChips();
}
function setRoving(id) {
  const target = S.byId.has(id) ? id : S.examples[0] && S.examples[0].id; // never leave the rail without a tab stop
  for (const ex of S.examples) { const m = ex.el && ex.el.querySelector('.card-main'); if (m) m.tabIndex = ex.id === target ? 0 : -1; }
}
function markCurrent(id) {
  if (id) S.custom = false;
  for (const ex of S.examples) {
    const cur = ex.id === id;
    ex.el.classList.toggle('is-current', cur);
    const m = ex.el.querySelector('.card-main');
    if (cur) m.setAttribute('aria-current', 'true'); else m.removeAttribute('aria-current');
    ex.el.querySelector('.card-hints').hidden = !cur;
  }
  setRoving(id);
  const ex = S.byId.get(id);
  // keep the open card in view (deep links, the API and the narrow select can open a card below the fold)
  if (ex && ex.el && typeof ex.el.scrollIntoView === 'function') { try { ex.el.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); } catch { /* ignore */ } }
  if (E.select.value !== (id || '')) E.select.value = id || '';
  E.mobileBlurb.textContent = ex ? ex.blurb : '';
  if (ex) { E.mobileHintList.replaceChildren(...ex.tryThis.map((h) => hintButton(ex, h))); }
  document.title = ex ? `${ex.title} · Lean Widget Gallery` : 'Lean Widget Gallery';
  renderChips();
}
// The veil fades out (opacity) when it is hidden; it also leaves the accessibility tree and the focus order then
// (aria-hidden, inert; gallery.css turns it visibility: hidden once the fade is over), so a screen reader never reads a
// stale "Loading…" over a ready editor (hardening lane, UX C17).
function showVeil(text) { E.veilText.textContent = text; E.veil.classList.remove('is-hidden'); E.veil.removeAttribute('aria-hidden'); E.veil.removeAttribute('inert'); E.veil.inert = false; }
function hideVeil() { E.veil.classList.add('is-hidden'); E.veil.setAttribute('aria-hidden', 'true'); E.veil.setAttribute('inert', ''); E.veil.inert = true; }
/** transient: a one-off remark (bad link, late repair, …) that the user's next selection dismisses. */
function showNotice(text, { transient = false, kind = null, action = null } = {}) {
  if (kind !== 'slow') S.noticeBeforeSlow = null; // any other notice replaces the slow-download one for good
  S.notice = text; S.noticeTransient = transient; S.noticeKind = kind; S.noticeAction = action ? action.run : null;
  if (E.noticeText.textContent !== text) E.noticeText.textContent = text;
  if (action) E.noticeAction.textContent = action.label;
  E.noticeAction.hidden = !action;
  E.noticeClose.hidden = unsavedNotice(); // the storage notice of an unsaved text stays until that text is kept (or the tab closes)
  // the slow-download notice sits below the QED64 page's own top bar (#bar), so it never covers the page's status pill and
  // its download figures (final audit, 2026-10-03); other notices keep the CSS position
  E.notice.classList.toggle('is-slow', kind === 'slow');
  const top = kind === 'slow' ? belowPageBar() : '';
  if (E.notice.style.top !== top) E.notice.style.top = top;
  E.notice.hidden = false;
}
/** The stage offset just below the QED64 page's top bar (#bar; the frame fills the stage from its top), or '' (CSS fallback). */
function belowPageBar() {
  if (S.v1) return ''; // the page's DOM is internal (§9): the CSS position (just below a stock-height top bar)
  const pw = pageWin();
  try { const bar = pw && pw.document.getElementById('bar'); const r = bar && bar.getBoundingClientRect(); if (r && r.bottom > 0 && r.bottom < 200) return `${Math.round(r.bottom + 8)}px`; } catch { /* no bar: CSS */ }
  return '';
}
/** The storage notice is up and a text is in no storage (S.doc.unsaved): its × is hidden and inert (the "Copy it" must stay). */
function unsavedNotice() { return S.noticeKind === 'storage' && !!S.doc.unsaved; }
/** Hide the notice. Hiding any OTHER notice (dismissed, transient, slow) brings the storage notice back while it has something to say. */
function hideNotice() {
  const was = S.noticeKind;
  S.notice = null; S.noticeKind = null; S.noticeAction = null; S.noticeBeforeSlow = null; E.notice.hidden = true; E.noticeAction.hidden = true; E.noticeClose.hidden = false; E.notice.classList.remove('is-slow'); E.notice.style.top = '';
  if (was !== 'storage' && (S.doc.held || S.doc.unsaved)) storageNotice(); // storageNotice hides only a storage notice: no recursion
}
E.noticeClose.addEventListener('click', () => { if (!unsavedNotice()) hideNotice(); });
E.noticeAction.addEventListener('click', () => { if (S.noticeAction) S.noticeAction(); });

/** The friendly error card. soft: recoverable (QED64 retries on its own), shown over the page. */
function showError({ kind, title, detail, checks = null, raw = null, soft = false, retry = true, action = null, resetButton = false, dismissLabel = 'Dismiss', dismiss = true, stockLink = true }) {
  S.error = { kind, title, detail, soft, checks: checks ? checks.map((c) => ({ ...c })) : null };
  if (S.notice) E.notice.hidden = true; // the card says what matters; never stack the two
  S.errorAction = action;
  E.errRetry.textContent = action === 'reset' ? 'Reset example' : action === 'restart' ? 'Restart Lean' : action === 'try-anyway' ? 'Try anyway' : 'Try again';
  E.errReset.hidden = !resetButton;
  E.errDismiss.textContent = dismissLabel;
  E.errDismiss.hidden = !dismiss;
  E.errStock.hidden = !stockLink;
  E.err.classList.remove('is-compact'); E.errNote.hidden = true;
  E.err.classList.toggle('is-soft', !!soft);
  E.errTitle.textContent = title;
  E.errDetail.textContent = detail;
  E.errChecks.replaceChildren(...(checks || []).map((c) => { const li = document.createElement('li'); li.className = c.ok ? 'ok' : 'bad'; li.textContent = c.detail; return li; }));
  E.errChecks.hidden = !checks || checks.length === 0;
  E.errRaw.textContent = raw || '';
  E.errTech.hidden = !raw;
  E.errRetry.hidden = !retry && action !== 'reset' && action !== 'restart' && action !== 'try-anyway';
  E.errStock.href = L.frameUrl(S.overlay || S.requestedOverlay || L.DEFAULT_OVERLAYS[0]);
  E.err.hidden = false;
  if (!soft) hideVeil();
}
function hideError(onlySoft = false) { if (onlySoft && S.error && !S.error.soft) return; S.error = null; E.err.hidden = true; E.err.classList.remove('is-compact'); if (S.notice) E.notice.hidden = false; }
/** Hide the card only when it is of this kind (a soft boot card must not take a stall card down, and vice versa). */
function hideErrorKind(kind) { if (S.error && S.error.kind === kind) hideError(); }
E.errDismiss.addEventListener('click', () => {
  // "Keep waiting" on the stall card: re-arm the watchdog for another STALL_MS
  if (S.error && S.error.kind === 'stalled') { S.stall.active = false; S.stall.lastProgressAt = now(); S.stall.events.push({ t: Math.round(now()), source: 'keep-waiting' }); }
  hideError();
});
E.errReset.addEventListener('click', () => { const id = S.current || S.shownId; hideError(); if (id) choose(id, { source: 'reset', reset: true }); });
E.errRetry.addEventListener('click', () => {
  if (S.errorAction === 'restart') { restartLean('card'); return; }
  if (S.errorAction === 'try-anyway') { tryAnyway(); return; }
  const resetOnly = S.errorAction === 'reset' && S.booted;
  hideError();
  if (resetOnly) { choose(S.current || S.examples[0].id, { source: 'reset', reset: true }); return; }
  S.booted = false; choose(S.current || S.examples[0].id, { source: 'retry', force: true });
});

// The status line says in plain words what a visitor needs (which example, is Lean ready or still checking, how long
// the last step took). The technical detail (QED64's own phase and relay, header mode, session, ?mem) is the line's
// tooltip and __showcase.status().statusLine.detail.
const OP_DONE = { boot: 'Lean started in', reload: 'reloaded in', switch: 'opened in', reset: 'reset in' };
function plainStatus(ex, st, busy) {
  const name = ex ? ex.title : S.custom ? 'Your saved buffer' : 'The gallery';
  const took = (s) => (busy ? `${s}… ${fmtS(now() - S.op.t0)}` : s);
  switch (S.phase) {
    case 'starting': return took('Starting');
    case 'preflight': return took('Checking the widget snapshots');
    case 'booting': return `${took(S.op.label === 'reload' ? 'Reloading Lean' : 'Starting Lean in your browser')}${S.boot.waiting && S.boot.current && S.boot.current.total ? ` · ${fmtMB(S.boot.current.loaded)} of ${fmtMB(S.boot.current.total)}` : ''}`;
    case 'switching': return took(S.op.label === 'reset' ? `Resetting ${name}` : `Opening ${name}`);
    case 'ready': {
      const edited = S.edited && ex ? ' (edited)' : '';
      if (st && st.phase === 'elaborating') return `${name}${edited}: Lean is checking…`;
      const done = OP_DONE[S.op.label] && S.op.doneMs != null ? ` · ${OP_DONE[S.op.label]} ${fmtS(S.op.doneMs)}` : '';
      return `${name}${edited} is ready${done}`;
    }
    case 'refused': return `${name} needs widgets that this snapshot does not have`;
    case 'halted': return 'Lean has stopped';
    case 'error': return 'Something went wrong';
    case 'unsupported': return S.caps && S.caps.hard.length ? 'This browser cannot run the gallery' : 'Waiting: this device may not have enough memory';
    default: return `${name}: ${S.phase}`;
  }
}
function technicalStatus(ex, st, busy) {
  const parts = [];
  parts.push(ex ? ex.title : S.custom ? 'your saved buffer' : 'gallery');
  const label = { starting: 'starting', preflight: 'checking overlay', booting: 'booting QED64', switching: 'checking example', ready: 'ready', refused: 'header refused', halted: 'checker halted', error: 'error', unsupported: `unsupported browser: lacks ${S.caps ? S.caps.missing.join(', ') : '?'}` }[S.phase] || S.phase;
  parts.push(S.phase === 'ready' && S.edited && ex ? 'ready · edited' : label);
  if (st) {
    parts.push(`qed64 ${st.phase}${st.relay && st.relay !== 'serving' && st.relay !== st.phase ? `/${st.relay}` : ''}`);
    parts.push(`header ${st.header ? st.header.mode : '–'}`);
    parts.push(`session ${st.session || '–'}`);
    if (st.collision) parts.push(`collision ${st.collision.names.slice(0, 2).join(',')}`);
  }
  if (S.mem.bytes) parts.push(`mem ${S.mem.gib} GiB${S.mem.applied === true ? ' ✓' : S.mem.applied === false ? ' ✗' : ''}`);
  if (S.overlay) parts.push(`overlay ${S.overlay}`);
  parts.push(busy ? fmtS(now() - S.op.t0) : S.op.doneMs != null ? `${S.op.label} ${fmtS(S.op.doneMs)}` : '');
  return parts.filter(Boolean).join(' · ');
}
function renderStatus() {
  const st = S.lastStatus;
  const ex = S.byId.get(S.current);
  const busy = ['starting', 'preflight', 'booting', 'switching'].includes(S.phase);
  const text = plainStatus(ex, st, busy);
  const detail = technicalStatus(ex, st, busy);
  S.statusLine = { text, detail };
  if (E.statusText.textContent !== text) E.statusText.textContent = text;
  if (E.statusLine.title !== detail) E.statusLine.title = detail;
  if (E.statusLine.dataset.phase !== S.phase) E.statusLine.dataset.phase = S.phase;
  const canAct = !!ex && (S.booted || S.phase === 'error');
  E.reset.disabled = !canAct;
  E.copy.disabled = !ex;
}

// ---------------------------------------------------------------- narrow screens: stack the page's editor over its InfoView
// The stock page lays #editor and #infoview side by side (#split is a flex row with no media query), which at
// 390 px leaves ~190 px each. When the gallery itself is narrow we add one <style> to the page document (runtime
// styling only, like the bridge; QED64's files are untouched) and ask Monaco to re-layout. ?stack=0 disables it.
const STACK_MODE = params.get('stack'); // null = auto (<= 720 px), '0' = never, '1' = always
const narrowMq = window.matchMedia('(max-width: 720px)');
const STACK_CSS = '#split{flex-direction:column}#editor{flex:1 1 50%;min-height:0}#infoview{flex:1 1 50%;min-height:0;border-left:0;border-top:1px solid #ccc}';
// The page's own example menu (#examples: "Mathlib — real numbers", …) swaps in a stock document behind the gallery's
// back and reads as if it named the current example. The gallery's rail replaces it, so it is hidden (runtime
// styling, like the stack rule; ?pagebar=full keeps it). Edits it would make are still detected (S.edited).
const PAGE_CSS = params.get('pagebar') === 'full' ? '' : '#examples{display:none}';
function applyPageStyle(pw) {
  try {
    const doc = pw.document; if (!doc.head || !PAGE_CSS || doc.getElementById('qed64-showcase-page')) return;
    const el = doc.createElement('style'); el.id = 'qed64-showcase-page'; el.textContent = PAGE_CSS; doc.head.append(el);
  } catch { /* ignore */ }
}
function applyStack() {
  const pw = pageWin(); if (!pw) return;
  applyPageStyle(pw);
  const want = STACK_MODE === '1' || (STACK_MODE !== '0' && narrowMq.matches);
  try {
    const doc = pw.document; if (!doc.head) return;
    let el = doc.getElementById('qed64-showcase-stack');
    if (want && !el) { el = doc.createElement('style'); el.id = 'qed64-showcase-stack'; el.textContent = STACK_CSS; doc.head.append(el); }
    else if (!want && el) el.remove();
    else return;
    // legacy: ask Monaco to re-layout (qed64.editor); V1: the editor is internal and Monaco follows the resize by itself
    const ed = editor(); if (ed && typeof ed.layout === 'function') requestAnimationFrame(() => { try { ed.layout(); } catch { /* ignore */ } });
  } catch { /* ignore */ }
}
narrowMq.addEventListener('change', applyStack);

// ---------------------------------------------------------------- status monitor (every 250 ms)
function monitor() {
  pollApi();
  const st = qStatus();
  S.lastStatus = st ? { phase: st.phase, version: st.version, header: st.header, session: st.session, relay: st.relay, rebootReason: st.rebootReason ?? null, lastDeath: st.lastDeath, collision: st.collision || null } : null;
  if (S.v1) memApplied(st);
  if (S.booted && !S.bridge.polling) ensureBridge('monitor');
  applyStack();
  tapProgress();
  tapUi();
  lateBootCheck(st);
  watchStall(st);
  liveness(st);
  compactOverPageCard();
  if (S.booted && st && !S.driving) {
    // Edited: the editor no longer holds the example (the user typed, a link inserted text, or the page's own
    // example menu replaced the document). The card says so and Reset restores the example.
    const ex = S.byId.get(S.shownId);
    const txt = docText();
    const edited = !!(ex && txt !== null && txt !== ex.text);
    if (edited !== S.edited) { S.edited = edited; if (edited) announce(`${ex.title}: the example has been edited. Reset example restores it.`); }
    const c = L.classifyStatus(st, true);
    if (c.kind === 'halted' && S.phase !== 'halted') {
      S.phase = 'halted';
      showError({ kind: 'halted', title: 'The Lean checker stopped', detail: `QED64 ${c.text}. Reset the example (or edit the file) to start a fresh checker; it takes a few seconds.`, raw: JSON.stringify(st, null, 2), retry: false, soft: true, action: 'reset' });
      announce('The Lean checker stopped after repeated crashes. Reset the example to restart it.');
    } else if (S.phase === 'halted' && c.kind === 'ready') {
      S.phase = 'ready'; hideError(); announce('The Lean checker is running again.');
    }
  }
  renderStatus();
  renderChips();
}
setInterval(monitor, 250);

// ---------------------------------------------------------------- stall watchdog (QED64 limitation L7)
/** Count elaboration progress the worker sends (once per relay object; the relay calls this.toClient dynamically). */
function tapProgress() {
  if (S.v1) { S.stall.source = 'api-events'; S.stall.tapped = api() ? S.api.obj : null; return; } // 'fileProgress' / 'diagnostics' events (subscribeApi)
  const q = qed(); let r = null; try { r = q && q.relay; } catch { r = null; }
  if (!r || r === S.stall.tapped || typeof r.toClient !== 'function') return;
  const tc = r.toClient;
  r.toClient = function (m) {
    try {
      // the liveness probe's own reply: record it and swallow it (the editor never sent this request)
      if (m && typeof m.id === 'string' && m.id.startsWith(PROBE_PREFIX) && m.method === undefined) { probeReply(m); return undefined; }
      if (m && typeof m.id === 'string' && m.id.startsWith(MAIN_PREFIX) && m.method === undefined) { mainReply(m); return undefined; }
      if (qed64Synthetic(m)) S.live.syntheticFrames++; // made by QED64's JS layer: neither proof of life nor progress (see qed64Synthetic)
      else {
        S.live.frames++; S.live.lastFrameAt = now(); // any other server frame: the Lean side is alive (proof of life)
        if (m && (m.method === '$/lean/fileProgress' || m.method === 'textDocument/publishDiagnostics')) { S.stall.lastProgressAt = now(); S.stall.progressMsgs++; }
      }
    } catch { /* never break the relay */ }
    return tc.apply(this, arguments);
  };
  S.stall.tapped = r;
}
function stallIdleMs(st = qStatus()) {
  if (!st || st.relay !== 'serving' || st.phase !== 'elaborating') return 0;
  return now() - S.stall.lastProgressAt;
}
function watchStall(st) {
  const key = st ? `${st.session}|${st.relay}|${st.phase}|${st.version}` : null;
  if (key !== S.stall.key) { S.stall.key = key; S.stall.lastProgressAt = now(); S.stall.keyAt = now(); }
  const busy = !!(st && st.relay === 'serving' && st.phase === 'elaborating');
  if (!busy) {
    if (S.stall.active) {
      S.stall.active = false; hideErrorKind('stalled');
      const ev = { t: Math.round(now()), source: 'cleared', phase: st ? st.phase : null, relay: st ? st.relay : null, version: st ? st.version : null };
      S.stall.events.push(ev);
      if (st && st.phase === 'ready') announce('The Lean checker is making progress again.');
    }
    return;
  }
  const idle = now() - S.stall.lastProgressAt;
  if (S.stall.active) { // re-word the card if Lean's signs of life changed while it is up (see ALIVE_RECENT_MS)
    const v = recentLifeAt() !== null ? 'alive' : 'stopped';
    if (v !== S.stall.variant && S.error && S.error.kind === 'stalled') { stallCard(st, idle, v); S.stall.events.push({ t: Math.round(now()), source: 'reworded', variant: v, version: st.version, idleMs: Math.round(idle) }); }
    return;
  }
  if (idle < STALL_MS) return;
  if (S.error && S.error.kind !== 'stalled' && !S.error.soft) return; // a hard card already says what is wrong
  const variant = recentLifeAt() !== null ? 'alive' : 'stopped';
  S.stall.active = true; S.stall.shown++;
  S.stall.events.push({ t: Math.round(now()), source: 'shown', variant, version: st.version, session: st.session, idleMs: Math.round(idle), pool: st.pool || null });
  stallCard(st, idle, variant);
  const secs = Math.round(idle / 1000);
  announce(variant === 'alive' ? `Lean has shown no progress for ${secs} seconds but is still answering. Keep waiting or Restart Lean.` : `Lean has shown no progress for ${secs} seconds. Restart Lean is offered.`);
}
/** The stall card in one of its two wordings: 'stopped' (no sign of life) or 'alive' (Lean answered recently). */
function stallCard(st, idle, variant) {
  S.stall.variant = variant;
  const secs = Math.round(idle / 1000);
  const life = recentLifeAt(); const ago = life === null ? null : Math.max(1, Math.round((now() - life) / 1000));
  showError({
    kind: 'stalled', soft: true, action: 'restart', resetButton: true, dismissLabel: 'Keep waiting',
    title: variant === 'alive' ? 'Lean is still working' : 'Lean has stopped making progress',
    detail: variant === 'alive'
      ? `QED64 has been checking this version of the file for ${secs} s without reporting progress, but Lean answered ${ago} s ago, so this is most likely a long-running command, not a freeze. Keep waiting, or Restart Lean to stop it and check the same text again (a few seconds); Reset example also restores the example.`
      : `QED64 has been checking this version of the file for ${secs} s without reporting any progress. If Lean has frozen (a known, rare QED64 runtime problem, L7), Restart Lean starts a fresh checker on the same text (a few seconds); Reset example also restores the example.`,
    raw: JSON.stringify({ status: st, idleMs: Math.round(idle), thresholdMs: STALL_MS, variant, lastLifeAgoMs: life === null ? null : Math.round(now() - life) }, null, 2),
  });
}
/**
 * Restart QED64's checker on the same text (the relay's own restart; QED64's "Load exact imports" uses it too). Returns
 * the event it recorded ({how: 'relay.restart' | 'page-reload' | 'none'}). allowReload: when the relay is not serving,
 * reload the QED64 page instead (the card's buttons do; the automatic liveness restart does not, the card is its fallback).
 */
function restartLean(source, { allowReload = true } = {}) {
  const q = qed(); let relay = null; try { relay = q && q.relay; } catch { relay = null; }
  const st = qStatus();
  const ev = { t: Math.round(now()), source, version: st ? st.version : null, phase: st ? st.phase : null, session: st ? st.session : null, idleMs: Math.round(now() - S.stall.lastProgressAt), how: null };
  S.stall.events.push(ev); if (S.stall.events.length > 60) S.stall.events.splice(0, 20);
  const a = api();
  if (a) {
    // V1 (§2.3): api.restart() with no arguments reuses the session's own boot inputs (the relay's header rule included); on
    // a halted relay it re-arms; {accepted:false} while a boot is in flight → the card's page-reload fallback below, else 'none'
    try {
      const r = a.restart();
      ev.accepted = !!(r && r.accepted); ev.fromSession = r ? r.fromSession ?? null : null;
      if (ev.accepted) {
        ev.how = 'api.restart'; S.stall.restarts++; S.stall.key = null; S.stall.lastProgressAt = now();
        S.stall.active = false; hideErrorKind('stalled');
        announce('Restarting the Lean checker; your text is kept.');
        return ev;
      }
    } catch (e) { ev.error = String(e && e.message || e).slice(0, 200); }
  } else if (relay && relay.state && relay.state.kind === 'serving' && typeof relay.restart === 'function') {
    try {
      const snaps = relay.session && Array.isArray(relay.session.snapshots) ? [...relay.session.snapshots] : null;
      relay.restart(relay.restartOpts || (snaps ? { snapshots: snaps } : {}));
      ev.how = 'relay.restart'; S.stall.restarts++; S.stall.key = null; S.stall.lastProgressAt = now();
      S.stall.active = false; hideErrorKind('stalled');
      announce('Restarting the Lean checker; your text is kept.');
      return ev;
    } catch (e) { ev.error = String(e && e.message || e).slice(0, 200); }
  }
  if (!allowReload) { ev.how = 'none'; return ev; }
  S.stall.active = false; hideErrorKind('stalled');
  // not serving (or no restart API): reload the QED64 page; it boots its saved buffer and the gallery adopts it
  const pw = pageWin();
  if (pw) { try { ev.how = 'page-reload'; pw.location.reload(); return ev; } catch (e) { ev.error = String(e && e.message || e).slice(0, 200); } }
  ev.how = 'none';
  return ev;
}

// ---------------------------------------------------------------- liveness probe (QED64 limitation L7; see PROBE_AFTER_MS)
function liveEvent(ev) { const L = S.live; L.events.push({ t: Math.round(now()), ...ev }); if (L.events.length > 60) L.events.splice(0, 20); }
/** Every 250 ms (monitor): arm, send, time out and decide, per the state machine described at PROBE_AFTER_MS. */
/** QED64's own liveness (see PROBE_DEFER_MS): detect it, follow its counters per session, report its "wedged" reboots. */
function observeQed64(st) {
  const Q = S.live.qed64;
  if (!st) return;
  if (st.relay === 'serving') Q.servingSession = st.session; // during a reboot the relay already names the NEW session
  const lv = st.liveness;
  if (lv && typeof lv === 'object' && typeof lv.probes === 'number') {
    if (!Q.builtIn) { Q.builtIn = true; Q.detectedAt = Math.round(now()); liveEvent({ source: 'qed64-detected', session: st.session, counters: { ...lv } }); }
    const cur = {}; for (const k of QED64_LIVE_KEYS) cur[k] = Number(lv[k]) || 0;
    // a new session (or a reloaded page reusing a session id: a counter went down) starts a new baseline at zero
    const fresh = Q.session !== st.session || !Q.counters || QED64_LIVE_KEYS.some((k) => cur[k] < Q.counters[k]);
    const base = fresh ? { probes: 0, answered: 0, stalls: 0, resumed: 0, rescues: 0 } : Q.counters;
    for (const k of QED64_LIVE_KEYS) {
      const d = cur[k] - base[k]; if (d <= 0) continue;
      Q.totals[k] += d;
      if (k === 'answered') Q.lastAnsweredAt = now(); // QED64's own probe answered: the Lean side is alive (proof of life)
      if (k === 'stalls' || k === 'resumed' || k === 'rescues') liveEvent({ source: `qed64-${k === 'stalls' ? 'stall' : k === 'resumed' ? 'resumed' : 'rescue'}`, session: st.session, version: st.version, [k]: cur[k] });
    }
    Q.session = st.session; Q.counters = cur;
  }
  // QED64's relay reboots a session its liveness declared wedged (lsp-relay.ts: rebootReason 'wedged'; lastDeath.reason too)
  const wedgedReboot = st.relay === 'rebooting' && st.rebootReason === 'wedged';
  if (wedgedReboot && !Q.rebooting) {
    Q.rebooting = true; Q.wedgedReboots++;
    Q.lastReboot = { t: Math.round(now()), from: Q.servingSession || null, to: st.session, version: st.version, lastDeath: st.lastDeath || null, counters: Q.counters ? { ...Q.counters } : null };
    liveEvent({ source: 'qed64-wedged', from: Q.servingSession || null, session: st.session, version: st.version, lastDeath: st.lastDeath || null });
    showNotice('Lean stopped responding; QED64 is restarting it. Your text is kept.', { transient: true });
    announce('Lean stopped responding. QED64 is restarting it; your text is kept.');
  } else if (!wedgedReboot && Q.rebooting) {
    Q.rebooting = false;
    liveEvent({ source: 'qed64-rebooted', session: st.session, phase: st.phase, relay: st.relay });
  }
}
/** QED64 reports a stall in its grace window: its own liveness is about to kill and reboot this session. */
function qed64Stalled(st) { const lv = st && st.liveness; return !!(lv && typeof lv.stalls === 'number' && lv.stalls > (Number(lv.resumed) || 0)); }
/** V1: ?mem= travelled as &memory=; applied = the commit the worker made (api.status().memory.initialBytes, §2.3) equals the request. */
function memApplied(st) { if (st && st.memory && st.memory.initialBytes != null && S.mem.bytes != null) S.mem.applied = st.memory.initialBytes === S.mem.bytes; }
/** V1: mirror the api's liveness projection (§2.2 LivenessInfo) into the legacy fields the card's wording reads (recentLifeAt). */
function observeApiLiveness(st) {
  const Q = S.live.qed64; const L1 = S.live;
  if (!st) return;
  if (st.relay === 'serving') Q.servingSession = st.session;
  Q.session = st.session;
  const lv = st.liveness;
  if (lv && typeof lv === 'object') {
    Q.stalled = !!lv.stalled; Q.lastAnswerAgoMs = lv.lastAnswerAgoMs ?? null; Q.lastFrameAgoMs = lv.lastFrameAgoMs ?? null;
    Q.probeAfterMs = lv.probeAfterMs ?? null; Q.wedgeAfterMs = lv.wedgeAfterMs ?? null; Q.graceMs = lv.graceMs ?? null;
    if (Number.isFinite(lv.lastAnswerAgoMs)) Q.lastAnsweredAt = Math.max(Q.lastAnsweredAt, now() - lv.lastAnswerAgoMs);
    if (Number.isFinite(lv.lastFrameAgoMs)) L1.lastFrameAt = Math.max(L1.lastFrameAt, now() - lv.lastFrameAgoMs);
  } else { Q.stalled = null; Q.lastAnswerAgoMs = null; Q.lastFrameAgoMs = null; }
  Q.rebooting = st.relay === 'rebooting' && st.rebootReason === 'wedged';
}
function liveness(st) {
  const L = S.live;
  if (S.v1) { observeApiLiveness(st); return; } // the probe stands down: QED64's own liveness (capabilities.liveness) and its events; the 45 s card stays the fallback
  observeQed64(st);
  if (L.mode === 'off') return;
  const busy = !!(st && st.relay === 'serving' && st.phase === 'elaborating');
  const key = busy ? `${st.session}|${st.version}` : null;
  if (key !== L.key) {
    // a new version, session or phase: start over (an outstanding probe may still be answered; it is then only counted)
    if (L.wedgedActive) liveEvent({ source: 'cleared', phase: st ? st.phase : null, version: st ? st.version : null, session: st ? st.session : null });
    L.key = key; L.misses = 0; L.wedgedActive = false; L.outstanding = null; L.armAt = now();
  }
  if (!busy) return;
  const o = L.outstanding;
  if (o) {
    if (S.stall.lastProgressAt > o.sentAt) { L.misses = 0; L.outstanding = null; L.armAt = now(); return; } // progress meanwhile: alive
    if (now() - o.sentAt < L.probeTimeoutMs) return;
    const via = proofOfLife();
    if (via) { // unanswered, but Lean showed life meanwhile (a saturated pool delays a hover): not a miss
      L.alive++; L.aliveVia[via]++; L.misses = 0; L.outstanding = null; L.armAt = now(); L.lastAliveAt = now();
      liveEvent({ source: 'alive', id: o.id, via, version: st.version, session: st.session, pool: st.pool || null });
      return;
    }
    L.missed++; L.misses++; L.outstanding = null;
    liveEvent({ source: 'missed', id: o.id, version: st.version, session: st.session, misses: L.misses });
    if (L.misses >= PROBE_MISSES) { wedged(st); return; }
    sendProbe(st);
    return;
  }
  if (L.wedgedActive) return; // already decided for this version (observe mode, rate limit, failed restart, deferred): the card is next
  // with QED64's own liveness on the page, ours is the slower fallback (PROBE_DEFER_MS)
  if (now() - Math.max(S.stall.lastProgressAt, L.armAt) < (L.qed64.builtIn ? L.probeDeferMs : L.probeAfterMs)) return;
  if (L.qed64.builtIn && qed64Stalled(st)) { L.armAt = now(); return; } // QED64 is about to reboot it: do not race
  sendProbe(st);
}
/** Proof of life since the first probe of this sequence (see LIFE_LOOKBACK_MS): 'frame' | 'late-answer' | 'qed64-answered' | 'main-loop' | null. */
function proofOfLife() {
  const L = S.live;
  if (L.lastFrameAt > L.seqStart) return 'frame';
  if (L.lastLateAnswerAt > L.seqStart) return 'late-answer'; // Lean answered one of our probes late: alive, merely busy
  if (L.qed64.builtIn && L.qed64.lastAnsweredAt >= L.seqStart - LIFE_LOOKBACK_MS) return 'qed64-answered';
  if (L.main.lastAnsweredAt > L.seqStart) return 'main-loop'; // the FileWorker's main loop answered our main-loop probe
  return null;
}
/** The newest sign of life (a probe answer or 'alive', any server frame including progress, a QED64 probe answer) since
 *  this version / session / phase began and within ALIVE_RECENT_MS: its time, else null (the card's wording). A progress
 *  message that arrives while the card is up is itself a sign of life (C22 (3): the first wave of sleeping proofs
 *  finished while the card was up); a frame from before the edit is not (C21 (b): ?stall=15 is shorter than 20 s). */
function recentLifeAt() {
  const L = S.live; const t = Math.max(L.lastAliveAt, L.lastFrameAt, L.qed64.lastAnsweredAt, L.main.lastAnsweredAt);
  return t > (S.stall.keyAt || 0) && now() - t <= ALIVE_RECENT_MS ? t : null;
}
function sendProbe(st) {
  const L = S.live; const q = qed(); let r = null; try { r = q && q.relay; } catch { r = null; }
  // only through a relay whose replies we can swallow, and only for an open document (the request needs its uri)
  const why = !r ? 'no relay' : r !== S.stall.tapped ? 'relay not tapped yet' : typeof r.fromClient !== 'function' ? 'no relay.fromClient' : !(r.doc && r.doc.uri) ? 'no open document' : null;
  if (why) { L.unavailable = why; L.armAt = now(); return; }
  const id = `${PROBE_PREFIX}${++L.seq}`;
  try {
    r.fromClient({ jsonrpc: '2.0', id, method: 'textDocument/hover', params: { textDocument: { uri: r.doc.uri }, position: { line: 0, character: 0 } } });
  } catch (e) { L.unavailable = `fromClient threw: ${String(e && e.message || e).slice(0, 120)}`; L.armAt = now(); return; }
  L.unavailable = null; L.sent++;
  if (L.misses === 0) L.seqStart = now(); // a new probe sequence: proof of life is looked for from here (see proofOfLife)
  L.outstanding = { id, sentAt: now(), version: st.version, session: st.session };
  L.probeSentAt.set(id, now()); if (L.probeSentAt.size > 20) L.probeSentAt.delete(L.probeSentAt.keys().next().value);
  // the main-loop probe (see MAIN_METHOD), sent with the hover; best effort (a throw here never blocks the hover)
  const M = L.main; const mid = `${MAIN_PREFIX}${L.seq}`;
  try {
    r.fromClient({ jsonrpc: '2.0', id: mid, method: MAIN_METHOD, params: {} });
    M.sent++; M.sentAt.set(mid, now()); if (M.sentAt.size > 20) M.sentAt.delete(M.sentAt.keys().next().value);
  } catch { /* the hover alone still probes */ }
  liveEvent({ source: 'probe', id, main: M.sentAt.has(mid) ? mid : null, version: st.version, session: st.session, idleMs: Math.round(now() - S.stall.lastProgressAt) });
}
/** A reply to a main-loop probe: Lean's own (normally MethodNotFound, -32601) is proof of life; QED64's synthetic ones are not. */
function mainReply(m) {
  const M = S.live.main;
  const err = m.error ? { code: m.error.code, message: String(m.error.message || '').slice(0, 120) } : null;
  const at = M.sentAt.get(m.id); M.sentAt.delete(m.id);
  if (qed64Synthetic(m)) { M.synthetic++; liveEvent({ source: 'main-synthetic', id: m.id, error: err }); return; }
  const ms = at === undefined ? null : Math.round(now() - at);
  M.answered++; M.lastAnsweredAt = now();
  if (ms !== null) { M.lastMs = ms; M.maxMs = Math.max(M.maxMs || 0, ms); }
  liveEvent({ source: 'main-answered', id: m.id, ms, code: err ? err.code : null });
}
function probeReply(m) {
  const L = S.live; const o = L.outstanding;
  const err = m.error ? { code: m.error.code, message: String(m.error.message || '').slice(0, 120) } : null;
  if (qed64Synthetic(m)) {
    // QED64's JS layer answered the probe (a halted relay, or failInFlight on a death or restart): Lean did not. Not an
    // answer and not a sign of life; an outstanding probe stays outstanding and times out as usual.
    L.syntheticReplies++;
    liveEvent({ source: 'synthetic-reply', id: m.id, error: err });
    return;
  }
  if (o && m.id === o.id) {
    const ms = Math.round(now() - o.sentAt);
    if (ms <= L.probeTimeoutMs) {
      L.answered++; L.misses = 0; L.outstanding = null; L.armAt = now(); L.lastAliveAt = now(); L.lastAnswerMs = ms; L.maxAnswerMs = Math.max(L.maxAnswerMs || 0, ms);
      liveEvent({ source: 'answered', id: m.id, ms, error: err });
      return;
    }
    // Answered AFTER its timeout, but before the 250 ms monitor tick looked at it. Classified by ELAPSED TIME, not by
    // tick order (hardening lane: an event loop delayed by host load used to turn such a late answer into an on-time
    // one, sim run 12): it is a late answer. A real (non-error) one is proof of life and settles the sequence 'alive'
    // right here; an error reply is recorded as late and the probe still times out on the next tick as a miss.
    L.late++;
    if (!err) {
      L.lateAnswers++; L.lastLateAnswerAt = now(); L.lastAliveAt = now();
      liveEvent({ source: 'late', id: m.id, ms, error: null, proofOfLife: true });
      L.alive++; L.aliveVia['late-answer']++; L.misses = 0; L.outstanding = null; L.armAt = now();
      liveEvent({ source: 'alive', id: m.id, via: 'late-answer', version: o.version, session: o.session });
    } else liveEvent({ source: 'late', id: m.id, ms, error: err, proofOfLife: false });
    return;
  }
  // a reply after its probe was counted as missed (or after a restart answered it with an error)
  L.late++;
  if (!err) { L.lateAnswers++; L.lastLateAnswerAt = now(); L.lastAliveAt = now(); } // a real answer from Lean, only late: proof of life
  const at = L.probeSentAt.get(m.id);
  liveEvent({ source: 'late', id: m.id, ms: at === undefined ? null : Math.round(now() - at), error: err, proofOfLife: !err });
  if (L.wedgedActive && !err) { L.wedgedActive = false; L.misses = 0; L.armAt = now(); liveEvent({ source: 'resumed', id: m.id }); }
}
function wedged(st) {
  const L = S.live; L.wedged++; L.wedgedActive = true;
  // recorded BEFORE acting: the restart answers the outstanding probes at once (relay failInFlight), and those 'late'
  // replies must follow the decision in the log, not precede it
  const ev = { t: Math.round(now()), source: 'wedged', mode: L.mode, version: st.version, session: st.session, phase: st.phase, relay: st.relay, lastDeath: st.lastDeath || null, pool: st.pool || null, idleMs: Math.round(now() - S.stall.lastProgressAt), action: null };
  L.events.push(ev); if (L.events.length > 60) L.events.splice(0, 20);
  if (L.qed64.builtIn) ev.qed64 = { counters: st.liveness ? { ...st.liveness } : null, stalled: qed64Stalled(st) };
  if (L.mode === 'observe') {
    ev.action = 'observed';
    console.warn(`[showcase] liveness: Lean answered none of ${PROBE_MISSES} probes on ${st.session} v${st.version} (observe mode: not restarting)`);
  } else if (L.qed64.builtIn && qed64Stalled(st)) {
    ev.action = 'deferred'; L.deferred++; // QED64's own liveness is in its grace window and reboots it itself; the card is the fallback
  } else if (now() - L.lastAutoRestartAt < L.restartGapMs) {
    ev.action = 'rate-limited'; L.rateLimited++; // the stall card (STALL_MS) offers the restart instead
  } else {
    L.lastAutoRestartAt = now();
    const r = restartLean('liveness', { allowReload: false });
    const restarted = r.how === 'relay.restart' || r.how === 'api.restart';
    ev.action = restarted ? r.how : 'restart-failed';
    if (r.error) ev.error = r.error;
    if (restarted) {
      L.restarts++;
      showNotice('Lean stopped responding and was restarted. Your text is kept.', { transient: true });
      announce('Lean stopped responding and was restarted.');
    } else L.restartFailed++;
  }
}
function liveSnapshot() {
  const L = S.live;
  return { mode: L.mode, probe: S.v1 ? (L.qed64.api ? 'stood-down' : 'unavailable') : (L.mode === 'off' ? 'off' : 'active'), probeAfterMs: L.probeAfterMs, probeTimeoutMs: L.probeTimeoutMs, restartGapMs: L.restartGapMs, misses: L.misses, sent: L.sent, answered: L.answered, missed: L.missed, late: L.late,
    wedged: L.wedged, wedgedActive: L.wedgedActive, restarts: L.restarts, rateLimited: L.rateLimited, restartFailed: L.restartFailed, outstanding: L.outstanding ? { ...L.outstanding, ageMs: Math.round(now() - L.outstanding.sentAt) } : null,
    lastAnswerMs: L.lastAnswerMs, maxAnswerMs: L.maxAnswerMs, unavailable: L.unavailable, lateAnswers: L.lateAnswers,
    frames: L.frames, lastFrameAgoMs: Number.isFinite(L.lastFrameAt) ? Math.round(now() - L.lastFrameAt) : null, syntheticFrames: L.syntheticFrames, syntheticReplies: L.syntheticReplies, alive: L.alive, aliveVia: { ...L.aliveVia },
    mainLoop: { method: MAIN_METHOD, sent: L.main.sent, answered: L.main.answered, synthetic: L.main.synthetic, outstanding: L.main.sentAt.size,
      lastAnsweredAgoMs: Number.isFinite(L.main.lastAnsweredAt) ? Math.round(now() - L.main.lastAnsweredAt) : null, lastMs: L.main.lastMs, maxMs: L.main.maxMs },
    probeDeferMs: L.probeDeferMs, deferring: L.qed64.builtIn && L.mode !== 'off', effectiveProbeAfterMs: L.qed64.builtIn ? L.probeDeferMs : L.probeAfterMs, deferred: L.deferred,
    qed64: { builtIn: L.qed64.builtIn, api: L.qed64.api, detectedAt: L.qed64.detectedAt, session: L.qed64.session, counters: L.qed64.counters ? { ...L.qed64.counters } : null,
      totals: S.v1 ? { probes: null, answered: L.qed64.totals.answered, stalls: L.qed64.totals.stalls, resumed: L.qed64.totals.resumed, rescues: L.qed64.totals.rescues } : { ...L.qed64.totals },
      lastAnsweredAgoMs: Number.isFinite(L.qed64.lastAnsweredAt) ? Math.round(now() - L.qed64.lastAnsweredAt) : null,
      wedgedReboots: L.qed64.wedgedReboots, rebooting: L.qed64.rebooting, lastReboot: L.qed64.lastReboot,
      ...(S.v1 ? { stalled: L.qed64.stalled, lastAnswerAgoMs: L.qed64.lastAnswerAgoMs, lastFrameAgoMs: L.qed64.lastFrameAgoMs, probeAfterMs: L.qed64.probeAfterMs, wedgeAfterMs: L.qed64.wedgeAfterMs, graceMs: L.qed64.graceMs } : {}) },
    events: L.events.slice(-40) };
}
/** QED64's own boot card is showing (e.g. a lasting network cut): keep our card compact so it never covers it. */
function compactOverPageCard() {
  if (!S.error || E.err.hidden || !['halted', 'boot', 'bootFailed'].includes(S.error.kind)) return;
  let want;
  if (S.v1) { const st = apiStatus(); want = !!(st && st.boot && st.boot.failed && st.boot.overlay); } // status().boot.overlay: the page's own card is visible (§2.2)
  else { const pw = pageWin(); want = !!(pw && pageBootFailure(pw)); }
  if (E.err.classList.contains('is-compact') === want) return;
  E.err.classList.toggle('is-compact', want);
  E.errNote.hidden = !want;
  E.errNote.textContent = want ? 'QED64’s own card below says what failed. Try again reloads the page.' : '';
}

// ---------------------------------------------------------------- boot progress (slow links; see BOOT_TIMEOUT_MS)
function bootEvent(ev) { const B = S.boot; B.events.push({ t: Math.round(now()), ...ev }); if (B.events.length > 40) B.events.splice(0, 10); }
/** A sign of progress while a boot wait runs: re-arms the true-stall clock. */
function bootMark(source) { const B = S.boot; B.lastProgressAt = now(); B.sources[source]++; }
/** A new page boot: forget what the previous page reported (counters of notices, stalls and recoveries are kept). */
function bootReset() {
  const B = S.boot;
  B.bytes = 0; B.hw.clear(); B.labels.clear(); B.keys.clear(); B.resources = 0; B.resourceUrls.clear(); B.current = null; B.label = null;
  B.lastBytesAt = -Infinity; B.late = null;
}
/**
 * QED64's status sink (globalThis.qed64.ui: the page's pill and boot card; busy/progress/idle(label, ProgressInfo {phase,
 * loaded, total, unit})) is wrapped once per page, so the gallery sees the download bytes the page reports, also after the
 * page has removed its own boot card (its snapshot prefetch reports "preparing the … environment" with bytes there).
 * Runtime instrumentation like the bridge and the relay tap; QED64's files are untouched. The wrapper never throws into the
 * page and always calls the original with the same arguments.
 */
function tapUi() {
  if (S.v1) { S.boot.source = 'api-events'; return; } // 'boot' events carry the same figures (apiBoot)
  const q = qed(); let ui = null; try { ui = q && q.ui; } catch { ui = null; }
  const B = S.boot;
  if (!ui || typeof ui !== 'object' || ui === B.ui) return;
  B.ui = ui; B.uiWrapped = [];
  for (const k of ['busy', 'progress', 'idle']) {
    let orig; try { orig = ui[k]; } catch { orig = null; }
    if (typeof orig !== 'function') continue;
    try {
      ui[k] = function (label, info) { try { uiCall(k, label, info); } catch { /* never break the page */ } return orig.apply(this, arguments); };
      if (ui[k] !== orig) B.uiWrapped.push(k);
    } catch { /* a frozen sink: progress then comes from the status and the page's resources only */ }
  }
}
function uiCall(kind, label, info) {
  const B = S.boot; B.uiCalls++;
  if (typeof label === 'string' && label) {
    B.label = label;
    if (!B.labels.has(label) && B.labels.size < 200) { B.labels.add(label); if (B.waiting) bootMark('label'); }
  }
  if (kind === 'progress' && info && info.unit === 'bytes' && Number.isFinite(info.loaded)) {
    // bytes count per download (phase + total) at its high-water mark: a retry that re-sends the same first bytes is no progress
    const key = `${info.phase || ''}|${Number.isFinite(info.total) ? info.total : ''}`;
    const hw = B.hw.get(key) || 0;
    if (info.loaded > hw && (B.hw.has(key) || B.hw.size < 200)) {
      B.hw.set(key, info.loaded); B.bytes += info.loaded - hw; B.lastBytesAt = now();
      if (B.waiting) bootMark('bytes');
    }
    B.current = { label: typeof label === 'string' ? label : null, loaded: info.loaded, total: Number.isFinite(info.total) && info.total > 0 ? info.total : null };
  }
}
/** Progress the gallery can read itself: a QED64 phase/relay/session/version not seen before, a new page resource. */
function bootTick(st) {
  const B = S.boot;
  tapUi();
  if (st) {
    const k = `${st.phase}|${st.relay}|${st.session}|${st.version}`;
    if (!B.keys.has(k) && B.keys.size < 200) { B.keys.add(k); bootMark('status'); }
  }
  // a page resource counts only when its URL (without query or hash) was not seen before in this boot: a page that keeps
  // re-fetching the same file (a retry loop, a cache-busting query) adds resource entries but is no progress (final audit,
  // 2026-10-03: each new entry used to re-arm the stall window)
  let list = null; try { const pw = pageWin(); list = pw && pw.performance ? pw.performance.getEntriesByType('resource') : null; } catch { list = null; }
  const n = list ? list.length : 0;
  if (n < B.resources) B.resources = 0; // a new page document: its entries start again (the URLs already seen stay seen)
  if (n > B.resources) {
    let fresh = false;
    for (let i = B.resources; i < n; i++) {
      let u = ''; try { u = String(list[i].name || '').split(/[?#]/)[0]; } catch { u = ''; }
      if (u && !B.resourceUrls.has(u) && B.resourceUrls.size < 500) { B.resourceUrls.add(u); fresh = true; }
    }
    B.resources = n;
    if (fresh) bootMark('resource');
  }
}
/** Is QED64's own boot overlay (#boot) still on the page? The stock page removes it 120 s after its editor opens. */
function pageBootOverlay() {
  if (S.v1) { const st = apiStatus(); return !!(st && st.boot && st.boot.overlay); }
  const pw = pageWin();
  try { const b = pw && pw.document.getElementById('boot'); return !!(b && !(b.classList && b.classList.contains('done'))); } catch { return false; }
}
/** The non-blocking "still downloading" notice (never the error card) while the boot makes progress. */
function bootNotice(el, idle) {
  const B = S.boot;
  const bytesRecent = now() - B.lastBytesAt <= BOOT_RECENT_MS;
  const want = idle < BOOT_STALL_MS && (el >= BOOT_TIMEOUT_MS || (el >= BOOT_NOTICE_MS && bytesRecent && !pageBootOverlay()));
  if (!want || S.error) return; // once shown it stays until ready or a stall (no flicker between chunks); a card says what matters
  // QED64's own figures for its current step (what its boot card would show): bytes PREPARED (e.g. a snapshot's raw
  // size while its compressed download streams in), not network bytes, so the text never sums steps into "downloaded"
  const cur = B.current && B.current.total ? B.current : null;
  const text = cur
    ? `Still downloading: ${cur.label || 'Lean'} — ${fmtMB(cur.loaded)} of ${fmtMB(cur.total)} so far. A first visit downloads several hundred MB, which takes minutes on a slow connection; later visits start from this browser's storage.`
    : `Lean is still starting (${fmtS(el)}) and making progress. On a slow connection the first visit takes several minutes.`;
  if (S.noticeKind !== 'slow') {
    S.noticeBeforeSlow = S.notice ? { text: S.notice, transient: S.noticeTransient, kind: S.noticeKind, action: S.noticeAction ? { label: E.noticeAction.textContent, run: S.noticeAction } : null } : null;
    B.noticeShown++; bootEvent({ source: 'notice', bytes: B.bytes, elapsedMs: Math.round(el) });
    announce('Still downloading Lean. The first visit is slow on this connection; the page keeps going.');
  }
  showNotice(text, { kind: 'slow' });
}
/** Take the slow-download notice down (and bring back the notice it replaced, if any). */
function hideSlowNotice() {
  if (S.noticeKind !== 'slow') return;
  const before = S.noticeBeforeSlow;
  hideNotice();
  if (before) showNotice(before.text, { transient: before.transient, kind: before.kind, action: before.action });
}
/** One tick of a progress-aware boot wait: throws TIMEOUT only on a true stall (BOOT_TIMEOUT_MS passed AND no progress for BOOT_STALL_MS). */
function bootCheck(t0, timeoutMs, label) {
  const B = S.boot;
  bootTick(qStatus());
  const el = now() - t0; const idle = now() - B.lastProgressAt;
  if (el >= timeoutMs && idle >= BOOT_STALL_MS) {
    B.stalls++; bootEvent({ source: 'stalled', elapsedMs: Math.round(el), idleMs: Math.round(idle), bytes: B.bytes, label: B.label });
    hideSlowNotice();
    const cur = B.current && B.current.total ? B.current : null;
    const e = new Error(`no download or start-up progress for ${fmtS(idle)} while waiting for ${label} (${fmtS(el)} in${cur ? `; QED64's last step: ${cur.label || 'download'}, ${fmtMB(cur.loaded)} of ${fmtMB(cur.total)}` : ''})`);
    e.code = 'TIMEOUT'; e.stalled = true;
    throw e;
  }
  bootNotice(el, idle);
}
/** After a true-stall card: QED64 reaching 'ready' on the same page closes the card and finishes the boot (cursor, panel). */
function lateBootCheck(st) {
  const lb = S.boot.late;
  if (!lb || S.phase !== 'error' || S.driving || S.adopting) return;
  const doc = bootToken();
  if (!doc || doc !== lb.doc) { S.boot.late = null; bootEvent({ source: 'late-dropped' }); return; }
  if (!st || (st.phase !== 'ready' && st.phase !== 'headerRefused') || (S.v1 && st.relay !== 'serving')) return;
  const relayText = docText();
  if (lb.text !== null && relayText !== null && relayText !== lb.text) return;
  S.boot.late = null; S.boot.recovered++;
  bootEvent({ source: 'recovered', kind: lb.kind, afterMs: Math.round(now() - lb.t0) });
  const r = { st, refused: st.phase === 'headerRefused' };
  hideError();
  S.bootMs = now() - lb.t0; S.op = { label: lb.kind === 'reload' ? 'reload' : 'boot', t0: lb.t0, doneMs: S.bootMs };
  S.booted = true; S.everReady = true;
  if (lb.kind === 'reload') adoptShown(r, lb.id);
  else { const ex = S.byId.get(lb.id); S.shownId = ex.id; shown(ex, r, null); }
}

// ---------------------------------------------------------------- waiting on the page
/** Throws Superseded when the selection that started this wait is no longer the wanted one. */
function checkWanted(w) { if (w && S.wanted !== w) throw new Superseded(); }

/** Wait until the page publishes globalThis.qed64, watching the page's own boot card for a failure. */
async function waitForHook(w) {
  if (S.v1) {
    // the api exists from the page's module start (§2.1); a boot that fails before the relay is even bound (a refused
    // parameter, a missing index: status().boot.failed with no session) is the hard "could not start" card
    return L.waitFor(() => {
      pollApi();
      const a = api(); if (!a) return null;
      const f = hardBootFailure(apiStatus());
      if (f) throw new GalleryError('boot', 'QED64 could not start', f);
      return a;
    }, { timeoutMs: HOOK_TIMEOUT_MS, intervalMs: 50, label: 'the QED64 page to start (qed64:frame-api)' });
  }
  return L.waitFor(() => {
    ensureBridge('hook-wait');
    const pw = pageWin();
    if (pw) {
      const fail = pageBootFailure(pw);
      if (fail) throw new GalleryError('boot', 'QED64 could not start', fail);
    }
    return qed();
  }, { timeoutMs: HOOK_TIMEOUT_MS, intervalMs: 50, label: 'the QED64 page to start (globalThis.qed64)' });
}
/** V1: the PAGE's own boot failure (status().boot.failed). At QED64 84d594e the page sets it on two paths only (main.ts
 *  bootFail): main() rejecting (before the relay was bound: a refused parameter, a missing index; or after it: the editor
 *  mount), which nothing ever retries, and a halt before any session was ready (renderStatus: bootFail(death.message ||
 *  death.reason)). A death the relay retries never sets it. So every boot.failed is the hard "could not start" card, except
 *  (a) while halted (classifyStatus's own hard 'halted' card; a Reset's re-arm gets haltedGraceMs), and (b) after a re-arm
 *  of such a halt: boot.failed is sticky, but its message is the halt's death (lastDeath survives the re-arm until a session
 *  is ready, lsp-relay.ts), and the re-armed relay does retry, so classifyStatus's soft card applies. */
function hardBootFailure(st) {
  if (!(st && st.boot && st.boot.failed)) return null;
  if (st.phase === 'halted' || st.relay === 'halted') return null;
  const d = st.lastDeath;
  if (d && st.boot.message != null && st.boot.message === (d.message || d.reason)) return null; // the re-armed halt's own report
  return st.boot.message || 'the page reported a boot failure';
}
/** LEGACY: the page's own failure card (#bootcard.failed, #bootlabel = the message), e.g. manifests or core pack failed. */
function pageBootFailure(pw) {
  if (S.v1) return null;
  try {
    const card = pw.document.getElementById('bootcard');
    if (card && card.classList.contains('failed')) return (pw.document.getElementById('bootlabel') || {}).textContent || 'the page reported a boot failure';
  } catch { /* ignore */ }
  return null;
}

/**
 * Wait for 'ready' (or 'headerRefused') on our text.
 *  text: required relay.lastText (null = any);  vBefore: require status.version > vBefore (for graceMs only, when set);
 *  notSession: require a different session id;  w: the selection (Superseded when it changes; null = never);
 *  haltedGraceMs: tolerate a 'halted' relay this long (a Reset's didChange re-arms it asynchronously).
 * Pre-ready deaths show a soft card (QED64 retries up to 3 deaths / 120 s); 'halted' or the page's boot card is hard.
 */
async function waitReady({ text = null, vBefore = null, vMin = null, graceMs = null, haltedGraceMs = 0, notSession = null, w = null, timeoutMs, label, progress = false }) {
  let softShown = false;
  const t0 = now();
  // progress: a boot wait (see BOOT_TIMEOUT_MS): timeoutMs is re-armed by progress and only a true stall throws TIMEOUT
  if (progress) { const B = S.boot; B.waiting = label; B.t0 = t0; B.lastProgressAt = t0; }
  try {
    const r = await L.waitFor(() => {
      checkWanted(w);
      if (progress) bootCheck(t0, timeoutMs, label);
      ensureBridge('ready-wait');
      tapProgress();
      let st;
      if (S.v1) {
        pollApi();
        st = apiStatus(); if (!st) return null;
        const hf = !S.everReady && hardBootFailure(st); if (hf) throw new GalleryError('boot', 'QED64 could not start', hf);
      } else {
        const q = qed(); if (!q) { const pw = pageWin(); const f0 = pw && pageBootFailure(pw); if (f0) throw new GalleryError('boot', 'QED64 could not start', f0); return null; }
        try { st = q.status(); } catch { return null; }
      }
      const c = L.classifyStatus(st, S.everReady);
      if (c.hard && now() - t0 < haltedGraceMs) return null; // a reset's didChange has not re-armed the relay yet
      if (c.hard) throw new GalleryError('halted', 'The Lean checker stopped', `QED64 ${c.text}.`, { status: st });
      const pw = S.v1 ? null : pageWin(); const f = !S.v1 && pw && !S.everReady && pageBootFailure(pw); // V1: the soft card is classifyStatus's alone (hardBootFailure)
      if (c.soft || f) {
        if (!softShown) { softShown = true; showError({ kind: 'bootFailed', soft: true, retry: true, title: 'QED64 is having trouble starting', detail: `${f || c.text}. It retries on its own; this card closes if it recovers.`, raw: JSON.stringify(st, null, 2) }); }
      } else if (softShown) { softShown = false; hideErrorKind('bootFailed'); }
      if (notSession && st.session === notSession) return null;
      const relayText = docText();
      if (text !== null && relayText !== null && relayText !== text) return null;
      const inGrace = graceMs == null || now() - t0 < graceMs;
      if (vBefore != null && inGrace && !(st.version != null && st.version > vBefore)) return null;
      if (vMin != null && !(st.version != null && st.version >= vMin)) return null; // V1: the version setDocument resolved with (§2.3)
      if (S.v1 && st.relay !== 'serving') return null; // §2.2: ready = a final verdict while the relay serves
      if (st.phase === 'ready') return { st, refused: false };
      if (st.phase === 'headerRefused') return { st, refused: true };
      return null;
    }, { timeoutMs: progress ? Infinity : timeoutMs, intervalMs: 100, label });
    if (softShown) hideErrorKind('bootFailed');
    return r;
  } finally { if (progress) { S.boot.waiting = null; hideSlowNotice(); } }
}

// ---------------------------------------------------------------- storage seed
// The user's own buffer is never lost: the first displaced one is kept under SAVED_KEY and never overwritten;
// later distinct ones go to a bounded newest-first history (lib.js planSave). An example the user edited in the
// gallery is not a user buffer: it goes to its own one-slot key and never enters the history. "Open my saved
// buffer" opens the NEWEST kept buffer; when more than one is kept, a chooser next to it lists them all.
function readHistory() { try { const h = JSON.parse(localStorage.getItem(L.SAVED_HISTORY_KEY) || '[]'); return Array.isArray(h) ? h : []; } catch { return []; } }
/**
 * V1: keep ONE displaced text through the save plan, in its own try. 'none' when the text is not worth keeping (blank, the
 * seed, a pristine example); 'failed' when storage is blocked or the plan's read or write threw (e.g. QuotaExceededError).
 */
function keepDisplaced(prev, seedText, blocked) {
  if (typeof prev !== 'string' || L.planSave({ prev, seedText, saved: null, history: [], exampleTexts: S.exampleTexts }).action === 'none') return { action: 'none', error: null };
  if (blocked) return { action: 'failed', error: blocked };
  try {
    const plan = L.planSave({ prev, seedText, saved: localStorage.getItem(L.SAVED_KEY), history: readHistory(), exampleTexts: S.exampleTexts });
    if (plan.action === 'saved') localStorage.setItem(L.SAVED_KEY, plan.saved);
    else if (plan.action === 'history') localStorage.setItem(L.SAVED_HISTORY_KEY, JSON.stringify(plan.history));
    else if (plan.action === 'example') localStorage.setItem(L.EXAMPLE_EDIT_KEY, plan.exampleEdit);
    return { action: plan.action, error: null };
  } catch (e) { return { action: 'failed', error: String(e && e.message || e).slice(0, 200) }; }
}
function seedBuffer(text) {
  const out = { saved: false, action: 'none', error: null };
  // V1 (§3): embed mode — the page neither reads nor writes qed64.buffer, and neither do we; the example travels as #code=.
  // What this boot displaces is OUR document key (boot() force-writes the example into it next) and this tab's text: each
  // goes through the same save plan as a displaced qed64.buffer, in its own write, so a user's own text is never lost on a
  // gallery reload. action stays 'embed' unless something was kept.
  //   the STORED text first (the key a previous gallery load or another tab persisted; when held, its success releases the
  //   hold), then a text a previous boot could not keep (S.doc.unsaved, retried), then the newest text this gallery saw
  //   forwarded (memory; when held, persistDocument wrote it nowhere), each distinct text kept or failing on its own.
  // keepFailed 'key': the text that failed is the one in our key, so boot() holds it there. A text that failed and lived only in
  // memory becomes S.doc.unsaved (the notice offers to copy it). Blocked storage (the localStorage getter or a read throws):
  // nothing is stored, so nothing is held (blocked:true; a memory-only user text still becomes unsaved).
  if (S.v1) {
    out.action = 'embed'; out.blocked = false; out.keepFailed = null; out.unsaved = null;
    let blocked = null;
    try { localStorage.getItem(L.DOCUMENT_KEY); } catch (e) { blocked = String(e && e.message || e).slice(0, 200); }
    out.blocked = blocked !== null;
    const stored = blocked ? null : savedDocument(); const mem = S.doc.lastText; const prior = S.doc.unsaved;
    // the STORED text is its own candidate (deduplicated by text): when it differs from memory (another gallery tab's text under
    // the shared key, or a key this tab never wrote) and cannot be kept, boot() holds it instead of overwriting it. Not when it is
    // this tab's OWN last successful write and the tab is not held: memory supersedes it (a pending throttled write, or a later
    // write that failed), so keeping it too would spend a SAVED/history slot and storage on a stale version
    const ownStale = !S.doc.held && stored !== null && stored === S.doc.lastWritten;
    const cands = [{ text: ownStale ? null : stored, from: 'key' }, { text: prior && prior.text, from: 'unsaved' }, { text: mem, from: 'memory' }];
    const seen = new Set(); let lost = null; let lostPrior = null;
    for (const c of cands) {
      if (typeof c.text !== 'string' || seen.has(c.text)) continue;
      seen.add(c.text);
      const r = keepDisplaced(c.text, text, blocked);
      if (r.action === 'saved' || r.action === 'history') { out.saved = true; out.action = r.action; }
      else if (r.action === 'example') { if (!out.saved) out.action = 'example'; }
      else if (r.action === 'failed') {
        out.error = out.error || r.error;
        if (c.from === 'key') out.keepFailed = 'key';
        else if (c.from === 'memory') lost = { text: c.text, error: r.error };
        else lostPrior = { text: c.text, error: r.error, at: prior.at };
      }
    }
    // the newest text that failed wins the single memory slot (an older unsaved one is kept only if nothing newer failed)
    S.doc.unsaved = lost ? { ...lost, at: Math.round(now()) } : lostPrior;
    if (S.doc.unsaved) out.unsaved = { length: S.doc.unsaved.text.length, error: S.doc.unsaved.error };
    renderSaved();
    return out;
  }
  try {
    const prev = localStorage.getItem(L.BUFFER_KEY);
    const plan = L.planSave({ prev, seedText: text, saved: localStorage.getItem(L.SAVED_KEY), history: readHistory(), exampleTexts: S.exampleTexts });
    out.action = plan.action;
    if (plan.action === 'saved') { localStorage.setItem(L.SAVED_KEY, plan.saved); out.saved = true; }
    else if (plan.action === 'history') { localStorage.setItem(L.SAVED_HISTORY_KEY, JSON.stringify(plan.history)); out.saved = true; }
    else if (plan.action === 'example') localStorage.setItem(L.EXAMPLE_EDIT_KEY, plan.exampleEdit);
    localStorage.setItem(L.BUFFER_KEY, text);
  } catch (e) { out.error = String(e && e.message || e); }
  renderSaved();
  return out;
}
function savedList() { try { return L.savedEntries(localStorage.getItem(L.SAVED_KEY), readHistory()); } catch { return []; } }
function renderSaved() {
  const list = savedList();
  E.restore.hidden = list.length === 0;
  E.restorePick.hidden = list.length < 2;
  E.restorePick.replaceChildren(...list.map((e, i) => { const o = document.createElement('option'); o.value = String(i); o.textContent = e.label; return o; }));
  if (list.length) {
    E.restore.textContent = list.length > 1 ? 'Open' : 'Open my saved buffer';
    E.restore.title = list.length > 1
      ? `Opens the kept buffer chosen in the list (${list.length} kept: newest first; the first one ever saved is under ${L.SAVED_KEY}, later ones under ${L.SAVED_HISTORY_KEY}).`
      : `Opens the QED64 buffer you had before the gallery replaced it (${list[0].label}; kept under ${L.SAVED_KEY}).`;
  }
}
/** Open a kept user buffer (index into savedEntries, 0 = newest) in the editor: not an example, no card is current. */
async function restoreSaved(index) {
  const list = savedList();
  const i = Number.isInteger(index) ? index : (E.restorePick.hidden ? 0 : Number(E.restorePick.value) || 0);
  const entry = list[i];
  if (!entry) return false;
  const t = entry.text; const ed = editor(); const model = ed && ed.getModel();
  if ((S.v1 ? !editorPresent() : !model) || !S.booted) { showNotice('QED64 is still starting; open your saved buffer once it is ready.', { transient: true }); return false; }
  if (S.driving) { showNotice('Wait for the current example to finish loading, then try again.', { transient: true }); return false; }
  S.wanted = null; S.current = null; S.shownId = null; S.custom = true;
  markCurrent(null);
  history.replaceState(null, '', location.pathname + location.search);
  if (S.v1) { try { const p = api().setDocument(t, { cursor: { lineNumber: 1, column: 1 }, undoable: false }); if (p && p.catch) p.catch(() => {}); } catch { /* the status line says what happened */ } }
  else model.setValue(t);
  placeCursor(1, 1);
  announce(`Your saved QED64 buffer is open in the editor (${entry.label}).`);
  renderStatus(); renderChips();
  return true;
}

// ---------------------------------------------------------------- cursor
function placeCursor(lineNumber, column, { focus = true } = {}) {
  if (S.v1) {
    // api.setCursor clamps the line to [1, lineCount] and the column to [1, lineLength + 1] (§2.3); reveal by default
    const a = api(); if (!a) return false;
    try { if (focus) { try { E.frame.contentWindow.focus(); } catch { /* ignore */ } } return a.setCursor({ lineNumber: Math.max(1, lineNumber), column }, { focus }) === true; } catch { return false; }
  }
  const ed = editor(); if (!ed) return false;
  ensureBridge('cursor');
  try {
    const model = ed.getModel();
    const ln = Math.min(Math.max(1, lineNumber), model ? model.getLineCount() : lineNumber);
    ed.setPosition({ lineNumber: ln, column });
    ed.revealLineInCenter(ln);
    if (focus) { try { E.frame.contentWindow.focus(); } catch { /* ignore */ } ed.focus(); }
    return true;
  } catch { return false; }
}
function placeFirstCursor(ex, opts) { return placeCursor(ex.firstCursor.lineNumber, ex.firstCursor.column, opts); }
function gotoHint(id, h) {
  if (S.shownId === id && (S.phase === 'ready' || S.phase === 'refused') && editorPresent()) { placeCursor(h.lineNumber, h.column); return; }
  choose(id, { source: 'hint', cursor: { lineNumber: h.lineNumber, column: h.column } });
}

// ---------------------------------------------------------------- the driver: one operation at a time, latest selection wins
/** Select an example. Returns a promise that settles when it is shown (ready / refused) or fails / is superseded. */
function choose(id, opts = {}) {
  if (capsBlocked()) { // nothing boots on a browser that failed the capability check (the card says why)
    const e = new Error(`this browser lacks ${S.caps.lacks}`); e.code = 'UNSUPPORTED';
    const p = Promise.reject(e); p.catch(() => { /* hashchange etc. ignore the promise */ }); return p;
  }
  if (!S.byId.has(id)) return Promise.reject(new Error(`unknown example ${id}`));
  const token = ++S.token;
  S.wanted = { id, token, reset: !!opts.reset, force: !!opts.force, cursor: opts.cursor || null, focus: opts.focus !== false, source: opts.source || 'api' };
  S.current = id;
  if (S.notice && S.noticeTransient && opts.source !== 'initial') hideNotice();
  markCurrent(id);
  if (location.hash.slice(1) !== id) history.replaceState(null, '', `#${id}`);
  S.selLog.push({ token, id, source: S.wanted.source, outcome: null }); if (S.selLog.length > 60) S.selLog.splice(0, 20);
  const p = new Promise((resolve, reject) => S.waiters.push({ token, id, resolve, reject }));
  p.catch(() => { /* callers that ignore the promise must not see unhandled rejections */ });
  drive();
  return p;
}
function settle(w, err) {
  const keep = [];
  for (const x of S.waiters) {
    if (x.token > w.token) { keep.push(x); continue; }
    const log = S.selLog.find((l) => l.token === x.token);
    if (x.token === w.token || (!err && x.id === w.id)) { if (log) log.outcome = err ? (err.code || 'error') : 'ok'; (err ? x.reject(err) : x.resolve(snapshot())); }
    else { if (log) log.outcome = 'SUPERSEDED'; x.reject(new Superseded()); }
  }
  S.waiters = keep;
}
async function drive() {
  if (S.driving) return;
  S.driving = true;
  try {
    for (;;) {
      const w = S.wanted;
      if (!w || w.done) break;
      try {
        if (!S.booted || w.force) await boot(w);
        else await switchTo(w);
        if (S.wanted === w) { w.done = true; settle(w, null); break; }
      } catch (e) {
        if (e && e.code === 'SUPERSEDED') continue;
        failWith(e);
        if (S.wanted === w) { w.done = true; settle(w, e); break; }
      }
    }
  } finally { S.driving = false; renderStatus(); }
}
function failWith(e) {
  S.phase = 'error';
  finishOp();
  const ex = S.byId.get(S.current);
  if (e instanceof GalleryError) {
    if (e.kind === 'preflight') {
      showError({ kind: 'preflight', title: e.title, detail: e.detail, checks: e.checks, raw: e.raw || null });
    } else if (e.kind === 'boot' || e.kind === 'halted') {
      showError({ kind: e.kind, title: e.title, detail: `${e.detail} ${e.kind === 'boot' ? 'Check that the server is running and the overlay is paired, then try again.' : 'Try again to reload the page.'}`, raw: e.status ? JSON.stringify(e.status, null, 2) : null });
    } else showError({ kind: e.kind, title: e.title, detail: e.detail });
  } else if (e && e.code === 'TIMEOUT') {
    const late = e.stalled && S.boot.late ? ' If Lean finishes starting after all, this card closes by itself.' : '';
    showError({ kind: 'timeout', title: 'This is taking too long', detail: `${e.message}. The page may still be working; the status line keeps updating.${late}`, raw: JSON.stringify(S.lastStatus, null, 2) });
  } else {
    showError({ kind: 'internal', title: 'The gallery hit an unexpected error', detail: String(e && e.message || e), raw: String(e && e.stack || '') });
  }
  announce(`${ex ? ex.title : 'Example'} failed to load: ${S.error ? S.error.title : 'error'}`);
}

// ---------------------------------------------------------------- boot
async function boot(w) {
  const ex = S.byId.get(w.id);
  w.force = false;
  S.booted = false; S.everReady = false; S.shownId = null;
  bootReset();
  hideError(); hideNotice();
  S.phase = 'preflight'; setOp('preflight');
  showVeil('Checking the widgets overlay…');
  renderStatus();
  // 1. pairing preflight (never navigates on failure)
  if (!S.mem.ok) showNotice(`${S.mem.note}; ignoring the memory knob.`);
  else if (S.mem.note) showNotice(S.mem.note);
  const modules = Object.fromEntries(S.examples.map((e) => [e.id, e.module]));
  const choice = await L.chooseOverlay({ requested: S.requestedOverlay, buildId: S.pin.buildId, fetch: (u, i) => fetch(u, i), modules });
  S.choice = choice;
  if (!choice.ok) {
    const tried = choice.attempts.map((a) => a.overlay).join(', then ');
    throw new GalleryError('preflight', S.requestedOverlay ? `The “${choice.overlay}” overlay is not usable` : 'No usable widgets overlay',
      `Tried ${tried}. ${choice.result.notFound ? `/snapshots/${choice.overlay}/index.json was not found — build the overlay (scripts/showcase.sh overlay) or pass ?overlay=<dir>.` : 'The overlay is not paired with this QED64 runtime; nothing was loaded.'}`,
      { checks: choice.result.checks, raw: JSON.stringify(choice.attempts.map((a) => ({ overlay: a.overlay, ok: a.ok, failed: a.result.checks.filter((c) => !c.ok) })), null, 2) });
  }
  S.overlay = choice.overlay;
  S.availability = choice.result.availability;
  E.overlayBadge.textContent = `snapshot ${S.overlay}`;
  E.overlayBadge.title = `Snapshot overlay /snapshots/${S.overlay}/ — region imports: ${(choice.result.regionImports || ['(not listed)']).join(', ')}`;
  if (choice.fellBack) {
    const first = choice.attempts[0];
    showNotice(`${first.overlay} is ${first.result.notFound ? 'not built yet' : 'not usable'}; using ${S.overlay}.${S.availability && S.availability['dist-lens'] === false ? ' DistLens needs widgets8.' : ''}`);
  }
  if (S.availability && S.availability[ex.id] === false) showNotice(`${ex.title} is not in the ${S.overlay} overlay; QED64 will refuse its header.`);
  renderChips();

  // From here until the new page's hook the frame is OURS (V1: a frame-api now is no reload to adopt, e.g. a document that
  // was still loading when this boot retired it) and the previous document's api is gone with it.
  S.navigating = true; S.api.obj = null; S.api.doc = null; S.api.via = null;
  const memOn = S.mem.ok && S.mem.bytes != null;
  let hook;
  try {
    // 2. retire a previous page first: its pagehide handler unloads the relay (kills the worker, freeing its
    //    multi-GiB heap before the next boot) and no pending 400 ms buffer save can overwrite our seed.
    if (pageWin()) {
      E.frame.src = 'about:blank';
      await L.waitFor(() => !pageWin(), { timeoutMs: 10000, intervalMs: 50, label: 'the previous page to unload' }).catch(() => null);
      // V1: the page dropped its #code= (history.replaceState), so a new src that differs from the frame's URL only by the
      // fragment would be a same-document navigation (no new document, no frame-api): never continue on a page that stayed
      if (S.v1 && pageWin()) throw new GalleryError('internal', 'The previous QED64 page did not unload', 'The frame kept its document for 10 s after it was told to retire; the new example cannot be booted over it. Try again retires it once more.');
    }
    S.api.obj = null; S.api.doc = null; S.api.via = null; // whatever a retiring document announced meanwhile
    // 3. seed the boot document, 4. navigate
    // V1: no light session and no seed — the example travels as #code= (read once by the page, §3.1) and ?mem= as &memory=
    // (the page validates and clamps it, §4); the ONLY document the frame boots is the example, so no placeholder either
    const seedText = memOn && !S.v1 ? L.memPlaceholder(S.mem.gib) : ex.text;
    S.seed = seedBuffer(seedText);
    // what an adopted reload during THIS boot must re-seed (see onApi); but when the displaced text could not be kept
    // (S.seed.keepFailed 'key'), our key is its only stored copy: memory only, and a notice (holdDocument, storageNotice)
    if (S.v1) {
      if (S.seed.keepFailed === 'key') holdDocument(ex.text, S.seed.error);
      else { S.doc.held = null; persistDocument(ex.text, { force: true }); }
      storageNotice();
    }
    S.phase = 'booting'; setOp('boot');
    hideVeil();
    E.frame.src = S.v1 ? L.frameUrl(S.overlay, { embed: true, memoryGiB: memOn ? S.mem.gib : null, code: ex.text }) : L.frameUrl(S.overlay);
    watchBridge();
    renderStatus();

    // 5. the page's hook, then ready
    hook = await waitForHook(null);
  } finally { S.navigating = false; }
  S.bootDoc = bootToken();
  if (S.v1) { requireCapabilities(hook); bridgeDecision(hook); }
  else if (!ensureBridge('hook')) throw new GalleryError('internal', 'The RPC bridge could not be installed', 'gallery/qed64-bridge.js did not load or the page window is not reachable.');
  let r;
  if (memOn && !S.v1) r = await memBoot(w, ex);
  else {
    try { r = await waitReady({ text: ex.text, w: null, timeoutMs: BOOT_TIMEOUT_MS, label: `${ex.title} to be checked (first boot)`, progress: true }); }
    catch (e) {
      // a true stall: the card shows, and a later 'ready' on this page still finishes the boot (lateBootCheck)
      if (e && e.code === 'TIMEOUT') S.boot.late = { kind: 'boot', id: ex.id, text: ex.text, doc: S.bootDoc, t0: S.op.t0 };
      throw e;
    }
  }
  S.bootMs = finishOp();
  S.booted = true; S.everReady = true;
  S.shownId = ex.id;
  shown(ex, r, w);
}

/**
 * ?mem=<GiB> (stage A X5). The relay constructs the FIRST session inside its constructor and calls start()
 * synchronously, which reads session.initialBytes into lean.boot() before the page even assigns
 * globalThis.qed64 (bundle: `s=new Jtn(...)` then `globalThis.qed64={...}`). So no same-origin wrapper can reach
 * the first session. The knob therefore makes the first session LIGHT: the seeded document has no import lines,
 * so EDITOR_POLICY boots ['init'] at 256 MiB. Once it is ready we wrap relay.makeSession (an own instance
 * property; the relay calls this.makeSession on every reboot) so each new session's initialBytes is set before
 * its start() runs (reboot() awaits the 1.5 s settle first), then relay.restart({snapshots:['init','mathlib']})
 * and setValue(example). The session that loads the widgets region is thus the wrapped one, and so is every
 * later crash/heartbeat reboot. Cost: one light init boot (a few seconds). We verify relay.session.initialBytes.
 */
async function memBoot(w, ex) {
  const light = await waitReady({ text: null, w: null, timeoutMs: BOOT_TIMEOUT_MS, label: 'the light first session (?mem)', progress: true });
  const q = qed();
  const relay = q.relay;
  S.mem.light = { session: light.st.session, initialBytes: relay.session && relay.session.initialBytes };
  if (!relay.__showcaseMem) {
    const orig = relay.makeSession;
    if (typeof orig !== 'function') throw new GalleryError('internal', 'The memory knob cannot attach', 'qed64.relay.makeSession is not a function in this QED64 build.');
    const info = { bytes: S.mem.bytes, sessions: [], errors: [] };
    relay.makeSession = function (opts) {
      const s = orig.call(this, opts);
      try { s.initialBytes = info.bytes; info.sessions.push({ id: s.id, initialBytes: s.initialBytes, snapshots: s.snapshots ? [...s.snapshots] : null }); } catch (e) { info.errors.push(String(e && e.message || e)); }
      return s;
    };
    relay.__showcaseMem = info;
  }
  relay.__showcaseMem.bytes = S.mem.bytes;
  S.mem.wrapped = true;
  if (!(relay.state && relay.state.kind === 'serving')) await L.waitFor(() => relay.state && relay.state.kind === 'serving', { timeoutMs: 30000, label: 'the relay to serve' });
  relay.restart({ snapshots: ['init', 'mathlib'] });
  editor().getModel().setValue(ex.text);
  const r = await waitReady({ text: ex.text, notSession: light.st.session, w: null, timeoutMs: BOOT_TIMEOUT_MS, label: `${ex.title} on the ${S.mem.gib} GiB session`, progress: true });
  S.mem.sessions = relay.__showcaseMem.sessions.slice();
  S.mem.applied = !!(relay.session && relay.session.initialBytes === S.mem.bytes);
  // best effort: what the worker actually committed
  try { relay.session.lean.request('telemetry').then((t) => { S.mem.telemetry = (t && (t.memory || (t.result && t.result.memory))) || null; }, () => {}); } catch { /* ignore */ }
  return r;
}

/** After a reload we did not start (e.g. the page's own Reload button): re-attach without navigating. */
async function adoptReload() {
  if (S.adopting) return;
  // Take the driver lock: a selection made meanwhile must wait for the adopted page instead of booting a second
  // navigation over it (drive() returns while S.driving; we run it once the page is adopted).
  S.adopting = true; S.driving = true;
  S.booted = false; S.everReady = false; S.bootDoc = null;
  bootReset();
  S.phase = 'booting'; setOp('reload');
  watchBridge();
  const id = S.current;
  try {
    const hook = await waitForHook(null);
    S.bootDoc = bootToken();
    if (S.v1) { requireCapabilities(hook); bridgeDecision(hook); }
    let r;
    try { r = await waitReady({ text: null, w: null, timeoutMs: BOOT_TIMEOUT_MS, label: 'the reloaded page', progress: true }); }
    catch (e) { if (e && e.code === 'TIMEOUT') S.boot.late = { kind: 'reload', id, text: null, doc: S.bootDoc, t0: S.op.t0 }; throw e; }
    S.bootMs = finishOp(); S.booted = true; S.everReady = true;
    adoptShown(r, id);
  } catch (e) { failWith(e); }
  finally {
    S.driving = false; S.adopting = false;
    if (S.wanted && !S.wanted.done) drive();
    renderStatus();
  }
}

/** The adopted page is ready: follow the example it shows (or none: the user's own buffer). */
function adoptShown(r, id) {
  const txt = editorText();
  const match = S.examples.find((e) => e.text === txt);
  S.shownId = match ? match.id : null;
  if (match) {
    // the page restored its own buffer: follow it (never overwrite what the page shows, it may hold edits)
    if (match.id !== id) { S.current = match.id; markCurrent(match.id); history.replaceState(null, '', `#${match.id}`); }
    shown(match, r, null);
  } else { S.phase = r.refused ? 'refused' : 'ready'; renderStatus(); renderChips(); }
}

// ---------------------------------------------------------------- switch
async function switchTo(w) {
  const ex = S.byId.get(w.id);
  if (S.v1) return switchToV1(w, ex);
  const ed = editor();
  const model = ed && ed.getModel();
  if (!model) { S.booted = false; return boot(w); }
  hideError();
  S.phase = 'switching'; setOp(w.reset ? 'reset' : 'switch');
  renderStatus();
  ensureBridge('switch');
  const st0 = qStatus();
  const halted = !!(st0 && (st0.phase === 'halted' || st0.relay === 'halted'));
  // A stuck checker (L7) never answers a didChange: Reset must restart it too (after the text change reached the relay,
  // so the fresh worker boots on the example).
  const stalled = !halted && (S.stall.active || stallIdleMs(st0) >= STALL_MS);
  const vBefore = st0 ? st0.version : null;
  const identical = model.getValue() === ex.text;
  let wait;
  if (stalled) {
    model.setValue(ex.text);
    const relay0 = qed() && qed().relay;
    await L.waitFor(() => { checkWanted(w); return relay0 && relay0.lastText === ex.text; }, { timeoutMs: 5000, intervalMs: 50, label: 'the reset text to reach the relay' }).catch((e) => { if (e && e.code === 'SUPERSEDED') throw e; });
    restartLean('reset');
    wait = { vBefore: null };
  } else if (!identical) { model.setValue(ex.text); wait = { vBefore }; }
  else if (w.reset || halted) {
    // Reset: setValue even on identical text — a halted relay re-arms only on a didChange (lsp-relay.ts fromClient).
    // If Monaco/lean4monaco send no change for identical content, accept 'ready' on this text after 3 s.
    model.setValue(ex.text); wait = { vBefore, graceMs: 3000 };
  } else wait = { vBefore: null }; // already this text: just re-place the cursor once ready
  if (halted) wait.haltedGraceMs = 10000; // the didChange reaches the relay asynchronously
  if (S.availability && S.availability[ex.id] === false) showNotice(`${ex.title} is not in the ${S.overlay} overlay; QED64 will refuse its header.`);
  else if (S.notice && /refuse/.test(S.notice)) hideNotice();
  let r = await waitReady({ text: ex.text, ...wait, w, timeoutMs: SWITCH_TIMEOUT_MS, label: `${ex.title} to be checked` });
  checkWanted(w);
  // A session booted for a header without Mathlib (e.g. the page reloaded into a user's own init-only buffer) does not
  // widen by itself: QED64 refuses the Mathlib header. Restart the relay on [init, mathlib] — the same call the page's
  // own "Load exact imports" path uses (lsp-relay.ts restart) — and wait for the example on the new session.
  const relay = qed() && qed().relay;
  const snaps = relay && relay.session && relay.session.snapshots ? [...relay.session.snapshots] : null;
  if (r.refused && snaps && !snaps.includes('mathlib') && relay.state && relay.state.kind === 'serving') {
    const old = r.st.session;
    showNotice(`Loading the widgets environment for ${ex.title} (the page had started without Mathlib)…`);
    relay.restart({ snapshots: ['init', 'mathlib'] });
    r = await waitReady({ text: ex.text, notSession: old, w, timeoutMs: SWITCH_TIMEOUT_MS, label: `${ex.title} on a Mathlib session` });
    checkWanted(w);
    if (!r.refused) hideNotice();
  }
  S.lastSwitchMs = finishOp();
  S.shownId = ex.id;
  shown(ex, r, w);
}

/**
 * V1 switch (contract item 5): api.setDocument(text, {cursor, focus}) resolves {version, unchanged} once the relay forwarded the
 * text (identical text: {unchanged:true} at the current version, nothing sent), then the polling wait of waitReady at
 * status.version >= that version. A halted relay: api.restart() re-arms it (no arguments), then the text. A stalled checker
 * (L7): the text, then api.restart(). A refused header on a session without 'mathlib' (status().snapshots):
 * api.restart({snapshots:['init','mathlib']}) and the wait on the replacement session (afterSession = fromSession).
 */
async function switchToV1(w, ex) {
  const a = api();
  if (!a || !editorPresent()) { S.booted = false; return boot(w); }
  hideError();
  S.phase = 'switching'; setOp(w.reset ? 'reset' : 'switch');
  renderStatus();
  const st0 = apiStatus();
  const halted = !!(st0 && (st0.phase === 'halted' || st0.relay === 'halted'));
  const stalled = !halted && (S.stall.active || stallIdleMs(st0) >= STALL_MS);
  const cur = w.cursor || { lineNumber: ex.firstCursor.lineNumber, column: ex.firstCursor.column };
  // undoable:false: a whole-document replacement must not be one Ctrl+Z step back to the previous example (legacy setValue
  // cleared Monaco's undo stack; page-api.ts setDocument pushes an undo stop unless told not to). focus:false: the cursor
  // moves now, but keyboard focus stays where the visitor is (the rail) until the verdict; shown() focuses after 'ready',
  // as legacy does. Focusing here let a keystroke meant for the rail edit the buffer mid-wait (the text check then never
  // passes: the 330 s timeout card), and a superseded selection would take focus for an example never shown.
  const setOpts = { cursor: cur, focus: false, undoable: false };
  const setDoc = (timeoutMs) => raced(a.setDocument(ex.text, setOpts), w, timeoutMs, `${ex.title}'s text to reach the relay`);
  let wait;
  if (halted) {
    let rr = { accepted: false }; try { rr = a.restart() || rr; } catch (e) { rr = { accepted: false, error: String(e && e.message || e).slice(0, 200) }; }
    S.stall.events.push({ t: Math.round(now()), source: 'reset-halted', how: rr.accepted ? 'api.restart' : 'none', fromSession: rr.fromSession ?? null, error: rr.error }); if (S.stall.events.length > 60) S.stall.events.splice(0, 20);
    await setDoc(15000).catch((e) => { if (e && e.code === 'SUPERSEDED') throw e; }); // a re-arm forwards the text into the fresh session
    wait = { vBefore: null, haltedGraceMs: 10000, notSession: rr.accepted && rr.fromSession ? rr.fromSession : null };
  } else if (stalled) {
    // A stuck checker never answers a didChange: the relay's JS side still forwards the text (its promise resolves), then
    // a restart boots a fresh worker on the example.
    await setDoc(5000).catch((e) => { if (e && e.code === 'SUPERSEDED') throw e; });
    restartLean('reset');
    wait = { vBefore: null };
  } else {
    let r = null;
    try { r = await setDoc(15000); } catch (e) { if (e && e.code === 'SUPERSEDED') throw e; r = null; } // a slow forward: fall back to the legacy version rule
    if (r && r.unchanged) wait = { vBefore: null, vMin: r.version ?? null };            // already this text: ready at the current version, then the cursor
    else if (r) wait = { vMin: r.version ?? null, vBefore: r.version == null ? (st0 ? st0.version : null) : null };
    // the forward is still pending: the version guard stays STRICT (no grace). docText() is the editor buffer, which
    // setDocument changed at once, so a lapsing guard would accept the previous text's verdict at the old version.
    else wait = { vBefore: st0 ? st0.version : null };
  }
  if (S.availability && S.availability[ex.id] === false) showNotice(`${ex.title} is not in the ${S.overlay} overlay; QED64 will refuse its header.`);
  else if (S.notice && /refuse/.test(S.notice)) hideNotice();
  let r = await waitReady({ text: ex.text, ...wait, w, timeoutMs: SWITCH_TIMEOUT_MS, label: `${ex.title} to be checked` });
  checkWanted(w);
  const snaps = r.st.snapshots;
  if (r.refused && Array.isArray(snaps) && !snaps.includes('mathlib') && r.st.relay === 'serving') {
    const old = r.st.session;
    showNotice(`Loading the widgets environment for ${ex.title} (the page had started without Mathlib)…`);
    let rr = { accepted: false }; try { rr = a.restart({ snapshots: ['init', 'mathlib'] }) || rr; } catch (e) { rr = { accepted: false, error: String(e && e.message || e).slice(0, 200) }; }
    S.stall.events.push({ t: Math.round(now()), source: 'widen', how: rr.accepted ? 'api.restart' : 'none', fromSession: rr.fromSession ?? old, error: rr.error }); if (S.stall.events.length > 60) S.stall.events.splice(0, 20);
    if (rr.accepted) {
      r = await waitReady({ text: ex.text, notSession: rr.fromSession || old, w, timeoutMs: SWITCH_TIMEOUT_MS, label: `${ex.title} on a Mathlib session` });
      checkWanted(w);
      if (!r.refused) hideNotice();
    }
  }
  S.lastSwitchMs = finishOp();
  S.shownId = ex.id;
  shown(ex, r, w);
}

function shown(ex, r, w) {
  S.phase = r.refused ? 'refused' : 'ready';
  S.edited = false; S.custom = false;
  if (r.refused) {
    const miss = (r.st.header && r.st.header.missing) || [];
    showNotice(`QED64 refused the header${miss.length ? `: ${miss.join(', ')} ${miss.length === 1 ? 'is' : 'are'} not in the ${S.overlay} overlay` : ''}.`);
  }
  hideVeil();
  const cur = w && w.cursor;
  if (!w || S.wanted === w) {
    if (cur) placeCursor(cur.lineNumber, cur.column, { focus: w.focus });
    else placeFirstCursor(ex, { focus: !w || w.focus });
  }
  renderStatus(); renderChips();
  announce(`${ex.title} ${r.refused ? 'loaded, but QED64 refused its header' : 'is ready'}. Cursor on line ${cur ? cur.lineNumber : ex.firstCursor.lineNumber}.`);
}

// ---------------------------------------------------------------- toolbar
E.reset.addEventListener('click', () => {
  const id = S.current; if (!id) return;
  if (!S.booted) { choose(id, { source: 'reset', force: true }); return; }
  choose(id, { source: 'reset', reset: true });
});
E.copy.addEventListener('click', async () => {
  const ex = S.byId.get(S.current); if (!ex) return;
  let ok = false;
  try { await navigator.clipboard.writeText(ex.text); ok = true; } catch {
    const ta = document.createElement('textarea'); ta.value = ex.text; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.append(ta); ta.select();
    try { ok = document.execCommand('copy'); } catch { ok = false; }
    ta.remove();
  }
  const idle = E.copyLabel.dataset.idle || (E.copyLabel.dataset.idle = E.copyLabel.innerHTML);
  E.copyLabel.textContent = ok ? 'Copied ✓' : 'Copy failed';
  announce(ok ? `${ex.title} example copied: paste it into a VS Code project that depends on Mathlib and ${ex.module}.` : 'Copy failed.');
  setTimeout(() => { E.copyLabel.innerHTML = idle; }, 1800);
});
E.select.addEventListener('change', () => { if (E.select.value) choose(E.select.value, { source: 'select' }); });
E.restore.addEventListener('click', () => { restoreSaved(); });

// ---------------------------------------------------------------- keyboard: rail roving focus, F6 between rail and editor
E.list.addEventListener('keydown', (ev) => {
  const btn = ev.target.closest && ev.target.closest('.card-main'); if (!btn) return;
  const ids = S.examples.map((e) => e.id);
  const i = ids.indexOf(btn.dataset.id);
  let j = null;
  if (ev.key === 'ArrowDown' || ev.key === 'ArrowRight') j = Math.min(ids.length - 1, i + 1);
  else if (ev.key === 'ArrowUp' || ev.key === 'ArrowLeft') j = Math.max(0, i - 1);
  else if (ev.key === 'Home') j = 0;
  else if (ev.key === 'End') j = ids.length - 1;
  if (j === null) return;
  ev.preventDefault();
  setRoving(ids[j]);
  S.byId.get(ids[j]).el.querySelector('.card-main').focus();
});
function focusRail() { const ex = S.byId.get(S.current) || S.examples[0]; if (ex && ex.el && getComputedStyle($('rail')).display !== 'none') ex.el.querySelector('.card-main').focus(); else E.select.focus(); }
function focusEditor() {
  if (S.v1) { const a = api(); let ok = false; try { E.frame.contentWindow.focus(); } catch { /* ignore */ } try { ok = !!(a && a.focus()); } catch { ok = false; } if (!ok) E.frame.focus(); return; }
  const ed = editor(); if (ed) { try { E.frame.contentWindow.focus(); } catch { /* ignore */ } ed.focus(); } else E.frame.focus();
}
document.addEventListener('keydown', (ev) => { if (ev.key === 'F6') { ev.preventDefault(); focusEditor(); } });
// The skip link targets the editor. Followed as a plain href="#qed64-frame" it rewrote the deep-link hash (#<pkg>) and the
// hashchange handler then reported "There is no example called “qed64-frame”" (UX suite C17, out/ux/dev12): move the
// focus into Monaco without touching the URL.
{ const skip = $('skip-link'); if (skip && skip.addEventListener) skip.addEventListener('click', (ev) => { ev.preventDefault(); focusEditor(); }); }
// F6 inside the QED64 page (Monaco keeps Tab for indentation, so Tab cannot leave the editor): back to the rail.
function installFrameKeys() {
  const pw = pageWin(); if (!pw || pw.__showcaseKeys) return;
  try {
    pw.__showcaseKeys = true;
    pw.addEventListener('keydown', (ev) => { if (ev.key === 'F6') { ev.preventDefault(); ev.stopPropagation(); window.focus(); focusRail(); } }, true);
  } catch { /* ignore */ }
}
setInterval(installFrameKeys, 1000);

window.addEventListener('hashchange', () => {
  if (capsBlocked()) return; // the capability card is up and nothing may boot
  const h = L.parseHash(location.hash, S.examples.map((e) => e.id));
  if (h.id && h.id !== S.current) choose(h.id, { source: 'hash' });
  else if (h.bad !== null) showNotice(`There is no example called “${h.bad}”; the link was ignored.`, { transient: true });
});

// ---------------------------------------------------------------- test API (Playwright)
function snapshot() {
  const ed = editor(); const a = api();
  let pos = null; try { pos = S.v1 ? (a ? a.getCursor() : null) : ed ? ed.getPosition() : null; } catch { pos = null; }
  const ast = S.v1 ? apiStatus() : null;
  if (ast) { observeApiLiveness(ast); memApplied(ast); } // what the monitor mirrors every 250 ms, refreshed for this reading
  return {
    mode: S.v1 ? 'v1' : 'legacy', modeSource: S.modeSource,
    api: { present: !!a, revision: S.v1 ? S.api.revision : null, embed: !!(a && S.api.embed), via: a ? S.api.via : null, capabilities: a && S.api.capabilities ? { ...S.api.capabilities } : null, missing: S.api.missing.slice(),
      pinRevision: S.pin ? S.pin.apiRevision ?? null : null, servedRevision: S.servedRevision, docs: S.api.docs, adopted: S.api.adopted, adoptSet: S.api.adoptSet, events: { ...S.api.counts }, deaths: S.api.deaths },
    document: { version: S.doc.version, length: S.doc.length, persisted: S.doc.persisted, lastEventAgoMs: S.doc.lastEventAt == null ? null : Math.round(now() - S.doc.lastEventAt), writes: S.doc.writes, error: S.doc.error, held: S.doc.held ? { ...S.doc.held } : null, unsaved: S.doc.unsaved ? { length: S.doc.unsaved.text.length, error: S.doc.unsaved.error, at: S.doc.unsaved.at, copied: !!S.doc.unsaved.copied } : null },
    phase: S.phase, current: S.current, shown: S.shownId, overlay: S.overlay, requestedOverlay: S.requestedOverlay,
    fellBack: S.choice ? S.choice.fellBack : null,
    preflight: S.choice ? { ok: S.choice.ok, overlay: S.choice.overlay, attempts: S.choice.attempts.map((a) => ({ overlay: a.overlay, ok: a.ok, notFound: a.result.notFound, failed: a.result.checks.filter((c) => !c.ok).map((c) => c.id) })), availability: S.availability, regionImports: S.choice.result.regionImports } : null,
    booted: S.booted, everReady: S.everReady, bootMs: S.bootMs, lastSwitchMs: S.lastSwitchMs,
    op: { label: S.op.label, elapsedMs: Math.round(now() - S.op.t0), doneMs: S.op.doneMs == null ? null : Math.round(S.op.doneMs) },
    statusLine: S.statusLine ? { ...S.statusLine } : null,
    error: S.error, notice: S.notice, seed: S.seed, edited: S.edited, custom: S.custom,
    caps: S.caps ? { ok: S.caps.ok, hard: S.caps.hard.slice(), soft: S.caps.soft.slice(), missing: S.caps.missing.slice(), lacks: S.caps.lacks, deviceMemory: S.caps.deviceMemory, checks: S.caps.checks.map((c) => ({ ...c })), override: !!S.capsOverride } : null,
    saved: (() => { try { return { present: localStorage.getItem(L.SAVED_KEY) !== null, history: readHistory().length, entries: savedList().map((e) => e.label), exampleEdit: localStorage.getItem(L.EXAMPLE_EDIT_KEY) !== null }; } catch { return null; } })(),
    mem: { requestedGiB: S.mem.gib, bytes: S.mem.bytes, ok: S.mem.ok, wrapped: S.mem.wrapped, applied: S.mem.applied, light: S.mem.light, sessions: S.mem.sessions, telemetry: S.mem.telemetry, memory: ast && ast.memory ? { ...ast.memory } : null },
    bridge: { installed: !!(pageWin() && pageWin().__showcaseBridge), stoodDown: S.bridge.stoodDown, capabilityMismatch: S.bridge.capabilityMismatch, installs: S.bridge.installs.slice(), late: S.bridge.late || 0 },
    cursor: pos ? { lineNumber: pos.lineNumber, column: pos.column } : null,
    qed64: (() => {
      const st = qStatus(); if (!st) return null;
      const base = { phase: st.phase, version: st.version, header: st.header, session: st.session, relay: st.relay, rebootReason: st.rebootReason ?? null, lastDeath: st.lastDeath, collision: st.collision || null };
      // V1: the api's own projections (§2.2) — offer, snapshots, memory, boot {stage,label,done,failed,overlay}, liveness
      return a ? { ...base, offer: st.offer ?? null, snapshots: st.snapshots ?? null, memory: st.memory ?? null, boot: st.boot ? { ...st.boot } : null, liveness: st.liveness ? { ...st.liveness } : null } : base;
    })(),
    selections: S.selLog.slice(-20).map((l) => ({ ...l })),
    stall: { thresholdMs: S.stall.thresholdMs, active: S.stall.active, variant: S.stall.active ? S.stall.variant || null : null, idleMs: Math.round(stallIdleMs()), shown: S.stall.shown, restarts: S.stall.restarts, progressMsgs: S.stall.progressMsgs, tapped: !!S.stall.tapped, source: S.stall.source, events: S.stall.events.slice(-20) },
    liveness: liveSnapshot(),
    boot: (() => { const B = S.boot; return { timeoutMs: B.timeoutMs, stallMs: B.stallMs, noticeMs: B.noticeMs, waiting: B.waiting, elapsedMs: B.waiting ? Math.round(now() - B.t0) : null, idleMs: B.waiting ? Math.round(now() - B.lastProgressAt) : null,
      bytes: B.bytes, current: B.current ? { ...B.current } : null, label: B.label, uiTapped: !!B.ui, uiWrapped: B.uiWrapped.slice(), uiCalls: B.uiCalls, source: B.source, apiBootEvents: B.apiBootEvents, sources: { ...B.sources }, resources: B.resources, resourceUrls: B.resourceUrls.size,
      pageBootOverlay: pageBootOverlay(), noticeShown: B.noticeShown, stalls: B.stalls, recovered: B.recovered, latePending: !!B.late, events: B.events.slice(-20) }; })(),
  };
}
window.__showcase = {
  version: 9,
  select: (pkg) => choose(pkg, { source: 'api' }),
  status: () => snapshot(),
  bridgeStats: () => { const w = pageWin(); const b = w && w.__showcaseBridge; return b ? JSON.parse(JSON.stringify(b)) : null; },
  currentText: () => editorText(),
  // V1 (§2.3): the page's one explicit action ("Load exact imports"), and running it as its button would; legacy: null / false
  offer: () => { const st = apiStatus(); return st ? st.offer ?? null : null; },
  acceptOffer: () => { const a = api(); if (!a) return false; try { return a.acceptOffer() === true; } catch { return false; } },
  examples: () => S.examples.map((e) => ({ id: e.id, title: e.title, module: e.module, phase: e.phase, firstCursor: e.firstCursor, textSha256: e.textSha256 })),
  reset: () => (S.current ? choose(S.current, { source: 'api', reset: true }) : Promise.reject(new Error('no current example'))),
  restoreSaved: (i = 0) => restoreSaved(Number.isInteger(i) ? i : 0),
  liveness: (mode) => {
    if (mode !== undefined) {
      if (!LIVE_MODES.includes(mode)) throw new Error(`liveness mode must be one of ${LIVE_MODES.join(', ')}`);
      if (mode !== S.live.mode) { liveEvent({ source: 'mode', from: S.live.mode, to: mode }); S.live.mode = mode; S.live.outstanding = null; S.live.misses = 0; S.live.wedgedActive = false; S.live.armAt = now(); }
    }
    return liveSnapshot();
  },
};

// ---------------------------------------------------------------- start
async function getJson(name) {
  const r = await fetch(name, { cache: 'no-cache' });
  if (!r.ok) throw new Error(`${name}: HTTP ${r.status}`);
  return r.json();
}
/**
 * Which mode the SERVED page needs, when gallery/pin.json may not describe it. pin.json is built for the ACTIVE pin; the
 * local server can serve a STAGED pin's release beside it (`SHOWCASE_PIN=<id> serve.mjs`, every response carrying
 * `X-Showcase-Pin: <id> <buildId>`). Only then (the header names another pin than pin.json) is the served release asked
 * for its revision: serve.mjs sends it on every response as `X-Showcase-Api: <apiRevision>|none|invalid` (read at start from the
 * served release's dist/qed64-build.json, schema qed64.build/v1), so the pin.json response already carries it and nothing
 * is fetched. Only when that header is absent or not a revision/'none' (an older serve.mjs; 'invalid': a release whose file
 * cannot be read or has another schema; serve.mjs sends /showcase/pin.json no-store, so no 304 replays a stale one) is the
 * release asked directly: /qed64-build.json (QED64 writes it next to its index.html, schema qed64.build/v1, apiRevision
 * since the embedding contract v1; releases of pins A–E have none: 404 = legacy). Production and the active pin (no
 * X-Showcase-Pin, or the same pin) never probe. Returns {revision, shell, servedPin} or null (pin.json decides).
 */
const API_REVISION_RE = /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/; // an embedding-contract revision (EMBEDDING.md §4: '1.0.0')
async function servedBuild(pin, header, apiHeader) {
  const servedPin = header ? String(header).trim().split(/\s+/)[0] : null;
  if (!servedPin || servedPin === pin.pin) return null;
  // only a revision or 'none' counts; anything else ('invalid': the release's file is unreadable or of another schema, or a
  // stray value) is treated as absent: the probe below, whose own checks fall back to pin.json
  const api = apiHeader == null ? '' : String(apiHeader).trim();
  if (api === 'none' || API_REVISION_RE.test(api)) return { revision: api === 'none' ? null : api, shell: null, servedPin };
  let r; try { r = await fetch('/qed64-build.json', { cache: 'no-cache' }); } catch { return null; }
  if (r.status === 404) return { revision: null, shell: null, servedPin };
  if (!r.ok) return null;
  let j; try { j = await r.json(); } catch { return null; }
  if (!j || j.schema !== 'qed64.build/v1') return null;
  return { revision: typeof j.apiRevision === 'string' && j.apiRevision ? j.apiRevision : null, shell: typeof j.shell === 'string' ? j.shell : null, servedPin };
}
// ---------------------------------------------------------------- browser capabilities (lib.js checkCapabilities)
/** The browser's own globals, read at start (tests override them before the page loads). */
function capsEnv() {
  let dm; try { dm = navigator.deviceMemory; } catch { dm = undefined; }
  return { crossOriginIsolated: globalThis.crossOriginIsolated, SharedArrayBuffer: globalThis.SharedArrayBuffer, WebAssembly: globalThis.WebAssembly, BigInt: globalThis.BigInt, deviceMemory: dm };
}
/** A browser that failed the capability check boots nothing, unless the only failure is memory and the visitor chose "Try anyway". */
function capsBlocked() { return !!(S.caps && !S.caps.ok && !(S.capsOverride && S.caps.hard.length === 0)); }
function showUnsupported() {
  const c = S.caps; const hard = c.hard.length > 0;
  S.phase = 'unsupported'; finishOp(); hideVeil();
  showError({
    kind: 'unsupported', soft: !hard, action: hard ? null : 'try-anyway', retry: !hard, dismiss: false, stockLink: false,
    title: hard ? 'This browser cannot run the Lean widget gallery' : 'This device may not have enough memory',
    detail: `${L.BROWSER_NEED}; your browser lacks ${c.lacks}.${hard ? ' Nothing was loaded.' : ' Lean may fail to start or the tab may crash; nothing has been loaded yet.'}`,
    checks: c.checks.map((x) => ({ id: x.id, ok: x.ok, detail: `${x.need}: ${x.detail}` })),
    raw: JSON.stringify({ missing: c.missing, deviceMemory: c.deviceMemory, userAgent: (() => { try { return navigator.userAgent; } catch { return null; } })() }, null, 2),
  });
  announce(hard ? `This browser cannot run the gallery: it lacks ${c.lacks}.` : 'This device may not have enough memory for the gallery. Try anyway is offered.');
  renderStatus();
}
/** "Try anyway" on the memory card: boot as usual. */
function tryAnyway() {
  if (!S.caps || S.caps.hard.length) return;
  S.capsOverride = true; hideError();
  const h = L.parseHash(location.hash, S.examples.map((e) => e.id));
  choose(S.current || h.id || S.examples[0].id, { source: 'initial' });
}

async function start() {
  setOp('starting');
  // 0. what the browser can do, before anything is fetched from QED64 or the iframe navigates
  S.caps = L.checkCapabilities(capsEnv());
  if (S.caps.hard.length) { showUnsupported(); return; }
  try {
    // both requests in flight at once (as before the served-pin header was read); pin.json's response is awaited first for its header
    const pinP = fetch('pin.json', { cache: 'no-cache' }); const exP = getJson('examples.json'); exP.catch(() => {});
    const pinRes = await pinP;
    if (!pinRes.ok) throw new Error(`pin.json: HTTP ${pinRes.status}`);
    let header = null; let apiHeader = null;
    try { header = pinRes.headers.get('X-Showcase-Pin'); apiHeader = pinRes.headers.get('X-Showcase-Api'); } catch { header = null; apiHeader = null; }
    const [pin, data] = await Promise.all([pinRes.json(), exP]);
    if (!pin || !/^wasm64-[0-9a-f]{16}$/.test(pin.buildId || '')) throw new Error('pin.json has no buildId (run node scripts/build-gallery.mjs)');
    if (!data || !Array.isArray(data.examples) || data.examples.length === 0) throw new Error('examples.json has no examples (run node scripts/build-gallery.mjs)');
    S.pin = pin;
    // embedding contract v1 (see the header): pin.json's apiRevision, unless the server serves another pin's release than
    // pin.json describes (servedBuild): then that release's own. null on pins A–E: the legacy flow.
    const pinRev = pin.apiRevision ?? null;
    const served = await servedBuild(pin, header, apiHeader);
    S.modeSource = served ? 'served' : 'pin.json'; S.servedRevision = served ? served.revision : null;
    const rev = served ? served.revision : pinRev;
    if (served && served.revision !== pinRev) console.warn(`[showcase] the server serves QED64 pin ${served.servedPin} (apiRevision ${JSON.stringify(served.revision)}) but gallery/pin.json describes ${pin.pin} (${JSON.stringify(pinRev)}): following the served page (${served.revision != null ? 'v1' : 'legacy'} mode)`);
    S.v1 = rev != null;
    S.api.revision = S.v1 ? rev : null;
    S.examples = data.examples;
    for (const ex of S.examples) { S.byId.set(ex.id, ex); S.exampleTexts.add(ex.text); }
  } catch (e) {
    S.phase = 'error';
    showError({ kind: 'data', title: 'The gallery data is missing', detail: `${e.message}. Generate it with “node scripts/build-gallery.mjs” and reload.`, retry: false });
    renderStatus();
    return;
  }
  const pinCommit = S.pin.qed64 && S.pin.qed64.commit ? S.pin.qed64.commit : null;
  E.pinBadge.textContent = `QED64 ${S.pin.pin || (pinCommit ? pinCommit.slice(0, 7) : '?')}${S.pin.leanVersion ? ` · Lean ${S.pin.leanVersion}` : ''}`;
  E.pinBadge.title = `QED64 commit ${pinCommit ? pinCommit.slice(0, 12) : '?'}, runtime ${S.pin.buildId} (pinned in QED64.lock.json)${S.v1 ? `; page API ${S.api.revision} (embed mode)` : ''}`;
  E.overlayBadge.textContent = `snapshot ${S.requestedOverlay || 'auto'}`;
  renderRail();
  const h = L.parseHash(location.hash, S.examples.map((e) => e.id));
  const initial = h.id || S.examples[0].id;
  renderSaved();
  if (!S.caps.ok) { S.current = initial; markCurrent(initial); showUnsupported(); return; } // memory only: the card offers "Try anyway"
  choose(initial, { source: 'initial' });
  if (h.bad !== null) showNotice(`There is no example called “${h.bad}”; showing ${S.byId.get(initial).title} instead.`, { transient: true });
}
start();
