# Portable performance diagnostics — `tools/unix/diagnostics/`

Portable bash tools shared by **Linux and macOS** for catching *intermittent* slowdowns: capture
unattended, then analyze the log by timestamp. OS-specific bits branch internally on `uname`.

> 🧰 **All repo tools:** [root README → Tools](../../../README.md#tools)
> 🧠 **Interpretation:** the [`perf-capture`](../../../.claude/skills/perf-capture/SKILL.md) skill plus the
> OS perf-diagnosis skill ([`linux-perf-diagnosis`](../../../.claude/skills/linux-perf-diagnosis/SKILL.md) /
> [`macos-perf-diagnosis`](../../../.claude/skills/macos-perf-diagnosis/SKILL.md)). The
> [`/capture`](../../../.claude/commands/capture.md) command dispatches here for `linux` and `darwin`.

## Scripts

| Script | What it does | Key params |
|---|---|---|
| [`perf-capture.sh`](perf-capture.sh) | Unattended background monitor; appends timestamped CPU/load/mem samples + a spike flag to a log (for intermittent slowdowns); writes a PID file | `-i INTERVAL`, `-d DURATION_MIN`, `-c CPU_PCT`, `-t TOP` |
| [`perf-analyze.sh`](perf-analyze.sh) | Parse a perf-capture log into ranked culprits, slow-time windows, and an optional time-focused view | `-p LOG`, `-a HH:MM`, `-w WINDOW_MIN`, `-c CPU_PCT`, `-t TOP` |

## Quick start

```bash
# "Comes and goes" -> capture unattended, then analyze by timestamp
./tools/unix/diagnostics/perf-capture.sh -i 5 -d 120 &      # background
./tools/unix/diagnostics/perf-analyze.sh -a 14:30 -w 3      # focus a moment it lagged
```

## Notes

- For a **one-shot** "it's slow right now" snapshot, use the OS-native tool instead:
  [`tools/linux/diagnostics/perf-snapshot.sh`](../../linux/diagnostics/README.md) or
  [`tools/macos/diagnostics/perf-snapshot.sh`](../../macos/diagnostics/README.md).
- Capture logs are written under `logs/<os>/diagnostics/` (git-ignored).
- The [`perf-analyst`](../../../.claude/agents/perf-analyst.md) agent can analyze long capture logs off the main context.
