<#
.NAME        perf-snapshot
.SYNOPSIS    Capture a one-time performance snapshot: CPU, RAM, disk, top processes, pagefile, power plan, VMs.
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
$commitGb       = [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1MB, 1)
$totalVirtualGb = [math]::Round($os.TotalVirtualMemorySize / 1MB, 1)
$commitPct      = [math]::Round($commitGb / $totalVirtualGb * 100, 0)
Out "Committed: ${commitGb} GB / ${totalVirtualGb} GB virtual  (${commitPct}%)"
if ($commitPct -gt 85) { Out '  ^^^ > 85% committed — system will swap under load' }

# ── Pagefile ──────────────────────────────────────────────────────────────────
Section 'PAGEFILE'
Get-CimInstance Win32_PageFileUsage | ForEach-Object {
    Out "$($_.Name)  allocated=$($_.AllocatedBaseSize) MB  current=$($_.CurrentUsage) MB  peak=$($_.PeakUsage) MB"
    if ($_.PeakUsage -gt 2000) { Out '  ^^^ Peak > 2 GB — significant swapping has occurred this session' }
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

# ── Virtual machine identification ───────────────────────────────────────────
Section 'VIRTUAL MACHINES'
$vmwps = Get-CimInstance Win32_Process -Filter "name='vmwp.exe'" -ErrorAction SilentlyContinue
if (-not $vmwps) {
    Out '  No vmwp.exe processes — no Hyper-V VMs running.'
} else {
    # Scan named pipes once — used to identify VM owners
    $allPipes = try { [System.IO.Directory]::GetFiles('\\.\pipe\') } catch { @() }

    foreach ($vmwp in $vmwps) {
        $vpid = $vmwp.ProcessId

        # Find the vmmem child
        $vmmemChild = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ParentProcessId -eq $vpid -and $_.Name -match 'vmmem' } |
            Select-Object -First 1
        $ramMb = 0
        $vmmemName = 'vmmem'
        if ($vmmemChild) {
            $vmmemName = $vmmemChild.Name
            $vmmemProc = Get-Process -Id $vmmemChild.ProcessId -ErrorAction SilentlyContinue
            if ($vmmemProc) { $ramMb = [math]::Round($vmmemProc.WorkingSet64 / 1MB, 0) }
        }

        # Identify VM type from named pipes
        $identity = 'Unknown Hyper-V VM'
        $pipeHints = $allPipes | Where-Object {
            $_ -match 'cowork|wslg|wsl|docker.desktop|docker_sandbox|android|WindowsSubsystemAndroid|wsa'
        }
        foreach ($pipe in $pipeHints) {
            if ($pipe -match 'cowork')                              { $identity = 'Cowork (collaboration app VM)'; break }
            if ($pipe -match 'docker.desktop|docker_sandbox')      { $identity = 'Docker Desktop VM'; break }
            if ($pipe -match 'wslg|wsl')                           { $identity = 'WSL2'; break }
            if ($pipe -match 'android|WindowsSubsystemAndroid|wsa'){ $identity = 'Windows Subsystem for Android'; break }
        }
        # vmmemWSL is always WSL regardless of pipes
        if ($vmmemName -eq 'vmmemWSL') { $identity = 'WSL2' }

        Out "  vmwp pid=${vpid}  →  ${vmmemName}  RAM=${ramMb} MB  Identity: ${identity}"
    }
}

# ── Known hogs check ─────────────────────────────────────────────────────────
Section 'KNOWN HOGS CHECK'
$watchlist = [ordered]@{
    # Dev tools
    'Cursor'                = 'AI code editor indexer — restart if CPU > 2000s; check workspace size'
    # Docker / VMs
    'Docker Desktop'        = 'Runs a full Linux VM — quit from tray if not containerizing'
    'com.docker.backend'    = 'Docker VM backend — if running without Docker UI, it is orphaned; kill it'
    'vmmemWSL'              = 'WSL2 memory — cap via %USERPROFILE%\.wslconfig [wsl2] memory=4GB'
    # Launchers
    'Wox'                   = 'Launcher — rebuild index if CPU > 500s: Settings → Index → Rebuild'
    # Peripheral software
    'LogiPluginService'     = 'Logitech plugin service — disable startup if not using special device features'
    'logioptionsplus_agent' = 'Logitech Options+ agent — companion to LogiPluginService; both should be near-zero CPU'
    'RzSynapse'             = 'Razer Synapse — peripheral manager; should be near-zero; restart if CPU > 1000s'
    # Adobe
    'Creative Cloud'        = 'Adobe CC background service — quit from tray; disable autostart in CC Preferences'
    'AdobeCollabSync'       = 'Adobe Collab background sync — stops when Creative Cloud quits'
    # Capture / media
    'SnagitCapture'         = 'Snagit capture engine — quit between sessions to reclaim RAM'
    # Voice / dictation
    'Wispr Flow'            = 'AI voice dictation — 1-2 processes is normal; more = orphaned instances, restart app'
    'Wispr Flow Helper'     = 'Wispr Flow helper — should follow parent; if running alone, restart Wispr Flow'
    # Utilities
    'Move Mouse'            = 'Mouse jiggler — check interval; 1-second loops cause high CPU'
}
$found = $false
foreach ($name in $watchlist.Keys) {
    $procs = Get-Process $name -ErrorAction SilentlyContinue
    if ($procs) {
        $found  = $true
        $count  = @($procs).Count
        $cpuS   = [math]::Round(($procs | Measure-Object CPU -Sum).Sum, 1)
        $ramMb  = [math]::Round(($procs | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 0)
        $label  = if ($count -gt 1) { "  [RUNNING x${count}]" } else { '  [RUNNING]' }
        Out "${label} $name  cpu=${cpuS}s  ram=${ramMb}MB"
        Out "            $($watchlist[$name])"
    }
}

# Notepad++ anomaly check — should never accumulate significant CPU
$npp = Get-Process 'notepad++' -ErrorAction SilentlyContinue
if ($npp) {
    $nppCpu = [math]::Round(($npp | Measure-Object CPU -Sum).Sum, 1)
    if ($nppCpu -gt 500) {
        $found = $true
        Out "  [ANOMALY] notepad++  cpu=${nppCpu}s — text editor should be near-zero; likely a runaway plugin or very large file"
    }
}

if (-not $found) { Out '  None of the watched processes flagged.' }

# ── Save log ──────────────────────────────────────────────────────────────────
if ($SaveLog) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logPath = Join-Path $logDir "${timestamp}-perf-snapshot.txt"
    $lines | Set-Content -Path $logPath -Encoding UTF8
    Write-Host "`nLog saved: $logPath" -ForegroundColor Green
}
