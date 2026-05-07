---
name: windows-system-settings
description: "[windows] Common Windows 11 UI/UX tweaks — Explorer, taskbar, dark mode, privacy, focus. Mostly registry-backed; restart Explorer to apply."
---

# windows-system-settings

Use this skill for everyday Windows 11 tweaks: Explorer view options, taskbar behavior, theme, privacy/telemetry, focus assist, default apps. Most settings live in the registry under `HKCU` (no admin needed). Defer to the `windows-registry` skill for the underlying read/write/backup pattern.

## Apply pattern

After any change that affects Explorer or the taskbar:

```powershell
Stop-Process -Name explorer -Force   # explorer auto-restarts
```

Theme changes usually take effect immediately. Some privacy/policy changes need a sign-out.

## Explorer view

```powershell
$key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

# Show hidden files
Set-ItemProperty -Path $key -Name "Hidden" -Value 1 -Type DWord       # 1 show, 2 hide

# Show file extensions
Set-ItemProperty -Path $key -Name "HideFileExt" -Value 0 -Type DWord  # 0 show, 1 hide

# Show full path in title bar (legacy)
Set-ItemProperty -Path $key -Name "ShowFullPathInTitleBar" -Value 1 -Type DWord

# Open File Explorer to "This PC" (1) instead of Quick access / Home (2)
Set-ItemProperty -Path $key -Name "LaunchTo" -Value 1 -Type DWord

# Use compact spacing (Win11 only)
Set-ItemProperty -Path $key -Name "UseCompactMode" -Value 1 -Type DWord
```

## Disable Explorer grouping

Win11 22H2+ auto-groups the Downloads folder by date and occasionally lets `Group by` settings sneak into other folders. To enforce "no grouping" as the default for every folder template:

```powershell
$base = 'HKCU:\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell'
$templates = [ordered]@{
  Generic   = '{5C4F28B5-F869-4E84-8E60-F11DB97C5CC7}'
  Documents = '{7D49D726-3C21-4F05-99AA-FDC2C9474656}'
  Pictures  = '{B3690E58-E961-423B-B687-386EBFD83239}'
  Music     = '{94D6DDCC-4A68-4175-A374-BD584A510B78}'
  Videos    = '{5FA96407-7E77-483C-AC93-691D05850DE8}'
}
foreach ($guid in $templates.Values) {
  $path = "$base\$guid"
  New-Item -Path $path -Force | Out-Null
  Set-ItemProperty -Path $path -Name 'Mode'             -Value 4 -Type DWord  # Details view
  Set-ItemProperty -Path $path -Name 'LogicalViewMode'  -Value 1 -Type DWord
  Set-ItemProperty -Path $path -Name 'GroupView'        -Value 0 -Type DWord  # the kill switch
  Set-ItemProperty -Path $path -Name 'GroupByKey:FMTID' -Value '' -Type String
}
Stop-Process -Name explorer -Force
```

Back up `HKCU:\Software\Microsoft\Windows\Shell\Bags`, `HKCU:\Software\Microsoft\Windows\Shell\BagMRU`, and `HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags` first via `reg export` (the `windows-registry` skill's pattern).

This sets defaults for folders that don't yet have a Bag entry. Folders with sticky existing Bags ignore the new defaults — the manual fix for those is **... → Options → View** tab → **Apply to Folders** while viewing a no-group folder of that template.

**Downloads-specific auto-group-by-date** is its own beast — Win11 applies it because the folder uses the *Downloads* template, not because of any `GroupView` setting. The fix has no clean registry equivalent: right-click the Downloads folder → Properties → Customize tab → **Optimize this folder for: General items** → ✓ Also apply to subfolders → OK. After this, Downloads inherits the Generic template's `GroupView=0` default.

## Taskbar (Win11)

```powershell
$key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

# Taskbar alignment: 0 = left, 1 = center
Set-ItemProperty -Path $key -Name "TaskbarAl" -Value 0 -Type DWord

# Hide search box: 0 hidden, 1 icon, 2 search box, 3 search box+label
$searchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
Set-ItemProperty -Path $searchKey -Name "SearchboxTaskbarMode" -Value 1 -Type DWord

# Hide Task View button
Set-ItemProperty -Path $key -Name "ShowTaskViewButton" -Value 0 -Type DWord

# Hide Widgets / News
Set-ItemProperty -Path $key -Name "TaskbarDa" -Value 0 -Type DWord

# Hide Chat / Teams
Set-ItemProperty -Path $key -Name "TaskbarMn" -Value 0 -Type DWord
```

## Dark mode

```powershell
$key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"

Set-ItemProperty -Path $key -Name "AppsUseLightTheme"    -Value 0 -Type DWord  # 0 dark, 1 light
Set-ItemProperty -Path $key -Name "SystemUsesLightTheme" -Value 0 -Type DWord
```

## Privacy / telemetry / suggestions

```powershell
# Disable advertising ID (per-user)
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Type DWord

# Stop "suggestions" / consumer features in Start menu
$cd = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
Set-ItemProperty -Path $cd -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord  # Start suggestions
Set-ItemProperty -Path $cd -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord  # Settings tips
Set-ItemProperty -Path $cd -Name "SystemPaneSuggestionsEnabled"   -Value 0 -Type DWord
Set-ItemProperty -Path $cd -Name "SilentInstalledAppsEnabled"     -Value 0 -Type DWord

# Lock screen tips/ads
Set-ItemProperty -Path $cd -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord
```

Telemetry level (`HKLM`, needs admin) is intentionally not enumerated here — confirm with Marty before touching machine-wide telemetry policy.

## Focus / Do Not Disturb

Focus Assist state lives at `HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.QuietHours` and is messy to manipulate via registry. Prefer the Settings UI for one-off changes; only automate it if Marty asks for an unattended pattern.

## Mouse and keyboard

```powershell
# Disable mouse acceleration ("enhance pointer precision")
$mouse = "HKCU:\Control Panel\Mouse"
Set-ItemProperty -Path $mouse -Name "MouseSpeed"      -Value "0" -Type String
Set-ItemProperty -Path $mouse -Name "MouseThreshold1" -Value "0" -Type String
Set-ItemProperty -Path $mouse -Name "MouseThreshold2" -Value "0" -Type String
# Sign out and back in to apply
```

## Default apps

Default app associations are signed and can't be set reliably from PowerShell on Windows 10+ without using `dism /Online /Export-DefaultAppAssociations` (per-machine, needs admin). For Marty's per-user defaults, point him at `Settings > Apps > Default apps`.

## Always

- Back up the affected key first (see `windows-registry`).
- Note the inverse (the value to flip back).
- Restart Explorer when needed; otherwise the change is invisible.
- Don't combine many tweaks into one big sweep — apply one or two, confirm they work, then continue.
