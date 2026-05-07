#!/usr/bin/env bash
# .NAME        perf-snapshot
# .SYNOPSIS    Capture a one-time performance snapshot: CPU, RAM, swap, disk, top processes, load.
# .PLATFORM    linux
# .CATEGORY    diagnostics
# .USAGE       ./tools/linux/diagnostics/perf-snapshot.sh [-t TOP] [-l]
# .WHEN        Machine feels slow or unresponsive; before/after a fix to compare baseline.

set -uo pipefail

TOP=15
SAVE_LOG=0
while getopts "t:lh" opt; do
    case "$opt" in
        t) TOP="$OPTARG" ;;
        l) SAVE_LOG=1 ;;
        h)
            sed -n '2,7p' "$0" | sed 's/^# //'
            exit 0
            ;;
        *) echo "Usage: $0 [-t TOP] [-l]" >&2; exit 2 ;;
    esac
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
log_dir="$repo_root/logs/linux/diagnostics"
timestamp="$(date '+%Y%m%d-%H%M%S')"

# Buffer + tee pattern: print to stdout; if -l, also append to a log file.
buffer=""
emit() { printf '%s\n' "$1"; buffer+="$1"$'\n'; }
section() { emit ""; emit "=== $1 ==="; }

# ── SYSTEM ────────────────────────────────────────────────────────────────────
section 'SYSTEM'
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    emit "Distro: ${PRETTY_NAME:-$NAME ${VERSION:-}}"
fi
emit "Kernel: $(uname -srm)"
if command -v lscpu >/dev/null 2>&1; then
    cpu_model=$(lscpu | awk -F': +' '/^Model name/ {print $2; exit}')
    cpu_cores=$(lscpu | awk -F': +' '/^Core\(s\) per socket/ {c=$2} /^Socket\(s\)/ {s=$2} END {print (c*s)}')
    cpu_logical=$(nproc)
    emit "CPU   : ${cpu_model:-unknown}"
    emit "Cores : ${cpu_cores:-?} physical / ${cpu_logical} logical"
fi
emit "Uptime: $(uptime -p 2>/dev/null || uptime)"
emit "Load  : $(awk '{print $1, $2, $3}' /proc/loadavg) (1/5/15 min)"

# ── MEMORY ────────────────────────────────────────────────────────────────────
section 'MEMORY'
if command -v free >/dev/null 2>&1; then
    free -h | sed 's/^/  /' | while IFS= read -r line; do emit "$line"; done
fi
mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
if [[ -n "${mem_total_kb:-}" && -n "${mem_avail_kb:-}" ]]; then
    used_pct=$(( (mem_total_kb - mem_avail_kb) * 100 / mem_total_kb ))
    emit "Used %: ${used_pct}%"
    if (( used_pct >= 85 )); then
        emit "  ^^^ High — system is under memory pressure"
    fi
fi

# ── SWAP ──────────────────────────────────────────────────────────────────────
section 'SWAP'
if [[ -r /proc/swaps ]] && [[ "$(wc -l < /proc/swaps)" -gt 1 ]]; then
    while IFS= read -r line; do emit "  $line"; done < /proc/swaps
    swap_used=$(awk '/^SwapTotal:/ {t=$2} /^SwapFree:/ {f=$2} END {print (t-f)/1024}' /proc/meminfo)
    emit "Swap used: ${swap_used} MB"
else
    emit "  (no swap configured)"
fi

# ── DISKS ─────────────────────────────────────────────────────────────────────
section 'DISKS'
df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs -x squashfs 2>/dev/null \
    | sed 's/^/  /' \
    | while IFS= read -r line; do emit "$line"; done

# ── TOP N BY CPU (accumulated) ────────────────────────────────────────────────
section "TOP $TOP PROCESSES BY CPU (snapshot %CPU)"
ps -eo pid,user,pcpu,rss,comm --sort=-pcpu --no-headers \
    | head -n "$TOP" \
    | awk '{ printf "  %-25s pid=%-7s user=%-12s cpu=%-5s%%  ram=%d MB\n", $5, $1, $2, $3, $4/1024 }' \
    | while IFS= read -r line; do emit "$line"; done

# ── TOP N BY RAM ──────────────────────────────────────────────────────────────
section "TOP $TOP PROCESSES BY RAM (RSS)"
ps -eo pid,user,pcpu,rss,comm --sort=-rss --no-headers \
    | head -n "$TOP" \
    | awk '{ printf "  %-25s pid=%-7s user=%-12s ram=%-7d MB  cpu=%s%%\n", $5, $1, $2, $4/1024, $3 }' \
    | while IFS= read -r line; do emit "$line"; done

# ── KNOWN HOGS (Linux) ────────────────────────────────────────────────────────
section 'KNOWN HOGS CHECK'
check_hog() {
    local pattern="$1" note="$2"
    local matches
    matches=$(pgrep -af "$pattern" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        local count
        count=$(printf '%s\n' "$matches" | wc -l)
        emit "  [RUNNING x${count}] ${pattern}"
        emit "            ${note}"
    fi
}
check_hog 'snapd'        'Snap daemon — heavy if many snaps refresh; check `snap refresh --hold`'
check_hog 'tracker-'     'GNOME Tracker — search indexer; can spike CPU on first crawl'
check_hog 'baloo_file'   'KDE Baloo file indexer — disable if not using semantic search'
check_hog 'dockerd'      'Docker daemon — full container runtime; stop if not actively used'
check_hog 'containerd'   'containerd — runs under dockerd; usually goes with it'
check_hog 'firefox'      'Firefox — common RAM hog; restart if RAM > 4 GB'
check_hog 'chromium\|chrome' 'Chromium/Chrome — multi-process browser; tabs accumulate RAM'
check_hog 'electron'     'Electron app(s) — VS Code/Slack/Discord/etc; each uses 200+ MB'
check_hog 'gnome-shell'  'GNOME Shell — desktop; CPU spike may indicate runaway extension'
check_hog 'plasmashell'  'KDE Plasma shell — same idea'
check_hog 'java'         'Java VM(s) — IDE/server; check heap with jcmd'
check_hog 'python.*celery' 'Celery worker — verify expected; stale workers eat RAM'
check_hog 'mysqld\|mariadbd' 'MySQL/MariaDB — large buffer pool; verify sized correctly'
check_hog 'postgres'     'PostgreSQL — multi-process; RAM scales with shared_buffers + connections'

emit ''
emit '=== END ==='

if (( SAVE_LOG )); then
    mkdir -p "$log_dir"
    log_file="$log_dir/${timestamp}-perf-snapshot.txt"
    printf '%s' "$buffer" > "$log_file"
    echo ""
    echo "Log saved: $log_file"
fi
