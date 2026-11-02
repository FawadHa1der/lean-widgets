#!/usr/bin/env bash
# lockstray.sh — the browser check of the lock's cooldown goes by executable, not by command text (procs_by_exe in
# scripts/lib/platform.sh, procsByExe in scripts/lib/platform.mjs). A shell whose command merely names both browsers stays
# alive throughout: it must not be listed and must not hold the cooldown (the control: pgrep -f does list it, which held
# the host lock's cooldown with no browser up on 2026-11-02). Fake browsers, copies of sleep at the two executable paths,
# must be listed and must make the cooldown refuse (exit 76); once they are gone it passes again. Where the list comes from
# ps (not Linux), a ps that fails must read as "cannot tell": the helper exits 2 and the cooldown refuses. No script may go
# back to pgrep or pkill for a browser name.
# Runs against a scratch lock directory (BROWSER_LOCK_DIR; never the real host lock); needs no browser. Exit 3 if a browser
# is already up, since the cooldown cases need a quiet host. For about 10 s the fakes look real to every other check on
# the host: a lane's cooldown waits for them, and the guards in showcase.sh and bake.sh refuse. So on a shared host run it
# under the real lock (the inner cases still use the scratch directory), or in a container:
#   scripts/with-browser-lock.sh lockstray bash tests/ux/bringup/lockstray.sh
#   docker run --rm --pull=never -v "$PWD/scripts:/sc/scripts:ro" -v "$PWD/tests/ux/bringup:/sc/tests/ux/bringup:ro" \
#     node:24-bookworm bash /sc/tests/ux/bringup/lockstray.sh
set -u
SC="$(cd "$(dirname "$0")/../../.." && pwd)"
WRAP="${LOCK_SCRIPT:-$SC/scripts/with-browser-lock.sh}"
. "$SC/scripts/lib/platform.sh"
unset BROWSER_LOCK_FILE   # it would override BROWSER_LOCK_DIR
RE='chrome-headless-shell|ms-playwright/firefox-'
T="$(mktemp -d)"; mention=""; fake=""; fails=0; nonode=""
stop() { [ -n "$1" ] || return 0; pkill -P "$1" 2>/dev/null; kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }
trap 'stop "$mention"; stop "$fake"; rm -rf "$T"' EXIT
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails + 1)); fi; }
check_node() {
  if ! command -v node >/dev/null; then echo "skip $1: no node"; nonode="; procsByExe not checked: no node"; return; fi
  check "$1" "$(MJS="$SC/scripts/lib/platform.mjs" RE="$RE" node --input-type=module \
    -e "const {procsByExe}=await import(process.env.MJS);console.log(procsByExe(new RegExp(process.env.RE)).join('\n'))")" "$2"; }
cooldown() { BROWSER_LOCK_DIR="$T/lock" MIN_FREE_GB=0 COOLDOWN_WAIT_S=3 NO_CAFFEINATE=1 "$WRAP" lockstray sh -c "echo ran > '$T/ran'" >"$T/lock.log" 2>&1; echo $?; }
ran() { if [ -e "$T/ran" ]; then rm -f "$T/ran"; echo yes; else echo no; fi; }

if up="$(procs_by_exe "$RE")"; then echo "a browser is running; rerun on a quiet host:"; echo "$up"; exit 3; fi

# a later command keeps bash alive, with the names in its argv
bash -c "sleep 120; : chrome-headless-shell ms-playwright/firefox-1/firefox" 2>/dev/null & mention=$!
sleep 0.3
if command -v pgrep >/dev/null; then
  check "control: pgrep -f lists the shell that only mentions them" "$(pgrep -f "$RE" | grep -cx "$mention")" 1
fi
check "procs_by_exe leaves that shell out" "$(procs_by_exe "$RE")" ""
check_node "procsByExe leaves it out" ""
check "the cooldown passes with it alive" "$(cooldown)" 0
check "and the command ran" "$(ran)" yes

mkdir -p "$T/ms-playwright/firefox-1/firefox"
for exe in "$T/chrome-headless-shell" "$T/ms-playwright/firefox-1/firefox/firefox"; do
  cp "$(command -v sleep)" "$exe"
  [ "$PLATFORM" != darwin ] || codesign -fs - "$exe" 2>/dev/null   # a plain copy of a signed binary is killed at start
  "$exe" 30 & fake=$!
  sleep 0.3
  check "procs_by_exe lists ${exe#"$T"/}" "$(procs_by_exe "$RE")" "$fake $exe"
  check_node "procsByExe lists it" "$fake $exe"
  check "the cooldown refuses" "$(cooldown)" 76
  check "and the command did not run" "$(ran)" no
  stop "$fake"; fake=""
done
check "the cooldown passes once they are gone" "$(cooldown)" 0
check "and the command ran" "$(ran)" yes

if [ "$PLATFORM" != linux ]; then
  mkdir -p "$T/failps"; printf '#!/bin/sh\nexit 7\n' > "$T/failps/ps"; chmod +x "$T/failps/ps"
  check "a ps that fails: procs_by_exe exits 2" "$(PATH="$T/failps:$PATH" procs_by_exe "$RE" >/dev/null; echo $?)" 2
  check "and the cooldown refuses" "$(PATH="$T/failps:$PATH" cooldown)" 76
  check "and the command did not run" "$(ran)" no
  check "and says why" "$(grep -c 'strays: ps failed' "$T/lock.log")" 1
fi

# no browser check back on command text (comments may name the old form)
stale="$(grep -nE '(pgrep|pkill).*(chrome|firefox|Chrome for Testing)' -r "$SC/scripts" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//|\*)')"
for f in tests/ux/lib/qed64.mjs tests/experiments/lib.mjs; do
  [ ! -e "$SC/$f" ] || stale="$stale$(grep -nE '(pgrep|pkill).*(chrome|firefox)' "$SC/$f")"
done
check "no script finds a browser with pgrep or pkill" "$stale" ""

[ "$fails" = 0 ] && echo "lockstray: PASS ($PLATFORM$nonode)" || { echo "lockstray: $fails FAILED ($PLATFORM)"; exit 1; }
