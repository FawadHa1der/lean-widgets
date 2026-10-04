#!/usr/bin/env bash
# assert-untouched.sh — BUILD-PLAN §2 S0.6.
#
# Proves that a stage wrote nothing into the read-only trees.
#
#   scripts/assert-untouched.sh stamp [NAME]   record HEAD + status --porcelain + diff hash of each git
#                                              tree, and touch out/.stage-stamp[-NAME] (mtime reference)
#   scripts/assert-untouched.sh check [NAME]   compare against the stamp, then list everything newer
#                                              than the stamp under each read-only tree and classify it:
#                                                WARN  the .git directory itself (or a directory inside
#                                                      .git) has a newer mtime, or a transient *.lock file
#                                                      inside .git is newer: lock-file churn from some
#                                                      git process that did not pass --no-optional-locks
#                                                      (creating + deleting .git/index.lock bumps .git's
#                                                      mtime but changes no content)
#                                                FAIL  any other file inside .git is newer (index, refs,
#                                                      objects, HEAD, config, logs, ...)
#                                                FAIL  any working-tree file or directory is newer
#                                              Exit 0 = UNTOUCHED (WARNs allowed), 1 = CHANGED,
#                                              2 = usage / no stamp.
#   scripts/assert-untouched.sh restate [NAME] recompute DIFFHASH under the current method, keeping the
#                                              stamp mtime; refused if any HEAD/status line changed
#
# NAME lets concurrent lanes keep their own stamps (default: none -> out/.stage-stamp).
# Every git call uses --no-optional-locks so the check itself never creates .git/index.lock.
set -u
export GIT_OPTIONAL_LOCKS=0

. "$(cd "$(dirname "$0")" && pwd)/lib/env.sh"   # SC, REPO_ROOT, WS, Q, K, KR, LG: scripts/lib/env.sh
# The read-only trees come from the environment / .env.local. QED64_REPO and QED64_KERNEL_BUILD are required; the
# kernel source and lean4game checkouts are watched when configured (QED64_KERNEL_SRC, LEAN4GAME_DIR) and the output
# says which trees are not configured. The widget sources are this repository's packages/ (WS): only that subtree
# is watched (git state limited to the pathspec packages/), because qed64-showcase/ itself lives in the same
# repository and writes its own out/.
need QED64_REPO QED64_KERNEL_BUILD
GIT_TREES=("$Q")                       # HEAD + porcelain + diff hash compared to the stamp
MTIME_TREES=("$Q" "$K")                # nothing may be newer than the stamp (except .git lock churn)
NOT_CONFIGURED=()
if [ -n "$KR" ]; then need QED64_KERNEL_SRC; GIT_TREES+=("$KR"); MTIME_TREES+=("$KR"); else NOT_CONFIGURED+=(QED64_KERNEL_SRC); fi
if [ -n "$LG" ]; then need LEAN4GAME_DIR; GIT_TREES+=("$LG"); else NOT_CONFIGURED+=(LEAN4GAME_DIR); fi
GIT_TREES+=("$WS"); MTIME_TREES+=("$WS")
# git state of a tree: the whole repository, except for WS (the packages/ subtree of this repository)
git_scope() { if [ "$1" = "$WS" ]; then printf '%s\n' "$REPO_ROOT" packages; else printf '%s\n' "$1" .; fi; }
MAX_LIST=20                             # newer paths printed per tree and class

cmd="${1:-}"; name="${2:-}"
suffix=""; [ -n "$name" ] && suffix="-$name"
STAMP="$SC/out/.stage-stamp$suffix"
STATE="$SC/out/.stage-stamp$suffix.state"

content_hash() {
  local t r spec rec st p
  { read -r r; read -r spec; } < <(git_scope "$1")
  git --no-optional-locks -C "$r" status --porcelain=v1 -z --untracked-files=all -- "$spec" 2>/dev/null |
  while IFS= read -r -d '' rec; do
    st="${rec:0:2}"; p="${rec:3}"
    case "$st" in R*|C*) IFS= read -r -d '' _orig ;; esac   # -z: rename source follows as its own field
    if [ -f "$r/$p" ]; then printf '%s %s %s\n' "$st" "$(shasum -a 256 < "$r/$p" | cut -c1-64)" "$p"
    else printf '%s - %s\n' "$st" "$p"; fi
  done | shasum -a 256 | cut -c1-64
}

state() {
  local r spec
  for t in "${GIT_TREES[@]}"; do
    { read -r r; read -r spec; } < <(git_scope "$t")
    echo "### $t"
    if [ "$spec" = . ]; then echo "HEAD $(git --no-optional-locks -C "$r" rev-parse HEAD 2>&1)"
    else echo "TREE $spec $(git --no-optional-locks -C "$r" rev-parse "HEAD:$spec" 2>&1)"; fi   # commits elsewhere in the repo do not count
    git --no-optional-locks -C "$r" status --porcelain=v1 --untracked-files=all -- "$spec" 2>&1
    # content of every modified/untracked path (lean4game / widgets-v4.34 carry pre-existing edits).
    # NOT `git diff HEAD`: that porcelain refreshes and REWRITES .git/index when a dirty file's stat
    # info is racy, even under --no-optional-locks / GIT_OPTIONAL_LOCKS=0 (git 2.54, verified on a
    # sandbox repo). Hashing the working-tree bytes of the status-listed paths is read-only.
    echo "DIFFHASH $(content_hash "$t")"
  done
}

# classify every path newer than the stamp under tree $1; prints lines, returns 1 on FAIL
classify_tree() {
  local t="$1" warn_n=0 fail_git_n=0 fail_wt_n=0 rel
  local warn_list fail_git_list fail_wt_list
  warn_list="$(mktemp)"; fail_git_list="$(mktemp)"; fail_wt_list="$(mktemp)"
  while IFS= read -r -d '' p; do
    rel="${p#"$t"}"; rel="${rel#/}"
    case "$rel" in
      .git)                         echo ".git/ (directory mtime)" >> "$warn_list"; warn_n=$((warn_n+1)) ;;
      .git/*)
        if [ -d "$p" ]; then          echo "$rel/ (directory mtime)" >> "$warn_list"; warn_n=$((warn_n+1))
        elif [[ "$rel" == *.lock ]]; then echo "$rel (transient lock file present)" >> "$warn_list"; warn_n=$((warn_n+1))
        else                          echo "$rel" >> "$fail_git_list"; fail_git_n=$((fail_git_n+1)); fi ;;
      *)                            echo "$rel" >> "$fail_wt_list"; fail_wt_n=$((fail_wt_n+1)) ;;
    esac
  done < <(find "$t" -newer "$STAMP" -print0 2>/dev/null)
  local rc=0
  if [ $fail_wt_n -gt 0 ]; then
    echo "FAIL $fail_wt_n working-tree path(s) newer than stamp under $t:"; head -n $MAX_LIST "$fail_wt_list" | sed 's/^/       /'; rc=1
  fi
  if [ $fail_git_n -gt 0 ]; then
    echo "FAIL $fail_git_n non-lock file(s) inside .git newer than stamp under $t:"; head -n $MAX_LIST "$fail_git_list" | sed 's/^/       /'; rc=1
  fi
  if [ $warn_n -gt 0 ]; then
    echo "WARN .git lock-file churn under $t ($warn_n path(s); a git process without --no-optional-locks created/removed *.lock; no git content changed):"
    head -n $MAX_LIST "$warn_list" | sed 's/^/       /'
  fi
  if [ $rc -eq 0 ] && [ $warn_n -eq 0 ]; then echo "OK   no file newer than stamp under $t"
  elif [ $rc -eq 0 ]; then echo "OK   no working-tree or non-lock .git file newer than stamp under $t"; fi
  rm -f "$warn_list" "$fail_git_list" "$fail_wt_list"
  return $rc
}

case "$cmd" in
  stamp)
    mkdir -p "$SC/out"
    state > "$STATE"
    # mtime reference: written AFTER state capture, so nothing we just read counts as "newer"
    : > "$STAMP"; touch "$STAMP"
    echo "STAMPED $(date -u +%Y-%m-%dT%H:%M:%SZ) -> $STAMP"
    grep -E '^(### |HEAD |TREE )' "$STATE" | paste - - | sed 's/^### /  /'
    [ ${#NOT_CONFIGURED[@]} -eq 0 ] || echo "  not configured (not watched): ${NOT_CONFIGURED[*]}"
    exit 0 ;;
  restate)
    # format migration only: recompute the state file under the CURRENT DIFFHASH method while keeping the
    # stamp's mtime reference; refused unless every HEAD/status line equals the recorded state.
    [ -f "$STAMP" ] && [ -f "$STATE" ] || { echo "NO STAMP at $STAMP"; exit 2; }
    now="$(mktemp)"; state > "$now"
    if diff <(grep -v '^DIFFHASH ' "$STATE") <(grep -v '^DIFFHASH ' "$now") >/dev/null; then
      cp "$STATE" "$STATE.prev"; cp "$now" "$STATE"; rm -f "$now"
      echo "RESTATED $STATE (HEAD/status lines unchanged; DIFFHASH recomputed; stamp mtime $(stat -f '%Sm' "$STAMP") kept)"; exit 0
    else echo "REFUSED: HEAD/status changed since stamp"; diff <(grep -v '^DIFFHASH ' "$STATE") <(grep -v '^DIFFHASH ' "$now"); rm -f "$now"; exit 1; fi ;;
  check)
    if [ ! -f "$STAMP" ] || [ ! -f "$STATE" ]; then echo "NO STAMP at $STAMP (run: $0 stamp $name)"; exit 2; fi
    fail=0
    now="$(mktemp)"; state > "$now"
    if diff -u "$STATE" "$now" > "$now.diff"; then
      echo "OK   git HEAD/status/diff unchanged for: ${GIT_TREES[*]}"
    else
      echo "FAIL git state changed since stamp:"; sed 's/^/     /' "$now.diff"; fail=1
    fi
    rm -f "$now" "$now.diff"
    for t in "${MTIME_TREES[@]}"; do classify_tree "$t" || fail=1; done
    [ ${#NOT_CONFIGURED[@]} -eq 0 ] || echo "NOTE not configured, so not watched: ${NOT_CONFIGURED[*]}"
    if [ $fail -eq 0 ]; then echo "VERDICT: UNTOUCHED (stamp $(stat -f '%Sm' "$STAMP"))"; exit 0
    else echo "VERDICT: CHANGED"; exit 1; fi ;;
  *)
    echo "usage: $0 stamp|check|restate [NAME]"; exit 2 ;;
esac
