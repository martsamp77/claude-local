---
name: performance-diagnosis
description: Diagnose Windows performance issues — slow/unresponsive machine, high CPU or RAM. Use when Marty reports sluggishness or when interpreting perf-snapshot output.
---

# performance-diagnosis

Use this skill when:
- Marty says the machine is slow, unresponsive, or laggy
- Interpreting output from `tools/diagnostics/perf-snapshot.ps1`
- Deciding which running processes to kill, cap, or disable

## Tools available

Run from the repo root (relative paths, no elevation needed):

```powershell
# One-shot snapshot — use this first
.\tools\diagnostics\perf-snapshot.ps1 [-Top 15] [-SaveLog]

# Continuous monitor — use to catch intermittent spikes
.\tools\diagnostics\perf-watch.ps1 [-IntervalSec 5] [-CpuThreshold 25] [-RamThresholdMb 800]
```

Saved logs land in `logs/diagnostics/` (gitignored).

## Reading the snapshot

**CPU column is accumulated seconds**, not live %. A process showing 9000s has burned 9000 CPU-seconds since it started — that's the total debt. To get live activity, run `perf-watch` for 30 seconds and look at the delta column.

**Memory Compression > 1 GB** means the system has hit RAM pressure at some point this session. Over 2 GB means it's been significant.

**Committed > 85% of virtual** means you're close to the edge; adding more open apps will cause swapping.

## Known culprits on this machine

| Process | Normal behavior | Red flag | Fix |
|---|---|---|---|
| `Cursor` | Low CPU when idle | CPU > 2000s accumulated | Restart Cursor; check if pointing at a huge workspace or network share |
| `Docker Desktop` / `com.docker.backend` | Only run when needed | Always running | Quit from tray when not containerizing |
| `vmmemWSL` | Small when idle | > 1 GB | Add `memory=4GB` to `%USERPROFILE%\.wslconfig` |
| `Wox` | Near-zero CPU | CPU > 500s | Rebuild index: Settings → Index → Rebuild; or switch to PowerToys Run |
| `LogiPluginService` / `logioptionsplus_agent` | Near-zero | Always high | Disable from startup if no special Logitech features needed |
| `Creative Cloud` | Not running | Always in tray | Disable autostart: CC app → Preferences → uncheck "Launch at login" |
| `SnagitCapture` | Only when capturing | Always running + high RAM | Quit between sessions |
| `Move Mouse` | Near-zero | > 200s | Check interval setting — 1-second loops cause this |
| `msedgewebview2` | Moderate | > 500 MB | Spawned by Creative Cloud and other apps; killing parent helps |
| `Memory Compression` | < 500 MB | > 2 GB | Symptom of RAM pressure — find and stop large consumers |

## Triage order

1. **Quit unused background apps first** (Docker, Creative Cloud, Snagit) — zero risk, immediate gain.
2. **Restart runaway indexers** (Cursor with high CPU) — safe, resets accumulated debt.
3. **Cap resource limits** (Docker, WSL via `.wslconfig`) — persistent fix for next session.
4. **Disable startup items** (Logitech, Wox) — requires restart to verify, use `windows-services` skill.

## Asking for a live snapshot

If Marty hasn't run a snapshot yet in this conversation:

```
I'll run a quick snapshot to see what's going on.
```

Then run `.\tools\diagnostics\perf-snapshot.ps1` and interpret from there.
