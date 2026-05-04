<#
.NAME        startup-inventory
.SYNOPSIS    Read-only audit of every Windows startup vector with enable/disable state.
.CATEGORY    startup
.USAGE       .\tools\startup\startup-inventory.ps1 [-IncludeMicrosoftTasks] [-SaveLog]
.WHEN        "what's launching at startup", "audit my startup items", "what should I disable",
             "why is my machine slow on boot", before recommending startup changes.
#>

[CmdletBinding()]
param(
    [switch]$IncludeMicrosoftTasks,
    [switch]$SaveLog
)

$ErrorActionPreference = 'Continue'

# Resolve repo root from script location (tools/startup/ -> repo root)
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# StartupApproved byte[0] state decode
function Get-StartupApprovedState {
    param([byte[]]$Bytes)
    if (-not $Bytes -or $Bytes.Length -eq 0) { return 'UNKNOWN' }
    switch ($Bytes[0]) {
        2 { 'ENABLED' }
        6 { 'ENABLED' }
        3 { 'DISABLED' }
        default { "RAW=$($Bytes[0])" }
    }
}

# Build cross-referenced state map for a Run key by querying its StartupApproved sibling
function Get-StartupApprovedMap {
    param([string]$ApprovedPath)
    $map = @{}
    if (-not (Test-Path $ApprovedPath)) { return $map }
    $vals = Get-ItemProperty -Path $ApprovedPath -ErrorAction SilentlyContinue
    foreach ($p in $vals.PSObject.Properties) {
        if ($p.Name -like 'PS*') { continue }
        $map[$p.Name] = Get-StartupApprovedState -Bytes $p.Value
    }
    return $map
}

$out = New-Object System.Collections.Generic.List[string]
function Add-Line { param($s = '') $out.Add([string]$s) }

Add-Line "=== STARTUP INVENTORY  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
Add-Line ""

# 1. Run / RunOnce registry keys (with StartupApproved cross-reference)
$runKeys = @(
    @{ Run='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';                                Approved='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
    @{ Run='HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce';                            Approved=$null }
    @{ Run='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';                                Approved='HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
    @{ Run='HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce';                            Approved=$null }
    @{ Run='HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';                    Approved='HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
    @{ Run='HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce';                Approved=$null }
)

foreach ($k in $runKeys) {
    Add-Line "--- $($k.Run) ---"
    if (-not (Test-Path $k.Run)) { Add-Line "  (key missing)"; Add-Line ""; continue }
    $approvedMap = if ($k.Approved) { Get-StartupApprovedMap -ApprovedPath $k.Approved } else { @{} }
    $vals = Get-ItemProperty -Path $k.Run -ErrorAction SilentlyContinue
    $any = $false
    foreach ($p in $vals.PSObject.Properties) {
        if ($p.Name -like 'PS*' -or $p.Name -eq '(default)') { continue }
        $any = $true
        $state = if ($approvedMap.ContainsKey($p.Name)) { $approvedMap[$p.Name] } else { 'NO-RECORD' }
        Add-Line ("  [{0,-9}] {1,-40}  {2}" -f $state, $p.Name, $p.Value)
    }
    if (-not $any) { Add-Line "  (empty)" }
    Add-Line ""
}
Add-Line "Note: NO-RECORD = entry runs but has never been toggled in Task Manager (no StartupApproved entry)."
Add-Line ""

# 2. Startup folders (user + machine)
$folders = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
)
$approvedFolderMaps = @{
    'User'    = Get-StartupApprovedMap -ApprovedPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
    'Machine' = Get-StartupApprovedMap -ApprovedPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
}
foreach ($f in $folders) {
    $scope = if ($f -like "$env:APPDATA*") { 'User' } else { 'Machine' }
    Add-Line "--- Startup folder ($scope) ---"
    Add-Line "  $f"
    if (-not (Test-Path $f)) { Add-Line "  (missing)"; Add-Line ""; continue }
    $items = Get-ChildItem -Path $f -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'desktop.ini' }
    if (-not $items) { Add-Line "  (empty)" }
    foreach ($i in $items) {
        $state = if ($approvedFolderMaps[$scope].ContainsKey($i.Name)) { $approvedFolderMaps[$scope][$i.Name] } else { 'NO-RECORD' }
        $target = $i.FullName
        if ($i.Extension -eq '.lnk') {
            try {
                $sh = New-Object -ComObject WScript.Shell
                $lnk = $sh.CreateShortcut($i.FullName)
                $target = "$($lnk.TargetPath) $($lnk.Arguments)".Trim()
            } catch { }
        }
        Add-Line ("  [{0,-9}] {1,-40}  -> {2}" -f $state, $i.Name, $target)
    }
    Add-Line ""
}

# 3. Scheduled tasks with logon/boot triggers (filter to third-party by default)
Add-Line "--- Logon/Boot scheduled tasks ---"
$tasks = Get-ScheduledTask | Where-Object {
    $_.State -ne 'Disabled' -and (
        $_.Triggers.CimClass.CimClassName -contains 'MSFT_TaskLogonTrigger' -or
        $_.Triggers.CimClass.CimClassName -contains 'MSFT_TaskBootTrigger'
    )
}
if (-not $IncludeMicrosoftTasks) {
    $tasks = $tasks | Where-Object {
        $_.TaskPath -notlike '\Microsoft\*' -and
        $_.TaskPath -notlike '\Microsoft Corporation\*'
    }
}
$rows = foreach ($t in $tasks) {
    $trigType = ($t.Triggers | ForEach-Object { ($_.CimClass.CimClassName -replace 'MSFT_Task','') -replace 'Trigger','' }) -join ','
    $action = ($t.Actions | ForEach-Object { ("$($_.Execute) $($_.Arguments)").Trim() }) -join ' | '
    [PSCustomObject]@{
        Trigger = $trigType
        Path    = "$($t.TaskPath)$($t.TaskName)"
        Author  = $t.Author
        Action  = $action
    }
}
if (-not $rows) {
    Add-Line "  (none — pass -IncludeMicrosoftTasks to also list MS internal tasks)"
} else {
    foreach ($r in ($rows | Sort-Object Path)) {
        Add-Line ("  [{0}] {1}" -f $r.Trigger, $r.Path)
        if ($r.Author) { Add-Line ("        author: {0}" -f $r.Author) }
        Add-Line ("        runs:   {0}" -f $r.Action)
    }
}
Add-Line ""

# 4. Auto-start non-svchost services. Path-substring filtering is unreliable
# (many third-party drivers live under C:\Windows\System32) so we list everything
# auto-start that isn't hosted by svchost and let the reader scan it.
Add-Line "--- Auto-start services (non-svchost) ---"
$svcs = Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue |
    Where-Object {
        $_.StartMode -in 'Auto','Automatic' -and
        $_.PathName -notlike '*\system32\svchost.exe*' -and
        $_.PathName -notlike '*\System32\svchost.exe*'
    }
foreach ($s in ($svcs | Sort-Object State,DisplayName -Descending)) {
    $stateTag = if ($s.State -eq 'Running') { 'RUNNING ' } else { 'STOPPED ' }
    Add-Line ("  [{0}] {1,-32}  {2}" -f $stateTag, $s.Name, $s.DisplayName)
    Add-Line ("              path: {0}" -f $s.PathName)
}
if (-not $svcs) { Add-Line "  (none detected)" }
Add-Line ""

Add-Line "=== END ==="

# Emit to console
$out | ForEach-Object { Write-Output $_ }

# Optional log file
if ($SaveLog) {
    $logDir = Join-Path $repoRoot 'logs\startup'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logFile = Join-Path $logDir "$stamp-startup-inventory.txt"
    $out | Out-File -FilePath $logFile -Encoding utf8
    Write-Output ""
    Write-Output "Log saved: $logFile"
}
