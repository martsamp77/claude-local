<#
.NAME        perf-capture
.SYNOPSIS    Unattended background monitor: append timestamped CPU/RAM/disk samples to a log and flag spikes, for catching intermittent slowdowns.
.PLATFORM    windows
.CATEGORY    diagnostics
.USAGE       .\tools\windows\diagnostics\perf-capture.ps1 [-IntervalSec 5] [-CpuPct 60] [-DiskQ 2] [-DurationMin 0] [-Top 4]
.WHEN        Machine is intermittently slow ("comes and goes"); need to catch what spikes when it happens, unattended, then review by timestamp.
#>
param(
    [int]$IntervalSec = 5,      # seconds between samples
    [double]$CpuPct   = 60,     # flag a sample when total system CPU% >= this
    [double]$DiskQ    = 2,      # flag when avg disk queue length >= this
    [int]$DurationMin = 0,      # 0 = run until the process is stopped
    [int]$Top         = 4       # processes listed per line (top by CPU delta)
)

$ErrorActionPreference = 'SilentlyContinue'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$logDir   = Join-Path $repoRoot 'logs\windows\diagnostics'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile  = Join-Path $logDir "$stamp-perf-capture.log"
$pidFile  = Join-Path $logDir '.perf-capture.pid'   # consumed by /capture stop|status

# Static values (sample once)
$cs0    = Get-CimInstance Win32_ComputerSystem
$cores  = $cs0.NumberOfLogicalProcessors
$totGb  = [math]::Round($cs0.TotalPhysicalMemory / 1GB, 1)

function Log([string]$text) { Add-Content -Path $logFile -Value $text }

$h1 = "perf-capture  started=$(Get-Date -Format 's')  interval=${IntervalSec}s  cpu-flag>=${CpuPct}%  diskq-flag>=${DiskQ}  cores=$cores  totalRAM=${totGb}GB"
$h2 = "columns: HH:mm:ss | CPU=tot% DiskQ=avgQ Disk=busy% RAM=used/totGB | SPIKE | topProcs name(core%/RAM)"
Write-Host $h1 -ForegroundColor Cyan
Write-Host "logging to: $logFile" -ForegroundColor Cyan
Log $h1
Log $h2

# Seed previous CPU table
$prev = @{}
foreach ($p in (Get-Process)) { if ($p.CPU) { $prev[$p.Id] = $p.CPU } }

$end   = if ($DurationMin -gt 0) { (Get-Date).AddMinutes($DurationMin) } else { [datetime]::MaxValue }
$lastT = Get-Date

# Record this monitor's PID + log path so /capture stop|status can find it across sessions.
"$PID|$logFile|$(Get-Date -Format s)|interval=${IntervalSec}s" | Set-Content -Path $pidFile -Encoding ascii

try {
while ((Get-Date) -lt $end) {
    Start-Sleep -Seconds $IntervalSec
    $now = Get-Date
    $dt  = ($now - $lastT).TotalSeconds
    if ($dt -le 0) { $dt = $IntervalSec }
    $lastT = $now

    # System counters (instantaneous sample)
    $c = (Get-Counter -Counter @(
        '\Processor(_Total)\% Processor Time',
        '\PhysicalDisk(_Total)\Avg. Disk Queue Length',
        '\PhysicalDisk(_Total)\% Disk Time'
    ) -ErrorAction SilentlyContinue).CounterSamples
    $cpuTot = [math]::Round((($c | Where-Object { $_.Path -match 'processor time' }).CookedValue), 1)
    $dq     = [math]::Round((($c | Where-Object { $_.Path -match 'queue' }).CookedValue), 1)
    $dbusy  = [math]::Round((($c | Where-Object { $_.Path -match 'disk time' }).CookedValue), 0)

    $freeGb = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
    $usedGb = [math]::Round($totGb - $freeGb, 1)

    # Per-process CPU deltas (core %)
    $cur  = @{}
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($p in (Get-Process)) {
        if (-not $p.CPU) { continue }
        $cur[$p.Id] = $p.CPU
        if ($prev.ContainsKey($p.Id)) {
            $d = $p.CPU - $prev[$p.Id]
            if ($d -gt 0.01) {
                $rows.Add([pscustomobject]@{
                    Name = $p.Name
                    Pct  = [math]::Round($d / $dt * 100, 0)
                    Ram  = [math]::Round($p.WorkingSet64 / 1MB, 0)
                })
            }
        }
    }
    $prev = $cur

    $topStr = (($rows | Sort-Object Pct -Descending | Select-Object -First $Top) |
        ForEach-Object { "{0}({1}%/{2}MB)" -f $_.Name, $_.Pct, $_.Ram }) -join '  '

    $spike = ($cpuTot -ge $CpuPct) -or ($dq -ge $DiskQ)
    $flag  = if ($spike) { 'SPIKE' } else { '     ' }
    Log ("{0} | CPU={1,5}% DiskQ={2,4} Disk={3,3}% RAM={4}/{5}GB | {6} | {7}" -f `
        $now.ToString('HH:mm:ss'), $cpuTot, $dq, $dbusy, $usedGb, $totGb, $flag, $topStr)
}
}
finally {
    # Best-effort cleanup; a -Force kill skips this, so stop|status also verify the PID is alive.
    Remove-Item -Path $pidFile -ErrorAction SilentlyContinue
}
