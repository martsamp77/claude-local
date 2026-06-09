# tools/windows/identity

Identity and sign-in tooling — Windows Hello for Business, Entra/AD hybrid trust.

## Tools

| Tool | What it does |
|---|---|
| `setup-whfb-cloud-kerberos-trust.ps1` | One-time **server-side** setup for WHfB cloud Kerberos trust: installs the `AzureADHybridAuthenticationManagement` module and creates the `AzureADKerberos` object + `krbtgt_AzureAD` account in on-prem AD so Entra ID can issue partial TGTs. |
| `enable-whfb-cloud-trust-client.ps1` | **Client-side** pilot: backs up then sets `UseCloudTrustForOnPremAuth = 1` under `HKLM\SOFTWARE\Policies\Microsoft\PassportForWork` and starts `WbioSrvc` if stopped. `-Undo` reverts. |

## Quick start

```powershell
# 1. Server side — run as Domain Admin; prompts for an Entra Hybrid Identity / Global Admin sign-in
.\tools\windows\identity\setup-whfb-cloud-kerberos-trust.ps1 -Domain corp.example.com -UserPrincipalName admin@example.com

# 2. Client side — run elevated on the pilot machine
.\tools\windows\identity\enable-whfb-cloud-trust-client.ps1

# 3. Reboot, sign in once with the password, then lock/unlock with the PIN.
dsregcmd /status   # SSO State -> OnPremTgt: YES means it works
```

## When to use

A hybrid-joined PC (`dsregcmd`: `DomainJoined: YES` + `AzureAdJoined: YES`) where
Hello PIN fails with `0xC00000BB` / fingerprint with `0xC000005F` and the
HelloForBusiness event log shows `Deployment Type: Key Trust` failures — typically
because the domain has **no enterprise PKI**, which key trust requires. Cloud
Kerberos trust is the PKI-less replacement. Full diagnosis trail and verification
steps: [docs/windows/whfb-cloud-kerberos-trust-runbook.md](../../../docs/windows/whfb-cloud-kerberos-trust-runbook.md).

## Safety notes

- The server-side script changes **AD + the Entra tenant** (creates the Kerberos
  server object). It is idempotent; inverse is `Remove-AzureADKerberosServer`.
  Requires Domain Admin + Entra Hybrid Identity Administrator (or Global Admin).
- The client script writes **HKLM** (machine-wide policy) — it refuses to run
  non-elevated, exports a `.reg` backup to `backups\windows\registry\` first, and
  supports `-Undo`.
- Rotate the `krbtgt_AzureAD` key periodically:
  `Set-AzureADKerberosServer ... -RotateServerKey`.
