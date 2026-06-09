<#
.SYNOPSIS    Re-enable Logitech Options+ and Adobe Creative Cloud autostart (inverse of disable-logitech-adobe-autostart.ps1).
.PLATFORM    windows
.DESCRIPTION
  Restores the three autostart Run values, sets the vendor services back to Automatic (and starts the Logi
  updater), and re-enables the Adobe Acrobat Update task. The agents relaunch at next sign-in (or start the
  updater service now). For a byte-exact registry restore instead, re-import the .reg files this machine's
  disable run saved under backups\windows\registry\<timestamp>-logitech-adobe-autostart\.
.USAGE       Run from an ELEVATED PowerShell:  .\staging\windows\restore-logitech-adobe-autostart.ps1
#>
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

Write-Host "== Restoring autostart Run values ==" -ForegroundColor Cyan
New-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' -Name 'Adobe Creative Cloud' -PropertyType String -Force `
    -Value '"C:\Program Files\Adobe\Adobe Creative Cloud\ACC\Creative Cloud.exe" --showwindow=false --onOSstartup=true' | Out-Null
New-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' -Name 'Adobe CCXProcess' -PropertyType String -Force `
    -Value 'C:\Program Files (x86)\Adobe\Adobe Creative Cloud Experience\CCXProcess.exe' | Out-Null
New-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Logitech Download Assistant' -PropertyType String -Force `
    -Value 'C:\Windows\system32\rundll32.exe C:\Windows\System32\LogiLDA.dll,LogiFetch' | Out-Null
New-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'TechSmithSnagit' -PropertyType String -Force `
    -Value '"C:\Program Files\TechSmith\Snagit\SnagitCapture.exe" /i' | Out-Null

Write-Host "== Setting vendor services back to Automatic ==" -ForegroundColor Cyan
foreach ($s in 'OptionsPlusUpdaterService','AdobeARMservice','AdobeUpdateService','FoxitReaderUpdateService') {
    if (Get-Service -Name $s -ErrorAction SilentlyContinue) { Set-Service -Name $s -StartupType Automatic }
}
Start-Service -Name 'OptionsPlusUpdaterService' -ErrorAction SilentlyContinue

Write-Host "== Re-enabling 'Adobe Acrobat Update Task' ==" -ForegroundColor Cyan
Enable-ScheduledTask -TaskPath '\' -TaskName 'Adobe Acrobat Update Task' -ErrorAction SilentlyContinue | Out-Null

Write-Host "`nDone. Sign out/in to relaunch the agents." -ForegroundColor Green
