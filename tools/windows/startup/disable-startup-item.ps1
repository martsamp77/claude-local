<#
.NAME        disable-startup-item
.SYNOPSIS    Reversibly disable (or -Undo) a startup item: auto-start service, Run entry, and/or running processes. Backs up first.
.PLATFORM    windows
.CATEGORY    startup
.USAGE       .\tools\windows\startup\disable-startup-item.ps1 -Preset LogiOptionsPlus [-Undo] [-DryRun]
             .\tools\windows\startup\disable-startup-item.ps1 -Service <svc> [-ServiceStartupType Disabled|Manual] -RunEntry <name> [-RunHive HKLM|HKCU] -KillProcess <proc> [-Undo] [-DryRun]
.WHEN        "disable logi / logitech options+", "stop X from auto-starting", "apply the perf tweaks / debloat this machine",
             "re-enable X" (pass -Undo). The action counterpart to the read-only startup-inventory.ps1.
.NOTES       Service + HKLM Run changes need an elevated shell. Run it non-elevated and it prints a ready-to-paste RunAs command
             instead of auto-elevating (per CLAUDE.md). Reversible: -Undo sets the service back to Automatic+Started and
             re-enables the Run entry. Killed processes relaunch on next logon / when the app is opened.
#>

[CmdletBinding()]
param(
    # Named bundle of service/run/process targets for a known offender. See $Presets below.
    [string]$Preset,

    # Ad-hoc service name(s) to stop + change startup type.
    [string[]]$Service,
    [ValidateSet('Disabled','Manual')]
    [string]$ServiceStartupType = 'Disabled',

    # Ad-hoc Run value name(s) to soft-disable via the StartupApproved flag.
    [string[]]$RunEntry,
    [ValidateSet('HKLM','HKCU')]
    [string]$RunHive = 'HKLM',

    # Ad-hoc process name(s) to stop now (no .exe).
    [string[]]$KillProcess,

    # Reverse the operation: service -> Automatic + Started, Run entry -> enabled.
    [switch]$Undo,

    # Show what would happen; change nothing.
    [switch]$DryRun,

    # Override the critical-service guard (see windows-services skill list).
    [switch]$Force,

    # Save a transcript under logs/windows/startup/.
    [switch]$SaveLog
)

$ErrorActionPreference = 'Continue'

# tools/windows/startup/ -> repo root
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

# ---- output buffer (console + optional log) ------------------------------
$script:logLines = New-Object System.Collections.Generic.List[string]
function Say {
    param([string]$Msg = '', [System.ConsoleColor]$Color)
    $script:logLines.Add($Msg)
    if ($PSBoundParameters.ContainsKey('Color')) { Write-Host $Msg -ForegroundColor $Color } else { Write-Host $Msg }
}

# ---- presets: known startup offenders ------------------------------------
# To add one, copy the shape. Services carry their own StartupType; RunEntries
# carry their own Hive. Keep names verified against a real machine.
$Presets = @{
    LogiOptionsPlus = @{
        Description = 'Logitech Options+ — logioptionsplus_agent (~135MB) + appbroker/updater + LogiPluginService(+Ext), its auto-start updater service, and the legacy Logitech Download Assistant nagger.'
        Services    = @( @{ Name = 'OptionsPlusUpdaterService'; StartupType = 'Disabled' } )
        RunEntries  = @( @{ Hive = 'HKLM'; Name = 'Logitech Download Assistant' } )
        Processes   = @('logioptionsplus_agent', 'logioptionsplus_appbroker', 'logioptionsplus_updater', 'LogiPluginService', 'LogiPluginServiceExt')
        Note        = "Also open Logi Options+ -> Settings -> uncheck 'Open at startup' so the app doesn't re-register itself."
    }
}

# Critical services — never touch without -Force (mirrors the windows-services skill).
$CriticalServices = @(
    'LanmanServer', 'LanmanWorkstation', 'Dnscache', 'Dhcp', 'EventLog',
    'RpcSs', 'RpcEptMapper', 'wuauserv', 'WinDefend', 'SecurityHealthService',
    'Audiosrv', 'Schedule'
)

# ---- helpers -------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Get-RunPath      { param($Hive) "${Hive}:\Software\Microsoft\Windows\CurrentVersion\Run" }
function Get-ApprovedPath { param($Hive) "${Hive}:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" }

function Get-ApprovedState {
    param([string]$Hive, [string]$Name)
    $p = Get-ApprovedPath $Hive
    if (-not (Test-Path $p)) { return 'NO-RECORD' }
    $v = (Get-ItemProperty -Path $p -Name $Name -ErrorAction SilentlyContinue).$Name
    if (-not $v) { return 'NO-RECORD' }
    switch ($v[0]) { 2 { 'ENABLED' } 6 { 'ENABLED' } 3 { 'DISABLED' } default { "RAW=$($v[0])" } }
}

# ---- resolve targets -----------------------------------------------------
$svcTargets  = New-Object System.Collections.Generic.List[object]
$runTargets  = New-Object System.Collections.Generic.List[object]
$procTargets = New-Object System.Collections.Generic.List[string]
$presetNote  = $null

if ($Preset) {
    $p = $Presets[$Preset]
    if (-not $p) {
        Say "Unknown preset '$Preset'. Available: $($Presets.Keys -join ', ')" Red
        exit 2
    }
    foreach ($s in $p.Services)   { $svcTargets.Add([pscustomobject]@{ Name = $s.Name; StartupType = $s.StartupType }) }
    foreach ($r in $p.RunEntries) { $runTargets.Add([pscustomobject]@{ Hive = $r.Hive; Name = $r.Name }) }
    foreach ($x in $p.Processes)  { $procTargets.Add($x) }
    $presetNote = $p.Note
}
foreach ($s in $Service)     { $svcTargets.Add([pscustomobject]@{ Name = $s; StartupType = $ServiceStartupType }) }
foreach ($r in $RunEntry)    { $runTargets.Add([pscustomobject]@{ Hive = $RunHive; Name = $r }) }
foreach ($x in $KillProcess) { $procTargets.Add($x) }

if ($svcTargets.Count -eq 0 -and $runTargets.Count -eq 0 -and $procTargets.Count -eq 0) {
    Say "Nothing to do. Specify -Preset <name>, or -Service / -RunEntry / -KillProcess." Yellow
    Say "Available presets: $($Presets.Keys -join ', ')"
    exit 2
}

$mode = if ($Undo) { 'RE-ENABLE' } else { 'DISABLE' }
Say ""
Say "=== $mode startup item$(if($Preset){" [$Preset]"})  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" Cyan
if ($Preset -and $Presets[$Preset].Description) { Say "  $($Presets[$Preset].Description)" }
if ($DryRun) { Say "  (DryRun — no changes will be made)" DarkGray }
Say ""

# ---- elevation gate ------------------------------------------------------
$needsAdmin = ($svcTargets.Count -gt 0) -or (@($runTargets | Where-Object { $_.Hive -eq 'HKLM' }).Count -gt 0)
if ($needsAdmin -and -not (Test-Admin) -and -not $DryRun) {
    Say "This operation changes a service and/or an HKLM Run entry — it needs an elevated shell." Yellow
    Say "Not auto-elevating (per CLAUDE.md). Paste this into an admin PowerShell:" Yellow
    function Quote($s) { '"' + ([string]$s -replace '"', '""') + '"' }
    $a = New-Object System.Collections.Generic.List[string]
    $a.Add('-NoProfile'); $a.Add('-ExecutionPolicy'); $a.Add('Bypass'); $a.Add('-File'); $a.Add((Quote $PSCommandPath))
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if     ($v -is [switch]) { if ($v.IsPresent) { $a.Add("-$k") } }
        elseif ($v -is [array])  { $a.Add("-$k"); $a.Add(($v | ForEach-Object { Quote $_ }) -join ',') }
        else                     { $a.Add("-$k"); $a.Add((Quote $v)) }
    }
    $argList = ($a | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', '
    Say ""
    Say "  Start-Process pwsh -Verb RunAs -ArgumentList $argList" White
    Say ""
    exit 1
}

# ---- backup (forward + undo both write registry/service config) ----------
if (-not $DryRun) {
    $stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
    $label     = if ($Preset) { $Preset } else { 'adhoc' }
    $backupDir = Join-Path $repoRoot 'backups\windows\registry'
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

    $exports = New-Object System.Collections.Generic.List[object]
    foreach ($s in $svcTargets) {
        $exports.Add(@{ Key = "HKLM\SYSTEM\CurrentControlSet\Services\$($s.Name)"; File = "$stamp-$label-svc-$($s.Name).reg" })
    }
    foreach ($hive in ($runTargets | ForEach-Object { $_.Hive } | Select-Object -Unique)) {
        $runKey      = (Get-RunPath $hive).Replace(':', '')
        $approvedKey = (Get-ApprovedPath $hive).Replace(':', '')
        $exports.Add(@{ Key = $runKey;      File = "$stamp-$label-$hive-Run.reg" })
        $exports.Add(@{ Key = $approvedKey; File = "$stamp-$label-$hive-StartupApproved-Run.reg" })
    }
    foreach ($e in $exports) {
        $dest = Join-Path $backupDir $e.File
        & reg.exe export $e.Key $dest /y *> $null
        if (Test-Path $dest) { Say "  backed up $($e.Key)" DarkGray }
        else                 { Say "  (no backup — key absent: $($e.Key))" DarkGray }
    }
    Say ""
}

# ===================== FORWARD (disable) ==================================
if (-not $Undo) {

    # 1) Services first, so they don't respawn the processes we kill next.
    foreach ($s in $svcTargets) {
        if ($CriticalServices -contains $s.Name -and -not $Force) {
            Say "  SKIP service $($s.Name): critical service — pass -Force to override." Red
            continue
        }
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        if (-not $svc) { Say "  service $($s.Name): not found (skipped)" DarkGray; continue }
        if ($DryRun) {
            Say "  [DryRun] Stop-Service $($s.Name) -Force; Set-Service $($s.Name) -StartupType $($s.StartupType)" DarkGray
            continue
        }
        try { Stop-Service -Name $s.Name -Force -ErrorAction Stop; Say "  stopped service $($s.Name)" Green }
        catch { Say "  service $($s.Name): stop failed — $($_.Exception.Message)" Yellow }
        try { Set-Service -Name $s.Name -StartupType $s.StartupType -ErrorAction Stop; Say "  set $($s.Name) startup = $($s.StartupType)" Green }
        catch { Say "  service $($s.Name): set startup failed — $($_.Exception.Message)" Red }
    }

    # 2) Kill running processes (free the RAM now).
    foreach ($name in $procTargets) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if (-not $procs) { Say "  process ${name}: not running" DarkGray; continue }
        if ($DryRun) { Say "  [DryRun] Stop-Process -Name $name -Force  ($($procs.Count) running)" DarkGray; continue }
        try { $procs | Stop-Process -Force -ErrorAction Stop; Say "  killed process $name ($($procs.Count))" Green }
        catch { Say "  process ${name}: kill failed — $($_.Exception.Message)" Yellow }
    }

    # 3) Soft-disable Run entries via StartupApproved (leaves the Run value intact).
    foreach ($r in $runTargets) {
        $runPath = Get-RunPath $r.Hive
        $exists  = (Get-ItemProperty -Path $runPath -Name $r.Name -ErrorAction SilentlyContinue).$($r.Name)
        if (-not $exists) { Say "  Run[$($r.Hive)] $($r.Name): no such entry (skipped)" DarkGray; continue }
        if ($DryRun) { Say "  [DryRun] disable StartupApproved $($r.Hive)\...\Run '$($r.Name)' (byte 0x03)" DarkGray; continue }
        $ap = Get-ApprovedPath $r.Hive
        if (-not (Test-Path $ap)) { New-Item -Path $ap -Force | Out-Null }
        New-ItemProperty -Path $ap -Name $r.Name -PropertyType Binary `
            -Value ([byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -Force | Out-Null
        Say "  disabled Run[$($r.Hive)] '$($r.Name)'" Green
    }
}

# ===================== UNDO (re-enable) ===================================
else {

    foreach ($s in $svcTargets) {
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        if (-not $svc) { Say "  service $($s.Name): not found (skipped)" DarkGray; continue }
        if ($DryRun) { Say "  [DryRun] Set-Service $($s.Name) -StartupType Automatic; Start-Service $($s.Name)" DarkGray; continue }
        try { Set-Service -Name $s.Name -StartupType Automatic -ErrorAction Stop; Say "  set $($s.Name) startup = Automatic" Green }
        catch { Say "  service $($s.Name): set startup failed — $($_.Exception.Message)" Red }
        try { Start-Service -Name $s.Name -ErrorAction Stop; Say "  started service $($s.Name)" Green }
        catch { Say "  service $($s.Name): start failed — $($_.Exception.Message)" Yellow }
    }

    foreach ($r in $runTargets) {
        if ($DryRun) { Say "  [DryRun] enable StartupApproved $($r.Hive)\...\Run '$($r.Name)' (byte 0x02)" DarkGray; continue }
        $ap = Get-ApprovedPath $r.Hive
        if (-not (Test-Path $ap)) { New-Item -Path $ap -Force | Out-Null }
        New-ItemProperty -Path $ap -Name $r.Name -PropertyType Binary `
            -Value ([byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -Force | Out-Null
        Say "  enabled Run[$($r.Hive)] '$($r.Name)'" Green
    }

    if ($procTargets.Count -gt 0) {
        Say "  (processes re-launch on next logon or when you open the app)" DarkGray
    }
}

# ---- verify --------------------------------------------------------------
Say ""
Say "--- state after ---" Cyan
foreach ($s in $svcTargets) {
    $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
    if ($svc) {
        $cim = Get-CimInstance Win32_Service -Filter "Name='$($s.Name)'" -ErrorAction SilentlyContinue
        Say ("  service {0,-28} {1,-9} start={2}" -f $s.Name, $svc.Status, $cim.StartMode)
    }
}
foreach ($name in $procTargets) {
    $n = @(Get-Process -Name $name -ErrorAction SilentlyContinue).Count
    Say ("  process {0,-28} {1}" -f $name, $(if ($n) { "RUNNING ($n)" } else { 'not running' }))
}
foreach ($r in $runTargets) {
    Say ("  Run[{0}] {1,-34} {2}" -f $r.Hive, $r.Name, (Get-ApprovedState $r.Hive $r.Name))
}

if ($presetNote) { Say ""; Say "Note: $presetNote" Yellow }
Say ""
Say "Re-run .\tools\windows\startup\startup-inventory.ps1 to confirm the full picture." DarkGray

# ---- optional log --------------------------------------------------------
if ($SaveLog) {
    $logDir = Join-Path $repoRoot 'logs\windows\startup'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logFile = Join-Path $logDir ("{0}-disable-{1}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $(if ($Preset) { $Preset } else { 'adhoc' }))
    $script:logLines | Out-File -FilePath $logFile -Encoding utf8
    Say "Log saved: $logFile" DarkGray
}

exit 0
