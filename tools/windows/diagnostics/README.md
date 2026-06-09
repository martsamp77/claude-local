# Windows performance diagnostics — `tools/windows/diagnostics/`

PowerShell tools for diagnosing a slow or unresponsive Windows machine — one-shot snapshots, live
threshold watching, unattended capture of *intermittent* slowdowns, and per-process AV/EDR overhead.

> 🧰 **All repo tools:** [root README → Tools](../../../README.md#tools)
> 🧠 **Interpretation:** the [`windows-perf-diagnosis`](../../../.claude/skills/windows-perf-diagnosis/SKILL.md)
> and [`perf-capture`](../../../.claude/skills/perf-capture/SKILL.md) skills; the [`/perf`](../../../.claude/commands/perf.md)
> and [`/capture`](../../../.claude/commands/capture.md) commands drive these tools and interpret the output.

## Scripts

| Script | What it does | Key params |
|---|---|---|
| [`perf-snapshot.ps1`](perf-snapshot.ps1) | One-shot snapshot: CPU, RAM, disk, pagefile, power plan, top processes, known-hog check | `-Top <n>`, `-SaveLog`, `-ExcludeDev`, `-Exclude <names>`, `-OnlyDev` |
| [`perf-watch.ps1`](perf-watch.ps1) | Continuous, interactive console monitor; alerts when a process crosses a CPU % or RAM MB threshold | `-IntervalSec`, `-CpuThreshold`, `-RamThresholdMb`, `-Top`, `-ExcludeDev`, `-Exclude`, `-OnlyDev` |
| [`perf-capture.ps1`](perf-capture.ps1) | **Unattended** background monitor; appends timestamped CPU/disk/RAM samples + a spike flag to a log; writes a PID file | `-IntervalSec`, `-CpuPct`, `-DiskQ`, `-DurationMin`, `-Top` |
| [`perf-analyze.ps1`](perf-analyze.ps1) | Parse a perf-capture log into ranked culprits, slow-time windows, and an optional time-focused view | `-Path`, `-Around HH:mm`, `-WindowMin`, `-CpuPct`, `-DiskQ`, `-Top`, `-ExcludeDev`, `-Exclude`, `-OnlyDev` |
| [`proc-track.ps1`](proc-track.ps1) | Track named processes' CPU% + file-I/O ops/sec + RAM over time to a log — catches AV/EDR scan bursts (high IOPS, low disk queue) that `perf-capture` thresholds miss; `-Summarize` reads the log back | `-Names`, `-IntervalSec`, `-DurationMin`, `-SpikeCpu`, `-SpikeIops`, `-Summarize`, `-Path` |
| [`dev-allowlist.ps1`](dev-allowlist.ps1) | Shared dev-tool allowlist + matcher (node / Docker+WSL / PowerToys / Tailscale); **dot-sourced** by the perf-* tools to power `-ExcludeDev`. Not run directly | _(library — dot-sourced)_ |

## Quick start

```powershell
# Machine is slow right now -> one-shot snapshot
.\tools\windows\diagnostics\perf-snapshot.ps1 -SaveLog

# Watch live, hide your own dev tools from the noise
.\tools\windows\diagnostics\perf-watch.ps1 -CpuThreshold 25 -RamThresholdMb 800 -ExcludeDev

# "Comes and goes" -> capture unattended in the background, then analyze by timestamp
.\tools\windows\diagnostics\perf-capture.ps1 -IntervalSec 5 -DurationMin 120   # (run in background)
.\tools\windows\diagnostics\perf-analyze.ps1 -Around 14:30 -ExcludeDev          # focus a moment it lagged

# Suspect an AV/EDR/RMM agent -> sample its CPU + I/O over time, then summarize
.\tools\windows\diagnostics\proc-track.ps1 -Names MsMpEng,Sysmon64 -DurationMin 60
.\tools\windows\diagnostics\proc-track.ps1 -Summarize
```

## Notes

- **One-shot vs intermittent:** reach for `perf-snapshot` when it's slow *now*; use `perf-capture` +
  `perf-analyze` when the slowness "comes and goes" and a single snapshot looks clean. The
  [`perf-analyst`](../../../.claude/agents/perf-analyst.md) agent chews through long capture logs off the main context.
- **`-ExcludeDev`** (on snapshot / watch / analyze) filters the dev-tool noise defined in `dev-allowlist.ps1`;
  `-OnlyDev` does the inverse, `-Exclude <names>` adds ad-hoc names.
- **Logs:** `-SaveLog` / capture output lands under `logs\windows\diagnostics\` (git-ignored).
