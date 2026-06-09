# Windows startup management — `tools/windows/startup/`

PowerShell tools for auditing what launches at boot/logon and reversibly disabling the noise —
plus a deep-dive on any single scheduled task.

> 🧰 **All repo tools:** [root README → Tools](../../../README.md#tools)
> 🧠 **Interpretation & triage:** the [`windows-startup-management`](../../../.claude/skills/windows-startup-management/SKILL.md)
> and [`windows-scheduled-tasks`](../../../.claude/skills/windows-scheduled-tasks/SKILL.md) skills; the
> [`/startup`](../../../.claude/commands/startup.md) and [`/disable-startup`](../../../.claude/commands/disable-startup.md) commands drive these.

## Scripts

| Script | What it does | Key params |
|---|---|---|
| [`startup-inventory.ps1`](startup-inventory.ps1) | Read-only audit of every startup vector — Run keys (incl. WOW6432), startup folders, logon/boot scheduled tasks, auto-start services — with each item's enable/disable state | `-IncludeMicrosoftTasks`, `-SaveLog` |
| [`inspect-task.ps1`](inspect-task.ps1) | Show full details of named scheduled task(s): action, principal, triggers — to decide if one is safe to remove | `-Name <task>[,<task>...]` |
| [`disable-startup-item.ps1`](disable-startup-item.ps1) | **Reversibly** disable a startup item (auto-start service + Run entry + running processes); backs up first, prints a `RunAs` block instead of auto-elevating, `-Undo` reverses. Ships a `LogiOptionsPlus` preset | `-Preset`, `-Service`, `-RunEntry`, `-KillProcess`, `-Undo`, `-DryRun` |

## Quick start

```powershell
# What launches at startup, and what's already disabled?
.\tools\windows\startup\startup-inventory.ps1 -SaveLog

# What does a specific task actually run, and as whom?
.\tools\windows\startup\inspect-task.ps1 -Name SidebarStartup,StartCN

# Preview disabling a known offender, then apply (reversible)
.\tools\windows\startup\disable-startup-item.ps1 -Preset LogiOptionsPlus -DryRun
.\tools\windows\startup\disable-startup-item.ps1 -Preset LogiOptionsPlus
.\tools\windows\startup\disable-startup-item.ps1 -Preset LogiOptionsPlus -Undo   # revert
```

## Notes

- `startup-inventory.ps1` is read-only; start there to triage before disabling anything.
- `disable-startup-item.ps1` is **reversible by design** — it backs up to `backups\windows\` before
  changing anything, never auto-elevates (it prints the elevated command for you to run), and `-Undo`
  restores the prior state. Always `-DryRun` first.
- Anything that needs admin (auto-start services, machine Run keys) is flagged, not silently elevated.
