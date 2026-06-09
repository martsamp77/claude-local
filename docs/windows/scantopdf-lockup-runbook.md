# ScanToPDF lockup — diagnosis & auto-recovery runbook

**Host:** `<SERVER>` (Windows Server 2019 VM) · **App:** ScanToPDF 6.5.0.12 (O Imaging Corp)
**Workflow:** a document-scanning billing pipeline — scanned PDFs are OCR'd, barcode-split, and filed.
**Last analyzed incident:** 2026-05-28 ~21:49 Central.

---

## TL;DR

ScanToPDF locks up because an **aged OCR engine crashes on large batches** and the **32-bit UI hangs waiting on it**, and
because the **batch size is uncapped** and a **stuck oversized PDF gets retried forever**. The fix is three parts, all reversible:

1. **`scantopdf-watchdog.ps1`** — a SYSTEM scheduled task (every 3 min) that auto-restarts the stopped service, kills a hung UI
   and orphaned OCR engines, quarantines the poison file, and alerts to Teams + the event log.
2. **Batch cap** — set `maxBatchCount` from `-1` (unlimited) to **150**.
3. **Poison-file quarantine** — oversized stuck PDFs are moved out of the hot folder so they stop causing repeat lockups.

Install: run `tools\windows\monitoring\install-scantopdf-watchdog.ps1` from an **elevated** PowerShell (preview first with `-DryRun`).

---

## Root cause (evidence)

**The components:**
- `ScanToPDFService.exe` — Windows service, `LocalSystem`, 64-bit, session 0. Runs **AutoFileImport**: watches the hot folder
  `E:\ScanToPDF\Hot Folder`, imports each PDF, OCRs + barcode-splits it,
  saves the pieces to `…\Scan to PDF reconcilliation\`, then deletes the source (`DeleteFilesFromSourceFolder="True"`).
- `ScanToPDF.exe` — interactive UI, runs as `<DOMAIN>\<scan-operator>` on the console (session 1), **32-bit** (~2–4 GB ceiling). TWAIN
  scanning from the Fujitsu fi-6130.
- `TOCRRService.exe` — **Transym OCR engine v5.1.0.100** (engine files dated 2015–2020). Spawned as a child process by both of
  the above; instances accumulate.

**The chain:**
1. Every few days an end-of-day **25–35 MB / 250–500-page PDF** enters the workflow. Confirmed in the dispatch log
   (`C:\ProgramData\OIC\ScanToPDF_6\Logs\ScanToPDFDispLog.txt`): 5/28 = 31.8 MB import + "259 pages captured"; 5/25 = "278 pages
   captured"; 5/22 = 32.8 MB.
2. The Transym OCR engine **access-violates (`0xc0000005`) inside `TOCRRService.exe`** grinding through the batch. The Windows
   **Application** log shows **38 such crashes since 2024**, clustered in evening heavy-batch windows (e.g. 4/27 ×5, 5/18 ×4,
   5/22, and 5/28 at 7:16 / 9:08 / 9:20 PM).
3. ScanToPDF blocks on the dead/incomplete OCR work; the 32-bit UI exhausts memory and **stops pumping its message loop** →
   **Application Hang, Event ID 1002** — *"ScanToPDF.exe version 6.5.0.12 stopped interacting with Windows and was closed"* at
   **2026-05-28 21:48:58**. It was relaunched manually 30 s later.
4. Because the import never finished, AutoFileImport **never deleted the source PDF**, so it was **retried on every restart** — a
   *poison-file loop*. The 21:00 log shows the service stop/start-ing three times that evening, each re-importing the **same
   31.8 MB file**. (A 5/18 file was still failing on 5/22.) That's why a single restart sometimes isn't enough.

**Why nothing auto-recovered:** the service has a failure action wired to `C:\Scripts\Alerting-WindowsService.ps1` (Teams + the
`ScanToPDF Alerting` event log), but **a hang is not a service failure**, so the SCM action never fired — and its companion
restart task (`C:\Scripts\Start-Service.xml`) was never imported.

**Key settings found:**

| Setting | File | Value | Meaning |
|---|---|---|---|
| `maxBatchCount` | `OptionsConfig.xml`, `ServiceOptionsConfig.xml` | **`-1`** | Unlimited batch — the runaway enabler |
| OCR `active` / `maxTimeToOCROnePage` | `Plugins\OCRRecognition\Default.xml` | `True` / `60` | OCR every page, 60 s/page timeout |
| AutoFileImport source | `Plugins\AutoFileImport\Default.xml` | the E: hot folder | + `DeleteFilesFromSourceFolder=True` |

---

## The fix

### 1. Watchdog — `tools/windows/monitoring/scantopdf-watchdog.ps1`
Runs as **SYSTEM every 3 minutes**. Each run:

| Check | Action | Alert |
|---|---|---|
| Service not Running (incl. wedged `StopPending`/`StartPending`/`Paused`) | `Start-Service`; if wedged, first `Stop-Service -Force` + kill the backing process and its hung `TOCRRService.exe` children, then start (flap guard: ≤ 3 / 30 min, else escalate & stop) | Teams + event 1001/1010 |
| UI not responding (confirmed after ~20 s) | `Stop-Process -Force` (operator reopens the UI; service keeps running) | Teams + event 1011 |
| UI working set ≥ 1500 MB | warn (approaching 32-bit ceiling) | Teams |
| Orphaned `TOCRRService.exe` (parent gone) | kill | Teams |
| ≥ 2 OCR crashes in 15 min | early-warning only | Teams + event 1012 |
| Oversized PDF stuck in hot folder | move to quarantine | Teams + event 1013 |

- **Wedged service:** a service stuck in `StopPending` (the hung-OCR lockup — the SCM is waiting on a stop that the dead/hung
  OCR child blocks) can't be revived by `Start-Service` alone. The watchdog force-stops it, kills the wedged backing process
  and its `TOCRRService.exe` children, then starts it; this counts against the flap guard like any other restart.
- **Poison-file rule:** a hot-folder PDF ≥ `QuarantineSizeMB` (default 20) is moved to the quarantine folder only when it has
  persisted ≥ 3 cycles **with correlated instability**, or has sat there ≥ 30 min — so a file that's merely processing normally
  is never yanked.
- **State** (flap history, poison-file persistence) lives in `C:\ProgramData\ScanToPDF-Watchdog\state.json`; a durable log is at
  `C:\ProgramData\ScanToPDF-Watchdog\watchdog.log`. With `-SaveLog`, each run also writes
  `logs\windows\monitoring\<ts>-scantopdf-watchdog.txt` in the repo.
- **`-DryRun`** does full detection + logging but changes nothing — safe to run unelevated.
- Alerts go to a **Teams webhook** (the URL is **not** stored in source — the watchdog reads it from
  `C:\ProgramData\ScanToPDF-Watchdog\webhook.url`, else `$env:SCANTOPDF_WEBHOOK_URL`, else an explicit `-WebhookUrl`; absent all
  three, Teams is skipped) and the registered **`ScanToPDF Alerting`** event log. Suppress everything with `-NoAlert`.

### 2. Batch cap — applied by the installer
Sets `maxBatchCount="150"` in `OptionsConfig.xml` and `ServiceOptionsConfig.xml`. Because the app rewrites these on exit, the
installer backs them up, stops the service + UI, edits, then restarts the service, and verifies the value stuck. Tune with
`-BatchCap`.

### 3. Quarantine
The watchdog moves stuck oversized PDFs to `E:\ScanToPDF\Scan2PDF_Quarantine`. A human splits the file into
smaller batches and re-drops it into the hot folder.

---

## Install / test / uninstall

All from an **elevated** PowerShell (the installer refuses to run unelevated). Preview everything with `-DryRun` first.

```powershell
# 1. Preview (safe, unelevated OK)
pwsh -File ".\tools\windows\monitoring\install-scantopdf-watchdog.ps1" -DryRun

# 2. Install (elevated) — registers the task + applies the 150 cap (briefly stops the service & UI)
#    Pass -WebhookUrl once to provision Teams alerts (written to ProgramData, never into the repo).
pwsh -File ".\tools\windows\monitoring\install-scantopdf-watchdog.ps1" -WebhookUrl "<teams-incoming-webhook-url>"

#    Variations:
#    -BatchCap 200        use a different cap
#    -SkipConfigCap       register the watchdog only, leave maxBatchCount alone
#    -SkipTask            apply the cap only
#    (omit -WebhookUrl    keep any existing webhook.url; Teams skipped if none — event-log alerting still fires)

# 3. Verify the watchdog logic against current state (safe)
pwsh -File ".\tools\windows\monitoring\scantopdf-watchdog.ps1" -DryRun -SaveLog

# 4. Live self-heal test
Stop-Service ScanToPDFService        # within 3 min the task restarts it and posts a Teams alert
Get-Content "$env:ProgramData\ScanToPDF-Watchdog\watchdog.log" -Tail 40
Get-ScheduledTask -TaskName 'ScanToPDF Watchdog' -TaskPath '\ScanToPDF\' | Get-ScheduledTaskInfo

# Uninstall
pwsh -File ".\tools\windows\monitoring\install-scantopdf-watchdog.ps1" -Uninstall                 # remove task, keep cap
pwsh -File ".\tools\windows\monitoring\install-scantopdf-watchdog.ps1" -Uninstall -RestoreConfig   # also revert maxBatchCount
```

Config backups are written to `backups\windows\scantopdf\<timestamp>\` (gitignored).

> **Note on profiles:** the cap is written to the two main config files (current profile). The active service profile may be a
> site-specific named profile and the UI profile is typically `Default`; per-profile copies can live in the SettingsVault. The installer re-reads and reports whether
> the value stuck — if it didn't, set the cap inside the relevant profile via the ScanToPDF UI (Options → Scan → max batch).

---

## Manual recovery (when it's locked up right now)

1. `Stop-Service ScanToPDFService -Force`
2. Kill the wedged processes: `Get-Process ScanToPDF,ScanToPDFB10,ScanToPDFx64,TOCRRService -EA SilentlyContinue | Stop-Process -Force`
3. **Check the hot folder** `E:\ScanToPDF\Hot Folder` for a large (>20 MB) PDF. If present, **move it out**
   (to `Scan2PDF_Quarantine`) so it stops re-triggering. Split it and re-drop it later.
4. `Start-Service ScanToPDFService`
5. If an operator was scanning, have them reopen the ScanToPDF window.

Once the watchdog is installed, steps 1–4 happen automatically within ~3 minutes.

---

## Follow-ups (recommended, out of scope here)

- **Real cure = the OCR engine.** The `0xc0000005` is *inside* Transym TOCR 5.1 (2015–2020). Engage scantopdf.com support to
  update the OCR plugin/engine — the watchdog mitigates, it doesn't fix the crash.
- **Interactive memory ceiling.** The UI runs 32-bit `ScanToPDF.exe`; launching via `ScanToPDFx64.exe` (64-bit, already present)
  raises the address ceiling for big interactive scans. Check which exe the desktop shortcut / autostart uses.
- **Security.** `C:\Scripts\Alerting-WindowsService.ps1` contains a **hardcoded plaintext SMTP password** — rotate it and move to
  a secure store (the box already has `Create-SecureStringXml.ps1` / Graph token helpers).
- **RAM headroom.** Server RAM is shared with various monitoring / security / RMM agents. More RAM eases the
  large-batch memory pressure.
