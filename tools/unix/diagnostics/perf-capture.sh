#!/usr/bin/env bash
# .NAME        perf-capture
# .SYNOPSIS    Unattended background monitor: append timestamped CPU/load/mem samples to a log and flag spikes, for catching intermittent slowdowns.
# .PLATFORM    unix
# .CATEGORY    diagnostics
# .USAGE       ./tools/unix/diagnostics/perf-capture.sh [-i INTERVAL] [-d DURATION_MIN] [-c CPU_PCT] [-t TOP]
# .WHEN        Machine is intermittently slow ("comes and goes"); need to catch what spikes when it happens, unattended, then review by timestamp.

set -uo pipefail

INTERVAL=5
DURATION_MIN=0      # 0 = run until stopped
CPU_PCT=70          # flag a sample when total CPU% >= this (or 1-min load >= ncpu)
TOP=4
while getopts "i:d:c:t:h" opt; do
    case "$opt" in
        i) INTERVAL="$OPTARG" ;;
        d) DURATION_MIN="$OPTARG" ;;
        c) CPU_PCT="$OPTARG" ;;
        t) TOP="$OPTARG" ;;
        h) sed -n '2,7p' "$0" | sed 's/^# //'; exit 0 ;;
        *) echo "Usage: $0 [-i INTERVAL] [-d DURATION_MIN] [-c CPU_PCT] [-t TOP]" >&2; exit 2 ;;
    esac
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
os="$(uname)"
case "$os" in
    Linux)  os_dir="linux" ;;
    Darwin) os_dir="macos" ;;
    *)      os_dir="linux" ;;
esac
log_dir="$repo_root/logs/$os_dir/diagnostics"
mkdir -p "$log_dir"
stamp="$(date '+%Y%m%d-%H%M%S')"
log_file="$log_dir/${stamp}-perf-capture.log"
pid_file="$log_dir/.perf-capture.pid"   # consumed by /capture stop|status

ncpu="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)"

# --- total CPU% (100 - idle) -------------------------------------------------
prev_idle=0; prev_total=0
cpu_total_pct() {
    if [[ "$os" == "Linux" ]]; then
        local cpu u n s i w irq sirq steal idle total d_idle d_total
        read -r cpu u n s i w irq sirq steal _ < /proc/stat
        idle=$(( i + w )); total=$(( u + n + s + i + w + irq + sirq + steal ))
        d_idle=$(( idle - prev_idle )); d_total=$(( total - prev_total ))
        prev_idle=$idle; prev_total=$total
        if (( d_total > 0 )); then awk -v dt="$d_total" -v di="$d_idle" 'BEGIN{ printf "%.0f", (dt-di)*100/dt }'; else echo 0; fi
    else
        # macOS: take the 2nd sample of top's CPU usage line (user + sys)
        top -l 2 -n 0 2>/dev/null | awk -F'[:,]' '/CPU usage/{u=$2; s=$3} END{ gsub(/[^0-9.]/,"",u); gsub(/[^0-9.]/,"",s); printf "%.0f", u+s }'
    fi
}
[[ "$os" == "Linux" ]] && cpu_total_pct >/dev/null   # seed /proc/stat baseline

# --- memory used % -----------------------------------------------------------
mem_used_pct() {
    if [[ "$os" == "Linux" ]]; then
        awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{ if(t>0) printf "%.0f", (t-a)*100/t; else print 0 }' /proc/meminfo
    else
        local ps
        ps="$(vm_stat | awk -F'of ' '/page size/{gsub(/[^0-9]/,"",$2); print $2}')"; ps="${ps:-4096}"
        vm_stat | awk -v ps="$ps" '
            /Pages free/{f=$3} /Pages active/{a=$3} /Pages inactive/{i=$3} /Pages speculative/{sp=$3} /Pages wired/{w=$3} /occupied by compressor/{c=$3}
            END{ gsub(/\./,"",f);gsub(/\./,"",a);gsub(/\./,"",i);gsub(/\./,"",sp);gsub(/\./,"",w);gsub(/\./,"",c);
                 used=(a+w+c)*ps; total=(f+a+i+sp+w+c)*ps; if(total>0) printf "%.0f", used*100/total; else print 0 }'
    fi
}

echo "$$|$log_file|$(date '+%Y-%m-%dT%H:%M:%S')|interval=${INTERVAL}s" > "$pid_file"
cleanup() { rm -f "$pid_file"; }
trap cleanup EXIT
trap 'exit 0' INT TERM   # exit -> fires EXIT trap; ensures `kill` (from /capture stop) stops the loop

{
    echo "perf-capture  started=$(date '+%Y-%m-%dT%H:%M:%S')  os=$os  interval=${INTERVAL}s  cpu-flag>=${CPU_PCT}%  ncpu=$ncpu"
    echo "columns: HH:mm:ss | CPU=tot% Load=1min MemUsed=% | SPIKE | topProcs name(cpu%)"
} | tee "$log_file"

end_epoch=0
(( DURATION_MIN > 0 )) && end_epoch=$(( $(date +%s) + DURATION_MIN * 60 ))

while :; do
    sleep "$INTERVAL"
    now="$(date '+%H:%M:%S')"
    cpu="$(cpu_total_pct)"
    load="$(uptime | sed -E 's/.*load averages?: //' | awk '{print $1}' | tr -d ',')"
    mem="$(mem_used_pct)"
    procs="$(ps -Ao pcpu,comm 2>/dev/null | sort -rn | head -n "$TOP" \
             | awk '{ c=$1; $1=""; sub(/^[ \t]+/,""); n=$0; sub(/.*\//,"",n); printf "%s(%s%%)  ", n, c }')"
    flag="     "
    if awk -v c="$cpu" -v cp="$CPU_PCT" -v l="$load" -v n="$ncpu" 'BEGIN{ exit !(c+0>=cp+0 || l+0>=n+0) }'; then flag="SPIKE"; fi
    printf '%s | CPU=%4s%% Load=%5s MemUsed=%3s%% | %s | %s\n' "$now" "$cpu" "$load" "$mem" "$flag" "$procs" >> "$log_file"
    (( end_epoch > 0 )) && (( $(date +%s) >= end_epoch )) && break
done
