Start, stop, check, or analyze a background performance capture for catching intermittent ("comes and goes") slowdowns. Dispatch by OS.

Usage: `/capture <start|stop|status|analyze> [HH:mm]`

The argument is in `$ARGUMENTS`. The first word is the subcommand; an optional `HH:mm` (24h) after `analyze` focuses the report on a moment the machine felt slow.

First, read the session's `Platform:` value and pick the tool set:
- **`win32`** — capture `.\tools\windows\diagnostics\perf-capture.ps1`, analyze `.\tools\windows\diagnostics\perf-analyze.ps1` (PowerShell tool). Pidfile: `logs\windows\diagnostics\.perf-capture.pid`.
- **`linux` / `darwin` (incl. WSL)** — capture `./tools/unix/diagnostics/perf-capture.sh`, analyze `./tools/unix/diagnostics/perf-analyze.sh` (Bash tool). Pidfile: `logs/<linux|macos>/diagnostics/.perf-capture.pid`.

Then act on the subcommand:

**start** — Launch the capture monitor *detached* so it survives this session, then report its PID and log path.
- Windows: `Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','.\tools\windows\diagnostics\perf-capture.ps1','-IntervalSec','5'` — report `$proc.Id`.
- Unix: `nohup ./tools/unix/diagnostics/perf-capture.sh -i 5 >/dev/null 2>&1 &` then `echo $!`.
- If a pidfile already exists and its PID is alive, say a monitor is already running (show its PID + log) instead of starting a second one.
- Tell Marty: use the machine normally; when it goes slow, note the time, then run `/capture analyze HH:mm`. Remind him it can be stopped with `/capture stop`.

**status** — Read the pidfile. If present and the PID is alive, report: PID, how long it's been running, the log path, and current line count / last sample line. If absent or the PID is dead, say no monitor is running (and clean up a stale pidfile).

**stop** — Read the pidfile, confirm the PID is alive, then stop that process (Windows `Stop-Process -Id`; Unix `kill`). Report the final log path so it can be analyzed. If no live monitor, say so.

**analyze [HH:mm]** — Run the analyzer on the most recent log (it auto-selects the latest unless `-Path`/`-p` is given). Pass the time through if provided: Windows `-Around HH:mm`, Unix `-a HH:mm`.
- Then interpret the output using the OS-matched perf-diagnosis skill (`windows-perf-diagnosis` / `linux-perf-diagnosis` / `macos-perf-diagnosis`) and the `perf-capture` skill. For a big or noisy log, delegate the read to the `perf-analyst` subagent instead of loading the whole log into context.
- Lead with the verdict: was there a real CPU/disk/load spike (name the culprit process), or was the machine calm at the slow moment (→ bottleneck is GPU/display, network, or a single app — say so and suggest the next probe).

Keep responses tight. No preamble. For `analyze`, end with one concrete next action.
