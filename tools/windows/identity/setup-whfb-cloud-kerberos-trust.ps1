<#
.NAME        setup-whfb-cloud-kerberos-trust
.SYNOPSIS    One-time server-side setup for Windows Hello for Business cloud Kerberos trust: creates the Azure AD Kerberos server object (AzureADKerberos computer + krbtgt_AzureAD account) in on-prem AD so Entra ID can issue partial TGTs.
.PLATFORM    windows
.CATEGORY    identity
.USAGE       .\tools\windows\identity\setup-whfb-cloud-kerberos-trust.ps1 -Domain <ad-dns-domain> -UserPrincipalName <entra-admin-upn>
.WHEN        Hello PIN/fingerprint fails on a hybrid-joined PC with 0xC00000BB (key trust, no PKI) and the fix is to deploy cloud Kerberos trust; or the user asks to "enable cloud Kerberos trust" / "create the Azure AD Kerberos server object".
#>

# Run as a DOMAIN ADMIN of the target AD domain. You will be prompted twice:
#   1. Get-Credential          -> on-prem domain-admin credential
#   2. interactive web sign-in -> Entra Hybrid Identity Administrator or Global Administrator
#
# Inverse (full rollback, do NOT run casually):
#   Remove-AzureADKerberosServer -Domain <domain> -UserPrincipalName <upn> -DomainCredential <cred>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Domain,             # AD DNS domain, e.g. corp.example.com
    [Parameter(Mandatory)] [string]$UserPrincipalName   # Entra admin UPN used for the cloud sign-in
)

$ErrorActionPreference = 'Stop'

Write-Host "== WHfB cloud Kerberos trust setup for domain '$Domain' ==" -ForegroundColor Cyan

# Set-AzureADKerberosServer requires an elevated shell in addition to the domain-admin credential
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This must run in an ELEVATED shell (Run as Administrator), then it will also prompt for the domain-admin credential." -ForegroundColor Red
    exit 1
}

# 1. Module
$mod = Get-Module -ListAvailable -Name AzureADHybridAuthenticationManagement
if (-not $mod) {
    Write-Host "[1/4] Installing AzureADHybridAuthenticationManagement module (CurrentUser scope)..."
    Install-Module AzureADHybridAuthenticationManagement -Scope CurrentUser -Force -AllowClobber
} else {
    Write-Host "[1/4] Module already installed (v$($mod[0].Version))."
}
Import-Module AzureADHybridAuthenticationManagement

# 2. Domain-admin credential — prompt in the console; Get-Credential on PS 5.1
#    pops a GUI dialog that can hide behind the window and look like a hang.
Write-Host "[2/4] Enter the on-prem domain-admin credential for ${Domain}:"
$credUser = Read-Host "  Username (e.g. DOMAIN\admin)"
$credPass = Read-Host "  Password" -AsSecureString
$domainCred = [System.Management.Automation.PSCredential]::new($credUser, $credPass)

# 3. Create / update the Azure AD Kerberos server object.
#    Idempotent: safe to re-run; rotates nothing unless -RotateServerKey is added.
Write-Host "[3/4] Creating the Azure AD Kerberos server object (an Entra sign-in window will open)..."
Set-AzureADKerberosServer -Domain $Domain -UserPrincipalName $UserPrincipalName -DomainCredential $domainCred

# 4. Verify
Write-Host "[4/4] Verifying..."
$srv = Get-AzureADKerberosServer -Domain $Domain -UserPrincipalName $UserPrincipalName -DomainCredential $domainCred
$srv | Format-List Id, DomainDnsName, ComputerAccount, UserAccount, KeyVersion, KeyUpdatedOn, KeyUpdatedFrom

# The object is healthy when both the cloud and AD copies exist and key versions are present.
if ($srv -and $srv.Id -and $srv.KeyVersion) {
    Write-Host "`nPASS: Azure AD Kerberos server object exists (KeyVersion $($srv.KeyVersion), updated $($srv.KeyUpdatedOn))." -ForegroundColor Green
    Write-Host @"

Next steps:
  1. On the pilot client, run elevated:  .\tools\windows\identity\enable-whfb-cloud-trust-client.ps1
  2. Reboot the client, sign in ONCE with the password, then lock and unlock with the PIN.
  3. Verify with:  dsregcmd /status   ->  OnPremTgt: YES
"@
} else {
    Write-Host "`nFAIL: Get-AzureADKerberosServer did not return a healthy object. Review the output above." -ForegroundColor Red
    exit 1
}
