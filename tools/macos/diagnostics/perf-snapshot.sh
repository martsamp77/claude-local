#!/usr/bin/env bash
# .NAME        perf-snapshot
# .SYNOPSIS    Capture a one-time performance snapshot on macOS: hardware, memory, swap, disk, top processes, load.
# .PLATFORM    macos
# .CATEGORY    diagnostics
# .USAGE       ./tools/macos/diagnostics/perf-snapshot.sh [-t TOP] [-l]
# .WHEN        Mac feels slow or laggy; spinning beachball; before/after tuning to compare baseline.

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
log_dir="$repo_root/logs/macos/diagnostics"
timestamp="$(date '+%Y%m%d-%H%M%S')"

buffer=""
emit() { printf '%s\n' "$1"; buffer+="$1"$'\n'; }
section() { emit ""; emit "=== $1 ==="; }

# ── SYSTEM ────────────────────────────────────────────────────────────────────
section 'SYSTEM'
emit "macOS : $(sw_vers -productName) $(sw_vers -productVersion) (build $(sw_vers -buildVersion))"
emit "Kernel: $(uname -srm)"
model=$(sysctl -n hw.model 2>/dev/null || echo unknown)
chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)
ncpu=$(sysctl -n hw.ncpu 2>/dev/null || echo ?)
nperf=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo "")
neff=$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null || echo "")
emit "Model : ${model}"
emit "CPU   : ${chip}"
if [[ -n "$nperf" && -n "$neff" ]]; then
    emit "Cores : ${nperf} performance + ${neff} efficiency / ${ncpu} logical (Apple Silicon)"
else
    nphys=$(sysctl -n hw.physicalcpu 2>/dev/null || echo ?)
    emit "Cores : ${nphys} physical / ${ncpu} logical"
fi
total_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
total_gb=$(awk -v b="$total_bytes" 'BEGIN{ printf "%.1f", b/1024/1024/1024 }')
emit "RAM   : ${total_gb} GB"
emit "Uptime: $(uptime | sed 's/^[ ]*//')"

# ── MEMORY (vm_stat) ──────────────────────────────────────────────────────────
section 'MEMORY'
if command -v vm_stat >/dev/null 2>&1; then
    page_size=$(vm_stat | awk -F'page size of ' 'NR==1 {gsub(" bytes.","",$2); print $2}')
    page_size=${page_size:-4096}
    vm=$(vm_stat | sed 's/\.//g')
    free_pages=$(echo "$vm" | awk '/Pages free/ {print $3}')
    active_pages=$(echo "$vm" | awk '/Pages active/ {print $3}')
    inactive_pages=$(echo "$vm" | awk '/Pages inactive/ {print $3}')
    speculative_pages=$(echo "$vm" | awk '/Pages speculative/ {print $3}')
    wired_pages=$(echo "$vm" | awk '/Pages wired down/ {print $4}')
    compressed_pages=$(echo "$vm" | awk '/Pages occupied by compressor/ {print $5}')
    awk -v p="$page_size" -v free="$free_pages" -v act="$active_pages" -v ina="$inactive_pages" \
        -v spec="$speculative_pages" -v wir="$wired_pages" -v comp="$compressed_pages" -v tot="$total_bytes" \
        'BEGIN {
            mb = 1024*1024
            printf "Free       : %.1f GB\n", free*p/1024/mb
            printf "Active     : %.1f GB\n", act*p/1024/mb
            printf "Inactive   : %.1f GB\n", ina*p/1024/mb
            printf "Wired      : %.1f GB\n", wir*p/1024/mb
            printf "Compressed : %.1f GB\n", comp*p/1024/mb
            used = (act+wir+comp)*p
            printf "Used (active+wired+compressed): %.1f GB / %.1f GB (%.0f%%)\n", used/1024/mb, tot/1024/mb, used*100/tot
        }' | while IFS= read -r l; do emit "  $l"; done

    # Memory pressure (real source of truth on macOS)
    if command -v memory_pressure >/dev/null 2>&1; then
        pressure=$(memory_pressure 2>/dev/null | awk '/System-wide memory free percentage/ {print $NF}')
        if [[ -n "$pressure" ]]; then
            emit "  Free %     : ${pressure}"
        fi
    fi
fi

# ── SWAP ──────────────────────────────────────────────────────────────────────
section 'SWAP'
swap=$(sysctl -n vm.swapusage 2>/dev/null)
if [[ -n "$swap" ]]; then
    emit "  $swap"
else
    emit "  (sysctl vm.swapusage unavailable)"
fi

# ── DISKS ─────────────────────────────────────────────────────────────────────
section 'DISKS'
df -h | grep -E '^(/dev/|Filesystem)' | sed 's/^/  /' \
    | while IFS= read -r line; do emit "$line"; done

# ── POWER / THERMAL ───────────────────────────────────────────────────────────
section 'POWER'
if command -v pmset >/dev/null 2>&1; then
    src=$(pmset -g batt 2>/dev/null | head -1)
    bat=$(pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1)
    emit "  Source: $src"
    [[ -n "$bat" ]] && emit "  Battery: $bat"
fi
if command -v sysctl >/dev/null 2>&1; then
    therm=$(sysctl -n machdep.xcpm.cpu_thermal_level 2>/dev/null || true)
    [[ -n "$therm" ]] && emit "  CPU thermal level (Intel): $therm"
fi

# ── TOP N BY CPU ──────────────────────────────────────────────────────────────
section "TOP $TOP PROCESSES BY CPU (snapshot %CPU)"
ps -Ao pid,user,pcpu,rss,comm -r 2>/dev/null \
    | head -n $((TOP+1)) | tail -n +2 \
    | awk '{ split($5, parts, "/"); name=parts[length(parts)]; printf "  %-30s pid=%-7s user=%-12s cpu=%-5s%%  ram=%d MB\n", name, $1, $2, $3, $4/1024 }' \
    | while IFS= read -r line; do emit "$line"; done

# ── TOP N BY RAM ──────────────────────────────────────────────────────────────
section "TOP $TOP PROCESSES BY RAM (RSS)"
ps -Ao pid,user,pcpu,rss,comm -m 2>/dev/null \
    | head -n $((TOP+1)) | tail -n +2 \
    | awk '{ split($5, parts, "/"); name=parts[length(parts)]; printf "  %-30s pid=%-7s user=%-12s ram=%-7d MB  cpu=%s%%\n", name, $1, $2, $4/1024, $3 }' \
    | while IFS= read -r line; do emit "$line"; done

# ── KNOWN HOGS (macOS) ────────────────────────────────────────────────────────
section 'KNOWN HOGS CHECK'
check_hog() {
    local pattern="$1" note="$2"
    local count
    count=$(pgrep -af "$pattern" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${count:-0}" -gt 0 ]]; then
        emit "  [RUNNING x${count}] ${pattern}"
        emit "            ${note}"
    fi
}
check_hog 'WindowServer'     'Compositor — high CPU often = bad GPU driver or external display refresh issues; logout fixes'
check_hog 'kernel_task'      'Kernel — high CPU = thermal throttling or peripheral firing IRQs; check pmset and unplug peripherals'
check_hog 'mds_stores\|mdworker' 'Spotlight indexer — heavy after big dir changes; `mdutil -i off /Volumes/X` to disable per volume'
check_hog 'bird'             'iCloud bird daemon — uploads/downloads; pause via System Settings > iCloud Drive if syncing huge files'
check_hog 'photoanalysisd'   'Photos library analyzer — runs when plugged in + idle; finishes once library is processed'
check_hog 'cloudphotod'      'iCloud Photos sync — companion to photoanalysisd'
check_hog 'syncdefaultsd'    'iCloud defaults/keychain sync — restart if stuck'
check_hog 'corespotlightd'   'Spotlight system index — separate from mds; usually quick'
check_hog 'Google Chrome'    'Chrome — multi-process; tabs accumulate RAM; restart if RSS > 4 GB'
check_hog 'Safari'           'Safari — per-tab content processes; check Activity Monitor > Memory tab'
check_hog 'firefox'          'Firefox — same shape as Chrome; restart on RAM creep'
check_hog 'Slack\|slack'     'Slack — Electron-heavy; restart if RAM > 1.5 GB'
check_hog 'zoom\.us\|zoom'   'Zoom — runs even after meetings end; quit fully via menu'
check_hog 'Dropbox'          'Dropbox — sync engine; pause from menu bar if hogging'
check_hog 'OneDrive'         'OneDrive — sync engine; same idea as Dropbox'

emit ''
emit '=== END ==='

if (( SAVE_LOG )); then
    mkdir -p "$log_dir"
    log_file="$log_dir/${timestamp}-perf-snapshot.txt"
    printf '%s' "$buffer" > "$log_file"
    echo ""
    echo "Log saved: $log_file"
fi
