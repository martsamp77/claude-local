Audit Windows startup items and recommend what to disable.

Steps:
1. Run `.\tools\startup\startup-inventory.ps1 -SaveLog` using the PowerShell tool.
2. Read the output using the `startup-management` skill.
3. For any unfamiliar scheduled task at root path (`\<name>` not `\Microsoft\*`), run `.\tools\startup\inspect-task.ps1 -Name <name>` to see what it actually launches.
4. Group findings into the three triage tiers from the skill:
   - **Disable freely** — known runaway hogs / inactive apps (Logi Options+, Razer if unused, Adobe stack, telemetry services).
   - **Investigate** — `NO-RECORD` entries in WOW6432Node, unknown scheduled tasks, hardware-vendor items that look ambiguous.
   - **Don't touch** — work-mandated EDR/RMM (Datto, Blackpoint, AutoElevate, Splashtop), load-bearing drivers, things Marty actively uses.
5. For each item in the "disable freely" tier, give the exact PowerShell command. Mark commands that need an elevated shell.
6. End with a one-line summary (e.g. "X items safe to disable, Y need investigation, Z work-mandated").

Keep the response tight. No section headers above what the skill already structures. Don't execute any disables — just stage commands. HKLM, services, and SYSTEM-owned scheduled tasks need explicit user confirmation before running.
