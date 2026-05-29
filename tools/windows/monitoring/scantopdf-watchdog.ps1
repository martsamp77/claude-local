<#
.NAME        scantopdf-watchdog
.SYNOPSIS    Self-healing watchdog for ScanToPDF: restarts the stopped service, kills the hung UI and orphaned OCR engines, and quarantines oversized poison files that cause repeat lockups.
.PLATFORM    windows
.CATEGORY    monitoring
.USAGE       .\tools\windows\monitoring\scantopdf-watchdog.ps1 [-DryRun] [-SaveLog] [-QuarantineSizeMB 20] [-HotFolder <path>] [-NoAlert]
.WHEN        "ScanToPDF keeps locking up", "the scanner service hangs at night", scheduled every few minutes as SYSTEM to auto-recover ScanToPDF on MD-FS01. Run with -DryRun first to see what it would do.
#>
# ---------------------------------------------------------------------------
# Background: ScanToPDF (MD-FS01) hangs when a large end-of-day batch (250-500
# page / 25-35 MB PDF) drives the aged Transym OCR engine (TOCRRService.exe) to
# access-violate. The 32-bit UI then stops responding (Event ID 1002) and the
# unconsumed source PDF gets retried on every restart -> repeat lockups.
# A hang is NOT a service failure, so the existing SCM failure-action never fires.
# This watchdog catches all of those cases on a timer and self-heals.
# See docs/windows/scantopdf-lockup-runbook.md for the full diagnosis.
# ---------------------------------------------------------------------------

[CmdletBinding()]
param(
    # Show what would happen, change nothing. Safe to run unelevated.
    [switch]$DryRun,
    # Also write this run's report to logs\windows\monitoring\ in the repo.
    [switch]$SaveLog,
    # Windows service to keep running.
    [string]$ServiceName = 'ScanToPDFService',
    # Interactive UI process names (no .exe) to watch for hangs.
    [string[]]$UiProcessNames = @('ScanToPDF', 'ScanToPDFB10'),
    # AutoFileImport hot folder watched by the ScanToPDF service.
    [string]$HotFolder = 'E:\Assurance Labs\Assurance Scientific\ASL- To be billed\ScanToPDF\Scan to PDF',
    # Where poison files get moved. Defaults to a sibling of the hot folder.
    [string]$QuarantineFolder,
    # A hot-folder PDF at/above this size is a candidate for the poison-file guard.
    [int]$QuarantineSizeMB = 20,
    # An oversized file must persist this many watchdog cycles (while instability is seen) before quarantine.
    [int]$QuarantinePersistCycles = 3,
    # ...or this many minutes regardless, after which it is clearly stuck.
    [int]$QuarantineHardAgeMinutes = 30,
    # Flap guard: at most this many service restarts inside the rolling window.
    [int]$MaxRestartsPerWindow = 3,
    [int]$RestartWindowMinutes = 30,
    # Seconds to wait before re-confirming a "not responding" UI (avoids killing a healthy busy app).
    [int]$HangConfirmSeconds = 20,
    # Alert if this many TOCR OCR crashes appear in the recent event-log window.
    [int]$OcrCrashAlertCount = 2,
    [int]$OcrCrashWindowMinutes = 15,
    # Warn when a 32-bit ScanToPDF process working set crosses this (approaching the ~2 GB ceiling).
    [int]$UiMemoryWarnMB = 1500,
    # Runtime state + durable log live here (independent of the repo location).
    [string]$StateDir = "$env:ProgramData\ScanToPDF-Watchdog",
    # Teams Incoming Webhook (reuses the channel already wired in C:\Scripts\Alerting-WindowsService.ps1).
    [string]$WebhookUrl = 'https://moleculardesigns.webhook.office.com/webhookb2/436676ff-7925-463b-8d8f-da16d54f7fd9@5822f0cb-d532-4afc-ab6c-137d04895edb/IncomingWebhook/9b1809f811674800a29d3d8169782fdd/892388b5-7e62-4284-95f3-d5392f2c77f8',
    # Suppress Teams + event-log alerts (still writes the local log).
    [switch]$NoAlert,
    # Custom event log + source already registered on the box by the alerting script.
    [string]$EventLogName    = 'ScanToPDF Alerting',
    [string]$EventLogSource  = 'ScanToPDF Alerting Script'
)

$ErrorActionPreference = 'Stop'
if (-not $QuarantineFolder) {
    $QuarantineFolder = Join-Path (Split-Path -Parent $HotFolder) 'Scan2PDF_Quarantine'
}

# -- output plumbing ---------------------------------------------------------
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$report    = [System.Collections.Generic.List[string]]::new()
$tag       = if ($DryRun) { '[DRYRUN] ' } else { '' }
# Anything the watchdog actually did (or would do) this run, for the summary alert.
$actionsTaken = [System.Collections.Generic.List[string]]::new()

function Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR', 'ACTION')][string]$Level = 'INFO')
    $line = '{0} - {1,-6} - {2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $tag, $Message
    $report.Add($line)
    $color = switch ($Level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'ACTION' { 'Green' } default { 'Gray' } }
    Write-Host $line -ForegroundColor $color
}

# Do (or, in DryRun, only describe) a state-changing action.
function Invoke-Action {
    param([string]$Description, [scriptblock]$Do)
    $actionsTaken.Add($Description)
    if ($DryRun) { Log "would: $Description" 'ACTION'; return }
    Log "doing: $Description" 'ACTION'
    try { & $Do } catch { Log "FAILED: $Description -- $($_.Exception.Message)" 'ERROR' }
}

# -- state file (rolling history for flap guard + poison-file persistence) -----
$stateFile = Join-Path $StateDir 'state.json'
function Get-State {
    if (Test-Path $stateFile) {
        try { return (Get-Content $stateFile -Raw | ConvertFrom-Json) } catch { }
    }
    [pscustomobject]@{ restarts = @(); uiKills = @(); bigFiles = [pscustomobject]@{} }
}
function Save-State($state) {
    if ($DryRun) { return }
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
    $state | ConvertTo-Json -Depth 6 | Set-Content -Path $stateFile -Encoding UTF8
}
# Keep a JSON array property as a plain string[] of ISO timestamps within the window.
function Trim-Window($items, [int]$minutes) {
    $cut = (Get-Date).ToUniversalTime().AddMinutes(-$minutes)
    @($items | Where-Object { $_ } | Where-Object { ([datetime]$_).ToUniversalTime() -ge $cut } | ForEach-Object { "$_" })
}

# -- alerting (Teams MessageCard + custom event log), mirrors the existing script --
function Send-Teams {
    param([string]$Title, [string]$Subtitle, [string]$Text)
    if ($NoAlert -or [string]::IsNullOrWhiteSpace($WebhookUrl)) { return }
    if ($DryRun) { Log "would post Teams card: $Title - $Subtitle" 'INFO'; return }
    $card = @{
        '@type'    = 'MessageCard'; '@context' = 'http://schema.org/extensions'
        summary    = 'ScanToPDF Watchdog'
        themeColor = 'D13438'
        sections   = @(@{ activityTitle = $Title; activitySubtitle = $Subtitle; activityText = $Text; markdown = $true })
    }
    try { Invoke-RestMethod -Uri $WebhookUrl -Method POST -ContentType 'application/json' -Body ($card | ConvertTo-Json -Depth 6 -Compress) | Out-Null }
    catch { Log "Teams webhook POST failed: $($_.Exception.Message)" 'WARN' }
}
function Write-AppEvent {
    param([string]$Message, [ValidateSet('Warning', 'Error', 'Information')][string]$EntryType = 'Warning', [int]$EventId = 1001)
    if ($NoAlert) { return }
    if ($DryRun) { Log "would write event ($EntryType/$EventId) to '$EventLogName'" 'INFO'; return }
    try { Write-EventLog -LogName $EventLogName -Source $EventLogSource -EntryType $EntryType -EventId $EventId -Message $Message }
    catch { Log "Event-log write failed (source '$EventLogSource' may be missing): $($_.Exception.Message)" 'WARN' }
}
function Send-Alert {
    param([string]$Title, [string]$Subtitle, [string]$Text, [ValidateSet('Warning', 'Error', 'Information')][string]$EntryType = 'Warning', [int]$EventId = 1001)
    Send-Teams -Title $Title -Subtitle $Subtitle -Text $Text
    Write-AppEvent -Message ("{0}: {1}`r`n{2}" -f $Title, $Subtitle, $Text) -EntryType $EntryType -EventId $EventId
}

# -- recent OCR-crash signal from the Windows Application log -------------------
function Get-RecentOcrCrashes {
    param([int]$Minutes)
    try {
        $ev = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = (Get-Date).AddMinutes(-$Minutes) } -ErrorAction Stop
        return @($ev | Where-Object { $_.Message -like '*TOCRR*' })
    } catch { return @() }
}

Log "ScanToPDF watchdog starting (DryRun=$DryRun) on $env:COMPUTERNAME" 'INFO'
$state = Get-State

# ===========================================================================
# 1) SERVICE - restart if stopped, with a flap guard.
# ===========================================================================
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$serviceWasDown = $false
if (-not $svc) {
    Log "Service '$ServiceName' not found on this machine." 'ERROR'
}
elseif ($svc.Status -ne 'Running') {
    $serviceWasDown = $true
    $recent = Trim-Window $state.restarts $RestartWindowMinutes
    Log "Service '$ServiceName' is $($svc.Status). Restarts in last $RestartWindowMinutes min: $($recent.Count)/$MaxRestartsPerWindow." 'WARN'
    if ($recent.Count -ge $MaxRestartsPerWindow) {
        Log "Flap guard tripped - NOT auto-restarting; escalating." 'ERROR'
        Send-Alert -Title 'ScanToPDF - service FLAPPING' -Subtitle "$env:COMPUTERNAME" `
            -Text "ScanToPDF service has been restarted $($recent.Count) times in $RestartWindowMinutes min and is $($svc.Status) again. Auto-restart suspended - likely a stuck/poison batch. Check the quarantine folder and the OCR engine." `
            -EntryType 'Error' -EventId 1010
    }
    else {
        Invoke-Action "Start-Service '$ServiceName'" { Start-Service -Name $ServiceName; (Get-Service $ServiceName).WaitForStatus('Running', '00:00:30') }
        $recent += (Get-Date).ToUniversalTime().ToString('o')
        $state.restarts = $recent
        Send-Alert -Title 'ScanToPDF - service auto-restarted' -Subtitle "$env:COMPUTERNAME" `
            -Text "Watchdog found '$ServiceName' $($svc.Status) and restarted it ($($recent.Count)/$MaxRestartsPerWindow in $RestartWindowMinutes min)."
    }
}
else {
    Log "Service '$ServiceName' is Running." 'INFO'
    $state.restarts = Trim-Window $state.restarts $RestartWindowMinutes
}

# ===========================================================================
# 2) UI - kill processes that have stopped responding (confirmed twice).
# ===========================================================================
$uiHangHandled = $false
$uiProcs = @()
foreach ($n in $UiProcessNames) { $uiProcs += Get-Process -Name $n -ErrorAction SilentlyContinue }
foreach ($p in $uiProcs) {
    $wsMB = [math]::Round($p.WorkingSet64 / 1MB, 0)
    $responding = $true
    try { $responding = $p.Responding } catch { $responding = $true }   # unknown -> treat as healthy
    if ($wsMB -ge $UiMemoryWarnMB) {
        Log "$($p.ProcessName) (PID $($p.Id)) working set ${wsMB}MB - approaching 32-bit memory ceiling." 'WARN'
        Send-Alert -Title 'ScanToPDF - UI memory high' -Subtitle "$env:COMPUTERNAME" -Text "$($p.ProcessName) PID $($p.Id) is using ${wsMB}MB. The 32-bit UI may be heading for an out-of-memory lockup on a large batch."
    }
    if (-not $responding) {
        Log "$($p.ProcessName) (PID $($p.Id)) is NOT responding. Confirming in ${HangConfirmSeconds}s..." 'WARN'
        if (-not $DryRun) { Start-Sleep -Seconds $HangConfirmSeconds }
        try { $p.Refresh(); $responding = $p.Responding } catch { }
        if (-not $responding) {
            $uiHangHandled = $true
            Invoke-Action "Stop hung UI $($p.ProcessName) (PID $($p.Id), ${wsMB}MB)" { Stop-Process -Id $p.Id -Force }
            $kills = Trim-Window $state.uiKills (24 * 60)
            $kills += (Get-Date).ToUniversalTime().ToString('o')
            $state.uiKills = $kills
            Send-Alert -Title 'ScanToPDF - hung UI killed' -Subtitle "$env:COMPUTERNAME" `
                -Text "$($p.ProcessName) (PID $($p.Id), ${wsMB}MB) stopped responding and was force-closed. An operator must reopen the scanning window. The service continues handling AutoFileImport." `
                -EntryType 'Error' -EventId 1011
        }
        else { Log "$($p.ProcessName) (PID $($p.Id)) recovered - leaving it alone." 'INFO' }
    }
    else { Log "$($p.ProcessName) (PID $($p.Id), ${wsMB}MB) responding." 'INFO' }
}
if (-not $uiProcs) { Log 'No interactive ScanToPDF UI process running.' 'INFO' }

# ===========================================================================
# 3) OCR ENGINE - clean up orphaned TOCRRService.exe (parent process gone).
#    Active workers (live parent) are left alone; we only alert on a glut.
# ===========================================================================
$tocr = @(Get-CimInstance Win32_Process -Filter "Name='TOCRRService.exe'" -ErrorAction SilentlyContinue)
if ($tocr.Count) {
    $livePids = (Get-Process -ErrorAction SilentlyContinue).Id
    $orphans  = @($tocr | Where-Object { $_.ParentProcessId -notin $livePids })
    Log "TOCRRService.exe instances: $($tocr.Count) (orphaned: $($orphans.Count))." 'INFO'
    foreach ($o in $orphans) {
        Invoke-Action "Kill orphaned TOCRRService.exe (PID $($o.ProcessId), parent $($o.ParentProcessId) gone)" { Stop-Process -Id $o.ProcessId -Force }
    }
    if ($orphans.Count) {
        Send-Alert -Title 'ScanToPDF - orphaned OCR engines cleaned' -Subtitle "$env:COMPUTERNAME" -Text "Killed $($orphans.Count) orphaned TOCRRService.exe process(es) left behind after a crash/hang."
    }
}
else { Log 'No TOCRRService.exe processes running.' 'INFO' }

# Early-warning: OCR engine crashing repeatedly (the true root cause).
$ocrCrashes = Get-RecentOcrCrashes -Minutes $OcrCrashWindowMinutes
if ($ocrCrashes.Count -ge $OcrCrashAlertCount) {
    Log "$($ocrCrashes.Count) Transym OCR crashes in the last $OcrCrashWindowMinutes min." 'WARN'
    Send-Alert -Title 'ScanToPDF - OCR engine crashing' -Subtitle "$env:COMPUTERNAME" `
        -Text "TOCRRService.exe has access-violated $($ocrCrashes.Count) time(s) in $OcrCrashWindowMinutes min. This is the recurring root cause of the lockups (aged Transym OCR engine). Consider an engine update via the vendor." `
        -EntryType 'Warning' -EventId 1012
}

# ===========================================================================
# 4) POISON-FILE GUARD - quarantine an oversized PDF that is clearly stuck.
# ===========================================================================
$recentInstability = $serviceWasDown -or $uiHangHandled -or ($ocrCrashes.Count -ge $OcrCrashAlertCount)
$bigFiles = @{}
if ($state.bigFiles) { $state.bigFiles.PSObject.Properties | ForEach-Object { $bigFiles[$_.Name] = $_.Value } }
$nowUtc = (Get-Date).ToUniversalTime()

$hotFolderReadable = $false
try { $hotFolderReadable = Test-Path -LiteralPath $HotFolder -ErrorAction SilentlyContinue } catch { $hotFolderReadable = $false }
if ($hotFolderReadable) {
    $present = @{}
    $candidates = @(Get-ChildItem -LiteralPath $HotFolder -Filter *.pdf -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge ($QuarantineSizeMB * 1MB) })
    foreach ($f in $candidates) {
        $sizeMB = [math]::Round($f.Length / 1MB, 1)
        $key = '{0}|{1}' -f $f.Name, $f.Length
        $present[$key] = $true
        if ($bigFiles.ContainsKey($key)) {
            $bigFiles[$key].seenCount = [int]$bigFiles[$key].seenCount + 1
        } else {
            $bigFiles[$key] = [pscustomobject]@{ name = $f.Name; sizeMB = $sizeMB; firstSeenUtc = $nowUtc.ToString('o'); seenCount = 1 }
        }
        $info     = $bigFiles[$key]
        $ageMin   = [math]::Round(($nowUtc - ([datetime]$info.firstSeenUtc).ToUniversalTime()).TotalMinutes, 1)
        $stuckPersist = ([int]$info.seenCount -ge $QuarantinePersistCycles) -and $recentInstability
        $stuckOld     = $ageMin -ge $QuarantineHardAgeMinutes
        Log "Oversized hot-folder file '$($f.Name)' ${sizeMB}MB - seen $($info.seenCount)x, age ${ageMin}min, instability=$recentInstability." 'WARN'
        if ($stuckPersist -or $stuckOld) {
            $reason = if ($stuckOld) { "present ${ageMin}min" } else { "seen $($info.seenCount)x during instability" }
            Invoke-Action "Quarantine poison file '$($f.Name)' (${sizeMB}MB; $reason) -> $QuarantineFolder" {
                if (-not (Test-Path -LiteralPath $QuarantineFolder)) { New-Item -ItemType Directory -Path $QuarantineFolder -Force | Out-Null }
                $dest = Join-Path $QuarantineFolder $f.Name
                if (Test-Path -LiteralPath $dest) { $dest = Join-Path $QuarantineFolder ("{0}_{1}{2}" -f $f.BaseName, $timestamp, $f.Extension) }
                Move-Item -LiteralPath $f.FullName -Destination $dest -Force
            }
            $bigFiles.Remove($key)
            $present.Remove($key)
            Send-Alert -Title 'ScanToPDF - poison file quarantined' -Subtitle "$env:COMPUTERNAME" `
                -Text "Moved oversized PDF '$($f.Name)' (${sizeMB}MB) out of the AutoFileImport hot folder into the quarantine folder ($reason). It was driving repeat lockups. Split it into smaller batches and re-drop it." `
                -EntryType 'Error' -EventId 1013
        }
    }
    # forget files that are no longer present (processed and deleted normally)
    foreach ($k in @($bigFiles.Keys)) { if (-not $present.ContainsKey($k)) { $bigFiles.Remove($k) } }
}
else {
    Log "Hot folder not accessible from this context: $HotFolder" 'INFO'
}
$state.bigFiles = [pscustomobject]$bigFiles

# ===========================================================================
# wrap up
# ===========================================================================
Save-State $state
if ($actionsTaken.Count) {
    Log "Summary: $($actionsTaken.Count) action(s) $(if($DryRun){'would be '})taken." 'INFO'
} else {
    Log 'Summary: healthy - no action needed.' 'INFO'
}

# durable runtime log (real runs only) + repo log (on -SaveLog)
if (-not $DryRun) {
    try {
        if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
        $runtimeLog = Join-Path $StateDir 'watchdog.log'
        Add-Content -Path $runtimeLog -Value $report -Encoding UTF8
        # cap runtime log at ~1 MB
        if ((Test-Path $runtimeLog) -and (Get-Item $runtimeLog).Length -gt 1MB) {
            $keep = Get-Content $runtimeLog -Tail 2000
            Set-Content -Path $runtimeLog -Value $keep -Encoding UTF8
        }
    } catch { Write-Host "Could not write runtime log: $($_.Exception.Message)" -ForegroundColor Yellow }
}

if ($SaveLog) {
    try {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
        $logDir   = Join-Path $repoRoot 'logs\windows\monitoring'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $logPath  = Join-Path $logDir "$timestamp-scantopdf-watchdog.txt"
        $report | Set-Content -Path $logPath -Encoding UTF8
        Write-Host "`nLog saved: $logPath" -ForegroundColor Green
    } catch { Write-Host "Could not save repo log: $($_.Exception.Message)" -ForegroundColor Yellow }
}
