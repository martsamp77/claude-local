<#
.NAME        enable-whfb-cloud-trust-client
.SYNOPSIS    Client-side pilot for WHfB cloud Kerberos trust: backs up and sets the UseCloudTrustForOnPremAuth policy registry value (HKLM), starts WbioSrvc if stopped. -Undo reverts.
.PLATFORM    windows
.CATEGORY    identity
.USAGE       .\tools\windows\identity\enable-whfb-cloud-trust-client.ps1 [-Undo]   (run elevated)
.WHEN        After the Azure AD Kerberos server object exists (setup-whfb-cloud-kerberos-trust.ps1) and a hybrid-joined client should switch Hello sign-in from key trust to cloud Kerberos trust; or to undo that pilot setting.
#>

# Registry equivalent of GPO: Windows Hello for Business ->
#   "Use cloud Kerberos trust for on-premises authentication" = Enabled
# Inverse: -Undo (deletes the value). A .reg backup is also written before any change.

[CmdletBinding()]
param(
    [switch]$Undo
)

$ErrorActionPreference = 'Stop'

$key      = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'
$regPath  = 'HKLM\SOFTWARE\Policies\Microsoft\PassportForWork'
$valName  = 'UseCloudTrustForOnPremAuth'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script writes HKLM and must run elevated. Re-launch PowerShell as Administrator." -ForegroundColor Red
    exit 1
}

# Backup before any change
$backupDir = Join-Path $repoRoot 'backups\windows\registry'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backup = Join-Path $backupDir ("{0}-PassportForWork.reg" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
reg export $regPath $backup /y 2>$null | Out-Null
if (Test-Path $backup) { Write-Host "Backup: $backup" } else { Write-Host "Note: $regPath did not exist yet; nothing to back up." }

if ($Undo) {
    if (Get-ItemProperty -Path $key -Name $valName -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $key -Name $valName
        Write-Host "Removed $valName - client is back to its previous trust model." -ForegroundColor Yellow
    } else {
        Write-Host "$valName not present; nothing to undo."
    }
    exit 0
}

if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
Set-ItemProperty -Path $key -Name $valName -Value 1 -Type DWord
Write-Host "Set $valName = 1 (cloud Kerberos trust enabled for Hello sign-in)." -ForegroundColor Green

# Biometric service: stopped WbioSrvc kills fingerprint even when the trust model is fixed
$wbio = Get-Service WbioSrvc -ErrorAction SilentlyContinue
if ($wbio -and $wbio.Status -ne 'Running') {
    Start-Service WbioSrvc
    Write-Host "Started WbioSrvc (Windows Biometric Service); was $($wbio.Status)."
} elseif ($wbio) {
    Write-Host "WbioSrvc already running."
}

Write-Host @"

Next steps:
  1. Reboot.
  2. Sign in ONCE with your password (picks up the policy + refreshes the PRT).
  3. Lock the machine, then unlock with the PIN.
  4. Verify:  dsregcmd /status   ->  SSO State: OnPremTgt: YES
     Event log Microsoft-Windows-HelloForBusiness/Operational, event 5205 ->
       "Use Cloud Trust for On-Premise Auth: true" and "Account has Cloud TGT: true"
  5. If fingerprint still complains after PIN works, re-enrol it in Settings > Sign-in options.

Undo:  .\tools\windows\identity\enable-whfb-cloud-trust-client.ps1 -Undo
"@
