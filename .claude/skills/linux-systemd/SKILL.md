---
name: linux-systemd
description: "[linux] Inspect and control systemd units — query status, start/stop/restart, enable/disable, follow journal. Use for service-level admin on systemd-based distros (Ubuntu, Debian, Fedora, RHEL, Arch, openSUSE)."
---

# linux-systemd

Use this skill any time a task involves a Linux service/daemon on a systemd-based distro (≈99% of mainstream desktop/server distros today). Equivalent in scope to the `windows-services` skill, with `journalctl` filling the role of the Windows event log.

For non-systemd init systems (Alpine/OpenRC, Devuan/sysvinit, runit) — different commands; this skill doesn't cover them.

## Inspect

```bash
systemctl status <unit>                  # snapshot: state, recent log lines, PID
systemctl list-units --type=service      # all loaded services
systemctl list-units --type=service --state=failed   # what's broken
systemctl list-unit-files --state=enabled            # what auto-starts
systemctl is-active <unit>               # exits 0 if running
systemctl is-enabled <unit>              # exits 0 if enabled at boot
systemctl cat <unit>                     # show the unit file (resolved with drop-ins)
systemctl show <unit> -p MainPID,Restart,MemoryCurrent  # specific properties
```

User units (per-user services under `~/.config/systemd/user/`) — append `--user`:

```bash
systemctl --user status <unit>
systemctl --user list-units
```

## Control

```bash
sudo systemctl start    <unit>
sudo systemctl stop     <unit>
sudo systemctl restart  <unit>
sudo systemctl reload   <unit>     # SIGHUP-style reload, only if unit supports it
sudo systemctl kill     <unit>     # SIGTERM by default; -s SIGKILL for last resort
```

User units skip `sudo` and use `--user`.

## Enable / disable for boot

```bash
sudo systemctl enable  <unit>            # start at boot
sudo systemctl enable  --now <unit>      # AND start it now
sudo systemctl disable <unit>            # don't start at boot (still leaves running)
sudo systemctl disable --now <unit>      # AND stop it now
sudo systemctl mask    <unit>            # disable AND prevent any future start
sudo systemctl unmask  <unit>            # undo mask
```

`mask` is the strongest off-switch — even `start` fails afterward. Use when something keeps re-enabling itself.

## Logs (journalctl)

```bash
journalctl -u <unit>                     # all logs for that unit
journalctl -u <unit> -f                  # follow live
journalctl -u <unit> -n 100              # last 100 lines
journalctl -u <unit> --since '1 hour ago'
journalctl -u <unit> -b                  # since current boot
journalctl -u <unit> -b -1               # previous boot
journalctl -p err -b                     # all errors this boot, system-wide
journalctl --disk-usage                  # how much journal space is used
```

Vacuum journal if disk is filling:

```bash
sudo journalctl --vacuum-time=7d         # keep last 7 days
sudo journalctl --vacuum-size=500M       # cap to 500 MB
```

## Critical units — DO NOT disable

These keep the system functional. Disabling them is a remote-recovery scenario.

- `systemd` itself (PID 1)
- `systemd-journald` — system logging
- `systemd-logind` — session management
- `systemd-udevd` — device events
- `systemd-resolved` (if enabled) — DNS resolution
- `dbus` / `dbus-broker` — IPC
- `NetworkManager` (or `systemd-networkd`, depending on distro) — networking
- `sshd` — your remote access; never disable on a remote box without console access
- `polkit` — privilege escalation prompts
- `cron` / `cronie` — scheduled jobs (if you use cron rather than timers)

## Common patterns

**Stop a service that keeps coming back:**

```bash
sudo systemctl disable --now <unit>
sudo systemctl mask <unit>               # only if it's still being pulled by another unit
```

**Convert a long-running script into a user service** (no sudo needed):

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/myjob.service <<'EOF'
[Unit]
Description=My job

[Service]
ExecStart=/home/<user>/bin/my-job.sh
Restart=on-failure

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now myjob.service
loginctl enable-linger $USER             # so it runs even when not logged in
```

**Timers (cron replacement):**

```bash
# ~/.config/systemd/user/myjob.timer
[Unit]
Description=Run myjob daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl --user enable --now myjob.timer
systemctl --user list-timers             # see next run for all timers
```

## Safety

- **`stop` vs `disable`:** `stop` is now-only; service comes back at next boot. `disable` is boot-only; service stays running. Use `disable --now` together for "off now and stays off".
- **System units → `sudo`. User units → `--user`, no sudo.** Mixing them up either hits a permissions error or quietly does nothing.
- **Don't edit `/usr/lib/systemd/system/*.service` directly** — package upgrades will overwrite it. Use `systemctl edit <unit>` to create a drop-in under `/etc/systemd/system/<unit>.d/override.conf`.
- **Always `daemon-reload` after editing a unit file.** `systemctl edit` does this for you; manual edits don't.
- **Never `mask` `dbus`, `systemd-logind`, or `NetworkManager`** without a recovery plan.

## Backup before edits

When editing `/etc/systemd/system/*.service` (or creating a drop-in), copy the file first to `backups/linux/etc/<timestamp>/` per CLAUDE.md.
