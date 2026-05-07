---
name: macos-perf-diagnosis
description: "[macos] Diagnose macOS performance issues — slow Mac, beachballs, fan noise, high CPU/RAM. Use when Marty reports sluggishness on a Mac or when interpreting perf-snapshot.sh output."
---

# macos-perf-diagnosis

Use this skill when:
- Marty says the Mac is slow, laggy, or showing the spinning beachball
- Fans are loud and the Mac feels hot
- Interpreting output from `tools/macos/diagnostics/perf-snapshot.sh`

## The tool

```bash
./tools/macos/diagnostics/perf-snapshot.sh [-t TOP] [-l]
```

Sections: SYSTEM (model + chip + macOS version), MEMORY (`vm_stat` translated), SWAP (`sysctl vm.swapusage`), DISKS (`df`), POWER (battery + AC, Intel thermal level), TOP by CPU, TOP by RAM, KNOWN HOGS.

`-l` saves output to `logs/macos/diagnostics/<ts>-perf-snapshot.txt` (gitignored).

For continuous monitoring, use Activity Monitor or `top -d -s 2` from Terminal.

## What to look for

- **Memory used %** ≥ 85 → memory pressure. macOS uses RAM aggressively for cache/compressed memory; the `Used` line in the snapshot adds active+wired+compressed which is the fairer "actually committed" number. The `memory_pressure` system call's "free percentage" is the real authority.
- **Swap used > 1 GB sustained** → real memory pressure. Some swap-out is normal on busy days; persistent multi-GB swap means a process needs RAM the system doesn't have.
- **`kernel_task` > 50% CPU sustained** → almost always thermal throttling on Intel Macs (it pretends to use CPU to slow other processes down). Cause is usually a hot peripheral (USB-C dock, charger, hot ambient) or a clogged fan.
- **`WindowServer` > 30% CPU sustained** → display compositor is unhappy. Causes: bad GPU driver state (logout/login), too many large displays at high refresh, or a misbehaving window-management app (Rectangle, BetterDisplay, Yabai).
- **`mds_stores` / `mdworker` busy** → Spotlight is indexing, usually after large file changes. Wait it out; if it never finishes, `mdutil -E /` rebuilds the index.
- **`photoanalysisd`/`cloudphotod` busy** → Photos library catch-up. Plug in + idle to let it finish.
- **Disk** ≥ 90% on `/` (now `/System/Volumes/Data` since APFS) → cleanup time. Check `~/Library/Caches/`, `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` if Docker is installed, and Photos library.
- **Battery — Source: AC Power, but battery percentage is dropping** → high power draw (kernel_task hot, GPU under load, charger underrated for the load).

## Common Mac hogs and recipes

| Symptom | Likely cause | Action |
|---|---|---|
| `kernel_task` 100%+, fans roaring on Intel Mac | Thermal throttling | Unplug USB-C peripherals one by one; check `pmset -g therm`; SMC reset on Intel |
| `WindowServer` pinned, mouse laggy | Display/GPU driver state | Logout/login (cheapest); restart; check window-management apps |
| `mds_stores` busy days after a copy | Spotlight indexing got stuck | `sudo mdutil -i off / && sudo mdutil -i on /` to restart fresh |
| Memory pressure but no obvious culprit | Cached file pages + leaks | Quit and relaunch big apps in Activity Monitor RAM tab; reboot if persistent |
| Disk full | Photos library, Docker.raw, ~/Library/Caches | Photos: optimize storage; Docker: Settings > Resources > prune; `~/Library/Caches/`: safe to delete |
| Slow login after upgrade | LaunchAgents from old apps still firing | `launchctl list | grep -v com.apple` — see `macos-launchd` skill |
| Beachball in specific app | App-internal hang | `kill -SIGINFO <pid>` to dump stack to stderr (Apple-only signal); `sample <pid> 5` for proper sampling |

## Triage decision tree

1. **Mac is hot + fans loud + slow** → almost always `kernel_task` thermal throttling (Intel) or sustained high-power workload (Apple Silicon). Unplug peripherals, check `pmset -g therm`.
2. **Specific app beachballs** → it's that app's bug or main-thread block. `sample <pid> 5 -f /tmp/sample.txt` then read the stack.
3. **Whole system slow + memory pressure** → biggest RSS first in `ps`. Restart the offender. If it's WindowServer or kernel_task, see #1.
4. **Disk full** → `du -sh ~/Library/* | sort -rh | head -20` and `du -sh /Library/* 2>/dev/null | sort -rh | head -20`.
5. **Nothing obvious** → check `log show --last 1h --predicate 'eventMessage CONTAINS[c] "error"'` for system-level issues; check Activity Monitor's Energy tab for unexpected high-impact apps.

## Safety

- **Never** kill `launchd` (PID 1), `kernel_task`, `WindowServer`, `loginwindow`, `Dock`, `Finder` (well, Finder respawns immediately), or `coreaudiod` — system breaks or session crashes.
- `kill -9` is a last resort; send `-TERM` first and wait 5–10 seconds.
- **`sudo killall -KILL coreaudiod`** is the canonical fix for stuck audio — coreaudiod respawns. Same for `bluetoothd` if Bluetooth dies.
- **Don't `mdutil -i off /`** as a perf fix unless you confirmed Spotlight is the culprit and you know how to re-enable it (`mdutil -i on /`). Many macOS features depend on Spotlight (Mail search, Siri suggestions).

## Output format for `/perf` on macOS

When `/perf` runs this on darwin: read the snapshot, surface the 2–3 issues by impact, give one concrete action per issue, end with a one-line health summary. Same shape as Windows + Linux variants.
