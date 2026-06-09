# ScanToPDF status dashboard — guide

A **read-only** status board for the ScanToPDF scanning system on `MD-FS01`. It answers, at a glance:
*is scanning working, what just processed, is anything stuck, and is the watchdog healthy?* — for three
audiences at once.

- **Tool:** `tools/windows/monitoring/scantopdf-dashboard.ps1`
- **Installer:** `tools/windows/monitoring/install-scantopdf-dashboard.ps1`
- **Companion of:** the watchdog (`scantopdf-watchdog.ps1`) — see [`scantopdf-lockup-runbook.md`](scantopdf-lockup-runbook.md).

## What it shows

| Section | For | Content |
|---|---|---|
| **Traffic-light banner** | everyone | GREEN / amber / red + one plain-English line ("Scanning is running normally", "…recovered after a hiccup", "DOWN — auto-recovery in progress"). Plus an **action-needed** callout if a hung scan window was auto-closed. |
| **At a glance** | scan operators | Service up/down, documents waiting to process (+ oldest age), last document processed, pages needing a human (errors folder). |
| **Administration** | admins | Service state/PID/RAM, watchdog task (last run/result/next/restarts 30m+24h), OCR (workers, on/off, crashes 24h/7d/30d, hangs), capacity (disk C:/E:, batch cap, import interval). |
| **Troubleshooting** | troubleshooters | Recent watchdog actions, and a newest-first activity feed parsed from the dispatch log (imports, page counts, saves to reconciliation vs errors, service start/stop). |

**Data sources** (all read by the SYSTEM task): the ScanToPDF dispatch log, the service + the watchdog's
scheduled task / `state.json` / `watchdog.log`, the `ScanToPDF Alerting` + Windows `Application` event
logs, the watched source + errors folders, the config XMLs, and live process info.

## How it works

- **`-Serve`** (what the installed task runs): a tiny built-in `HttpListener` web server on `-Port`
  (default **8088**). Routes: `/` (HTML), `/status.json` (machine-readable), `/healthz` (`ok`). The page
  auto-refreshes every ~15 s. Collection is cached ~15 s; the expensive 30-day event-log scans are cached
  ~2 min, so page hits stay cheap. The same process rewrites the static snapshot every ~30–60 s.
- **`-Once`**: collect once, write `status.html` + `status.json`, exit. Used for testing and as a
  no-server fallback.
- **Snapshot** is always written to `%ProgramData%\ScanToPDF-Dashboard\` and, if `-SharePath` is given,
  to that share too — so a self-contained `status.html` is viewable even if the web server is down.

## Access & security

- **Subnet-scoped, no auth.** The installer opens an inbound firewall rule **`ScanToPDF Dashboard`**
  limited to the `-Subnet` you provide (e.g. `10.0.0.0/24`). `-Subnet` is **required** — the installer
  refuses to open the port network-wide.
- **PII-safe by default.** The dashboard shows counts, sizes, page counts, timestamps and status —
  **not** scanned-document filenames or paths. Add `-ShowFilenames` only if you accept exposing them
  (for on-box troubleshooting). The dispatch log here references a billing-lab share, so default to hidden.
- **Read-only.** No control endpoints; the server never changes ScanToPDF, the service, or any task.
- It runs as **SYSTEM** under **PowerShell 7 (`pwsh`)**; a URL ACL reservation lets it bind the port. (If `pwsh` is absent the installer falls back to Windows PowerShell 5.1, where the HTML dashboard still works but the `/status.json` endpoint + snapshot JSON are unavailable — a 5.1 `ConvertTo-Json` limitation.)

## Install

From an **elevated** PowerShell, at the repo root. Preview first.

```powershell
# 0. (safe) test the snapshot locally — no server, no changes
.\tools\windows\monitoring\scantopdf-dashboard.ps1 -Once
start "$env:ProgramData\ScanToPDF-Dashboard\status.html"

# 1. preview the install
.\tools\windows\monitoring\install-scantopdf-dashboard.ps1 -DryRun -Subnet 10.0.0.0/24

# 2. install (ELEVATED). -Subnet REQUIRED; -Port default 8088; -SharePath optional
.\tools\windows\monitoring\install-scantopdf-dashboard.ps1 -Subnet 10.0.0.0/24 -Port 8088 `
    -SharePath "\\MD-FS01\ScanToPDF-Status"
#   -ShowFilenames   reveal document filenames (PII) — off by default
```

Then browse **`http://MD-FS01:8088/`** from a machine in that subnet (or `http://<server-ip>:8088/`).

The installer (1) reserves the URL ACL, (2) creates the subnet-scoped firewall rule, and (3) registers
+ starts the SYSTEM task **`\ScanToPDF\ScanToPDF Dashboard`** (triggered at startup, **no execution time
limit**, auto-restart on failure). It survives reboots and restarts itself if the process dies.

## Verify

```powershell
Get-ScheduledTask -TaskName 'ScanToPDF Dashboard' -TaskPath '\ScanToPDF\' | Get-ScheduledTaskInfo
Invoke-WebRequest http://localhost:8088/healthz -UseBasicParsing   # -> 'ok' (allow ~10s after start to warm)
```

> **Cold start:** the first request after the task starts can take ~10 s while the initial event-log scan
> runs (the server is single-threaded). It's warm long before anyone connects; subsequent hits are instant.

## Change the subnet / port, or uninstall

```powershell
# change subnet or port: just re-run the installer (it replaces the rule + task)
.\tools\windows\monitoring\install-scantopdf-dashboard.ps1 -Subnet 10.0.5.0/24 -Port 8090

# uninstall: removes the task, the firewall rule, and the URL ACL
.\tools\windows\monitoring\install-scantopdf-dashboard.ps1 -Uninstall
```

## Troubleshooting

- **Page won't load from another PC:** confirm the client is inside `-Subnet`; check the rule with
  `Get-NetFirewallRule -DisplayName 'ScanToPDF Dashboard' | Get-NetFirewallAddressFilter`.
- **`HTTP 503`/bind error in `server.log`:** another process holds the port, or the URL ACL is missing —
  re-run the installer (it reserves the ACL) or pick another `-Port`.
- **Server log:** `%ProgramData%\ScanToPDF-Dashboard\server.log`. **Snapshot:** `…\status.html`.
- **Is it running?** `Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | ? CommandLine -like '*scantopdf-dashboard*'`.
