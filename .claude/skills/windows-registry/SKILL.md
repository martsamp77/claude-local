---
name: windows-registry
description: Safely read, write, and back up the Windows registry from PowerShell. Use whenever a task involves HKCU/HKLM keys.
---

# windows-registry

Use this skill any time a task requires reading or writing the Windows registry — system tweaks, app config, autostart entries, file associations, group policy.

## Backup first — always

Before any write or delete, export the affected key:

```powershell
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = "C:\DATA\Workspace-37m\claude-local\backups\registry"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "$backupDir\explorer-advanced-$ts.reg" /y
```

`reg export` uses backslash-style hive paths (`HKCU\...`), not the PowerShell drive form. Both `HKCU` and `HKLM` work with it. Restore is `reg import <file>.reg`.

## PowerShell drive form

In PowerShell, hives are PSDrives:

- `HKCU:\Software\...` — current user
- `HKLM:\Software\...` — machine-wide (needs admin)
- `HKCR:`, `HKU:`, `HKCC:` — also available

## Read

```powershell
Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden"
Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" | Format-List
```

To check if a value exists without erroring:

```powershell
(Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
```

## Write

```powershell
# Existing key, set or update value
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1 -Type DWord

# Create the key first if it might not exist
New-Item -Path "HKCU:\Software\MyApp" -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\MyApp" -Name "Setting" -Value "value" -PropertyType String -Force
```

Common `-Type` / `-PropertyType` values: `String`, `ExpandString`, `DWord`, `QWord`, `Binary`, `MultiString`.

## Delete

```powershell
Remove-ItemProperty -Path $path -Name $name        # remove a value
Remove-Item -Path $path -Recurse                   # remove a key and its subkeys
```

## Scope rules

- **HKCU** writes apply to Marty only, no admin needed. Default to these.
- **HKLM** writes are machine-wide and need an elevated shell. Confirm with Marty before each `HKLM` write — say which key, what value, what the inverse is.
- Group Policy keys live under `HKCU\Software\Policies\...` and `HKLM\Software\Policies\...`.

## Common locations worth knowing

- `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` — taskbar, Explorer view options
- `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run` — per-user autostart
- `HKLM:\Software\Microsoft\Windows\CurrentVersion\Run` — machine autostart
- `HKCU:\Control Panel\Desktop` — desktop/UI settings
- `HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` — theme/dark mode
- `HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` — suggestions/ads in Start

## Making changes visible

Some changes need a process restart to take effect:

- Explorer/taskbar tweaks — `Stop-Process -Name explorer` (it restarts automatically)
- Theme changes — usually visible immediately, sometimes need sign-out
- Environment variables — see `windows-env-vars` skill (broadcast `WM_SETTINGCHANGE`)
