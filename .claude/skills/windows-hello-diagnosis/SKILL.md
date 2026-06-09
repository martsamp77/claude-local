---
name: windows-hello-diagnosis
description: "[windows] Diagnose and fix Windows Hello PIN/fingerprint failures — credentials lost after lock, re-enrollment not sticking, biometrics greyed out, or PIN error 0xC00000BB on hybrid-joined PCs. Covers services, NGC corruption, domain/Intune device registration, key-trust-without-PKI (cloud Kerberos trust fix), and TPM issues."
---

# windows-hello-diagnosis

Use when: PIN stops working after being away from the lock screen, fingerprint isn't recognised, Windows Hello asks to re-enrol but the new credential doesn't stick, or both methods fail simultaneously after a period of inactivity.

## Fast diagnostic sequence

Run these five commands first (non-elevated OK for most; NGC folder check needs admin). They reveal root cause in under a minute.

```powershell
# 1. Services — WbioSrvc stopped is an instant fingerprint killer
Get-Service WbioSrvc, NgcCtnrSvc | Select-Object Name, Status, StartType

# 2. Device registration — the single most revealing command on corporate machines
dsregcmd /status

# 3. NGC folder — exists and non-empty means credentials are present
$ngc = "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc"
if (Test-Path $ngc -ErrorAction SilentlyContinue) { "Present" } else { "Absent/inaccessible" }

# 4. Event logs — errors in the last 24h tell you what's actively failing
Get-WinEvent -LogName "Microsoft-Windows-User Device Registration/Admin" -ErrorAction SilentlyContinue |
    Where-Object { $_.TimeCreated -gt (Get-Date).AddHours(-24) -and $_.Level -le 3 } |
    Select-Object TimeCreated, Id, Message -First 10 | Format-List

# 5. Intune PIN policy (only relevant if machine is MDM-managed)
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Policies\PassportForWork" -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue | Select-Object Expiration, UsePassportForWork }
```

## Read dsregcmd /status — what to look for

| Field | What it means |
|---|---|
| `DomainJoined: YES` | Machine is on a corporate AD domain — WHfB/Intune rules apply |
| `WorkplaceJoined: YES` | Work account registered (Intune MDM managed) |
| `AzureAdJoined: YES` | Full Azure AD join — WHfB works natively |
| `NgcSet: YES` | Credential exists in NGC container |
| `AzureAdPrt: NO` | No Primary Refresh Token — cloud validation will fail |
| `Previous Registration → error_missing_device` | **Device object deleted from Azure AD** — root cause of periodic credential loss |
| `Server ErrorSubCode: error_missing_device` | Fix: `dsregcmd /forcerecovery` (run as user, not admin) |

## Root causes and fixes (in order of probability)

### 1. Broken Azure AD device registration (domain + Intune machines)

**Symptom**: PIN works immediately after lock, fails after 10–60 min. Re-enrolment doesn't stick.

**Why**: Intune pushes a Windows Hello for Business policy. WHfB validates the NGC credential against the Azure AD device object on every unlock. If that device object was deleted from Azure AD (stale, admin cleanup, re-imaging), validation fails and the credential is torn down. The renewal attempt runs hourly; if it fails, it can trigger within minutes too.

**Diagnosis**: `dsregcmd /status` → Diagnostic Data section → look for `error_missing_device`.

**Fix** (run as regular user, not admin):
```powershell
dsregcmd /forcerecovery
```
Then `dsregcmd /status` again — `WorkplaceDeviceId` should change to a new GUID and `DeviceCertificateValidity` should start at the current time. Re-enrol PIN and fingerprint after.

**If forcerecovery fails**: Settings → Accounts → Access work or school → click the work account → Disconnect → reconnect with the work email. Creates a fresh device object in Azure AD.

**Where the Intune WHfB policy lives** (useful for reading PIN complexity, expiration etc.):
```
HKLM:\SOFTWARE\Microsoft\Policies\PassportForWork\<tenantId>\Device\Policies\PINComplexity
```
Key values: `Expiration` (days, 0 = never), `MinimumPINLength`, `History`.

---

### 2. Hybrid key trust without PKI — PIN error 0xC00000BB at every logon

**Symptom**: On a hybrid-joined PC (`dsregcmd`: `DomainJoined: YES` + `AzureAdJoined: YES`), PIN fails at the lock screen with `status: 0xc00000bb` (fingerprint: `0xc000005f`). Re-enrollment "succeeds" but the next sign-in fails again. Device registration looks perfectly healthy (`DeviceAuthStatus: SUCCESS`, valid PRT) but SSO State shows `OnPremTgt: NO`. The machine doesn't show at myaccount.microsoft.com/device-list — that's *expected* for hybrid join (no registered owner), and a clue the failing box took a different join path than working Entra-joined siblings.

**Why**: Hello sign-in on a hybrid machine must also authenticate to an on-prem DC. The default **key trust** model requires DCs to hold PKINIT certificates from an enterprise CA. No AD CS in the domain → `0xC00000BB` (STATUS_NOT_SUPPORTED) forever; enrollment still works because it only talks to Entra.

**Diagnosis** (all read-only, regular user):
```powershell
Get-WinEvent -LogName "Microsoft-Windows-HelloForBusiness/Operational" -MaxEvents 40
# Event 7001: "Deployment Type: Key Trust ... 0xC00000BB"
# Event 5205: "Use Cloud Trust for On-Premise Auth: false / Account has Cloud TGT: false"
certutil -store -enterprise NTAuth                                  # empty => no enterprise PKI
([adsisearcher]"(objectClass=pKIEnrollmentService)").FindAll()      # none => no AD CS
([adsisearcher]"(&(objectClass=computer)(name=AzureADKerberos))").FindOne()  # null => cloud trust not deployed
nltest /dsgetdc:<domain> /keylist /kdc                              # KEYLIST flag => DCs (2016+) can do cloud trust
```

**Fix**: deploy **cloud Kerberos trust** (PKI-less, Microsoft-recommended):
1. Server side (once, Domain Admin + Entra Hybrid Identity/Global Admin): `tools\windows\identity\setup-whfb-cloud-kerberos-trust.ps1 -Domain <domain> -UserPrincipalName <entra-admin-upn>`
2. Client pilot (elevated): `tools\windows\identity\enable-whfb-cloud-trust-client.ps1` (sets `UseCloudTrustForOnPremAuth=1`; `-Undo` reverts)
3. Reboot → password sign-in once → PIN. Verify `dsregcmd /status` → `OnPremTgt: YES` and event 5205 flips to true.

Full trail: `docs/windows/whfb-cloud-kerberos-trust-runbook.md`.

---

### 3. WbioSrvc stopped (fingerprint dead on return from idle)

**Symptom**: Fingerprint fails after idle, PIN may still work. `Get-Service WbioSrvc` shows `Stopped`.

**Why**: Something knocked the Windows Biometric Service down (driver update, failed Hello loop, crash). It's set to Automatic but didn't restart.

**Fix** (elevated):
```powershell
Start-Service WbioSrvc
# Confirm:
Get-Service WbioSrvc | Select-Object Status, StartType
```

---

### 4. NGC folder corruption

**Symptom**: PIN and fingerprint both fail. Re-enrolment appears to succeed but credentials vanish on next lock.

**Why**: The NGC folder holds the key containers for all Windows Hello credentials. Corruption means new credentials written into it also fail to load.

**Fix** (elevated — `takeown` needed because folder is owned by LocalService):
```powershell
$ngc = "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc"
Stop-Service NgcCtnrSvc -Force -ErrorAction SilentlyContinue
Stop-Service WbioSrvc -Force -ErrorAction SilentlyContinue
cmd /c "takeown /f `"$ngc`" /r /a /d y" 2>$null
cmd /c "icacls `"$ngc`" /grant *S-1-5-32-544:(OI)(CI)F /t /c /q" 2>$null
cmd /c "rd /s /q `"$ngc`"" 2>$null
Start-Service WbioSrvc
Start-Service NgcCtnrSvc -ErrorAction SilentlyContinue
```
Then re-enrol PIN first, then fingerprint (PIN is required before biometrics will register).

---

### 5. NgcCtnrSvc startup type wrong

**Symptom**: PIN fails after cold boot or after service manager restarts. Works in the same session.

**Why**: NgcCtnrSvc is a protected trigger-start service. `Set-Service` will be denied with "Access is denied" — this is expected. The service runs on demand via Windows triggers; Manual startup is correct. If it's Disabled, that's wrong.

**Check**:
```powershell
sc.exe qc NgcCtnrSvc   # should show START_TYPE: DEMAND_START (3), not DISABLED (4)
```
If disabled:
```powershell
sc.exe config NgcCtnrSvc start= demand
```

---

### 6. TPM anti-hammering lockout

**Symptom**: All Hello methods fail simultaneously. Timing: exactly around 10-minute intervals (TPM forgets 1 failed attempt per 10 min; locks after 32 failures).

**Diagnosis**:
```powershell
Get-Tpm | Select-Object LockoutCount, LockoutHealTime, LockoutMax
```
`LockoutCount > 0` with `TpmReady: False` confirms lockout.

**Fix** (elevated):
```powershell
Clear-TpmAuthValue   # preferred — clears lockout without full TPM reset
# If that fails:
# Clear-Tpm          # nuclear option — removes all TPM keys; check BitLocker first
Get-BitLockerVolume | Select-Object MountPoint, VolumeStatus, ProtectionStatus
```

---

## Service reference

| Service | Display Name | Normal state | Startup type |
|---|---|---|---|
| `WbioSrvc` | Windows Biometric Service | Running | Automatic |
| `NgcCtnrSvc` | Microsoft Passport Container | Running (on demand) | Manual (trigger-start) |

## Event logs to check for Hello failures

```powershell
# Device registration failures (most useful on domain/Intune machines)
Get-WinEvent -LogName "Microsoft-Windows-User Device Registration/Admin" -MaxEvents 20 | Format-List TimeCreated, Id, Message

# Biometric errors (sensor, key container failures)
Get-WinEvent -LogName "Microsoft-Windows-Biometrics/Operational" -MaxEvents 20 | Format-List TimeCreated, Id, Message

# Windows Hello for Business specific
Get-WinEvent -LogName "Microsoft-Windows-HelloForBusiness/Operational" -ErrorAction SilentlyContinue -MaxEvents 20 | Format-List TimeCreated, Id, Message
```

Key event IDs:
- **304** — Automatic device registration failed (look for `error_missing_device`)
- **360** — WHfB provisioning will not launch (device not AAD joined, policy mismatch)
- **420** — Kerberos ticket acquisition failure (DC or AAD auth issue)
- **1014** — Biometric: failed to delete/access DB record (key container broken — `0x8009801B = NTE_BAD_KEYSET`)

## Fix decision tree

```
PIN/fingerprint failing after idle?
│
├─ dsregcmd /status → error_missing_device?
│   └─ YES → dsregcmd /forcerecovery (as user) → re-enrol
│
├─ Hybrid-joined + PIN error 0xC00000BB + HelloForBusiness event 7001 "Key Trust"?
│   └─ YES → no PKI? (NTAuth empty) → deploy cloud Kerberos trust
│            (tools\windows\identity\, see root cause #2)
│
├─ Get-Service WbioSrvc → Stopped?
│   └─ YES → Start-Service WbioSrvc → test fingerprint
│
├─ Re-enrolment fails to stick (credential gone on next lock)?
│   └─ Clear NGC folder (admin) → re-enrol PIN then fingerprint
│
├─ Get-Tpm → LockoutCount > 0?
│   └─ YES → Clear-TpmAuthValue → re-enrol
│
└─ Nothing above → check event logs (Device Registration/Admin + Biometrics)
```

## When forcerecovery doesn't hold: stale AD computer object (requires IT admin)

If `dsregcmd /forcerecovery` temporarily fixes the registration but the PIN keeps getting wiped every ~hour, the problem has moved to the server side.

**Symptom**: `dsregcmd /status` → Diagnostic Data shows `error_missing_device` for the SAME old device GUID every time, even after forcerecovery created a new `WorkplaceDeviceId`. The old GUID is not in the local registry.

**Cause**: The old device ID is embedded in the on-prem AD computer object's attributes (e.g. `userCertificate`, `msDS-KeyCredentialLink`). Azure AD Connect synced it there. An IT admin deleted the Azure AD device object, but the AD attributes still point to it. The `Automatic-Device-Join` scheduled task (protected; runs as SYSTEM every hour) reads those attributes via Kerberos, tries to renew the dead device, fails with `error_missing_device`, and Windows wipes the NGC credentials as a security response.

**This task cannot be disabled from the local machine** — it's TrustedInstaller-protected. `Disable-ScheduledTask`, `schtasks /Change /Disable`, `takeown`, and COM Task Scheduler API all return "Access is denied" even from an elevated admin shell.

**What to tell IT admin:**
> Windows Hello PIN on `<machine>` is being wiped every hour by the `Automatic-Device-Join` scheduled task. Failing with `error_missing_device` for Azure AD device `<guid>`. That object was deleted from Azure AD but the ID remains in the machine's on-prem AD computer object attributes. Fix: clear the stale device attributes from `<machine>$` in on-prem AD (likely `userCertificate` or `msDS-KeyCredentialLink`), then run an Azure AD Connect delta sync. The machine will register a fresh device object and Windows Hello will function normally.

The device GUID and machine name come from `dsregcmd /status` → `Previous Registration → Server Message`.

## Notes

- On domain/Intune machines, always run `dsregcmd /status` first — it's the single richest diagnostic.
- `Set-Service NgcCtnrSvc -StartupType Automatic` will always fail with "Access is denied" — this is expected; the service is protected.
- After clearing the NGC folder, enrol PIN before fingerprint — biometrics won't register without a PIN anchor.
- A PIN expiration policy (`Expiration` value in PINComplexity) is normal corporate behaviour; it forces a reset every N days, not a bug.
- `dsregcmd /forcerecovery` must run as the regular user (not admin) — it operates on the user's work account token.
- `Disable-ScheduledTask` on `\Microsoft\Windows\Workplace Join\Automatic-Device-Join` will always fail — this task is TrustedInstaller-protected even from elevated admin.
