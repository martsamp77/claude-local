<#
.NAME        scantopdf-dashboard
.SYNOPSIS    Read-only status dashboard for ScanToPDF: a tiny built-in web server (and a static HTML/JSON snapshot) showing service health, the watchdog, OCR, scanning activity and queue - for admins, troubleshooters, and scan operators.
.PLATFORM    windows
.CATEGORY    monitoring
.USAGE       .\tools\windows\monitoring\scantopdf-dashboard.ps1 [-Serve|-Once] [-Port 8088] [-SharePath <\\unc\path>] [-ShowFilenames] [-SaveLog]
.WHEN        "I want a page that shows whether ScanToPDF is working", "give the scan operators / on-call a live status board". Run -Once to test the snapshot; the install-scantopdf-dashboard.ps1 installer runs it as a SYSTEM -Serve task.
#>
# Read-only. Never changes ScanToPDF/service/task state. Companion of scantopdf-watchdog.ps1.
# Data sources (all SYSTEM-readable): the ScanToPDF dispatch log, the service + the watchdog's
# scheduled task / state.json / watchdog.log, the ScanToPDF Alerting + Application event logs,
# the watched source + errors folders, config XMLs, and live process info. See
# docs/windows/scantopdf-dashboard-guide.md and docs/windows/scantopdf-lockup-runbook.md.

[CmdletBinding(DefaultParameterSetName = 'Serve')]
param(
    # Run the built-in web server (default). Long-running; the installer schedules this at startup.
    [Parameter(ParameterSetName = 'Serve')][switch]$Serve,
    # Collect once, write the static snapshot (status.html/json), then exit. For testing + as a fallback.
    [Parameter(ParameterSetName = 'Once')][switch]$Once,
    # TCP port the web server listens on (bound to all interfaces; scope access with the firewall rule).
    [int]$Port = 8088,
    # Durable output dir for the snapshot + server log (outside the repo).
    [string]$StateDir = "$env:ProgramData\ScanToPDF-Dashboard",
    # Optional network share to also publish the static snapshot to (the "share copy").
    [string]$SharePath,
    # Reveal raw scanned-document filenames/paths. OFF by default (PII-safe: counts/sizes/pages only).
    [switch]$ShowFilenames,
    # Seconds the live server caches a collected status before recollecting (limits log hammering).
    [int]$CacheSeconds = 15,
    # How often (seconds) the server rewrites the static snapshot, regardless of traffic.
    [int]$SnapshotIntervalSeconds = 60,
    # Page auto-refresh cadence (seconds) baked into the served HTML.
    [int]$RefreshSeconds = 15,
    # Also write this run's text log to logs\windows\monitoring\ in the repo (-Once only).
    [switch]$SaveLog,

    # --- ScanToPDF locations (defaults match this site; override per deployment) ---
    [string]$ServiceName    = 'ScanToPDFService',
    [string]$ProfileName    = 'Scan to PDF',
    [string]$ConfigDir      = 'C:\ProgramData\OIC\ScanToPDF_6',
    [string]$DispatchLog    = 'C:\ProgramData\OIC\ScanToPDF_6\Logs\ScanToPDFDispLog.txt',
    # Watched source folder (local path is more robust for a SYSTEM service than the UNC equivalent).
    [string]$SourceFolder   = 'E:\Assurance Labs\Assurance Scientific\ASL- To be billed\ScanToPDF\Scan to PDF',
    [string]$ErrorsFolder   = 'E:\Assurance Labs\Assurance Scientific\ASL- To be billed\ScanToPDF\Scan to PDF errors',
    [string]$WatchdogStateDir = "$env:ProgramData\ScanToPDF-Watchdog",
    [string]$EventLogName   = 'ScanToPDF Alerting',
    [string[]]$UiProcessNames = @('ScanToPDF', 'ScanToPDFB10', 'ScanToPDFx64'),
    [string[]]$OcrProcessNames = @('TOCRRService')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
$serverLog = Join-Path $StateDir 'server.log'

function Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    $line = '{0} - {1,-5} - {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line -ForegroundColor $(switch ($Level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } default { 'Gray' } })
    try {
        Add-Content -Path $serverLog -Value $line -Encoding UTF8
        if ((Get-Item $serverLog).Length -gt 1MB) { Set-Content -Path $serverLog -Value (Get-Content $serverLog -Tail 2000) -Encoding UTF8 }
    } catch { }
}
function HtmlEnc([string]$s) { [System.Net.WebUtility]::HtmlEncode("$s") }

# Deep-convert to primitives (DateTime -> ISO string) before ConvertTo-Json. Windows PowerShell 5.1's
# ConvertTo-Json throws "capacity was less than the current size" on graphs containing DateTime objects;
# this sidesteps that and serializes identically under 5.1 and pwsh 7.
function ConvertTo-Plain($o) {
    if ($null -eq $o) { return $null }
    if ($o -is [datetime]) { return $o.ToString('o') }
    if ($o -is [string] -or $o -is [bool] -or $o -is [ValueType]) { return $o }
    if ($o -is [System.Collections.IDictionary]) { $h = [ordered]@{}; foreach ($k in $o.Keys) { $h["$k"] = ConvertTo-Plain $o[$k] }; return $h }
    if ($o -is [System.Collections.IEnumerable]) { return @(foreach ($i in $o) { ConvertTo-Plain $i }) }
    $h = [ordered]@{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-Plain $p.Value }; return $h
}

# ===========================================================================
# DATA COLLECTION  (all read-only)
# ===========================================================================
function Get-DiskInfo([string]$DriveLetter) {
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$DriveLetter`:'" -ErrorAction SilentlyContinue
    if (-not $d) { return $null }
    [pscustomobject]@{
        drive  = "$DriveLetter`:"
        freeGB = [math]::Round($d.FreeSpace / 1GB, 1)
        totalGB = [math]::Round($d.Size / 1GB, 1)
        pctFree = if ($d.Size) { [math]::Round($d.FreeSpace / $d.Size * 100, 0) } else { 0 }
    }
}

function Get-ServiceInfo {
    $svc = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if (-not $svc) { return [pscustomobject]@{ found = $false; status = 'NOT FOUND'; running = $false } }
    $ramMB = 0
    if ($svc.ProcessId) { $p = Get-Process -Id $svc.ProcessId -ErrorAction SilentlyContinue; if ($p) { $ramMB = [math]::Round($p.WorkingSet64 / 1MB, 0) } }
    [pscustomobject]@{
        found = $true; name = $svc.Name; displayName = $svc.DisplayName
        status = "$($svc.State)"; running = ($svc.State -eq 'Running')
        startMode = "$($svc.StartMode)"; pid = $svc.ProcessId; ramMB = $ramMB
    }
}

# Expensive event-log stats (OCR crashes/hangs + watchdog restarts in 24h) - cached ~2 min so the
# live server doesn't re-scan the Application log on every page hit.
$script:EvtCache = $null; $script:EvtCacheAt = [datetime]::MinValue
function Get-EventStats {
    if ($script:EvtCache -and ((Get-Date) - $script:EvtCacheAt).TotalSeconds -lt 120) { return $script:EvtCache }
    $crashes = @(); $hangs = @(); $restarts24h = 0
    try { $crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue | Where-Object { $_.Message -like '*TOCRR*' }) } catch { }
    try { $hangs = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Hang'; Id = 1002; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue | Where-Object { $_.Message -like '*ScanToPDF*' }) } catch { }
    try { $restarts24h = @(Get-WinEvent -FilterHashtable @{ LogName = $EventLogName; Id = 1001; StartTime = (Get-Date).AddHours(-24) } -ErrorAction SilentlyContinue).Count } catch { }
    $now = Get-Date
    $script:EvtCache = [pscustomobject]@{
        crashes24h = @($crashes | Where-Object { $_.TimeCreated -ge $now.AddHours(-24) }).Count
        crashes7d  = @($crashes | Where-Object { $_.TimeCreated -ge $now.AddDays(-7) }).Count
        crashes30d = @($crashes).Count
        lastCrash  = ($crashes | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
        hangs30d   = @($hangs).Count
        lastHang   = ($hangs | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
        restarts24h = $restarts24h
    }
    $script:EvtCacheAt = $now
    $script:EvtCache
}

function Get-WatchdogInfo {
    $info = [pscustomobject]@{
        taskState = 'unknown'; lastRun = $null; lastResult = $null; nextRun = $null
        restarts30m = 0; restarts24h = 0; recentActions = @(); uiKillRecent = $false; lastRunLog = $null
    }
    try {
        $t = Get-ScheduledTask -TaskName 'ScanToPDF Watchdog' -TaskPath '\ScanToPDF\' -ErrorAction SilentlyContinue
        if ($t) {
            $ti = $t | Get-ScheduledTaskInfo
            $info.taskState = "$($t.State)"; $info.lastRun = $ti.LastRunTime
            $info.lastResult = ('0x{0:X}' -f $ti.LastTaskResult); $info.nextRun = $ti.NextRunTime
        } else { $info.taskState = 'NOT REGISTERED' }
    } catch { }
    # rolling restart history + UI kills from the watchdog's state.json
    try {
        $sf = Join-Path $WatchdogStateDir 'state.json'
        if (Test-Path $sf) {
            $st = Get-Content $sf -Raw | ConvertFrom-Json
            $cut = (Get-Date).ToUniversalTime().AddMinutes(-30)
            $info.restarts30m = @(@($st.restarts) | Where-Object { $_ } | Where-Object { try { ([datetime]$_).ToUniversalTime() -ge $cut } catch { $false } }).Count
            $kcut = (Get-Date).ToUniversalTime().AddHours(-12)
            $info.uiKillRecent = [bool](@($st.uiKills) | Where-Object { $_ } | Where-Object { try { ([datetime]$_).ToUniversalTime() -ge $kcut } catch { $false } }).Count
        }
    } catch { }
    # restarts in 24h (from the cached event stats) + recent activity from watchdog.log
    try { $info.restarts24h = (Get-EventStats).restarts24h } catch { }
    try {
        $wl = Join-Path $WatchdogStateDir 'watchdog.log'
        if (Test-Path $wl) {
            $tail = Get-Content $wl -Tail 60
            $info.recentActions = @($tail | Where-Object { $_ -match ' - (ACTION|WARN |ERROR) - ' } | Select-Object -Last 6)
            $info.lastRunLog = ($tail | Select-Object -Last 1)
        }
    } catch { }
    $info
}

function Get-OcrInfo {
    $procs = @()
    foreach ($n in $OcrProcessNames) { $procs += Get-Process -Name $n -ErrorAction SilentlyContinue }
    $e = Get-EventStats
    [pscustomobject]@{
        instances = @($procs).Count
        ramMB     = [math]::Round((@($procs | Measure-Object WorkingSet64 -Sum).Sum) / 1MB, 0)
        crashes24h = $e.crashes24h; crashes7d = $e.crashes7d; crashes30d = $e.crashes30d; lastCrash = $e.lastCrash
        hangs30d = $e.hangs30d; lastHang = $e.lastHang
        activeProfileOcrEnabled = (Get-OcrEnabled)
    }
}

function Get-OcrEnabled {
    # OCR active flag for the in-use profile (the lockups are OCR-driven, so this matters).
    try {
        $p = Join-Path $ConfigDir ("Plugins\OCRRecognition\{0}.xml" -f $ProfileName)
        if (Test-Path $p) {
            $node = ([xml](Get-Content $p -Raw)).DocumentElement
            $a = $node.GetAttribute('active')
            if ($a) { return ($a -eq 'True') }
        }
    } catch { }
    return $null  # unknown
}

function Get-Config {
    $cap = '?'; $watched = $SourceFolder; $del = '?'; $timer = '?'
    try { $cap = ([xml](Get-Content (Join-Path $ConfigDir 'ServiceOptionsConfig.xml') -Raw)).SelectSingleNode('//ScanOptions').maxBatchCount } catch { }
    try {
        $afi = [xml](Get-Content (Join-Path $ConfigDir ("Plugins\AutoFileImport\{0}.xml" -f $ProfileName)) -Raw)
        $watched = $afi.SelectSingleNode('//Source/Folder').'#text'
        $fileNode = $afi.SelectSingleNode('//File')
        $del = $fileNode.DeleteFilesFromSourceFolder; $timer = $fileNode.TimerInterval
    } catch { }
    [pscustomobject]@{ batchCap = "$cap"; watchedFolder = "$watched"; deleteAfter = "$del"; timerIntervalSec = "$timer" }
}

function Get-QueueInfo {
    $count = 0; $oldestMin = $null; $readable = $false
    try {
        if (Test-Path -LiteralPath $SourceFolder) {
            $readable = $true
            $pdfs = @(Get-ChildItem -LiteralPath $SourceFolder -Filter *.pdf -File -ErrorAction SilentlyContinue)
            $count = $pdfs.Count
            if ($count) { $oldestMin = [math]::Round(((Get-Date) - ($pdfs | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime).TotalMinutes, 0) }
        }
    } catch { }
    [pscustomobject]@{ readable = $readable; count = $count; oldestMin = $oldestMin }
}

function Get-DispatchActivity {
    $act = [pscustomobject]@{
        readable = $false; lastActivity = $null
        importsToday = 0; savedToday = 0; errorsToday = 0
        lastImport = $null; recent = @(); errorsFolderCount = 0; errorsFolderMB = 0
        lastServiceEvent = $null
    }
    $today = (Get-Date).Date
    $tsFmt = 'dd MMM yyyy HH:mm:ss'; $inv = [Globalization.CultureInfo]::InvariantCulture
    try {
        if (Test-Path $DispatchLog) {
            $act.readable = $true
            $lines = Get-Content $DispatchLog -Tail 600
            $recent = [System.Collections.Generic.List[object]]::new()
            $pendingImport = $null
            foreach ($ln in $lines) {
                if ($ln -notmatch '^(\d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2}) - (.*)$') { continue }
                $ts = $null; try { $ts = [datetime]::ParseExact($Matches[1], $tsFmt, $inv) } catch { continue }
                $msg = $Matches[2]
                $isToday = ($ts.Date -eq $today)
                if ($msg -match "^Importing '(.+)' \(([\d.]+)MB - '(.+)' - \[(.+)\]\)$") {
                    if ($isToday) { $act.importsToday++ }
                    $act.lastImport = [pscustomobject]@{ time = $ts; file = $Matches[1]; sizeMB = [double]$Matches[2]; profile = $Matches[4] }
                    $pendingImport = $act.lastImport
                    $act.lastActivity = $ts
                    $recent.Add([pscustomobject]@{ time = $ts; kind = 'import'; text = ("imported batch - {0} MB" -f $Matches[2]); file = $Matches[1] })
                }
                elseif ($msg -match '^(\d+) pages captured$') {
                    if ($pendingImport) { $pendingImport | Add-Member -NotePropertyName pages -NotePropertyValue ([int]$Matches[1]) -Force }
                    if ($recent.Count) { $recent[$recent.Count - 1].text += (" - {0} pages" -f $Matches[1]) }
                }
                elseif ($msg -match "^'(.+)' saved \((\d+) pages?\)$") {
                    $savedPath = $Matches[1]; $pages = [int]$Matches[2]
                    $isErr = ($savedPath -match '\\[^\\]*errors\\')
                    if ($isToday) { if ($isErr) { $act.errorsToday++ } else { $act.savedToday++ } }
                    $act.lastActivity = $ts
                    $dest = if ($isErr) { 'errors' } else { 'reconciliation' }
                    $recent.Add([pscustomobject]@{ time = $ts; kind = $(if($isErr){'error'}else{'saved'}); text = ("saved {0}-page doc -> {1}" -f $pages, $dest); file = (Split-Path $savedPath -Leaf) })
                }
                elseif ($msg -match '^(Stop request|ScanToPDF Service stopped|ScanToPDF Service started)$') {
                    $act.lastServiceEvent = [pscustomobject]@{ time = $ts; text = $msg }
                    $recent.Add([pscustomobject]@{ time = $ts; kind = 'service'; text = $msg; file = $null })
                }
            }
            $act.recent = @($recent | Select-Object -Last 12)
        }
    } catch { }
    # errors folder backlog (failed pages worth a human's attention)
    try {
        if (Test-Path -LiteralPath $ErrorsFolder) {
            $ef = @(Get-ChildItem -LiteralPath $ErrorsFolder -Filter *.pdf -File -ErrorAction SilentlyContinue)
            $act.errorsFolderCount = $ef.Count
            $act.errorsFolderMB = [math]::Round((@($ef | Measure-Object Length -Sum).Sum) / 1MB, 1)
        }
    } catch { }
    $act
}

function Get-ScanToPdfStatus {
    $svc = Get-ServiceInfo
    $wd  = Get-WatchdogInfo
    $ocr = Get-OcrInfo
    $cfg = Get-Config
    $q   = Get-QueueInfo
    $act = Get-DispatchActivity
    $cap = [pscustomobject]@{ diskC = (Get-DiskInfo 'C'); diskE = (Get-DiskInfo 'E'); batchCap = $cfg.batchCap }

    # ---- overall health + plain-English line (end-user friendly) ----
    $level = 'green'; $msg = 'Scanning is running normally.'; $actionNeeded = $null
    $warn = @(); $bad = @()
    if (-not $svc.running) { $bad += 'service-down' }
    if ($wd.restarts30m -ge 3) { $bad += 'flapping' }
    if ($wd.restarts30m -ge 1 -and $svc.running) { $warn += 'recently-restarted' }
    if ($wd.lastResult -and $wd.lastResult -ne '0x0' -and $wd.taskState -ne 'unknown') { $warn += 'watchdog-result' }
    if ($wd.taskState -in 'NOT REGISTERED','unknown') { $warn += 'watchdog-task' }
    if ($ocr.crashes24h -gt 0) { $warn += 'ocr-crashes' }
    if ($q.count -gt 0 -and $q.oldestMin -ne $null -and $q.oldestMin -ge 10) { if ($svc.running) { $warn += 'queue-stuck' } else { $bad += 'queue-stuck' } }
    if ($cap.diskE -and $cap.diskE.pctFree -le 5) { $bad += 'disk-E' } elseif ($cap.diskE -and $cap.diskE.pctFree -le 10) { $warn += 'disk-E' }
    if ($cap.diskC -and $cap.diskC.pctFree -le 5) { $bad += 'disk-C' } elseif ($cap.diskC -and $cap.diskC.pctFree -le 10) { $warn += 'disk-C' }
    if ($ocr.activeProfileOcrEnabled -eq $false) { $warn += 'ocr-disabled' }
    if ($wd.uiKillRecent) { $actionNeeded = 'A hung scanning window was closed automatically - an operator should reopen ScanToPDF on the server.' }

    if ($bad.Count) {
        $level = 'red'
        if ($bad -contains 'service-down') { $msg = 'Scanning is DOWN - the service is not running (automatic recovery should kick in within ~3 minutes).' }
        elseif ($bad -contains 'flapping') { $msg = 'Scanning is unstable - the service keeps restarting. Needs attention.' }
        elseif ($bad -contains 'queue-stuck') { $msg = 'A document appears stuck and the service is down.' }
        else { $msg = 'A capacity problem needs attention (low disk).' }
    } elseif ($warn.Count) {
        $level = 'amber'
        if ($warn -contains 'queue-stuck') { $msg = ("A document may be stuck - {0} waiting, oldest ~{1} min." -f $q.count, $q.oldestMin) }
        elseif ($warn -contains 'recently-restarted') { $msg = 'Scanning recovered after a hiccup - it is running now.' }
        elseif ($warn -contains 'ocr-crashes') { $msg = 'Scanning is running, but the OCR engine has crashed recently - watch for lockups.' }
        elseif ($warn -contains 'ocr-disabled') { $msg = 'Scanning is running (note: OCR is turned off on the active profile).' }
        else { $msg = 'Scanning is running, with a minor warning - see details.' }
    }

    [pscustomobject]@{
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        generatedLocal = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        host = $env:COMPUTERNAME
        overall = [pscustomobject]@{ level = $level; message = $msg; actionNeeded = $actionNeeded; warnings = $warn; problems = $bad }
        service = $svc; watchdog = $wd; ocr = $ocr; activity = $act; queue = $q; capacity = $cap; config = $cfg
    }
}

# ===========================================================================
# RENDERING
# ===========================================================================
function Ago([datetime]$t) {
    if (-not $t) { return 'never' }
    $s = ((Get-Date) - $t).TotalSeconds
    if ($s -lt 90) { return ('{0}s ago' -f [int]$s) }
    if ($s -lt 5400) { return ('{0} min ago' -f [int]($s / 60)) }
    if ($s -lt 172800) { return ('{0} hr ago' -f [int]($s / 3600)) }
    return ('{0} days ago' -f [int]($s / 86400))
}

function ConvertTo-StatusHtml {
    param([object]$S, [int]$Refresh = 15)
    $color = switch ($S.overall.level) { 'red' { '#d13438' } 'amber' { '#c77700' } default { '#107c10' } }
    $word  = switch ($S.overall.level) { 'red' { 'PROBLEM' } 'amber' { 'WARNING' } default { 'HEALTHY' } }

    # --- end-user section ---
    $queueTxt = if (-not $S.queue.readable) { 'queue unknown' } elseif ($S.queue.count -eq 0) { 'none waiting' } else { "$($S.queue.count) waiting (oldest ~$($S.queue.oldestMin) min)" }
    $lastProc = if ($S.activity.lastActivity) { Ago $S.activity.lastActivity } else { 'no recent activity' }
    $actionHtml = if ($S.overall.actionNeeded) { "<div class='action'>&#9888; $(HtmlEnc $S.overall.actionNeeded)</div>" } else { '' }

    # --- activity feed rows ---
    $rows = foreach ($r in ($S.activity.recent | Sort-Object time -Descending)) {
        $detail = HtmlEnc $r.text
        if ($ShowFilenames -and $r.file) { $detail += " <span class='dim'>($(HtmlEnc $r.file))</span>" }
        $cls = switch ($r.kind) { 'error' { 'k-err' } 'service' { 'k-svc' } 'saved' { 'k-ok' } default { 'k-imp' } }
        "<tr><td class='t'>$($r.time.ToString('HH:mm:ss'))</td><td class='$cls'>$($r.kind)</td><td>$detail</td></tr>"
    }
    if (-not $rows) { $rows = "<tr><td colspan='3' class='dim'>no recent entries in the dispatch log</td></tr>" }

    # --- watchdog actions ---
    $wdActions = foreach ($a in $S.watchdog.recentActions) { "<li>$(HtmlEnc $a)</li>" }
    if (-not $wdActions) { $wdActions = "<li class='dim'>no recent watchdog actions (healthy)</li>" }

    $ocrEnabledTxt = switch ($S.ocr.activeProfileOcrEnabled) { $true { 'enabled' } $false { "<span class='warn'>DISABLED on active profile</span>" } default { 'unknown' } }
    $dC = $S.capacity.diskC; $dE = $S.capacity.diskE

    @"
<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<meta http-equiv='refresh' content='$Refresh'>
<title>ScanToPDF status - $(HtmlEnc $S.host)</title>
<style>
:root{color-scheme:light dark}
body{font:14px/1.45 'Segoe UI',system-ui,sans-serif;margin:0;background:#f3f3f3;color:#1b1b1b}
.wrap{max-width:1000px;margin:0 auto;padding:16px}
.banner{background:$color;color:#fff;border-radius:10px;padding:18px 20px;margin-bottom:16px}
.banner .w{font-size:13px;letter-spacing:.12em;opacity:.9}
.banner .m{font-size:22px;font-weight:600;margin-top:2px}
.action{background:#fff3cd;color:#664d03;border:1px solid #ffe69c;border-radius:8px;padding:10px 12px;margin-bottom:16px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}
.card{background:#fff;border:1px solid #e1e1e1;border-radius:10px;padding:14px}
.card h3{margin:0 0 8px;font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#666}
.kv{display:flex;justify-content:space-between;gap:10px;padding:3px 0;border-bottom:1px solid #f0f0f0}
.kv:last-child{border-bottom:0}.kv b{font-weight:600}
.big{font-size:28px;font-weight:600}
h2{font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#555;margin:22px 0 8px;border-bottom:2px solid #ddd;padding-bottom:4px}
table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e1e1e1;border-radius:10px;overflow:hidden}
td{padding:6px 10px;border-bottom:1px solid #f0f0f0;vertical-align:top}
td.t{white-space:nowrap;color:#666;font-variant-numeric:tabular-nums}
.k-ok{color:#107c10;font-weight:600}.k-err{color:#d13438;font-weight:600}.k-svc{color:#8764b8;font-weight:600}.k-imp{color:#0078d4;font-weight:600}
.dim{color:#999}.warn{color:#c77700;font-weight:600}.bad{color:#d13438;font-weight:600}.good{color:#107c10;font-weight:600}
ul.acts{margin:0;padding-left:18px}ul.acts li{padding:2px 0;font-variant-numeric:tabular-nums}
.foot{color:#888;font-size:12px;margin-top:18px;text-align:center}
@media (prefers-color-scheme:dark){body{background:#1b1b1b;color:#e6e6e6}.card,table{background:#262626;border-color:#383838}.kv{border-color:#333}td{border-color:#333}h2{color:#aaa;border-color:#444}.banner .w{opacity:.95}}
</style></head><body><div class='wrap'>

<div class='banner'><div class='w'>SCANTOPDF &mdash; $word</div><div class='m'>$(HtmlEnc $S.overall.message)</div></div>
$actionHtml

<h2>At a glance (for scan operators)</h2>
<div class='grid'>
  <div class='card'><h3>Scanning service</h3><div class='big $(if($S.service.running){'good'}else{'bad'})'>$(if($S.service.running){'UP'}else{'DOWN'})</div><div class='dim'>$(HtmlEnc $S.service.status)</div></div>
  <div class='card'><h3>Waiting to process</h3><div class='big'>$(if($S.queue.readable){$S.queue.count}else{'?'})</div><div class='dim'>$(HtmlEnc $queueTxt)</div></div>
  <div class='card'><h3>Last document processed</h3><div class='big'>$lastProc</div><div class='dim'>processed today: $($S.activity.savedToday)</div></div>
  <div class='card'><h3>Needs a human?</h3><div class='big $(if($S.activity.errorsFolderCount){'warn'}else{'good'})'>$($S.activity.errorsFolderCount)</div><div class='dim'>page(s) in the errors folder</div></div>
</div>

<h2>Administration</h2>
<div class='grid'>
  <div class='card'><h3>Service</h3>
    <div class='kv'><span>State</span><b class='$(if($S.service.running){'good'}else{'bad'})'>$(HtmlEnc $S.service.status)</b></div>
    <div class='kv'><span>Start mode</span><b>$(HtmlEnc $S.service.startMode)</b></div>
    <div class='kv'><span>PID / RAM</span><b>$($S.service.pid) / $($S.service.ramMB) MB</b></div>
  </div>
  <div class='card'><h3>Watchdog</h3>
    <div class='kv'><span>Task</span><b class='$(if($S.watchdog.taskState -eq 'Ready'){'good'}else{'warn'})'>$(HtmlEnc $S.watchdog.taskState)</b></div>
    <div class='kv'><span>Last run / result</span><b>$(if($S.watchdog.lastRun){$S.watchdog.lastRun.ToString('HH:mm:ss')}else{'?'}) / $(HtmlEnc $S.watchdog.lastResult)</b></div>
    <div class='kv'><span>Next run</span><b>$(if($S.watchdog.nextRun){$S.watchdog.nextRun.ToString('HH:mm:ss')}else{'?'})</b></div>
    <div class='kv'><span>Restarts 30m / 24h</span><b class='$(if($S.watchdog.restarts30m -ge 3){'bad'}elseif($S.watchdog.restarts30m){'warn'}else{''})'>$($S.watchdog.restarts30m) / $($S.watchdog.restarts24h)</b></div>
  </div>
  <div class='card'><h3>OCR engine</h3>
    <div class='kv'><span>Workers / RAM</span><b>$($S.ocr.instances) / $($S.ocr.ramMB) MB</b></div>
    <div class='kv'><span>OCR setting</span><b>$ocrEnabledTxt</b></div>
    <div class='kv'><span>Crashes 24h/7d/30d</span><b class='$(if($S.ocr.crashes24h){'warn'}else{''})'>$($S.ocr.crashes24h) / $($S.ocr.crashes7d) / $($S.ocr.crashes30d)</b></div>
    <div class='kv'><span>UI hangs (30d)</span><b>$($S.ocr.hangs30d)</b></div>
  </div>
  <div class='card'><h3>Capacity</h3>
    <div class='kv'><span>Disk C:</span><b class='$(if($dC -and $dC.pctFree -le 10){'warn'}else{''})'>$(if($dC){"$($dC.freeGB) GB free ($($dC.pctFree)%)"}else{'?'})</b></div>
    <div class='kv'><span>Disk E:</span><b class='$(if($dE -and $dE.pctFree -le 10){'warn'}else{''})'>$(if($dE){"$($dE.freeGB) GB free ($($dE.pctFree)%)"}else{'?'})</b></div>
    <div class='kv'><span>Batch cap</span><b>$(HtmlEnc $S.capacity.batchCap)</b></div>
    <div class='kv'><span>Auto-import every</span><b>$(HtmlEnc $S.config.timerIntervalSec)s</b></div>
  </div>
</div>

<h2>Troubleshooting</h2>
<div class='grid'>
  <div class='card' style='grid-column:1/-1'><h3>Recent watchdog activity</h3><ul class='acts'>$($wdActions -join '')</ul></div>
</div>
<table><tbody>
<tr><td class='t'><b>time</b></td><td><b>type</b></td><td><b>activity (newest first)</b></td></tr>
$($rows -join "`n")
</tbody></table>

<div class='foot'>$(HtmlEnc $S.host) &middot; generated $($S.generatedLocal) &middot; auto-refresh ${Refresh}s &middot; watched: $(HtmlEnc $S.config.watchedFolder)$(if(-not $ShowFilenames){' &middot; filenames hidden (PII-safe)'})</div>
</div></body></html>
"@
}

function Write-Snapshot([object]$S) {
    $html = ConvertTo-StatusHtml -S $S -Refresh 60
    $json = $null
    try { $json = (ConvertTo-Plain $S) | ConvertTo-Json -Depth 8 } catch { Log "JSON serialize failed: $($_.Exception.Message)" 'WARN' }
    $targets = @($StateDir)
    if ($SharePath) { $targets += $SharePath }
    foreach ($dir in $targets) {
        try {
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Set-Content -Path (Join-Path $dir 'status.html') -Value $html -Encoding UTF8
            if ($json) { Set-Content -Path (Join-Path $dir 'status.json') -Value $json -Encoding UTF8 }
        } catch { Log "Snapshot write failed for ${dir}: $($_.Exception.Message)" 'WARN' }
    }
}

# ===========================================================================
# WEB SERVER
# ===========================================================================
function Start-Server {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://+:$Port/")
    try { $listener.Start() } catch { Log "Could not start listener on port $Port (urlacl/firewall? in use?): $($_.Exception.Message)" 'ERROR'; throw }
    Log "ScanToPDF dashboard listening on http://+:$Port/  (PII-safe=$(-not $ShowFilenames))" 'INFO'

    $cached = $null; $cachedAt = [datetime]::MinValue; $lastSnap = [datetime]::MinValue
    $ctxTask = $null
    while ($listener.IsListening) {
        # Keep exactly ONE outstanding GetContextAsync. Requesting a new context each loop and
        # abandoning it on timeout leaks pending receives - HTTP.sys then completes an orphaned
        # task we never read, and the request hangs. Only ask for a new one once the prior is consumed.
        if (-not $ctxTask) { $ctxTask = $listener.GetContextAsync() }
        $haveCtx = $ctxTask.Wait(2000)   # short wait so cache + snapshot maintenance runs even with no traffic
        if (((Get-Date) - $cachedAt).TotalSeconds -ge $CacheSeconds -or -not $cached) { $cached = Get-ScanToPdfStatus; $cachedAt = Get-Date }
        if (((Get-Date) - $lastSnap).TotalSeconds -ge $SnapshotIntervalSeconds) { try { Write-Snapshot $cached } catch { }; $lastSnap = Get-Date }
        if (-not $haveCtx) { continue }
        $ctx = $ctxTask.Result; $ctxTask = $null
        try {
            $path = $ctx.Request.Url.AbsolutePath.TrimEnd('/')
            switch ($path) {
                '/status.json' { $body = ((ConvertTo-Plain $cached) | ConvertTo-Json -Depth 8); $ctype = 'application/json' }
                '/healthz'     { $body = 'ok'; $ctype = 'text/plain' }
                default        { $body = ConvertTo-StatusHtml -S $cached -Refresh $RefreshSeconds; $ctype = 'text/html; charset=utf-8' }
            }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $ctx.Response.ContentType = $ctype
            $ctx.Response.Headers['Cache-Control'] = 'no-store'
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch { Log "Request error: $($_.Exception.Message)" 'WARN' }
        finally { try { $ctx.Response.Close() } catch { } }
    }
}

# ===========================================================================
# ENTRY POINT
# ===========================================================================
if ($Once) {
    $status = Get-ScanToPdfStatus
    Write-Snapshot $status
    Log ("Snapshot written to {0}\status.html (overall={1}){2}" -f $StateDir, $status.overall.level, $(if ($SharePath) { " + $SharePath" } else { '' })) 'INFO'
    if ($SaveLog) {
        try {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
            $logDir = Join-Path $repoRoot 'logs\windows\monitoring'; New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            (ConvertTo-Plain $status) | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $logDir ("{0}-scantopdf-status.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Encoding UTF8
        } catch { }
    }
    return
}

# default: serve. Auto-restart the loop on unexpected listener failure (the SYSTEM task also restarts the process).
while ($true) {
    try { Start-Server }
    catch { Log "Server loop crashed: $($_.Exception.Message). Restarting in 10s." 'ERROR'; Start-Sleep 10 }
}
