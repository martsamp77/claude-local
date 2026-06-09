#!/usr/bin/env bash
# .NAME        perf-analyze
# .SYNOPSIS    Parse a perf-capture log into a ranked culprit list, slow-time windows, and an optional time-focused view.
# .PLATFORM    unix
# .CATEGORY    diagnostics
# .USAGE       ./tools/unix/diagnostics/perf-analyze.sh [-p LOG] [-a HH:MM] [-w WINDOW_MIN] [-c CPU_PCT] [-t TOP]
# .WHEN        After perf-capture has been running; you want to know what spiked, and when. Pass -a to focus on a moment you felt the slowness.

set -uo pipefail

LOG=""; AROUND=""; WINDOW_MIN=3; CPU_PCT=70; TOP=8
while getopts "p:a:w:c:t:h" opt; do
    case "$opt" in
        p) LOG="$OPTARG" ;;
        a) AROUND="$OPTARG" ;;
        w) WINDOW_MIN="$OPTARG" ;;
        c) CPU_PCT="$OPTARG" ;;
        t) TOP="$OPTARG" ;;
        h) sed -n '2,7p' "$0" | sed 's/^# //'; exit 0 ;;
        *) echo "Usage: $0 [-p LOG] [-a HH:MM] [-w WINDOW_MIN] [-c CPU_PCT] [-t TOP]" >&2; exit 2 ;;
    esac
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
os="$(uname)"
case "$os" in Linux) os_dir="linux" ;; Darwin) os_dir="macos" ;; *) os_dir="linux" ;; esac
log_dir="$repo_root/logs/$os_dir/diagnostics"

if [[ -z "$LOG" ]]; then
    LOG="$(ls -t "$log_dir"/*-perf-capture.log 2>/dev/null | head -n1 || true)"
    [[ -z "$LOG" ]] && { echo "No perf-capture logs in $log_dir. Run /capture start first."; exit 1; }
fi
[[ -f "$LOG" ]] || { echo "Log not found: $LOG"; exit 1; }

# Data lines look like:  HH:MM:SS | CPU=  11% Load=  0.5 MemUsed= 35% | SPIKE | name(cpu%)  name(cpu%)
data_re='^[0-9][0-9]:[0-9][0-9]:[0-9][0-9] \| CPU='

echo "=== PERF-ANALYZE ==="
echo "log      : $(basename "$LOG")"

# --- overview + slow windows -------------------------------------------------
awk -F' \\| ' -v cp="$CPU_PCT" '
    BEGIN{ cmax=0; lmax=0; mmax=0 }
    $0 ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9] \| CPU=/ {
        t=$1; flag=$3;
        cpu=$2;  sub(/.*CPU=[ ]*/,"",cpu);     sub(/%.*/,"",cpu);
        load=$2; sub(/.*Load=[ ]*/,"",load);   sub(/ .*/,"",load);
        mem=$2;  sub(/.*MemUsed=[ ]*/,"",mem); sub(/%.*/,"",mem);
        n++; cs+=cpu;
        if(cpu+0>cmax)cmax=cpu; if(load+0>lmax)lmax=load; if(mem+0>mmax)mmax=mem;
        if(first=="")first=t; last=t;
        hot=(flag ~ /SPIKE/);
        if(hot){ hc++; if(!inw){ws=t; inw=1; wp=cpu} we=t; if(cpu+0>wp+0)wp=cpu }
        else if(inw){ win[++w]="  " ws "-" we "  peakCPU=" wp "%"; inw=0 }
    }
    END{
        if(inw) win[++w]="  " ws "-" we "  peakCPU=" wp "%";
        if(n==0){ print "  (no parseable sample lines)"; exit }
        printf "span     : %s -> %s   samples=%d\n", first, last, n;
        printf "CPU total: avg=%.1f%%  max=%s%%   Load max=%s   MemUsed max=%s%%\n", cs/n, cmax, lmax, mmax;
        printf "hot/spike: %d of %d samples flagged (CPU>=%s%% or 1-min load>=ncpu)\n", hc, n, cp;
        print "";
        print "=== SLOW WINDOWS ===";
        if(w==0){
            print "  None. The machine never crossed CPU/load thresholds during this capture.";
            print "  If it FELT slow while this ran, the bottleneck was NOT CPU/load/mem ->";
            print "  look at disk I/O, GPU, network, or a single app (re-run with -a HH:MM at the slow moment).";
        } else { for(k=1;k<=w;k++) print win[k] }
    }' "$LOG"

# --- top culprits across the whole capture -----------------------------------
echo ""
echo "=== TOP CPU CONSUMERS (whole capture, by peak cpu%) ==="
grep -E "$data_re" "$LOG" \
  | grep -oE '[^ ]+\([0-9.]+%\)' \
  | awk -F'(' '{ name=$1; pc=$2; gsub(/[^0-9.]/,"",pc);
                 if(pc+0>peak[name])peak[name]=pc+0; sum[name]+=pc+0; cnt[name]++ }
               END{ for(nm in peak) printf "%s\t%d\t%d\t%d\n", nm, peak[nm], sum[nm]/cnt[nm], cnt[nm] }' \
  | sort -t"$(printf '\t')" -k2 -rn | head -n "$TOP" \
  | awk -F"$(printf '\t')" '{ printf "  %-26s peak=%4s%%  avg=%4s%%  seen=%4sx\n", $1, $2, $3, $4 }'

# --- optional time focus -----------------------------------------------------
if [[ -n "$AROUND" ]]; then
    ch="${AROUND%%:*}"; cm="${AROUND##*:}"
    cmin=$(( 10#$ch * 60 + 10#$cm ))
    lomin=$(( cmin - WINDOW_MIN )); himin=$(( cmin + WINDOW_MIN ))
    (( lomin < 0 )) && lomin=0; (( himin > 1439 )) && himin=1439
    lo="$(printf '%02d:%02d:00' $((lomin/60)) $((lomin%60)))"
    hi="$(printf '%02d:%02d:59' $((himin/60)) $((himin%60)))"
    echo ""
    echo "=== FOCUS $AROUND +/-${WINDOW_MIN}min ($lo..$hi) ==="
    focus="$(awk -F' \\| ' -v lo="$lo" -v hi="$hi" '$0 ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9] \| CPU=/ && $1>=lo && $1<=hi' "$LOG")"
    if [[ -z "$focus" ]]; then
        echo "  No samples in that window. Is the time right, and was the monitor running then?"
    else
        printf '%s\n' "$focus" | awk -F' \\| ' '
            { cpu=$2; sub(/.*CPU=[ ]*/,"",cpu); sub(/%.*/,"",cpu); n++; if(cpu+0>cmax)cmax=cpu }
            END{ printf "  %d samples  peakCPU=%s%%\n", n, cmax;
                 if(cmax+0 < '"$CPU_PCT"'+0) print "  CPU was CALM here -> slowness was elsewhere (disk I/O, GPU, network, or one app)." }'
        echo "  Hottest processes in window:"
        printf '%s\n' "$focus" \
          | grep -oE '[^ ]+\([0-9.]+%\)' \
          | awk -F'(' '{ name=$1; pc=$2; gsub(/[^0-9.]/,"",pc); if(pc+0>peak[name])peak[name]=pc+0 }
                       END{ for(nm in peak) printf "%s\t%d\n", nm, peak[nm] }' \
          | sort -t"$(printf '\t')" -k2 -rn | head -n 6 \
          | awk -F"$(printf '\t')" '{ printf "    %-26s peak=%4s%%\n", $1, $2 }'
    fi
fi
