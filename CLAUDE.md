# claude-local — Windows 11 management workspace

This directory is Marty's home base for Windows 11 administration tasks. When he asks Claude Code to change a system setting, edit the registry, manage software, tweak the environment, or set up dev tooling, work happens here.

This is not a code project. There's no app to build, no tests to run. Tasks are sysadmin-flavored: *change something on this machine safely*.

## Platform

- Windows 11 Pro, single-user (Marty).
- PowerShell 7+ (`pwsh`) is available — that's the primary tool for Windows-native operations. Use the `PowerShell` tool.
- Bash is also configured (Git for Windows). Use the `Bash` tool for cross-platform/file operations.

**Convention:** prefer PowerShell for anything Windows-system-specific (registry, services, winget, scheduled tasks, env vars, system settings). Use bash for general file ops, scripting that needs to be portable, or git work. Don't shell out to `cmd.exe` unless a tool genuinely requires it.

## Safety conventions

These apply to every session. They are non-negotiable unless Marty explicitly waives one in the conversation.

- **Confirm before destructive system changes.** Stopping critical services, deleting registry keys, uninstalling packages, removing scheduled tasks — pause and confirm.
- **Back up the registry before edits.** Use `reg export <key> <path>.reg` before any `Set-ItemProperty` / `New-Item` / `Remove-Item` against the registry. Save backups to `C:\DATA\Workspace-37m\claude-local\backups\registry\` (create dir if needed) with a timestamped filename.
- **HKLM requires explicit confirmation.** `HKCU` changes affect only this user and are reversible — proceed with normal care. `HKLM` (machine-wide) changes need a clear "yes go ahead" from Marty before each write.
- **Never disable UAC, Defender, SmartScreen, or Windows Update** without an explicit instruction naming the thing to disable.
- **Prefer reversible changes.** A registry tweak that can be flipped back beats a uninstall that has to be reinstalled. Note the inverse operation when you make a change.
- **Don't auto-elevate.** If something needs admin (`HKLM`, system services, machine env vars), say so and let Marty re-launch the shell elevated rather than chaining `Start-Process -Verb RunAs`.

## Where things live

- **Skills** — `C:\DATA\Workspace-37m\claude-local\.claude\skills\<name>\SKILL.md`. Each skill is one folder with a `SKILL.md` containing YAML frontmatter (`name`, `description`) and a tight body. Read them when the matching topic comes up.
- **Persistent memory** — `C:\Users\marty\.claude\projects\C--DATA-Workspace-37m-claude-local\memory\`. Auto-managed; this is where user/feedback/project/reference memories live.
- **Reference library** — `C:\DATA\Workspace-public\everything-claude-code` is a sprawling blueprint repo with 300+ skills, 50+ agents, 80+ commands. Treat it as a library to browse when a need actually appears — don't auto-pull from it.

## Adding new skills

When a recurring Windows task doesn't fit any existing skill, create a new one:

1. Make `C:\DATA\Workspace-37m\claude-local\.claude\skills\<kebab-name>\`
2. Add `SKILL.md` with frontmatter:

   ```markdown
   ---
   name: <kebab-name>
   description: <one line — when this skill applies>
   ---
   ```

3. Body should cover: when to use, key cmdlets/commands, safety notes, common patterns. Aim for 30–80 lines. Practical, not exhaustive.

## Existing skills

- `windows-registry` — safe registry read/write with backup
- `windows-env-vars` — user/machine env vars and PATH editing
- `winget-packages` — install/upgrade/list/pin via winget
- `windows-services` — service inspection and control
- `scheduled-tasks` — Task Scheduler via PowerShell
- `windows-system-settings` — common Win11 tweaks (taskbar, Explorer, dark mode, privacy)
- `dev-environment` — git, SSH, WSL, language toolchains
- `nilesoft-shell` — context-menu customization via Nilesoft Shell (.nss configs, register/unregister, themes)
