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

**CPU column is accumulated seconds**, not live %. A process showing 9000s has burned 9000 CPU-seconds since it started. To get live activity, run `perf-watch` for 30 seconds and watch the delta column.

**Memory Compression > 1 GB** means the system has hit RAM pressure at some point this session. Over 2 GB = significant.

**Committed > 85% of virtual** means you're close to the edge; adding more apps will cause swapping.

**Pagefile peak > 2 GB** means the system has already been swapping hard this session — even if it looks OK now.

## Known culprits on this machine

| Process | Normal behavior | Red flag | Fix |
|---|---|---|---|
| `Cursor` | Low CPU when idle | CPU > 2000s, RAM > 1 GB | Restart Cursor; check if workspace points at a huge folder or network share |
| `Docker Desktop` / `com.docker.backend` | Only run when needed | Always running | Quit from tray when not containerizing |
| `com.docker.backend` running alone | — | Running without Docker Desktop UI | Orphaned backend — kill it: `Stop-Process -Name com.docker.backend -Force` |
| `vmmemWSL` | Small when idle | > 1 GB | Add `[wsl2]\nmemory=4GB` to `%USERPROFILE%\.wslconfig` |
| `Wox` | Near-zero CPU | CPU > 500s | Rebuild index: Settings → Index → Rebuild; or switch to PowerToys Run |
| `LogiPluginService` / `logioptionsplus_agent` | Near-zero | Hundreds or thousands of CPU-seconds | Disable from startup via `windows-services` skill if not using special Logitech features |
| `RzSynapse` | Near-zero | CPU > 1000s | Razer Synapse peripheral manager — restart it; disable startup if not needed |
| `Creative Cloud` / `AdobeCollabSync` | Not running | Always in tray | CC Preferences → uncheck "Launch at login"; AdobeCollabSync stops when CC quits |
| `SnagitCapture` | Only when capturing | Always running + high RAM | Quit between sessions |
| `Wispr Flow` | 1–2 processes | 3+ instances | Multiple orphaned instances — restart the app to clear them |
| `Move Mouse` | Near-zero | > 200s | Check interval setting — 1-second loops cause this |
| `msedgewebview2` | Moderate | > 500 MB per instance | Embedded browser spawned by other apps (Creative Cloud, 1Password, Wispr Flow); killing the parent app reclaims the memory |
| `Memory Compression` | < 500 MB | > 2 GB | Symptom of RAM pressure — find and stop large consumers |
| `notepad++` | Near-zero | CPU > 500s | Text editors should never accumulate CPU; likely a runaway plugin or a very large file open |
| `endpointprotection` | Always present, low CPU | High CPU | EDR/antivirus; if scanning heavily, check if it's doing a scheduled scan |

## Virtual machines (vmmem / vmwp)

The snapshot now auto-identifies running VMs. If you see `vmmem` processes:

- **`vmmemWSL`** — always WSL2. Cap with `%USERPROFILE%\.wslconfig`.
- **`vmmem` (generic)** — a Hyper-V VM. The snapshot identifies it via named pipes.

**Known VMs on this machine:**

| Identity | RAM | Notes |
|---|---|---|
| WSL2 | ~1–2 GB | Used by Docker and direct WSL usage |
| Docker Desktop VM | ~1–2 GB | Quit Docker Desktop to stop |
| Cowork | ~1.5 GB | Collaboration app — quit from tray if not in a Cowork session |
| Windows Subsystem for Android | varies | Stop via WSA Settings if not needed |

**Manual VM identification** (if snapshot doesn't catch it):
```powershell
# Find all vmwp processes and their named pipes
[System.IO.Directory]::GetFiles('\\.\pipe\') | Where-Object { $_ -match 'cowork|wsl|docker|android' }
```

## Docker orphaned backend pattern

If Docker Desktop "won't start" but `com.docker.backend` is still in the process list:
The backend is stuck; the UI can't attach to it. Fix:
```powershell
Stop-Process -Name "com.docker.backend" -Force
Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
# Then relaunch Docker Desktop normally
```

## Triage order

1. **Quit unused background apps** (Docker, Creative Cloud, Snagit, Cowork) — zero risk, immediate RAM gain.
2. **Restart runaway processes** (Cursor high CPU, Wispr Flow multiple instances, Notepad++ anomaly) — resets accumulated debt.
3. **Kill orphaned backends** (Docker backend without UI, extra Wispr Flow processes).
4. **Cap VM memory** (WSL `.wslconfig`, Docker resource limits) — persistent fix for next session.
5. **Disable startup items** (Logitech, Razer Synapse, Wox) — use `windows-services` skill; requires restart to verify.

## Asking for a live snapshot

If Marty hasn't run a snapshot yet:

```
I'll run a quick snapshot to see what's going on.
```

Then: `.\tools\diagnostics\perf-snapshot.ps1 -SaveLog`
