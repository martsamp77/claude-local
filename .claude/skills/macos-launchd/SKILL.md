---
name: macos-launchd
description: "[macos] Inspect and control launchd services — list/load/unload LaunchAgents and LaunchDaemons, write plist units, follow logs. Use for service-level admin on macOS (analog of windows-services and linux-systemd)."
---

# macos-launchd

Use this skill any time a task involves a long-running daemon or per-user agent on macOS. `launchd` is macOS's PID 1 — it manages everything from system services to per-user GUI helpers. Roughly:

| Concept | Linux equivalent | Windows equivalent |
|---|---|---|
| LaunchDaemon (`/Library/LaunchDaemons/`) | system systemd unit | Windows service |
| LaunchAgent (`~/Library/LaunchAgents/`) | user systemd unit (`~/.config/systemd/user/`) | logon scheduled task / user Run key |
| `launchctl` | `systemctl` | `Get-Service` / `Set-Service` |
| `log show --predicate ...` | `journalctl -u` | Event Viewer |

## The four locations

| Path | Scope | Runs as | When |
|---|---|---|---|
| `/System/Library/LaunchDaemons/` | system | root | Apple-shipped. **SIP-protected; do not edit.** |
| `/System/Library/LaunchAgents/` | system | logged-in user | Apple-shipped. **SIP-protected.** |
| `/Library/LaunchDaemons/` | system | root | Third-party / your additions, system-wide. |
| `/Library/LaunchAgents/` | system | logged-in user | Third-party, fires for any logged-in user. |
| `~/Library/LaunchAgents/` | user | this user only | Your per-user agents. |

The first two are Apple's; never touch. Editing the others requires deciding the right scope: per-user (no `sudo`) vs system-wide (`sudo`, plus explicit confirmation per CLAUDE.md).

## Inspect

```bash
launchctl list                                # everything launchd is tracking for this session
launchctl list | grep -v 'com.apple'          # third-party / user only
launchctl print gui/$UID                      # full domain status (modern syntax)
launchctl print system                        # system-wide domain
launchctl print system/com.example.myjob      # specific service detail
launchctl print-disabled system               # what's disabled
```

Three columns from `launchctl list`: PID (or `-` if not running), Status (last exit code or `-`), Label.

## Load / unload

Modern API (Big Sur+):

```bash
# User agent — no sudo
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.example.myjob.plist
launchctl bootout    gui/$UID/com.example.myjob

# System daemon — sudo
sudo launchctl bootstrap system /Library/LaunchDaemons/com.example.myjob.plist
sudo launchctl bootout    system/com.example.myjob

# Force-kick a one-shot run (regardless of triggers)
launchctl kickstart -k gui/$UID/com.example.myjob
sudo launchctl kickstart -k system/com.example.myjob
```

Older `launchctl load -w` / `launchctl unload -w` still works on most macOS versions but is deprecated; prefer `bootstrap`/`bootout` for new code.

## Enable / disable

```bash
launchctl enable  gui/$UID/com.example.myjob   # allow boot at next session
launchctl disable gui/$UID/com.example.myjob   # block from starting

sudo launchctl enable  system/com.example.myjob
sudo launchctl disable system/com.example.myjob
```

Enable/disable is independent of bootstrap/bootout. A disabled service won't start on next session even if the plist exists.

## Plist anatomy (a minimal LaunchAgent)

`~/Library/LaunchAgents/com.example.myjob.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.myjob</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/<user>/bin/myjob.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>3600</integer>          <!-- every hour -->
    <key>StandardOutPath</key>
    <string>/Users/<user>/Library/Logs/myjob.out</string>
    <key>StandardErrorPath</key>
    <string>/Users/<user>/Library/Logs/myjob.err</string>
</dict>
</plist>
```

Other useful keys:

- `KeepAlive` (boolean or dict) — restart on exit. Dict form: `{ SuccessfulExit = false; }` to restart only on failure.
- `StartCalendarInterval` (dict) — cron-like: `Hour = 3; Minute = 0;`.
- `WatchPaths` (array) — fire when paths change.
- `ThrottleInterval` (integer) — minimum seconds between starts (default 10).
- `WorkingDirectory`, `EnvironmentVariables` (dict).
- `Disabled` is honored only by older `load -w`; modern flow uses `enable`/`disable` instead.

After editing a plist, you must `bootout` and `bootstrap` again — launchd doesn't auto-reload.

## Logs

`launchd` itself logs to the unified system log:

```bash
log show --predicate 'subsystem == "com.apple.launchd"' --last 10m
log show --predicate 'process == "com.example.myjob"' --last 1h
log stream --predicate 'process == "com.example.myjob"'   # live tail
```

Plus whatever the service writes to `StandardOutPath` / `StandardErrorPath`.

## Critical services — DO NOT modify

These keep macOS itself functioning:

- Anything under `/System/Library/Launch*` (SIP-protected anyway)
- `com.apple.WindowServer`
- `com.apple.loginwindow`
- `com.apple.coreaudiod` (audio)
- `com.apple.cfprefsd` (preferences)
- `com.apple.notifyd` (notifications IPC)
- `com.apple.mDNSResponder` (DNS / Bonjour)
- `com.apple.cupsd` (printing)
- `com.apple.opendirectoryd` (directory services)

If you genuinely need to disable an Apple service, research the specific consequence first.

## Common patterns

**Stop something that keeps coming back:**

```bash
launchctl bootout    gui/$UID/com.example.thing
launchctl disable    gui/$UID/com.example.thing
# If it has a plist, move it out of the way:
mv ~/Library/LaunchAgents/com.example.thing.plist ~/Library/LaunchAgents/com.example.thing.plist.disabled
```

**See what auto-starts at login:**

```bash
ls -la ~/Library/LaunchAgents/ /Library/LaunchAgents/
# Plus System Settings > General > Login Items, which writes to its own plist
```

**Validate a plist before loading:**

```bash
plutil -lint ~/Library/LaunchAgents/com.example.myjob.plist
```

## Safety

- **System-wide plists in `/Library/LaunchDaemons/` need explicit confirmation.** Per CLAUDE.md, get a clear yes from the user before any write/delete here.
- **Backup before edits.** Copy the existing plist to `backups/macos/launchd/<ts>/` before modifying.
- **`bootout` doesn't delete the plist file** — it just unloads the running service. To make it permanent across reboots, delete or rename the plist too.
- **A plist in `~/Library/LaunchAgents/` whose `Label` doesn't match the filename basename will surprise you.** Match `com.example.myjob` label to `com.example.myjob.plist`.
- **Don't auto-elevate.** If a daemon edit needs `sudo`, print the command and let the user run it.
