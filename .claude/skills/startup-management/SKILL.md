---
name: startup-management
description: Audit and manage Windows startup items — Run keys, startup folders, logon scheduled tasks, auto-start services. Use when Marty asks what's launching at logon, what to disable, or wants to slim down boot.
---

# startup-management

Use when Marty says any of:
- "what's launching at startup"
- "audit my startup items"
- "what should I disable"
- "why is so much running on a fresh boot"
- after a `/perf` snapshot reveals runaway accumulated CPU on processes that survive reboots (Logitech, Razer, Adobe, etc.) and the question shifts to *prevent it from coming back*

## Tools

```powershell
# Full startup audit across every vector — read-only
.\tools\startup\startup-inventory.ps1 [-IncludeMicrosoftTasks] [-SaveLog]

# Deep-dive on one or more named scheduled tasks (action / principal / triggers)
.\tools\startup\inspect-task.ps1 -Name SidebarStartup,StartCN
```

`startup-inventory.ps1` prints five sections; read all of them before recommending anything. The slash command `/startup` runs the inventory and asks Claude to interpret it.

## The four startup vectors

| Vector | Where | Notes |
|---|---|---|
| Run keys | `HKCU\...\Run`, `HKLM\...\Run`, `HKLM\WOW6432Node\...\Run` (+ RunOnce variants) | Most apps register here. **WOW6432Node is the 32-bit Run key** — easy to miss; Razer Synapse, Adobe Creative Cloud, CentraStage Gui live there. |
| Startup folders | `%APPDATA%\...\Startup`, `%ProgramData%\...\Startup` | Shortcuts only. `desktop.ini` is not a startup item. |
| Scheduled tasks | Task Scheduler with `MSFT_TaskLogonTrigger` or `MSFT_TaskBootTrigger` | Filter out `\Microsoft\*` to focus on third-party noise. |
| Auto-start services | `Get-CimInstance Win32_Service` where `StartMode=Auto` | Ignore svchost-hosted services (shared MS hosts). The interesting cases are standalone third-party services like `OptionsPlusUpdaterService`. |

## StartupApproved state semantics

Task Manager's Startup tab toggles `HKCU\...\Explorer\StartupApproved\Run` (and `\StartupFolder`) without removing the underlying entry. The first byte of the value decides:

| Byte 0 | Meaning |
|---|---|
| `0x02` or `0x06` | ENABLED (`0x06` means user has toggled it; bytes 4–11 are the FILETIME of last toggle) |
| `0x03` | DISABLED |

**`NO-RECORD` in the inventory** = the entry runs but Task Manager has never seen it toggled. Common for HKLM and WOW6432Node entries — most apps install the Run value but don't seed StartupApproved, so they run by default.

## Triage tiers

When asked "what should I disable", classify each item into one of these:

**Tier 1 — Disable freely (zero downside if Marty isn't actively using the feature):**
- Logi Options+ (`OptionsPlusUpdaterService` service + `Logitech Download Assistant` HKLM Run) — known runaway hog
- Razer Synapse (HKLM WOW6432 Run) if no Razer peripherals
- Adobe Creative Cloud + CCXProcess (HKLM WOW6432 Run) + `AdobeARMservice` + `AdobeUpdateService` services + `\Adobe Acrobat Update Task`
- AMD telemetry: `AUEPLauncher` (User Experience Program Data Uploader) — pure metrics
- Foxit/Brave/etc. update services — only matter if app is open
- Snagit, Wispr Flow, Cursor's own helper, anything in startup folder Marty doesn't want

**Tier 2 — Investigate before touching:**
- Anything labeled `NO-RECORD` in WOW6432Node — surfaces 32-bit installers' Run entries the GUI doesn't show
- Unknown scheduled tasks at `\` root (no `\Microsoft\` path) — use `inspect-task.ps1` to see what they actually launch
- Hardware-vendor services with names that look like drivers (atiesrxx, RtkAudUService) — these are usually load-bearing, leave them
- StartCN / StartDVR — AMD Radeon Software UI launchers; safe to remove if Marty doesn't use the overlay/recording, but reappear after GPU driver updates

**Tier 3 — Don't touch (work-mandated or load-bearing):**
- Datto stack: `HUNTAgent` (Datto EDR), `CagService` (Datto RMM), `dattorollbackservice`, `Datto EDR` HKLM Run, `CentraStage Gui` WOW6432 Run — work EDR/RMM
- Blackpoint: `Snap`, `ZTAC` — work security agents
- `AutoElevateAgent`, `AEDelayedStartService` — work-managed elevation
- `Splashtop` — remote support
- `SecurityHealth` — Windows Defender tray
- `RtkAudUService` / `RtkAudioUniversalService` — Realtek audio
- `Tailscale` — actively used (startup folder + service)
- `OneDrive` (HKCU Run) — actively used
- `PowerToys\Autorun for msampson` — actively used
- `ParkControl` (Bitsum tray) — pairs with Bitsum Highest Performance power plan, keep

## Disable vs. remove vs. uninstall

| Action | Cmd | When |
|---|---|---|
| Soft-disable in registry | toggle StartupApproved byte to `0x03` (or use Task Manager UI) | Reversible from Task Manager. Default for HKCU Run. |
| Remove Run key entry | `Remove-ItemProperty -Path <RunKey> -Name <Name>` | When you want the entry gone entirely; reinstating means reinstall or manual recreate. |
| Disable service auto-start | `Set-Service -Name <svc> -StartupType Manual` then `Stop-Service -Name <svc>` | For services. Trivially reversible. |
| Disable scheduled task | `Disable-ScheduledTask -TaskName <name>` | Soft, reversible. |
| Remove scheduled task | `Unregister-ScheduledTask -TaskName <name> -Confirm:$false` | When the task is unwanted entirely; may reappear after the owning app updates. |
| Uninstall app | `winget uninstall ...` | Last resort — covers all four startup vectors at once. |

## Elevation

- HKCU Run, user startup folder, user-context scheduled tasks → no elevation needed.
- HKLM Run, WOW6432Node Run, machine startup folder, services, scheduled tasks owned by SYSTEM/AMD/etc. → elevated PowerShell required.

Per `CLAUDE.md`: **don't auto-elevate**. Stage the commands and hand Marty a single block to paste into an admin shell.

## Common patterns

### Logi Options+ (the recurring offender)

Lives in TWO places — the obvious Run key AND a Windows service:

```powershell
# Elevated:
Set-Service -Name OptionsPlusUpdaterService -StartupType Manual
Stop-Service -Name OptionsPlusUpdaterService
Remove-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Logitech Download Assistant'
```

Also tell the user to open Logi Options+ → Settings → uncheck "Open at startup". Otherwise the app re-registers itself.

### AMD Radeon Software UI auto-launch

`StartCN` and `StartDVR` scheduled tasks. Removable but **return after GPU driver updates** — note this in any recommendation.

### Adobe full disable

Five things to hit: HKLM WOW6432 Run x2 (Creative Cloud + CCXProcess), services x2 (AdobeARMservice + AdobeUpdateService), scheduled task x1 (`\Adobe Acrobat Update Task`). Plus tell the user: Creative Cloud → Preferences → uncheck "Launch at login" so it doesn't re-register the Run key.

### "App is in HKLM but not in Task Manager Startup tab"

That's the WOW6432Node Run key (32-bit installers). Task Manager only shows entries with a corresponding StartupApproved record. The script flags these as `NO-RECORD`.

## Verification

After any disable, re-run `.\tools\startup\startup-inventory.ps1` to confirm the change took effect. Most disables only show their effect after the next logon, but Run key removals show immediately and service `Stopped` state shows after `Stop-Service`.

If Marty wants live confirmation that the process isn't currently running, follow up with the `performance-diagnosis` skill / `perf-snapshot.ps1`.
