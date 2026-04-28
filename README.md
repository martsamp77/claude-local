# claude-local

Personal Claude Code workspace for administering Marty's Windows 11 machine — system settings, registry, environment, software, services, scheduled tasks, dev tooling, and Nilesoft Shell customization. Working directory for sysadmin-style asks; not an application.

When Marty opens Claude Code in `C:\DATA\Workspace-37m\claude-local`, the [`CLAUDE.md`](./CLAUDE.md) at the root is auto-loaded along with any matching skill in `.claude/skills/`. Conversations pick up the conventions and skill knowledge without re-explaining each session.

## What this is

A small, focused runtime config — **not a library, not a fork of [everything-claude-code](https://github.com/nilesoft/Shell)**. Three things live here:

- **Skills** Claude reads at session start (`.claude/skills/`).
- **Workspace orientation** that pins safety conventions and platform notes (`CLAUDE.md`).
- **Working artifacts** from sysadmin sessions: registry backups, staged config edits, Nilesoft `.nss` candidates ready for elevated copy.

What it intentionally does **not** contain:

- No application code, build tooling, or tests.
- No persistent memory — that lives at `~/.claude/projects/C--DATA-Workspace-37m-claude-local/memory/`, outside this repo.
- No `agents/`, `commands/`, or `hooks/` folders. Each can be added when a real need appears; this workspace prefers minimum-viable structure.

## Layout

```
claude-local/
├── CLAUDE.md                     # Workspace orientation (auto-loaded)
├── README.md                     # You are here
├── .gitignore                    # Excludes backups/
├── .claude/
│   ├── settings.local.json       # Per-project Claude Code permissions
│   └── skills/                   # Domain skills, auto-discovered by name
│       ├── windows-registry/
│       ├── windows-env-vars/
│       ├── winget-packages/
│       ├── windows-services/
│       ├── scheduled-tasks/
│       ├── windows-system-settings/
│       ├── dev-environment/
│       └── nilesoft-shell/
├── staging/                      # Edits ready to copy into protected dirs
│   ├── nilesoft/                 # Mirrors C:\Program Files\Nilesoft Shell\
│   │   ├── shell.nss
│   │   └── imports/
│   │       ├── local-additions.nss
│   │       └── modify.nss
│   └── registry/                 # .reg files for elevated `reg import`
│       └── hide-recommended-section.reg
└── backups/                      # GIT-IGNORED. Timestamped snapshots before edits.
    ├── nilesoft/<yyyyMMdd-HHmmss>/
    └── registry/<yyyyMMdd-HHmmss>/
```

`backups/` is `.gitignore`d — these are point-in-time snapshots of system state, not source-of-truth, and shouldn't pollute git history.

## Skills

Each skill is one folder with a `SKILL.md` (YAML frontmatter `name` + `description`, then a tight body covering: when to use, key cmdlets, safety notes, common patterns).

| Skill | What it covers |
|---|---|
| [`windows-registry`](.claude/skills/windows-registry/SKILL.md) | Reading/writing the registry safely; `reg export` backup pattern; HKCU vs HKLM scope rules; common keys |
| [`windows-env-vars`](.claude/skills/windows-env-vars/SKILL.md) | User vs Machine env vars; PATH split-dedupe-rewrite pattern; `WM_SETTINGCHANGE` broadcast; why `setx` is unsafe |
| [`winget-packages`](.claude/skills/winget-packages/SKILL.md) | Search/install/upgrade/list/pin/uninstall; export/import for snapshots; common package IDs |
| [`windows-services`](.claude/skills/windows-services/SKILL.md) | `Get-Service` / `Set-Service`; startup type via PowerShell vs `sc.exe`; critical-service warning list |
| [`scheduled-tasks`](.claude/skills/scheduled-tasks/SKILL.md) | `Register-ScheduledTask` with Action/Trigger/Principal/Settings; logon vs daily vs startup triggers; SYSTEM vs interactive |
| [`windows-system-settings`](.claude/skills/windows-system-settings/SKILL.md) | Common Win11 tweaks (Explorer, taskbar, dark mode, privacy); restart-Explorer pattern |
| [`dev-environment`](.claude/skills/dev-environment/SKILL.md) | git config, SSH keys + `ssh-agent`, WSL setup, Node/Python/Go/Rust/.NET install; PowerShell `$PROFILE` |
| [`nilesoft-shell`](.claude/skills/nilesoft-shell/SKILL.md) | `.nss` syntax; CLI flags (`-register -treat -restart -silent`); runtime modifier shortcuts (`CTRL+WIN`); reload mechanics |

## How a session typically works

1. `cd C:\DATA\Workspace-37m\claude-local` and start Claude Code (or run from any IDE pointed at this dir).
2. Ask in natural language — "remove the AMD entry from the right-click menu", "set up scheduled defrag at 3am", "add VS Code to PATH machine-wide".
3. For **HKLM** registry edits, **machine env vars**, **service changes**, or **anything under `Program Files`**: Claude proposes the change with the exact key/value/inverse, **stages files in `staging/<area>/`**, takes a backup in `backups/<area>/<timestamp>/`, and gives a one-line elevated PowerShell `Copy-Item ... ; Stop-Process ...` command for Marty to paste into an admin shell.
4. Reversible local changes (HKCU registry, user env vars, `winget` user-scope, file ops) execute directly without elevation.
5. Outcome of the session ends up in three places: changes applied to the system, artifacts in this repo (skills updated, staging files left for re-use), and any cross-session learnings saved to the auto-memory dir at `~/.claude/projects/C--DATA-Workspace-37m-claude-local/memory/`.

## Conventions (durable)

These are codified in `CLAUDE.md` and feedback memories. They apply unless Marty waives one in-conversation.

- **PowerShell first** for Windows-system operations (registry, services, winget, scheduled tasks, env vars). Bash is for cross-platform/file ops and git.
- **Back up before destructive edits.** Registry: `reg export <key> backups/registry/<ts>/<name>.reg`. Nilesoft: copy `shell.nss` + `imports/` to `backups/nilesoft/<ts>/`.
- **HKLM writes need explicit confirmation each time.** HKCU is per-user and reversible — proceed with normal care. HKLM is machine-wide — pause and ask before each write naming the key/value.
- **Never disable UAC, Defender, SmartScreen, or Windows Update** without an explicit instruction naming the thing.
- **Don't auto-elevate.** Stage and hand back an elevated command rather than chaining `Start-Process -Verb RunAs`.
- **Note the inverse** of any forward operation (the registry value to flip back, the `winget` uninstall, the rollback `Copy-Item`).
- **Iterate Nilesoft `.nss` edits in single blocks.** A parse error anywhere kills the whole config silently — ship one `menu(...)` at a time, verify against `shell.log`, then add the next.

## Memory

Persistent memory across sessions lives outside this repo at:

```
C:\Users\marty\.claude\projects\C--DATA-Workspace-37m-claude-local\memory\
```

It's auto-managed by Claude — user/feedback/project/reference entries plus a `MEMORY.md` index. The repo deliberately doesn't shadow this; the memory layer is owned by the harness, not source-controlled.

## Reference

- [`everything-claude-code`](https://github.com/anthropics/everything-claude-code) (mirror at `C:\DATA\Workspace-public\everything-claude-code`) — sprawling blueprint repo with 300+ skills / 50+ agents / 80+ commands. Consult as a library when expanding capabilities; **don't auto-pull**.
- [`Nilesoft Shell`](https://nilesoft.org) (mirror at `C:\DATA\Workspace-public\Shell`) — context-menu replacement docs and example configs; the source-of-truth for `.nss` syntax referenced by the `nilesoft-shell` skill.

## Adding to the workspace

When a recurring task doesn't fit any existing skill:

1. Make `.claude/skills/<kebab-name>/SKILL.md` with frontmatter:

   ```markdown
   ---
   name: <kebab-name>
   description: <one line — when this skill applies>
   ---
   ```

2. Body: when to use, key commands, safety notes, common patterns. Aim for 30–80 lines. Practical, not exhaustive.
3. Add a one-line entry to the skills table above and to `CLAUDE.md`.
4. Commit. The skill is then auto-discovered in future sessions.
