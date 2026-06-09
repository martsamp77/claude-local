<#
.SYNOPSIS    Disable Logitech Options+ and Adobe Creative Cloud autostart, and stop their running processes.
.PLATFORM    windows
.DESCRIPTION
  Reversible. Backs up both HKLM Run keys to backups\windows\registry\ FIRST, then:
    - removes the autostart Run values (Adobe Creative Cloud, Adobe CCXProcess, Logitech Download Assistant)
    - sets OptionsPlusUpdaterService / AdobeARMservice / AdobeUpdateService to Manual (stops the Logi updater)
    - disables the "Adobe Acrobat Update Task" scheduled task
    - stops the running Logitech + Adobe processes (incl. Adobe's bundled node.exe — NOT your dev node)
  Inverse: staging\windows\restore-logitech-adobe-autostart.ps1
.USAGE       Run from an ELEVATED PowerShell:  .\staging\windows\disable-logitech-adobe-autostart.ps1
.WHEN        You want Logitech Options+ and Adobe CC to stop draining CPU and stop relaunching at logon.
#>
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$bk       = Join-Path $repoRoot "backups\windows\registry\$stamp-logitech-adobe-autostart"
New-Item -ItemType Directory -Path $bk -Force | Out-Null

Write-Host "== 1/5  Backing up HKLM Run keys -> $bk ==" -ForegroundColor Cyan
reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"               "$bk\HKLM-Run.reg"            /y | Out-Null
reg export "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"   "$bk\HKLM-WOW6432Node-Run.reg" /y | Out-Null

Write-Host "== 2/5  Removing autostart Run values ==" -ForegroundColor Cyan
Remove-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' -Name 'Adobe Creative Cloud' -ErrorAction SilentlyContinue
Remove-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' -Name 'Adobe CCXProcess'     -ErrorAction SilentlyContinue
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'             -Name 'Logitech Download Assistant' -ErrorAction SilentlyContinue
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'             -Name 'TechSmithSnagit' -ErrorAction SilentlyContinue
# NOTE: 'Corsair iCUE5 Software' is intentionally left in place (may drive CPU cooling/fan curves).

Write-Host "== 3/5  Setting vendor services to Disabled ==" -ForegroundColor Cyan
foreach ($s in 'OptionsPlusUpdaterService','AdobeARMservice','AdobeUpdateService','FoxitReaderUpdateService') {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($svc) {
        Set-Service -Name $s -StartupType Disabled
        if ($svc.Status -eq 'Running') { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
        Write-Host "   $s -> Disabled$(if($svc.Status -eq 'Running'){' (stopped)'})"
    }
}

Write-Host "== 4/5  Disabling 'Adobe Acrobat Update Task' ==" -ForegroundColor Cyan
Disable-ScheduledTask -TaskPath '\' -TaskName 'Adobe Acrobat Update Task' -ErrorAction SilentlyContinue | Out-Null

Write-Host "== 5/5  Stopping running Logitech + Adobe processes ==" -ForegroundColor Cyan
$names = @(
    'logioptionsplus_agent','logioptionsplus_appbroker','logioptionsplus_updater',
    'LogiPluginService','LogiPluginServiceExt',
    'Creative Cloud','Creative Cloud Helper','CCXProcess','CoreSync',
    'AdobeIPCBroker','Adobe Desktop Service','AdobeCollabSync','AdobeNotificationClient','AdobeNotificationHelper',
    'SnagitCapture'   # background capture helper only — NOT SnagitEditor (you may have it open with work)
)
Get-Process -Name $names -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
# Adobe ships its own node.exe under \Adobe\... — stop only those, leave dev node (Codex/pnpm/vite) running.
Get-CimInstance Win32_Process -Filter "name='node.exe'" |
    Where-Object { $_.CommandLine -match '\\Adobe\\' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host "`nDone." -ForegroundColor Green
Write-Host "Reboot or sign out/in to confirm nothing relaunches." -ForegroundColor Green
Write-Host "Undo: .\staging\windows\restore-logitech-adobe-autostart.ps1 (elevated), or re-import the .reg files in:`n  $bk" -ForegroundColor Yellow
