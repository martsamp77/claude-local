Run a performance snapshot and interpret it. Dispatch by OS.

Steps:
1. Check the session's `Platform:` value. Pick the snapshot tool + interpreter skill:
   - **`win32`** — run `.\tools\windows\diagnostics\perf-snapshot.ps1 -SaveLog` (PowerShell tool); interpret with the `windows-perf-diagnosis` skill.
   - **`linux`** (incl. WSL) — run `bash ./tools/linux/diagnostics/perf-snapshot.sh -l` (Bash tool); interpret with the `linux-perf-diagnosis` skill.
   - **`darwin`** — run `bash ./tools/macos/diagnostics/perf-snapshot.sh -l` (Bash tool); interpret with the `macos-perf-diagnosis` skill.
2. Identify the top 2–3 issues by impact.
3. For each issue, give: what it is, why it hurts, and one concrete action to fix or mitigate it.
4. End with a one-line summary of the overall health (e.g. "System is healthy", "Moderate pressure from X and Y", "Heavy load — action needed on X").

Keep the response tight. No section headers. No preamble. Just findings and actions.
