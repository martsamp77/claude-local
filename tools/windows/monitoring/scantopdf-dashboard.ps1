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
# the watched source + errors folders, config XMLs, and live process info.
#
# This file is the PLUMBING (params, listener loop, snapshot writing). The data collection + HTML
# rendering live in scantopdf-dashboard.lib.ps1, which the running -Serve server HOT-RELOADS the moment
# it changes on disk - so editing the look/content shows up on the next page refresh with no restart.
# See docs/windows/scantopdf-dashboard-guide.md and docs/windows/scantopdf-lockup-runbook.md.

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
    # The hot-reloadable collection+rendering library (defaults next to this script).
    [string]$LibPath,

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

# --- load the hot-reloadable collection + rendering library (dot-sourced into script scope) ---
if (-not $LibPath) { $LibPath = Join-Path $PSScriptRoot 'scantopdf-dashboard.lib.ps1' }
if (-not (Test-Path $LibPath)) { Write-Host "ERROR: library not found: $LibPath" -ForegroundColor Red; exit 1 }
. $LibPath
$libMtime = (Get-Item $LibPath).LastWriteTimeUtc

# Snapshot writing is plumbing (it touches $StateDir/$SharePath + Log); it calls the lib's renderer/serializer.
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

# ===========================================================================
# WEB SERVER  (loop runs at script scope so the lib hot-reload re-sources into script scope)
# ===========================================================================
while ($true) {
    $listener = $null
    try {
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://+:$Port/")
        $listener.Start()
        Log "ScanToPDF dashboard listening on http://+:$Port/  (hot-reload on; PII-safe=$(-not $ShowFilenames))" 'INFO'

        $cached = $null; $cachedAt = [datetime]::MinValue; $lastSnap = [datetime]::MinValue; $ctxTask = $null
        while ($listener.IsListening) {
            # Hot-reload: re-source the lib if it changed on disk, so edits to collection/rendering show up
            # on the next refresh with no restart. Re-dot-sourcing at script scope updates the functions.
            try {
                $m = (Get-Item $LibPath).LastWriteTimeUtc
                if ($m -ne $libMtime) { . $LibPath; $libMtime = $m; $cached = $null; Log "Hot-reloaded $(Split-Path $LibPath -Leaf)" 'INFO' }
            } catch { Log "Lib reload failed (keeping previous): $($_.Exception.Message)" 'WARN' }

            # Keep exactly ONE outstanding GetContextAsync. Requesting a new context each loop and
            # abandoning it on timeout leaks pending receives - HTTP.sys then completes an orphaned task
            # we never read, and the request hangs. Only ask for a new one once the prior is consumed.
            if (-not $ctxTask) { $ctxTask = $listener.GetContextAsync() }
            $haveCtx = $ctxTask.Wait(2000)   # short wait so cache + snapshot + reload checks run even with no traffic
            if (((Get-Date) - $cachedAt).TotalSeconds -ge $CacheSeconds -or -not $cached) {
                try { $cached = Get-ScanToPdfStatus; $cachedAt = Get-Date } catch { Log "Collect failed: $($_.Exception.Message)" 'WARN' }
            }
            if ($cached -and ((Get-Date) - $lastSnap).TotalSeconds -ge $SnapshotIntervalSeconds) { try { Write-Snapshot $cached } catch { }; $lastSnap = Get-Date }
            if (-not $haveCtx) { continue }
            $ctx = $ctxTask.Result; $ctxTask = $null
            try {
                if (-not $cached) { try { $cached = Get-ScanToPdfStatus; $cachedAt = Get-Date } catch { } }
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
    } catch {
        Log "Server loop crashed: $($_.Exception.Message). Restarting in 10s." 'ERROR'; Start-Sleep 10
    } finally {
        try { if ($listener) { $listener.Stop(); $listener.Close() } } catch { }   # free the port before re-binding
    }
}
