---
name: windows-services
description: Inspect and control Windows services — query state, start/stop/restart, change startup type. Use for service-level admin tasks.
---

# windows-services

Use this skill for managing Windows services: starting, stopping, restarting, changing startup type, querying status. Most operations need an elevated shell — call that out and let Marty re-launch rather than auto-elevating.

## Inspect

```powershell
Get-Service                                    # all services
Get-Service -Name Spooler                      # one service
Get-Service -DisplayName "*Update*"            # by display name
Get-Service | Where-Object Status -eq Running
Get-Service | Where-Object StartType -eq Automatic | Sort-Object DisplayName
```

For more detail (path, account, dependencies):

```powershell
Get-CimInstance Win32_Service -Filter "Name='Spooler'" | Format-List *
sc.exe qc Spooler                              # query config
sc.exe queryex Spooler                         # query state with PID
```

## Start / stop / restart

```powershell
Start-Service -Name Spooler
Stop-Service  -Name Spooler                    # fails if other services depend on it
Stop-Service  -Name Spooler -Force             # also stops dependents — confirm first
Restart-Service -Name Spooler
```

`Stop-Service -Force` cascades to dependents. List dependents first:

```powershell
Get-Service -Name Spooler -DependentServices
```

## Change startup type

```powershell
Set-Service -Name Spooler -StartupType Automatic
Set-Service -Name Spooler -StartupType Manual
Set-Service -Name Spooler -StartupType Disabled
Set-Service -Name Spooler -StartupType AutomaticDelayedStart   # pwsh 7+
```

For `AutomaticDelayedStart` on Windows PowerShell 5.1, fall back to `sc.exe`:

```powershell
sc.exe config Spooler start= delayed-auto
```

(Note the space after `=` — required by `sc.exe`.)

## Wait for state

```powershell
(Get-Service Spooler).WaitForStatus('Running', '00:00:30')
```

## Critical services — don't touch without explicit instruction

Stopping these can lock Marty out, break networking, or prevent updates. Always confirm before stopping or disabling:

- `LanmanServer`, `LanmanWorkstation` — file sharing
- `Dnscache` — DNS resolution
- `Dhcp` — DHCP client
- `EventLog` — event log (many things depend on it)
- `RpcSs`, `RpcEptMapper` — RPC, foundational
- `wuauserv` — Windows Update
- `WinDefend`, `SecurityHealthService` — Defender (don't disable without explicit instruction)
- `Audiosrv` — audio
- `Schedule` — Task Scheduler

## Common pattern: "set to manual to reduce startup time"

Before changing a service to `Manual` or `Disabled`:

1. Identify which apps actually depend on it (`Get-Service -RequiredServices` and search the web for the service name).
2. Show Marty the proposed change *and* the inverse command to revert.
3. Apply, then verify with `Get-Service` after a reboot — services with on-demand start can show `Stopped` even when working correctly.

## Service account changes

Changing the account a service runs as is high-impact. Use:

```powershell
sc.exe config <service> obj= "DOMAIN\User" password= "<pwd>"
```

Confirm with Marty and warn about lockouts and password rotation.
