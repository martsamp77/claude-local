<#
.NAME        perf-snapshot
.SYNOPSIS    Capture a one-time performance snapshot: CPU, RAM, disk, top processes, pagefile, power plan.
.CATEGORY    diagnostics
.USAGE       .\tools\diagnostics\perf-snapshot.ps1 [-Top <n>] [-SaveLog]
.WHEN        Machine feels slow or unresponsive; before/after a fix to compare baseline; Outlook+Cursor+Claude all open
#>
param(
    [int]$Top = 15,
    [switch]$SaveLog
)

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$logDir    = Join-Path $repoRoot 'logs\diagnostics'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$lines     = [System.Collections.Generic.List[string]]::new()

function Section([string]$title) {
    $lines.Add('')
    $lines.Add("=== $title ===")
    Write-Host "`n=== $title ===" -ForegroundColor Cyan
}

function Out([string]$text) {
    $lines.Add($text)
    Write-Host $text
}

# ── Hardware summary ──────────────────────────────────────────────────────────
Section 'SYSTEM'
$cpu = Get-CimInstance Win32_Processor
$cs  = Get-CimInstance Win32_ComputerSystem
$os  = Get-CimInstance Win32_OperatingSystem
Out "CPU  : $($cpu.Name.Trim())"
Out "Cores: $($cpu.NumberOfCores) physical / $($cpu.NumberOfLogicalProcessors) logical"
$totalGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$freeGb  = [math]::Round($os.FreePhysicalMemory  / 1MB, 1)
$usedGb  = [math]::Round($totalGb - $freeGb, 1)
Out "RAM  : ${usedGb} GB used / ${totalGb} GB total  (${freeGb} GB free)"

# ── Memory compression ────────────────────────────────────────────────────────
Section 'MEMORY COMPRESSION'
$mc = Get-Process 'Memory Compression' -ErrorAction SilentlyContinue
if ($mc) {
    $mcMb = [math]::Round($mc.WorkingSet64 / 1MB, 0)
    Out "Memory Compression process: ${mcMb} MB working set"
    if ($mcMb -gt 1000) { Out '  ^^^ High — system has been under memory pressure' }
} else {
    Out 'Memory Compression process not found (normal on fresh boot)'
}
$commitGb      = [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1MB, 1)
$totalVirtualGb = [math]::Round($os.TotalVirtualMemorySize / 1MB, 1)
Out "Committed: ${commitGb} GB / ${totalVirtualGb} GB virtual"

# ── Pagefile ──────────────────────────────────────────────────────────────────
Section 'PAGEFILE'
Get-CimInstance Win32_PageFileUsage | ForEach-Object {
    Out "$($_.Name)  allocated=$($_.AllocatedBaseSize) MB  current=$($_.CurrentUsage) MB  peak=$($_.PeakUsage) MB"
}

# ── Power plan ────────────────────────────────────────────────────────────────
Section 'POWER PLAN'
$scheme = powercfg /getactivescheme
Out $scheme

# ── Disks ─────────────────────────────────────────────────────────────────────
Section 'DISKS'
Get-PhysicalDisk | ForEach-Object {
    Out "$($_.FriendlyName)  $($_.MediaType)  $([math]::Round($_.Size/1GB,0)) GB"
}

# ── Top processes by CPU ──────────────────────────────────────────────────────
Section "TOP $Top PROCESSES BY CPU (accumulated seconds)"
$cpuProcs = Get-Process |
    Where-Object { $_.CPU -gt 0 } |
    Sort-Object CPU -Descending |
    Select-Object -First $Top Name, Id,
        @{N='CPU(s)';  E={[math]::Round($_.CPU, 1)}},
        @{N='RAM(MB)'; E={[math]::Round($_.WorkingSet64 / 1MB, 0)}}
$cpuProcs | ForEach-Object { Out ('{0,-30} pid={1,-7} cpu={2,-10} ram={3} MB' -f $_.Name, $_.Id, $_.'CPU(s)', $_.'RAM(MB)') }

# ── Top processes by RAM ──────────────────────────────────────────────────────
Section "TOP $Top PROCESSES BY RAM"
$ramProcs = Get-Process |
    Sort-Object WorkingSet64 -Descending |
    Select-Object -First $Top Name, Id,
        @{N='RAM(MB)'; E={[math]::Round($_.WorkingSet64 / 1MB, 0)}},
        @{N='CPU(s)';  E={[math]::Round($_.CPU, 1)}}
$ramProcs | ForEach-Object { Out ('{0,-30} pid={1,-7} ram={2,-8} MB  cpu={3} s' -f $_.Name, $_.Id, $_.'RAM(MB)', $_.'CPU(s)') }

# ── Known hogs check ─────────────────────────────────────────────────────────
Section 'KNOWN HOGS CHECK'
$watchlist = @{
    'Cursor'              = 'AI indexer — check which workspace is open; restart if CPU > 2000s'
    'Docker Desktop'      = 'Runs a full Linux VM — quit if not actively using containers'
    'com.docker.backend'  = 'Docker VM backend — quit Docker Desktop to stop this'
    'vmmemWSL'            = 'WSL memory — cap via %USERPROFILE%\.wslconfig if unused'
    'Wox'                 = 'Launcher — rebuild index if CPU > 500s (Settings → Index → Rebuild)'
    'LogiPluginService'   = 'Logitech — disable startup if not using special device features'
    'logioptionsplus_agent' = 'Logitech — companion to LogiPluginService'
    'Creative Cloud'      = 'Adobe background service — quit from tray when not needed'
    'SnagitCapture'       = 'Snagit — quit between capture sessions'
    'Move Mouse'          = 'Mouse jiggler — check interval; should use near-zero CPU'
}
$found = $false
foreach ($name in $watchlist.Keys) {
    $p = Get-Process $name -ErrorAction SilentlyContinue
    if ($p) {
        $found = $true
        $cpuS  = [math]::Round(($p | Measure-Object CPU -Sum).Sum, 1)
        $ramMb = [math]::Round(($p | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 0)
        Out "  [RUNNING] $name  cpu=${cpuS}s  ram=${ramMb}MB"
        Out "            $($watchlist[$name])"
    }
}
if (-not $found) { Out '  None of the watched processes are running.' }

# ── Save log ──────────────────────────────────────────────────────────────────
if ($SaveLog) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logPath = Join-Path $logDir "${timestamp}-perf-snapshot.txt"
    $lines | Set-Content -Path $logPath -Encoding UTF8
    Write-Host "`nLog saved: $logPath" -ForegroundColor Green
}
