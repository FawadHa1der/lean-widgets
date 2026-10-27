# platform.sh — the few host facilities that differ between macOS (where this project was built) and Linux (GitHub
# runners, the node:26-bookworm image). Source it from any bash script:   . "<path to>/scripts/lib/platform.sh"
# scripts/lib/platform.mjs is the same for Node.
#
#   PLATFORM                 darwin | linux | other (uname -s, lower-cased)
#   reclaimable_gib [prec]   memory a new heavy process can get, in GiB, printed with <prec> decimals (default 1):
#                              macOS: free + inactive + speculative pages (vm_stat), as QED64's harness measures it;
#                              Linux: MemAvailable (/proc/meminfo); other: 0 (callers then refuse, never guess)
#   clone_file <src> <dst>   copy one file as a copy-on-write clone where the file system can (new inode, never a hard
#                              link): macOS `cp -c` (APFS clonefile), Linux `cp --reflink=auto` (btrfs/xfs reflink, else a
#                              plain copy); never fails over to a link
#   clone_tree <src> <dst>   the same for a directory tree (cp -cR / cp -R --reflink=auto); <dst> must not exist
#   file_size <path>         size in bytes (stat -f %z / stat -c %s)
#   file_nlink <path>        hard-link count (stat -f %l / stat -c %h)
#   file_mtime <path>        modification time, human readable (stat -f %Sm / date -r)
#   AWAKE                    array: a process-scoped "do not idle-sleep" prefix for long commands. macOS: (caffeinate -i)
#                              unless NO_CAFFEINATE=1; elsewhere empty (a CI runner or a Linux host does not idle-sleep
#                              a running job the way a laptop does). Use as: "${AWAKE[@]+"${AWAKE[@]}"}" cmd …
#   NODE_TOOL                array: the node command for our short-lived headless tools, node --no-concurrent-sparkplug.
#                              node 26.3 deadlocked in process.exit after the verdict in 14 of 30 runs of one control
#                              (2026-10-27): the main thread joins a V8 concurrent Sparkplug job that waits for a GC only
#                              the main thread can run (DisposePlatform -> uv_thread_join); with that background compiler
#                              off, 0 of 30 (code is still baseline-compiled, on the main thread). Use as: "${NODE_TOOL[@]}" x.mjs …
case "$(uname -s)" in Darwin) PLATFORM=darwin ;; Linux) PLATFORM=linux ;; *) PLATFORM=other ;; esac

reclaimable_gib() {
  local prec="${1:-1}"
  case "$PLATFORM" in
    darwin) vm_stat | awk -v p="$prec" '/page size of/ {ps=$8} /Pages free/ {f=$3} /Pages inactive/ {i=$3} /Pages speculative/ {s=$3}
              END {gsub(/\./,"",f); gsub(/\./,"",i); gsub(/\./,"",s); printf "%.*f", p, (f+i+s)*ps/1073741824}' ;;
    linux) awk -v p="$prec" '/^MemAvailable:/ {printf "%.*f", p, $2/1048576; found=1} END {if (!found) printf "%.*f", p, 0}' /proc/meminfo ;;
    *) printf '%.*f' "$prec" 0 ;;
  esac
}
# free_inactive_gib: the stricter integer figure showcase.sh / preflight-overlays.sh guard on (macOS: free + inactive
# pages only, truncated; Linux: MemAvailable, truncated)
free_inactive_gib() {
  case "$PLATFORM" in
    darwin) vm_stat | awk '/page size of/ {ps=$8} /Pages free/ {f=$3} /Pages inactive/ {i=$3} END {gsub(/\./,"",f); gsub(/\./,"",i); printf "%d", (f+i)*ps/1073741824}' ;;
    linux) awk '/^MemAvailable:/ {printf "%d", $2/1048576; found=1} END {if (!found) printf "0"}' /proc/meminfo ;;
    *) printf '0' ;;
  esac
}
clone_file() {
  case "$PLATFORM" in darwin) cp -c "$1" "$2" ;; linux) cp --reflink=auto "$1" "$2" ;; *) cp "$1" "$2" ;; esac
}
clone_tree() {
  case "$PLATFORM" in darwin) cp -cR "$1" "$2" ;; linux) cp -R --reflink=auto "$1" "$2" ;; *) cp -R "$1" "$2" ;; esac
}
file_size() { case "$PLATFORM" in darwin) stat -f %z "$1" ;; *) stat -c %s "$1" ;; esac; }
file_nlink() { case "$PLATFORM" in darwin) stat -f %l "$1" ;; *) stat -c %h "$1" ;; esac; }
file_mtime() { case "$PLATFORM" in darwin) stat -f %Sm "$1" ;; *) date -r "$1" ;; esac; }
NODE_TOOL=(node --no-concurrent-sparkplug)
AWAKE=()
if [ "$PLATFORM" = darwin ] && command -v caffeinate >/dev/null 2>&1 && [ "${NO_CAFFEINATE:-0}" != 1 ]; then AWAKE=(caffeinate -i); fi
