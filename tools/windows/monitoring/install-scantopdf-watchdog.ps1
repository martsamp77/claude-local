<#
.NAME        install-scantopdf-watchdog
.SYNOPSIS    Installs the ScanToPDF watchdog: registers a SYSTEM scheduled task, ensures the alerting event-log source, and caps the runaway batch size (maxBatchCount). Run elevated.
.PLATFORM    windows
.CATEGORY    monitoring
.USAGE       .\tools\windows\monitoring\install-scantopdf-watchdog.ps1 [-DryRun] [-IntervalMinutes 3] [-BatchCap 150] [-SkipConfigCap] [-SkipTask] [-Uninstall]
.WHEN        One-time setup (or removal) of the ScanToPDF auto-recovery. Always preview with -DryRun first. Needs an elevated PowerShell.
#>
# Companion installer for scantopdf-watchdog.ps1. See docs/windows/scantopdf-lockup-runbook.md.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Uninstall,
    # How often the watchdog runs.
    [int]$IntervalMinutes = 3,
    # Cap unlimited batches (maxBatchCount=-1) at this many pages. 0 / -SkipConfigCap leaves config alone.
    [int]$BatchCap = 150,
    [switch]$SkipConfigCap,
    [switch]$SkipTask,
    # Also restore the previous config from the most recent backup during -Uninstall.
    [switch]$RestoreConfig,
    [string]$TaskName = 'ScanToPDF Watchdog',
    [string]$TaskPath = '\ScanToPDF\',
    [string]$ServiceName = 'ScanToPDFService',
    [string]$EventLogName   = 'ScanToPDF Alerting',
    [string]$EventLogSource = 'ScanToPDF Alerting Script',
    [string]$WatchdogScript,
    # Watchdog state dir (must match the watchdog's -StateDir). The Teams webhook lives here, out of the repo.
    [string]$StateDir = "$env:ProgramData\ScanToPDF-Watchdog",
    # Teams Incoming Webhook. If supplied, it is written to $StateDir\webhook.url so the SYSTEM task can alert
    # without the secret ever entering source control. Omit to leave any existing webhook.url untouched.
    [string]$WebhookUrl,
    [string[]]$ConfigFiles = @(
        'C:\ProgramData\OIC\ScanToPDF_6\OptionsConfig.xml',
        'C:\ProgramData\OIC\ScanToPDF_6\ServiceOptionsConfig.xml'
    ),
    [string[]]$UiProcessNames = @('ScanToPDF', 'ScanToPDFB10', 'ScanToPDFx64')
)

$ErrorActionPreference = 'Stop'
$tag = if ($DryRun) { '[DRYRUN] ' } else { '' }
if (-not $WatchdogScript) { $WatchdogScript = Join-Path $PSScriptRoot 'scantopdf-watchdog.ps1' }

function Say  { param([string]$m, [string]$c = 'Gray') Write-Host "$tag$m" -ForegroundColor $c }
function Step { param([string]$m) Write-Host "`n=== $tag$m ===" -ForegroundColor Cyan }
function Do-It {
    param([string]$Description, [scriptblock]$Do)
    if ($DryRun) { Say "would: $Description" 'Green'; return }
    Say "doing: $Description" 'Green'
    & $Do
}
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isAdmin = Test-Admin
if (-not $isAdmin) {
    if ($DryRun) {
        Say 'NOTE: not elevated. -DryRun preview will print, but a real run must be from an elevated PowerShell.' 'Yellow'
    } else {
        Write-Host 'ERROR: This installer must run elevated (Administrator).' -ForegroundColor Red
        Write-Host '       Re-launch PowerShell as Administrator and run it again, e.g.:' -ForegroundColor Red
        Write-Host "       pwsh -File `"$PSCommandPath`"" -ForegroundColor Red
        exit 1
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$fullTaskName = ($TaskPath.TrimEnd('\') + '\' + $TaskName)

# ===========================================================================
# UNINSTALL
# ===========================================================================
if ($Uninstall) {
    Step "Uninstalling watchdog ($fullTaskName)"
    $existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if ($existing) {
        Do-It "Unregister scheduled task $fullTaskName" { Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false }
    } else { Say "Task $fullTaskName not present." }

    if ($RestoreConfig) {
        $backupRoot = Join-Path $repoRoot 'backups\windows\scantopdf'
        $latest = Get-ChildItem $backupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) {
            Say "Restoring config from $($latest.FullName) (stops the service briefly)."
            Do-It "Stop-Service $ServiceName" { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue }
            foreach ($bak in Get-ChildItem $latest.FullName -Filter *.xml) {
                $dest = $ConfigFiles | Where-Object { (Split-Path $_ -Leaf) -eq $bak.Name } | Select-Object -First 1
                if ($dest) { Do-It "Restore $($bak.Name) -> $dest" { Copy-Item $bak.FullName $dest -Force } }
            }
            Do-It "Start-Service $ServiceName" { Start-Service -Name $ServiceName -ErrorAction SilentlyContinue }
        } else { Say 'No backup found to restore.' 'Yellow' }
    } else {
        Say 'Config cap left as-is. Re-run with -RestoreConfig to revert maxBatchCount from the latest backup.' 'Yellow'
    }
    Say "`nUninstall complete." 'Green'
    return
}

# ===========================================================================
# INSTALL
# ===========================================================================
Step 'Pre-flight'
if (-not (Test-Path $WatchdogScript)) { Write-Host "ERROR: watchdog script not found: $WatchdogScript" -ForegroundColor Red; exit 1 }
Say "Watchdog script : $WatchdogScript"
Say "Repo root       : $repoRoot"
Say "Task            : $fullTaskName  (every $IntervalMinutes min, as SYSTEM)"
Say "Batch cap       : $(if ($SkipConfigCap) { 'SKIPPED' } else { $BatchCap })"

# --- 1. event-log source ---------------------------------------------------
Step 'Event-log source'
$srcExists = $false
try { $srcExists = [System.Diagnostics.EventLog]::SourceExists($EventLogSource) } catch { }
if ($srcExists) { Say "Source '$EventLogSource' already present." }
else { Do-It "Create event-log source '$EventLogSource' in log '$EventLogName'" { New-EventLog -LogName $EventLogName -Source $EventLogSource } }

# --- 1b. Teams webhook (kept out of source control) ------------------------
Step 'Teams webhook'
$webhookFile = Join-Path $StateDir 'webhook.url'
if ($WebhookUrl) {
    Do-It "Write Teams webhook -> $webhookFile" {
        if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
        Set-Content -Path $webhookFile -Value $WebhookUrl.Trim() -Encoding UTF8 -NoNewline
    }
} elseif (Test-Path $webhookFile) {
    Say "Existing webhook.url kept ($webhookFile)."
} else {
    Say "No -WebhookUrl given and no $webhookFile present - Teams alerts will be skipped (event-log alerting still fires)." 'Yellow'
}

# --- 2. scheduled task -----------------------------------------------------
if (-not $SkipTask) {
    Step 'Scheduled task'
    $existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if ($existing) { Say "Task already exists - it will be replaced." 'Yellow' }
    Do-It "Register $fullTaskName (SYSTEM, every $IntervalMinutes min)" {
        $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
                    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$WatchdogScript`" -SaveLog"
        # Run every $IntervalMinutes minutes, indefinitely. Built as a daily trigger that
        # borrows a 24h repetition pattern -- this avoids the [TimeSpan]::MaxValue serialization
        # overflow that yields "task XML contains a value ... out of range" on Server 2016/2019.
        $startAt = (Get-Date).Date   # for a Daily trigger only the time-of-day matters
        $daily   = New-ScheduledTaskTrigger -Daily -At $startAt
        $repeat  = New-ScheduledTaskTrigger -Once -At $startAt `
                    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
                    -RepetitionDuration (New-TimeSpan -Hours 24)
        $daily.Repetition = $repeat.Repetition
        $atBoot  = New-ScheduledTaskTrigger -AtStartup
        $princ   = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
        $set     = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable `
                    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $action `
            -Trigger @($daily, $atBoot) -Principal $princ -Settings $set -Force `
            -Description 'Self-healing watchdog for ScanToPDF: restarts stopped service, kills hung UI / orphaned OCR, quarantines oversized poison PDFs.' | Out-Null
    }
} else { Step 'Scheduled task'; Say 'Skipped (-SkipTask).' 'Yellow' }

# --- 3. batch-size cap -----------------------------------------------------
if (-not $SkipConfigCap) {
    Step "Batch-size cap (maxBatchCount = $BatchCap)"
    # show current values
    foreach ($cfg in $ConfigFiles) {
        if (Test-Path $cfg) {
            try { $cur = ([xml](Get-Content $cfg -Raw)).SelectSingleNode('//ScanOptions').maxBatchCount } catch { $cur = '?' }
            Say "  $(Split-Path $cfg -Leaf): maxBatchCount currently '$cur'"
        } else { Say "  MISSING: $cfg" 'Yellow' }
    }

    $backupDir = Join-Path $repoRoot ("backups\windows\scantopdf\{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Do-It "Back up config files -> $backupDir" {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        foreach ($cfg in $ConfigFiles) { if (Test-Path $cfg) { Copy-Item $cfg $backupDir -Force } }
    }

    # The app rewrites these XMLs on exit, so stop it before editing.
    Do-It "Stop-Service $ServiceName (so config edits persist)" { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue; Start-Sleep 2 }
    $running = @()
    foreach ($n in $UiProcessNames) { $running += Get-Process -Name $n -ErrorAction SilentlyContinue }
    if ($running) {
        Say "WARNING: interactive UI is open ($($running.ProcessName -join ', ')). It will be closed so the cap persists." 'Yellow'
        Do-It "Stop UI processes ($($running.ProcessName -join ', '))" { $running | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep 2 }
    }

    foreach ($cfg in $ConfigFiles) {
        if (-not (Test-Path $cfg)) { continue }
        Do-It "Set maxBatchCount=$BatchCap in $(Split-Path $cfg -Leaf)" {
            $xml = [xml](Get-Content $cfg -Raw)
            $node = $xml.SelectSingleNode('//ScanOptions')
            if ($node) { $node.SetAttribute('maxBatchCount', "$BatchCap"); $xml.Save($cfg) }
            else { Say "  no <ScanOptions> node in $cfg - skipped" 'Yellow' }
        }
    }

    Do-It "Start-Service $ServiceName" { Start-Service -Name $ServiceName -ErrorAction SilentlyContinue }

    if (-not $DryRun) {
        Say 'Verifying cap persisted after restart...'
        Start-Sleep 3
        foreach ($cfg in $ConfigFiles) {
            if (Test-Path $cfg) {
                try { $now = ([xml](Get-Content $cfg -Raw)).SelectSingleNode('//ScanOptions').maxBatchCount } catch { $now = '?' }
                $ok = ($now -eq "$BatchCap")
                Say "  $(Split-Path $cfg -Leaf): maxBatchCount now '$now' $(if($ok){'OK'}else{'-- did NOT stick (profile vault may override; see runbook)'})" $(if($ok){'Green'}else{'Yellow'})
            }
        }
    }
} else { Step 'Batch-size cap'; Say 'Skipped (-SkipConfigCap).' 'Yellow' }

# --- 4. summary ------------------------------------------------------------
Step 'Done'
Say "Installed (or previewed) the ScanToPDF watchdog." 'Green'
Say ''
Say 'Set/refresh the Teams webhook (kept out of the repo):'
Say "  re-run with -WebhookUrl `"<url>`", or drop the URL into $($StateDir)\webhook.url"
Say ''
Say 'Test it now (safe, no changes):'
Say "  pwsh -File `"$WatchdogScript`" -DryRun -SaveLog"
Say 'Force a live self-heal test:'
Say "  Stop-Service $ServiceName   # the task should restart it within $IntervalMinutes min + post a Teams alert"
Say 'Inspect the task / runtime log:'
Say "  Get-ScheduledTask -TaskName '$TaskName' -TaskPath '$TaskPath' | Get-ScheduledTaskInfo"
Say "  Get-Content `"$env:ProgramData\ScanToPDF-Watchdog\watchdog.log`" -Tail 40"
Say 'Uninstall:'
Say "  pwsh -File `"$PSCommandPath`" -Uninstall            # remove task (keeps cap)"
Say "  pwsh -File `"$PSCommandPath`" -Uninstall -RestoreConfig   # also revert maxBatchCount"
