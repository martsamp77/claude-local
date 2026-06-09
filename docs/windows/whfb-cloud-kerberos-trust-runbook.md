# Windows Hello fails on hybrid-joined PC — key trust without PKI, fixed via cloud Kerberos trust

## Symptoms

- After every reboot, only **password** sign-in works.
- PIN fails at the lock screen: *"Something went wrong and your PIN isn't available
  (status: 0xc00000bb, substatus: 0x0)"*. Re-enrolling the PIN "succeeds" but the
  next sign-in fails the same way.
- Fingerprint fails: *"Your credentials couldn't be verified. (code: 0xc000005f, 0x0)"*.
- The machine does **not** appear at `myaccount.microsoft.com/device-list`, while
  other (working) machines do.

## Root cause

The machine is **hybrid-joined** (`dsregcmd /status`: `DomainJoined: YES` **and**
`AzureAdJoined: YES`). On a hybrid machine, a Hello gesture (PIN/fingerprint) must
authenticate to an **on-prem domain controller**, not just Entra ID. There are three
ways that can work — certificate trust, key trust, cloud Kerberos trust — and the
machine defaulted to **key trust**, which has a hard prerequisite the environment
didn't meet:

- Key trust needs every DC to hold a **Kerberos Authentication (PKINIT) certificate**
  issued by an enterprise CA in the forest.
- If the domain has **no AD CS / enterprise PKI** (empty NTAuth store, no
  `pKIEnrollmentService` objects in the Configuration partition), PKINIT is
  impossible and every key-trust sign-in fails with **0xC00000BB**
  (STATUS_NOT_SUPPORTED).

Enrollment still "works" because it only talks to Entra ID — the public key even
syncs back to the AD user object (`msDS-KeyCredentialLink` accumulates one entry
per re-enrollment). Sign-in then fails locally, every time. Classic
*"enrollment succeeds, logon never works"* deployment gap.

### Why a sibling Entra-joined machine works fine

An Entra-joined (cloud-only) machine validates the PIN purely against Entra ID — no
DC involved. Entra-joined devices also record the signing-in user as *registered
owner*, which is why they appear at `myaccount.microsoft.com/device-list`.
Hybrid-joined devices have no owner, so their absence from that page is **expected**
— it's a clue about the join type, not a fault. Check Entra admin portal → Devices
for the hybrid object instead.

## Diagnosis trail (read-only, regular user)

```powershell
dsregcmd /status
# Key fields: DomainJoined + AzureAdJoined both YES (hybrid), NgcSet YES,
#             AzureAdPrt YES, but SSO State -> OnPremTgt: NO

Get-WinEvent -LogName "Microsoft-Windows-HelloForBusiness/Operational" -MaxEvents 40
# Event 7001: Deployment Type: Key Trust, Authentication Error Status: 0xC00000BB
# Event 5205: Use Cloud Trust for On-Premise Auth: false / Account has Cloud TGT: false

# Is key trust even possible? (enterprise PKI present?)
certutil -store -enterprise NTAuth          # empty => no enterprise CA trusted
([adsisearcher]"(objectClass=pKIEnrollmentService)").FindAll()   # none => no AD CS

# Is the user's Hello key syncing to AD? (rules out the Entra-Connect-sync cause)
$s=[adsisearcher]"(&(objectCategory=person)(sAMAccountName=<user>))"
$s.PropertiesToLoad.Add('msds-keycredentiallink')|Out-Null
$s.FindOne().Properties['msds-keycredentiallink'].Count   # >0 => sync OK

# Cloud Kerberos trust prerequisites
nltest /dsgetdc:<domain> /keylist /kdc      # KEYLIST flag => DC supports it (2016+)
([adsisearcher]"(&(objectClass=computer)(name=AzureADKerberos))").FindOne()
# null => cloud Kerberos trust NOT deployed yet
```

Decision: with no PKI and 2016+ DCs, **cloud Kerberos trust** is the right fix
(Microsoft's recommended hybrid deployment; no certificates needed).

## Fix

### 1. Server side (once per forest/domain) — Domain Admin + Entra Hybrid Identity/Global Admin

```powershell
.\tools\windows\identity\setup-whfb-cloud-kerberos-trust.ps1 `
    -Domain <ad-dns-domain> -UserPrincipalName <entra-admin-upn>
```

Creates the `AzureADKerberos` computer object + disabled `krbtgt_AzureAD` account
in AD and registers the trust in the tenant, letting Entra ID issue **partial TGTs**
for the on-prem domain. Idempotent. Inverse: `Remove-AzureADKerberosServer`.

Operational note: the `krbtgt_AzureAD` key should be rotated periodically (e.g.
every few months): `Set-AzureADKerberosServer ... -RotateServerKey`.

### 2. Client side (pilot machine, elevated)

```powershell
.\tools\windows\identity\enable-whfb-cloud-trust-client.ps1        # -Undo reverts
```

Backs up then sets `HKLM\SOFTWARE\Policies\Microsoft\PassportForWork\UseCloudTrustForOnPremAuth = 1`
(registry equivalent of the GPO/Intune setting *Use cloud Kerberos trust for
on-premises authentication*) and starts `WbioSrvc` if stopped.

### 3. Activate + verify on the client

1. Reboot; sign in once with the **password**.
2. Lock → unlock with the **PIN**.
3. Verify:
   - `dsregcmd /status` → SSO State → **`OnPremTgt: YES`**
   - HelloForBusiness event **5205** → `Use Cloud Trust for On-Premise Auth: true`,
     `Account has Cloud TGT: true`
   - No new event **7001** with 0xC00000BB.
4. Full reboot → PIN at first sign-in (the original failing case).
5. If fingerprint still errors after the PIN works, re-enrol it
   (Settings → Sign-in options); biometrics hang off the PIN-anchored container.

### 4. Roll out

Once the pilot passes, deliver the same setting fleet-wide via GPO
(*Computer Configuration → Administrative Templates → Windows Components →
Windows Hello for Business → Use cloud Kerberos trust for on-premises
authentication = Enabled*) or Intune Settings Catalog, and remove the local
registry pilot value (`-Undo`) so policy is the single source of truth.

Optional cleanup: prune stale `msDS-KeyCredentialLink` entries on user objects
(one accumulates per failed re-enrollment attempt; keep the newest).

## Gotchas

- **0xC00000BB ≠ broken device registration.** `dsregcmd` can show a perfectly
  healthy device (DeviceAuthStatus SUCCESS, valid PRT) while every Hello sign-in
  fails — the break is in the *on-prem authentication leg*, not the join.
- The `KEYLIST` flag from `nltest /keylist` means the DC *can* serve key-list
  requests (OS capability, 2016+), **not** that cloud Kerberos trust is deployed.
  The `AzureADKerberos` object is what proves deployment.
- Cloud Kerberos trust requires the client to have **line of sight to a DC** at
  first sign-in after a password change, and the user must sign in with a password
  once after the policy lands before the PIN starts working.
- `certutil -dcinfo` needs admin rights on the DCs; from a regular workstation use
  the NTAuth-store + `pKIEnrollmentService` checks above to establish "no PKI".
