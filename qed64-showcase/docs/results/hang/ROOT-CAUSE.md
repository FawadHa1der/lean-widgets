# L7 root cause: why QED64 stays in `elaborating` forever (widget-lane analysis)

Written 2026-10-01 by the hang lane. QED64 is pinned at commit 1859b83, runtime `wasm64-4b025db7729c5f89` (Lean
4.34.0). Read-only trees were only read; nothing outside `out/hang/` and `scripts/headless/hang-*.mjs` was
written. Evidence files in this directory:

* `c20-hasse-timeline.tsv`: the C20 hasse-view session rebuilt from the trace and the console log.
* `progress-bar-frames.tsv`: the editor's fileProgress bar, read off the trace's screencast frames.
* `hang-repro.*.json`: the headless replay runs (see section 7).

## 1. Verdict

* **What L7 is.** Every Lean pthread in the worker stopped at the same moment, about 83.0 s into the session.
  The Emscripten main thread, the worker's own JS thread, kept running. It is not a slow elaboration and it is
  not a deadlock local to the inserted `example`. Nothing in the worker created or ended a pthread for 450 s,
  although new input kept arriving: the v61 edit and the InfoView's requests at 502.9 s. Nothing was written
  to stdout. The heartbeat, which comes from the JS thread, kept QED64 from noticing.
* **Where.** The freeze happened inside QED64's runtime, below the FileWorker's request and cancel logic. The
  most likely locus is the Lean task manager's single global mutex (`task_manager::m_mutex`). Lean holds that
  mutex while it calls `pthread_create`. Under Emscripten, `pthread_create` from a pthread is a *synchronous*
  round trip to the main JS thread (`pthreadCreateProxied` → `proxyToMainThread(2,0,1,…)`). If one such round
  trip never completes, the thread holding `m_mutex` waits forever. Every other Lean thread then blocks at its
  next task operation. That is exactly the observed state: the pool frozen at `8/17`, no frames, almost no CPU.
* **How likely, and why.** The language server creates a new pthread for every LSP message it writes
  (`chanOut.forAsync (prio := .dedicated)`), and for every request and request continuation (`ServerTask` is
  always `.dedicated`). The headless replay measured **153 pthread creations per C20 cycle** (42,016 in 271
  cycles), each one locked and proxied. The freeze happened during a burst of them.
* **The hang rate is low.** There was 1 hang in the 19 recorded C20 runs (`out/ux/*/tests/C20.json`: ~2,220
  link clicks, each with a reset, so ~4,400 edits). That is about 1 per ~340,000 creations, which fits a rare
  race or lost wakeup in this path, not a deterministic bug. The one headless replay that the host allowed (271
  cycles, 42,016 creations, section 7) did not hang, which is consistent with that rate.
* **Exactly which wakeup is lost is not proven** (confidence: *likely*, not *confirmed*). The capture holds no
  stack or worker stderr. Two candidates remain:
  * a lost main-thread mailbox notification;
  * a pthread start that never runs while its creator holds the mutex.
  The probes built into `scripts/headless/hang-repro.mjs` decide between them (sections 7 and 9).
* **Our widgets and bridge are not the cause** (section 6). The bridge's abortSignal strip creates no
  long-lived or blocked tasks. The HasseView panel RPC is a pure render that takes at most ~0.55 s. The
  inserted `by decide` example is ordinary: the identical text was clicked at link #5 of the same session and
  in every other run without trouble. The widget traffic only adds to the thread churn that every LSP message
  causes.

## 2. What `pool a/b` measures

* `qed64.status().pool` comes from `poolSample()` in `public/workers/lean.worker.js:289-299`. It is
  `{unused: PThread.unusedWorkers.length, running: Object.keys(PThread.pthreads).length}`.
* `emitStatus()` (`:305-312`) attaches a fresh sample to the worker's status on every frame through the front
  door, client and server alike (`frontDoorApply`, `:314-356`, called for page messages at `:1401`). It posts
  the status only when the JSON changed.
* Each status the page receives prints one `[qed64] <phase>` console line. The bundle's `Wh.busy/idle` logs
  it (`index-CzXuAkOQ.js` line 1323).
* In the glue (`lean.js`, 48,971,853 B, one line, served unchanged as trace resource `9d0d6204….js`):
  * `PThread.initMainThread` preallocates `pthreadPoolSize=24` Workers (offset 12424).
  * `spawnThread` (offset 10349) takes a Worker from `getNewWorker()` (offset 15144). That function allocates
    a new Worker when `unusedWorkers` is empty. It then records the thread in `PThread.pthreads`.
  * `cleanupThread` (offset 9392) returns the Worker to the pool. Workers are never terminated.
* So `unused + running` is the high-water mark of concurrently live pthreads. It goes past 24 only when more
  than 24 were alive at once.
* `running` counts every live pthread:
  * the FileWorker main loop on the application pthread (`lean.worker.js:131-135`, `callMain(["--worker"])`);
  * the std task-pool workers. These are created lazily up to `hardwareConcurrency` = 14, plus compensation
    workers, and they never exit (`object.cpp:831-871`);
  * every live dedicated task.
* The owner session's reading, fact (iii), is correct.

## 3. The exact sequence around the hang

Sources: `out/ux/auditor-full/test-results/20-click-all-C20-…/trace.zip`, entry `0-trace.trace`, with
Playwright's `evaluate` and `click` calls decoded; `tests/C20.c20-hasse-view.console.jsonl`; and the screencast
frames. Times are seconds since the session start (07:05:58.952 EDT). The full table is
`c20-hasse-timeline.tsv`.

Each C20 cycle runs these steps:

1. Reset: `setValue` sends a full-text didChange, version v.
2. The cursor is set to `[24,0]`.
3. The InfoView link is clicked. The bridge's `executeEdits` sends a didChange for v+1.
4. The test waits for `ready`.

The InfoView's requests for a hasse cursor were measured in the bring-up probe `out/ux/bringup/rt-hasse-d3.json`
(stock page plus bridge):

* `getWidgets`, `getInteractiveGoals`, `getInteractiveTermGoal`, `getInteractiveDiagnostics`;
* `getWidgetSource` ×2, but only the first time a hash is seen;
* `HasseView.HassePanel.rpc`, the slowest at **512 ms**;
* the editor's `textDocument/codeAction`;
* a `keepAlive` notification.

The editor adds its own document requests on each version. LSP request ids advance by ~32 per cycle in this
session (626, 659, …, 851).

| t (s) | what | evidence |
|---|---|---|
| 79.108 → 79.616 | Reset → **v57** ready; cursor 79.790 | qstatus `ready v57 pool 11/14` |
| 80.345 | click link #29 → **v58**; 80.374 reply id 819 `-32800` (message `''`) | timeline; console `errorReply` |
| 80.493 / 80.700 / 80.875 | progress bar lines 25–36 → lines 26, 33, 35–36 → none: the example's proof ran on, while later commands finished | `progress-bar-frames.tsv` |
| 80.844 | `ready v58 pool 10/15` | timeline |
| 81.461 → 81.971 | Reset → **v59** ready; cursor 82.135 (`[24,0]`); 82.672 `ready v59 pool 9/16` | timeline |
| **82.695** | click link #30 “{0} ⋖ {0, 2}” → **v60**; 82.724 reply id **851** `-32800` | timeline; console |
| 82.724–83.008 | 9 status events (pool changing: `10/15` → `7/18` → `8/17`) | console `[qed64] elaborating` ×9 |
| **82.849** | v60 fileProgress #1: bar on lines **25–36** (`#hasse … updown` and everything below) | frame `…-1790852841802.jpeg` |
| **≈83.00** | v60 fileProgress #2: bar on line **26** and lines **28–36**. The `#hasse` at line 25 (with its 14-`decide` link gate) has finished. The inserted example is processing, and nothing after it has finished. In the v58 cycle, lines 28–32 were done 0.35 s after the click | frame `…-1790852842003.jpeg` (83.05) |
| 83.008 | **last status event of the session's live phase** | console |
| 83.038 → 202.8 | qstatus every ~150 ms: `elaborating v60 pool 8/17` (total 25), `relay serving`, `lastDeath null`, `workerDeaths 0`: **identical in all 770 samples** | timeline; `0-trace.trace` |
| 100.0 | bar still lines 26, 28–36 | frame `…-1790852858952.jpeg` |
| 202.813 | Reset → **v61** (didChange). 202.893: one status event, the version change, sampled *before* the worker reads the ring: `elaborating v61 pool 8/17` | console, timeline |
| 203.0 | bar gone (the editor dropped the v60 decorations on the edit); no v61 fileProgress ever drew one | frame `…-1790852961952.jpeg` |
| 502.870 | cursor `[24,0]` again: the InfoView sends its requests for v61; until 530.8 it shows its *updating* (gold) summary on every poll (130 of 130) | `queryCount summary[class*=gold]` = 1 |
| 203.0 → 502.9 | qstatus: `elaborating v61 pool 8/17`, identical in all 1,848 samples | timeline |
| 530.99 → 623.157 | Playwright hit the test timeout at 530.99 (`After Hooks`). The test body still ran on and clicked link #32 at 623.10, which sent a didChange for **v62**. The status event at 623.157 is that version change. It is the *only* status event between 202.893 and 623.157, although the worker took the InfoView's v61 requests (502.9 s) and a keepAlive every 10 s as client frames, and each of those re-samples the pool | `test.trace` steps; console |

Facts that follow from the table:

* **The -32800 at the click is routine.** One request per cycle is in flight when the edit lands, and the client
  cancels it. Most likely it is the editor's re-request of `textDocument/inlayHint`. The server keeps sending
  `workspace/inlayHint/refresh` (659 times in the headless replay, §7), and the editor asks again each time.
  Lean answers a request that is not the first after an edit only after a 3 s "consistent latency" window
  (`FileWorker/InlayHints.lean:139-147`, `AsyncList.lean:85-135`). So one is always pending when the next
  edit comes 1.2 to 1.6 s later. Every other request in the cursor trace
  finishes in under 0.55 s (`rt-hasse-d3.json`). This is an inference, because the request method is not in
  the capture. This happens in every C20 run (`auditor-c20b`, `full6`, `full7`, `c20rep1`: 34–39 per hasse
  session, at the same spacing of ~32 ids), and none of those runs hung. The reply's empty message matches
  `RequestError.requestCancelled` (`Requests.lean:180-181`) emitted by `emitRequestResponse` (`FileWorker.lean:930-934`).
  This confirms the owner's fact (i).
* **The v60 reporter did run.** Two distinct v60 fileProgress notifications reached the editor, at 82.85 and
  83.0 s. The output path still worked at 83.0 s. So owner hypothesis (1), "the reporter task for v60 never
  runs", is ruled out.
* **Elaboration of v60 advanced:** `#hasse` at line 25 re-elaborated, including its link gate of 14
  `decide`s. Everything stopped as the example on line 26 began. In a healthy cycle (v58), its synchronous
  part finished within 0.35 s and the commands after it went on.

## 4. The freeze is runtime-wide, not local to one task

* **No pthread was created or ended for 450 s while input kept arriving.**
  * `emitStatus` samples the pool on every client frame (`lean.worker.js:355`, `:1401`).
  * After 83.0 s the client sent the v61 didChange and the InfoView's v61 requests at 502.9 s. Through 530.9 s
    the InfoView stayed *updating*, so its requests were pending. KeepAlives went out every 10 s
    (`index-CzXuAkOQ.js`: `setInterval(…"$/lean/rpc/keepAlive"…, 1e4)`).
  * The worker never reported a different pool. The qstatus samples run to 502.9 s; after that the console has
    no status event until the v62 edit at 623.157. Yet processing v61 would spawn a dedicated reporter
    (`FileWorker.lean:642-643` → `reportSnapshots` → `ServerTask.BaseIO.asTask`, which is `.dedicated`,
    `ServerTask.lean:80-81`). Each RPC request would spawn at least one dedicated task (`RequestM.asTask`;
    builtin RPCs block a dedicated thread in `t.wait`, `Rpc/RequestHandling.lean:42-51`). Each answer would
    spawn the output continuation (next bullet).
  * A main loop that read the ring would have changed `running`. A healthy runtime changes it on almost every
    frame: the C20 per-link pools vary between 11 and 22 `running` at `ready`.
* **No output at all.** Every LSP message the worker writes goes through `chanOut.forAsync (prio := .dedicated)`
  (`FileWorker.lean:571`). `Std.Channel.forAsync` is `BaseIO.bindTask (prio := prio) (← ch.recv) fun v => do f v;
  ch.forAsync f prio` (`Std/Sync/Channel.lean:906-908`), and a non-sync bind always allocates a task
  (`object.cpp:1273-1281`). So **each output message runs on a freshly created pthread**, and its write is a
  synchronous `fd_write` proxy to the main thread (`lean.js` offset 135856: `proxyToMainThread(42,0,1,…)`). No
  frame arrived after ≈83.0 s.
* **The JS side was alive.**
  * The worker's JS thread processed the v61 frame (status event at 202.893) and later frames. Its 2 s
    heartbeat (`lean.worker.js:336-338`) kept `LeanSession` from declaring a death (`src/runtime/client.ts:217-228`).
  * The auditor reported 7.3 % renderer CPU. This is a second-hand figure: UX-RESULTS.md:345, not a stored
    sample. Any looping pthread would show as ≥ 100 %.
* **It cannot be the stdin ring alone** (owner hypothesis 2). A lost ring wakeup would leave v61 unread. It
  cannot stop v60's own elaboration and output, which need no stdin. Yet v60 stopped at 83.0 s, 120 s before
  v61 existed.
* **It is not an accumulation of blocked dedicated threads** (owner hypothesis 3).
  * `running = 17` at the freeze. The floor of `running` (the minimum per 6 s window) rose 8 → 11 → 13 over the
    session, which is std-worker growth. So the freeze holds about 4 live non-floor threads. One is the v60
    reporter blocked in `IO.waitAny`, which is expected while elaborating.
  * The same workload in runs that did not hang shows far more: `full7` hasse links #44–#47 at
    `8/21`, `10/19`, `9/22`; c20rep1 #47 `6/22`; pool totals 28–33 (`out/ux/*/tests/C20.json` `results[].pool`,
    `poolTotals`).
  * 8 Workers were unused at the freeze, so the Emscripten pool was not exhausted.

What fits all of these at once is a single resource that every Lean thread needs and one stuck thread holds.
In this runtime that is the task manager's mutex.

## 5. Mechanism in the QED64 runtime

### 5.1 The task manager

The task manager is in `src/runtime/object.cpp` of `wasm64-lean-kernel`, unchanged from upstream in this
respect.

* `enqueue_core` (`:789-809`) runs with `m_mutex` held. It calls `spawn_dedicated_worker` (`:873-884`) for
  every `prio > LEAN_MAX_PRIO` task. It calls `spawn_worker` (`:831-871`) when no std worker is idle.
* Both call `lthread`, which calls `pthread_create` (`thread.cpp:135-147`) **while still holding `m_mutex`**.
* `enqueue_core` is reached from every path that holds the lock:
  * `enqueue` (`:990`), from every `Task.spawn`/`asTask`;
  * `add_dep` (`:1009`), from every `bindTask`/`mapTask`;
  * `resolve_core` → `handle_finished` (`:927-955`), from every task completion and `IO.Promise.resolve`.
    Here **one finishing task spawns threads for all of its dependents in a loop under the lock**.
  * `wait_for` (`:1025-1047`) spawns compensation workers under the lock.
* Every other entry point takes the same lock:
  * `get_task_state` (`:1085`), reached through `IO.hasFinished`. The FileWorker main loop calls it for every
    pending request on every message it reads (`FileWorker.lean:1000-1009`);
  * `wait_any` (`:1049`);
  * task exit in `run_task`;
  * `cancel`, `deactivate_task`.

### 5.2 Emscripten makes thread creation a synchronous main-thread round trip

From pinned glue `lean.js`:

* `___pthread_create_js`, called on a pthread with an empty transfer list, returns `pthreadCreateProxied(…)`
  (offset 91983). That is `proxyToMainThread(2,0,1,…)`, where proxy mode 1 means synchronous.
* The calling pthread blocks until the main JS thread services its mailbox and runs `spawnThread`.
* The main thread learns of the work through `checkMailbox` (offset 121496). Two paths trigger it:
  * an `Atomics.waitAsync` armed by `__emscripten_thread_mailbox_await` (offset 121130);
  * a `{cmd:4}` postMessage sent by `__emscripten_notify_mailbox_postmessage` (offset 121719).
* QED64's own patch notes already record that this proxying is fragile in this build:
  * PATCHES.md 0019: "synchronous `pthread_create` under Emscripten can only claim preallocated workers".
  * 0020: `checkMailbox` → `maybeExit` killed pthreads blocked in `emscripten_proxy_sync`; fixed by a
    keepalive.
  * 0018 and `FileWorker.lean:408-416`: "timed sleeps on task pthreads" block forever.
  * HARDENING #29: an elaboration pthread's proxied WORKERFS lookup "stalls — the pill reads `elaborating`
    forever".

### 5.3 How often the runtime takes this path

* Every request runs on at least one new dedicated pthread (`ServerTask.lean:20-31`). Every bind continuation
  of a request is another (`ServerTask.lean:64-131`). Every LSP output message is another (§4).
* Measured headlessly (section 7): one C20 cycle makes a median of **153** `pthread_create` calls, for 22
  requests and 110 server frames. The browser's cycle has ~32 requests (request ids advance ~32 per cycle), so
  it makes at least as many.
* The 18 other recorded C20 runs made ~2,190 link clicks (~4,400 edits, at roughly 1 to 2.5 s each)
  without a freeze. The one session that froze did so after 30 clicks (60 versions).
* The moment of the freeze (≈83.0 s) is the densest point of a cycle:
  * `#hasse` at line 25 had just finished.
  * That released every InfoView and editor request bound to its snapshot: getWidgets, goals, term goal,
    diagnostics, the panel RPC, codeAction and documentHighlight. Their `.dedicated` continuations are spawned
    one after another inside `handle_finished`, under the lock.
  * The reporter's progress messages, each a new output thread, went out at the same time.
  * The inserted example's elaboration tasks were starting.

### 5.4 The two failure points that remain

The "single thread stuck while holding `m_mutex`" picture admits two causes:

* **(A) A lost main-thread mailbox wakeup.** A sync proxy (`pthread_create`, or an `fd_write` of a thread that
  also holds the lock) is enqueued, but `checkMailbox` is never triggered. Any later proxied call would rescue
  it, but once every Lean thread is blocked on `m_mutex`, nobody proxies again. The JS thread stays idle and
  healthy.
* **(B) The new pthread never starts.** The proxied create completes. The creator then waits on something the
  new thread must do. The task manager has no such wait, so B needs an Emscripten-internal handshake. It is
  less likely.

Without a stack or a probe, A and B cannot be told apart. Section 7's `checkMailbox()` probe tests A directly.

### 5.5 Why v61 also hung

Under the global freeze this is automatic: the main loop blocks on `m_mutex` while processing the v61 change.

Even without a global freeze, the reset would have blocked. For the `abbrev Bowtie` command that now sits
where v60's example was, `elabMutualDef` does a "blocking wait" on the *old* command's
`DefsParsedSnapshot` (`MutualDef.lean:1545-1547`, `old.val.get`). That snapshot never resolves if the old
`example` never got going.

## 6. The widget-specific questions

### (a) Does our bridge's abortSignal strip, or do the panel RPCs, create blocked dedicated tasks?

No, for four reasons.

1. **Which requests the strip affects.** It applies only to ProofWidgets `OfRpcMethod` panels. Stats show
   `stripped 1` per panel render in `rt-hasse*.json` and `stripped 3` for the 8-widget walk in UX-RESULTS. The
   InfoView's own RPCs carry no abortSignal.
2. **Cancelling the panel RPC would change nothing on the server.**
   * Every widget panel here is a plain `mk_rpc_widget%`: `ChainPanel.rpc`, `DistPanel.rpc`,
     `GraphScopePanel.rpc`, `HassePanel.rpc`, `IntervalInspectorPanel.rpc`, `XRayPanel.rpc`. None uses the
     cancellable protocol (no `ProofWidgets.checkRequest` polling).
   * `HassePanel.rpc` (`widgets-src/hasse-view/HasseView/Widget.lean`) is
     `RequestM.asTask do let doc ← RequestM.readDoc; return renderPanelWith …`. That is a pure render of
     props the command stored, with no `checkCancelled`, no `evalExpr`, no `decide` and no IO.
   * On a cancelled request, Lean only swaps the answer for `-32800` *after* the handler finishes
     (`FileWorker.lean:926-934`).
   * So the strip costs at most one discarded response per superseded panel render. Without it, the panel
     never renders at all (D1).
3. **How long panel RPCs live.**
   * In the browser, `HassePanel.rpc` takes 512 ms (`rt-hasse.json` and `rt-hasse-d3.json`, "slowest"). It
     runs in the IR interpreter; the widget modules are legacy, with their IR in the `.olean`.
   * Headless E3 measured `rpcMs` max 552 ms for hasse, 340 interval-inspector, 309 graph-scope, 150
     expr-xray, 114 dist-lens (`out/headless/*.widgets8.rpc.json`).
   * With one call per cursor or version, at most one or two are alive at any moment. At the freeze, 17
     `running` is ordinary for this workload (§4).
4. **The getWidgetSource storm (L2) is coalesced by D3.** At the hasse cursor this means 2 forwarded instead of
   15 (`rt-hasse.json` 15 calls vs `rt-hasse-d3.json` 2), and the total stayed 24 for the first 42 versions.

### (b) Can the hasse-view panel RPC or the inserted `by decide` example block a dedicated thread?

* **The panel RPC: no.** See (a). It is a pure render on its own dedicated thread, finished in ≤ 0.55 s.
* **The example: not by itself.**
  * It is elaborated by the command elaborator on the std pool, not on a dedicated thread.
  * Native re-elaboration takes 530 ms (`out/click-all/w8/hasse-view.json` link 30). In the browser it is
    ~0.5–0.65 s (`auditor-ux-full.log` links #26–#29).
  * The *identical* text `example : ({0} : (Finset (Fin 3))) ⋖ {0, 2} := by decide` was link #5 of the
    same session (line 18 position), at 964 ms. It is links #5 and #30 in ~20 other C20 runs, all clean.
  * At the freeze it had not even finished its synchronous part. Section 3 shows lines 28–36 still pending,
    where the healthy cycle had them done at +0.35 s. It froze with everything else rather than causing the
    freeze.

### (c) Is there a deterministic widget-specific repro?

No widget-specific trigger exists in the evidence. The same link and the same sequence pass in every other
run. Section 7 has the headless replay and the stress variants that were tried.

## 7. Dynamic: headless replay (`scripts/headless/hang-repro.mjs`)

**Run `replay`.**

* Started 2026-10-01 10:49:21 EDT, with the browser lock absent, 20.4 GB free+inactive and no
  chrome-headless-shell running.
* Command: `node --stack-size=8192 scripts/headless/hang-repro.mjs --label replay --minutes 11`.
* Inputs:
  * snapshots `$W/raw/init.snap` + `$W/raw/widgets8.snap`, both paired with the bake-out-w8 index before
    boot;
  * lib `$W/tree-slim-w8`;
  * the pinned stage1 runtime `wasm64-4b025db7729c5f89`.
* It boots like `rpc-probe.mjs` and then replays the C20 hasse-view cycle over all 47 links in order.
* The tool wraps the glue's own `spawnThread`/`cleanupThread` globals, so the thread counts are exact.
* Output: `hang-repro.replay.json`, with per-cycle rows and a summary, and `hang-repro.replay.log`.

Results:

| measure | value |
|---|---|
| duration | 345 s; boot 4.5 s. The run stopped itself, as designed, when another lane took the browser lock (`auditor5-mut1`, 14:55:11Z) |
| cycles / versions | **271** cycles (each link ~5.8 times) / 543 versions; every settle succeeded |
| pthreads created / exited | **42,016** / 42,001: **153 per cycle** (median), for 22 client requests and 110 server frames per cycle |
| pool | `running` 10–26 at cycle ends, max 33; 9 creations found the pool empty, so the total grew 24 → 33, the L2-style growth *without* any widget storm |
| requests | 12 kinds × 542 (getWidgetSource 2, cached); **0 errors, 0 left in flight**; `HassePanel.rpc` mean 197 ms, max 486 ms |
| server frames | fileProgress 18,900; publishDiagnostics 814; ileanInfoUpdate 3,734; responses 5,965; **`workspace/inlayHint/refresh` 659** |
| hang | **none** (`HANG-REPRO NO-HANG replay 271 cycles (aborted: browser lock appeared)`) |
| peak RSS | 12.0 GB |

What this adds:

1. **Thread churn is measured, no longer estimated.** One C20 cycle costs ~153 `pthread_create` calls. Each is a
   synchronous main-thread proxy made under `task_manager::m_mutex` (§5). The browser's record of 1 freeze in
   ~2,220 C20 clicks is therefore about **1 freeze per ~340,000 locked, proxied thread creations**.
2. **Why the run says nothing either way.** It made 42,016 creations. At the browser rate it would expect ~0.12
   freezes, so "no hang" neither confirms nor refutes the race. Node's `worker_threads` and event loop also
   differ from Chrome's nested Workers and `Atomics.waitAsync`.
   * The mechanism itself is reproduced: every request and frame spawns a pthread.
   * Concurrency bursts alone push the pool past 24.
3. **Timed sleeps on dedicated pthreads do wake in this runtime (under Node).** The server sent 659
   `workspace/inlayHint/refresh` requests, and those come only after the refresh loop's `IO.sleep` naps
   (`FileWorker.lean:1037-1107`).
   * So the "timed sleeps never wake" note (PATCHES 0018, `FileWorker.lean:413`) does not apply to this
     build in Node.
   * Our single inlay-hint request per version is answered at once (the first request after an edit). The
     browser's editor re-requests on every refresh, and that re-request waits out the 3 s latency window.
   * That makes it the probable owner of the routine per-edit `-32800` (§3).
4. **The stress variants were not run:**
   * `--cancel`: cancel everything in flight at each click;
   * `--storm 14`: the L2 `getWidgetSource` storm, without D3, on every version;
   * `--panel-storm 4`: uncancelled panel RPCs piling up.
   No second window opened. Other lanes re-took the browser lock about every 9 minutes. At 11:05 and 11:14 the
   host had 14 and 9 GB free+inactive, with 15 and 10 chrome-headless-shell processes from other sessions.
   They are ready to run:
   ```
   node --stack-size=8192 scripts/headless/hang-repro.mjs --label stress --cancel --storm 14 --panel-storm 4 --minutes 12
   ```
   Hitting the browser rate needs on the order of 10 such 12-minute runs. If one hangs, the JSON's `hang`
   block records the pool, the in-flight requests, the last 40 frames, and the results of the ring-kick and
   `checkMailbox()` probes (§9).


## 8. Fixes

### In our repo (qed64-showcase)

1. **Keep the stall watchdog, and give it a liveness probe so it can restart on its own.**
   * Today `gallery.js` `watchStall` (`:393-419`) counts only fileProgress and publishDiagnostics, then waits
     45 s for a user click.
   * A frozen runtime answers *no* request. A healthy one answers a cheap request that needs only the header
     snapshot within ~100 ms, even in the middle of a long elaboration, because requests run on their own
     dedicated threads.
   * Proposal:
     * Trigger: the phase is `elaborating` with no progress for 10 s.
     * Probe: send `textDocument/hover` at 0:0 through `relay.fromClient`, with a private id.
     * Read the reply in the existing `relay.toClient` tap, and swallow it there so the editor never sees an
       unknown id.
     * No reply in 5 s means frozen: run `restartLean('auto')` at once, with the same text.
     * Keep the card for the case where a restart fails.
   * A frozen `pool` alone is not a safe signal. A legitimately long single command with no client activity
     can also leave the pool unchanged.
   * This turns L7 from 45 s plus a user click into about 15 s.
2. **Do not invest in "real" cancellation in the bridge for L7's sake.** Replacing the strip with a
   `$/cancelRequest` sent when the InfoView's AbortSignal fires is feasible. It needs a hook inside the
   InfoView frame to observe `abort`, plus a seqNum → LSP-id map from the relay tap. But Lean's pure panel
   handlers do not poll cancellation, so the server would do the same work. It would save one output frame
   (one thread) per superseded render. It is a hygiene item at most, not an L7 fix.
3. **Optional churn reduction (unproven benefit).**
   * The bridge could cap concurrent `$/lean/rpc/call` at, for example, 4, queueing the rest. Fewer requests
     released at once means fewer locked thread creations in one `handle_finished` burst.
   * Measure the hang rate first (section 7 tool, `--panel-storm`/`--storm`) before shipping it. It slows
     panels.
4. **Docs.** Correct the L7 text in `gallery/README.md` and `docs/UX-RESULTS.md` to "runtime-wide freeze of
   all Lean pthreads (pool frozen, no frames, JS thread alive)", with this file as the reference. Not done
   here: those files are outside this lane's write scope.

### For QED64 (the owner)

1. **Detect it.** The heartbeat must come from Lean, not the JS thread.
   * For example, when `phase=elaborating` and no server frame has arrived for N s, the worker sends itself a
     cheap request through the ring (`$/lean/rpc/connect`, or `textDocument/hover` at 0:0) and requires an
     answer within M s.
   * Or treat "pool sample unchanged across K client frames while elaborating" as a death. Then `died` →
     reboot, as for any crash.
2. **Self-heal probe for cause A (cheap, worth trying first).**
   * Add `setInterval(() => { try { self.checkMailbox && self.checkMailbox(); } catch {} }, 1000)` in
     `lean.worker.js`. The glue is a classic `importScripts` script, so `checkMailbox` is a worker global, the
     same way `PThread` is used by `poolSample`.
   * If L7 is a lost main-thread mailbox notification, this makes it a ≤ 1 s hiccup.
   * When a stall is detected, call it once and log whether frames resume. That single bit tells A from B in
     the field.
3. **Remove the amplifier (kernel).** Do not call `pthread_create` while holding `task_manager::m_mutex`:
   * In `enqueue_core`/`handle_finished`/`wait_for`, collect the tasks that need a new thread, unlock, create
     the threads, then relock. The dedicated thread already re-takes the lock before `run_task`.
   * Or, on Emscripten, run `.dedicated` tasks on a growable pool of long-lived threads instead of one fresh
     pthread each.
   * Either removes the global-lock-across-main-thread-round-trip pattern. With it, any proxy delay or loss
     freezes the whole runtime.
4. **Cut the churn (kernel or stdlib, upstreamable).**
   * The FileWorker's output loop `chanOut.forAsync (prio := .dedicated)` creates one pthread per LSP message.
     A single long-lived output thread (`while true: let m ← chanOut.sync.recv; write m`) would do the same
     job with zero thread creations per message.
   * This alone removes the majority of runtime `pthread_create` calls in a busy session.

## 9. What would settle the remaining question

* Run `hang-repro.mjs` until it hangs. Its two probes then decide:
  * frames resume after the ring kick: a lost stdin wakeup;
  * frames resume after `checkMailbox()`: cause A;
  * frames resume after neither: a true lock cycle or a pthread that never started (B).
* Or, in the browser, add the `checkMailbox()` stall probe of §8 QED64-2 to the gallery's watchdog. The gallery
  can reach `iframe.contentWindow`, but not the worker's globals, so this belongs in QED64.
* The QED64 owner's Node storm repro can report the same bit if it adds the probe.

## Verification

Adversarial re-check by a second hang-lane agent, 2026-10-01 11:16–(see the end) EDT. Same rules: read-only
trees only read, no browser launched, only this file appended (plus scratch extracts outside the repo). Every
item below was re-extracted from the cited source, not copied from the sections above.

### V1. Verdict

* **The observation is confirmed:** after ≈83.01 s no Lean pthread was created and none exited, while the
  worker's JS thread kept handling page messages. The v60 output stopped mid-file, the v61 edit and the
  InfoView's v61 requests got nothing, and there was no death, no exception and no host sleep (V2, V3).
* **The location is likely, as stated:** inside QED64's runtime, below the FileWorker. No evidence points at
  our widgets or bridge (V5).
* **The trigger is still a hypothesis, not "likely":** "a synchronous proxy to the Emscripten main thread
  never completed, and `task_manager::m_mutex` spread it to every thread". The code path is real and
  verified (V2 items 7–9), but nothing in the capture separates it from a lock cycle among pthreads alone
  (V4). Node evidence also cuts against the per-creation-race reading: about 610,000 thread creations
  without a freeze (V6).
* **Two fix proposals need correction** (V7). The periodic `checkMailbox` kick, as written, leaks
  `Atomics.waitAsync` waiters. The kernel "unlock around `pthread_create`" change would not on its own stop
  L7 from looking the same to the user. The ranking changes accordingly.

### V2. Evidence items re-checked

| # | Claim (sections above) | Re-check | Result |
|---|---|---|---|
| 1 | No `[qed64]` status event between 83.008 and 202.893, then only 623.157 | `tests/C20.c20-hasse-view.console.jsonl`, wall0 1790852758952: events at 82.724–83.008 (9), 202.893, 623.157, nothing else after 83.008 | **confirmed** |
| 2 | `pool 8/17` identical in 770 + 1,848 qstatus samples | Re-decoded `0-trace.trace` (`q.status()` evaluations): **772** samples in 83.03–202.85 and **1,846** in 202.95–502.95, all `{elaborating, v60/v61, unused 8, running 17, serving, lastDeath null, workerDeaths 0}` | **confirmed, but the samples are not independent.** `qed64.status().pool` is the last status the worker *posted*. `emitStatus` posts only when the JSON changes (`lean.worker.js:305-312`), so 2,618 samples are one observation. The independent evidence is that `emitStatus` runs at the end of **every** `frontDoorApply` (`:314-356`, called for every page `lsp` message at `:1401`). Frames that did pass through it with no change: the v61 didChange (202.81, its own version-change event at 202.893), the InfoView's requests at 502.87 (cursor set; the gold *updating* summary in 130/130 polls, re-counted, plus `Error updating` 0/130), and, by inference only, keepAlives every 10 s (`dist/assets/index-CzXuAkOQ.js`: `const CRi=1e4 … setInterval(… "$/lean/rpc/keepAlive" …)`). The UX tap counts client methods (`__uxTap.calls`), but no evaluation in this trace ever read them, so the keepAlive frames themselves are not in the capture |
| 3 | Two v60 fileProgress updates; the reporter ran | Extracted frames `…-1790852841802/1841952/1842003/1858952.jpeg` and `…1839652.jpeg`, cropped the gutter. 82.849: bar on lines 25–36. **83.000: still 25–36.** 83.051: line 26 plus 28–36 (line 27 blank, not in any range). 100.0: identical. v58 at 80.700: lines 26, 33, 35–36 | **confirmed.** The second update arrived between 83.000 and 83.051, matching the two status events at 83.008. Note: `progress-bar-frames.tsv` writes that row as "lines 26-36 (104 px)" and hides the line-27 gap; the prose in §3 is right. Overreach in §1/§3: "everything stopped as the example started" is not observable. Only the **output** stopped at 83.008. After that, elaboration progress cannot be seen, because std workers never exit and can elaborate without creating threads (`object.cpp:831-871`) |
| 4 | -32800 is routine | This session: 20 replies (ids 2 … 851; regular every ~32 ids from 626), all with message `''`. Others: auditor-c20b 39, full6 37, full7 35, c20rep1 38, c20rep3 34 (median id gap 30.5–32) | **confirmed** |
| 5 | Running 17 is ordinary | `full7` C20 hasse #44 8/21, #45 8/21, #46 10/19, #47 9/22; `c20rep1` #47 6/22. At link #30 itself those runs had 11/16 and 9/16 | **confirmed** |
| 6 | Pool definition, glue offsets | Served glue (trace resource `9d0d6204….js`, 48,971,853 B): `pthreadCreateProxied` @91983 (`proxyToMainThread(2,0,1,…)`), `_fd_write` @135856 (`proxyToMainThread(42,0,1,…)`), `pthreadPoolSize=24` @12428, `getNewWorker` @15144, `cleanupThread` @9396 | **confirmed.** Addition: a pthread's exit cleanup is a plain `postMessage({cmd:6})` (`__emscripten_thread_cleanup` @123223), **not** a mailbox proxy. Exits would therefore show in `running` even with a dead mailbox. A frozen `running` means no thread got through its exit path. That fits every thread blocking on `m_mutex`: `run_task` re-locks after the closure, `object.cpp:898-904`. A dead mailbox alone does not explain it |
| 7 | `pthread_create` under `m_mutex` | `object.cpp` `enqueue_core` :789, `spawn_worker` :831, `spawn_dedicated_worker` :873, `run_task` :885 (unlocks around the closure, re-locks, then `resolve_core`), `resolve_core` :927, `handle_finished` :938, `wait_for` :1025; `thread.cpp:142` `pthread_create`, :150 `pthread_detach` (also under the lock) | **confirmed** |
| 8 | Every output message on a fresh pthread | `FileWorker.lean:571` `chanOut.forAsync (prio := .dedicated)`, `Std/Sync/Channel.lean:906-908`, `object.cpp:1273-1281` | **confirmed.** Correction: "every request continuation" runs on a new pthread is overstated. Cheap continuations run synchronously on the finishing thread, for example the response emission, `ServerTask.IO.mapTaskCheap`, `FileWorker.lean:928` |
| 9 | Headless replay numbers | `hang-repro.replay.json` summary: 271 cycles, 42,016 / 42,001, median 153, `maxRssGB 12.04`, `HassePanel.rpc` max 486 ms | **confirmed.** Limitation not stated above: `latency.*.cancelled` is **0 for all 12 methods**. The browser's per-click cancel path (the routine -32800) was never exercised |
| 10 | Panels are pure, non-cancellable | `widgets-v4.34/hasse-view/HasseView/Widget.lean:94-99` (`RequestM.asTask do let doc ← RequestM.readDoc; return renderPanelWith …`). `mk_rpc_widget%` in 5 files / 6 panels: XRayPanel, IntervalInspectorPanel, DistPanel, ChainPanel, GraphScopePanel, HassePanel | **confirmed** |
| 11 | Inserted text = link #5 | `out/click-all/w8/hasse-view.json` n=5 and n=30: same `newText`, inserted after line 18 vs line 25. `auditor-ux-full.log` "#5 ok … 964 ms" | **confirmed** |
| 12 | QED64 precedents | `PATCHES.md:28` (0019), `:29` (0020), `HARDENING.md:189` (#29) | **confirmed.** Note: #29's trigger (an on-thread WORKERFS import) was removed by patch 0032, so it is a precedent for the *symptom* of a stuck proxy, not for this trigger |
| 13 | 7.3 % CPU | Second-hand, now at `docs/UX-RESULTS.md:375` (§4 says :345). Not in any stored file | **unverifiable**, as the investigator already says |
| 14 | Not host sleep | The trace's screencast frames and calls have **no gap > 1 s** over the whole session (56,127 events; frames every ~8 ms right through the hang). `pmset -g log` has no Sleep/Wake/DarkWake line in 07:05–07:17 | **confirmed** |

### V3. Do the observed details follow from the mechanism?

* **No death:** yes. The heartbeat is a `setInterval` on the worker's JS thread (`lean.worker.js:336-338`).
* **About 7 % CPU:** yes, as far as it goes. Every Lean thread is blocked in a futex wait, and the renderer's
  cost is the page repainting about every 8 ms (frames continue in the trace).
* **Pool `8/17`, 8 unused:** consistent and unremarkable (V2 item 5).
* **Pool total 24 → 25 at v43:** neutral. Std-worker compensation in `wait_for` (`object.cpp:1031-1037`,
  `m_max_std_workers++` then `spawn_worker()`) explains why the total grows past 24 and why the
  `running` floor rises. Those workers never exit. Nothing links that growth to a freeze 17 versions later;
  non-hanging runs reach totals of 28–33.
* **v61 also stuck:** yes.
* **Intermittency:** 1 hang in the 20 recorded C20 runs, about 2,360 clicks. The auditor's "1 of 3" counted
  only `auditor-full`, `auditor-c20b` and `auditor-mutCD`. The other failures (`dev5`, `dev9`,
  `auditor-mutCD`, and the partial `dev7`, `dev8` and `c20rep4`) are harness failures (click or mutant), not
  stalls. One rare, random event fits this record. It does not single out hasse link #30.

### V4. Alternative explanations tested against the same evidence

| Alternative | Verdict | Why |
|---|---|---|
| A JS exception thrown inside a proxied call on the worker's JS thread | **ruled out** | The stdout tap runs QED64's front door *inside* the proxied `fd_write` (`put_char` → `LspFrameDecoder` → `frontDoorApply`, `lean.worker.js:96-126`). A throw there would leave the proxy uncompleted and could wedge the main-thread mailbox, which would be a QED64-specific trigger. But the glue's `quit_` rethrows (offset 628, `(status,toThrow)=>{throw toThrow}`). An uncaught worker error reaches `onWorkerError` (`src/runtime/client.ts:193-202`, `died(…,"crash")`), and an unhandled rejection in LSP mode calls `die(…,"unhandled")` (`lean.worker.js:467-486`). Observed: `lastDeath null`, `workerDeaths 0` |
| Stdout frame decoder wedged (HARDENING #27 class: Lean alive, frames dropped as junk) | **ruled out** | A live Lean would have changed the pool while processing v61 and the 502.87 requests, and those frames were sampled. No status event appeared |
| Stdin-ring lost wakeup alone (owner H2) | **ruled out** for v60 | Agrees with §4: v60's own output stopped at 83.008, mid-file, with no stdin involved |
| Lean deadlock local to v60, plus the main loop blocking on it at v61 | **reduces to the same thing** | The v61 path does not wait on old tasks: `handleOnDidChange` holds `lastTaskMutex` only around `mapTaskCostly` (`Requests.lean:676-682`), and `Language.Lean` uses `get?` (`Lean.lean:518-521`). But `doc.update` takes `diagnosticsMutex` (`FileWorker/Utils.lean:115`), and `publishDiagnostics` holds that mutex across the `chanOut` send (`Utils.lean:131-163`). That send can resolve the output loop's `recv` promise, which leads to `handle_finished` and then `pthread_create` under `m_mutex`. Every blocking path found ends in "a thread stuck in a task-manager operation while holding locks" |
| (B) a new pthread that never starts | **ruled out as the sole cause** (stronger than "less likely") | Emscripten's create returns as soon as `spawnThread` has posted `cmd:2` (offset 10353). Nothing in the task manager waits for a thread to start. B gives a partial stall (one chain dead), not a pool frozen across v61 |
| Blocked dedicated threads accumulating (owner H3) | **not supported** | The inlay-hint latency path creates up to two dedicated `IO.sleep` threads per delayed request and never cancels them (`AsyncList.lean:85-139`). If timed sleeps never woke in Chrome, `running` would climb by 1–2 per cycle; the floor rose only 8 → 13 over 30 cycles. So browser sleeps wake, and nothing accumulates |
| A lock cycle among pthreads only (no proxy involved) | **cannot be excluded** | The capture holds no stacks. This and the investigator's (A), a lost main-thread mailbox wakeup, both produce exactly the observed state |

### V5. Widget-specific questions (a)–(c)

* **(a) Bridge abortSignal strip and panel RPCs.**
  * Confirmed structurally: `gallery/qed64-bridge.js:117-124,141-143` only deletes `abortSignal` and
    re-dispatches. The worker therefore receives no `$/cancelRequest` for panel RPCs; it does not receive
    extra work.
  * Panel RPCs are pure and short (V2 item 10).
  * **Outstanding panel RPCs cannot be counted from this capture.** The tap never recorded methods, and
    `__showcase.status().bridge` carries only `{installed, installs, late}`. The bound "1–2 alive at a
    time" is structural (one call per cursor or version, ≤ 0.55 s), not measured.
  * The `running` trajectory (V3) shows no accumulation.
* **(b) Can the panel RPC or the inserted `by decide` block a dedicated thread?** No evidence for it.
  * The panel RPC is pure.
  * The example is elaborated on std workers, not dedicated threads.
  * The identical text passed at link #5 of the same session and in every other run.
* **(c) Deterministic widget repro.** None exists. The share of thread creations caused by widgets is small:
  per cycle, 1 panel RPC (plus 2 `getWidgetSource` the first time) out of ~22–32 requests.

### V6. Dynamic evidence

* **Our replay was not re-run as a repro check:** no repro was claimed, so there was nothing to reproduce.
  For the host window used for a stress variant, see V8.
* **The QED64 owner's own Node storm adds data.** It is
  `pipeline/snapshot/thread-storm-probe.mjs --minutes 30 --burst 2 --seed 7`, running while this check ran;
  its log is `qed64/work/storm/run1-burst2.log`, read only. It covers didChange plus request bursts plus a
  `$/cancelRequest` for everything in flight. By +1,295 s it had made **569,461 pthread creations over 3,750
  cycles with no freeze**, with pool totals up to ~127.
* **Combined Node total: about 610,000 creations, 0 freezes.**
  * If the browser hazard really were about 1 per 340,000 creations and Node shared it, about 1.8 freezes
    would be expected. Seeing none has a probability of about e^-1.8 ≈ 0.17.
  * Not decisive. It does weaken "a rare race per locked thread creation, independent of host". It favours
    a trigger that is specific to the browser (Chrome's nested pthread Workers, `Atomics.waitAsync` on the
    worker's JS thread, or the JS front door running inside every proxied `fd_write`) or to the workload.
* **Consequence:** more Node runs may never reproduce L7. The deciding experiment probably has to run in the
  browser with an in-worker probe (V9).

### V7. Corrections to the fix proposals

* **The `setInterval(() => checkMailbox(), 1000)` kick (QED64 fix 2) is unsafe as written.**
  * In this glue, `checkMailbox` (offset 121453) calls `__emscripten_thread_mailbox_await` (offset 121139)
    on every call. That arms a **new** `Atomics.waitAsync` waiter each time and never cancels the previous
    one.
  * A 1 s interval therefore adds one pending waiter per second for as long as the worker lives.
  * In upstream Emscripten, the C notifier wakes every waiter on that address. If this build does the same,
    every mailbox notification then fires one `checkMailbox` per accumulated waiter, and each re-arms. That
    last step is from upstream source and was not verified in this binary.
  * Safer options: call the raw export `__emscripten_check_mailbox()` (glue:
    `__emscripten_check_mailbox=wasmExports["_emscripten_check_mailbox"]`), which processes the mailbox
    without re-arming, on a timer. Or call `checkMailbox()` **once** when a stall is detected, which is all
    the A-versus-not-A diagnosis needs.
* **The kernel change "never `pthread_create` under `m_mutex`" (QED64 fix 3) does not cure the user-visible
  L7 by itself.**
  * If the main-thread mailbox stops being serviced, every `fd_write` is still a synchronous proxy (offset
    135856). Output would still stop forever and the pill would still read `elaborating`.
  * The change only shrinks the blast radius: elaboration and threads would keep moving. Under a pure lock
    cycle it may not help at all.
  * Keep it as hygiene, ranked below detection and the mailbox probe.
* **The gallery liveness probe (our fix 1) is right, with three guards.**
  * Use a string id that cannot collide with the client's numeric ids, and swallow its reply in the
    existing `relay.toClient` tap.
  * Require two consecutive missed probes before acting.
  * Rate-limit automatic restarts (for example at most one per 2 minutes, then fall back to the card), so
    a long legitimate header step can never cause a restart loop.
  * Why the probe works: a hover answer needs a dedicated thread and a proxied `fd_write`, which is exactly
    the path that dies. KeepAlive cannot serve as the probe: it is handled on the main loop without
    spawning a thread or producing output.

### V8. Ranked fix list (by expected effect on L7 as users see it)

1. **Ours:** the gallery liveness probe plus automatic `restartLean('auto')`, with the V7 guards. This bounds
   every variant of L7 (any trigger) to about 15–20 s.
2. **QED64:** Lean-level liveness in the relay or worker (a cheap request through the ring while
   `elaborating` and silent), treated as a death. This is the same bound for every QED64 user, without our
   gallery.
3. **QED64:** on a detected stall, call `__emscripten_check_mailbox()` once (not `checkMailbox` on an
   interval) and log whether frames resume. That decides A and may self-heal it; if A is confirmed, add a
   low-rate raw-export kick.
4. **Kernel (upstreamable):** one long-lived output thread instead of `forAsync (prio := .dedicated)`. This
   cuts about 70 % of thread creations (110 of 153 per cycle) and takes `fd_write` off short-lived threads.
   It helps only if the hazard scales with creations, which V6 makes less certain.
5. **Kernel:** no `pthread_create` under `m_mutex`, or a growable pool for `.dedicated` work on Emscripten.
   This reduces the blast radius (V7).
6. **Ours, optional:** cap concurrent `$/lean/rpc/call`. Widgets account for about 1–3 of 22–32 requests per
   cycle, so the expected effect is small.
7. **Docs:** correct L7 in `gallery/README.md` and `docs/UX-RESULTS.md` (runtime-wide freeze, cancels
   routine, reporter ran). Also correct the "1 of 3" to the current 1-in-20-runs record.
8. **Keep the D1 strip; do not build real cancellation for L7.** This is unchanged and correct.

### V9. What would settle it

* The trigger needs a hang caught **in the browser**, with a probe inside the worker. Without changing QED64
  in git, the only route is a test-only harness: an init script in the QED64 frame that wraps `Worker` so
  `lean.worker.js` runs under a shim. On a stall, the shim calls `__emscripten_check_mailbox()`, then
  `checkMailbox()`, and reports whether server frames resume.
  * Caveat: the worker loads its siblings with relative `importScripts`, so a blob shim needs absolute
    URLs.
  * Caveat: this is diagnostic only, and it must not ship.
* At the browser rate this needs on the order of 20 C20-length runs.

## Verification, second pass

A second adversarial pass, 2026-10-01 11:53–12:15 EDT. It checks both the investigation (§1–§9) and the first
pass above, whose end time was never filled in. Rules were the same as before. Read-only trees were only read,
with git always run as `--no-optional-locks`. The Emscripten 6.0.5 sources were copied out of the local
`emscripten/emsdk:6.0.5-arm64` image with `docker create` + `docker cp`; no container ran. The copies are in the
scratchpad, outside the repo. No browser was launched and no wasm process was started. Only this section was
added.

### W1. Verdict

* **The observation is confirmed a third time** (W2). Output stopped at 83.008 s. The v61 didChange reached the
  stdin ring, and `pool` read `8/17` both before and after it. There was no stderr, no death and no exception.
* **The mechanism is back to *likely*, but the trigger is still unknown.** The QED64 owner's Node fault-injection
  run E1 shows the mechanism is enough to produce L7 on this runtime. It is in
  `qed64/work/storm/e1-waitasync-drop.{log,json}` (11:53, read only).
  * Dropping **one** wake of the main-thread mailbox reproduced the exact L7 signature: pool frozen at `12/12`
    for 180 s, 0 frames, and `processing` stuck at 5.
  * A ring kick brought back 0 frames, and so did the raw `__emscripten_check_mailbox()`.
  * The glue's `checkMailbox()` brought frames back at once: "FRAMES RESUMED after probe 'js-checkMailbox'".
  * So "the Emscripten main thread stops servicing proxied calls, and `pthread_create` under
    `task_manager::m_mutex` freezes everything" fits every detail of the browser capture.
  * What actually lost the wake in Chrome is still not observed (W4).
* **Two statements are wrong and are corrected below:**
  * §5.4(A), "any later proxied call would rescue it". This is false for a lost wake (W3).
  * First-pass V7, "use the raw `__emscripten_check_mailbox()` on a timer". E1 refutes it (W4).
* **Our widgets and bridge are not the cause.** This is unchanged. The panel RPCs are 1–3 of the 22–32 requests
  per cycle, so at most a proportional share of the proxied calls.

### W2. Evidence re-checked (new items only)

| # | Item | Re-check | Result |
|---|---|---|---|
| 1 | No Lean-level fatal path | `[lean:stderr]` lines do reach this console: 11 rows at 1.95–4.45 s (`[boot] runtime keepalive pushed`, `[WASM LSP] header covered …`) and **none afterwards**. Every exit path of the pinned FileWorker prints first: `workerMain` does `e.putStrLn err.toString` then `IO.Process.forceExit 1`, and the main-loop catch publishes an error diagnostic through `writeErrorDiag` (`git show 9fbb45afcb:src/Lean/Server/FileWorker.lean`, :1130-1158) | **A FileWorker error or exit, a `panic!` or an internal panic is ruled out** (each one prints while the mailbox works) |
| 2 | Onset matches a healthy cycle | Console rows from 79 s: in the healthy v58 cycle the `-32800` came 28 ms after the click, followed by 20 status events and `ready` at 80.821 (+0.48 s). In v60: the `-32800` at 82.724 (+29 ms), then 9 events, the last at 83.008 (+0.31 s), then only 202.893 and 623.157 | **confirmed.** Nothing distinguishes the onset |
| 3 | v61 really reached Lean's input | Client frames are written to the ring synchronously while the phase is `open` (`lsp-front-door.js` `emit` :231-244, `admit` :340-358; keepAlive is on the forwarding list, :61-67). A parked ring would change `ring.bytesQueued` in the status JSON and post an event (`lean.worker.js` `emitStatus` :305-312, `residentPump` :193-216). No such event appeared | **confirmed.** The v61 bytes were in the ring by 202.893. qstatus shows `8/17` at 83.038 and `8/17` at 203.007 |
| 4 | Line citations name the code that was served | Pinned kernel = **9fbb45afcb** (QED64 `965c249`: "runtime wasm64-4b025db7729c5f89 (kernel 9fbb45afcb)"). `git diff --stat 8d91aadcda 9fbb45afcb -- src/runtime src/Lean/Server src/Std/Sync` is empty. Note: the kernel's HEAD is now **9af8a8652a** "task manager never creates a thread while holding m_mutex … (patch 0035, draft)" (11:40, object.cpp +146/−39), so reading the working tree no longer shows the served code. From `git show 9fbb45afcb:src/runtime/object.cpp`: `enqueue_core` :789 (→ `spawn_dedicated_worker` :873, `lthread` under the caller's lock), `handle_finished` :938, `wait_for` :1025; `thread.cpp` :141 `pthread_create` | **confirmed** for the served commit |
| 5 | Glue mailbox code | Served glue sha256 `3662dd667a6aa276…` (same 48,971,853 B in `qed64-showcase-work/stage1/bin` and QED64 `pipeline/toolchain/work/build/stage1/bin`). `checkMailbox = () => {…; runtimeKeepalivePush(); callUserCallback(() => { __emscripten_thread_mailbox_await(p); __emscripten_check_mailbox() }); runtimeKeepalivePop()}` (patch 0020 form). `__emscripten_thread_mailbox_await` arms `Atomics.waitAsync(HEAP32, p/4, p).value.then(checkMailbox)` and stores `waiting_async` at `p+204`. The proxy table is `[_proc_exit, exitOnMainThread, pthreadCreateProxied, …]`, and `__emscripten_receive_on_main_thread_js` calls `func(...)` with **no try/catch** | **confirmed** |
| 6 | 7.3 % CPU | `auditor-ux-full.log` (128 lines) has only RSS figures. No CPU sample is stored anywhere | **still unverifiable** |
| 7 | Memory growth near 83 s as a trigger | C3 in the same audit logged heap `2147483648 -> 2147483648` across all 8 examples. No growth event was found | **no evidence for it** (weak check) |

### W3. Correction: a lost main-thread wake is permanent on its own

* **Emscripten 6.0.5 never re-notifies.** Both `em_task_queue_send` (`system/lib/pthread/em_task_queue.c`
  :233-264) and `emscripten_thread_mailbox_send` (`thread_mailbox.c`) enqueue, then run
  `previous = atomic_exchange(&notification, NOTIFICATION_PENDING)`.
  * They notify only when `previous != PENDING`: by `memory.atomic.notify` on the thread word when
    `waiting_async` is set, otherwise by postMessage.
  * `PENDING` is cleared only inside `_emscripten_check_mailbox` (RECEIVED → execute → CAS to NONE).
  * So once a wake is lost, **every later sender sees `PENDING` and sends nothing.** §5.4's "any later proxied
    call would rescue it, but once every Lean thread is blocked on `m_mutex`, nobody proxies again" is false.
    The mailbox stays dead with or without `m_mutex`.
* **What `m_mutex` does explain is the shape of the freeze.**
  * A pthread's exit is a direct `postMessage({cmd:6})` (`__emscripten_thread_cleanup`), not a mailbox call.
    `_emscripten_thread_exit` takes no main-thread round trip (`pthread_create.c` :310-385).
  * So with a dead mailbox and *no* lock held, finishing dedicated threads would still exit, and `running`
    would have fallen between 83.038 and 202.893. It stayed at `8/17`, and E1 froze at `12/12`.
  * That is the fingerprint of a creator stuck in `pthread_create` while holding `m_mutex`.
  * The kernel fix (now drafted as patch 0035) would therefore change the shape, not cure it. Threads would keep
    draining, but every output frame still needs a proxied `fd_write`.
* **The one case where a later call does rescue.** If a proxied call *throws* inside the main thread's batch,
  `notification` is left at RECEIVED. The next sender then notifies the waiter armed before the batch, and the
  stranded calls run. Here `m_mutex` does decide the outcome: if the stranded call is a `pthread_create` under the
  lock, nobody proxies again.
  * The only silent throw is `ExitStatus`/`"unwind"`, which `callUserCallback`/`handleException` swallow.
  * In C20 it could come only from an exit, which W2-1 rules out.

### W4. Corrections to the first pass

* **V7's "raw `__emscripten_check_mailbox()` on a timer" is refuted by E1.** The raw export drains the queue once
  but does not re-arm the `waitAsync` chain, so the next wake is lost too (0 frames in 10 s). Only `checkMailbox()`,
  which re-arms and then processes, revived the runtime.
* **V7's warning about a blind 1 s `checkMailbox()` interval still holds.**
  * Each call arms one more `Atomics.waitAsync`.
  * `notify(-1)` wakes all of them, and each re-arms, so the count only grows.
  * Workable forms are those the owner is testing in `work/storm/run-series.sh` e2–e4. One is postMessage
    notifications (`waitAsyncPolyfilled = true` before init, the owner's `--message-mailbox`), where a raw
    `_emscripten_check_mailbox()` kick is safe. The other, in `waitAsync` mode, is a kick that re-arms only when no
    waiter is pending.
* **V6, updated:** the owner's `run1-burst2.log` last progress line, at +1773.3 s, reads 5,075 cycles and
  **771,228** spawns. It has no FREEZE line (and no summary line).
  * With our replay, about 813k creations ran in Node with 0 natural freezes.
  * Under §7's 1/340k rate with an equal Node hazard, about 2.4 freezes were expected; P(0) ≈ 0.09.
  * A per-creation race that does not depend on the host is now disfavoured.
  * A pure Lean lock cycle, which would not depend on the host either, is disfavoured for the same reason, though
    the capture still cannot exclude it.
  * The open trigger is most likely in the browser host layer: Chrome's `Atomics.waitAsync` and the event loop of
    the nested Worker. It is unproven. A web search found no matching Chromium/V8 report. The Emscripten test
    `test_pthread_waitasync_after_exit` covers stale waiters on *recycled pthread structs*, and the main thread's
    struct is never recycled.

### W5. Side finding (latent QED64 bug, not L7)

* **The pieces:**
  * `_proc_exit` in the glue calls `Module.onExit` only when `!keepRuntimeAlive()`.
  * QED64 pushes a keepalive at boot (`lean.worker.js` :1015-1016), and `callMain` pushes another.
  * `IO.Process.forceExit` is `std::_Exit` → `__wasi_proc_exit` (musl `_Exit.c`) → a synchronous proxy, `(0,0,1)`.
* **What follows.** On the main thread, `quit_` throws `ExitStatus`, and `callUserCallback` swallows it.
  `onExit → die(code,"exit")` (`lean.worker.js` :970) never fires, and the exiting FileWorker pthread waits
  forever.
* **What a user would see.** A FileWorker fatal error would show as an L7-like freeze plus one `[lean:stderr]` line
  and one error diagnostic.
* **What to tell the QED64 owner.** The comment at :966-969 ("main returning … is a death FACT") does not hold in
  resident mode.

### W6. Dynamic

* **Our replay was not re-run.** It claimed no repro (0 hangs in 271 cycles), so a re-run could not refute
  anything.
* **The host was not available anyway.**
  * 11:53: no browser lock, but 6.1 GB free+inactive.
  * 12:07–12:10: browser lock held by `audit5`, 15–17 GB free, chrome-headless-shell running, and the owner's
    patch-0035 gate (`node-runner.mjs`) running.
* **The deciding dynamic result belongs to the owner.** It is E1, an injected lost wake: 1 of 1 froze, with the L7
  signature, and `checkMailbox()` revived it. We did not repeat it, per the division of labour.

### W7. Fixes, ranked by expected effect on L7 as users see it

1. **QED64 worker: a self-healing main-thread mailbox.** Use the postMessage notification mode plus a raw
   `_emscripten_check_mailbox()` kick about every 1 s. If L7 is a lost wake, as E1 suggests, it becomes a hiccup of
   at most 1 s. Owner series e2–e4 measure exactly this.
2. **Ours: the gallery liveness probe with automatic restart**, plus the V7 guards (string id, 2 misses, rate
   limit). It bounds L7 from any cause to about 15–20 s and needs no QED64 change.
3. **QED64: Lean-level liveness.** A cheap request through the ring while `elaborating` and silent; no answer
   means death, then reboot.
4. **QED64: on a stall in the browser, call `checkMailbox()` once and log whether frames resume.** This names the
   browser trigger in the field, with E1 as the reference signature.
5. **Kernel patch 0035** (no `pthread_create` under `m_mutex`, parked-thread reuse). It means fewer proxies and
   threads that keep draining, but output still stops if the mailbox is dead (W3). It is hygiene, not a cure.
6. **Kernel: one long-lived FileWorker output thread.** This cuts about 110 of 153 creations per cycle.
7. **Ours, optional: cap concurrent `$/lean/rpc/call`.** The effect is small.
8. **Docs: correct L7** in `gallery/README.md` and `docs/UX-RESULTS.md`.
9. **Keep the D1 strip.**

§8 QED64 fix 2, as written (`setInterval(checkMailbox, 1000)` in `waitAsync` mode), should not be shipped
(W4).
