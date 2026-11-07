#!/usr/bin/env bash
# lockfifo.sh — FIFO test for scripts/with-browser-lock.sh, invoked through SEVERAL PATHS that must share one lock:
# the script itself (absolute), the script through a relative path, and any compatibility stub that execs it
# (STUB=<path>, e.g. the stub left at a checkout's old location; default: a scratch stub made here).
# A holder takes the lock for HOLD0_S seconds; then N waiters arrive GAP_S apart, cycling through the paths; each holds
# the lock for HOLD_S seconds and journals "start/end <name> <time>". Passes iff all ran, no two critical sections
# overlap, the start order equals the arrival order, the three fault cases below pass (DROP_TICKET, PS_FAIL,
# STALE_TICKET; while any is on, the holder keeps the lock until DROP_TICKET is checked, the stale ticket is planted and
# w1 is checked and stopped), the takeover cases below pass, and no lock or ticket is left. Runs in a scratch directory
# (BROWSER_LOCK_DIR=<tmp>/lockdir; the takeover cases use <tmp>/tko/<case>/browser.lock, through BROWSER_LOCK_FILE or,
# for handoff and release, the script's perl programs run by themselves), never the real host lock; needs no browser.
# TAKEOVER_CASES (default race,lane,empty,mutex,handoff,signal,release,done; 0 or empty disables) run after the FIFO part:
#   race   a takeover in progress (the test holds the flock and the takeover directory, whose pid file names a dead pid)
#          must be left alone: for 3 s the stale lock and that directory stay and no waiter runs; once it ends, the
#          waiter takes the stale lock over. Then a directory left by a killed takeover (marker 'flk') is reclaimed,
#          and a marked one whose flock the test holds (a live takeover) is left alone (exit 75).
#   lane   a lane with a space is refused (exit 2); an older copy's lock line with a spaced lane and a live owner is
#          left alone (the waiter gives up: exit 75).
#   empty  an empty lock is left alone while fresh (exit 75), and taken over once 2 min old; so is a NUL-filled one.
#   mutex  a stale lock behind a takeover directory with no pid, or with a live pid, ends in exit 75 at LOCK_WAIT_S
#          with a "waiting" report (not an endless silent wait); one with no pid and 2 min old is reclaimed.
#   handoff the takeover program (TAKEOVER_PL, taken from the script) run by itself, paused 2 s after it reads a lock
#          whose owner is alive: that owner then releases it and a new owner takes it, so the takeover must keep the
#          new owner's lock (exit 3); the same with the new line written in place (same file: the line compare alone
#          must catch it); with the lock left as read and its owner gone in the pause, it must remove it (exit 0); with
#          the lock removed in the pause, exit 4; an empty lock 2 min old that gets its line in the pause is kept (3);
#          the same line written as a new file is kept (3: the dev/inode compare; skipped if the inode number is reused).
#   signal owners whose wrappers get HUP, INT, TERM, QUIT, ALRM, USR1, USR2, PIPE, TRAP, ABRT, EMT (macOS), SYS, XCPU,
#          XFSZ, VTALRM or PROF while their commands run keep their locks until the commands end (a queued waiter
#          starts only then), and exit 128 + the signal's number (INT, TERM: 130); one sent HUP in its cooldown exits
#          129 without running its command, and releases.
#   release the release program (RELEASE_PL) run by itself waits for the takeover flock (held by the test) before
#          removing its parent's lock, leaves a lock naming another pid (exit 3), and, orphaned after its check, leaves
#          the lock (exit 4); and the wrapper's own release waits for the flock too, ignoring a HUP meanwhile.
#   done   a takeover killed on its way out (right before or after done()'s rename) never leaves an unmarked
#          <lock>.takeover behind (the next one succeeds at once).
set -u
SC="$(cd "$(dirname "$0")/../../.." && pwd)"
WRAP="${LOCK_SCRIPT:-$SC/scripts/with-browser-lock.sh}"
N="${N:-6}"; HOLD0_S="${HOLD0_S:-4}"; HOLD_S="${HOLD_S:-1}"; GAP_S="${GAP_S:-0.4}"
# N and DROP_TICKET are whole numbers; HOLD0_S, HOLD_S and GAP_S are seconds and may be fractional (loop counts derived
# from them are computed with awk: polls, below). Checked before anything starts, so a bad value cannot orphan waiters.
isint() { case "$1" in ''|*[!0-9]*|0[0-9]*) return 1 ;; esac; }
isnum() { case "$1" in ''|.|*[!0-9.]*|*.*.*) return 1 ;; esac; }
{ isint "$N" && [ "$N" -ge 1 ] && isint "${DROP_TICKET:-2}" && [ "${DROP_TICKET:-2}" -le "$N" ] && isnum "$HOLD0_S" &&
  isnum "$HOLD_S" && isnum "$GAP_S"; } || {
  echo "LOCKFIFO FAIL: need N >= 1 and DROP_TICKET <= N as whole numbers, HOLD0_S, HOLD_S and GAP_S as seconds" \
    "(got N=$N DROP_TICKET=${DROP_TICKET:-2} HOLD0_S=$HOLD0_S HOLD_S=$HOLD_S GAP_S=$GAP_S)"; exit 2; }
TKO="${TAKEOVER_CASES-race,lane,empty,mutex,handoff,signal,release,done}"; [ "$TKO" != 0 ] || TKO=""; TKO="$(echo "$TKO" | tr ',' ' ')"
for c in $TKO; do case "$c" in race|lane|empty|mutex|handoff|signal|release|done) ;; *)
  echo "LOCKFIFO FAIL: TAKEOVER_CASES is a comma list of race, lane, empty, mutex, handoff, signal, release, done, or 0 (got ${TAKEOVER_CASES-})"; exit 2 ;; esac; done
# polls '<awk expression>': a loop count, int(expression) + 1, with a=HOLD0_S, h=HOLD_S and n=N
polls() { awk -v a="$HOLD0_S" -v h="$HOLD_S" -v n="$N" "BEGIN { printf \"%d\", ($1) + 1 }"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/lockfifo.XXXXXX")"
J="$T/journal"; : > "$J"
STUB="${STUB:-}"
if [ -z "$STUB" ]; then STUB="$T/stub/with-browser-lock.sh"; mkdir -p "$T/stub"
  printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$WRAP" > "$STUB"; chmod +x "$STUB"; fi
REL_DIR="$(dirname "$WRAP")"
export BROWSER_LOCK_DIR="$T/lockdir" MIN_FREE_GB=0 LOCK_WAIT_S=300 SKIP_COOLDOWN_FOR_TEST=1 NO_CAFFEINATE=1
LOCKF="$(bash "$WRAP" --print-lock)"
[ "$LOCKF" = "$T/lockdir/browser.lock" ] || { echo "LOCKFIFO FAIL: --print-lock gave $LOCKF"; exit 1; }
[ "$(bash "$STUB" --print-lock)" = "$LOCKF" ] || { echo "LOCKFIFO FAIL: the stub resolves another lock"; exit 1; }
# fault cases (below): DROP_TICKET (default 2), PS_FAIL (default 1) and STALE_TICKET (default 1); 0 disables each.
# While any is on, the holder keeps the lock past HOLD0_S until $REL exists (or for 2400 polls of 0.05 s, each also
# forking a sleep: at least 120 s more, about 2.5 min measured on macOS), so DROP_TICKET is checked, the stale ticket
# planted, and w1's ticket checked and w1 stopped, all while it is held; $REL then releases it. Every exit from here on
# creates $REL (EXIT trap), so an early failure never leaves the holder waiting, and ends the stale ticket's process
# and the takeover cases' processes.
DROP="${DROP_TICKET:-2}"; PSF="${PS_FAIL:-1}"; STALE="${STALE_TICKET:-1}"; REL="$T/release"; SPID=""
CPID=""; FPID=""; TW=""; HP=""   # the takeover cases' live pid, flock holder, waiter and handoff processes (below)
on_exit() { local p; [ -d "$T" ] && : > "$REL"; for p in $SPID $CPID $FPID $TW $HP; do kill "$p" 2>/dev/null; done; }
trap on_exit EXIT
[ "$DROP" != 0 ] || [ "$PSF" != 0 ] || [ "$STALE" != 0 ] || : > "$REL"
mkdir -p "$T/fakeps"; printf '#!/bin/sh\nexit 1\n' > "$T/fakeps/ps"; chmod +x "$T/fakeps/ps"   # a ps that always fails
body() { echo "echo \"start $1 \$(perl -MTime::HiRes=time -e 'printf q(%.4f), time')\" >> '$J'; sleep $2; ${3:-}echo \"end $1 \$(perl -MTime::HiRes=time -e 'printf q(%.4f), time')\" >> '$J'"; }
bash "$WRAP" holder bash -c "$(body holder "$HOLD0_S" "for _ in \$(seq 1 2400); do [ -e '$REL' ] && break; sleep 0.05; done; ")" > "$T/holder.log" 2>&1 &
sleep 1
ARR=()
for i in $(seq 1 "$N"); do
  P="$PATH"; [ "$PSF" != 0 ] && [ "$i" = 1 ] && P="$T/fakeps:$PATH"   # PS_FAIL: w1 runs with the failing ps
  case $(( i % 3 )) in
    1) how=stub; (PATH="$P" bash "$STUB" "w$i-$how" bash -c "$(body "w$i" "$HOLD_S")" > "$T/w$i.log" 2>&1 &) ;;
    2) how=abs;  (PATH="$P" bash "$WRAP" "w$i-$how" bash -c "$(body "w$i" "$HOLD_S")" > "$T/w$i.log" 2>&1 &) ;;
    0) how=rel;  (cd "$REL_DIR" && PATH="$P" ./"$(basename "$WRAP")" "w$i-$how" bash -c "$(body "w$i" "$HOLD_S")" > "$T/w$i.log" 2>&1 &) ;;
  esac
  # "arrived" = its ticket is filed (the wrapper serves tickets in filing order). Launch order alone is not arrival
  # order: under host load a later waiter's bash can start before an earlier one filed its ticket (seen as a flake,
  # 2026-10-05: start order w1,w2,w4,w3,... with a 0.4 s gap), so wait for ticket i before launching waiter i+1.
  for _ in $(seq 1 200); do [ "$(ls "$LOCKF.queue" 2>/dev/null | wc -l | tr -d ' ')" -ge "$i" ] && break; sleep 0.05; done
  [ "$(ls "$LOCKF.queue" 2>/dev/null | wc -l | tr -d ' ')" -ge "$i" ] || { echo "LOCKFIFO FAIL: waiter w$i filed no ticket within 10 s"; exit 1; }
  ARR+=("w$i"); echo "arrived w$i via $how (ticket filed)"
  sleep "$GAP_S"
done
now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }'; }
holder_holds() { [ "$(awk '{print $1}' "$LOCKF" 2>/dev/null)" = holder ]; }
# fresh: the wrapper's test for a '-' ticket (head_ticket): modified under 60 s ago (GNU find) or at most 60 whole
# seconds ago (macOS /usr/bin/find, which works in whole seconds), or in the future
fresh() { [ -n "$(find "$1" -mmin -1 2>/dev/null)" ]; }
backdate() { perl -e '$t = time - 120; exit(utime($t, $t, $ARGV[0]) ? 0 : 1)' "$1"; }   # set mtime 2 min back
BAD=0; NOTES=""; note() { echo "$1"; NOTES="$NOTES; $1"; }
W1T="$(ls "$LOCKF.queue" 2>/dev/null | LC_ALL=C sort | sed -n 1p)"; W1PID="${W1T##*-}"   # ticket <time>-<pid>
# DROP_TICKET: waiter DROP_TICKET's ticket is removed while the lock is held (by hand, or by a scan: scans once dropped
# live tickets, 2026-10-25). Its owner re-files it at its next poll whatever the lock state, so its place is back
# within one poll (about 2 s); until then, a later waiter that finds the lock free could take it first, which is why
# the drop is made while the lock is held. Require the ticket back within 5 s while the holder still holds; FIFO must
# then hold.
if [ "$DROP" != 0 ]; then
  dt="$(ls "$LOCKF.queue" 2>/dev/null | LC_ALL=C sort | sed -n "${DROP}p")"
  [ -n "$dt" ] || { echo "LOCKFIFO FAIL: no ticket #$DROP to drop"; exit 1; }
  rm -f "$LOCKF.queue/$dt"; t1="$(now)"; echo "dropped ticket #$DROP ($dt: waiter w$DROP) while the holder holds the lock"
  for _ in $(seq 1 100); do [ -e "$LOCKF.queue/$dt" ] && break; sleep 0.05; done
  if [ -e "$LOCKF.queue/$dt" ] && holder_holds; then note "w$DROP re-filed its ticket $(since "$t1") s after the drop, lock still held"
  else BAD=$(( BAD + 1 )); note "w$DROP did NOT re-file its ticket within 5 s while the lock was held"; fi
fi
# STALE_TICKET: plant at the queue head, while the lock is held, the ticket that a waiter whose ps failed (start '-')
# leaves when it is killed with SIGKILL (no EXIT trap) and its pid is then reused by a live unrelated process (here a
# `sleep` of ours), last re-filed 2 min ago. Once the lock is free it must be removed and must not hold back the queue
# (checked after the release, below).
if [ "$STALE" != 0 ]; then
  sleep 300 & SPID=$!
  ST_T="$LOCKF.queue/0000000000.000000-$SPID"   # sorts before every real <time>-<pid> ticket
  { printf '%s\t-\tstale-killed\n' "$SPID" > "$T/stale.tkt" && backdate "$T/stale.tkt" && mv -f "$T/stale.tkt" "$ST_T"; } ||
    { echo "LOCKFIFO FAIL: cannot plant the stale ticket"; exit 1; }
  echo "planted a stale '-' ticket of live pid $SPID (mtime 2 min old) at the queue head"
fi
# PS_FAIL: w1 runs with a ps that always fails (as under memory pressure), so its ticket records no start time ('-');
# the other waiters must still count it as live. Such a ticket counts only while fresh (about 60 s), so w1 must keep it
# fresh: it is backdated by 2 min (as if w1 had stopped polling) while the lock is held and must be fresh again within
# 5 s. Then w1 is stopped (SIGSTOP: alive, but not polling) while the holder releases, so the others poll the free lock
# first: for 3 s (each polls at least every 2 s) none may take it or remove w1's ticket. A watchdog continues w1 even
# if this test dies first.
if [ "$PSF" != 0 ]; then
  [ -e "$LOCKF.queue/$W1T" ] || { echo "LOCKFIFO FAIL: w1's ticket ${W1T:-none} is gone"; exit 1; }
  w1st="$(cut -f2 "$LOCKF.queue/$W1T")"
  case "$w1st" in -|'') ;; *) echo "LOCKFIFO FAIL: w1's ticket records start '$w1st': the failing ps did not apply"; exit 1 ;; esac
  backdate "$LOCKF.queue/$W1T" || { echo "LOCKFIFO FAIL: cannot backdate w1's ticket"; exit 1; }; t1="$(now)"
  for _ in $(seq 1 100); do fresh "$LOCKF.queue/$W1T" && break; sleep 0.05; done
  if fresh "$LOCKF.queue/$W1T" && holder_holds; then note "w1 (no start time) re-filed its backdated ticket $(since "$t1") s later"
  else BAD=$(( BAD + 1 )); note "w1 (no start time) did NOT re-file its backdated ticket within 5 s while the lock was held"; fi
  kill -STOP "$W1PID" 2>/dev/null || { echo "LOCKFIFO FAIL: cannot stop w1 (pid ${W1PID:-none})"; exit 1; }
  (for _ in $(seq 1 "$(polls '(a + 30) / 0.2')"); do [ -e "$T/cont" ] && exit 0; sleep 0.2; done; kill -CONT "$W1PID") 2>/dev/null &
  : > "$REL"
  for _ in $(seq 1 "$(polls '(a + 10) / 0.05')"); do holder_holds || break; sleep 0.05; done
  sleep 3
  took="$(grep -m1 '^start w' "$J" | cut -d' ' -f2)"; [ -n "$took" ] || took="$(awk '{print $1}' "$LOCKF" 2>/dev/null)"
  kept=no; [ -e "$LOCKF.queue/$W1T" ] && kept=yes
  kill -CONT "$W1PID"; : > "$T/cont"
  if [ "$kept" = yes ] && [ -z "$took" ]; then note "w1 (no start time) kept its ticket; the free lock waited 3 s for it"
  else BAD=$(( BAD + 1 )); note "while w1 (no start time) was stopped: ticket kept: $kept, lock taken by: ${took:-nobody}"; fi
fi
: > "$REL"
# STALE_TICKET, checked: within 15 s (from here: the release, or w1's continue under PS_FAIL) a waiter must start while
# the stale ticket's pid still lives, and that ticket must be gone. Then its process is ended either way, so a failing
# run still finishes (its ticket is then a dead pid's).
if [ "$STALE" != 0 ]; then
  for _ in $(seq 1 300); do grep -q '^start w' "$J" && break; sleep 0.05; done
  first="$(grep -m1 '^start w' "$J" | cut -d' ' -f2)"; gone=yes; [ -e "$ST_T" ] && gone=no
  alive=no; kill -0 "$SPID" 2>/dev/null && alive=yes
  kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null; SPID=""
  if [ -n "$first" ] && [ "$gone" = yes ] && [ "$alive" = yes ]; then
    note "the stale '-' ticket of a live unrelated pid was removed; $first took the free lock while that pid lived"
  else BAD=$(( BAD + 1 )); note "stale '-' ticket of a live unrelated pid: removed: $gone, first waiter started within 15 s: ${first:-none}"; fi
fi
# wait for everyone (the waiters are not our children: poll the journal)
for _ in $(seq 1 "$(polls '(a + n * (h + 3)) / 0.5')"); do [ "$(grep -c '^end ' "$J")" -ge $(( N + 1 )) ] && break; sleep 0.5; done
wait
# the last holder removes the lock right after its command exits: give it up to 10 s before judging "lock left"
for _ in $(seq 1 20); do [ -e "$LOCKF" ] || break; sleep 0.5; done
# ---- takeover cases (TAKEOVER_CASES, see the header): each on its own lock file $T/tko/<case>/browser.lock --------
# tstart <lock> <lane> <LOCK_WAIT_S>: start one waiter on <lock> whose command appends "ran" to <lock>.ran; tend <s>:
# wait up to <s> seconds for it and set TRC to its exit code, or to "still-waiting" (it is then ended: SIGTERM)
tstart() { BROWSER_LOCK_FILE="$1" LOCK_WAIT_S="$3" bash "$WRAP" "$2" bash -c "echo ran >> '$1.ran'" > "$1.$2.log" 2>&1 & TW=$!; }
tend() { for _ in $(seq 1 "$(polls "$1 / 0.05")"); do kill -0 "$TW" 2>/dev/null || break; sleep 0.05; done
  if kill -0 "$TW" 2>/dev/null; then kill "$TW" 2>/dev/null; wait "$TW" 2>/dev/null; TRC=still-waiting; else wait "$TW"; TRC=$?; fi; TW=""; }
ran() { [ -e "$1.ran" ] && wc -l < "$1.ran" | tr -d ' ' || echo 0; }   # how many waiters ran their command on <lock>
inode_of() { perl -e '@s = stat($ARGV[0]) or exit 1; print "$s[1]"' "$1" 2>/dev/null || echo none; }   # inode
if [ -n "$TKO" ]; then
  sh -c 'exit 0' & DPID=$!; wait "$DPID"   # a pid that is certainly gone
  sleep 300 & CPID=$!                      # a live pid (a stopped holder, a reused pid, or an older copy's live owner)
fi
for c in $TKO; do
  d="$T/tko/$c"; L="$d/browser.lock"; mkdir -p "$d"; STALE_LINE="deadlane $DPID 2026-10-27T00:00:00Z"
  case "$c" in
  race)
    # a takeover in progress, as the test: it holds the flock and the directory mutex, whose pid file names a DEAD pid
    # (what a waiter saw when it read the pid of an earlier, dead mutex that has since been replaced by this live one:
    # moving it then let two takeovers act at once, 2026-10-27). For 3 s no waiter may touch it or the lock.
    echo "$STALE_LINE" > "$L"
    perl -MFcntl=:flock -e 'open(my $m, ">>", "$ARGV[0].takeover.flk") or exit 1; flock($m, LOCK_EX) or exit 1;
      mkdir("$ARGV[0].takeover") or exit 1; open(my $h, ">", "$ARGV[0].takeover/pid") or exit 1; print $h "$ARGV[1]\n";
      close($h); for (1 .. 1200) { last if -e $ARGV[2]; select(undef, undef, undef, 0.05) }
      unlink("$ARGV[0].takeover/pid"); rmdir("$ARGV[0].takeover")' "$L" "$DPID" "$d/go" & FPID=$!
    for _ in $(seq 1 100); do [ -s "$L.takeover/pid" ] && break; sleep 0.05; done
    ino="$(inode_of "$L.takeover")"; tstart "$L" race1 30; sleep 3
    left=yes; { [ "$(cat "$L" 2>/dev/null)" = "$STALE_LINE" ] && [ "$(inode_of "$L.takeover")" = "$ino" ] && [ "$ino" != none ] &&
      [ "$(ran "$L")" = 0 ]; } || left=no
    : > "$d/go"; wait "$FPID" 2>/dev/null; FPID=""; t1="$(now)"; tend 10; trc1="$TRC"; took="$(since "$t1")"
    # a directory mutex left by a killed takeover of this copy (marker 'flk'; its pid is gone): reclaimed at once
    echo "$STALE_LINE" > "$L"; mkdir "$L.takeover"; : > "$L.takeover/flk"; echo "$DPID" > "$L.takeover/pid"
    tstart "$L" race2 30; tend 10; trc2="$TRC"; ran2="$(ran "$L")"
    # a live takeover that has written its marker 'flk': only its flock (held by the test) keeps others off, since a
    # marked directory is otherwise reclaimed at once (as above). The waiter must give up (exit 75), touching nothing.
    echo "$STALE_LINE" > "$L"
    perl -MFcntl=:flock -e 'open(my $m, ">>", "$ARGV[0].takeover.flk") or exit 1; flock($m, LOCK_EX) or exit 1;
      mkdir("$ARGV[0].takeover") or exit 1; open(my $h, ">", "$ARGV[0].takeover/flk") or exit 1; close($h);
      open($h, ">", "$ARGV[0].takeover/pid") or exit 1; print $h "$ARGV[1]\n"; close($h); open($h, ">", $ARGV[3]) and close($h);
      for (1 .. 1200) { last if -e $ARGV[2]; select(undef, undef, undef, 0.05) }
      unlink("$ARGV[0].takeover/pid", "$ARGV[0].takeover/flk"); rmdir("$ARGV[0].takeover")' "$L" "$DPID" "$d/go3" "$d/held3" & FPID=$!
    for _ in $(seq 1 200); do [ -e "$d/held3" ] && break; sleep 0.05; done
    ino="$(inode_of "$L.takeover")"; tstart "$L" race3 3; tend 15; trc3="$TRC"
    kept3=yes; { [ "$(cat "$L" 2>/dev/null)" = "$STALE_LINE" ] && [ "$(inode_of "$L.takeover")" = "$ino" ] && [ "$ino" != none ] &&
      [ -e "$L.takeover/flk" ] && [ "$(ran "$L")" = "$ran2" ]; } || kept3=no
    : > "$d/go3"; wait "$FPID" 2>/dev/null; FPID=""; rm -f "$L"
    if [ "$left" = yes ] && [ "$trc1" = 0 ] && [ "$trc2" = 0 ] && [ "$ran2" = 2 ] && [ "$trc3" = 75 ] && [ "$kept3" = yes ] && [ ! -e "$L.takeover" ]; then
      note "race: a live takeover (its mutex naming a dead pid) was left alone 3 s, then the stale lock was taken ${took} s after it ended; a killed takeover's mutex was reclaimed; a marked one whose flock is held was left alone (exit 75)"
    else BAD=$(( BAD + 1 )); note "race: live takeover left alone 3 s: $left; waiter after it ended: $trc1; after a killed takeover: $trc2; ran: $ran2; marked mutex with its flock held: waiter $trc3 (want 75), left alone: $kept3"; fi ;;
  lane)
    BROWSER_LOCK_FILE="$L" bash "$WRAP" "a b" bash -c "echo ran >> '$L.ran'" > "$d/refuse.log" 2>&1; rr=$?
    # an older copy's lock line whose lane has a space, owner alive: its pid must be found, and the lock left alone
    printf 'old lane %s 2026-10-27T00:00:00Z\n' "$CPID" > "$L"; line0="$(cat "$L")"
    tstart "$L" lanew 3; tend 15
    if [ "$rr" = 2 ] && [ "$TRC" = 75 ] && [ "$(cat "$L" 2>/dev/null)" = "$line0" ] && [ "$(ran "$L")" = 0 ]; then
      note "lane: 'a b' refused (exit 2); an older copy's live lock with a spaced lane kept (exit 75)"
    else BAD=$(( BAD + 1 )); note "lane: 'a b' exit $rr (want 2); live spaced-lane lock: waiter $TRC (want 75), lock kept: $( [ "$(cat "$L" 2>/dev/null)" = "$line0" ] && echo yes || echo no), ran: $(ran "$L")"; fi ;;
  empty)
    : > "$L"; tstart "$L" e1 3; tend 15; e1="$TRC"; kept=no; [ -e "$L" ] && [ ! -s "$L" ] && [ "$(ran "$L")" = 0 ] && kept=yes
    backdate "$L"; tstart "$L" e2 6; tend 15; e2="$TRC"
    printf '\0\0\0\0\0\0' > "$L"; backdate "$L"; tstart "$L" e3 6; tend 15; e3="$TRC"
    if [ "$e1" = 75 ] && [ "$kept" = yes ] && [ "$e2" = 0 ] && [ "$e3" = 0 ] && [ "$(ran "$L")" = 2 ] && [ ! -e "$L" ]; then
      note "empty lock: kept while fresh (exit 75); taken over at 2 min old, a NUL-filled one too"
    else BAD=$(( BAD + 1 )); note "empty lock: fresh: waiter $e1 (want 75), kept: $kept; 2 min old: waiter $e2 (want 0); NUL-filled: waiter $e3 (want 0)"; fi ;;
  mutex)
    echo "$STALE_LINE" > "$L"; mkdir "$L.takeover"   # no pid: its maker died between mkdir and writing it
    tstart "$L" m1 3; tend 15; m1="$TRC"; said=no; grep -q 'waiting' "$L.m1.log" && said=yes
    echo "$CPID" > "$L.takeover/pid"                 # a live pid: an older copy's holder that is stopped, or a reused pid
    tstart "$L" m2 3; tend 15; m2="$TRC"; said2=no; grep -q 'waiting' "$L.m2.log" && said2=yes
    rm -f "$L.takeover/pid"; backdate "$L.takeover"   # no pid, 2 min old: dead
    tstart "$L" m3 30; tend 15; m3="$TRC"
    if [ "$m1" = 75 ] && [ "$said" = yes ] && [ "$m2" = 75 ] && [ "$said2" = yes ] && [ "$m3" = 0 ] && [ "$(ran "$L")" = 1 ] && [ ! -e "$L" ] && [ ! -e "$L.takeover" ]; then
      note "takeover mutex with no pid or a live pid: exit 75 at LOCK_WAIT_S, each reported; no pid and 2 min old: reclaimed"
    else BAD=$(( BAD + 1 )); note "takeover mutex: no pid: waiter $m1 (want 75), reported: $said; live pid: waiter $m2 (want 75), reported: $said2; no pid, 2 min old: waiter $m3 (want 0)"; fi ;;
  handoff)
    # a takeover reached at an ordinary handoff and paused between its read and its check: the owner it read (Q) was
    # alive, then released the lock, and a new owner (R) took it; judging Q gone and removing the lock by its path then
    # removed R's LIVE lock (2026-10-27). Played with the takeover program alone (its 2nd argument: a pause after the
    # read), so the order is exact. What happens in the pause, by mode: new (Q ends, the lock is removed and R's line
    # written as a new file: keep it, exit 3), inplace (the same with R's line written into the same file: only the
    # line compare can catch it), keep (Q ends, the lock is left as read: stale, remove it, exit 0), gone (Q ends, the
    # lock is removed: exit 4), empty (the lock starts empty and 2 min old, and a line is written into it: keep it, 3),
    # newsame (Q ends, the lock is removed and Q's own line written as a new file: only the dev/inode compare can catch
    # it, so it is skipped where the filesystem hands the new file the old inode number).
    TKPL="$(perl -0ne "print \$1 if /\nTAKEOVER_PL='([^']*)'/" "$WRAP")"
    hand() {   # hand <mode>: sets HRC (the takeover's exit code), HLINE (the lock after it: "none" if gone), RLINE
      sleep 300 & local q=$!; sleep 300 & local r=$!; HP="$q $r"; RLINE="r $r 2026-10-27T00:00:01Z"; HSKIP=no
      QLINE="q $q 2026-10-27T00:00:00Z"
      if [ "$1" = empty ]; then : > "$L"; backdate "$L"; else printf '%s\n' "$QLINE" > "$L"; fi
      perl -e "$TKPL" "$L" 2 > "$d/$1.out" 2> "$d/$1.err" & local tp=$!; HP="$HP $tp"
      for _ in $(seq 1 100); do [ -s "$L.takeover/pid" ] && break; sleep 0.02; done; sleep 0.5   # it has read the lock
      kill "$q"; wait "$q" 2>/dev/null
      case "$1" in
        new) rm -f "$L"; printf '%s\n' "$RLINE" > "$L" ;;
        inplace|empty) printf '%s\n' "$RLINE" > "$L" ;;
        gone) rm -f "$L" ;;
        newsame) local i0; i0="$(inode_of "$L")"; rm -f "$L"; printf '%s\n' "$QLINE" > "$L"
          [ "$(inode_of "$L")" != "$i0" ] || HSKIP=yes ;;
      esac
      wait "$tp"; HRC=$?; kill "$r" 2>/dev/null; wait "$r" 2>/dev/null; HP=""
      HLINE="$(cat "$L" 2>/dev/null || echo none)"; rm -f "$L"; }
    if [ -z "$TKPL" ]; then BAD=$(( BAD + 1 )); note "handoff: no TAKEOVER_PL program in $WRAP"
    else
      hres=""; hok=yes; hskipped=""
      for mode in new inplace newsame keep gone empty; do
        hand "$mode"; want=3; wline="$RLINE"
        case "$mode" in keep) want=0; wline=none ;; gone) want=4; wline=none ;; newsame) wline="$QLINE" ;; esac
        if [ "$HSKIP" = yes ]; then hskipped="$hskipped $mode"; continue; fi
        okm=yes; [ "$HRC" = "$want" ] && [ "$HLINE" = "$wline" ] || okm=no
        case "$mode" in new|inplace|newsame|empty) grep -q 'changed' "$d/$mode.err" || okm=no ;; esac
        [ "$okm" = yes ] || hok=no; hres="$hres $mode=$HRC(want $want, lock $( [ "$HLINE" = none ] && echo gone || echo kept))"
      done
      if [ "$hok" = yes ] && [ ! -e "$L.takeover" ]; then
        note "handoff: a lock changed in the takeover's pause (new file, same file, the same line in a new file, an empty one written) was kept; the unchanged stale one removed; one removed in the pause: exit 4${hskipped:+ (skipped, the inode was reused:$hskipped)}"
      else BAD=$(( BAD + 1 )); note "handoff:$hres; takeover dir left: $( [ -e "$L.takeover" ] && echo yes || echo no)"; fi
    fi ;;
  signal)
    # an owner whose wrapper gets a signal while its command runs must keep the lock until the command ends: bash ran
    # the EXIT trap (release) at once for an untrapped HUP, USR1, ABRT, XCPU, ... and died, or died without it (QUIT,
    # PROF), so a queued waiter ran beside the command (2026-10-27). One owner per signal, each on its own lock and all
    # at once; each is started with every signal tested here at its default: a background job of a script starts with INT
    # and QUIT ignored, and GitHub's Linux runner starts a step with PIPE ignored (2026-11-05), and a signal ignored on
    # entry cannot be trapped, so the wrapper could not receive it. Its exit code must be 128 + the signal's number (INT,
    # TERM: 130).
    SIGS=""; for sg in HUP INT TERM QUIT ALRM USR1 USR2 PIPE TRAP ABRT EMT SYS XCPU XFSZ VTALRM PROF; do
      kill -l "$sg" >/dev/null 2>&1 && SIGS="$SIGS $sg"; done   # EMT exists on macOS only
    [ "$(uname -s)" != Linux ] || SIGS="$SIGS IO PWR STKFLT"   # trapped on Linux only (on macOS IO is ignored)
    QWS=(); RWS=(); HP=""
    for sg in $SIGS; do sd="$d/$sg"; mkdir -p "$sd"
      BROWSER_LOCK_FILE="$sd/browser.lock" LOCK_WAIT_S=60 perl -e '$SIG{$_} = "DEFAULT" for split " ", shift; exec { $ARGV[0] } @ARGV' \
        "$SIGS" bash "$WRAP" "q$sg" bash -c "echo start-q >> '$sd/j'; sleep 8; echo end-q >> '$sd/j'" > "$sd/q.log" 2>&1 &
      QWS+=($!); HP="$HP $!"; done
    for sg in $SIGS; do for _ in $(seq 1 200); do grep -q start-q "$d/$sg/j" 2>/dev/null && break; sleep 0.05; done; done
    for sg in $SIGS; do sd="$d/$sg"
      BROWSER_LOCK_FILE="$sd/browser.lock" LOCK_WAIT_S=60 bash "$WRAP" "r$sg" bash -c "echo start-r >> '$sd/j'" > "$sd/r.log" 2>&1 &
      RWS+=($!); HP="$HP $!"; done
    # each command runs 8 s; all signals are sent about 2 s after the first command started, so a lock released then
    # leaves its waiter (which polls a held lock every 2 s) about 6 s to start before the command ends: it starts
    # before end-q in the journal
    sleep 0.5; k=0; for sg in $SIGS; do kill -"$sg" "${QWS[$k]}" 2>/dev/null; k=$(( k + 1 )); done
    sres=""; sok=yes; k=0
    for sg in $SIGS; do sd="$d/$sg"
      wait "${QWS[$k]}"; qrc=$?
      for _ in $(seq 1 300); do grep -q end-q "$sd/j" 2>/dev/null && grep -q start-r "$sd/j" 2>/dev/null && break; sleep 0.05; done
      wait "${RWS[$k]}"; k=$(( k + 1 ))
      case "$sg" in INT|TERM) want=130 ;; *) want=$(( 128 + $(kill -l "$sg") )) ;; esac
      order="$(tr '\n' ' ' < "$sd/j" 2>/dev/null)"
      if [ "$order" = "start-q end-q start-r " ] && [ "$qrc" = "$want" ] && [ ! -e "$sd/browser.lock" ]; then :
      else sok=no; sres="$sres $sg: order ${order:-none}, owner exit $qrc (want $want);"; fi
    done; HP=""
    # an owner signalled in its cooldown (it waits for memory it will never get): it exits 129 once the cooldown's
    # current step ends (at most about 5 s), without running its command, and releases the lock
    sd="$d/cool"; mkdir -p "$sd"
    BROWSER_LOCK_FILE="$sd/browser.lock" SKIP_COOLDOWN_FOR_TEST=0 MIN_FREE_GB=100000 COOLDOWN_WAIT_S=120 \
      perl -e '$SIG{HUP} = "DEFAULT"; exec { $ARGV[0] } @ARGV' bash "$WRAP" qcool \
      bash -c ": > '$sd/ran'" > "$sd/q.log" 2>&1 & cw=$!; HP="$cw"
    # the HUP must reach it in the cooldown (a wrapper still waiting for the lock also dies by HUP: 129, no command)
    seen=no; for _ in $(seq 1 600); do grep -q 'cooldown waiting' "$sd/q.log" 2>/dev/null && { seen=yes; break; }; sleep 0.05; done
    kill -HUP "$cw" 2>/dev/null; t1="$(now)"; wait "$cw"; crc=$?; HP=""; ctook="$(since "$t1")"
    cok=yes; [ "$seen" = yes ] && [ "$crc" = 129 ] && [ ! -e "$sd/ran" ] && [ ! -e "$sd/browser.lock" ] || cok=no
    if [ "$sok" = yes ] && [ "$cok" = yes ]; then note "signal: owners sent $(echo "${SIGS# }" | tr ' ' ',') kept the lock until their commands ended, exit 128+n (INT, TERM: 130); one sent HUP in its cooldown exited 129 in ${ctook} s and released"
    else BAD=$(( BAD + 1 )); note "signal:$sres cooldown HUP: reached the cooldown first: $seen, exit $crc (want 129), command ran: $( [ -e "$sd/ran" ] && echo yes || echo no), lock left: $( [ -e "$sd/browser.lock" ] && echo yes || echo no)"; fi ;;
  release)
    # the release program (RELEASE_PL) by itself, run by a parent shell that the lock names: (1) it waits for the
    # takeover flock (the test holds it) and then removes its parent's lock; (2) it leaves a lock naming another pid
    # (exit 3); (3) orphaned in its pause after the check (its parent killed with SIGKILL) it leaves the lock (exit 4)
    # for a takeover: an older copy's takeover, which takes no flock, could otherwise remove it first and then lose the
    # next owner's lock to us. Then (4) the wrapper's own release() must go through it: an owner whose command has
    # ended keeps its lock while the test holds the flock (also when sent HUP meanwhile: release() ignores it), and
    # removes it once the flock is free, exiting with its command's code.
    RLPL="$(perl -0ne "print \$1 if /\nRELEASE_PL='([^']*)'/" "$WRAP")"
    if [ -z "$RLPL" ]; then BAD=$(( BAD + 1 )); note "release: no RELEASE_PL program in $WRAP"
    else
      holdflock() {   # holdflock <go file> <held file>: hold the takeover flock until <go file> exists (FPID)
        rm -f "$1" "$2"
        perl -MFcntl=:flock -e 'open(my $m, ">>", "$ARGV[0].takeover.flk") or exit 1; flock($m, LOCK_EX) or exit 1;
          open(my $h, ">", $ARGV[2]) and close($h); for (1 .. 1200) { last if -e $ARGV[1]; select(undef, undef, undef, 0.05) }' \
          "$L" "$1" "$2" & FPID=$!
        for _ in $(seq 1 200); do [ -e "$2" ] && break; sleep 0.05; done; }
      # (1)
      holdflock "$d/go1" "$d/held1"
      bash -c 'printf "q %s 2026-10-27T00:00:00Z\n" "$$" > "$1"; perl -e "$2" "$1" "$$"; echo $? > "$3"' _ "$L" "$RLPL" "$d/r1.rc" & rp=$!; HP="$rp"
      sleep 1.5; waited=no; [ -e "$L" ] && kill -0 "$rp" 2>/dev/null && waited=yes
      : > "$d/go1"; wait "$FPID" 2>/dev/null; FPID=""; wait "$rp"; HP=""; r1="$(cat "$d/r1.rc" 2>/dev/null)"; gone1=yes; [ -e "$L" ] && gone1=no
      # (2)
      bash -c 'printf "r 1 2026-10-27T00:00:00Z\n" > "$1"; perl -e "$2" "$1" "$$"; echo $? > "$3"' _ "$L" "$RLPL" "$d/r2.rc"
      r2="$(cat "$d/r2.rc" 2>/dev/null)"; kept2=no; [ "$(cat "$L" 2>/dev/null)" = "r 1 2026-10-27T00:00:00Z" ] && kept2=yes; rm -f "$L"
      # (3)
      # its exit code is written by an END block prepended to the program, as perl must stay the shell's direct child
      RLPL3='END { if (open(my $f, ">", $ENV{RCF})) { print $f "$?\n" } } '"$RLPL"
      RCF="$d/r3.rc" bash -c 'printf "q %s 2026-10-27T00:00:00Z\n" "$$" > "$1"; perl -e "$2" "$1" "$$" 2 & echo $! > "$3"; wait' _ "$L" "$RLPL3" "$d/r3.pid" & bp=$!; HP="$bp"
      for _ in $(seq 1 100); do [ -s "$d/r3.pid" ] && break; sleep 0.05; done; rlp="$(cat "$d/r3.pid" 2>/dev/null)"; HP="$bp $rlp"
      sleep 0.5; line3="$(cat "$L" 2>/dev/null)"; kill -KILL "$bp" 2>/dev/null; wait "$bp" 2>/dev/null
      for _ in $(seq 1 100); do kill -0 "$rlp" 2>/dev/null || break; sleep 0.05; done; HP=""
      for _ in $(seq 1 100); do [ -s "$d/r3.rc" ] && break; sleep 0.05; done; r3="$(cat "$d/r3.rc" 2>/dev/null)"
      kept3=no; [ -n "$line3" ] && [ "$(cat "$L" 2>/dev/null)" = "$line3" ] && [ "$r3" = 4 ] && kept3=yes; rm -f "$L"
      # (4)
      holdflock "$d/go4" "$d/held4"
      BROWSER_LOCK_FILE="$L" LOCK_WAIT_S=30 bash "$WRAP" relw bash -c ": > '$d/cmd4'" > "$d/relw.log" 2>&1 & ow=$!; HP="$ow"
      for _ in $(seq 1 200); do [ -e "$d/cmd4" ] && break; sleep 0.05; done; sleep 1
      kill -HUP "$ow" 2>/dev/null; sleep 0.5   # ignored while release() runs
      kept4=no; [ -e "$L" ] && kill -0 "$ow" 2>/dev/null && kept4=yes
      : > "$d/go4"; wait "$FPID" 2>/dev/null; FPID=""; wait "$ow"; orc=$?; HP=""; gone4=yes; [ -e "$L" ] && gone4=no
      if [ "$waited" = yes ] && [ "$r1" = 0 ] && [ "$gone1" = yes ] && [ "$r2" = 3 ] && [ "$kept2" = yes ] && [ "$kept3" = yes ] &&
         [ "$kept4" = yes ] && [ "$orc" = 0 ] && [ "$gone4" = yes ]; then
        note "release: it waited for the takeover flock, then removed its own lock; left another pid's lock (exit 3); orphaned after its check, left the lock; the wrapper's release waited for the flock too, through a HUP"
      else BAD=$(( BAD + 1 )); note "release: (1) waited for the flock: $waited, exit $r1 (want 0), removed: $gone1; (2) another pid's lock: exit $r2 (want 3), kept: $kept2; (3) orphaned after its check: exit ${r3:-none} (want 4), lock kept: $kept3; (4) wrapper: kept while the flock was held: $kept4, exit $orc (want 0), removed after: $gone4"; fi
    fi ;;
  done)
    # a takeover killed with SIGKILL on its way out (in done(), after removing the lock) must never leave an UNMARKED
    # <lock>.takeover (no 'flk'), which the rule for older copies' directories treats as live for 60 s (every takeover
    # of this copy then waited 60 s, 2026-10-27). done() renames it to <lock>.takeover.gone.<pid> before emptying it.
    # Played with the takeover program alone, killed at two points: right before the rename (the directory must still
    # be whole and marked, so the next takeover reclaims it at once: emptying it first left it unmarked) and right
    # after it (no <lock>.takeover at all).
    TKPL="$(perl -0ne "print \$1 if /\nTAKEOVER_PL='([^']*)'/" "$WRAP")"
    INJ='my $d = rename($T, $g) ? $g : $T;'
    case "$TKPL" in *"$INJ"*) ;; *) TKPL="" ;; esac
    if [ -z "$TKPL" ]; then BAD=$(( BAD + 1 )); note "done: no TAKEOVER_PL with done()'s rename in $WRAP"
    else
      dres=""; dok=yes
      for at in before after; do
        TKPAUSE="$(printf '%s' "$TKPL" | INJ="$INJ" AT="$at" perl -0pe '$i = index($_, $ENV{INJ});
          substr($_, $i + ($ENV{AT} eq "after" ? length($ENV{INJ}) : 0), 0, " select(undef, undef, undef, 30); ") if $i >= 0')"
        echo "$STALE_LINE" > "$L"
        perl -e "$TKPAUSE" "$L" > "$d/done1.out" 2>&1 & tp=$!; HP="$tp"
        # it removes the lock just before done(): the kill must land in the injected pause, after that
        gone=no; for _ in $(seq 1 600); do [ ! -e "$L" ] && { gone=yes; break; }; sleep 0.05; done; sleep 0.3
        kill -KILL "$tp" 2>/dev/null; wait "$tp" 2>/dev/null; HP=""
        left="none"; [ -e "$L.takeover" ] && { left=unmarked; [ -e "$L.takeover/flk" ] && left=marked; }
        want=none; [ "$at" = before ] && want=marked   # before the rename the directory is still whole; after it, gone
        echo "$STALE_LINE" > "$L"; t1="$(now)"; perl -e "$TKPL" "$L" > "$d/done2.out" 2>&1; drc=$?; took="$(since "$t1")"
        [ "$gone" = yes ] && [ "$left" = "$want" ] && [ "$drc" = 0 ] && [ ! -e "$L" ] && [ ! -e "$L.takeover" ] || dok=no
        dres="$dres $at its rename: lock removed first: $gone, left $left (want $want), next takeover exit $drc in ${took} s;"
        rm -rf "$L".takeover.gone.* 2>/dev/null; rm -f "$L"
      done
      if [ "$dok" = yes ]; then note "done: a takeover killed on its way out never left an unmarked <lock>.takeover:$dres"
      else BAD=$(( BAD + 1 )); note "done:$dres"; fi
    fi ;;
  esac
done
[ -z "$CPID" ] || { kill "$CPID" 2>/dev/null; wait "$CPID" 2>/dev/null; CPID=""; }
node -e '
  const fs = require("fs");
  const [jf, n, lockf, qdir, arr, bad, notes] = process.argv.slice(1);
  const lines = fs.readFileSync(jf, "utf8").trim().split("\n").map((l) => l.split(" "));
  const iv = {}; for (const [k, who, t] of lines) { iv[who] = iv[who] || {}; iv[who][k] = +t; }
  const xs = Object.entries(iv).map(([w, v]) => ({ w, s: v.start, e: v.end })).sort((a, b) => a.s - b.s);
  let overlaps = 0; for (let i = 1; i < xs.length; i++) if (xs[i].s < xs[i - 1].e) overlaps++;
  const done = xs.filter((x) => x.s && x.e).length;
  const order = xs.map((x) => x.w).filter((w) => w !== "holder");
  const want = arr.split(",");
  const fifo = JSON.stringify(order) === JSON.stringify(want);
  const left = fs.existsSync(lockf), tickets = fs.existsSync(qdir) ? fs.readdirSync(qdir).length : 0;
  const ok = done === +n + 1 && overlaps === 0 && fifo && !left && tickets === 0 && +bad === 0;
  console.log(`LOCKFIFO ${ok ? "OK" : "FAIL"}: ${done}/${+n + 1} ran, ${overlaps} overlapping critical sections, start order ${order.join(",")} (arrival ${want.join(",")}: ${fifo ? "FIFO" : "NOT FIFO"}), lock left: ${left}, tickets left: ${tickets}, fault cases: ${notes || "off"}`);
  process.exit(ok ? 0 : 1);
' "$J" "$N" "$LOCKF" "$LOCKF.queue" "$(IFS=,; echo "${ARR[*]}")" "$BAD" "${NOTES#; }"; rc=$?
[ $rc = 0 ] || { for f in "$T"/*.log; do echo "== $f"; tail -5 "$f"; done; }
rm -rf "$T"; exit $rc
