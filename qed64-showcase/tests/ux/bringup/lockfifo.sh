#!/usr/bin/env bash
# lockfifo.sh — FIFO test for scripts/with-browser-lock.sh, invoked through SEVERAL PATHS that must share one lock:
# the script itself (absolute), the script through a relative path, and any compatibility stub that execs it
# (STUB=<path>, e.g. the stub left at a checkout's old location; default: a scratch stub made here).
# A holder takes the lock for HOLD0_S seconds; then N waiters arrive GAP_S apart, cycling through the paths; each holds
# the lock for HOLD_S seconds and journals "start/end <name> <time>". Passes iff all ran, no two critical sections
# overlap, the start order equals the arrival order, and no lock or ticket is left. Runs against a scratch lock
# directory (BROWSER_LOCK_DIR=<tmp>), never the real host lock; needs no browser.
set -u
SC="$(cd "$(dirname "$0")/../../.." && pwd)"
WRAP="${LOCK_SCRIPT:-$SC/scripts/with-browser-lock.sh}"
N="${N:-6}"; HOLD0_S="${HOLD0_S:-4}"; HOLD_S="${HOLD_S:-1}"; GAP_S="${GAP_S:-0.4}"
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
body() { echo "echo \"start $1 \$(perl -MTime::HiRes=time -e 'printf q(%.4f), time')\" >> '$J'; sleep $2; echo \"end $1 \$(perl -MTime::HiRes=time -e 'printf q(%.4f), time')\" >> '$J'"; }
bash "$WRAP" holder bash -c "$(body holder "$HOLD0_S")" > "$T/holder.log" 2>&1 &
sleep 1
ARR=()
for i in $(seq 1 "$N"); do
  case $(( i % 3 )) in
    1) how=stub; (bash "$STUB" "w$i-$how" bash -c "$(body "w$i" "$HOLD_S")" > "$T/w$i.log" 2>&1 &) ;;
    2) how=abs;  (bash "$WRAP" "w$i-$how" bash -c "$(body "w$i" "$HOLD_S")" > "$T/w$i.log" 2>&1 &) ;;
    0) how=rel;  (cd "$REL_DIR" && ./"$(basename "$WRAP")" "w$i-$how" bash -c "$(body "w$i" "$HOLD_S")" > "$T/w$i.log" 2>&1 &) ;;
  esac
  ARR+=("w$i"); echo "arrived w$i via $how"
  sleep "$GAP_S"
done
# wait for everyone (the waiters are not our children: poll the journal)
for _ in $(seq 1 $(( (HOLD0_S + N * (HOLD_S + 3)) * 2 ))); do [ "$(grep -c '^end ' "$J")" -ge $(( N + 1 )) ] && break; sleep 0.5; done
wait
# the last holder removes the lock right after its command exits: give it up to 10 s before judging "lock left"
for _ in $(seq 1 20); do [ -e "$LOCKF" ] || break; sleep 0.5; done
node -e '
  const fs = require("fs");
  const [jf, n, lockf, qdir, arr] = process.argv.slice(1);
  const lines = fs.readFileSync(jf, "utf8").trim().split("\n").map((l) => l.split(" "));
  const iv = {}; for (const [k, who, t] of lines) { iv[who] = iv[who] || {}; iv[who][k] = +t; }
  const xs = Object.entries(iv).map(([w, v]) => ({ w, s: v.start, e: v.end })).sort((a, b) => a.s - b.s);
  let overlaps = 0; for (let i = 1; i < xs.length; i++) if (xs[i].s < xs[i - 1].e) overlaps++;
  const done = xs.filter((x) => x.s && x.e).length;
  const order = xs.map((x) => x.w).filter((w) => w !== "holder");
  const want = arr.split(",");
  const fifo = JSON.stringify(order) === JSON.stringify(want);
  const left = fs.existsSync(lockf), tickets = fs.existsSync(qdir) ? fs.readdirSync(qdir).length : 0;
  const ok = done === +n + 1 && overlaps === 0 && fifo && !left && tickets === 0;
  console.log(`LOCKFIFO ${ok ? "OK" : "FAIL"}: ${done}/${+n + 1} ran, ${overlaps} overlapping critical sections, start order ${order.join(",")} (arrival ${want.join(",")}: ${fifo ? "FIFO" : "NOT FIFO"}), lock left: ${left}, tickets left: ${tickets}`);
  process.exit(ok ? 0 : 1);
' "$J" "$N" "$LOCKF" "$LOCKF.queue" "$(IFS=,; echo "${ARR[*]}")"; rc=$?
[ $rc = 0 ] || { for f in "$T"/*.log; do echo "== $f"; tail -5 "$f"; done; }
rm -rf "$T"; exit $rc
