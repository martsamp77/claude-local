<#
.NAME        install-scantopdf-dashboard
.SYNOPSIS    Installs the ScanToPDF status dashboard: registers a SYSTEM start-up scheduled task that runs the web server, reserves the URL ACL, and opens a subnet-scoped inbound firewall rule. Run elevated.
.PLATFORM    windows
.CATEGORY    monitoring
.USAGE       .\tools\windows\monitoring\install-scantopdf-dashboard.ps1 -Subnet 10.0.0.0/24 [-Port 8088] [-SharePath \\srv\share\ScanToPDF-Status] [-DryRun] [-Uninstall]
.WHEN        One-time setup (or removal) of the ScanToPDF dashboard web app. Always preview with -DryRun first. Needs an elevated PowerShell.
#>
# Companion installer for scantopdf-dashboard.ps1. See docs/windows/scantopdf-dashboard-guide.md.
# The dashboard is READ-ONLY; this installer makes three machine changes (autostart task, urlacl,
# firewall rule), each reversed by -Uninstall. Access is scoped to -Subnet (no auth) per the chosen design.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Uninstall,
    # CIDR(s)/range(s) allowed to reach the dashboard port. REQUIRED for a real install (no default,
    # so we never open the port to the whole network by accident). e.g. '10.0.0.0/24' or '10.0.0.0/24','10.0.1.0/24'.
    [string[]]$Subnet,
    [int]$Port = 8088,
    # Optional network share to also publish the static snapshot to (the "share copy"). Passed to -Serve.
    [string]$SharePath,
    # Reveal raw document filenames on the dashboard (PII). OFF by default.
    [switch]$ShowFilenames,
    [string]$TaskName  = 'ScanToPDF Dashboard',
    [string]$TaskPath  = '\ScanToPDF\',
    [string]$FirewallRuleName = 'ScanToPDF Dashboard',
    [string]$DashboardScript
)

$ErrorActionPreference = 'Stop'
$tag = if ($DryRun) { '[DRYRUN] ' } else { '' }
if (-not $DashboardScript) { $DashboardScript = Join-Path $PSScriptRoot 'scantopdf-dashboard.ps1' }
$fullTaskName = ($TaskPath.TrimEnd('\') + '\' + $TaskName)
$urlAcl = "http://+:$Port/"

function Say  { param([string]$m, [string]$c = 'Gray') Write-Host "$tag$m" -ForegroundColor $c }
function Step { param([string]$m) Write-Host "`n=== $tag$m ===" -ForegroundColor Cyan }
function Do-It { param([string]$Description, [scriptblock]$Do)
    if ($DryRun) { Say "would: $Description" 'Green'; return }
    Say "doing: $Description" 'Green'; & $Do
}
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    if ($DryRun) { Say 'NOTE: not elevated. -DryRun preview only; a real run must be from an elevated PowerShell.' 'Yellow' }
    else { Write-Host 'ERROR: This installer must run elevated (Administrator).' -ForegroundColor Red; exit 1 }
}

# ===========================================================================
# UNINSTALL
# ===========================================================================
if ($Uninstall) {
    Step "Uninstalling dashboard ($fullTaskName)"
    if (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue) {
        Do-It "Stop + unregister task $fullTaskName" {
            Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
        }
    } else { Say "Task $fullTaskName not present." }

    if (Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue) {
        Do-It "Remove firewall rule '$FirewallRuleName'" { Remove-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue }
    } else { Say "Firewall rule '$FirewallRuleName' not present." }

    Do-It "Remove URL ACL $urlAcl" { & netsh http delete urlacl url=$urlAcl | Out-Null }
    Say "`nUninstall complete. (Snapshot files under ProgramData/the share are left in place.)" 'Green'
    Say 'Stop any running instance now: Get-CimInstance Win32_Process -Filter "Name=''pwsh.exe''" | ? CommandLine -like *scantopdf-dashboard* | % { Stop-Process -Id $_.ProcessId -Force }' 'Gray'
    return
}

# ===========================================================================
# INSTALL
# ===========================================================================
Step 'Pre-flight'
if (-not (Test-Path $DashboardScript)) { Write-Host "ERROR: dashboard script not found: $DashboardScript" -ForegroundColor Red; exit 1 }
if (-not $Subnet -or $Subnet.Count -eq 0) {
    if ($DryRun) { Say 'NOTE: -Subnet not supplied; a real install REQUIRES it (the firewall rule scope). Showing <SUBNET> placeholder.' 'Yellow'; $Subnet = @('<SUBNET>') }
    else { Write-Host "ERROR: -Subnet is required (e.g. -Subnet 10.0.0.0/24). Refusing to open the port network-wide." -ForegroundColor Red; exit 1 }
}
Say "Dashboard script : $DashboardScript"
Say "Task             : $fullTaskName  (SYSTEM, at startup, auto-restart)"
Say "URL / port       : $urlAcl"
Say "Firewall scope   : $($Subnet -join ', ')  (inbound TCP $Port)"
Say "Share copy       : $(if ($SharePath) { $SharePath } else { '(local snapshot only)' })"
Say "PII filenames    : $(if ($ShowFilenames) { 'SHOWN' } else { 'hidden (default)' })"

# port-in-use sanity check
$busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($busy) { Say "WARNING: port $Port already has a listener (PID $($busy.OwningProcess -join ',')). Choose another -Port or stop it first." 'Yellow' }

# --- 1. URL ACL (lets the SYSTEM task bind http://+:$Port/) ---------------
Step 'URL ACL'
Do-It "Reserve $urlAcl for NT AUTHORITY\SYSTEM" {
    $existing = & netsh http show urlacl url=$urlAcl 2>$null
    if ($existing -match [regex]::Escape($urlAcl)) { Say "  urlacl already present." }
    else { & netsh http add urlacl url=$urlAcl user="NT AUTHORITY\SYSTEM" | Out-Null }
}

# --- 2. firewall rule (subnet-scoped, inbound) ----------------------------
Step 'Firewall rule'
if (Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue) {
    Do-It "Replace existing firewall rule '$FirewallRuleName'" { Remove-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue }
}
Do-It "Allow inbound TCP $Port from $($Subnet -join ', ')" {
    New-NetFirewallRule -DisplayName $FirewallRuleName -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $Port -RemoteAddress $Subnet -Profile Any `
        -Description 'ScanToPDF status dashboard (read-only web app). Scoped to the office subnet.' | Out-Null
}

# --- 3. scheduled task (SYSTEM, at startup, no time limit, restart on failure) ---
Step 'Scheduled task'
# Run under PowerShell 7 (pwsh): Windows PowerShell 5.1's ConvertTo-Json has a serializer bug
# ("capacity was less than the current size") on this status object, breaking /status.json + the
# snapshot JSON. The HTML dashboard works under either; 5.1 is only a degraded fallback.
$exe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $exe) { $exe = 'powershell.exe'; Say 'NOTE: pwsh (PowerShell 7) not found - using Windows PowerShell 5.1. HTML dashboard works; /status.json + snapshot JSON will be unavailable.' 'Yellow' }
else { Say "Runtime          : $exe" }
$argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$DashboardScript`" -Serve -Port $Port"
if ($SharePath)     { $argLine += " -SharePath `"$SharePath`"" }
if ($ShowFilenames) { $argLine += ' -ShowFilenames' }
if (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue) { Say 'Task already exists - it will be replaced.' 'Yellow' }
Do-It "Register $fullTaskName and start it" {
    $action = New-ScheduledTaskAction -Execute $exe -Argument $argLine
    $trig   = New-ScheduledTaskTrigger -AtStartup
    $princ  = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    # Long-running web server: NO execution time limit (PT0S), restart if it ever dies, one instance only.
    $set    = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable `
                -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit ([TimeSpan]::Zero) `
                -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 3
    Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $action `
        -Trigger $trig -Principal $princ -Settings $set -Force `
        -Description 'ScanToPDF status dashboard - read-only web server (subnet-scoped) + static snapshot. See docs/windows/scantopdf-dashboard-guide.md.' | Out-Null
    Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
}

# --- 4. summary -----------------------------------------------------------
Step 'Done'
Say "ScanToPDF dashboard installed (or previewed)." 'Green'
Say ''
Say "Open it from a machine in $($Subnet -join ', '):" 'Gray'
Say "  http://$env:COMPUTERNAME`:$Port/    (or http://<server-ip>:$Port/)" 'Cyan'
Say "JSON for tooling: http://$env:COMPUTERNAME`:$Port/status.json   Health: /healthz" 'Gray'
if ($SharePath) { Say "Static snapshot (no server needed): $SharePath\status.html" 'Gray' }
Say "Local snapshot + server log: $env:ProgramData\ScanToPDF-Dashboard\" 'Gray'
Say ''
Say 'Verify:' 'Gray'
Say "  Get-ScheduledTask -TaskName '$TaskName' -TaskPath '$TaskPath' | Get-ScheduledTaskInfo" 'Gray'
Say "  Invoke-WebRequest http://localhost:$Port/healthz -UseBasicParsing   # -> 'ok' once warm (~10s)" 'Gray'
Say 'Uninstall:' 'Gray'
Say "  pwsh -File `"$PSCommandPath`" -Uninstall   # removes task + firewall rule + urlacl" 'Gray'
