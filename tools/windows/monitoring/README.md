# ScanToPDF watchdog — `tools/windows/monitoring/`

Self-healing auto-recovery for **ScanToPDF** (O Imaging Corp) on a Windows scan/billing server.
ScanToPDF periodically **locks up**: a large end-of-day batch drives its aged Transym OCR engine
(`TOCRRService.exe`) to access-violate, the 32-bit UI stops responding, and the unconsumed source
PDF is retried on every restart. This watchdog detects and recovers from all of that on a timer.

> 📖 **Full diagnosis, evidence, and the manual recovery runbook:**
> [`docs/windows/scantopdf-lockup-runbook.md`](../../../docs/windows/scantopdf-lockup-runbook.md)
> 🧰 **All repo tools:** [root README → Tools](../../../README.md#tools)

## Scripts

| Script | Role |
|---|---|
| [`scantopdf-watchdog.ps1`](scantopdf-watchdog.ps1) | The watchdog. Runs as **SYSTEM** on a schedule (default every 3 min); restarts the stopped service, kills a hung UI / orphaned `TOCRRService.exe`, quarantines oversized "poison" PDFs, and alerts. |
| [`install-scantopdf-watchdog.ps1`](install-scantopdf-watchdog.ps1) | One-time **elevated** installer / uninstaller. Registers the scheduled task, ensures the event-log source, provisions the Teams webhook (kept out of source control), and caps `maxBatchCount`. |

## What the watchdog does each run

| Check | Action | Alert (event ID) |
|---|---|---|
| Service not Running | `Start-Service` (flap guard: ≤ `MaxRestartsPerWindow` per window, else escalate & stop) | Teams + 1001 / 1010 |
| UI not responding (re-confirmed after `HangConfirmSeconds`) | `Stop-Process -Force` (an operator reopens the UI; the service keeps running) | Teams + 1011 |
| UI working set ≥ `UiMemoryWarnMB` | warn — approaching the 32-bit memory ceiling | Teams |
| Orphaned `TOCRRService.exe` (parent gone) | kill | Teams |
| ≥ `OcrCrashAlertCount` OCR crashes in `OcrCrashWindowMinutes` | early-warning only (root-cause signal) | Teams + 1012 |
| Oversized PDF stuck in the hot folder | move to the quarantine folder | Teams + 1013 |

The **poison-file rule** only quarantines a PDF ≥ `QuarantineSizeMB` once it has persisted
`QuarantinePersistCycles` cycles *with correlated instability*, or has sat there `QuarantineHardAgeMinutes` —
so a file that is merely processing normally is never yanked.

## Quick start

Run from the repo root. Preview everything first — `-DryRun` changes nothing and is safe to run unelevated.

```powershell
# 1. See what the watchdog would do against the current machine state
.\tools\windows\monitoring\scantopdf-watchdog.ps1 -DryRun -SaveLog

# 2. Preview the install (task + maxBatchCount cap)
.\tools\windows\monitoring\install-scantopdf-watchdog.ps1 -DryRun

# 3. Install (ELEVATED). Pass -WebhookUrl once to enable Teams alerts; it is written to
#    %ProgramData%\ScanToPDF-Watchdog\webhook.url and never stored in the repo.
.\tools\windows\monitoring\install-scantopdf-watchdog.ps1 -WebhookUrl "https://<your-teams-webhook>"
#    -BatchCap 150        cap unlimited batches (default 150)
#    -SkipConfigCap       register the watchdog only, leave maxBatchCount alone
#    -SkipTask            apply the cap only
#    -HotFolder is set on the watchdog, not the installer — see Configuration

# 4. Live self-heal test
Stop-Service ScanToPDFService     # the task restarts it within one interval + alerts
Get-Content "$env:ProgramData\ScanToPDF-Watchdog\watchdog.log" -Tail 40

# Uninstall
.\tools\windows\monitoring\install-scantopdf-watchdog.ps1 -Uninstall                # remove task, keep cap
.\tools\windows\monitoring\install-scantopdf-watchdog.ps1 -Uninstall -RestoreConfig  # also revert maxBatchCount
```

## Configuration

- **Hot folder:** the watchdog defaults to `E:\ScanToPDF\Hot Folder`. Point it at your site's
  AutoFileImport source with `-HotFolder '<path>'` (quarantine defaults to a `Scan2PDF_Quarantine`
  sibling, override with `-QuarantineFolder`).
- **Teams webhook (secret):** never lives in source. Resolved at runtime in this order —
  `-WebhookUrl` → `%ProgramData%\ScanToPDF-Watchdog\webhook.url` → `$env:SCANTOPDF_WEBHOOK_URL` → none
  (Teams skipped; event-log + local-log alerting still fire). The installer writes `webhook.url` when
  you pass `-WebhookUrl`.
- **Event log:** writes to the `ScanToPDF Alerting` log (source `ScanToPDF Alerting Script`); the
  installer creates the source if missing.
- **State + durable log:** `%ProgramData%\ScanToPDF-Watchdog\` (`state.json`, `watchdog.log`). With
  `-SaveLog`, each run also drops a report in `logs\windows\monitoring\` (git-ignored).
- **Other knobs:** `-QuarantineSizeMB` (20), `-MaxRestartsPerWindow` (3) / `-RestartWindowMinutes` (30),
  `-HangConfirmSeconds` (20), `-UiMemoryWarnMB` (1500), `-NoAlert`.

## Safety notes

- `-DryRun` is fully side-effect-free (no kills, restarts, moves, config writes, or state files).
- The scheduled task runs under **Windows PowerShell 5.1**; both scripts are ASCII-only and parse
  clean there. The task trigger uses a daily + 24 h-repetition pattern (not `[TimeSpan]::MaxValue`,
  which Task Scheduler rejects as out of range).
- The installer **stops the service and the interactive UI** while it edits `maxBatchCount` (the app
  rewrites its config on exit), backs the config up to `backups\windows\scantopdf\<timestamp>\`, then
  restarts the service. Run it off-hours.
- The watchdog mitigates the lockups; the lasting fix is updating the OCR engine — see the runbook.
