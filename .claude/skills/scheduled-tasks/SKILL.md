---
name: scheduled-tasks
description: Create, inspect, and manage Windows scheduled tasks via PowerShell. Use when a task should run on a schedule, at logon, or at startup.
---

# scheduled-tasks

Use this skill any time a task should run automatically — on a schedule, at user logon, at system boot, on idle, or on an event. Prefer Task Scheduler over background services for user-context jobs and over `cron`-style hacks.

## Inspect

```powershell
Get-ScheduledTask                                          # all tasks
Get-ScheduledTask -TaskName "MyJob"
Get-ScheduledTask -TaskPath "\Custom\*"
Get-ScheduledTaskInfo -TaskName "MyJob"                    # last run time, result, next run
Get-ScheduledTask -TaskName "MyJob" | Select-Object -ExpandProperty Actions
```

To find tasks by what they run:

```powershell
Get-ScheduledTask | Where-Object { $_.Actions.Execute -match "powershell" }
```

## Create — minimal scheduled task

Build the four pieces (Action, Trigger, Principal, Settings), then register.

```powershell
$Action = New-ScheduledTaskAction `
    -Execute "pwsh.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\DATA\Workspace-37m\claude-local\scripts\my-job.ps1"

$Trigger = New-ScheduledTaskTrigger -Daily -At 7:00am

$Principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited                # or Highest if it needs admin

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1)

Register-ScheduledTask `
    -TaskName "MyJob" `
    -TaskPath "\Custom\" `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Description "Daily PowerShell job at 7am"
```

Use `\Custom\` (or another non-root TaskPath) so you don't pollute the root task list.

## Trigger patterns

```powershell
New-ScheduledTaskTrigger -AtLogOn                                     # current user logon
New-ScheduledTaskTrigger -AtStartup                                   # system boot (needs SYSTEM)
New-ScheduledTaskTrigger -Daily -At 3:00am
New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Friday -At 9:00am
New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)
New-ScheduledTaskTrigger -Once -At 9:00am `
    -RepetitionInterval (New-TimeSpan -Minutes 30) `
    -RepetitionDuration (New-TimeSpan -Hours 8)
```

## Principal patterns

```powershell
# Current user, only when logged in
New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

# Current user, runs whether logged in or not (needs stored credentials)
New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Password -RunLevel Limited

# SYSTEM (no UI, full machine access)
New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
```

`Interactive` only fires when Marty is signed in. `Password` runs even when signed out but requires `Register-ScheduledTask -Password <plaintext>`. SYSTEM is the right choice for headless boot-time jobs.

## Run, disable, unregister

```powershell
Start-ScheduledTask  -TaskName "MyJob" -TaskPath "\Custom\"
Disable-ScheduledTask -TaskName "MyJob" -TaskPath "\Custom\"
Enable-ScheduledTask  -TaskName "MyJob" -TaskPath "\Custom\"
Unregister-ScheduledTask -TaskName "MyJob" -TaskPath "\Custom\" -Confirm:$false
```

Confirm with Marty before `Unregister-ScheduledTask` for any task you didn't create yourself.

## Tips

- Always pass `-NoProfile` to PowerShell actions — task contexts can have surprising profile state.
- Always pass `-ExecutionPolicy Bypass` if running a `.ps1` (the host config may differ from interactive).
- Log output explicitly; tasks have no console. `Start-Transcript` or redirect to a file under the workspace.
- For tasks that fail silently, `Get-ScheduledTaskInfo` shows `LastTaskResult` — exit code or HRESULT.
- Don't disable or modify built-in tasks under `\Microsoft\` without an explicit ask.
