Run a performance snapshot and interpret it.

Steps:
1. Run `.\tools\diagnostics\perf-snapshot.ps1 -SaveLog` using the PowerShell tool.
2. Read the output using the `performance-diagnosis` skill.
3. Identify the top 2–3 issues by impact.
4. For each issue, give: what it is, why it hurts, and one concrete action to fix or mitigate it.
5. End with a one-line summary of the overall health (e.g. "System is healthy", "Moderate pressure from X and Y", "Heavy load — action needed on X").

Keep the response tight. No section headers. No preamble. Just findings and actions.
