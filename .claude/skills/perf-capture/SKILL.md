---
name: perf-capture
description: "[all] Catch intermittent ('comes and goes') slowdowns that a one-shot snapshot misses. Start an unattended background monitor, then analyze the log by timestamp. Use when the machine is sporadically slow, or when /perf looks clean but the user insists it lags."
---

# perf-capture — catching intermittent slowdowns

A one-shot `/perf` snapshot only sees *this instant*. When slowness **comes and goes**, you have to record over time and review the moment it happened. That's what this workflow is for.

## When to use

- Marty says the machine is *sometimes* slow / laggy / stutters, but it's fine right now.
- `/perf` (perf-snapshot) shows a healthy, idle machine, yet the complaint persists.
- You need to correlate a felt slow moment ("it was bad around 2:35") with what was actually running.

## The lifecycle (use the `/capture` command)

| Step | Command | What happens |
|---|---|---|
| 1. Start | `/capture start` | Launches the monitor **detached** (survives the session); records a pidfile + a timestamped log. |
| 2. Live | (use the machine) | Every ~5 s it appends one line: total CPU%, disk queue (Win) / load (Unix), RAM, a `SPIKE` flag, and the top processes by core-%. |
| 3. Check | `/capture status` | Is a monitor running, since when, where's the log, how many samples. |
| 4. Analyze | `/capture analyze [HH:mm]` | Parses the log → ranked culprits, slow-time windows, optional focus on a reported time. |
| 5. Stop | `/capture stop` | Kills the monitor; the log stays for later analysis. |

Tools behind it: `perf-capture.{ps1,sh}` (the monitor) and `perf-analyze.{ps1,sh}` (the parser). Windows pair lives in `tools/windows/diagnostics/`; the Unix pair (Linux + macOS) in `tools/unix/diagnostics/`. Logs + pidfile land in `logs/<os>/diagnostics/` (gitignored).

## Reading the analysis — the key fork

The analyzer's most important output is **whether any sample crossed the thresholds**:

- **Slow windows found** → a real CPU/disk/load spike happened. The window lists the dominant process(es). That's your culprit — restart it, cap it, or disable it.
- **No slow windows, but the user felt slowness during the capture** → the bottleneck was **NOT** CPU/disk/RAM. Pivot to:
  - **GPU / display** — driver stalls, compositor lag (DWM on Windows, WindowServer on macOS). Not visible in process CPU.
  - **Network** — "slow" often means slow web/DNS/VPN, not a slow PC.
  - **A single app** — only one program is sluggish; profile that app, not the system.
  - **DPC/interrupt latency** (Windows) — driver-level; check `% DPC Time` / `% Interrupt Time` separately.

Always state which fork you're on. A calm log during a slow moment is a *positive finding*, not an inconclusive one — it rules out three whole categories.

## Tips

- The `SPIKE` flag is a convenience marker; the per-line top-process list is logged **every** sample, so a single pegged core still shows even if total CPU never hits the flag threshold (one core of 32 ≈ 3% total).
- A process that appears in *every* sample at moderate core-% (e.g. a misbehaving peripheral agent) is a steady drain — distinct from a brief spike. The analyzer's `seen=Nx` count surfaces this.
- For long or noisy logs, hand the analysis to the `perf-analyst` subagent so the raw log doesn't fill the main context.
- Hand off to the OS perf-diagnosis skill (`windows-perf-diagnosis` / `linux-perf-diagnosis` / `macos-perf-diagnosis`) for the known-hog tables and concrete fixes once you've named the culprit.
