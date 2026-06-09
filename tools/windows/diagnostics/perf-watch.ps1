<#
.NAME        perf-watch
.SYNOPSIS    Continuously poll top processes and alert when CPU or RAM crosses a threshold.
.PLATFORM    windows
.CATEGORY    diagnostics
.USAGE       .\tools\windows\diagnostics\perf-watch.ps1 [-IntervalSec 5] [-CpuThreshold 25] [-RamThresholdMb 800] [-Top 10] [-ExcludeDev] [-Exclude <names>] [-OnlyDev]
.WHEN        Catching intermittent spikes; watching a specific app; monitoring during a reproduce session
             Use -ExcludeDev for the live "what's busy NOW, ignoring my dev tools" view.
#>
param(
    [int]$IntervalSec    = 5,
    [double]$CpuThreshold   = 25.0,   # % CPU per interval (approx)
    [int]$RamThresholdMb = 800,
    [int]$Top            = 10,
    [switch]$ExcludeDev,        # hide the dev allowlist (node/Docker+WSL/PowerToys/Tailscale) from the live view
    [string[]]$Exclude = @(),   # extra process-name patterns to hide; -like, case-insensitive
    [switch]$OnlyDev            # inverse: show ONLY the dev allowlist
)

# Dev allowlist (dot-sourced). Filtering is applied to the live rankings/alerts only.
. "$PSScriptRoot\dev-allowlist.ps1"
$suppress = @()
if ($ExcludeDev) { $suppress += $DevAllowlist }
$suppress += $Exclude
function Test-Keep([string]$name) {
    if ($OnlyDev) { return (Test-DevProcess -Name $name -ExtraPatterns $Exclude) }
    foreach ($pat in $suppress) { if ($name -like $pat) { return $false } }
    return $true
}
$filterNote = if ($OnlyDev) { '  [DEV ONLY]' } elseif ($suppress.Count) { '  [DEV EXCLUDED]' } else { '' }

Write-Host "perf-watch  interval=${IntervalSec}s  cpu-alert>=${CpuThreshold}%  ram-alert>=${RamThresholdMb}MB${filterNote}  Ctrl+C to stop" -ForegroundColor Cyan
Write-Host ''

$prev = @{}  # pid -> previous CPU seconds

while ($true) {
    $snap     = Get-Date -Format 'HH:mm:ss'
    $procs    = Get-Process | Where-Object { $_.Id -gt 0 }
    $os       = Get-CimInstance Win32_OperatingSystem
    $freeGb   = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $totalGb  = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $usedGb   = [math]::Round($totalGb - $freeGb, 1)

    # Compute per-interval CPU delta
    $current = @{}
    $deltas  = [System.Collections.Generic.List[psobject]]::new()

    foreach ($p in $procs) {
        $current[$p.Id] = $p.CPU
        if ($prev.ContainsKey($p.Id) -and $p.CPU -gt 0) {
            $delta = $p.CPU - $prev[$p.Id]
            if ($delta -lt 0) { $delta = 0 }
            $ramMb = [math]::Round($p.WorkingSet64 / 1MB, 0)
            $deltas.Add([pscustomobject]@{
                Name   = $p.Name
                Id     = $p.Id
                DeltaS = [math]::Round($delta, 2)
                RamMb  = $ramMb
            })
        }
    }

    $prev = $current

    $rank   = $deltas | Where-Object { Test-Keep $_.Name }
    $top    = $rank | Sort-Object DeltaS -Descending | Select-Object -First $Top
    $alerts = $rank | Where-Object { ($_.DeltaS / $IntervalSec * 100) -ge $CpuThreshold -or $_.RamMb -ge $RamThresholdMb }

    # Suppression footer (live %): what the allowlist hid this interval, so nothing vanishes silently.
    $supNote = ''
    if ($OnlyDev) {
        $supNote = '(showing dev tools only — -OnlyDev)'
    } elseif ($suppress.Count) {
        $sup = @($deltas | Where-Object { -not (Test-Keep $_.Name) })
        if ($sup.Count) {
            $supPct = [math]::Round((($sup | Measure-Object DeltaS -Sum).Sum / $IntervalSec * 100), 1)
            $supRam = [math]::Round((($sup | Measure-Object RamMb  -Sum).Sum / 1024), 1)
            $supNote = "(suppressed: {0}  ~{1}% CPU now / {2} GB RAM)" -f (Get-DevCategoryBreakdown -Names $sup.Name -ExtraPatterns $Exclude), $supPct, $supRam
        }
    }

    Clear-Host
    Write-Host "[$snap]  RAM: ${usedGb} / ${totalGb} GB used  |  interval=${IntervalSec}s  Ctrl+C to stop" -ForegroundColor Cyan
    Write-Host ''

    if ($alerts.Count -gt 0) {
        Write-Host '  ALERTS:' -ForegroundColor Red
        foreach ($a in ($alerts | Sort-Object DeltaS -Descending)) {
            $cpuPct = [math]::Round($a.DeltaS / $IntervalSec * 100, 1)
            Write-Host ("  !! {0,-28} pid={1,-6} cpu~{2,5}%  ram={3} MB" -f $a.Name, $a.Id, $cpuPct, $a.RamMb) -ForegroundColor Red
        }
        Write-Host ''
    }

    $topLabel = if ($OnlyDev) { "Top $Top dev-tool activity this interval:" } elseif ($suppress.Count) { "Top $Top by activity this interval (dev tools excluded):" } else { "Top $Top by activity this interval:" }
    Write-Host "  $topLabel" -ForegroundColor Yellow
    foreach ($p in $top) {
        $cpuPct = [math]::Round($p.DeltaS / $IntervalSec * 100, 1)
        $color  = if (($p.DeltaS / $IntervalSec * 100) -ge $CpuThreshold -or $p.RamMb -ge $RamThresholdMb) { 'Red' } else { 'Gray' }
        Write-Host ("  {0,-28} pid={1,-6} cpu~{2,5}%  ram={3} MB" -f $p.Name, $p.Id, $cpuPct, $p.RamMb) -ForegroundColor $color
    }
    if ($supNote) { Write-Host "  $supNote" -ForegroundColor DarkGray }

    Start-Sleep -Seconds $IntervalSec
}
