# claude-local — Windows 11 management workspace

This directory is Marty's home base for Windows 11 administration tasks. When he asks Claude Code to change a system setting, edit the registry, manage software, tweak the environment, or set up dev tooling, work happens here.

This is not a code project. There's no app to build, no tests to run. Tasks are sysadmin-flavored: *change something on this machine safely*.

## Platform

- Windows 11 Pro, single-user (Marty).
- PowerShell 7+ (`pwsh`) is available — that's the primary tool for Windows-native operations. Use the `PowerShell` tool.
- Bash is also configured (Git for Windows). Use the `Bash` tool for cross-platform/file ops and git work.

**Convention:** prefer PowerShell for anything Windows-system-specific (registry, services, winget, scheduled tasks, env vars, system settings). Use bash for general file ops, scripting that needs to be portable, or git work. Don't shell out to `cmd.exe` unless a tool genuinely requires it.

## Safety conventions

These apply to every session. They are non-negotiable unless Marty explicitly waives one in the conversation.

- **Confirm before destructive system changes.** Stopping critical services, deleting registry keys, uninstalling packages, removing scheduled tasks — pause and confirm.
- **Back up the registry before edits.** Use `reg export <key> <path>.reg` before any `Set-ItemProperty` / `New-Item` / `Remove-Item` against the registry. Save backups to `backups\registry\` (relative to repo root) with a timestamped filename.
- **HKLM requires explicit confirmation.** `HKCU` changes affect only this user and are reversible — proceed with normal care. `HKLM` (machine-wide) changes need a clear "yes go ahead" from Marty before each write.
- **Never disable UAC, Defender, SmartScreen, or Windows Update** without an explicit instruction naming the thing to disable.
- **Prefer reversible changes.** A registry tweak that can be flipped back beats a uninstall that has to be reinstalled. Note the inverse operation when you make a change.
- **Don't auto-elevate.** If something needs admin (`HKLM`, system services, machine env vars), say so and let Marty re-launch the shell elevated rather than chaining `Start-Process -Verb RunAs`.

## Where things live

All paths below are relative to the repo root.

- **Skills** — `.claude/skills/<name>/SKILL.md`. Each skill is one folder with a `SKILL.md` containing YAML frontmatter (`name`, `description`) and a tight body. Loaded automatically by Claude Code.
- **Commands** — `.claude/commands/<name>.md`. Slash commands invokable as `/<name>` in Claude Code. Each file describes what Claude should do when the command runs.
- **Tools** — `tools/<os>/<category>/<name>.ps1` (or `.sh` on Linux/macOS). Executable scripts. All paths inside scripts are relative (via `$PSScriptRoot` / `$(dirname "$0")`). See **Tool inventory** below.
- **Staging** — `staging/<os>/<area>/`. Config file edits that need elevation to copy into place (e.g. Nilesoft `.nss`, `.reg` files on Windows).
- **Backups** — `backups/<os>/<area>/<timestamp>/`. Gitignored. Timestamped snapshots before destructive changes.
- **Logs** — `logs/<os>/<category>/`. Gitignored. Output from tool runs that requested `-SaveLog`.
- **Persistent memory** — `~/.claude/projects/<project-slug>/memory/`. Auto-managed by Claude; lives outside this repo.

## Tool inventory

Tools live under `tools/<os>/<category>/`. At the start of any session where a system, performance, or diagnostic task comes up, list the tools for the current OS only:

```powershell
# Windows:
Get-ChildItem tools\windows -Recurse -Filter *.ps1 | Select-Object -ExpandProperty FullName

# Linux / macOS / WSL (Linux side):
find tools/linux tools/macos tools/unix -name '*.sh' 2>/dev/null
```

Then read the first 15 lines of each result. The `.SYNOPSIS`, `.PLATFORM`, and `.WHEN` header fields tell you what each script does and when to reach for it. Run scripts from the repo root:

```powershell
.\tools\<os>\<category>\<name>.ps1 [params]   # Windows
./tools/<os>/<category>/<name>.sh [params]     # Linux / macOS
```

Every script uses this header format — the `.WHEN` field is the trigger: what Marty says that should make you reach for this tool. Skip scripts whose `.PLATFORM` doesn't match the current OS.

```powershell
<#
.NAME        <name>
.SYNOPSIS    <one line — what it does>
.PLATFORM    windows | linux | macos | unix | all
.CATEGORY    <category folder name>
.USAGE       .\tools\<os>\<category>\<name>.ps1 [params]
.WHEN        <what the user says that should trigger this tool>
#>
```

## Adding new skills

When a recurring Windows task doesn't fit any existing skill, create a new one:

1. Make `.claude/skills/<kebab-name>/SKILL.md` with frontmatter:

   ```markdown
   ---
   name: <kebab-name>
   description: <one line — when this skill applies>
   ---
   ```

2. Body should cover: when to use, key cmdlets/commands, safety notes, common patterns. Aim for 30–80 lines. Practical, not exhaustive.
3. Add a one-line entry to the skills table in README.md.
4. Commit. The skill is then auto-discovered in future sessions.

## Adding new tools

When a recurring task would benefit from a reusable script:

1. Pick the OS subdir (`tools/windows/`, `tools/linux/`, `tools/macos/`, or `tools/unix/` for portable bash) and a category folder under it (e.g. `diagnostics`, `network`, `system`, `startup`).
2. Add `<name>.ps1` (Windows) or `<name>.sh` (Unix) with the standard header block (see Tool inventory above), including the `.PLATFORM` field.
3. Use `$PSScriptRoot` (PS) or `$(cd "$(dirname "$0")" && pwd)` (bash) for all relative path resolution inside the script. Never hardcode absolute paths.
4. If the script produces output worth saving, write to `$repoRoot/logs/<os>/<category>/<timestamp>-<name>.txt` behind a `-SaveLog` switch.
5. Update the tools table in README.md.

## Completing a task

After any task that adds or modifies a tool, skill, command, staging file, or any other repo artifact:

1. **Verify** — smoke-test the change. Don't claim it works without running it.
2. **Update documentation** — if you added a skill, tool, or command, add a row to the relevant table in README.md and a one-line entry in the appropriate list in CLAUDE.md (if it isn't already there). If you modified one, update its description.
3. **Commit** — stage the changed files explicitly by name and commit with a clear message describing what changed and why. Use the `Co-Authored-By` trailer. Do not commit `backups/` or `logs/`.
4. **Push for successful improvements.** When the change is a real improvement to the project (new tool/skill/command, or material enhancement of one) and verification passed, push to origin. The `completing-an-improvement` skill encapsulates the full lifecycle including a "great commit message" guide. For partial work, debugging detours, or ad-hoc fixes that aren't repo improvements, don't auto-push — Marty can run `/ship` when ready.

If a task was purely conversational (no files changed), skip 1–4.

## Existing skills

Each skill's `description` frontmatter starts with a scope tag — `[windows]`, `[linux]`, `[macos]`, `[unix]` (Linux+macOS), or `[all]`. Honor the tag: only use skills whose scope matches the current OS.

**Windows:**
- `windows-registry` — safe registry read/write with backup
- `windows-env-vars` — user/machine env vars and PATH editing
- `winget-packages` — install/upgrade/list/pin via winget
- `windows-services` — service inspection and control
- `windows-scheduled-tasks` — Task Scheduler via PowerShell
- `windows-system-settings` — common Win11 tweaks (taskbar, Explorer, dark mode, privacy)
- `windows-perf-diagnosis` — diagnose slow/unresponsive machine; interpret perf-snapshot output; known hogs
- `windows-startup-management` — audit Run keys, startup folders, logon scheduled tasks, auto-start services; triage what to disable
- `nilesoft-shell` — context-menu customization via Nilesoft Shell (.nss configs, register/unregister, themes)
- `dev-environment` — git, SSH, WSL, language toolchains (currently Windows-biased; planned split into windows/unix variants)

**Cross-platform (`[all]`):**
- `completing-an-improvement` — full ship cycle for a verified repo improvement: docs, commit, push

Linux and macOS skills will be added in subsequent phases.

## Existing commands

- `/perf` — run a performance snapshot and get an interpreted summary with recommended actions (currently Windows; OS dispatch planned)
- `/startup` — audit startup items and recommend what to disable (Windows-only; no equivalent planned for Linux/macOS — startup vectors differ)
- `/ship` — commit any uncommitted work and push to the remote (cross-platform)
