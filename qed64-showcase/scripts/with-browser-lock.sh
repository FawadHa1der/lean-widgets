#!/usr/bin/env bash
# with-browser-lock.sh <lane> <cmd...> — run <cmd> holding the HOST-WIDE browser lock (ONE Playwright/Chrome at a time
# across every lane, session and checkout on this machine).
#
#   with-browser-lock.sh --print-lock      print the lock file path and exit
#
# Where the lock lives: it is host-global, not inside any repository, so every checkout (and every copy of this
# script that resolves the same directory) shares it:
#   BROWSER_LOCK_DIR   directory of the lock (default: ~/.cache/host-browser-lock); the lock file is <dir>/browser.lock
#   BROWSER_LOCK_FILE  the lock file itself (tests only; overrides BROWSER_LOCK_DIR)
# The command runs with HOST_BROWSER_LOCK_FILE=<lock file> in its environment (consumers such as the UX suite check
# that it is held: scripts/lib/browser-lock.mjs).
#
# The lock is created atomically with `set -o noclobber` and holds "<lane> <pid> <iso-time>". If it exists and its owner
# pid is alive we poll (every 2-5 s, up to LOCK_WAIT_S, default 3600 s); a lock whose owner is dead is stale and is
# replaced — under a takeover mutex (mkdir <lock>.takeover) after re-checking its contents, so two waiters can never
# both get in. The lock is removed on exit, including failure and SIGINT/SIGTERM.
#
# FAIRNESS (FIFO): every waiter first files a ticket <lock>.queue/<arrival-time>-<pid> (content: pid + process start
# time, so a reused pid is never mistaken for a waiter). A free lock is taken only by the waiter holding the OLDEST
# live ticket; tickets of dead processes are ignored and removed. So waiters are served in arrival order whatever
# path they invoked the script by. FAIR=0 disables the queue (take the lock as soon as it is free).
#
# Before running <cmd> it also requires >= MIN_FREE_GB (default 6) free+inactive+speculative memory (vm_stat) and no
# chrome-headless-shell, waiting up to COOLDOWN_WAIT_S (default 3600) for both. Exit codes: 75 lock wait timed out,
# 76 cooldown refused, 2 usage; otherwise the command's own exit code.
set -u
DEFAULT_DIR="$HOME/.cache/host-browser-lock"
LOCK_DIR="${BROWSER_LOCK_DIR:-$DEFAULT_DIR}"
LOCK="${BROWSER_LOCK_FILE:-$LOCK_DIR/browser.lock}"
if [ "${1:-}" = --print-lock ]; then echo "$LOCK"; exit 0; fi
TAKEOVER="$LOCK.takeover"   # mkdir mutex serializing stale-lock takeovers
QUEUE="$LOCK.queue"         # FIFO tickets
LANE="${1:?usage: with-browser-lock.sh <lane> <cmd...> | --print-lock}"; shift
[ $# -gt 0 ] || { echo "usage: with-browser-lock.sh <lane> <cmd...>" >&2; exit 2; }
WAIT_S="${LOCK_WAIT_S:-3600}"
MIN_FREE_GB="${MIN_FREE_GB:-6}"
mkdir -p "$(dirname "$LOCK")" "$QUEUE" || { echo "browser-lock: cannot create $(dirname "$LOCK")" >&2; exit 2; }

reclaimable_gb() {
  vm_stat | awk '/page size of/ {ps=$8} /Pages free/ {f=$3} /Pages inactive/ {i=$3} /Pages speculative/ {s=$3}
    END {gsub(/\./,"",f); gsub(/\./,"",i); gsub(/\./,"",s); printf "%.1f", (f+i+s)*ps/1073741824}'
}
pstart() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/  */ /g; s/^ //; s/ $//'; }

# ---- FIFO ticket -----------------------------------------------------------------------------------------------
TICKET=""
if [ "${FAIR:-1}" != 0 ]; then
  TICKET="$QUEUE/$(perl -MTime::HiRes=time -e 'printf "%017.6f", time')-$$"
  printf '%s\t%s\t%s\n' "$$" "$(pstart $$)" "$LANE" > "$TICKET"
fi
drop_ticket() { [ -n "$TICKET" ] && rm -f "$TICKET"; TICKET=""; }
# head_ticket: the oldest ticket whose process is still the one that filed it (pid alive AND same start time);
# dead tickets are removed on the way.
head_ticket() {
  local t pid st
  for t in $(ls "$QUEUE" 2>/dev/null | LC_ALL=C sort); do
    IFS=$'\t' read -r pid st _ < "$QUEUE/$t" 2>/dev/null || { rm -f "$QUEUE/$t"; continue; }
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$(pstart "$pid")" = "$st" ]; then echo "$t"; return 0; fi
    rm -f "$QUEUE/$t"
  done
  return 1
}

t0=$(date +%s)
lastmsg=0
trap 'drop_ticket; exit 130' INT TERM
trap 'drop_ticket' EXIT
while :; do
  if [ ! -e "$LOCK" ] && [ -n "$TICKET" ]; then
    h="$(head_ticket)"
    if [ -n "$h" ] && [ "$QUEUE/$h" != "$TICKET" ]; then
      if [ $(( $(date +%s) - lastmsg )) -ge 60 ]; then
        echo "browser-lock: lock free, but deferring to an earlier waiter ($(cut -f3 "$QUEUE/$h" 2>/dev/null) pid $(cut -f1 "$QUEUE/$h" 2>/dev/null))"; lastmsg=$(date +%s); fi
      if [ $(( $(date +%s) - t0 )) -ge "$WAIT_S" ]; then echo "browser-lock: gave up after ${WAIT_S}s (deferring to earlier waiters)" >&2; exit 75; fi
      sleep 1; continue
    fi
  fi
  if ( set -o noclobber; echo "$LANE $$ $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOCK" ) 2>/dev/null; then break; fi
  owner="$(cat "$LOCK" 2>/dev/null || true)"; opid="$(echo "$owner" | awk '{print $2}')"
  if [ -n "$opid" ] && ! kill -0 "$opid" 2>/dev/null; then
    # Stale-lock takeover, serialized: only the holder of the takeover mutex (an atomic mkdir) may delete a lock it
    # does not own, and only after re-reading it under the mutex and finding the SAME dead owner line. A mutex left
    # by a takeover that died is itself reclaimed once its recorded pid is gone.
    if mkdir "$TAKEOVER" 2>/dev/null; then
      echo $$ > "$TAKEOVER/pid"
      now="$(cat "$LOCK" 2>/dev/null || true)"
      if [ -n "$now" ] && [ "$now" = "$owner" ]; then
        rm -f "$LOCK"; echo "browser-lock: stale lock ($owner): owner pid $opid is gone; removed under the takeover mutex"
      else echo "browser-lock: lock changed while taking over (now: ${now:-none}); retrying"; fi
      rm -rf "$TAKEOVER"; continue
    fi
    tpid="$(cat "$TAKEOVER/pid" 2>/dev/null || true)"
    if [ -n "$tpid" ] && ! kill -0 "$tpid" 2>/dev/null; then
      if mv "$TAKEOVER" "$TAKEOVER.dead.$$" 2>/dev/null; then
        if [ "$(cat "$TAKEOVER.dead.$$/pid" 2>/dev/null)" = "$tpid" ]; then rm -rf "$TAKEOVER.dead.$$"; echo "browser-lock: reclaimed a takeover mutex left by dead pid $tpid"
        else mv -n "$TAKEOVER.dead.$$" "$TAKEOVER" 2>/dev/null || rm -rf "$TAKEOVER.dead.$$"; fi # moved a live one: put it back
      fi
    fi
    sleep 1; continue
  fi
  if [ $(( $(date +%s) - t0 )) -ge "$WAIT_S" ]; then echo "browser-lock: gave up after ${WAIT_S}s; held by: $owner" >&2; exit 75; fi
  if [ $(( $(date +%s) - lastmsg )) -ge 60 ]; then echo "browser-lock: held by '$owner'; waiting"; lastmsg=$(date +%s); fi
  sleep 2
done
drop_ticket
release() { if [ "$(awk '{print $2}' "$LOCK" 2>/dev/null)" = "$$" ]; then rm -f "$LOCK"; echo "browser-lock: released ($LANE)"; fi; }
trap release EXIT
trap 'exit 130' INT TERM
echo "browser-lock: acquired by $LANE pid $$ ($LOCK)"

# Cooldown: wait (default up to COOLDOWN_WAIT_S=3600 s) for memory and for any other headless Chrome on the host
# (other sessions share this machine), logging the reason once a minute; exit 76 only after the full wait.
COOLDOWN_WAIT_S="${COOLDOWN_WAIT_S:-3600}"; c0=$(date +%s); last=0
# Test-only escape hatch: honoured ONLY when the lock is not the default host lock, so real runs always get the cooldown.
if [ "$LOCK" != "$DEFAULT_DIR/browser.lock" ] && [ "${SKIP_COOLDOWN_FOR_TEST:-0}" = 1 ]; then COOLDOWN_WAIT_S=-1; fi
while :; do
  strays="$(pgrep -fl chrome-headless-shell || true)"; free="$(reclaimable_gb)"
  if [ "$COOLDOWN_WAIT_S" = -1 ] || { [ -z "$strays" ] && awk -v f="$free" -v m="$MIN_FREE_GB" 'BEGIN{exit !(f>=m)}'; }; then
    echo "browser-lock: cooldown ok: ${free} GiB reclaimable, no chrome-headless-shell"; break
  fi
  el=$(( $(date +%s) - c0 ))
  [ "$el" -ge "$COOLDOWN_WAIT_S" ] && { echo "browser-lock: cooldown refused after ${el}s: ${free} GiB reclaimable; strays: ${strays:-none}" >&2; exit 76; }
  if [ $(( el - last )) -ge 60 ] || [ "$last" = 0 ]; then last=$el; [ "$last" = 0 ] && last=1
    echo "browser-lock: cooldown waiting (${el}s): ${free} GiB reclaimable (need ${MIN_FREE_GB}); other headless Chrome: $(echo "$strays" | grep -vc '^$')"; fi
  sleep 5
done

export HOST_BROWSER_LOCK_FILE="$LOCK"
# Keep the host awake while the browser runs: a headless Chrome holds no idle-sleep assertion, and an idle Mac once
# slept 988 s in the middle of a UX run, freezing the browser and the test clock. caffeinate -i only holds a
# process-scoped PreventUserIdleSystemSleep assertion for the command's lifetime; it changes no system setting.
if command -v caffeinate >/dev/null 2>&1 && [ "${NO_CAFFEINATE:-0}" != 1 ]; then
  echo "browser-lock: running under caffeinate -i (no idle sleep while the browser runs)"
  caffeinate -i "$@"
else
  "$@"
fi
rc=$?
echo "browser-lock: command exited rc=$rc"
exit $rc
