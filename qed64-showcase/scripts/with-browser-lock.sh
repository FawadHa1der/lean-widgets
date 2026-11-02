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
# The lock is created atomically with `set -o noclobber` and holds "<lane> <pid> <iso-time>", so <lane> must be one word
# (an empty lane, or one with a space, tab or newline, is refused: exit 2). While it exists we poll every 1-2 s, up to
# LOCK_WAIT_S (default 3600 s), and say once a minute who holds it and why we wait. It is stale when its owner pid is
# gone, or when it names no owner pid (empty or cut short: its writer died or failed between creating and writing it)
# and has not changed for 60 s. A waiter that finds it possibly stale calls the takeover (TAKEOVER_PL: one perl
# process), which re-reads the lock, decides, and unlinks it while it holds two mutexes: a flock on <lock>.takeover.flk,
# which the kernel releases when its holder dies (so it is never reclaimed and never removed: the file stays), keeps
# any two takeovers of this copy from acting at once; the directory <lock>.takeover (mkdir; it holds a pid file and the
# marker 'flk') keeps out the takeovers of older copies of this script, which use only that directory (limit (4)). The
# lock is removed on exit, including failure and any trapped signal (each is deferred until the command ends: see the
# trap lines), by RELEASE_PL under the same flock.
#
# FAIRNESS (FIFO): every waiter first files a ticket <lock>.queue/<arrival-time>-<pid> (content: pid, process start
# time, lane). A free lock is taken only by the waiter holding the OLDEST live ticket, so waiters are served in arrival
# order whatever path they invoked the script by. Tickets that are not live are removed on the way (see head_ticket):
# pid dead; pid alive with a different start time (the pid was reused); start time unknown and the ticket not modified
# for about 60 s (head_ticket has the exact cut-off). A waiter whose ps cannot report its own start time (ps can fail
# under memory pressure) records '-' and re-files the ticket at every poll, so its ticket stays a few seconds old while
# it waits; a '-' ticket left by a waiter killed with SIGKILL whose pid was then reused stops counting about 60 s after
# it was last re-filed (later if the clock steps back: limit (3)). FAIR=0 disables the queue (take the lock when free).
# Known limits: (1) a ticket with a recorded start time counts as live while the SCANNER's ps cannot report its pid,
# even if that pid was reused, until the scanner's ps works again. (2) The start time is ps's lstart string, which
# follows the TZ and locale (LC_TIME) of the process running ps: a scanner whose TZ or locale differs from the
# waiter's reads the waiter's live ticket as a reused pid and removes it (a waiter of this copy re-files it at its next
# poll), so arrival order is not kept between waiters run under different TZ/LC_TIME. All copies on one host normally
# share them. Pinning TZ/LC_ALL here would remove (2), but this copy would then remove the live tickets of older
# copies, and they this copy's, so it is left as is. (3) A ticket's age is its mtime's age on the wall clock. After the
# clock steps back by X s, a stale '-' ticket counts as live for about X s longer (a future mtime always counts as
# fresh); after it steps forward, or the host sleeps, by more than about 60 s, live '-' tickets can look stale and be
# removed (each owner re-files its ticket at its next poll, as after any removal: see file_ticket). (4) Older copies of
# this script (before 2026-10-27) guard their takeovers with the <lock>.takeover directory alone, reclaim one whose
# recorded pid is dead by moving it away (which can move a live one made in the meantime), and release with a bash check
# followed by a separate rm. While such an older copy shares the lock, this copy cannot prevent three things: its
# takeover acting alongside another one, once the pid recorded in a takeover directory has died (this copy records its
# waiter's pid, which outlives the takeover, so that takes a waiter dying inside a takeover's few milliseconds); its
# release's rm, orphaned by a SIGKILL of that owner, removing the next owner's live lock; and its takeover removing a
# stale lock while a release of this copy, orphaned in the instant between its last check and its unlink, is about to
# unlink the next owner's lock. Between copies like this one none of these can happen: a takeover never touches the
# directory while another one of this copy may be live (it holds the flock while it does anything to it); a release
# checks that its wrapper lives and unlinks under the same flock (one orphaned between the two still holds that flock,
# so no takeover of this copy acts before its unlink); a takeover reclaims a directory made by an older copy only once
# that one's pid is gone (or it has none) and it has not changed for 60 s, checked just before it is moved; and one
# whose recorded pid is alive (an older copy's holder that is stopped, or whose pid was reused) holds every takeover off
# until it goes (waiters exit 75 after LOCK_WAIT_S). (5) The lock's owner pid is trusted: a dead owner whose pid was
# reused counts as alive until that process exits (waiters exit 75 after LOCK_WAIT_S); and a waiter stopped (e.g.
# SIGSTOP) for over 60 s right between creating the lock and writing its line can lose the lock to a takeover and still
# run its command when it resumes. (6) Liveness is the wrapper's pid, not the command's: the command is our child, so
# the wrapper's death by SIGKILL, or by a fault signal it does not trap (SEGV, BUS, ILL, FPE; on Linux also the
# real-time signals), leaves the command running while the lock counts as stale or is released, and the next waiter runs
# beside it. Stop a run by ending its command (its pid or its process group: kill -TERM -<pgid>); the wrapper then
# releases the lock. A trapped signal to the wrapper itself waits for the command to end.
#
# Before running <cmd> it also requires >= MIN_FREE_GB (default 6) reclaimable memory (scripts/lib/platform.sh: macOS
# free+inactive+speculative pages from vm_stat, Linux MemAvailable) and no stray Playwright browser (chrome-headless-shell,
# or Playwright's Firefox: its binary lives under ms-playwright/firefox-<build>/), matched on the executable, not the
# command text (procs_by_exe in scripts/lib/platform.sh; QED64's harness has the same regex under pgrep -fl, so it still
# counts a shell that mentions the name). A process list that cannot be read counts as a stray. It waits up to
# COOLDOWN_WAIT_S (default 3600) for both. Exit codes: 75 lock wait timed out, 76 cooldown refused, 2 usage, 141 a status
# line could not be written (see say); a trapped signal once the lock is taken: 128 + its number (INT and TERM: 130),
# after the command (or the cooldown step) has ended, and the command's own code is then not reported; otherwise the
# command's own exit code.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib/platform.sh"   # reclaimable_gib, procs_by_exe, AWAKE (caffeinate -i on macOS only)
DEFAULT_DIR="$HOME/.cache/host-browser-lock"
LOCK_DIR="${BROWSER_LOCK_DIR:-$DEFAULT_DIR}"
LOCK="${BROWSER_LOCK_FILE:-$LOCK_DIR/browser.lock}"
if [ "${1:-}" = --print-lock ]; then echo "$LOCK"; exit 0; fi
# say: our status lines. A failed write ends us (exit 141, as the default SIGPIPE would; the EXIT trap still releases):
# with SIGPIPE ignored when we were started, bash 3.2 went on after the failed echo and every later subshell flushed
# the line into its output, so the cooldown read it as stray browsers and held the lock for COOLDOWN_WAIT_S. Defined
# before its first use: a call above it ran macOS's /usr/bin/say (text to speech) instead
say() { printf '%s\n' "$*" || exit 141; }
QUEUE="$LOCK.queue"         # FIFO tickets
LANE="${1:-}"
# one word: the lock line is "<lane> <pid> <time>" and its pid is found by position (lock_pid), so a lane "a b" made
# every other waiter read the LIVE lock's pid as "b", count it as stale and remove it (2026-10-27)
case "$LANE" in ''|*[[:space:]]*)
  echo "usage: with-browser-lock.sh <lane> <cmd...> | --print-lock (<lane>: one word, no spaces; got '$LANE')" >&2; exit 2 ;; esac
shift
[ $# -gt 0 ] || { echo "usage: with-browser-lock.sh <lane> <cmd...>" >&2; exit 2; }
WAIT_S="${LOCK_WAIT_S:-3600}"
MIN_FREE_GB="${MIN_FREE_GB:-6}"
mkdir -p "$(dirname "$LOCK")" "$QUEUE" || { say "browser-lock: cannot create $(dirname "$LOCK")" >&2; exit 2; }

reclaimable_gb() { reclaimable_gib 1; }
pstart() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/  */ /g; s/^ //; s/ $//'; }
# lock_pid <lock content>: the owner pid, i.e. the last word of the first line, other than its first word, that is a
# whole number. "<lane> <pid> <time>" gives <pid>; so do a line whose time is missing (a failed `date`) and a lane with
# spaces written by an older copy. Empty if there is none: the takeover then goes by the lock's age (TAKEOVER_PL).
lock_pid() { printf '%s\n' "$1" | awk 'NR == 1 { for (i = NF; i >= 2; i--) if ($i ~ /^[0-9]+$/) { print $i; break } } { exit }'; }
# TAKEOVER_PL <lock> [pause]: the stale-lock takeover (see the header). Holding the flock and then the directory mutex,
# it reads the lock and removes it if it is stale, i.e. if its owner pid (found as lock_pid does) is gone, or if it
# names none and is at least 60 s old. A lock judged stale is read again and removed only if it is still the same file
# with the same line: an owner alive at the first read may have released it since and a new waiter taken it, while a
# stale lock that is unchanged can no longer be released (release() checks and removes only its own lock, never a
# pid-less one, in one process holding the same flock: RELEASE_PL), only taken over, and the mutexes keep other
# takeovers out. Exit 0 removed (event printed on stdout), 4 the lock was gone, 3 not stale or changed, 1 another
# takeover (or a release) holds a mutex, 2 error; the reason for 1-3 is printed on stderr. A second argument (tests only: lockfifo.sh
# runs this program by itself) pauses that many seconds between the first read and the check. INT/TERM/HUP are blocked
# for its few milliseconds; a SIGKILL leaves the directory with the marker 'flk', which the next takeover reclaims at
# once: the flock it then holds shows that the directory's maker is gone. On its way out it first renames the directory
# to <lock>.takeover.gone.<pid> and empties that, so a SIGKILL there never leaves an unmarked <lock>.takeover (it can
# leave the inert .gone.<pid>, which nothing reads). A directory without the marker is an older copy's (or one killed
# before writing the marker), reclaimed once its pid is gone (or it has none) and it has not changed for 60 s, checked
# just before it is moved aside; a moved directory that turns out not to be the one judged is put back if its place is
# free.
TAKEOVER_PL='use strict; use warnings; use Fcntl qw(:flock); use POSIX ();
my ($L, $PAUSE) = @ARGV; my $T = "$L.takeover"; my $MIN = 60; my $have = 0;
$PAUSE = 0 unless defined $PAUSE && $PAUSE =~ /^\d+(\.\d+)?\z/;
POSIX::sigprocmask(POSIX::SIG_BLOCK(), POSIX::SigSet->new(POSIX::SIGINT(), POSIX::SIGTERM(), POSIX::SIGHUP()));
sub why { print STDERR @_, "\n"; }
sub alive { my ($p) = @_; return (kill(0, $p) || $!{EPERM}) ? 1 : 0; }
sub slurp { my ($f) = @_; open(my $h, "<", $f) or return ""; local $/; my $c = <$h>; return defined $c ? $c : ""; }
sub show { my ($s) = @_; $s =~ s/[^\x20-\x7e]/?/g; return length($s) > 120 ? substr($s, 0, 120) . "..." : $s; }
sub done { if ($have) { my $g = "$T.gone.$$"; my $d = rename($T, $g) ? $g : $T; unlink("$d/pid", "$d/flk"); rmdir($d); }
  exit($_[0]); }
open(my $m, ">>", "$T.flk") or do { why("cannot open the takeover mutex $T.flk: $!"); exit 2 };
flock($m, LOCK_EX | LOCK_NB) or do { why("another takeover or a release holds $T.flk"); exit 1 };
unless (mkdir($T)) {
  my @st = stat($T);
  if (@st) {
    my $mine = -e "$T/flk"; my $p = slurp("$T/pid"); $p =~ s/\s+\z//; my $age = time - $st[9];
    my $pid = ($p =~ /^\d+\z/) ? $p : "";
    if (!$mine) {
      if ($pid ne "" && alive($pid)) { why("takeover mutex $T is held by pid $pid"); exit 1 }
      if ($age < $MIN) { why("takeover mutex $T, left by ", ($pid ne "" ? "dead pid $pid" : "a holder that wrote no pid"),
        ", is ${age}s old (reclaimed at ${MIN}s)"); exit 1 }
    }
    my $tmp = "$T.dead.$$";
    if (rename($T, $tmp)) {
      my @mv = stat($tmp);
      if (@mv && $mv[0] == $st[0] && $mv[1] == $st[1]) {
        unlink("$tmp/pid", "$tmp/flk"); rmdir($tmp) or system("rm", "-rf", $tmp);
        print "browser-lock: reclaimed a takeover mutex left by ", ($mine ? "a killed takeover of this copy (pid " .
          ($pid ne "" ? $pid : "not written") . ")" : $pid ne "" ? "dead pid $pid" : "a holder that wrote no pid"), "\n";
      } else {
        rename($tmp, $T) unless -e $T; system("rm", "-rf", $tmp) if -e $tmp;
        why("takeover mutex $T was replaced while being reclaimed"); exit 1;
      }
    }
  }
  mkdir($T) or do { why("takeover mutex $T is held"); exit 1 };
}
$have = 1;
# the pid file names the WAITER (BROWSER_LOCK_TKO_PID, our caller), which outlives this program: an older copy that read
# a pid of ours gone milliseconds later took our next, live directory for an abandoned one and moved it (2026-10-27)
my $who = (($ENV{BROWSER_LOCK_TKO_PID} // "") =~ /^\d+\z/) ? $ENV{BROWSER_LOCK_TKO_PID} : $$;
{ my $h; open($h, ">", "$T/flk") and close($h); open($h, ">", "$T/pid") and print($h "$who\n") and close($h); }
my $lh; unless (open($lh, "<", $L)) { done(4) if $!{ENOENT}; why("cannot read $L: $!"); done(2) }
my @ls = stat($lh); my $c = do { local $/; my $x = <$lh>; defined $x ? $x : "" }; close($lh);
$c =~ s/\n+\z//;
my @f = split(" ", (split(/\n/, $c))[0] // ""); my $op = "";
for (my $i = $#f; $i >= 1; $i--) { if ($f[$i] =~ /^\d+\z/) { $op = $f[$i]; last } }
select(undef, undef, undef, $PAUSE) if $PAUSE > 0;
my $r;
if ($op ne "") {
  if (alive($op)) { why("owner pid $op is alive"); done(3) }
  $r = "owner pid $op is gone";
} else {
  my $age = @ls ? time - $ls[9] : 0;
  if ($age < $MIN) { why("it names no owner pid; that is stale once unchanged for ${MIN}s (now ${age}s)"); done(3) }
  $r = "it names no owner pid and has not changed for ${age}s";
}
# read it again, now that it is judged stale: removing what the first read saw removed the LIVE lock of a waiter that
# took it after an owner alive at that read had released it (a takeover paused between its read and its check at a
# handoff, 2026-10-27). Unchanged now, it can no longer be released (RELEASE_PL needs the flock we hold), only taken
# over (see above)
my @s2 = stat($L); done(4) unless @s2;
my $c2 = slurp($L); $c2 =~ s/\n+\z//;
unless (@ls && $s2[0] == $ls[0] && $s2[1] == $ls[1] && $c2 eq $c) { why("the lock changed while it was judged"); done(3) }
unlink($L) or do { why("cannot remove $L: $!"); done(2) };
print "browser-lock: stale lock (", show($c), "): $r; removed under the takeover mutex\n";
done(0);'
# RELEASE_PL <lock> <owner pid> [pause]: remove the lock if its owner pid (found as lock_pid does) is <owner pid>, while
# holding the flock on <lock>.takeover.flk, so no takeover of this copy acts between the check and the unlink, and only
# while <owner pid> is still its parent: orphaned by a SIGKILL of the owner, it leaves the lock (stale) to a takeover
# under the mutexes, so an older copy's takeover, which takes no flock, cannot remove it first and then lose the next
# owner's lock to us (2026-10-27), except in the instant between its last check and its unlink (limit (4)). The flock is retried for up to 10 s (takeovers hold it for milliseconds). Exit 0
# removed, 3 not ours, no lock, or orphaned at the first check, 4 orphaned after it, 1 the flock stayed busy, 2 error. A third argument
# (tests only: lockfifo.sh runs this program by itself) pauses that many seconds after the check, holding the flock.
RELEASE_PL='use strict; use warnings; use Fcntl qw(:flock);
my ($L, $me, $PAUSE) = @ARGV; $PAUSE = 0 unless defined $PAUSE && $PAUSE =~ /^\d+(\.\d+)?\z/;
open(my $m, ">>", "$L.takeover.flk") or exit 2;
my $n = 0; until (flock($m, LOCK_EX | LOCK_NB)) { exit 1 if ++$n > 200; select(undef, undef, undef, 0.05) }
open(my $h, "<", $L) or exit 3; my $c = do { local $/; my $x = <$h>; defined $x ? $x : "" }; close($h);
my @f = split(" ", (split(/\n/, $c))[0] // ""); my $op = "";
for (my $i = $#f; $i >= 1; $i--) { if ($f[$i] =~ /^\d+\z/) { $op = $f[$i]; last } }
exit 3 unless $op ne "" && $op eq $me && getppid() == $me;
select(undef, undef, undef, $PAUSE) if $PAUSE > 0;
exit 4 unless getppid() == $me;
unlink($L) or exit 2; exit 0;'

# ---- FIFO ticket -----------------------------------------------------------------------------------------------
TICKET=""; MYSTART=""; TAB=$'\t'
if [ "${FAIR:-1}" != 0 ]; then
  TICKET="$QUEUE/$(perl -MTime::HiRes=time -e 'printf "%017.6f", time')-$$"
fi
# file_ticket: (re)write our ticket atomically (written beside the queue, then renamed into it), so a scanner never
# sees a half-written ticket. Our start time is retried on each call while ps cannot report it, and recorded as '-'
# meanwhile; the loop calls this at every poll until it is known, which also keeps the ticket's mtime fresh (a '-'
# ticket counts as live only while fresh, about 60 s: see head_ticket). A ticket removed under us is re-filed under the
# same name at our next poll (one poll interval, about 2 s, later: see the loop), which gives back our place; until
# then, a later waiter that finds the lock free can take it first.
file_ticket() { [ -n "$TICKET" ] || return 0; [ -n "$MYSTART" ] || MYSTART="$(pstart $$)"
  printf '%s\t%s\t%s\n' "$$" "${MYSTART:--}" "$LANE" > "$LOCK.tkt.$$" && mv -f "$LOCK.tkt.$$" "$TICKET"; }
file_ticket
drop_ticket() { [ -n "$TICKET" ] && rm -f "$TICKET"; rm -f "$LOCK.tkt.$$"; TICKET=""; }
# head_ticket: the oldest live ticket, i.e. one whose process is still the one that filed it; older tickets that are not
# live are removed on the way. Live: pid alive, and either its recorded start time equals ps's now, or ps cannot report
# it now (ps can fail under memory pressure: limit (1) in the header), or the start is unknown and the ticket is fresh
# (see below) or its age cannot be read. An unknown start is '-' from this copy, whose owner re-files the ticket at
# every poll (see file_ticket), or empty from older copies, which re-file only after a removal, if at all. Removed: pid
# gone; alive with a DIFFERENT start time (a reused pid); start unknown and the ticket not fresh, because its owner is
# not polling (killed and its pid reused, or stopped; a stopped owner of this copy re-files it when it resumes) or is
# an older copy, which does not keep it fresh and so can lose its place about 60 s after filing (older copies remove
# '-' and empty-start tickets themselves when a scan reaches them, at least while their own ps works). Dropping a live
# waiter's ticket let a later arrival take the lock out of turn (seen 2026-10-25). An unreadable ticket (gone, or not
# yet a whole line) or a pid-less one is skipped and left in place: it neither holds back the queue nor is removed.
head_ticket() {
  local t line pid st now
  for t in $(ls "$QUEUE" 2>/dev/null | LC_ALL=C sort); do
    IFS= read -r line 2>/dev/null < "$QUEUE/$t" || continue
    # fields: pid TAB start TAB lane. Split by hand: `read` with IFS=TAB would merge an empty start into the lane.
    pid="${line%%"$TAB"*}"; st="${line#"$pid"}"; st="${st#"$TAB"}"; st="${st%%"$TAB"*}"
    [ -n "$pid" ] || continue
    if kill -0 "$pid" 2>/dev/null; then
      if [ -z "$st" ] || [ "$st" = - ]; then
        # start unknown: live while fresh, i.e. while `find -mmin -1` prints it: GNU find if it was modified under 60 s
        # ago; macOS /usr/bin/find works in whole seconds and still prints it at 60 s (not at 61 s); both print it if
        # its mtime is in the future (limit (3)). The "ok" shows that find ran, so it is removed only on find's word (a
        # find that could not run, e.g. no fork under memory pressure, or a ticket that just went, counts as live for
        # this poll)
        case "$(find "$QUEUE/$t" -mmin -1 2>/dev/null && echo ok)" in ok) ;; *) echo "$t"; return 0 ;; esac
      else
        now="$(pstart "$pid")"
        if [ -z "$now" ] || [ "$now" = "$st" ]; then echo "$t"; return 0; fi
      fi
    fi
    rm -f "$QUEUE/$t"
  done
  return 1
}

t0=$(date +%s)
lastmsg=0
trap 'drop_ticket; exit 130' INT TERM
trap 'drop_ticket' EXIT
while :; do
  # our ticket removed under us, or filed while ps could not report our start time: (re)file it now, whatever the lock
  # state, so a removal costs our place for at most one poll, and a '-' ticket stays fresh (see file_ticket)
  if [ -n "$TICKET" ] && { [ ! -e "$TICKET" ] || [ -z "$MYSTART" ]; }; then file_ticket; fi
  # With the queue on, try to create the lock only right after seeing it free with our ticket at the head. Trying also
  # when this poll saw it held let a waiter take it the moment it was released, without checking the queue (start
  # order w1,w2,w3,w4,w6,w5 seen 2026-10-27; reproduced 3/3 with a 0.3 s sleep added before the create).
  try=1
  if [ -n "$TICKET" ]; then
    if [ -e "$LOCK" ]; then try=0
    else
      h="$(head_ticket)"
      if [ -n "$h" ] && [ "$QUEUE/$h" != "$TICKET" ]; then
        if [ $(( $(date +%s) - lastmsg )) -ge 60 ]; then
          say "browser-lock: lock free, but deferring to an earlier waiter ($(cut -f3 "$QUEUE/$h" 2>/dev/null) pid $(cut -f1 "$QUEUE/$h" 2>/dev/null))"; lastmsg=$(date +%s); fi
        if [ $(( $(date +%s) - t0 )) -ge "$WAIT_S" ]; then say "browser-lock: gave up after ${WAIT_S}s (deferring to earlier waiters)" >&2; exit 75; fi
        sleep 1; continue
      fi
    fi
  fi
  if [ "$try" = 1 ] && ( set -o noclobber; echo "$LANE $$ $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOCK" ) 2>/dev/null; then break; fi
  owner="$(cat "$LOCK" 2>/dev/null || true)"; opid="$(lock_pid "$owner")"; why=""; nap=2
  if [ -e "$LOCK" ] && { [ -z "$opid" ] || ! kill -0 "$opid" 2>/dev/null; }; then
    # it may be stale (owner pid gone, or none): the takeover decides under its mutexes, and removes it if so. Its
    # events go to our stdout, its reason for not removing it into $why. Removed (0) or gone (4): retry at once.
    { why="$(BROWSER_LOCK_TKO_PID=$$ perl -e "$TAKEOVER_PL" "$LOCK" 2>&1 1>&3 3>&-)"; } 3>&1; trc=$?
    case "$trc" in 0|4) continue ;; 1) nap=1 ;; esac
  fi
  # every wait, a stale-looking lock's included, is bounded by LOCK_WAIT_S and reported once a minute (a stale branch
  # that went straight back to its poll once let a waiter wait forever and silently behind a takeover mutex left with no
  # pid, 2026-10-27)
  if [ $(( $(date +%s) - t0 )) -ge "$WAIT_S" ]; then say "browser-lock: gave up after ${WAIT_S}s; held by: $owner${why:+ ($why)}" >&2; exit 75; fi
  if [ $(( $(date +%s) - lastmsg )) -ge 60 ]; then say "browser-lock: held by '$owner'${why:+ ($why)}; waiting"; lastmsg=$(date +%s); fi
  sleep "$nap"
done
drop_ticket
# release: RELEASE_PL removes the lock if it is still ours, checking and unlinking in one process under the takeover
# flock. A check in bash followed by a separate `rm` let an rm orphaned by a SIGKILL of its owner remove the LIVE lock
# of the next owner after a takeover (2026-10-27). If the flock stays busy it leaves the lock, which is stale once we
# have exited: the next waiter takes it over.
TRAPPED=""   # the signals trapped below; ignored while release() runs (we are exiting)
release() { [ -z "$TRAPPED" ] || trap '' $TRAPPED; perl -e "$RELEASE_PL" "$LOCK" "$$"; case $? in
  0) say "browser-lock: released ($LANE)" ;;
  1) say "browser-lock: the takeover mutex stayed busy; lock left for a takeover (stale once we exit) ($LANE)" >&2 ;;
  3) say "browser-lock: WARNING: at release the lock was no longer ours ($LANE): it was removed or replaced while we held it" >&2 ;; esac; }
trap release EXIT
# Every catchable signal whose default action ends a process, except the synchronous faults, is trapped: bash defers
# it until the command ends, then exits with 128 + its number (INT and TERM: 130, as before) through the EXIT trap
# (release). An untrapped HUP, ALRM, USR1, USR2, PIPE, ABRT, XCPU, ... made bash run release at once, or die without
# it (QUIT, PROF), while the command kept running, so the next waiter ran beside it (2026-10-27). SIGKILL cannot be
# trapped, and SEGV, BUS, ILL and FPE are left alone (a trap on a real fault can loop on it): limit (6). IO, PWR and
# STKFLT end a process only on Linux (on macOS IO is ignored), so they are trapped there only.
trap 'exit 130' INT TERM; TRAPPED="INT TERM"
# shellcheck disable=SC2064  # the exit code is meant to be fixed when the trap is set
trap_exit() { local sg n; for sg in "$@"; do
  n="$(kill -l "$sg" 2>/dev/null)" && trap "exit $(( 128 + n ))" "$sg" 2>/dev/null && TRAPPED="$TRAPPED $sg"; done; }
trap_exit HUP QUIT ALRM USR1 USR2 PIPE TRAP ABRT EMT SYS XCPU XFSZ VTALRM PROF
[ "$(uname -s)" != Linux ] || trap_exit IO PWR STKFLT
say "browser-lock: acquired by $LANE pid $$ ($LOCK)"

# Cooldown: wait (default up to COOLDOWN_WAIT_S=3600 s) for memory and for any other Playwright browser on the host
# (other sessions share this machine), logging the reason once a minute; exit 76 only after the full wait.
COOLDOWN_WAIT_S="${COOLDOWN_WAIT_S:-3600}"; c0=$(date +%s); last=0
# Test-only escape hatch: honoured ONLY when the lock is not the default host lock, so real runs always get the cooldown.
if [ "$LOCK" != "$DEFAULT_DIR/browser.lock" ] && [ "${SKIP_COOLDOWN_FOR_TEST:-0}" = 1 ]; then COOLDOWN_WAIT_S=-1; fi
while :; do
  strays="$(procs_by_exe 'chrome-headless-shell|ms-playwright/firefox-')"; [ $? -lt 2 ] || strays='ps failed: cannot tell'
  free="$(reclaimable_gb)"
  if [ "$COOLDOWN_WAIT_S" = -1 ] || { [ -z "$strays" ] && awk -v f="$free" -v m="$MIN_FREE_GB" 'BEGIN{exit !(f>=m)}'; }; then
    say "browser-lock: cooldown ok: ${free} GiB reclaimable, no chrome-headless-shell or Playwright Firefox"; break
  fi
  el=$(( $(date +%s) - c0 ))
  [ "$el" -ge "$COOLDOWN_WAIT_S" ] && { say "browser-lock: cooldown refused after ${el}s: ${free} GiB reclaimable; strays: ${strays:-none}" >&2; exit 76; }
  if [ $(( el - last )) -ge 60 ] || [ "$last" = 0 ]; then last=$el; [ "$last" = 0 ] && last=1
    say "browser-lock: cooldown waiting (${el}s): ${free} GiB reclaimable (need ${MIN_FREE_GB}); other Playwright browser processes: $(echo "$strays" | grep -vc '^$')"; fi
  sleep 5
done

export HOST_BROWSER_LOCK_FILE="$LOCK"
# Keep the host awake while the browser runs: a headless Chrome holds no idle-sleep assertion, and an idle Mac once
# slept 988 s in the middle of a UX run, freezing the browser and the test clock. caffeinate -i only holds a
# process-scoped PreventUserIdleSystemSleep assertion for the command's lifetime; it changes no system setting. AWAKE
# (scripts/lib/platform.sh) is (caffeinate -i) on macOS and empty elsewhere (and with NO_CAFFEINATE=1).
if [ ${#AWAKE[@]} -gt 0 ]; then
  say "browser-lock: running under ${AWAKE[*]} (no idle sleep while the browser runs)"
  "${AWAKE[@]}" "$@"
else
  "$@"
fi
rc=$?
say "browser-lock: command exited rc=$rc"
exit $rc
