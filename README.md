# claude-local

Personal Claude Code workspace for administering Marty's Windows 11 machine — system settings, registry, environment, software, services, scheduled tasks, dev tooling, and Nilesoft Shell customization. Working directory for sysadmin-style asks; not an application.

When Marty opens Claude Code in this directory, `CLAUDE.md` is auto-loaded along with any matching skill in `.claude/skills/`. Conversations pick up the conventions and tool knowledge without re-explaining each session.

## What this is

Three layers:

- **Skills** (`.claude/skills/`) — instruction files that tell Claude how to approach a task domain.
- **Tools** (`tools/`) — executable PowerShell scripts Claude can run directly. Self-describing via header comments; Claude discovers them automatically via the Tool inventory section of `CLAUDE.md`.
- **Commands** (`.claude/commands/`) — slash commands that trigger multi-step workflows (e.g. `/perf`).

What it intentionally does **not** contain:

- No application code, build tooling, or tests.
- No persistent memory — that lives at `~/.claude/projects/<slug>/memory/`, outside this repo.

## Layout

```
claude-local/
├── CLAUDE.md                          # Workspace orientation + tool discovery instructions (auto-loaded)
├── README.md                          # You are here
├── .gitignore                         # Excludes backups/ and logs/
├── .claude/
│   ├── settings.local.json            # Per-project Claude Code permissions
│   ├── commands/                      # Slash commands
│   │   └── perf.md                    # /perf — snapshot + interpret
│   └── skills/                        # Domain skills, auto-discovered by name
│       ├── windows-registry/
│       ├── windows-env-vars/
│       ├── winget-packages/
│       ├── windows-services/
│       ├── scheduled-tasks/
│       ├── windows-system-settings/
│       ├── dev-environment/
│       ├── nilesoft-shell/
│       └── performance-diagnosis/
├── tools/                             # Executable scripts — run from repo root
│   └── diagnostics/
│       ├── perf-snapshot.ps1          # One-shot system snapshot
│       └── perf-watch.ps1             # Continuous threshold monitor
├── staging/                           # Edits ready to copy into protected dirs (elevated)
│   ├── nilesoft/
│   │   ├── shell.nss
│   │   └── imports/
│   └── registry/
├── logs/                              # GIT-IGNORED. Output from -SaveLog runs.
│   └── diagnostics/
└── backups/                           # GIT-IGNORED. Timestamped snapshots before edits.
    ├── nilesoft/
    └── registry/
```

## Skills

| Skill | What it covers |
|---|---|
| [`windows-registry`](.claude/skills/windows-registry/SKILL.md) | Reading/writing the registry safely; `reg export` backup pattern; HKCU vs HKLM scope rules |
| [`windows-env-vars`](.claude/skills/windows-env-vars/SKILL.md) | User vs Machine env vars; PATH split-dedupe-rewrite pattern; `WM_SETTINGCHANGE` broadcast |
| [`winget-packages`](.claude/skills/winget-packages/SKILL.md) | Search/install/upgrade/list/pin/uninstall; export/import for snapshots |
| [`windows-services`](.claude/skills/windows-services/SKILL.md) | `Get-Service` / `Set-Service`; startup type; critical-service warning list |
| [`scheduled-tasks`](.claude/skills/scheduled-tasks/SKILL.md) | `Register-ScheduledTask`; logon vs daily vs startup triggers; SYSTEM vs interactive |
| [`windows-system-settings`](.claude/skills/windows-system-settings/SKILL.md) | Common Win11 tweaks (Explorer, taskbar, dark mode, privacy); restart-Explorer pattern |
| [`dev-environment`](.claude/skills/dev-environment/SKILL.md) | git config, SSH keys, WSL setup, Node/Python/Go/Rust/.NET install; PowerShell `$PROFILE` |
| [`nilesoft-shell`](.claude/skills/nilesoft-shell/SKILL.md) | `.nss` syntax; CLI flags; runtime modifier shortcuts; reload mechanics |
| [`performance-diagnosis`](.claude/skills/performance-diagnosis/SKILL.md) | Diagnose slow/unresponsive machine; interpret snapshot output; known hogs and fixes |

## Tools

Scripts Claude can run directly. All paths are relative — no hardcoded machine paths.

| Script | What it does | Key params |
|---|---|---|
| `tools/diagnostics/perf-snapshot.ps1` | One-shot snapshot: CPU, RAM, disk, pagefile, power plan, top processes, known-hog check | `-Top <n>`, `-SaveLog` |
| `tools/diagnostics/perf-watch.ps1` | Continuous monitor; highlights processes crossing CPU % or RAM MB thresholds | `-IntervalSec`, `-CpuThreshold`, `-RamThresholdMb` |

## Commands

| Command | What it does |
|---|---|
| `/perf` | Run perf-snapshot, interpret output, return top issues + recommended actions |
| `/ship` | Commit any uncommitted work (with doc check) and push to the remote |

## How a session typically works

1. Open Claude Code in this directory (or any IDE pointed at it).
2. Ask in natural language — "why is my machine slow", "remove the AMD entry from the right-click menu", "set up scheduled defrag at 3am".
3. For **HKLM** registry edits, **machine env vars**, **service changes**, or **anything under `Program Files`**: Claude proposes the change, stages files in `staging/<area>/`, takes a backup in `backups/<area>/<timestamp>/`, and gives a one-line elevated PowerShell command for Marty to paste into an admin shell.
4. Reversible local changes (HKCU registry, user env vars, `winget` user-scope, file ops) execute directly.
5. When performance, slowness, or resource issues come up, Claude auto-discovers `tools/diagnostics/` scripts and runs the appropriate one.

## Conventions

- **PowerShell first** for Windows-system operations. Bash for cross-platform/file ops and git.
- **Back up before destructive edits.** Registry: `reg export <key> backups/registry/<ts>/<name>.reg`.
- **HKLM writes need explicit confirmation.** HKCU is per-user and reversible — proceed with care. HKLM is machine-wide — pause and name the key/value before writing.
- **Never disable UAC, Defender, SmartScreen, or Windows Update** without an explicit instruction naming the thing.
- **Don't auto-elevate.** Stage and hand back an elevated command.
- **Note the inverse** of any forward operation.
- **All tool scripts use relative paths via `$PSScriptRoot`.** Never hardcode absolute paths to the repo.

## Adding to the workspace

**New skill:** `.claude/skills/<kebab-name>/SKILL.md` with frontmatter + body. Add a row to the skills table above and to `CLAUDE.md`.

**New tool:** `tools/<category>/<name>.ps1` with the standard header block (`.NAME`, `.SYNOPSIS`, `.CATEGORY`, `.USAGE`, `.WHEN`). Add a row to the tools table above. Claude discovers it automatically next session via `CLAUDE.md`.

**New command:** `.claude/commands/<name>.md` describing the workflow. Add a row to the commands table above.

## Reference

- `everything-claude-code` (at `C:\DATA\Workspace-public\everything-claude-code` if present) — blueprint repo with 300+ skills / 50+ agents / 80+ commands. Consult as a library; don't auto-pull.
- [Nilesoft Shell](https://nilesoft.org) — source of truth for `.nss` syntax used by the `nilesoft-shell` skill.
