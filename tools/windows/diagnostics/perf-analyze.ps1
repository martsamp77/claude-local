<#
.NAME        perf-analyze
.SYNOPSIS    Parse a perf-capture log into a ranked culprit list, slow-time windows, and an optional time-focused view.
.PLATFORM    windows
.CATEGORY    diagnostics
.USAGE       .\tools\windows\diagnostics\perf-analyze.ps1 [-Path <log>] [-Around HH:mm] [-WindowMin 3] [-CpuPct 60] [-DiskQ 2] [-Top 8]
.WHEN        After perf-capture has been running; you want to know what spiked, and when. Pass -Around to focus on a moment you felt the slowness.
#>
param(
    [string]$Path,             # default: most recent *-perf-capture.log under logs\windows\diagnostics
    [string]$Around,           # 'HH:mm' — focus the report on this moment
    [int]$WindowMin = 3,       # +/- minutes around -Around
    [double]$CpuPct = 60,      # a sample is "hot" when total CPU% >= this
    [double]$DiskQ  = 2,       # ...or when avg disk queue length >= this
    [int]$Top       = 8
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$logDir   = Join-Path $repoRoot 'logs\windows\diagnostics'

if (-not $Path) {
    $latest = Get-ChildItem (Join-Path $logDir '*-perf-capture.log') -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { Write-Host "No perf-capture logs found in $logDir. Run /capture start first." -ForegroundColor Yellow; exit 1 }
    $Path = $latest.FullName
}
if (-not (Test-Path $Path)) { Write-Host "Log not found: $Path" -ForegroundColor Red; exit 1 }

$lines = Get-Content $Path
$interval = ($lines | Where-Object { $_ -match 'interval=(\S+)' } | Select-Object -First 1) -replace '.*interval=(\S+).*', '$1'

# Parse data lines:  HH:mm:ss | CPU=  9.6% DiskQ=   0 Disk=  0% RAM=35.5/93.6GB | SPIKE | name(pct%/ramMB)  ...
$rx = '^(\d{2}:\d{2}:\d{2}) \| CPU=\s*([\d.]+)% DiskQ=\s*([\d.]+) Disk=\s*([\d.]+)% RAM=([\d.]+)/([\d.]+)GB \| (SPIKE|\s+) \| (.*)$'
$samples = foreach ($l in $lines) {
    if ($l -match $rx) {
        [pscustomobject]@{
            Time   = $Matches[1]
            Cpu    = [double]$Matches[2]
            DiskQ  = [double]$Matches[3]
            Disk   = [double]$Matches[4]
            RamUse = [double]$Matches[5]
            Spike  = ($Matches[7].Trim() -eq 'SPIKE')
            Procs  = $Matches[8]
        }
    }
}
if (-not $samples) { Write-Host "No parseable sample lines in $Path." -ForegroundColor Yellow; exit 1 }

# Optional time focus
$focus = $null
if ($Around) {
    try { $center = [datetime]::ParseExact($Around, 'HH:mm', $null) }
    catch { Write-Host "-Around must be HH:mm (24h). Got '$Around'." -ForegroundColor Red; exit 1 }
    $lo = $center.AddMinutes(-$WindowMin).ToString('HH:mm:ss')
    $hi = $center.AddMinutes( $WindowMin).ToString('HH:mm:ss')
    $focus = $samples | Where-Object { $_.Time -ge $lo -and $_.Time -le $hi }
}

function Parse-Procs([string]$blob) {
    # tokens are 'name(pct%/ramMB)' separated by 2+ spaces
    foreach ($tok in ($blob -split '\s{2,}')) {
        if ($tok -match '^(.*)\((\d+)%/(\d+)MB\)$') {
            [pscustomobject]@{ Name=$Matches[1]; Pct=[int]$Matches[2]; Ram=[int]$Matches[3] }
        }
    }
}

function Rank-Culprits($set, [int]$top) {
    $agg = @{}
    foreach ($s in $set) {
        foreach ($p in (Parse-Procs $s.Procs)) {
            if (-not $agg.ContainsKey($p.Name)) { $agg[$p.Name] = [pscustomobject]@{ Name=$p.Name; Peak=0; Sum=0; Count=0; MaxRam=0 } }
            $a = $agg[$p.Name]
            if ($p.Pct -gt $a.Peak) { $a.Peak = $p.Pct }
            if ($p.Ram -gt $a.MaxRam) { $a.MaxRam = $p.Ram }
            $a.Sum += $p.Pct; $a.Count++
        }
    }
    $agg.Values | Sort-Object Peak, Sum -Descending | Select-Object -First $top
}

$span   = "{0} -> {1}" -f $samples[0].Time, $samples[-1].Time
$hot    = $samples | Where-Object { $_.Cpu -ge $CpuPct -or $_.DiskQ -ge $DiskQ }
$cpuMax = ($samples | Measure-Object Cpu   -Maximum).Maximum
$cpuAvg = [math]::Round((($samples | Measure-Object Cpu -Average).Average), 1)
$dqMax  = ($samples | Measure-Object DiskQ -Maximum).Maximum
$dkMax  = ($samples | Measure-Object Disk  -Maximum).Maximum
$ramMax = ($samples | Measure-Object RamUse -Maximum).Maximum

Write-Host "=== PERF-ANALYZE ===" -ForegroundColor Cyan
Write-Host ("log      : {0}" -f (Split-Path $Path -Leaf))
Write-Host ("span     : {0}   samples={1}  interval={2}" -f $span, $samples.Count, $interval)
Write-Host ("CPU total: avg={0}%  max={1}%   DiskQ max={2}   Disk busy max={3}%   RAM used max={4} GB" -f $cpuAvg, $cpuMax, $dqMax, $dkMax, $ramMax)
Write-Host ("hot/spike: {0} of {1} samples crossed CPU>={2}% or DiskQ>={3}" -f $hot.Count, $samples.Count, $CpuPct, $DiskQ)

# Slow windows = contiguous runs of hot samples
Write-Host "`n=== SLOW WINDOWS ===" -ForegroundColor Cyan
if (-not $hot) {
    Write-Host "  None. The machine never crossed CPU/disk thresholds during this capture."
    Write-Host "  If it FELT slow while this was running, the bottleneck was NOT CPU/disk/RAM ->"
    Write-Host "  look at GPU/display, network, or a single application (re-run /capture analyze HH:mm at the slow moment)."
} else {
    $win = $null
    $windows = [System.Collections.Generic.List[object]]::new()
    foreach ($s in $samples) {
        $isHot = ($s.Cpu -ge $CpuPct -or $s.DiskQ -ge $DiskQ)
        if ($isHot) {
            if (-not $win) { $win = [pscustomobject]@{ Start=$s.Time; End=$s.Time; PeakCpu=$s.Cpu; PeakDq=$s.DiskQ; Rows=[System.Collections.Generic.List[object]]::new() } }
            $win.End = $s.Time
            if ($s.Cpu  -gt $win.PeakCpu) { $win.PeakCpu = $s.Cpu }
            if ($s.DiskQ -gt $win.PeakDq)  { $win.PeakDq  = $s.DiskQ }
            $win.Rows.Add($s)
        } elseif ($win) { $windows.Add($win); $win = $null }
    }
    if ($win) { $windows.Add($win) }
    foreach ($w in $windows) {
        $top1 = (Rank-Culprits $w.Rows 3 | ForEach-Object { "$($_.Name)($($_.Peak)%)" }) -join ', '
        Write-Host ("  {0}-{1}  peakCPU={2}%  peakDiskQ={3}  -> {4}" -f $w.Start, $w.End, $w.PeakCpu, $w.PeakDq, $top1)
    }
}

Write-Host "`n=== TOP CPU CONSUMERS (whole capture, by peak core%) ===" -ForegroundColor Cyan
Rank-Culprits $samples $Top | ForEach-Object {
    $avg = if ($_.Count) { [math]::Round($_.Sum / $_.Count, 0) } else { 0 }
    Write-Host ("  {0,-26} peak={1,4}%  avg={2,4}%  seen={3,4}x  maxRAM={4} MB" -f $_.Name, $_.Peak, $avg, $_.Count, $_.MaxRam)
}

if ($Around) {
    Write-Host ("`n=== FOCUS {0} +/-{1}min ===" -f $Around, $WindowMin) -ForegroundColor Cyan
    if (-not $focus) {
        Write-Host "  No samples in that window. Is the time right, and was the monitor running then?"
    } else {
        $fCpuMax = ($focus | Measure-Object Cpu -Maximum).Maximum
        $fDqMax  = ($focus | Measure-Object DiskQ -Maximum).Maximum
        Write-Host ("  {0} samples  peakCPU={1}%  peakDiskQ={2}" -f $focus.Count, $fCpuMax, $fDqMax)
        if ($fCpuMax -lt $CpuPct -and $fDqMax -lt $DiskQ) {
            Write-Host "  CPU and disk were CALM at that moment -> the slowness was elsewhere (GPU/display, network, or one app)."
        }
        Write-Host "  Hottest processes in window:"
        Rank-Culprits $focus 6 | ForEach-Object {
            Write-Host ("    {0,-26} peak={1,4}%  maxRAM={2} MB" -f $_.Name, $_.Peak, $_.MaxRam)
        }
    }
}
