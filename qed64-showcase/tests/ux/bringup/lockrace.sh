#!/usr/bin/env bash
# lockrace.sh — race test for scripts/with-browser-lock.sh's stale-lock takeover (bring-up audit minor).
# Plants a stale lock (dead owner pid), then starts N waiters at once; each holds the lock for HOLD_S seconds and
# appends "start <t>" / "end <t>" to a shared journal. Passes iff all N ran and no two critical sections overlap.
# Runs against a scratch copy of the script and a scratch lock directory (BROWSER_LOCK_DIR; never the real host lock);
# needs no browser.
set -u
SC="$(cd "$(dirname "$0")/../../.." && pwd)"
N="${N:-6}"; HOLD_S="${HOLD_S:-1}"
T="$(mktemp -d "${TMPDIR:-/tmp}/lockrace.XXXXXX")"; mkdir -p "$T/scripts" "$T/out"
cp "${LOCK_SCRIPT:-$SC/scripts/with-browser-lock.sh}" "$T/scripts/with-browser-lock.sh"  # LOCK_SCRIPT: test another version
J="$T/journal"; : > "$J"
sh -c 'exit 0' & dead=$!; wait $dead   # a pid that is certainly gone
export BROWSER_LOCK_DIR="$T/out" NO_CAFFEINATE=1
LOCKF="$(bash "$T/scripts/with-browser-lock.sh" --print-lock)"
echo "stale-lane $dead 2000-01-01T00:00:00Z" > "$LOCKF"
now() { perl -MTime::HiRes=time -e 'printf "%.4f\n", time'; }
export -f now 2>/dev/null || true
for i in $(seq 1 "$N"); do
  MIN_FREE_GB=0 LOCK_WAIT_S=300 bash "$T/scripts/with-browser-lock.sh" "racer$i" bash -c "echo \"start racer$i \$(perl -MTime::HiRes=time -e 'printf q(%.4f), time')\" >> '$J'; sleep $HOLD_S; echo \"end racer$i \$(perl -MTime::HiRes=time -e 'printf q(%.4f), time')\" >> '$J'" > "$T/racer$i.log" 2>&1 &
done
wait
grep -h "stale lock\|lock changed\|reclaimed" "$T"/racer*.log | sort | uniq -c
node -e '
  const lines = require("fs").readFileSync(process.argv[1], "utf8").trim().split("\n").map((l) => l.split(" "));
  const iv = {}; for (const [k, who, t] of lines) { iv[who] = iv[who] || {}; iv[who][k] = +t; }
  const xs = Object.entries(iv).map(([w, v]) => ({ w, s: v.start, e: v.end })).sort((a, b) => a.s - b.s);
  let overlaps = 0; for (let i = 1; i < xs.length; i++) if (xs[i].s < xs[i - 1].e) overlaps++;
  const done = xs.filter((x) => x.s && x.e).length;
  console.log(`LOCKRACE ${done === +process.argv[2] && overlaps === 0 ? "OK" : "FAIL"}: ${done}/${process.argv[2]} ran, ${overlaps} overlapping critical sections, lock left: ${require("fs").existsSync(process.argv[3])}`);
  process.exit(done === +process.argv[2] && overlaps === 0 && !require("fs").existsSync(process.argv[3]) ? 0 : 1);
' "$J" "$N" "$LOCKF"; rc=$?
[ $rc = 0 ] || { for f in "$T"/racer*.log; do echo "== $f"; tail -4 "$f"; done; }
rm -rf "$T"; exit $rc
