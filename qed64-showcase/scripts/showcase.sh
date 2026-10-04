#!/usr/bin/env bash
# showcase.sh — one entry point for the QED64 widget showcase. It delegates to the stage scripts in
# scripts/ in the right order, with the cross-stage guards the build relies on, and logs every step.
#
#   scripts/showcase.sh [--dry-run] <subcommand> [args]
#
#   bootstrap [--pin <id>] [--origin URL] [--qed64-origin URL] [--no-verify]
#                                   FROM A CLONE: QED64's sources (the submodule deps/qed64, or the pin's
#                                   worktree) → npm ci at the root if needed → the widget export → the
#                                   page built from source (scripts/build-shell.mjs: byte-identical to the
#                                   lock or nothing installed) → QED64's binaries and our overlays fetched
#                                   from artifact origins, sha256-checked against the lock
#                                   (scripts/fetch-artifacts.mjs) → the active pin's serve links → verify.
#                                   Origins: --origin / ARTIFACT_ORIGIN (the showcase's own origin, serves
#                                   both), --qed64-origin / QED64_ARTIFACT_ORIGIN (QED64's own files only).
#   pin [--yes]                 S0  release clone + lock from a QED64 checkout with QED64's binaries
#                                   built (QED64_REPO; registering a NEW pin). Without --yes: read-only
#                                   precondition report only (QED64 HEAD/clean vs the pinned commit).
#   verify [--deep] [--untouched NAME]
#                                   S0.5 chain of trust (pin-qed64 verify), pin-constant consistency
#                                   across scripts, stage1 buildId, overlay pairing (cheap; --deep also
#                                   gunzips and digest-checks every overlay .snapz), gallery freshness,
#                                   optionally assert-untouched check NAME.
#   native [all|identity|reuse-pre|delta|gate-delta|append|reuse-post|widgets|gate-widgets|
#           distlens|gate-distlens|reuse-final]
#                                   S2  native64 Docker build of the widget delta (build-native.sh). One
#                                   Docker job at a time; refused while a bake runs.
#   stage [w7|w8|fat|all] [--force]
#                                   S3  C1/C2 olean trees (stage-trees.mjs). Refused while a bake runs.
#   bake [w7|w8|all]            S3  C4 bake + C5 judge + C6 offline pairing. The bake itself runs under
#                                   the browser lock (no browser may overlap a bake); refused while a
#                                   browser, a Docker container or another bake runs.
#   overlay [w7|w8|all] [--preflight]
#                                   S3  C7 overlay for the stock page + pairing (--cmp against the raw
#                                   bake region). --preflight adds QED64's own read-only preflight
#                                   (boots a headless browser: takes the browser lock).
#   headless [all|controls|stage4 [w8|w7|all] [pkg…]|e2 [pkg…]|summary]
#                                   S4  wasm verification in Node (no browser): controls, E1/E3/E3b, E2.
#   gallery [--live]            S6  regenerate gallery data only if stale, then the static gate; prints the
#                                   gallery content sha256 (scripts/lib/gallery-hash.mjs) the result is for,
#                                   and whether the last green `showcase.sh ux` run was on that same gallery.
#   serve                       start scripts/serve.mjs (PORT, default 5190) unless one is already up.
#   stop [--force]              stop the server on PORT, but only one this lane (SHOWCASE_LANE)
#                                   started through `showcase.sh serve`; --force overrides.
#   ux [args…]                  S6  the Playwright UX suite (tests/ux, owned by the UX lane): the same
#                                   command as `npm run test:ux` (with-browser-lock.sh + playwright test
#                                   -c tests/ux/playwright.config.mjs), plus the browser preflight below.
#                                   The suite itself starts/stops serve.mjs on :5190 when none is up.
#                                   Each run appends {start,end,lane,rc,galleryStart,galleryEnd,args} to
#                                   out/ux/showcase-ux-runs.jsonl (the UX verdict's gallery revision; only a
#                                   full-suite run — no args — with rc 0 and an unchanged gallery is a verdict).
#                                   UX_RUN names the run; a name already used (out/ux/<run>/ exists or the
#                                   jsonl records it) is REFUSED (rc 3) before anything starts.
#   locked <what> -- <cmd…>     run any command under the browser lock AND after the browser preflight
#                                   (>= MIN_BROWSER_GB free+inactive, no stray headless Chrome, no bake),
#                                   e.g. a one-off Playwright probe: showcase.sh locked probe -- node x.mjs
#   all [--rebuild]             verify → native → stage → bake → overlay → headless → gallery → ux.
#                                   Skipped unless --rebuild: native (out/native-build.json exists), stage
#                                   (the three trees exist), bake w7/w8 (judge-bake GREEN), overlay w7/w8
#                                   (index.json exists), headless (out/headless/summary.json for the lock's
#                                   buildId has gate.stage4Green and gate.E2Green, and no bake/overlay was
#                                   redone in this run). gallery and ux always run.
#
#   --dry-run (-n), anywhere:   print the plan and run only the read-only guards (a guard that would
#                               refuse is reported as a WARN, and the plan is still printed); execute nothing.
#
# Browser lock: ONE implementation, scripts/with-browser-lock.sh (also behind `npm run test:ux`). Every
# locked step (ux, locked, bake, overlay --preflight) runs as
#   with-browser-lock.sh <lane>-<what> bash showcase.sh _inlock <kind> -- <cmd…>
# so the lock file format (host-wide: `with-browser-lock.sh --print-lock`, default ~/.cache/host-browser-lock/browser.lock),
# the FIFO queue, the stale-lock takeover mutex (<lock>.takeover, content-compared),
# the cooldown (memory, no chrome-headless-shell) and `caffeinate -i` are the same for every lane;
# `_inlock` (internal) re-runs this script's preflight inside the lock, then execs the command.
# Long unlocked steps (native, stage, headless) also run under `caffeinate -i` (process-scoped assertion:
# no idle sleep while they run; changes no setting). NO_CAFFEINATE=1 disables both.
#
# Locations (scripts/lib/env.sh; the gitignored .env.local, template .env.example): QED64_SHOWCASE_WORK ($W, the work
#      dir), QED64_REPO ($Q), QED64_KERNEL_BUILD ($K); a subcommand that needs Q or K refuses with a clear error if unset.
#      QED64's SOURCES are the submodule deps/qed64 (+ git worktrees $W/qed64-pins/<id> for staged pins), never Q.
# Platform (scripts/lib/platform.sh): macOS and Linux. The memory probe is vm_stat / /proc/meminfo, clones are cp -c /
#      cp --reflink=auto, and the idle-sleep guard (caffeinate) exists only on macOS.
# Env: SHOWCASE_LANE (name written into lock/owner files; default "showcase.sh"), PORT (default 5190),
#      LOCK_WAIT_S / COOLDOWN_WAIT_S (with-browser-lock.sh waits, default 3600 s each), MIN_BROWSER_GB (6),
#      WITH_BROWSER_LOCK (the lock script — change only for tests), BROWSER_LOCK_DIR (where the host-wide lock lives,
#      default ~/.cache/host-browser-lock; every lane on the host must use the same one),
#      BASE_SLIM / BASE_FAT / CORE_SRC / BASE_N (the served olean trees the bake trees start from, the
#      served core lib, and the served region's module count; change them only on a re-pin).
# Exit: 0 ok · 1 a step failed · 2 usage · 3 refused by a guard. A locked step is reported as REFUSED (exit
#       3) only for with-browser-lock.sh's 75 (lock wait timed out) and 76 (cooldown refused) and for 77, the
#       code `_inlock` uses for its own preflight refusal; any other rc, including a locked command's own 3, is
#       that command's result and passes through (so `locked x -- cmd` exiting 3 means cmd exited 3: a refusal
#       prints only the `[showcase] REFUSED:` line, a command failure only `<what>: FAILED rc=N`).
# Logs: every executed step tees into $W/logs/showcase-<lane>-<sub>-<step>.log (<lane> = SHOWCASE_LANE with
# unsafe characters replaced, so concurrent lanes never overwrite each other's logs); the exit code
# checked is the step's own (PIPESTATUS), never the tee's.
set -uo pipefail

SC="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
# SC, REPO_ROOT, WS, W (QED64_SHOWCASE_WORK), Q (QED64_REPO), K (QED64_KERNEL_BUILD), LOGS: scripts/lib/env.sh (reads the
# gitignored .env.local; template .env.example). Q and K are required only by the subcommands that read them (need …).
. "$SC/scripts/lib/env.sh"
. "$SC/scripts/lib/platform.sh"   # PLATFORM, free_inactive_gib, clone_file/clone_tree, file_size, AWAKE (caffeinate -i on macOS)
WBL="${WITH_BROWSER_LOCK:-$SC/scripts/with-browser-lock.sh}"
LOCK="$(bash "$WBL" --print-lock)" || { echo "[showcase] ERROR: $WBL --print-lock failed" >&2; exit 1; }   # the file with-browser-lock.sh uses
LANE="${SHOWCASE_LANE:-showcase.sh}"
LANE_TAG="$(printf '%s' "$LANE" | tr -c 'A-Za-z0-9._-' '_')"   # file-name-safe lane name for logs
PORT="${PORT:-5190}"
MIN_BROWSER_GB="${MIN_BROWSER_GB:-6}"
# the served base trees come from the TARGET pin's descriptor (pins/<id>/pin.json servedTrees; scripts/lib/pins.mjs):
# SHOWCASE_PIN=<id> (a registered, possibly staged pin: stage/bake/overlay/headless then use that pin's own stores and
# never the active links; nothing is switched), else the active pin
pin_field() { node "$SC/scripts/lib/pins.mjs" field "$1" 2>/dev/null; }
store() { node "$SC/scripts/lib/pins.mjs" store "$1"; }   # a store of the target pin (scripts/lib/pins.mjs storePath)
BASE_SLIM="${BASE_SLIM:-$(pin_field servedTrees.baseSlim)}"
BASE_FAT="${BASE_FAT:-${Q:+$Q/work/lib-tree}}"
CORE_SRC="${CORE_SRC:-$(pin_field servedTrees.coreSrc)}"   # the served core lib (exact bytes) for a core delta
BASE_N="${BASE_N:-$(pin_field servedTrees.baseN)}"                                     # modules in the served region's tree
ROOTS7="QED64.Essential,ChartKit,ExprXRay,GraphScope,HasseView,IntervalInspector,SimpLens,TreeScope"
ROOTS8="$ROOTS7,DistLens"
ROOTSFAT="$ROOTS8,LeanWidgetKit"

DRY=0; ARGS=()
for a in "$@"; do case "$a" in --dry-run|-n) DRY=1 ;; *) ARGS+=("$a") ;; esac; done
set -- "${ARGS[@]+"${ARGS[@]}"}"
SUB="${1:-}"; shift || true
mkdir -p "$LOGS" "$SC/out"

say()  { printf '[showcase] %s\n' "$*"; }
die()  { printf '[showcase] ERROR: %s\n' "$*" >&2; exit 1; }
REFUSE_RC=3   # cmd_inlock sets 77, so a preflight refusal inside the lock is distinguishable from the command's rc
refuse() { printf '[showcase] REFUSED: %s\n' "$*" >&2; exit "$REFUSE_RC"; }
usage() { sed -n '2,/^set -uo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }
q() { printf '%q ' "$@"; }
# AWAKE (scripts/lib/platform.sh): prefix for long steps — on macOS a process-scoped `caffeinate -i` assertion (this
# host idles to sleep after 1 min; an unattended UX run once slept 988 s mid-test, docs/UX-RESULTS.md); empty elsewhere
# and with NO_CAFFEINATE=1.
oneline() { printf '%s' "$1" | tr '\n' ' '; }   # pid lists on one line

# step <name> <cmd…>: echo the command; in --dry-run stop there; else run it teeing into a log and
# return the command's own exit status.
step() {
  local name="$1"; shift
  local log="$LOGS/showcase-$LANE_TAG-$SUB-$name.log"
  printf '+ %s\n' "$(q "$@")"
  [ "$DRY" = 1 ] && return 0
  { echo "=== $(date -u +%FT%TZ) $LANE: $(q "$@")"; } > "$log"
  "$@" 2>&1 | tee -a "$log"
  local rc=${PIPESTATUS[0]}
  echo "=== exit=$rc" >> "$log"
  if [ "$rc" = 0 ]; then say "$name: OK (log $log)"
  elif [[ " ${STEP_REFUSAL_RCS:-} " == *" $rc "* ]]; then :   # locked_run prints the one REFUSED line for these
  else say "$name: FAILED rc=$rc (log $log)"; fi
  return "$rc"
}
must() { step "$@" || exit 1; }
# vstep <name> <cmd…>: a cheap read-only check with a 600 s watchdog (perl alarm -> rc 142), retried once on
# timeout. Reason: on 2026-10-01 `build-gallery.mjs --check` printed CHECK OK and then never exited — `sample`
# showed node::Environment::Exit joining a V8 baseline-compiler worker stuck in allocation (a Node v26 exit
# deadlock, 1 in ~8 runs here, not this repo's code). A hang there must not stall verify forever.
vstep() {
  local name="$1"; shift; local rc
  step "$name" perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "${VSTEP_TIMEOUT_S:-600}" "$@"; rc=$?
  if [ "$rc" = 142 ]; then say "$name: timed out after ${VSTEP_TIMEOUT_S:-600}s (see the Node exit deadlock note in showcase.sh); retrying once"
    step "$name" perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "${VSTEP_TIMEOUT_S:-600}" "$@"; rc=$?; fi
  return "$rc"
}

# ---------------------------------------------------------------- guards (read-only)
free_gib() { free_inactive_gib; }   # scripts/lib/platform.sh: macOS free+inactive (vm_stat), Linux MemAvailable
bake_pids() { pgrep -f '^(/usr/bin/time -l )?node .*bake-snapshot\.mjs' 2>/dev/null || true; }
browser_pids() { pgrep -f 'chrome-headless-shell|Google Chrome for Testing' 2>/dev/null || true; }
docker_busy() { command -v docker >/dev/null && [ -n "$(docker ps -q 2>/dev/null)" ]; }
# docker_image_guard: `native` must run in the toolchain image the lock records (QED64.lock.json
# toolchain.docker.id: the image the delta oleans were built in). The tag qed64-toolchain:emsdk-6.0.5 is
# QED64's (its pipeline/toolchain/build.sh re-runs `docker build -t` on it), so it can move under us; then
# `native` refuses until the image is re-pinned (README "Re-pin": Docker tag drift). verify reports it as DRIFT.
docker_image_guard() {
  local img want got
  img="$(node -p 'require(process.argv[1]).toolchain.docker.image' "$SC/QED64.lock.json")"
  want="$(node -p 'require(process.argv[1]).toolchain.docker.id' "$SC/QED64.lock.json")"
  got="$(docker image ls --no-trunc --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null | awk -v t="$img" '$1 == t {sub(/^sha256:/, "", $2); print $2; exit}')"
  case "$got" in
    "$want"*) say "toolchain image $img = ${got:0:12} == lock" ;;
    "") guard_fail "toolchain image $img not present (or Docker not reachable); the lock records $want" ;;
    *) guard_fail "toolchain image $img is now ${got:0:12}, but the native oleans were built in $want (QED64.lock.json); the tag moved — see README \"Re-pin\" (Docker tag drift) before rebuilding" ;;
  esac
}
lock_desc() { if [ -f "$LOCK" ]; then printf 'held: %s' "$(cat "$LOCK" 2>/dev/null)"; else printf 'free'; fi; }

no_bake() { local p; p="$(bake_pids)"; [ -z "$p" ] || refuse "a snapshot bake is running (pid $(oneline "$p")); $1"; }
# guard_fail <msg>: refuse (exit 3); in --dry-run only WARN, so the rest of the plan is still printed.
guard_fail() { if [ "$DRY" = 1 ]; then say "dry-run WARN: would refuse now: $*"; else refuse "$*"; fi; }

# Before any browser boot: enough free+inactive memory, no stray headless browser, no bake. Runs INSIDE the
# lock (via _inlock), after with-browser-lock.sh's own cooldown; in --dry-run it only reports.
browser_preflight() {
  local fg strays bk; fg="$(free_gib)"; strays="$(oneline "$(browser_pids)")"; strays="${strays% }"; bk="$(oneline "$(bake_pids)")"; bk="${bk% }"
  say "free+inactive ${fg} GiB (need >= $MIN_BROWSER_GB); stray browsers: ${strays:-none}; bake: ${bk:-none}"
  [ -z "$bk" ] || guard_fail "a snapshot bake is running (pid $bk); a browser never overlaps a bake"
  [ "$fg" -ge "$MIN_BROWSER_GB" ] || guard_fail "only ${fg} GiB free+inactive (< $MIN_BROWSER_GB)"
  if [ -n "$strays" ] && [ "$DRY" = 1 ]; then
    say "dry-run WARN: headless Chrome running now (pids $strays): a real run waits for chrome-headless-shell in the lock's cooldown (COOLDOWN_WAIT_S, default 3600 s; then rc 76 -> REFUSED), and refuses if any remain inside the lock"
  elif [ -n "$strays" ]; then refuse "chrome-headless-shell / Chrome for Testing already running (pids $strays); not ours to kill"; fi
}
# Inside the lock before a bake: no browser, no Docker container, no other bake.
bake_preflight() {
  local b; b="$(oneline "$(browser_pids)")"; b="${b% }"
  no_bake "one bake at a time"
  [ -z "$b" ] || guard_fail "a browser is running (pids $b); bakes never overlap a browser"
  if docker_busy; then guard_fail "a Docker container is running; bakes never overlap Docker"; fi
}

# locked_run <what> <browser|bake> <cmd…>: run <cmd> as a logged step under the ONE browser-lock
# implementation (with-browser-lock.sh: atomic noclobber lock "<lane> <pid> <time>", content-compared stale
# takeover under <lock>.takeover, FIFO queue, cooldown, caffeinate -i), re-running our preflight inside it.
# Returns the command's rc; a lock timeout (75), a cooldown refusal (76) or our in-lock preflight refusal (77)
# exit 3 (REFUSED). Every other rc, a command's own 3 included, is returned unchanged.
locked_run() {
  local what="$1" kind="$2"; shift 2
  if [ "$DRY" = 1 ]; then
    say "dry-run: browser lock $(lock_desc); would run under $(basename "$WBL") as lane ${LANE_TAG}-${what}"
    [ "$kind" = browser ] && browser_preflight      # bake: cmd_bake already ran bake_preflight
    printf '+ %s\n' "$(q "$WBL" "${LANE_TAG}-${what}" bash "$SELF" _inlock "$kind" -- "$@")"
    return 0
  fi
  STEP_REFUSAL_RCS="75 76 77" step "$what" env LOCK_WAIT_S="${LOCK_WAIT_S:-3600}" MIN_FREE_GB="$MIN_BROWSER_GB" \
    bash "$WBL" "${LANE_TAG}-${what}" bash "$SELF" _inlock "$kind" -- "$@"
  local rc=$?
  case "$rc" in 75|76|77) refuse "$what: refused by the lock/preflight (rc=$rc; see the log)";; esac
  return "$rc"
}
cmd_inlock() {   # internal: _inlock <browser|bake> -- <cmd…>  (runs inside with-browser-lock.sh)
  local kind="${1:-}"; shift || true
  [ "${1:-}" = -- ] || die "usage: _inlock <browser|bake> -- <cmd…>"; shift
  [ $# -gt 0 ] || die "_inlock: no command"
  REFUSE_RC=77
  say "inside the browser lock: $(lock_desc)"
  case "$kind" in browser) browser_preflight ;; bake) bake_preflight ;; *) die "_inlock: unknown kind $kind" ;; esac
  exec "$@"
}

pidfile() { if [ "$PORT" = 5190 ]; then echo "$SC/out/serve.pid"; else echo "$SC/out/serve-$PORT.pid"; fi; }
ownerfile() { echo "$(pidfile).owner"; }
port_answers() { curl -s -o /dev/null --max-time 5 "http://localhost:${1:-$PORT}/"; }
# server_is_showcase [port]: the listener is OUR serve.mjs for THIS pin, not any HTTP server that happens to
# hold the port: /showcase/pin.json answers 200 with COEP require-corp + CORP same-origin, its buildId equals the
# lock's, its X-Showcase-Pin header names the active pin, and it serves the local gallery. Prints the reason when not.
server_is_showcase() {
  local port="${1:-$PORT}" hdr body bid want
  hdr="$(curl -s -D - -o /dev/null --max-time 5 "http://localhost:$port/showcase/pin.json" | tr -d '\r')"
  printf '%s' "$hdr" | head -1 | grep -q ' 200' || { echo "GET /showcase/pin.json is not 200 ($(printf '%s' "$hdr" | head -1))"; return 1; }
  printf '%s' "$hdr" | grep -qi '^cross-origin-embedder-policy: *require-corp' || { echo "no COEP require-corp header"; return 1; }
  printf '%s' "$hdr" | grep -qi '^cross-origin-resource-policy: *same-origin' || { echo "no CORP same-origin header"; return 1; }
  body="$(curl -s --max-time 5 "http://localhost:$port/showcase/pin.json")"
  bid="$(printf '%s' "$body" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).buildId||"")}catch{console.log("")}})')"
  want="$(lock_buildid)"
  [ "$bid" = "$want" ] || { echo "pin.json buildId '${bid}' != lock $want"; return 1; }
  # ... and it serves the ACTIVE pin's release: serve.mjs fixes its pin at start and says so in X-Showcase-Pin (a pin
  # switch never changes what a running server serves; two pins can share a buildId, so pin.json alone cannot tell)
  local sp ap; sp="$(printf '%s' "$hdr" | sed -n 's/^[Xx]-[Ss]howcase-[Pp]in: *//p' | head -1)"
  ap="$(node "$SC/scripts/lib/pins.mjs" active) $want"
  [ "$sp" = "$ap" ] || { echo "it serves pin '${sp:-none}', not the active pin '$ap' (restart it: showcase.sh stop; showcase.sh serve)"; return 1; }
  # ... and it serves THIS gallery: the content sha256 over the bytes it returns for every shipped gallery file equals
  # the local one (a GALLERY_DIR=<mutant> server on the port is not "the showcase"; docs audit r3)
  local served mine
  served="$(node "$SC/scripts/lib/ux-record.mjs" served "http://localhost:$port" 2>&1)" || { echo "its /showcase/ files do not all answer: $served"; return 1; }
  mine="$(gallery_hash)"
  [ "$served" = "$mine" ] || { echo "it serves gallery ${served:0:16}…, not the local gallery/ ${mine:0:16}… (another GALLERY_DIR?)"; return 1; }
}

sha256sum_() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi; }
lock_buildid() { node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).qed64.buildId' "$SC/QED64.lock.json"; }

# ---------------------------------------------------------------- subcommands
# pin: the multiple-pin model (scripts/lib/pins.mjs; docs/REPIN-LOG.md "Multiple pins"). Pins are keyed by QED64 commit
# (id = first 7 hex digits); one is active (the links QED64.lock.json, out/overlay/snapshots/widgets{7,8},
# out/headless, $W/stage1 …). Subcommands:
#   pin list | current | check <id> [--full]     scripts/pin-switch.mjs (read-only)
#   pin use <id> [--dry-run] [--no-deploy]        switch the active pin (scripts/pin-switch.mjs use: guards, atomic links,
#                                                 gallery/pin.json, deploy inputs), then `pin current`
#   pin clone <id> [--yes]                        S0 for a REGISTERED pin (pins/<id>/pin.json) from QED64_REPO (a checkout
#                                                 with QED64's binaries built): without --yes only the S0.2
#                                                 report (QED64 HEAD/clean vs the pin's commit); with --yes pin-qed64.mjs
#                                                 pin --pin <id> + record-widgets-hash + verify (writes only pins/<id>/ and
#                                                 release/<id>/; never switches)
#   pin [--yes]                                   = pin clone <active id> [--yes] (the single-pin form)
cmd_pin() {
  local sub="${1:-}"
  case "$sub" in
    list|current) step "pin-$sub" node "$SC/scripts/pin-switch.mjs" "$sub"; return $? ;;
    check) shift; step "pin-check-${1:-x}" node "$SC/scripts/pin-switch.mjs" check "$@"; return $? ;;
    use)
      shift; local to="${1:?pin use <id>}"; shift
      local a dryflag=""; [ "$DRY" = 1 ] && dryflag=--dry-run
      for a in "$@"; do [ "$a" = --dry-run ] && dryflag=--dry-run; done
      local rest=(); for a in "$@"; do [ "$a" = --dry-run ] || rest+=("$a"); done
      node "$SC/scripts/pin-switch.mjs" use "$to" $dryflag ${rest[@]+"${rest[@]}"} 2>&1 | tee "$LOGS/showcase-$LANE_TAG-pin-use-$to.log"
      local rc=${PIPESTATUS[0]}
      [ "$rc" = 3 ] && exit "$REFUSE_RC"
      [ "$rc" = 0 ] || return "$rc"
      [ -n "$dryflag" ] && return 0
      step pin-current node "$SC/scripts/pin-switch.mjs" current; return $? ;;
    clone) shift; cmd_pin_clone "$@"; return $? ;;
    ""|--yes) cmd_pin_clone "$(node "$SC/scripts/lib/pins.mjs" active)" "$@"; return $? ;;
    *) die "pin: unknown subcommand '$sub' (list | current | check <id> | use <id> | clone <id> [--yes])" ;;
  esac
}
cmd_pin_clone() {
  local id="${1:?pin clone <id> [--yes]}"; shift
  local qpin head dirty
  need QED64_REPO
  qpin="$(node "$SC/scripts/lib/pins.mjs" field qed64.commit "$id")" || die "pin $id is not registered (pins/$id/pin.json)"
  head="$(git --no-optional-locks -C "$Q" rev-parse HEAD 2>/dev/null || echo '?')"
  dirty="$(git --no-optional-locks -C "$Q" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  say "pin $id = QED64 $qpin; QED64 HEAD=$head; uncommitted paths in QED64: $dirty"
  if [ "${1:-}" != --yes ]; then
    if [ "$head" = "$qpin" ] && [ "$dirty" = 0 ]; then say "precondition S0.2 holds: 'showcase.sh pin clone $id --yes' would re-clone release/$id and rewrite pins/$id/QED64.lock.json from $qpin"
    else say "precondition S0.2 does NOT hold: 'pin clone $id --yes' would refuse (see the re-pin procedure in README.md)"; fi
    say "nothing written (pass --yes to run pin-qed64.mjs pin --pin $id + record-widgets-hash + verify)"
    return 0
  fi
  no_bake "pinning rewrites release/$id under a running bake"
  [ "$id" != "$(node "$SC/scripts/lib/pins.mjs" active)" ] || ! pgrep -f "$SC/scripts/serve.mjs" >/dev/null || refuse "this repo's serve.mjs is running and may serve release/$id; stop it first"
  must pin node "$SC/scripts/pin-qed64.mjs" pin --pin "$id"
  must record-widgets-hash node "$SC/scripts/pin-qed64.mjs" record-widgets-hash --pin "$id"
  must verify node "$SC/scripts/pin-qed64.mjs" verify --pin "$id"
}

# bootstrap: a clone becomes a working showcase without QED64_REPO or the kernel build (docs/ARCHITECTURE.md). Every
# step checks its own result against the committed lock; nothing is installed that does not match it.
cmd_bootstrap() {
  local id="" origin="${ARTIFACT_ORIGIN:-}" qorigin="${QED64_ARTIFACT_ORIGIN:-}" doverify=1
  while [ $# -gt 0 ]; do case "$1" in
    --pin) id="${2:?--pin <id>}"; shift 2 ;; --origin) origin="${2:?--origin <url>}"; shift 2 ;;
    --qed64-origin) qorigin="${2:?--qed64-origin <url>}"; shift 2 ;; --no-verify) doverify=0; shift ;;
    *) die "bootstrap: unknown arg $1 (--pin <id> --origin <url> --qed64-origin <url> --no-verify)" ;; esac; done
  local act; act="$(node "$SC/scripts/lib/pins.mjs" active)" || die "no active pin (QED64.lock.json)"
  [ -n "$id" ] || id="$act"
  say "bootstrap pin $id (active: $act); origins: showcase ${origin:-none}, qed64 ${qorigin:-none}"
  must sources node "$SC/scripts/qed64-src.mjs" ensure "$id"
  if [ ! -d "$SC/node_modules/@playwright/test" ]; then must npm-ci bash -c "cd \"\$1\" && npm ci --no-audit --no-fund" _ "$SC"; else say "node_modules present (npm ci skipped)"; fi
  local wc; wc="$(node -p 'require(process.argv[1]).WIDGETS_COMMIT' "$SC/pins/$id/QED64.lock.json")"
  if node "$SC/scripts/export-widgets.mjs" --commit "$wc" --check >/dev/null 2>&1; then say "widget export \$W/widgets-src == git archive ${wc:0:12} packages/ (the lock's WIDGETS_COMMIT)"
  else must export-widgets node "$SC/scripts/export-widgets.mjs" --commit "$wc"; fi
  must shell node "$SC/scripts/build-shell.mjs" --pin "$id"
  local fa=(node "$SC/scripts/fetch-artifacts.mjs" --pin "$id")
  [ -n "$origin" ] && fa+=(--origin "$origin"); [ -n "$qorigin" ] && fa+=(--qed64-origin "$qorigin")
  must artifacts "${fa[@]}"
  if [ "$id" = "$act" ]; then
    must links node "$SC/scripts/pin-switch.mjs" use "$id"
  else say "pin $id is staged: its stores are ready; switch with: scripts/showcase.sh pin use $id"; fi
  if [ "$doverify" = 1 ] && [ "$id" = "$act" ]; then cmd_verify || return 1; fi
  [ "$DRY" = 1 ] || say "BOOTSTRAP OK: pin $id built from source + fetched artifacts, every file == pins/$id/QED64.lock.json"
}

# Pin constants (multiple pins): NO file under scripts/, tests/, gallery/ or infra/ may hardcode a pin. Every script and
# test asks scripts/lib/pins.mjs (the active lock) for the buildId, the release dir (release/<id>), the served trees and the
# QED64 main bundle (selectors.json says "@qed64-main-bundle"). So a real runtime buildId is accepted ONLY in PIN_SITES
# (gallery/pin.json, generated from the active lock by build-gallery.mjs), with exact counts and equal to the active pin's;
# a hashed QED64 bundle name (/assets/index-<8>.js) or a release/wasm64-… path anywhere is a FAIL. The all-zero / all-f ids
# are deliberate fake runtimes (the gallery gate's mutation tests; the UX suite's C9 unpaired-runtime fixture) and are
# accepted ONLY in SENTINEL_SITES, with exact counts.
PIN_SITES="gallery/pin.json:2"
SENTINEL_SITES="scripts/check-gallery.mjs:3 scripts/sim-gallery.mjs:1 tests/ux/specs/30-robustness.spec.mjs:2"
check_pin_constants() {
  node - "$SC" "$PIN_SITES" "$SENTINEL_SITES" <<'EOF'
const fs = require('fs'), path = require('path');
const [root, pinSites, sentSites] = process.argv.slice(2);
(async () => {
const P = await import(path.join(root, 'scripts/lib/pins.mjs'));
let bad = 0;
const id = P.activePinId(), bid = P.activeBuildId();
console.log(`     active pin ${id} (runtime ${bid}); registered: ${P.listPins().map((p) => p.id).join(', ')}`);
const table = (str) => new Map(str.trim().split(/\s+/).map((e) => { const i = e.lastIndexOf(':'); return [e.slice(0, i), +e.slice(i + 1)]; }));
const expected = table(pinSites), sentinels = table(sentSites);
const EXT = /\.(mjs|cjs|js|sh|json|py|ts)$/;
const SKIP = new Set(['node_modules', 'out', 'work', 'release', 'vendor', 'deps', '__screenshots__']);
const files = [];
const walk = (rel) => {
  for (const e of fs.readdirSync(path.join(root, rel), { withFileTypes: true })) {
    const r = path.posix.join(rel, e.name);
    if (e.isDirectory()) { if (!SKIP.has(e.name)) walk(r); } else if (EXT.test(e.name)) files.push(r);
  }
};
for (const d of ['scripts', 'tests', 'gallery', 'infra']) if (fs.existsSync(path.join(root, d))) walk(d);
const real = new Map(), fake = new Map(), wrong = [], hard = [];
for (const f of files) {
  fs.readFileSync(path.join(root, f), 'utf8').split('\n').forEach((l, i) => {
    for (const m of l.matchAll(/wasm64-[0-9a-f]{16}/g)) {
      const x = m[0];
      if (/^wasm64-(0{16}|f{16})$/.test(x)) { if (sentinels.has(f)) fake.set(f, (fake.get(f) || 0) + 1); else wrong.push(`${f}:${i + 1}: ${x} (fake all-0/all-f id outside the sentinel files)`); }
      else if (expected.has(f) && x === bid) real.set(f, (real.get(f) || 0) + 1);
      else wrong.push(`${f}:${i + 1}: ${x}${expected.has(f) ? ` (!= the active pin's ${bid})` : ' (hardcoded runtime buildId: ask scripts/lib/pins.mjs)'}`);
    }
    for (const m of l.matchAll(/\/assets\/index-[A-Za-z0-9_-]{8}\.js/g)) hard.push(`${f}:${i + 1}: ${m[0]} (hashed QED64 bundle name: use "@qed64-main-bundle" / pins.mjs mainBundle())`);
    if (/release\/wasm64-[0-9a-f]/.test(l)) hard.push(`${f}:${i + 1}: release/wasm64-… (releases are keyed by pin id: pins.mjs releaseOf())`);
  });
}
if (wrong.length) { console.log('FAIL runtime buildIds outside the generated pin sites (or != the active pin):'); for (const w of wrong) console.log(`     ${w}`); bad++; }
if (hard.length) { console.log('FAIL hardcoded pin artifacts:'); for (const w of hard) console.log(`     ${w}`); bad++; }
const miss = [];
for (const [f, n] of expected) if ((real.get(f) || 0) !== n) miss.push(`${f}: ${real.get(f) || 0} occurrence(s) of the active buildId, expected ${n} (run node scripts/build-gallery.mjs)`);
for (const [f, n] of sentinels) if ((fake.get(f) || 0) !== n) miss.push(`${f}: ${fake.get(f) || 0} sentinel id(s), expected ${n}`);
if (miss.length) { console.log('FAIL pin-site inventory:'); for (const m of miss) console.log(`     ${m}`); bad++; }
// the console allowlist's bundle token resolves to the active pin's main bundle, which exists in its release
const raw = fs.readFileSync(path.join(root, 'tests/ux/selectors.json'), 'utf8');
const nTok = raw.split('"' + P.MAIN_BUNDLE_TOKEN + '"').length - 1;
const mb = P.mainBundle(id);
const mbOk = fs.existsSync(path.join(P.releaseOf(id), 'dist', mb));
if (nTok > 0 && mbOk) console.log(`OK   tests/ux/selectors.json: ${nTok} "${P.MAIN_BUNDLE_TOKEN}" urls resolve to the active pin's main bundle ${mb} (present in release/${id}/dist)`);
else { console.log(`FAIL tests/ux/selectors.json main-bundle token: ${nTok} uses; ${mb} ${mbOk ? 'present' : 'MISSING'} in release/${id}/dist`); bad++; }
if (!wrong.length && !hard.length && !miss.length) console.log(`OK   no hardcoded pin under scripts/ tests/ gallery/ infra/ (${files.length} files): runtime buildId only in ${[...expected.keys()].join(', ')} (== active ${bid}); sentinels only in ${[...sentinels.keys()].join(', ')}; no hashed bundle names, no release/wasm64-… paths`);
process.exit(bad ? 1 : 0);
})().catch((e) => { console.log(`FAIL pin constants: ${e.message}`); process.exit(1); });
EOF
}
check_stage1() {
  local bid got; bid="$(lock_buildid)"
  if [ "$(node "$SC/scripts/lib/pins.mjs" built 2>/dev/null)" = no ] && [ ! -e "$W/stage1" ]; then
    echo "ABSENT $W/stage1: no build stores of runtime $bid in this checkout (it serves fetched artifacts; the runtime is checked by pin-verify #2/#3). Bakes and the headless verifiers need it: README \"Re-pin\" step 4"; return 0
  fi
  [ -f "$W/stage1/bin/lean.wasm" ] || { echo "FAIL $W/stage1/bin/lean.wasm missing (copy QED64's pipeline/toolchain/work/build/stage1/bin of the pinned runtime to $W/stage1/bin)"; return 1; }
  got="wasm64-$(sha256sum_ "$W/stage1/bin/lean.wasm" | cut -c1-16)"
  if [ "$got" = "$bid" ]; then echo "OK   $W/stage1 buildId $got == lock"; else echo "FAIL $W/stage1 buildId $got != lock $bid"; return 1; fi
}
check_overlays_cheap() {   # [widgets7|widgets8 …] (default both)
  node - "$SC/out/overlay/snapshots" "$(lock_buildid)" "$@" <<'EOF'
const fs = require('fs'), path = require('path');
const [root, bid, ...only] = process.argv.slice(2);
let bad = 0, seen = 0;
for (const dir of only.length ? only : ['widgets7', 'widgets8']) {
  const d = path.join(root, dir), ix = path.join(d, 'index.json');
  if (!fs.existsSync(ix)) { console.log(`FAIL overlay ${dir}: no index.json`); bad++; continue; }
  seen++;
  const j = JSON.parse(fs.readFileSync(ix, 'utf8'));
  const names = j.snapshots.map((s) => s.name).sort().join(',');
  const errs = [];
  if (j.schema !== 'qed64.snapshot-index/v1') errs.push(`schema ${j.schema}`);
  if (names !== 'init,mathlib') errs.push(`entries ${names}`);
  for (const s of j.snapshots) {
    if (s.runtime !== bid) errs.push(`${s.name}.runtime ${s.runtime}`);
    const f = path.join(d, path.basename(s.url));
    if (!fs.existsSync(f)) { errs.push(`${s.name}: ${path.basename(s.url)} missing`); continue; }
    if (fs.statSync(f).size !== s.transfer) errs.push(`${s.name}: size ${fs.statSync(f).size} != transfer ${s.transfer}`);
  }
  const m = j.snapshots.find((s) => s.name === 'mathlib');
  console.log(`${errs.length ? 'FAIL' : 'OK  '} overlay ${dir}: runtime == ${bid}, {init, mathlib}, sizes == transfer; mathlib imports [${m ? m.imports.join(', ') : '?'}]${errs.length ? ' — ' + errs.join('; ') : ''}`);
  bad += errs.length ? 1 : 0;
}
process.exit(bad ? 1 : 0);
EOF
}
cmd_verify() {
  local deep=0 untouched="" rc=0
  while [ $# -gt 0 ]; do case "$1" in --deep) deep=1; shift ;; --untouched) untouched="${2:?--untouched NAME}"; shift 2 ;; *) die "verify: unknown arg $1" ;; esac; done
  # the ACTIVE pin fully (S0.5 chain of trust: every release file's sha256, git anchors, #10 dist vs git), its links, and
  # every STAGED pin cheaply (pin-switch.mjs check: descriptor == lock, release file set + sizes, main bundle, QED64
  # sources at its commit, its overlays == lock, its runtime's stage1/raw/bakes where built here; a staged pin this
  # checkout never bootstrapped prints NOT MATERIALIZED); `pin check <id> --full` or `pin-qed64.mjs verify --pin <id>`
  # verifies a staged pin fully
  vstep pin-current node "$SC/scripts/pin-switch.mjs" current || rc=1
  vstep pin-verify node "$SC/scripts/pin-qed64.mjs" verify || rc=1
  local act sp; act="$(node "$SC/scripts/lib/pins.mjs" active 2>/dev/null)"
  for sp in $(node "$SC/scripts/lib/pins.mjs" list | cut -d' ' -f1); do
    [ "$sp" = "$act" ] && continue
    vstep "pin-staged-$sp" node "$SC/scripts/pin-switch.mjs" check "$sp" --if-materialized || rc=1
  done
  if [ "$DRY" = 0 ] && grep -q '^DRIFT' "$LOGS/showcase-$LANE_TAG-verify-pin-verify.log" 2>/dev/null; then
    say "NOTE: pin-verify reports DRIFT in a rebuild-only input (served artifacts unaffected; 'native' refuses until re-pinned — README \"Re-pin\", Docker tag drift)"
  fi
  step pin-constants check_pin_constants || rc=1
  step stage1 check_stage1 || rc=1
  step overlays check_overlays_cheap || rc=1
  if [ "$deep" = 1 ]; then
    for n in 7 8; do vstep "pair-overlay-w$n" node "$SC/scripts/pair-check.mjs" "$SC/out/overlay/snapshots/widgets$n" || rc=1; done
  fi
  vstep gallery-fresh node "$SC/scripts/build-gallery.mjs" --check || rc=1
  [ -n "$untouched" ] && { step untouched bash "$SC/scripts/assert-untouched.sh" check "$untouched" || rc=1; }
  [ "$DRY" = 1 ] && return 0
  if [ $rc = 0 ]; then say "VERIFY: all checks OK"; else say "VERIFY: FAILED (see the FAIL lines above)"; fi
  return $rc
}

# new-oleans.txt (paths relative to the clone) -> module list, for the header gate
oleans_to_modules() { sed -nE 's#^(\.lake/packages/[^/]+/)?\.lake/build/lib/lean/(.*)\.olean$#\2#p' "$1" | tr / . | LC_ALL=C sort; }
native_gate() { # native_gate <label> <build step whose new oleans to gate>
  local label="$1" src="$LOGS/$2.new-oleans.txt" mods="$LOGS/$2.new-modules.txt"
  if [ "$DRY" = 0 ]; then
    [ -s "$src" ] || die "no $src (run the build step first)"
    oleans_to_modules "$src" > "$mods"
  fi
  step "gate-$label" ${AWAKE[@]+"${AWAKE[@]}"} bash "$SC/scripts/build-native.sh" header-gate --clone "$W/mathlib4" --core "$K/native/stage1/lib/lean" \
    --modules "$mods" --label "$label" --json "$LOGS/header-gate-$label.json"
}
cmd_native() {
  local what="${1:-all}"
  need QED64_KERNEL_BUILD
  no_bake "native builds never overlap a bake"
  docker_busy && refuse "a Docker container is running (one Docker job at a time): $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
  if [ -f "$LOCK" ] && [ -z "${NATIVE_NOTED:-}" ]; then NATIVE_NOTED=1; say "note: the browser lock is held ($(cat "$LOCK")); Docker may overlap a short browser run (amendment 4), never a bake"; fi
  docker_image_guard
  local b="$SC/scripts/build-native.sh"
  case "$what" in
    identity)      must identity ${AWAKE[@]+"${AWAKE[@]}"} bash "$b" identity ;;
    reuse-pre)     must reuse-pre ${AWAKE[@]+"${AWAKE[@]}"} bash "$b" reuse-gate pre ;;
    delta)         must delta ${AWAKE[@]+"${AWAKE[@]}"} bash "$b" delta ;;
    gate-delta)    native_gate b3-delta b3-delta || exit 1 ;;
    append)        must append ${AWAKE[@]+"${AWAKE[@]}"} bash "$b" append ;;
    reuse-post)    must reuse-post ${AWAKE[@]+"${AWAKE[@]}"} bash "$b" reuse-gate post ;;
    widgets)       must widgets ${AWAKE[@]+"${AWAKE[@]}"} bash "$b" widgets ;;
    gate-widgets)  native_gate b4-widgets b4-widgets || exit 1 ;;
    distlens)      must distlens ${AWAKE[@]+"${AWAKE[@]}"} env T="${T:-4}" bash "$b" distlens ;;
    gate-distlens) native_gate s7-distlens "s7-distlens-T${T:-4}" || exit 1 ;;
    reuse-final)   must reuse-final ${AWAKE[@]+"${AWAKE[@]}"} bash "$b" reuse-gate final ;;
    all) for s in identity reuse-pre delta gate-delta append reuse-post widgets gate-widgets distlens gate-distlens reuse-final; do cmd_native "$s"; done
         [ "$DRY" = 1 ] || must report python3 "$SC/scripts/native-report.py" ;;
    *) die "native: unknown step '$what'" ;;
  esac
}

cmd_stage() {
  local which="${1:-all}" force=""; [ "${2:-}" = --force ] && force=--force
  [ "${1:-}" = --force ] && { which=all; force=--force; }
  no_bake "a bake reads these trees"
  # the trees are shared by every runtime (not per pin): a headless verifier reading them must not see them replaced
  [ "$DRY" = 1 ] || [ ! -e "$W/headless/.lock" ] || refuse "a headless verifier holds $W/headless/.lock ($(cat "$W/headless/.lock/owner" 2>/dev/null)); it reads these trees"
  need QED64_REPO QED64_KERNEL_BUILD
  [ -n "$BASE_SLIM" ] && [ -n "$CORE_SRC" ] && [ -n "$BASE_N" ] || die "the target pin's servedTrees (pins/<id>/pin.json) did not resolve: $(node "$SC/scripts/lib/pins.mjs" field servedTrees.baseSlim 2>&1 >/dev/null)"
  local st="$SC/scripts/stage-trees.mjs" common=(--core-src "$CORE_SRC" --base-n "$BASE_N")
  case "$which" in
    w7)  must stage-w7 ${AWAKE[@]+"${AWAKE[@]}"} node "$st" --base "$BASE_SLIM" --into "$W/tree-slim-w7" --slim --roots "$ROOTS7" "${common[@]}" --report "$LOGS/stage-trees-w7.json" $force ;;
    w8)  must stage-w8 ${AWAKE[@]+"${AWAKE[@]}"} node "$st" --base "$BASE_SLIM" --into "$W/tree-slim-w8" --slim --roots "$ROOTS8" "${common[@]}" --report "$LOGS/stage-trees-w8.json" $force ;;
    fat) local hdrs; hdrs="$(find "$W/widgets-src" -mindepth 3 -maxdepth 3 -name Demo.lean | LC_ALL=C sort | paste -sd, -)"
         must stage-fat ${AWAKE[@]+"${AWAKE[@]}"} node "$st" --base "$BASE_FAT" --into "$W/tree-fat" --fat --roots "$ROOTSFAT" --root-headers "$hdrs" "${common[@]}" --report "$LOGS/stage-trees-fat.json" $force ;;
    all) cmd_stage w7 $force; cmd_stage w8 $force; cmd_stage fat $force ;;
    *) die "stage: unknown tree '$which'" ;;
  esac
}

cmd_bake() {
  local which="${1:-all}"
  case "$which" in w7|w8) ;; all) cmd_bake w7; cmd_bake w8; return ;; *) die "bake: unknown '$which'" ;; esac
  bake_preflight                 # fast refusal before queueing for the lock; re-checked inside it
  # The lock keeps browser lanes out for the whole bake (bake.sh re-checks its own 12 GiB itself).
  locked_run "bake-$which" bake bash "$SC/scripts/bake.sh" "$which" || exit 1
  must "judge-$which" node "$SC/scripts/judge-bake.mjs" "$which"
  must "pair-$which-bakeout" node "$SC/scripts/pair-check.mjs" "$(store "bake-out-$which")" --cmp "widgets=$(store "bake-work-$which")/widgets.snap"
}

cmd_overlay() {
  local which=all pre=0
  for a in "$@"; do case "$a" in w7|w8|all) which="$a" ;; --preflight) pre=1 ;; *) die "overlay: unknown arg $a" ;; esac; done
  if [ "$which" = all ]; then
    local extra=(); [ $pre = 1 ] && extra=(--preflight)
    cmd_overlay w7 "${extra[@]+"${extra[@]}"}"; cmd_overlay w8 "${extra[@]+"${extra[@]}"}"; return
  fi
  local n="${which#w}"
  must "make-$which" node "$SC/scripts/make-overlay.mjs" "$which"
  must "pair-$which-overlay" node "$SC/scripts/pair-check.mjs" "$(store "overlay/widgets$n")" --cmp "mathlib=$(store "bake-work-$which")/widgets.snap"
  if [ $pre = 1 ]; then
    locked_run "preflight-widgets$n" browser bash "$SC/scripts/preflight-overlays.sh" "widgets$n" || exit 1
  fi
}

cmd_headless() {
  local what="${1:-all}"; shift || true
  local H="$SC/scripts/headless"
  case "$what" in
    controls) must controls ${AWAKE[@]+"${AWAKE[@]}"} bash "$H/run-controls.sh" ;;
    stage4)   must "stage4-${1:-all}" ${AWAKE[@]+"${AWAKE[@]}"} bash "$H/run-stage4.sh" "$@" ;;
    e2)       must e2 ${AWAKE[@]+"${AWAKE[@]}"} bash "$H/run-e2.sh" "$@" ;;
    summary)  must summary node "$H/summarize-stage4.mjs" "$@" ;;
    all)      cmd_headless controls; cmd_headless stage4 all; cmd_headless e2; cmd_headless summary ;;
    *) die "headless: unknown '$what'" ;;
  esac
}

# gallery_hash: the gallery content sha256 (scripts/lib/gallery-hash.mjs) — "which gallery" a green result is for.
gallery_hash() { node "$SC/scripts/lib/gallery-hash.mjs" | cut -d' ' -f1; }
UX_RUNS="$SC/out/ux/showcase-ux-runs.jsonl"
# ux_freshness <hash>: is there a VERDICT run (scripts/lib/ux-record.mjs whyNotVerdict: full suite, rc 0, report clean
# with expected + skipped == listed and only C19 skipped, no UX_ORIGIN, the server served exactly the local gallery from
# start to end) for this gallery with the current lock and overlay indexes?
ux_freshness() { node "$SC/scripts/lib/ux-record.mjs" freshness "$1"; }
cmd_gallery() {
  local live=""; [ "${1:-}" = --live ] && live=--live
  if [ "$DRY" = 1 ]; then printf '+ %s\n' "node scripts/build-gallery.mjs --check || node scripts/build-gallery.mjs"
  elif node "$SC/scripts/build-gallery.mjs" --check > "$LOGS/showcase-$LANE_TAG-gallery-fresh.log" 2>&1; then
    say "gallery data up to date ($(tail -1 "$LOGS/showcase-$LANE_TAG-gallery-fresh.log")); not rewritten"
  else
    say "gallery data stale: $(tail -1 "$LOGS/showcase-$LANE_TAG-gallery-fresh.log")"
    must build node "$SC/scripts/build-gallery.mjs"
  fi
  local h0 h1; h0="$(gallery_hash)"
  must check node "$SC/scripts/check-gallery.mjs" $live
  [ "$DRY" = 1 ] && return 0
  h1="$(gallery_hash)"
  [ "$h0" = "$h1" ] || die "gallery/ changed while the gate ran ($h0 -> $h1): the result describes neither; re-run once edits settle"
  say "gallery gate GREEN on gallery content sha256 $h1 ($(date '+%F %T %Z'))"
  say "$(ux_freshness "$h1")"
}

cmd_serve() {
  if port_answers; then
    local why; why="$(server_is_showcase)" || refuse "port :$PORT is held by a server that is not this showcase's serve.mjs ($why); pick another PORT"
    local who="unknown (no owner file: started directly or by another lane)"; [ -f "$(ownerfile)" ] && who="$(cat "$(ownerfile)")"
    say "already serving the showcase on :$PORT — owner: $who"; return 0
  fi
  step serve-start env PORT="$PORT" "$SC/scripts/serve-start.sh" || exit 1
  [ "$DRY" = 1 ] || printf 'lane=%s at=%s\n' "$LANE" "$(date -u +%FT%TZ)" > "$(ownerfile)"
  [ "$DRY" = 1 ] || say "open http://localhost:$PORT/showcase/  (owner lane=$LANE recorded in $(ownerfile))"
}
cmd_stop() {
  local force=0; [ "${1:-}" = --force ] && force=1
  local of; of="$(ownerfile)"
  if [ ! -f "$of" ]; then
    [ $force = 1 ] || refuse "no owner file $of: the server on :$PORT was not started by 'showcase.sh serve' (never stop another lane's server; --force overrides)"
  elif ! grep -q "^lane=$LANE " "$of"; then
    [ $force = 1 ] || refuse "server on :$PORT belongs to '$(cat "$of")', not lane=$LANE (--force overrides)"
  fi
  step serve-stop env PORT="$PORT" "$SC/scripts/serve-stop.sh" || exit 1
  [ "$DRY" = 1 ] || rm -f "$of"
}

# The UX suite is owned by the UX lane. Its documented entry point is `npm run test:ux`
# (= scripts/with-browser-lock.sh ux-suite npx playwright test -c tests/ux/playwright.config.mjs); `ux` runs
# the same command through locked_run (same lock script, cooldown and caffeinate -i) plus our preflight.
# The suite's global setup needs the host browser lock held and :5190 answering /showcase/pin.json; it starts
# serve.mjs itself when nothing is up and stops it afterwards only then. UX_CMD is an argument array
# ($SC contains a space, "lean questions").
UX_CMD=()
ux_runner() {
  if [ -x "$SC/tests/ux/run-ux.sh" ]; then UX_CMD=(bash "$SC/tests/ux/run-ux.sh")
  elif [ -f "$SC/tests/ux/playwright.config.mjs" ]; then UX_CMD=(npx --no-install playwright test -c "$SC/tests/ux/playwright.config.mjs")
  else UX_CMD=(); return 1; fi
}
cmd_ux() {
  if ! ux_runner; then
    [ "$DRY" = 1 ] || die "no UX suite entry point found (tests/ux/playwright.config.mjs); the UX lane owns tests/ux"
    say "dry-run WARN: no UX suite entry point (tests/ux/playwright.config.mjs)"; UX_CMD=("<ux-suite>")
  fi
  local origin="${UX_ORIGIN:-http://localhost:5190}" started=0
  [ "$PORT" = 5190 ] || [ -n "${UX_ORIGIN:-}" ] || say "note: the UX suite always uses :5190 (UX_ORIGIN overrides); PORT=$PORT is ignored"
  # A run name is used once: the suite writes out/ux/<run>/ in place, so reusing a name silently overwrote an earlier run's
  # evidence (final audit, 2026-10-03: a second 'audit-full1' overwrote a cited 2026-10-02 VERDICT run's files). Refused
  # before anything starts (no server, no lock) when out/ux/<run>/ exists or the run log already records the name.
  local run="${UX_RUN:-showcase-${LANE_TAG}-$(date -u +%Y%m%dT%H%M%SZ)}"
  if [ -e "$SC/out/ux/$run" ]; then guard_fail "UX_RUN=$run: out/ux/$run/ already exists (an earlier run's evidence); pick an unused run name"
  elif [ -f "$UX_RUNS" ] && node -e 'const fs=require("fs");const [f,r]=process.argv.slice(1);process.exit(fs.readFileSync(f,"utf8").split("\n").some((l)=>{try{return JSON.parse(l).run===r}catch{return false}})?0:1)' "$UX_RUNS" "$run"; then
    guard_fail "UX_RUN=$run: out/ux/showcase-ux-runs.jsonl already records a run named $run; pick an unused run name"
  fi
  if [ -n "${UX_ORIGIN:-}" ]; then
    say "UX_ORIGIN=$UX_ORIGIN: the run is recorded with its origin, but it is never a UX verdict for the local gallery"
  elif port_answers 5190; then
    local why; why="$(server_is_showcase 5190)" || guard_fail "port :5190 is held by a server that is not this showcase's serve.mjs for the local gallery ($why); the suite would test the wrong app"
    [ -z "${why:-}" ] && say "server on :5190 is the showcase for the local gallery (pin.json buildId == lock, COEP/CORP, served gallery sha256 == local); the suite uses it"
  elif [ "$DRY" = 1 ]; then say "dry-run: nothing on :5190; would start serve.mjs (GALLERY_DIR unset) for the run and stop it afterwards"
  else
    # start it here (not in the suite's global setup) so the served gallery can be hashed before AND after the run
    env -u GALLERY_DIR PORT=5190 "$SC/scripts/serve-start.sh" >/dev/null || die "could not start serve.mjs on :5190"
    started=1; say "started serve.mjs on :5190 for this run (stopped afterwards)"
  fi
  docker_busy && say "note: a Docker container is running (allowed for short browser runs, amendment 4)"
  if [ "$DRY" = 1 ]; then (cd "$SC" && UX_RUN="$run" locked_run ux browser "${UX_CMD[@]}" "$@"); return 0; fi
  local g0 s0 in0 t0 rc g1 s1 in1 listed sp0 sp1
  g0="$(gallery_hash)"; in0="$(node "$SC/scripts/lib/ux-record.mjs" inputs)"; t0="$(date -u +%FT%TZ)"
  s0="$(node "$SC/scripts/lib/ux-record.mjs" served "$origin" 2>/dev/null || echo none)"
  sp0="$(node "$SC/scripts/lib/ux-record.mjs" servedpin "$origin" 2>/dev/null || echo none)"
  listed="$(cd "$SC" && UX_RUN="$run" npx --no-install playwright test -c "$SC/tests/ux/playwright.config.mjs" --list "$@" 2>/dev/null | sed -nE 's/^Total: ([0-9]+) tests? in .*/\1/p' | tail -1)"
  say "UX run $run on pin $(node "$SC/scripts/lib/pins.mjs" active) and local gallery $g0 (served by $origin: gallery $s0, pin $sp0); $listed tests listed"
  [ -n "${UX_ORIGIN:-}" ] || [ "$s0" = "$g0" ] || say "WARNING: $origin serves gallery $s0, not the local $g0: this run cannot be a verdict"
  (cd "$SC" && export UX_RUN="$run" && locked_run ux browser "${UX_CMD[@]}" "$@"); rc=$?
  g1="$(gallery_hash)"; in1="$(node "$SC/scripts/lib/ux-record.mjs" inputs)"
  s1="$(node "$SC/scripts/lib/ux-record.mjs" served "$origin" 2>/dev/null || echo none)"
  sp1="$(node "$SC/scripts/lib/ux-record.mjs" servedpin "$origin" 2>/dev/null || echo none)"
  if [ "$started" = 1 ]; then env PORT=5190 "$SC/scripts/serve-stop.sh" >/dev/null 2>&1 || true; say "stopped the serve.mjs this run started"; fi
  # Record which gallery, pin and overlays this run is for, and whether it is a verdict (ux-record.mjs whyNotVerdict).
  # README "Results", `showcase.sh gallery` and deploy-manifest G2 read this file.
  mkdir -p "$(dirname "$UX_RUNS")"
  local rec
  rec="$(node -e '
    const [start, end, lane, rc, run, origin, uxo, g0, g1, s0, s1, in0, in1, listed, sp0, sp1, report, ...args] = process.argv.slice(1);
    const a = JSON.parse(in0), b = JSON.parse(in1);
    console.log(JSON.stringify({ start, end, lane, rc: Number(rc), args, run, origin, uxOrigin: uxo === "1", galleryStart: g0, galleryEnd: g1,
      servedStart: s0 === "none" ? null : s0, servedEnd: s1 === "none" ? null : s1, lockSha256: a.lockSha256, lockSha256End: b.lockSha256,
      overlays: a.overlays, overlaysEnd: b.overlays, pin: a.pin, pinEnd: b.pin, servedPinStart: sp0 === "none" ? null : sp0, servedPinEnd: sp1 === "none" ? null : sp1,
      listed: listed ? Number(listed) : null, report: JSON.parse(report), ...(process.env.UX_HEADED_ALL === "1" ? { headed: true } : {}), ...(process.env.UX_CHANNEL ? { channel: process.env.UX_CHANNEL } : {}) }));' \
    "$t0" "$(date -u +%FT%TZ)" "$LANE" "$rc" "$run" "$origin" "$([ -n "${UX_ORIGIN:-}" ] && echo 1 || echo 0)" "$g0" "$g1" "$s0" "$s1" "$in0" "$in1" "$listed" "$sp0" "$sp1" \
    "$(node "$SC/scripts/lib/ux-record.mjs" report "$SC/out/ux/$run")" "$@")"
  printf '%s\n' "$rec" >> "$UX_RUNS"
  [ "$g0" = "$g1" ] || say "WARNING: gallery/ changed during the UX run ($g0 -> $g1): this run is not a verdict on either"
  say "UX rc=$rc on gallery $g1 (recorded in out/ux/showcase-ux-runs.jsonl): $(node "$SC/scripts/lib/ux-record.mjs" verdict "$rec")"
  return "$rc"
}

# locked always runs the browser preflight inside the lock: the lock exists to serialise browser boots, and
# binding rule 3 requires the memory / stray-browser / no-bake checks before every boot.
cmd_locked() {
  local what="${1:-}"; shift || true
  [ -n "$what" ] && [ "${1:-}" = -- ] || die "usage: locked <what> -- <cmd…>"
  shift; [ $# -gt 0 ] || die "locked: no command"
  locked_run "$what" browser "$@"
}

# headless_green: "GREEN: <why>" when out/headless/summary.json is for the lock's buildId and its gate has
# stage4Green and E2Green; else "RUN: <why>".
headless_green() {
  # shellcheck disable=SC2016  # JS template literals, not shell expansions
  SHOWCASE_W="$W" node -e '
    const fs = require("fs"), [f, bid] = process.argv.slice(1), W = process.env.SHOWCASE_W;
    if (!fs.existsSync(f)) { console.log("RUN: no out/headless/summary.json"); process.exit(0); }
    const s = JSON.parse(fs.readFileSync(f, "utf8")), g = s.gate || {};
    if (s.runtime !== bid) console.log(`RUN: summary.json runtime ${s.runtime} != lock ${bid}`);
    else if (!(g.stage4Green === true && g.E2Green === true)) console.log(`RUN: summary.json gate stage4Green=${g.stage4Green} E2Green=${g.E2Green}`);
    else {
      // the summary must describe the bakes that exist NOW (a bake redone by an earlier, separate invocation would
      // otherwise skip S4 on stale results): every package e1.snapSha256 == sha256 of $W/bake-work-<b>/widgets.snap
      const crypto = require("crypto"), stale = [];
      for (const [b, v] of Object.entries(s.bakes || {})) {
        const f = `${W}/bake-work-${b}/widgets.snap`;
        const want = new Set((v.packages || []).map((p) => p.e1 && p.e1.snapSha256).filter(Boolean));
        if (!fs.existsSync(f)) { stale.push(`${b}: ${f} missing`); continue; }
        const h = crypto.createHash("sha256"); const fd = fs.openSync(f, "r"); const buf = Buffer.allocUnsafe(1 << 23);
        for (let n; (n = fs.readSync(fd, buf, 0, buf.length, null)) > 0;) h.update(buf.subarray(0, n));
        fs.closeSync(fd); const got = h.digest("hex");
        if (want.size !== 1 || !want.has(got)) stale.push(`${b}: summary snapSha256 ${[...want].map((x) => String(x).slice(0, 12)).join("/") || "none"} != ${got.slice(0, 12)} (widgets.snap now)`);
      }
      if (!Object.keys(s.bakes || {}).length) stale.push("summary.json lists no bakes");
      console.log(stale.length ? `RUN: summary.json does not describe the current bakes (${stale.join("; ")})`
        : `GREEN: out/headless/summary.json (${s.generatedAt}, ${bid}) has stage4Green and E2Green (E2 ${g.E2}) and its snapSha256 == the current ${Object.keys(s.bakes).join("/")} widgets.snap`);
    }
  ' "$SC/out/headless/summary.json" "$(lock_buildid)"
}
cmd_all() {
  local rebuild=0; [ "${1:-}" = --rebuild ] && rebuild=1
  local redone=0 verify_red=0 fails=()
  # verify first; a red verify does not stop the build stages (they may repair what it flags: a missing overlay, a stale
  # stage1), but verify then runs AGAIN after them and `all` exits 1 if it is still red (docs audit r3: `all` used to
  # exit with ux's rc even after verify had failed).
  cmd_verify || { verify_red=1; say "verify reported failures (continuing: the build stages may repair them; verify re-runs after them)"; }
  if [ $rebuild = 1 ] || [ ! -f "$SC/out/native-build.json" ]; then cmd_native all; else say "SKIP native: out/native-build.json exists (--rebuild to redo)"; fi
  if [ $rebuild = 1 ] || [ ! -f "$W/tree-slim-w8.EXPECTED-N" ] || [ ! -f "$W/tree-slim-w7.EXPECTED-N" ] || [ ! -f "$W/tree-fat.EXPECTED-N" ]; then cmd_stage all --force; else say "SKIP stage: tree-slim-w7/w8 and tree-fat exist (--rebuild to redo)"; fi
  for t in w7 w8; do
    if [ $rebuild = 0 ] && node "$SC/scripts/judge-bake.mjs" "$t" > "$LOGS/showcase-$LANE_TAG-all-judge-$t.log" 2>&1; then say "SKIP bake $t: judge-bake $t is GREEN on the existing bake ($(tail -1 "$LOGS/showcase-$LANE_TAG-all-judge-$t.log"))"
    else cmd_bake "$t"; redone=1; fi
    # an overlay is skipped only when its cheap check passes (index schema, {init, mathlib}, runtime == lock, every
    # snapz present with size == transfer), not merely because index.json exists
    if [ $rebuild = 0 ] && check_overlays_cheap "widgets${t#w}" > "$LOGS/showcase-$LANE_TAG-all-overlay-$t.log" 2>&1; then say "SKIP overlay $t: out/overlay/snapshots/widgets${t#w} passes the overlay check ($(head -1 "$LOGS/showcase-$LANE_TAG-all-overlay-$t.log" | cut -c1-90)…)"
    else [ $rebuild = 0 ] && say "overlay $t: $(grep -m1 FAIL "$LOGS/showcase-$LANE_TAG-all-overlay-$t.log" | cut -c1-160) — rebuilding it"; cmd_overlay "$t"; redone=1; fi
  done
  local hs; hs="$(headless_green)"
  if [ $rebuild = 0 ] && [ $redone = 0 ] && [ "${hs%%:*}" = GREEN ]; then say "SKIP headless: ${hs#*: } (--rebuild to redo; ~20 min, 12 GB+ RSS peaks)"
  else [ $redone = 1 ] && say "headless: a bake/overlay was redone in this run, so S4 re-runs"; [ $rebuild = 0 ] && [ $redone = 0 ] && say "headless: ${hs#*: }"; cmd_headless all; fi
  if [ $verify_red = 1 ]; then
    if cmd_verify; then say "verify is green after the build stages"; else fails+=("verify still red after the build stages"); fi
  fi
  cmd_gallery            # exits 1 itself on a red gate
  local urc=0; cmd_ux || urc=$?
  [ "$urc" = 0 ] || fails+=("ux rc=$urc")
  [ "$DRY" = 1 ] && return 0
  if [ ${#fails[@]} -gt 0 ]; then say "ALL: FAILED (${fails[*]})"; exit 1; fi
  say "ALL: OK"
}

# SHOWCASE_PIN=<id>: the build and verification steps act on that pin's own stores (scripts/lib/pins.mjs targetPinId),
# without switching. The steps that test or serve the ACTIVE pin on :5190 refuse a different target.
if [ -n "${SHOWCASE_PIN:-}" ]; then
  TGT="$(node "$SC/scripts/lib/pins.mjs" target 2>&1)" || { say "SHOWCASE_PIN=$SHOWCASE_PIN: $TGT"; exit 2; }
  ACT="$(node "$SC/scripts/lib/pins.mjs" active 2>/dev/null || echo none)"
  if [ "$TGT" != "$ACT" ]; then
    case "$SUB" in
      ux|gallery|all) refuse "$SUB tests the active pin ($ACT); unset SHOWCASE_PIN (=$TGT), or switch with 'pin use $TGT'" ;;
      serve|stop) [ "$PORT" != 5190 ] || refuse "SHOWCASE_PIN=$TGT is a staged pin: serve it on another PORT (5190 serves the active pin $ACT)" ;;
    esac
    case "$SUB" in stage|bake|overlay|headless) say "target: staged pin $TGT (runtime $(node "$SC/scripts/lib/pins.mjs" target-bid)), its own stores; the active pin $ACT and its links are not touched" ;; esac
  fi
fi

case "$SUB" in
  pin) cmd_pin "$@" ;;
  bootstrap) cmd_bootstrap "$@" ;;
  verify) cmd_verify "$@" ;;
  native) cmd_native "$@" ;;
  stage) cmd_stage "$@" ;;
  bake) cmd_bake "$@" ;;
  overlay) cmd_overlay "$@" ;;
  headless) cmd_headless "$@" ;;
  gallery) cmd_gallery "$@" ;;
  serve) cmd_serve "$@" ;;
  stop) cmd_stop "$@" ;;
  ux) cmd_ux "$@" ;;
  locked) cmd_locked "$@" ;;
  _inlock) cmd_inlock "$@" ;;
  all) cmd_all "$@" ;;
  -h|--help|help) usage 0 ;;
  "") usage 2 ;;
  *) say "unknown subcommand '$SUB'"; usage ;;
esac
