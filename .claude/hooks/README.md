# Hooks

Project-scoped Claude Code hooks, registered in [`../settings.json`](../settings.json). Both are written in **PowerShell 7 (`pwsh`)**, which is cross-platform, so a single committed config works on Windows, Linux, and macOS.

| Hook | Event | Matcher | What it does |
|---|---|---|---|
| [`guard-destructive.ps1`](guard-destructive.ps1) | `PreToolUse` | `Bash\|PowerShell` | Scans the proposed shell command for destructive-system-change patterns (HKLM/registry deletes, disabling Defender/UAC/SmartScreen/Windows Update, stopping services; `rm -rf` on system paths, `/etc` edits, `systemctl disable/mask`, firewall/SELinux changes, SIP/Gatekeeper/FileVault, `sudo`, disk/format ops). On a match it injects a reminder of the relevant CLAUDE.md rule. **Warn-only**: it never blocks and never auto-approves — the normal permission prompt still applies. |
| [`session-start.ps1`](session-start.ps1) | `SessionStart` | (all) | Injects an OS-filtered orientation: the tools available for the current OS (name + synopsis), and whether a `perf-capture` monitor is already running. Automates the "list tools at session start" step from CLAUDE.md. |

## Cross-OS note

The committed hook command is `pwsh -NoProfile -File "${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.ps1"`.

- **Windows** — works out of the box (`pwsh` present).
- **Linux / macOS** — install PowerShell once and the same scripts run unmodified:
  - macOS: `brew install --cask powershell` (see `macos-homebrew` skill)
  - Linux: distro package `powershell` / snap (see `linux-packages` skill)
  - If `pwsh` is absent, the hook simply fails non-blocking (a harmless warning) — it never stops the session.

## Safety

Both hooks are read-only, wrapped in try/catch, and always `exit 0`. They observe and remind; they never change the system or block a tool call. Editing behavior here changes what Claude is reminded of — keep them conservative.
